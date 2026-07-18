import test from "node:test";
import assert from "node:assert/strict";
import crypto from "node:crypto";
import { openDb, type Db, type UserRow } from "../src/db.js";
import { GAME, SKILL_TYPES } from "../src/config.js";
import * as gangs from "../src/game/gangs.js";
import * as social from "../src/game/social.js";
import * as svc from "../src/game/svc.js";
import { awardAchievements, grantDailyRankPoints } from "../src/game/achievements.js";
import { effectiveStats } from "../src/game/stats.js";
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

test("Banden: Gründen, Beitreten, Kasse, Ausbau und Boni", (t) => {
  const db = openDb(":memory:");
  t.after(() => db.close());
  const boss = newUser(db, "boss");
  const member = newUser(db, "handlanger");

  assert.equal(gangs.foundGang(db, boss, "Gleis-Gang", "geheim").ok, true);
  assert.equal(fresh(db, boss.id).money, 100_000 - GAME.GANG_FOUND_COST);
  assert.equal(gangs.foundGang(db, boss, "Zweite Bande", "geheim").ok, false);
  assert.equal(gangs.joinGang(db, member, "Gleis-Gang", "falsch").ok, false);
  assert.equal(gangs.joinGang(db, member, "Gleis-Gang", "geheim").ok, true);

  // Kasse: einzahlen (Euro-Eingabe) und Tageslimit bei Auszahlung.
  assert.equal(gangs.depositToGang(db, fresh(db, boss.id), "300").ok, true);
  let gang = gangs.gangOf(db, boss.id)!.gang;
  assert.equal(gang.treasury, 30_000);
  const tooMuch = gangs.payoutFromGang(db, fresh(db, boss.id), member.id, "150");
  assert.equal(tooMuch.ok, false, "über dem Tageslimit von 100 €");
  assert.match(tooMuch.msg, /Tageslimit/);
  const okPayout = gangs.payoutFromGang(db, fresh(db, boss.id), member.id, "50");
  assert.equal(okPayout.ok, true);
  assert.equal(
    gangs.payoutFromGang(db, fresh(db, member.id), boss.id, "10").ok,
    false,
    "einfaches Mitglied darf nicht auszahlen",
  );

  // Ausbau: Waffenkammer aus der Kasse; ATT-Bonus wirkt auf Mitglieder.
  db.prepare("UPDATE gangs SET treasury = ? WHERE id = ?").run(1_000_000, gang.id);
  db.prepare("UPDATE skills SET level = 20 WHERE user_id = ? AND type = 'angriff'").run(member.id);
  const before = effectiveStats(db, member.id).attEff;
  assert.equal(gangs.upgradeBuilding(db, fresh(db, boss.id), "armory").ok, true);
  const after = effectiveStats(db, member.id).attEff;
  assert.equal(after, Math.round(before * 1.05), "+5 % ATT durch Waffenkammer");

  // Bandentraining beschleunigt Weiterbildungen.
  assert.equal(gangs.upgradeBuilding(db, fresh(db, boss.id), "training").ok, true);
  assert.ok(gangs.gangTrainingFactor(db, member.id) < 1);

  // Verlassen: Boss erst nach Übertragung, dann Auflösung durch Letzten.
  assert.equal(gangs.leaveGang(db, fresh(db, boss.id)).ok, false);
  assert.equal(gangs.manageMember(db, fresh(db, boss.id), member.id, "transfer").ok, true);
  assert.equal(gangs.leaveGang(db, fresh(db, boss.id)).ok, true);
  assert.equal(gangs.leaveGang(db, fresh(db, member.id)).ok, true, "Letzter löst auf");
  assert.equal((db.prepare("SELECT COUNT(*) AS n FROM gangs").get() as any).n, 0);
});

test("Nachrichten: senden, ungelesen, blockieren, Limits", (t) => {
  const db = openDb(":memory:");
  t.after(() => db.close());
  const anna = newUser(db, "anna");
  const bernd = newUser(db, "bernd");

  assert.equal(social.sendMessage(db, anna, "bernd", "Na, alter Kanalgeruch?").ok, true);
  assert.equal(social.unreadCount(db, bernd.id), 1);
  const inbox = social.mailbox(db, bernd.id, "eingang");
  assert.equal(inbox.length, 1);
  const msg = social.getMessage(db, bernd.id, inbox[0].id);
  assert.ok(msg?.read_at, "Öffnen markiert als gelesen");
  assert.equal(social.unreadCount(db, bernd.id), 0);

  // Blockieren stoppt weitere Nachrichten.
  assert.equal(social.addRelation(db, bernd, "anna", "block").ok, true);
  const blocked = social.sendMessage(db, anna, "bernd", "Hallo?");
  assert.equal(blocked.ok, false);
  assert.match(blocked.msg, /blockiert/);

  // Archivieren verschiebt aus dem Eingang.
  assert.equal(social.archiveMessage(db, bernd.id, inbox[0].id).ok, true);
  assert.equal(social.mailbox(db, bernd.id, "eingang").length, 0);
  assert.equal(social.mailbox(db, bernd.id, "archiv").length, 1);

  assert.equal(social.sendMessage(db, anna, "anna", "Selbstgespräch").ok, false);
  assert.equal(social.sendMessage(db, anna, "gibtsnicht", "Echo?").ok, false);
});

test("Auszeichnungen: Schwellen und tägliche Rangpunkte", (t) => {
  const db = openDb(":memory:");
  t.after(() => db.close());
  const user = newUser(db, "sammlerin");
  db.prepare("UPDATE users SET bottles_total = 1500 WHERE id = ?").run(user.id);
  awardAchievements(db, user.id);
  const rows = db
    .prepare("SELECT type, tier FROM achievements WHERE user_id = ? ORDER BY tier")
    .all(user.id) as any[];
  assert.deepEqual(
    rows.map((r) => `${r.type}:${r.tier}`),
    ["sammler:1", "sammler:2"],
    "Bronze (100) und Silber (1000) für 1500 Flaschen",
  );

  // Tägliche Rangpunkte: einmal pro Tag, Platz 1 bekommt 64.
  const zweite = newUser(db, "zweite");
  db.prepare("UPDATE users SET points = 100 WHERE id = ?").run(user.id);
  db.prepare("UPDATE users SET points = 50 WHERE id = ?").run(zweite.id);
  grantDailyRankPoints(db);
  grantDailyRankPoints(db); // idempotent am selben Tag
  assert.equal(fresh(db, user.id).rank_points, GAME.DAILY_RANK_POINTS[0]);
  assert.equal(fresh(db, zweite.id).rank_points, GAME.DAILY_RANK_POINTS[1]);
});

test("Urlaubsmodus: schützt beide Richtungen, Kontingent, Abbruch", (t) => {
  const db = openDb(":memory:");
  t.after(() => db.close());
  const urlauber = newUser(db, "urlauber");
  const angreifer = newUser(db, "angreifer");

  assert.equal(svc.startVacation(db, urlauber.id, 99).ok, false, "über dem Kontingent");
  assert.equal(svc.startVacation(db, urlauber.id, 2).ok, true);
  const u = fresh(db, urlauber.id);
  assert.ok(svc.isOnVacation(u));
  assert.equal(svc.vacationDaysLeft(u), GAME.VACATION_DAYS_PER_MONTH - 2);

  assert.match(svc.canAttack(db, angreifer, u).msg, /Urlaub/);
  assert.match(svc.canAttack(db, u, fresh(db, angreifer.id)).msg, /Urlaub/);
  assert.ok(
    !svc.attackableTargets(db, angreifer).some((t2) => t2.id === urlauber.id),
    "Urlauber tauchen nicht in der Zielliste auf",
  );

  assert.equal(svc.endVacation(db, urlauber.id).ok, true);
  assert.ok(!svc.isOnVacation(fresh(db, urlauber.id)));
  assert.equal(
    svc.vacationDaysLeft(fresh(db, urlauber.id)),
    GAME.VACATION_DAYS_PER_MONTH - 2,
    "abgebrochene Tage kommen nicht zurück",
  );
});
