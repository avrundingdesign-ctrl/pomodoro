import test from "node:test";
import assert from "node:assert/strict";
import crypto from "node:crypto";
import { openDb, type Db, type UserRow } from "../src/db.js";
import { GAME, SKILL_TYPES } from "../src/config.js";
import * as gangs from "../src/game/gangs.js";
import * as wars from "../src/game/wars.js";
import * as pets from "../src/game/pets.js";
import * as community from "../src/game/community.js";
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

function makeGang(db: Db, boss: UserRow, name: string): number {
  db.prepare("UPDATE users SET money = money + ? WHERE id = ?").run(
    GAME.GANG_FOUND_COST,
    boss.id,
  );
  const result = gangs.foundGang(db, fresh(db, boss.id), name, "geheim");
  assert.equal(result.ok, true, result.msg);
  return gangs.gangOf(db, boss.id)!.gang.id;
}

test("Bandenkriege: Erklärung, Wertung über Kampfsiege, Punktelimit, Prämie", (t) => {
  const db = openDb(":memory:");
  t.after(() => db.close());
  const bossA = newUser(db, "boss_a");
  const bossB = newUser(db, "boss_b");
  const gangA = makeGang(db, bossA, "Alpha");
  const gangB = makeGang(db, bossB, "Beta");

  // Mitglied darf nicht erklären; Boss schon.
  const soldier = newUser(db, "soldat_a");
  gangs.joinGang(db, soldier, "Alpha", "geheim");
  assert.equal(wars.declareWar(db, fresh(db, soldier.id), "Beta").ok, false);
  assert.equal(wars.declareWar(db, fresh(db, bossA.id), "Beta").ok, true);
  assert.equal(
    wars.declareWar(db, fresh(db, bossA.id), "Beta").ok,
    false,
    "nur ein aktiver Krieg",
  );

  // Kampfsiege zählen: Punktelimit → Krieg endet, Gewinner kassiert Prämie.
  const treasuryBefore = (gangs.gangOf(db, bossA.id)!.gang as any).treasury;
  for (let i = 0; i < GAME.WAR_POINT_LIMIT; i++) {
    wars.recordWarFightWin(db, soldier.id, bossB.id);
  }
  const war = db.prepare("SELECT * FROM gang_wars").get() as any;
  assert.equal(war.status, "finished");
  assert.equal(war.winner_gang_id, gangA);
  assert.equal(war.score_a, GAME.WAR_POINT_LIMIT);
  const gangARow = db.prepare("SELECT * FROM gangs WHERE id = ?").get(gangA) as any;
  assert.equal(gangARow.war_wins, 1);
  assert.equal(gangARow.treasury, treasuryBefore + GAME.WAR_WIN_TREASURY_BONUS);

  // Bündnis verhindert neuen Krieg.
  assert.equal(wars.proposeAlliance(db, fresh(db, bossA.id), "Beta").ok, true);
  assert.equal(
    wars.respondAlliance(
      db,
      fresh(db, bossB.id),
      (db.prepare("SELECT id FROM gang_alliances").get() as any).id,
      true,
    ).ok,
    true,
  );
  const blocked = wars.declareWar(db, fresh(db, bossA.id), "Beta");
  assert.equal(blocked.ok, false);
  assert.match(blocked.msg, /Verbündeten/);
});

test("Bandenkrieg: Zeitlimit beendet den Krieg mit Punktesieger", (t) => {
  const db = openDb(":memory:");
  t.after(() => db.close());
  const bossA = newUser(db, "kriegs_a");
  const bossB = newUser(db, "kriegs_b");
  makeGang(db, bossA, "Gamma");
  const gangB = makeGang(db, bossB, "Delta");
  assert.equal(wars.declareWar(db, fresh(db, bossA.id), "Delta").ok, true);
  wars.recordWarFightWin(db, bossB.id, bossA.id); // Delta führt 0:1
  db.prepare("UPDATE gang_wars SET ends_at = ends_at - 999999999").run();
  wars.finishExpiredWars(db);
  const war = db.prepare("SELECT * FROM gang_wars").get() as any;
  assert.equal(war.status, "finished");
  assert.equal(war.winner_gang_id, gangB);
});

test("Bandenliga: Saisonwechsel befördert Punktesammler", (t) => {
  const db = openDb(":memory:");
  t.after(() => db.close());
  const bossA = newUser(db, "liga_a");
  const bossB = newUser(db, "liga_b");
  const gangA = makeGang(db, bossA, "Aufsteiger");
  const gangB = makeGang(db, bossB, "Schlafmuetzen");

  wars.rolloverLeagueSeason(db); // Saison initialisieren
  db.prepare("UPDATE users SET points = 500 WHERE id = ?").run(bossA.id);
  // Monatswechsel simulieren:
  db.prepare("UPDATE meta SET value = '2020-01' WHERE key = 'league_season'").run();
  wars.rolloverLeagueSeason(db);
  const a = db.prepare("SELECT league, treasury FROM gangs WHERE id = ?").get(gangA) as any;
  const b = db.prepare("SELECT league FROM gangs WHERE id = ?").get(gangB) as any;
  assert.equal(a.league, 1, "Punktesammler steigt aus der Qualifikation auf");
  assert.equal(b.league, 0, "ohne Zuwachs kein Aufstieg");
  assert.ok(a.treasury >= GAME.LEAGUE_REWARDS[0], "Platz 1 kassiert die Prämie");
});

test("Haustierkämpfe: Treuhand, Sieg nach Haltung, Passwort, Rückzug", (t) => {
  const db = openDb(":memory:");
  t.after(() => db.close());
  // Startgeld unter der Basis-Kapazität, damit Gewinne auch ankommen.
  const dompteur = newUser(db, "dompteur", 4_000);
  const gegner = newUser(db, "gegner", 4_000);
  const schwein = db.prepare("SELECT * FROM items WHERE key = 'pet_7'").get() as any; // 5/7
  const taube = db.prepare("SELECT * FROM items WHERE key = 'pet_1'").get() as any; // 0/1
  const give = db.prepare(
    "INSERT INTO inventory (user_id, item_id, is_active, acquired_at, quantity) VALUES (?, ?, 1, 0, 1)",
  );
  give.run(dompteur.id, schwein.id);
  give.run(gegner.id, taube.id);

  // Aufstellen: Einsatz wird hinterlegt.
  assert.equal(
    pets.createChallenge(db, fresh(db, dompteur.id), schwein.id, "5", "offensiv", "").ok,
    true,
  );
  assert.equal(fresh(db, dompteur.id).money, 3_500);

  // Eigene Herausforderung annehmen: verboten.
  const challenge = db.prepare("SELECT * FROM pet_challenges").get() as any;
  assert.equal(
    pets.acceptChallenge(db, fresh(db, dompteur.id), challenge.id, schwein.id, "neutral", "").ok,
    false,
  );

  // Schwaches Tier gegen starkes: Schwein (offensiv, ATT 5) gewinnt praktisch immer.
  const result = pets.acceptChallenge(
    db,
    fresh(db, gegner.id),
    challenge.id,
    taube.id,
    "offensiv",
    "",
  );
  assert.equal(result.ok, true);
  assert.equal(result.outcome, "loss", "Taube offensiv (ATT 0) verliert gegen ATT 5");
  assert.equal(fresh(db, gegner.id).money, 3_500, "Einsatz weg");
  assert.equal(fresh(db, dompteur.id).money, 3_500 + 1_000, "Sieger nimmt den Topf");

  // Passwortgeschützt = gezielter Geldtransfer (Kap. 7.2).
  assert.equal(
    pets.createChallenge(db, fresh(db, dompteur.id), schwein.id, "2", "defensiv", "codewort").ok,
    true,
  );
  const secret = db
    .prepare("SELECT * FROM pet_challenges WHERE status = 'open'")
    .get() as any;
  const wrongPw = pets.acceptChallenge(
    db,
    fresh(db, gegner.id),
    secret.id,
    taube.id,
    "neutral",
    "falsch",
  );
  assert.equal(wrongPw.ok, false);
  assert.match(wrongPw.msg, /Passwort/);

  // Rückzug erstattet den Einsatz.
  const beforeCancel = fresh(db, dompteur.id).money;
  assert.equal(pets.cancelChallenge(db, fresh(db, dompteur.id), secret.id).ok, true);
  assert.equal(fresh(db, dompteur.id).money, beforeCancel + 200);
});

test("Chat & Forum: Nachrichtenfluss, Rubriken, Banden-Trennung", (t) => {
  const db = openDb(":memory:");
  t.after(() => db.close());
  const laberkopf = newUser(db, "laberkopf");

  assert.equal(community.sendChatMessage(db, laberkopf, "Moin Block!").ok, true);
  assert.equal(community.sendChatMessage(db, laberkopf, "").ok, false);
  const sinceZero = community.chatMessages(db, 0);
  assert.equal(sinceZero.length, 1);
  assert.equal(community.chatMessages(db, sinceZero[0].id).length, 0, "seit-Filter");

  const thread = community.createThread(
    db,
    laberkopf,
    null,
    "hilfe",
    "Wie werde ich Kurs-Millionär?",
    "Flaschen horten oder sofort verkaufen?",
  );
  assert.equal(thread.ok, true);
  assert.equal(community.createThread(db, laberkopf, null, "quatschrubrik", "T", "B").ok, false);
  assert.equal(
    community.replyToThread(db, laberkopf, thread.id, "Horten! Der Kurs steigt bestimmt.", null).ok,
    true,
  );
  assert.equal(community.threadPosts(db, thread.id!).length, 2);
  assert.equal(community.threadList(db, null, "hilfe").length, 1);
  assert.equal(community.threadList(db, null, "allgemein").length, 0);

  // Banden-Forum ist getrennt: Antwort mit falschem Kontext scheitert.
  const boss = newUser(db, "forumboss");
  db.prepare("UPDATE users SET money = 100000 WHERE id = ?").run(boss.id);
  assert.equal(gangs.foundGang(db, fresh(db, boss.id), "Forum-Bande", "geheim").ok, true);
  const gangId = gangs.gangOf(db, boss.id)!.gang.id;
  const gangThread = community.createThread(db, boss, gangId, null, "Geheimplan", "Psst.");
  assert.equal(gangThread.ok, true);
  assert.equal(
    community.replyToThread(db, laberkopf, gangThread.id, "Ich lese mit!", null).ok,
    false,
    "Banden-Thread ist für Außenstehende tabu",
  );
});
