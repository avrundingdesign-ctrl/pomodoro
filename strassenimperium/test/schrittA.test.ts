import test from "node:test";
import assert from "node:assert/strict";
import crypto from "node:crypto";
import { openDb, type Db, type UserRow } from "../src/db.js";
import {
  CRIME_MAX_CHANCE,
  CRIMES,
  GAME,
  SKILL_TYPES,
} from "../src/config.js";
import * as svc from "../src/game/svc.js";
import { resolveAllDue } from "../src/game/resolve.js";
import { donationAmountFor } from "../src/game/donation.js";
import { now } from "../src/clock.js";

function newUser(db: Db, name: string, money = 100_000): UserRow {
  const result = db
    .prepare(
      `INSERT INTO users (username, email, password_hash, created_at, money,
                          cleanliness, donation_code)
       VALUES (?, ?, 'x', ?, ?, 50, ?)`,
    )
    .run(name, `${name}@example.com`, now(), money, crypto.randomBytes(8).toString("hex"));
  const id = Number(result.lastInsertRowid);
  for (const type of SKILL_TYPES) {
    db.prepare("INSERT INTO skills (user_id, type, level) VALUES (?, ?, 0)").run(id, type);
  }
  return db.prepare("SELECT * FROM users WHERE id = ?").get(id) as unknown as UserRow;
}

const fresh = (db: Db, id: number): UserRow =>
  db.prepare("SELECT * FROM users WHERE id = ?").get(id) as unknown as UserRow;

function setSkill(db: Db, userId: number, type: string, level: number): void {
  db.prepare("UPDATE skills SET level = ? WHERE user_id = ? AND type = ?").run(
    level,
    userId,
    type,
  );
}

test("Verbrechen: Gates (Geschick + Unterkunft), Chance-Formel, Auflösung", (t) => {
  const db = openDb(":memory:");
  t.after(() => db.close());
  const user = newUser(db, "ganove");

  // Ohne Geschick ist selbst der Automat tabu.
  const denied = svc.startCrime(db, user.id, "automat");
  assert.equal(denied.ok, false);
  assert.match(denied.msg, /Geschicklichkeit/);

  // Kiosk braucht zusätzlich Unterkunft Stufe 2.
  setSkill(db, user.id, "geschick", 10);
  const noHome = svc.startCrime(db, user.id, "kiosk");
  assert.equal(noHome.ok, false);
  assert.match(noHome.msg, /Unterkunft/);

  // Chance-Formel: Basis + 2 %/Überschuss-Stufe, gedeckelt.
  const automat = CRIMES[0];
  assert.equal(svc.crimeChance(automat, automat.minGeschick), automat.baseChance);
  assert.ok(
    svc.crimeChance(automat, automat.minGeschick + 5) >
      svc.crimeChance(automat, automat.minGeschick),
  );
  assert.ok(svc.crimeChance(automat, 999) <= CRIME_MAX_CHANCE);

  // Automat starten und auflösen: Ergebnis ist Beute ODER Strafe.
  const start = svc.startCrime(db, user.id, "automat");
  assert.equal(start.ok, true);
  const before = fresh(db, user.id).money;
  db.prepare("UPDATE actions SET ends_at = ends_at - 10000000").run();
  resolveAllDue(db);
  const action = db
    .prepare("SELECT * FROM actions WHERE type = 'verbrechen'")
    .get() as any;
  assert.ok(action.resolved_at, "Verbrechen muss aufgelöst sein");
  const r = JSON.parse(action.result);
  const after = fresh(db, user.id).money;
  if (r.success) {
    assert.ok(r.loot >= automat.lootMin && r.loot <= automat.lootMax);
    assert.equal(after, Math.min(GAME.BASE_CAPACITY, before + r.kept));
  } else {
    assert.equal(r.fine, Math.min(before, automat.fine));
    assert.equal(after, before - r.fine);
  }

  // Während eines laufenden Verbrechens: kein zweites, kein Sammeln.
  svc.startCrime(db, user.id, "automat");
  assert.equal(svc.startCrime(db, user.id, "automat").ok, false);
  assert.equal(svc.startCollect(db, user.id, 10).ok, false);
});

test("Konzentrieren: verkürzt Restzeit, Cooldown, Skill-Gate", (t) => {
  const db = openDb(":memory:");
  t.after(() => db.close());
  const user = newUser(db, "denker");

  assert.equal(svc.concentrate(db, user.id).ok, false, "ohne Skill kein Schub");

  setSkill(db, user.id, "konzentration", 2);
  assert.match(svc.concentrate(db, user.id).msg, /keine Weiterbildung/);

  assert.equal(svc.startTraining(db, user.id, "angriff").ok, true);
  const before = (
    db.prepare("SELECT ends_at FROM trainings WHERE resolved_at IS NULL").get() as any
  ).ends_at;
  const boost = svc.concentrate(db, user.id);
  assert.equal(boost.ok, true);
  assert.match(boost.msg, /20 %/);
  const after = (
    db.prepare("SELECT ends_at FROM trainings WHERE resolved_at IS NULL").get() as any
  ).ends_at;
  assert.ok(after < before, "Restzeit muss sinken");

  const again = svc.concentrate(db, user.id);
  assert.equal(again.ok, false, "Cooldown muss greifen");
  assert.match(again.msg, /raucht/);
});

test("Straßenmusik: Auszahlung pro 6-Stunden-Periode, offline nachgeholt", (t) => {
  const db = openDb(":memory:");
  t.after(() => db.close());
  const user = newUser(db, "musiker", 5000);
  setSkill(db, user.id, "musik", 1);
  const instr = db.prepare("SELECT * FROM items WHERE key = 'instr_1'").get() as any;
  assert.equal(svc.buyItem(db, user.id, instr.id).ok, true);

  // Frisch aktiviert: noch keine Periode voll.
  assert.equal(svc.collectMusicIncome(db, user.id), null);

  // 13 Stunden zurückdatieren → 2 volle Perioden à 6 Std.
  db.prepare("UPDATE users SET music_collected_at = music_collected_at - ? WHERE id = ?").run(
    13 * 3_600_000,
    user.id,
  );
  const moneyBefore = fresh(db, user.id).money;
  const payout = svc.collectMusicIncome(db, user.id);
  assert.ok(payout);
  assert.equal(payout!.periods, 2);
  assert.equal(payout!.added, 2 * instr.income);
  assert.equal(fresh(db, user.id).money, moneyBefore + 2 * instr.income);

  // Direkt danach: nichts mehr offen (Rest < 1 Periode bleibt stehen).
  assert.equal(svc.collectMusicIncome(db, user.id), null);
});

test("Bettelspot: aktiver Spot erhöht die Spende", (t) => {
  const db = openDb(":memory:");
  t.after(() => db.close());
  const user = newUser(db, "spotbesitzer", 50_000);
  const without = donationAmountFor(db, fresh(db, user.id));
  setSkill(db, user.id, "bildung", 1);
  const spot = db.prepare("SELECT * FROM items WHERE key = 'spot_1'").get() as any;
  assert.equal(svc.buyItem(db, user.id, spot.id).ok, true);
  const withSpot = donationAmountFor(db, fresh(db, user.id));
  assert.ok(withSpot > without, `Spot muss Spenden erhöhen (${without} → ${withSpot})`);
});

test("Skill-Limits: Musik endet bei Stufe 5", (t) => {
  const db = openDb(":memory:");
  t.after(() => db.close());
  const user = newUser(db, "kapellmeister", 10_000_000);
  setSkill(db, user.id, "musik", 5);
  const res = svc.startTraining(db, user.id, "musik");
  assert.equal(res.ok, false);
  assert.match(res.msg, /Maximalstufe 5/);
});
