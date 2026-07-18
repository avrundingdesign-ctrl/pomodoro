import type { ActionRow, Db, TrainingRow, UserRow } from "../db.js";
import { withTx } from "../db.js";
import { now } from "../clock.js";
import { CRIME_MAX_CHANCE, CRIME_SKILL_BONUS, CRIMES, GAME } from "../config.js";
import { collectYield, fightScores, lootAmount } from "./formulas.js";
import { addMoney } from "./money.js";
import { effectiveStats } from "./stats.js";
import { districtOf } from "./districts.js";
import { fightFactor, promilleOf } from "./promille.js";

/**
 * Kern des Idle-Prinzips: Alle fälligen, noch nicht aufgelösten Timer
 * (Weiterbildungen, Sammelaktionen, Kämpfe) werden bei jedem Request
 * serverseitig nachgezogen — chronologisch, damit z. B. eine fertige
 * Geschick-Weiterbildung noch in eine später endende Sammelaktion einfließt.
 *
 * Bewusste MVP-Entscheidung statt Job-Queue (Redis/BullMQ, Kap. 16):
 * bei kleiner Spielerzahl völlig ausreichend; die Auflösung ist idempotent
 * und ausschließlich von Serverzeit + Datenbank abhängig, sodass später
 * ein Worker dieselben Funktionen aufrufen kann.
 */
export function resolveAllDue(db: Db): void {
  const t = now();
  const dueTrainings = db
    .prepare(
      "SELECT * FROM trainings WHERE resolved_at IS NULL AND ends_at <= ?",
    )
    .all(t) as unknown as TrainingRow[];
  const dueActions = db
    .prepare("SELECT * FROM actions WHERE resolved_at IS NULL AND ends_at <= ?")
    .all(t) as unknown as ActionRow[];

  type Due =
    | { kind: "training"; endsAt: number; row: TrainingRow }
    | { kind: "action"; endsAt: number; row: ActionRow };
  const all: Due[] = [
    ...dueTrainings.map((row) => ({ kind: "training" as const, endsAt: row.ends_at, row })),
    ...dueActions.map((row) => ({ kind: "action" as const, endsAt: row.ends_at, row })),
  ].sort((a, b) => a.endsAt - b.endsAt);

  for (const due of all) {
    if (due.kind === "training") resolveTraining(db, due.row);
    else resolveAction(db, due.row);
  }
}

function resolveTraining(db: Db, training: TrainingRow): void {
  withTx(db, () => {
    const claimed = db
      .prepare("UPDATE trainings SET resolved_at = ? WHERE id = ? AND resolved_at IS NULL")
      .run(training.ends_at, training.id);
    if (claimed.changes === 0) return; // bereits von parallelem Request aufgelöst
    db.prepare(
      `UPDATE skills SET level = MAX(level, ?)
       WHERE user_id = ? AND type = ?`,
    ).run(training.target_level, training.user_id, training.skill_type);
    // Punkte für abgeschlossene Weiterbildungen (Kap. 3)
    db.prepare("UPDATE users SET points = points + ? WHERE id = ?").run(
      training.target_level,
      training.user_id,
    );
  });
}

function resolveAction(db: Db, action: ActionRow): void {
  withTx(db, () => {
    const claimed = db
      .prepare("UPDATE actions SET resolved_at = ? WHERE id = ? AND resolved_at IS NULL")
      .run(action.ends_at, action.id);
    if (claimed.changes === 0) return;
    if (action.type === "sammeln") resolveCollect(db, action);
    else if (action.type === "kampf") resolveFight(db, action);
    else if (action.type === "verbrechen") resolveCrime(db, action);
  });
}

function resolveCrime(db: Db, action: ActionRow): void {
  const payload = JSON.parse(action.payload ?? "{}") as { key?: string };
  const crime = CRIMES.find((c) => c.key === payload.key);
  const user = db
    .prepare("SELECT * FROM users WHERE id = ?")
    .get(action.user_id) as unknown as UserRow | undefined;
  if (!crime || !user) {
    db.prepare("UPDATE actions SET result = ? WHERE id = ?").run(
      JSON.stringify({ cancelled: true }),
      action.id,
    );
    return;
  }
  const geschick = effectiveStats(db, user.id).skills.geschick;
  const chance = Math.min(
    CRIME_MAX_CHANCE,
    crime.baseChance + CRIME_SKILL_BONUS * Math.max(0, geschick - crime.minGeschick),
  );
  if (Math.random() < chance) {
    const loot =
      crime.lootMin + Math.floor(Math.random() * (crime.lootMax - crime.lootMin + 1));
    const result = addMoney(db, user.id, loot);
    db.prepare("UPDATE actions SET result = ? WHERE id = ?").run(
      JSON.stringify({ success: true, loot, kept: result.added, lost: result.lost }),
      action.id,
    );
  } else {
    // Erwischt: Strafe wächst mit der Verbrechensgröße (Kap. 5).
    const fine = Math.min(user.money, crime.fine);
    db.prepare("UPDATE users SET money = money - ? WHERE id = ?").run(fine, user.id);
    db.prepare("UPDATE actions SET result = ? WHERE id = ?").run(
      JSON.stringify({ success: false, fine }),
      action.id,
    );
  }
}

function resolveCollect(db: Db, action: ActionRow): void {
  const payload = JSON.parse(action.payload ?? "{}") as { minutes?: number };
  const minutes = payload.minutes ?? 60;
  const user = db
    .prepare("SELECT * FROM users WHERE id = ?")
    .get(action.user_id) as unknown as UserRow | undefined;
  if (!user) return;
  const stats = effectiveStats(db, action.user_id);
  const district = districtOf(db, user);
  const bottles = collectYield(minutes, stats.skills.geschick, district.factor);
  // Wühlen in Containern macht dreckig (Kap. 3: Sauberkeit sinkt beim Sammeln).
  const dirt = Math.max(1, Math.round((minutes / 60) * GAME.CLEANLINESS_LOSS_PER_HOUR));
  db.prepare(
    "UPDATE users SET bottles = bottles + ?, cleanliness = MAX(0, cleanliness - ?) WHERE id = ?",
  ).run(bottles, dirt, action.user_id);
  db.prepare("UPDATE actions SET result = ? WHERE id = ?").run(
    JSON.stringify({ bottles, minutes, dirt }),
    action.id,
  );
}

function resolveFight(db: Db, action: ActionRow): void {
  const attacker = db
    .prepare("SELECT * FROM users WHERE id = ?")
    .get(action.user_id) as unknown as UserRow | undefined;
  const defender = action.target_user_id
    ? (db
        .prepare("SELECT * FROM users WHERE id = ?")
        .get(action.target_user_id) as unknown as UserRow | undefined)
    : undefined;
  if (!attacker || !defender) {
    db.prepare("UPDATE actions SET result = ? WHERE id = ?").run(
      JSON.stringify({ cancelled: true }),
      action.id,
    );
    return;
  }

  const attStats = effectiveStats(db, attacker.id);
  const defStats = effectiveStats(db, defender.id);
  // Promille wirkt auf den eigenen Wurf: nüchtern-aggressiv stark,
  // betrunken unpräzise (Kap. 3/7.1).
  const { attScore, defScore, outcome } = fightScores(
    attStats.attEff,
    defStats.defEff,
    Math.random,
    fightFactor(promilleOf(attacker)),
    fightFactor(promilleOf(defender)),
  );

  const P = GAME.FIGHT_POINTS;
  let moneyLoot = 0;
  let moneyKept = 0;
  let pointsAttacker = 0;
  let pointsDefender = 0;

  if (outcome === "win") {
    moneyLoot = lootAmount(defender.money, attStats.attEff, defStats.defEff);
    db.prepare("UPDATE users SET money = money - ? WHERE id = ?").run(
      moneyLoot,
      defender.id,
    );
    // Beute unterliegt der eigenen Behälter-Kapazität — Überschuss geht verloren.
    moneyKept = addMoney(db, attacker.id, moneyLoot).added;
    pointsAttacker = P.attackerWin;
    pointsDefender = -P.defenderLossPenalty;
  } else if (outcome === "loss") {
    pointsAttacker = -P.attackerLossPenalty;
    pointsDefender = P.defenderWin;
  } else {
    pointsAttacker = P.draw;
    pointsDefender = P.draw;
  }

  // Punkte fallen nie unter 0; gespeichert wird das tatsächlich angewendete
  // Delta, damit das Kampflog nicht mehr Verlust anzeigt als real passiert ist.
  const applyPoints = (userId: number, delta: number): number => {
    const row = db
      .prepare("SELECT points FROM users WHERE id = ?")
      .get(userId) as unknown as { points: number };
    const next = Math.max(0, row.points + delta);
    db.prepare("UPDATE users SET points = ? WHERE id = ?").run(next, userId);
    return next - row.points;
  };
  pointsAttacker = applyPoints(attacker.id, pointsAttacker);
  pointsDefender = applyPoints(defender.id, pointsDefender);

  const fight = db
    .prepare(
      `INSERT INTO fights
        (attacker_id, defender_id, att_score, def_score, outcome,
         money_loot, money_kept, points_attacker, points_defender, occurred_at)
       VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)`,
    )
    .run(
      attacker.id,
      defender.id,
      Math.round(attScore * 100) / 100,
      Math.round(defScore * 100) / 100,
      outcome,
      moneyLoot,
      moneyKept,
      pointsAttacker,
      pointsDefender,
      action.ends_at,
    );
  db.prepare("UPDATE actions SET result = ? WHERE id = ?").run(
    JSON.stringify({ fightId: Number(fight.lastInsertRowid) }),
    action.id,
  );
}
