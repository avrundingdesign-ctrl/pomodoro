import test from "node:test";
import assert from "node:assert/strict";
import type { Server } from "node:http";
import { openDb } from "../src/db.js";
import { createApp } from "../src/app.js";
import { kursToday } from "../src/game/svc.js";
import { GAME } from "../src/config.js";

interface Ctx {
  base: string;
  server: Server;
  db: ReturnType<typeof openDb>;
}

function startServer(): Promise<Ctx> {
  const db = openDb(":memory:");
  const app = createApp(db);
  return new Promise((resolve) => {
    const server = app.listen(0, () => {
      const addr = server.address() as { port: number };
      resolve({ base: `http://127.0.0.1:${addr.port}`, server, db });
    });
  });
}

async function post(
  ctx: Ctx,
  path: string,
  body: Record<string, string>,
  cookie?: string,
): Promise<Response> {
  return fetch(ctx.base + path, {
    method: "POST",
    headers: {
      "content-type": "application/x-www-form-urlencoded",
      ...(cookie ? { cookie } : {}),
    },
    body: new URLSearchParams(body).toString(),
    redirect: "manual",
  });
}

async function get(ctx: Ctx, path: string, cookie?: string): Promise<Response> {
  return fetch(ctx.base + path, {
    headers: cookie ? { cookie } : {},
    redirect: "manual",
  });
}

function cookieFrom(res: Response): string {
  const setCookie = res.headers.getSetCookie()[0];
  assert.ok(setCookie, "Set-Cookie erwartet");
  return setCookie.split(";")[0];
}

async function register(ctx: Ctx, username: string): Promise<string> {
  const res = await post(ctx, "/registrieren", {
    username,
    email: `${username}@example.com`,
    password: "geheim123",
    password2: "geheim123",
  });
  assert.equal(res.status, 302, `Registrierung von ${username} sollte umleiten`);
  assert.equal(res.headers.get("location"), "/uebersicht");
  return cookieFrom(res);
}

async function csrfOf(ctx: Ctx, cookie: string): Promise<string> {
  const res = await get(ctx, "/uebersicht", cookie);
  assert.equal(res.status, 200);
  const html = await res.text();
  const m = html.match(/name="_csrf" value="([0-9a-f]+)"/);
  assert.ok(m, "CSRF-Token im HTML erwartet");
  return m[1];
}

function userRow(ctx: Ctx, username: string): any {
  return ctx.db.prepare("SELECT * FROM users WHERE username = ?").get(username);
}

test("Spielfluss end-to-end: Registrieren → Training → Kampf → Sammeln → Verkaufen → Highscore", async (t) => {
  const ctx = await startServer();
  t.after(() => {
    ctx.server.close();
    ctx.db.close();
  });

  // Ohne Login: Spielseiten leiten zum Login um.
  const anon = await get(ctx, "/uebersicht");
  assert.equal(anon.status, 302);
  assert.equal(anon.headers.get("location"), "/login");

  const cookieA = await register(ctx, "tester_a");
  const cookieB = await register(ctx, "tester_b");
  const csrfA = await csrfOf(ctx, cookieA);

  // Doppelte Registrierung wird abgelehnt.
  const dup = await post(ctx, "/registrieren", {
    username: "tester_a",
    email: "other@example.com",
    password: "geheim123",
    password2: "geheim123",
  });
  assert.equal(dup.status, 400);

  // POST ohne CSRF-Token → 403.
  const noCsrf = await post(ctx, "/weiterbildung/start", { skill: "angriff" }, cookieA);
  assert.equal(noCsrf.status, 403);

  // Weiterbildung starten: Geld wird abgezogen, Training läuft.
  const start = await post(
    ctx,
    "/weiterbildung/start",
    { skill: "angriff", _csrf: csrfA },
    cookieA,
  );
  assert.equal(start.status, 302);
  let a = userRow(ctx, "tester_a");
  assert.equal(a.money, GAME.START_MONEY - GAME.TRAINING_BASE_COST);
  assert.equal(
    (ctx.db.prepare("SELECT COUNT(*) AS n FROM trainings WHERE resolved_at IS NULL").get() as any).n,
    1,
  );

  // Zeit „vergehen lassen": Training fällig machen, nächster Request löst auf.
  ctx.db.prepare("UPDATE trainings SET ends_at = ends_at - 10000000").run();
  await get(ctx, "/uebersicht", cookieA);
  const skill = ctx.db
    .prepare("SELECT level FROM skills WHERE type = 'angriff' AND user_id = ?")
    .get(a.id) as any;
  assert.equal(skill.level, 1, "Training muss den Skill auf Stufe 1 heben");
  a = userRow(ctx, "tester_a");
  assert.equal(a.points, 1, "Abgeschlossene Weiterbildung gibt Punkte");

  // Kampf: A überfällt B, Ergebnis nach Ablauf des Timers.
  const b0 = userRow(ctx, "tester_b");
  const totalBefore = a.money + b0.money;
  const attack = await post(
    ctx,
    "/kampf/angriff",
    { defenderId: String(b0.id), _csrf: csrfA },
    cookieA,
  );
  assert.equal(attack.status, 302);
  // Während des Angriffs ist keine zweite körperliche Aktion möglich.
  const busy = await post(
    ctx,
    "/aktionen/sammeln/start",
    { minutes: "10", _csrf: csrfA },
    cookieA,
  );
  assert.equal(busy.status, 302); // Redirect mit Fehler-Flash
  assert.equal(
    (ctx.db.prepare("SELECT COUNT(*) AS n FROM actions WHERE type = 'sammeln'").get() as any).n,
    0,
    "Sammeln darf während eines Kampfes nicht starten",
  );

  ctx.db.prepare("UPDATE actions SET ends_at = ends_at - 10000000").run();
  await get(ctx, "/uebersicht", cookieA);
  const fight = ctx.db.prepare("SELECT * FROM fights").get() as any;
  assert.ok(fight, "Kampf muss aufgelöst worden sein");
  assert.ok(["win", "loss", "draw"].includes(fight.outcome));
  a = userRow(ctx, "tester_a");
  const b1 = userRow(ctx, "tester_b");
  assert.ok(a.points >= 0 && b1.points >= 0, "Punkte fallen nie unter 0");
  assert.ok(
    a.money + b1.money <= totalBefore,
    "Kampf erzeugt kein Geld aus dem Nichts",
  );
  if (fight.outcome === "win") {
    assert.equal(b0.money - b1.money, fight.money_loot, "Beute stammt vom Verlierer");
  }

  // Cooldown: sofortiger zweiter Angriff auf dasselbe Ziel ist blockiert.
  const again = await post(
    ctx,
    "/kampf/angriff",
    { defenderId: String(b0.id), _csrf: csrfA },
    cookieA,
  );
  assert.equal(again.status, 302);
  assert.equal(
    (ctx.db.prepare("SELECT COUNT(*) AS n FROM actions WHERE type = 'kampf'").get() as any).n,
    1,
    "Cooldown muss den zweiten Angriff verhindern",
  );

  // Sammeln: starten, fällig machen, auflösen, verkaufen.
  const collect = await post(
    ctx,
    "/aktionen/sammeln/start",
    { minutes: "10", _csrf: csrfA },
    cookieA,
  );
  assert.equal(collect.status, 302);
  ctx.db.prepare("UPDATE actions SET ends_at = ends_at - 10000000").run();
  await get(ctx, "/uebersicht", cookieA);
  a = userRow(ctx, "tester_a");
  assert.ok(a.bottles > 0, "Sammeln muss Flaschen bringen");

  const kurs = kursToday(); // inkl. eventuellem Saison-Event-Faktor
  const expected = Math.min(GAME.BASE_CAPACITY, a.money + a.bottles * kurs);
  const sell = await post(ctx, "/inventar/verkaufen", { _csrf: csrfA }, cookieA);
  assert.equal(sell.status, 302);
  const afterSell = userRow(ctx, "tester_a");
  assert.equal(afterSell.bottles, 0);
  assert.equal(afterSell.money, expected, "Verkauf zum Tageskurs, begrenzt durch Kapazität");

  // Behälter kaufen: wird automatisch aktiviert und erhöht die Kapazität.
  ctx.db.prepare("UPDATE users SET money = ? WHERE id = ?").run(5000, a.id);
  const container = ctx.db
    .prepare("SELECT * FROM items WHERE key = 'container_1'")
    .get() as any;
  const buy = await post(
    ctx,
    "/stadt/kaufen",
    { itemId: String(container.id), _csrf: csrfA },
    cookieA,
  );
  assert.equal(buy.status, 302);
  const inv = ctx.db
    .prepare("SELECT * FROM inventory WHERE user_id = ? AND item_id = ?")
    .get(a.id, container.id) as any;
  assert.ok(inv, "Behälter muss im Inventar liegen");
  assert.equal(inv.is_active, 1, "Erster Behälter wird automatisch aktiviert");
  assert.equal(userRow(ctx, "tester_a").money, 5000 - container.price);

  // Highscore listet beide Spieler.
  const hs = await get(ctx, "/highscore", cookieA);
  assert.equal(hs.status, 200);
  const hsHtml = await hs.text();
  assert.ok(hsHtml.includes("tester_a") && hsHtml.includes("tester_b"));

  // Login/Logout-Roundtrip.
  const login = await post(ctx, "/login", {
    identifier: "tester_b",
    password: "geheim123",
  });
  assert.equal(login.status, 302);
  assert.equal(login.headers.get("location"), "/uebersicht");
  const badLogin = await post(ctx, "/login", {
    identifier: "tester_b",
    password: "falsches-passwort",
  });
  assert.equal(badLogin.status, 401);
});
