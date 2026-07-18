import test from "node:test";
import assert from "node:assert/strict";
import crypto from "node:crypto";
import type { Server } from "node:http";
import { openDb, type Db, type UserRow } from "../src/db.js";
import { createApp } from "../src/app.js";
import { GAME, SKILL_TYPES } from "../src/config.js";
import {
  applyPromilleDelta,
  fightFactor,
  promilleOf,
  trainingDurationFactor,
} from "../src/game/promille.js";
import { donationAmountFor, recordDonationClick } from "../src/game/donation.js";
import { listDistricts } from "../src/game/districts.js";
import { collectYield, fightScores } from "../src/game/formulas.js";
import { effectiveStats } from "../src/game/stats.js";
import * as svc from "../src/game/svc.js";
import { now } from "../src/clock.js";

function newUser(db: Db, name: string, money = 100_000): UserRow {
  const result = db
    .prepare(
      `INSERT INTO users (username, email, password_hash, created_at, money,
                          cleanliness, donation_code)
       VALUES (?, ?, 'x', ?, ?, ?, ?)`,
    )
    .run(
      name,
      `${name}@example.com`,
      now(),
      money,
      GAME.CLEANLINESS_START,
      crypto.randomBytes(8).toString("hex"),
    );
  const id = Number(result.lastInsertRowid);
  for (const type of SKILL_TYPES) {
    db.prepare("INSERT INTO skills (user_id, type, level) VALUES (?, ?, 0)").run(id, type);
  }
  return db.prepare("SELECT * FROM users WHERE id = ?").get(id) as unknown as UserRow;
}

const fresh = (db: Db, id: number): UserRow =>
  db.prepare("SELECT * FROM users WHERE id = ?").get(id) as unknown as UserRow;

test("Promille: Aufbau, Abbau über Zeit und Krankenhaus bei 4,0 ‰", (t) => {
  const db = openDb(":memory:");
  t.after(() => db.close());
  const user = newUser(db, "trinker", 10_000);

  assert.equal(promilleOf(user), 0);
  let r = applyPromilleDelta(db, fresh(db, user.id), 1.0);
  assert.equal(r.hospital, false);
  assert.ok(Math.abs(r.promille - 1.0) < 1e-9);

  // Abbau: 2 Stunden zurückdatieren → 2 × 0,15 ‰ weniger.
  // (Toleranz großzügig: der Abbau läuft seit dem Persistieren real weiter.)
  db.prepare("UPDATE users SET alcohol_at = alcohol_at - 7200000 WHERE id = ?").run(user.id);
  const decayed = promilleOf(fresh(db, user.id));
  assert.ok(Math.abs(decayed - (1.0 - 2 * GAME.PROMILLE_DECAY_PER_HOUR)) < 5e-3);

  // Bis zur Lebensgefahr trinken: Krankenhaus kassiert und macht nüchtern.
  applyPromilleDelta(db, fresh(db, user.id), 2.0);
  const before = fresh(db, user.id);
  const hospital = applyPromilleDelta(db, before, 2.0);
  assert.equal(hospital.hospital, true);
  assert.equal(hospital.promille, 0);
  assert.equal(
    hospital.fee,
    Math.floor(before.money * GAME.PROMILLE_HOSPITAL_FEE_FACTOR),
  );
  const after = fresh(db, user.id);
  assert.equal(after.money, before.money - hospital.fee);
  assert.equal(promilleOf(after), 0);
});

test("Laune: Faktoren folgen der Beispielkurve", () => {
  assert.ok(trainingDurationFactor(2.5) < 1, "gute Laune trainiert schneller");
  assert.ok(trainingDurationFactor(0) > 1, "nüchtern-mies trainiert langsamer");
  assert.ok(fightFactor(0) > 1, "nüchtern = aggressiv/kampfstark");
  assert.ok(fightFactor(3.2) < 1, "betrunken = unpräzise");
  assert.ok(fightFactor(0) > fightFactor(2.5));
  // Kampf-Faktoren fließen in die Formel ein:
  let wins = 0;
  for (let i = 0; i < 2000; i++) {
    const o = fightScores(10, 10, Math.random, 1.3, 0.7).outcome;
    if (o === "win") wins++;
  }
  assert.ok(wins > 1500, `Faktor-Vorteil muss sich auszahlen (wins=${wins})`);
});

test("Konsum über Service: kaufen stapelt, konsumieren senkt Bestand und hebt Pegel", (t) => {
  const db = openDb(":memory:");
  t.after(() => db.close());
  const user = newUser(db, "kioskkunde", 10_000);
  const beer = db.prepare("SELECT * FROM items WHERE key = 'drink_1'").get() as any;

  assert.equal(svc.buyItem(db, user.id, beer.id).ok, true);
  assert.equal(svc.buyItem(db, user.id, beer.id).ok, true);
  let inv = db
    .prepare("SELECT * FROM inventory WHERE user_id = ? AND item_id = ?")
    .get(user.id, beer.id) as any;
  assert.equal(inv.quantity, 2);
  assert.equal(inv.is_active, 0, "Konsumgüter werden nie automatisch aktiviert");

  assert.equal(svc.activateItem(db, user.id, inv.id).ok, false, "Bier trägt man nicht");

  const result = svc.consumeItem(db, user.id, inv.id);
  assert.equal(result.ok, true);
  inv = db
    .prepare("SELECT * FROM inventory WHERE user_id = ? AND item_id = ?")
    .get(user.id, beer.id) as any;
  assert.equal(inv.quantity, 1);
  assert.ok(Math.abs(promilleOf(fresh(db, user.id)) - 0.3) < 5e-3);

  // Essen senkt den Pegel wieder.
  const brezel = db.prepare("SELECT * FROM items WHERE key = 'food_1'").get() as any;
  svc.buyItem(db, user.id, brezel.id);
  const brezelInv = db
    .prepare("SELECT id FROM inventory WHERE user_id = ? AND item_id = ?")
    .get(user.id, brezel.id) as any;
  svc.consumeItem(db, user.id, brezelInv.id);
  assert.equal(promilleOf(fresh(db, user.id)), 0);
});

test("Stadtteile: Umzug kostet, Faktor wirkt, gebundene Unterkunft deaktiviert sich", (t) => {
  const db = openDb(":memory:");
  t.after(() => db.close());
  const districts = listDistricts(db);
  assert.equal(districts.length, 12, "12 Viertel geseedet");
  const start = districts[0];
  const tier2 = districts.find((d) => d.tier === 2)!;
  const user = newUser(db, "umzugsprofi", 1_000_000);
  assert.equal(fresh(db, user.id).district_id, start.id);

  // Sammelertrag steigt mit dem Viertel-Faktor.
  assert.ok(collectYield(60, 0, tier2.factor) >= collectYield(60, 0, start.factor));

  // Stadtteilgebundene Unterkunft: im Startviertel nicht kaufbar.
  db.prepare("UPDATE skills SET level = 6 WHERE user_id = ? AND type = 'verteidigung'").run(user.id);
  const bauwagen = db.prepare("SELECT * FROM items WHERE key = 'home_4'").get() as any;
  const denied = svc.buyItem(db, user.id, bauwagen.id);
  assert.equal(denied.ok, false);
  assert.match(denied.msg, /Viertel/);

  // Umzug: Kosten werden abgezogen, dann klappt der Kauf.
  const before = fresh(db, user.id).money;
  const move = svc.moveToDistrict(db, user.id, tier2.id);
  assert.equal(move.ok, true);
  assert.equal(fresh(db, user.id).money, before - tier2.move_cost);
  assert.equal(svc.buyItem(db, user.id, bauwagen.id).ok, true);
  const inv = db
    .prepare("SELECT * FROM inventory WHERE user_id = ? AND item_id = ?")
    .get(user.id, bauwagen.id) as any;
  assert.equal(inv.is_active, 1, "erste Unterkunft wird aktiviert");

  // Zurück ins Startviertel: Bauwagen liegt zu weit weg → deaktiviert.
  const back = svc.moveToDistrict(db, user.id, start.id);
  assert.equal(back.ok, true);
  assert.match(back.msg, /keinen Schutz/);
  const invAfter = db
    .prepare("SELECT is_active FROM inventory WHERE id = ?")
    .get(inv.id) as any;
  assert.equal(invAfter.is_active, 0);

  // Unbezahlbarer Umzug wird abgelehnt.
  db.prepare("UPDATE users SET money = 0 WHERE id = ?").run(user.id);
  const broke = svc.moveToDistrict(db, user.id, tier2.id);
  assert.equal(broke.ok, false);
});

test("Spendenlink: zahlt einmal pro Quelle und Tag, Sauberkeit erhöht den Betrag", (t) => {
  const db = openDb(":memory:");
  t.after(() => db.close());
  const user = newUser(db, "bettelkoenig", 500);

  db.prepare("UPDATE users SET cleanliness = 0 WHERE id = ?").run(user.id);
  const dirty = donationAmountFor(db, fresh(db, user.id));
  db.prepare("UPDATE users SET cleanliness = 100 WHERE id = ?").run(user.id);
  const clean = donationAmountFor(db, fresh(db, user.id));
  assert.ok(clean > dirty, "Sauberkeit muss die Spende erhöhen");

  const first = recordDonationClick(db, fresh(db, user.id), "quelle_a");
  assert.equal(first.paid, true);
  assert.ok(first.amount > 0);
  assert.equal(fresh(db, user.id).money, 500 + first.amount);

  const dup = recordDonationClick(db, fresh(db, user.id), "quelle_a");
  assert.equal(dup.paid, false);
  assert.equal(dup.reason, "duplicate");

  const second = recordDonationClick(db, fresh(db, user.id), "quelle_b");
  assert.equal(second.paid, true);

  // Tagesdeckel.
  const day = new Date(now()).toISOString().slice(0, 10);
  const stmt = db.prepare(
    "INSERT OR IGNORE INTO donation_clicks (user_id, ip_hash, day, amount, created_at) VALUES (?, ?, ?, 1, ?)",
  );
  for (let i = 0; i < GAME.DONATION_DAILY_CAP; i++) {
    stmt.run(user.id, `fake_${i}`, day, now());
  }
  const capped = recordDonationClick(db, fresh(db, user.id), "quelle_c");
  assert.equal(capped.paid, false);
  assert.equal(capped.reason, "daily_cap");
});

test("Sozialkontakte: Stufenlimit greift, Haustier zählt in ATT/DEF", (t) => {
  const db = openDb(":memory:");
  t.after(() => db.close());
  const user = newUser(db, "tierfreund", 1_000_000);
  db.prepare("UPDATE skills SET level = 10 WHERE user_id = ? AND type = 'sozial'").run(user.id);
  const maxed = svc.startTraining(db, user.id, "sozial");
  assert.equal(maxed.ok, false);
  assert.match(maxed.msg, /Maximalstufe/);

  const taube = db.prepare("SELECT * FROM items WHERE key = 'pet_1'").get() as any;
  assert.equal(svc.buyItem(db, user.id, taube.id).ok, true);
  const stats = effectiveStats(db, user.id);
  assert.equal(stats.pet?.name, "Straßentaube");
  assert.equal(stats.defEff, 1, "Taube gibt +1 DEF");
});

test("HTTP: Stadtseiten, Waschhaus und öffentlicher Spendenlink", async (t) => {
  const db = openDb(":memory:");
  const app = createApp(db);
  const server: Server = await new Promise((resolve) => {
    const s = app.listen(0, () => resolve(s));
  });
  const port = (server.address() as { port: number }).port;
  const base = `http://127.0.0.1:${port}`;
  t.after(() => {
    server.close();
    db.close();
  });

  const reg = await fetch(`${base}/registrieren`, {
    method: "POST",
    headers: { "content-type": "application/x-www-form-urlencoded" },
    body: new URLSearchParams({
      username: "stadtkind",
      email: "stadt@example.com",
      password: "geheim123",
      password2: "geheim123",
    }).toString(),
    redirect: "manual",
  });
  const cookie = reg.headers.getSetCookie()[0].split(";")[0];

  for (const path of [
    "/stadt",
    "/stadt/karte",
    "/stadt/supermarkt",
    "/stadt/waschhaus",
    "/stadt/waffenladen",
    "/stadt/immobilien",
    "/stadt/tierhandlung",
    "/stadt/zubehoer",
    "/aktionen/betteln",
  ]) {
    const res = await fetch(base + path, { headers: { cookie } });
    assert.equal(res.status, 200, `${path} sollte 200 liefern`);
  }

  // Waschhaus: Katzenwäsche +20 Punkte.
  const me = db.prepare("SELECT * FROM users WHERE username = 'stadtkind'").get() as any;
  db.prepare("UPDATE users SET cleanliness = 30 WHERE id = ?").run(me.id);
  const dash = await fetch(`${base}/uebersicht`, { headers: { cookie } });
  const csrf = (await dash.text()).match(/name="_csrf" value="([0-9a-f]+)"/)![1];
  await fetch(`${base}/stadt/waschhaus`, {
    method: "POST",
    headers: { "content-type": "application/x-www-form-urlencoded", cookie },
    body: new URLSearchParams({ option: "guenstig", _csrf: csrf }).toString(),
    redirect: "manual",
  });
  assert.equal(
    (db.prepare("SELECT cleanliness FROM users WHERE id = ?").get(me.id) as any).cleanliness,
    50,
  );

  // Öffentlicher Spendenlink: ohne Login, zahlt genau einmal pro Quelle/Tag.
  const moneyBefore = (db.prepare("SELECT money FROM users WHERE id = ?").get(me.id) as any).money;
  const code = (db.prepare("SELECT donation_code FROM users WHERE id = ?").get(me.id) as any)
    .donation_code;
  const click1 = await fetch(`${base}/spende/${code}`);
  assert.equal(click1.status, 200);
  assert.match(await click1.text(), /Münzen in den Becher/);
  const moneyAfter = (db.prepare("SELECT money FROM users WHERE id = ?").get(me.id) as any).money;
  assert.ok(moneyAfter > moneyBefore, "Klick muss auszahlen");
  const click2 = await fetch(`${base}/spende/${code}`);
  assert.match(await click2.text(), /schon/);
  assert.equal(
    (db.prepare("SELECT money FROM users WHERE id = ?").get(me.id) as any).money,
    moneyAfter,
    "zweiter Klick derselben Quelle zahlt nicht",
  );
  const invalid = await fetch(`${base}/spende/gibtsnicht`);
  assert.equal(invalid.status, 404);
});
