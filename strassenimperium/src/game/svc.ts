import type { ActionRow, Db, InventoryRow, ItemRow, UserRow } from "../db.js";
import { withTx } from "../db.js";
import { now } from "../clock.js";
import { GAME, SKILL_INFO, SKILL_TYPES, scaledMs, type SkillType } from "../config.js";
import {
  attackRange,
  kursCentsFor,
  trainingCost,
  trainingDurationMinutes,
} from "./formulas.js";
import { addMoney, capacityFor, clampToCapacity } from "./money.js";
import { skillLevels } from "./stats.js";
import { fmtDuration, fmtMoney } from "../util.js";

export type Res = { ok: true; msg: string } | { ok: false; msg: string };

const ok = (msg: string): Res => ({ ok: true, msg });
const err = (msg: string): Res => ({ ok: false, msg });

export function getUser(db: Db, id: number): UserRow | undefined {
  return db.prepare("SELECT * FROM users WHERE id = ?").get(id) as unknown as
    | UserRow
    | undefined;
}

export function kursToday(): number {
  return kursCentsFor(new Date(now()));
}

/** Laufende „körperliche" Aktion (Sammeln oder Kampf) — max. eine zugleich. */
export function activePhysicalAction(db: Db, userId: number): ActionRow | null {
  const row = db
    .prepare(
      `SELECT * FROM actions
       WHERE user_id = ? AND resolved_at IS NULL AND type IN ('sammeln','kampf')
       ORDER BY ends_at ASC LIMIT 1`,
    )
    .get(userId) as unknown as ActionRow | undefined;
  return row ?? null;
}

export function activeTrainings(db: Db, userId: number) {
  return db
    .prepare(
      `SELECT * FROM trainings
       WHERE user_id = ? AND resolved_at IS NULL ORDER BY ends_at ASC`,
    )
    .all(userId) as unknown as Array<{
    id: number;
    skill_type: string;
    target_level: number;
    ends_at: number;
    started_at: number;
  }>;
}

// ---------------------------------------------------------------- Weiterbildung

export function startTraining(db: Db, userId: number, skillRaw: unknown): Res {
  const skill = String(skillRaw) as SkillType;
  if (!SKILL_TYPES.includes(skill)) return err("Unbekannter Skill.");
  return withTx(db, () => {
    const running = activeTrainings(db, userId);
    if (running.length >= GAME.MAX_PARALLEL_TRAININGS) {
      return err("Beide Trainingsplätze sind schon belegt.");
    }
    if (running.some((t) => t.skill_type === skill)) {
      return err(`${SKILL_INFO[skill].name} wird bereits trainiert.`);
    }
    const level = skillLevels(db, userId)[skill];
    const target = level + 1;
    const cost = trainingCost(target);
    const user = getUser(db, userId)!;
    if (user.money < cost) {
      return err(
        `Zu wenig Geld: Stufe ${target} kostet ${fmtMoney(cost)}, du hast ${fmtMoney(user.money)}.`,
      );
    }
    const durationMs = scaledMs(trainingDurationMinutes(target) * 60_000);
    db.prepare("UPDATE users SET money = money - ? WHERE id = ?").run(cost, userId);
    db.prepare(
      `INSERT INTO trainings (user_id, skill_type, target_level, cost, started_at, ends_at)
       VALUES (?, ?, ?, ?, ?, ?)`,
    ).run(userId, skill, target, cost, now(), now() + durationMs);
    return ok(
      `Weiterbildung „${SKILL_INFO[skill].name}" auf Stufe ${target} gestartet — dauert ${fmtDuration(durationMs)}.`,
    );
  });
}

// -------------------------------------------------------------------- Sammeln

export function startCollect(db: Db, userId: number, minutesRaw: unknown): Res {
  const minutes = Number(minutesRaw);
  if (!(GAME.COLLECT_MINUTES as readonly number[]).includes(minutes)) {
    return err("Ungültige Sammeldauer.");
  }
  return withTx(db, () => {
    const busy = activePhysicalAction(db, userId);
    if (busy) {
      return err(
        busy.type === "sammeln"
          ? "Du bist schon unterwegs und sammelst."
          : "Du bist gerade in einen Kampf verwickelt.",
      );
    }
    const durationMs = scaledMs(minutes * 60_000);
    db.prepare(
      `INSERT INTO actions (user_id, type, payload, started_at, ends_at)
       VALUES (?, 'sammeln', ?, ?, ?)`,
    ).run(userId, JSON.stringify({ minutes }), now(), now() + durationMs);
    return ok(
      `Du ziehst los und sammelst Pfandflaschen — zurück in ${fmtDuration(durationMs)}.`,
    );
  });
}

export function sellBottles(db: Db, userId: number): Res {
  return withTx(db, () => {
    const user = getUser(db, userId)!;
    if (user.bottles <= 0) return err("Du hast keine Pfandflaschen im Beutel.");
    const kurs = kursToday();
    const proceeds = user.bottles * kurs;
    const result = addMoney(db, userId, proceeds);
    db.prepare("UPDATE users SET bottles = 0 WHERE id = ?").run(userId);
    let msg = `${user.bottles} Flaschen zum Tageskurs von ${kurs} Cent verkauft: +${fmtMoney(result.added)}.`;
    if (result.lost > 0) {
      msg += ` ${fmtMoney(result.lost)} passten nicht mehr in deinen Behälter und sind futsch! Kauf dir was Größeres.`;
    }
    return ok(msg);
  });
}

// ---------------------------------------------------------------------- Kampf

export function attackCooldownUntil(
  db: Db,
  attackerId: number,
  defenderId: number,
): number | null {
  const row = db
    .prepare(
      `SELECT MAX(occurred_at) AS last FROM fights
       WHERE attacker_id = ? AND defender_id = ?`,
    )
    .get(attackerId, defenderId) as unknown as { last: number | null };
  if (!row.last) return null;
  const until = row.last + scaledMs(GAME.FIGHT_COOLDOWN_HOURS * 3_600_000);
  return until > now() ? until : null;
}

export function canAttack(
  db: Db,
  attacker: UserRow,
  defender: UserRow,
): Res {
  if (attacker.id === defender.id) {
    return err("Du kannst dich nicht selbst überfallen.");
  }
  const range = attackRange(attacker.points);
  if (defender.points < range.min || defender.points > range.max) {
    return err(
      `${defender.username} liegt außerhalb deiner Punkte-Spanne (${range.min}–${range.max}).`,
    );
  }
  const cooldown = attackCooldownUntil(db, attacker.id, defender.id);
  if (cooldown) {
    return err(`${defender.username} ist noch auf der Hut — erneuter Angriff erst später möglich.`);
  }
  return ok("");
}

export function startAttack(db: Db, attackerId: number, defenderIdRaw: unknown): Res {
  const defenderId = Number(defenderIdRaw);
  if (!Number.isInteger(defenderId)) return err("Ungültiges Ziel.");
  return withTx(db, () => {
    const attacker = getUser(db, attackerId)!;
    const defender = getUser(db, defenderId);
    if (!defender) return err("Diesen Spieler gibt es nicht.");
    const busy = activePhysicalAction(db, attackerId);
    if (busy) {
      return err(
        busy.type === "sammeln"
          ? "Du bist gerade unterwegs und sammelst — erst zurückkommen, dann prügeln."
          : "Du bist bereits in einen Kampf verwickelt.",
      );
    }
    const check = canAttack(db, attacker, defender);
    if (!check.ok) return check;
    const durationMs = scaledMs(GAME.FIGHT_DURATION_MINUTES * 60_000);
    db.prepare(
      `INSERT INTO actions (user_id, type, target_user_id, started_at, ends_at)
       VALUES (?, 'kampf', ?, ?, ?)`,
    ).run(attackerId, defenderId, now(), now() + durationMs);
    return ok(
      `Du machst dich auf den Weg zu ${defender.username} — Ergebnis in ${fmtDuration(durationMs)}.`,
    );
  });
}

// -------------------------------------------------------------------- Inventar

export function getItem(db: Db, itemId: number): ItemRow | undefined {
  return db.prepare("SELECT * FROM items WHERE id = ?").get(itemId) as unknown as
    | ItemRow
    | undefined;
}

export function buyItem(db: Db, userId: number, itemIdRaw: unknown): Res {
  const itemId = Number(itemIdRaw);
  if (!Number.isInteger(itemId)) return err("Ungültiger Gegenstand.");
  return withTx(db, () => {
    const item = getItem(db, itemId);
    if (!item) return err("Diesen Gegenstand gibt es nicht.");
    const owned = db
      .prepare("SELECT id FROM inventory WHERE user_id = ? AND item_id = ?")
      .get(userId, itemId);
    if (owned) return err(`„${item.name}" besitzt du schon.`);
    if (item.unlock_skill) {
      const levels = skillLevels(db, userId);
      const have = levels[item.unlock_skill as SkillType] ?? 0;
      if (have < (item.unlock_level ?? 0)) {
        const skillName = SKILL_INFO[item.unlock_skill as SkillType]?.name ?? item.unlock_skill;
        return err(
          `„${item.name}" erfordert ${skillName} Stufe ${item.unlock_level}.`,
        );
      }
    }
    const user = getUser(db, userId)!;
    if (user.money < item.price) {
      return err(
        `Zu wenig Geld: „${item.name}" kostet ${fmtMoney(item.price)}.`,
      );
    }
    db.prepare("UPDATE users SET money = money - ? WHERE id = ?").run(
      item.price,
      userId,
    );
    const hasActiveSameCategory = db
      .prepare(
        `SELECT inventory.id FROM inventory
         JOIN items ON items.id = inventory.item_id
         WHERE inventory.user_id = ? AND inventory.is_active = 1 AND items.category = ?`,
      )
      .get(userId, item.category);
    db.prepare(
      `INSERT INTO inventory (user_id, item_id, is_active, acquired_at)
       VALUES (?, ?, ?, ?)`,
    ).run(userId, itemId, hasActiveSameCategory ? 0 : 1, now());
    return ok(
      `„${item.name}" gekauft${hasActiveSameCategory ? " (liegt im Inventar — noch aktivieren!)" : " und direkt angelegt"}.`,
    );
  });
}

function getInventoryEntry(
  db: Db,
  userId: number,
  invId: number,
): (InventoryRow & ItemRow) | undefined {
  return db
    .prepare(
      `SELECT inventory.id, inventory.user_id, inventory.item_id, inventory.is_active,
              inventory.acquired_at, items.*
       FROM inventory JOIN items ON items.id = inventory.item_id
       WHERE inventory.id = ? AND inventory.user_id = ?`,
    )
    .get(invId, userId) as unknown as (InventoryRow & ItemRow) | undefined;
}

export function activateItem(db: Db, userId: number, invIdRaw: unknown): Res {
  const invId = Number(invIdRaw);
  if (!Number.isInteger(invId)) return err("Ungültiger Gegenstand.");
  return withTx(db, () => {
    const entry = getInventoryEntry(db, userId, invId);
    if (!entry) return err("Dieser Gegenstand liegt nicht in deinem Inventar.");
    if (entry.is_active) return err(`„${entry.name}" ist schon aktiv.`);
    db.prepare(
      `UPDATE inventory SET is_active = 0
       WHERE user_id = ? AND item_id IN (SELECT id FROM items WHERE category = ?)`,
    ).run(userId, entry.category);
    db.prepare("UPDATE inventory SET is_active = 1 WHERE id = ?").run(invId);
    let msg = `„${entry.name}" aktiviert.`;
    if (entry.category === "container") {
      const lost = clampToCapacity(db, userId);
      if (lost > 0) {
        msg += ` Der kleinere Behälter fasste dein Geld nicht — ${fmtMoney(lost)} sind herausgefallen!`;
      }
    }
    return ok(msg);
  });
}

export function sellInventoryItem(db: Db, userId: number, invIdRaw: unknown): Res {
  const invId = Number(invIdRaw);
  if (!Number.isInteger(invId)) return err("Ungültiger Gegenstand.");
  return withTx(db, () => {
    const entry = getInventoryEntry(db, userId, invId);
    if (!entry) return err("Dieser Gegenstand liegt nicht in deinem Inventar.");
    const resale = Math.floor(entry.price * GAME.ITEM_RESALE_FACTOR);
    db.prepare("DELETE FROM inventory WHERE id = ?").run(invId);
    let lostByCapacity = 0;
    if (entry.category === "container" && entry.is_active) {
      // Erst fällt die Kapazität weg, dann kommt der Erlös dazu.
      lostByCapacity = clampToCapacity(db, userId);
    }
    const result = addMoney(db, userId, resale);
    let msg = `„${entry.name}" für ${fmtMoney(result.added)} verkauft.`;
    if (lostByCapacity > 0 || result.lost > 0) {
      msg += ` Dabei gingen ${fmtMoney(lostByCapacity + result.lost)} verloren, weil dein Behälter zu klein ist!`;
    }
    return ok(msg);
  });
}

// ----------------------------------------------------------------- Kampf-Infos

export interface TargetView {
  id: number;
  username: string;
  points: number;
  cooldownUntil: number | null;
}

export function attackableTargets(db: Db, me: UserRow, limit = 20): TargetView[] {
  const range = attackRange(me.points);
  const rows = db
    .prepare(
      `SELECT id, username, points FROM users
       WHERE id != ? AND points BETWEEN ? AND ?
       ORDER BY ABS(points - ?) ASC, id ASC LIMIT ?`,
    )
    .all(me.id, range.min, range.max, me.points, limit) as unknown as Array<{
    id: number;
    username: string;
    points: number;
  }>;
  return rows.map((r) => ({
    ...r,
    cooldownUntil: attackCooldownUntil(db, me.id, r.id),
  }));
}

export interface IncomingAttack {
  attackerName: string;
  endsAt: number;
}

/** Ab Geschick-Stufe 20 sichtbar (Kap. 3/7.1): wer ist auf dem Weg zu mir? */
export function incomingAttacks(db: Db, userId: number): IncomingAttack[] {
  return db
    .prepare(
      `SELECT users.username AS attackerName, actions.ends_at AS endsAt
       FROM actions JOIN users ON users.id = actions.user_id
       WHERE actions.type = 'kampf' AND actions.resolved_at IS NULL
         AND actions.target_user_id = ?
       ORDER BY actions.ends_at ASC`,
    )
    .all(userId) as unknown as IncomingAttack[];
}
