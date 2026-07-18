import type { ActionRow, Db, InventoryRow, ItemRow, UserRow } from "../db.js";
import { CONSUMABLE_CATEGORIES, withTx } from "../db.js";
import { now } from "../clock.js";
import {
  CRIME_MAX_CHANCE,
  CRIME_SKILL_BONUS,
  CRIMES,
  GAME,
  SKILL_INFO,
  SKILL_TYPES,
  TIME_SCALE,
  scaledMs,
  type CrimeDef,
  type SkillType,
} from "../config.js";
import {
  attackRange,
  kursCentsFor,
  trainingCost,
  trainingDurationMinutes,
} from "./formulas.js";
import { addMoney, capacityFor, clampToCapacity } from "./money.js";
import { effectiveStats, skillLevels } from "./stats.js";
import { districtOf, getDistrict } from "./districts.js";
import { gangIncomeFactor, gangTrainingFactor } from "./gangs.js";
import {
  applyPromilleDelta,
  fmtPromille,
  moodLabel,
  promilleOf,
  trainingDurationFactor,
} from "./promille.js";
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

/** Laufende „körperliche" Aktion (Sammeln, Kampf oder Verbrechen) — max. eine zugleich. */
export function activePhysicalAction(db: Db, userId: number): ActionRow | null {
  const row = db
    .prepare(
      `SELECT * FROM actions
       WHERE user_id = ? AND resolved_at IS NULL
         AND type IN ('sammeln','kampf','verbrechen')
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
    const maxLevel = GAME.SKILL_MAX_LEVEL[skill];
    if (maxLevel !== undefined && target > maxLevel) {
      return err(`${SKILL_INFO[skill].name} ist bereits auf der Maximalstufe ${maxLevel}.`);
    }
    const cost = trainingCost(target);
    const user = getUser(db, userId)!;
    if (user.money < cost) {
      return err(
        `Zu wenig Geld: Stufe ${target} kostet ${fmtMoney(cost)}, du hast ${fmtMoney(user.money)}.`,
      );
    }
    // Skill-Zeile sicherstellen (Alt-Accounts kennen neue Skills noch nicht).
    db.prepare(
      "INSERT OR IGNORE INTO skills (user_id, type, level) VALUES (?, ?, 0)",
    ).run(userId, skill);
    // Laune (Kap. 3) und Bandentraining (Kap. 11) beeinflussen die Dauer.
    const moodFactor = trainingDurationFactor(promilleOf(user));
    const gangFactor = gangTrainingFactor(db, userId);
    const durationMs = scaledMs(
      Math.round(trainingDurationMinutes(target) * moodFactor * gangFactor) * 60_000,
    );
    db.prepare("UPDATE users SET money = money - ? WHERE id = ?").run(cost, userId);
    db.prepare(
      `INSERT INTO trainings (user_id, skill_type, target_level, cost, started_at, ends_at)
       VALUES (?, ?, ?, ?, ?, ?)`,
    ).run(userId, skill, target, cost, now(), now() + durationMs);
    const moodNote =
      moodFactor < 1 ? " Deine gute Laune beschleunigt das Training!" : "";
    return ok(
      `Weiterbildung „${SKILL_INFO[skill].name}" auf Stufe ${target} gestartet — dauert ${fmtDuration(durationMs)}.${moodNote}`,
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
          : busy.type === "verbrechen"
            ? "Du drehst gerade ein anderes Ding."
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
    // Bandenkonto-Bonus auf Einnahmen (Kap. 11).
    const proceeds = Math.round(user.bottles * kurs * gangIncomeFactor(db, userId));
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
  // Urlaubsmodus (Kap. 14): weder angreifen noch angegriffen werden.
  if (isOnVacation(attacker)) {
    return err("Du bist im Urlaub — keine Überfälle, Erholung ist Erholung.");
  }
  if (isOnVacation(defender)) {
    return err(`${defender.username} ist im Urlaub und damit geschützt.`);
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
          : busy.type === "verbrechen"
            ? "Du drehst gerade ein Ding — erst die Finger frei kriegen."
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

function isConsumable(item: ItemRow): boolean {
  return (CONSUMABLE_CATEGORIES as readonly string[]).includes(item.category);
}

export function buyItem(db: Db, userId: number, itemIdRaw: unknown): Res {
  const itemId = Number(itemIdRaw);
  if (!Number.isInteger(itemId)) return err("Ungültiger Gegenstand.");
  return withTx(db, () => {
    const item = getItem(db, itemId);
    if (!item) return err("Diesen Gegenstand gibt es nicht.");
    const user = getUser(db, userId)!;
    const existing = db
      .prepare("SELECT id, quantity FROM inventory WHERE user_id = ? AND item_id = ?")
      .get(userId, itemId) as unknown as { id: number; quantity: number } | undefined;
    if (existing && !isConsumable(item)) {
      return err(`„${item.name}" besitzt du schon.`);
    }
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
    if (item.min_district_tier) {
      const district = districtOf(db, user);
      if (district.tier < item.min_district_tier) {
        return err(
          `„${item.name}" gibt es nur in besseren Vierteln (ab Viertel-Stufe ${item.min_district_tier}) — zieh erst um.`,
        );
      }
    }
    if (user.money < item.price) {
      return err(
        `Zu wenig Geld: „${item.name}" kostet ${fmtMoney(item.price)}.`,
      );
    }
    db.prepare("UPDATE users SET money = money - ? WHERE id = ?").run(
      item.price,
      userId,
    );
    if (existing) {
      db.prepare("UPDATE inventory SET quantity = quantity + 1 WHERE id = ?").run(
        existing.id,
      );
      return ok(`„${item.name}" gekauft (jetzt ${existing.quantity + 1}× im Inventar).`);
    }
    if (isConsumable(item)) {
      db.prepare(
        `INSERT INTO inventory (user_id, item_id, is_active, acquired_at, quantity)
         VALUES (?, ?, 0, ?, 1)`,
      ).run(userId, itemId, now());
      return ok(`„${item.name}" gekauft — liegt im Inventar (konsumieren nicht vergessen).`);
    }
    const hasActiveSameCategory = db
      .prepare(
        `SELECT inventory.id FROM inventory
         JOIN items ON items.id = inventory.item_id
         WHERE inventory.user_id = ? AND inventory.is_active = 1 AND items.category = ?`,
      )
      .get(userId, item.category);
    db.prepare(
      `INSERT INTO inventory (user_id, item_id, is_active, acquired_at, quantity)
       VALUES (?, ?, ?, ?, 1)`,
    ).run(userId, itemId, hasActiveSameCategory ? 0 : 1, now());
    if (!hasActiveSameCategory && item.category === "instrument") {
      // Auto-Aktivierung beim Kauf: Straßenmusik-Uhr sofort starten.
      db.prepare("UPDATE users SET music_collected_at = ? WHERE id = ?").run(
        now(),
        userId,
      );
    }
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
              inventory.acquired_at, inventory.quantity, items.*
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
    if (isConsumable(entry)) {
      return err(`„${entry.name}" trägt man nicht — das konsumiert man.`);
    }
    if (entry.is_active) return err(`„${entry.name}" ist schon aktiv.`);
    db.prepare(
      `UPDATE inventory SET is_active = 0
       WHERE user_id = ? AND item_id IN (SELECT id FROM items WHERE category = ?)`,
    ).run(userId, entry.category);
    db.prepare("UPDATE inventory SET is_active = 1 WHERE id = ?").run(invId);
    if (entry.category === "instrument") {
      // Die Straßenmusik-Uhr startet mit der Aktivierung.
      db.prepare("UPDATE users SET music_collected_at = ? WHERE id = ?").run(
        now(),
        userId,
      );
    }
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
    if (entry.quantity > 1) {
      db.prepare("UPDATE inventory SET quantity = quantity - 1 WHERE id = ?").run(invId);
    } else {
      db.prepare("DELETE FROM inventory WHERE id = ?").run(invId);
    }
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

// ------------------------------------------------ Phase 3: Urlaubsmodus (Kap. 14)

export function isOnVacation(user: Pick<UserRow, "vacation_until">): boolean {
  return user.vacation_until > now();
}

function currentMonthKey(): string {
  return new Date(now()).toISOString().slice(0, 7);
}

export function vacationDaysLeft(user: UserRow): number {
  if (user.vacation_month !== currentMonthKey()) return GAME.VACATION_DAYS_PER_MONTH;
  return Math.max(0, GAME.VACATION_DAYS_PER_MONTH - user.vacation_days_used);
}

export function startVacation(db: Db, userId: number, daysRaw: unknown): Res {
  const days = Number(daysRaw);
  if (!Number.isInteger(days) || days < 1) return err("Ungültige Tagesanzahl.");
  return withTx(db, () => {
    const user = getUser(db, userId)!;
    if (isOnVacation(user)) return err("Du bist doch schon im Urlaub.");
    const left = vacationDaysLeft(user);
    if (days > left) {
      return err(`Diesen Monat hast du nur noch ${left} Urlaubstag${left === 1 ? "" : "e"}.`);
    }
    if (activePhysicalAction(db, userId)) {
      return err("Erst die laufende Aktion beenden, dann ab in die Hängematte.");
    }
    const month = currentMonthKey();
    const used = user.vacation_month === month ? user.vacation_days_used : 0;
    db.prepare(
      `UPDATE users SET vacation_until = ?, vacation_month = ?, vacation_days_used = ?
       WHERE id = ?`,
    ).run(now() + scaledMs(days * 24 * 3_600_000), month, used + days, userId);
    return ok(
      `Ab in den Urlaub: ${days} Tag${days === 1 ? "" : "e"} unangreifbar — aber auch ohne Überfälle und mit halbem Nebeneinkommen.`,
    );
  });
}

export function endVacation(db: Db, userId: number): Res {
  return withTx(db, () => {
    const user = getUser(db, userId)!;
    if (!isOnVacation(user)) return err("Du bist gar nicht im Urlaub.");
    db.prepare("UPDATE users SET vacation_until = ? WHERE id = ?").run(now(), userId);
    return ok("Zurück auf der Straße — verbrauchte Urlaubstage gibt es nicht zurück.");
  });
}

// ------------------------------------------------------ Schritt A: Verbrechen

export function crimeByKey(key: unknown): CrimeDef | undefined {
  return CRIMES.find((c) => c.key === String(key));
}

/** Erfolgschance eines Verbrechens für einen Geschick-Wert (Kap. 5). */
export function crimeChance(crime: CrimeDef, geschick: number): number {
  return Math.min(
    CRIME_MAX_CHANCE,
    crime.baseChance + CRIME_SKILL_BONUS * Math.max(0, geschick - crime.minGeschick),
  );
}

export function crimeRequirementCheck(
  db: Db,
  userId: number,
  crime: CrimeDef,
): Res {
  const stats = effectiveStats(db, userId);
  if (stats.skills.geschick < crime.minGeschick) {
    return err(`Dafür brauchst du Geschicklichkeit ${crime.minGeschick}.`);
  }
  if (crime.minHomeTier > 0 && (stats.home?.tier ?? 0) < crime.minHomeTier) {
    return err(
      `Für diesen Coup brauchst du eine Unterkunft ab Stufe ${crime.minHomeTier} — Hehler verhandeln nur mit Leuten mit fester Adresse.`,
    );
  }
  return ok("");
}

export function startCrime(db: Db, userId: number, keyRaw: unknown): Res {
  const crime = crimeByKey(keyRaw);
  if (!crime) return err("Dieses Verbrechen kennt hier niemand.");
  return withTx(db, () => {
    const busy = activePhysicalAction(db, userId);
    if (busy) return err("Du bist gerade anderweitig unterwegs.");
    const check = crimeRequirementCheck(db, userId, crime);
    if (!check.ok) return check;
    const durationMs = scaledMs(crime.minutes * 60_000);
    db.prepare(
      `INSERT INTO actions (user_id, type, payload, started_at, ends_at)
       VALUES (?, 'verbrechen', ?, ?, ?)`,
    ).run(userId, JSON.stringify({ key: crime.key }), now(), now() + durationMs);
    return ok(
      `Du ziehst los: „${crime.name}“ — Ergebnis in ${fmtDuration(durationMs)}. Halt die Ohren steif.`,
    );
  });
}

// --------------------------------------------------- Schritt A: Konzentrieren

export function concentrate(db: Db, userId: number): Res {
  return withTx(db, () => {
    const level = skillLevels(db, userId).konzentration;
    if (level < 1) {
      return err("Dafür brauchst du die Weiterbildung „Konzentration“ (Stufe 1).");
    }
    const user = getUser(db, userId)!;
    const cooldownMs = scaledMs(GAME.KONZ_COOLDOWN_HOURS * 3_600_000);
    const readyAt = user.last_concentrated_at + cooldownMs;
    if (readyAt > now()) {
      return err("Dein Kopf raucht noch — Konzentrieren geht erst wieder später.");
    }
    if (level < GAME.KONZ_COMBINABLE_AT && activePhysicalAction(db, userId)) {
      return err(
        `Unterwegs kannst du dich noch nicht konzentrieren — das klappt erst ab Konzentration ${GAME.KONZ_COMBINABLE_AT}.`,
      );
    }
    const running = db
      .prepare(
        "SELECT id, ends_at FROM trainings WHERE user_id = ? AND resolved_at IS NULL AND ends_at > ?",
      )
      .all(userId, now()) as unknown as Array<{ id: number; ends_at: number }>;
    if (running.length === 0) {
      return err("Es läuft gerade keine Weiterbildung, die du beschleunigen könntest.");
    }
    const factor = GAME.KONZ_BOOST_PER_LEVEL * level;
    for (const t of running) {
      const remaining = t.ends_at - now();
      db.prepare("UPDATE trainings SET ends_at = ends_at - ? WHERE id = ?").run(
        Math.floor(remaining * factor),
        t.id,
      );
    }
    db.prepare("UPDATE users SET last_concentrated_at = ? WHERE id = ?").run(
      now(),
      userId,
    );
    return ok(
      `Tief durchgeatmet und konzentriert: ${running.length} Weiterbildung${running.length > 1 ? "en" : ""} um ${Math.round(factor * 100)} % verkürzt.`,
    );
  });
}

// -------------------------------------------------- Schritt A: Straßenmusik

/**
 * Passives Instrument-Einkommen (Kap. 6): alle 6 Stunden ein „Auftritt".
 * Lazy beim Seitenaufruf des Besitzers abgerechnet — auch offline
 * angesammelte Perioden werden nachgezahlt.
 */
export function collectMusicIncome(
  db: Db,
  userId: number,
): { periods: number; added: number; lost: number } | null {
  return withTx(db, () => {
    const user = getUser(db, userId)!;
    const stats = effectiveStats(db, userId);
    if (!stats.instrument || stats.instrument.income <= 0) return null;
    const periodRealMs = Math.max(
      1000,
      Math.round((GAME.MUSIC_PAYOUT_HOURS * 3_600_000) / TIME_SCALE),
    );
    if (user.music_collected_at <= 0) {
      db.prepare("UPDATE users SET music_collected_at = ? WHERE id = ?").run(
        now(),
        userId,
      );
      return null;
    }
    const periods = Math.floor((now() - user.music_collected_at) / periodRealMs);
    if (periods < 1) return null;
    // Bandenkonto erhöht, Urlaub halbiert das passive Einkommen (Kap. 11/14).
    let gross = Math.round(
      periods * stats.instrument.income * gangIncomeFactor(db, userId),
    );
    if (isOnVacation(user)) {
      gross = Math.round(gross * GAME.VACATION_INCOME_FACTOR);
    }
    const result = addMoney(db, userId, gross);
    db.prepare("UPDATE users SET music_collected_at = music_collected_at + ? WHERE id = ?").run(
      periods * periodRealMs,
      userId,
    );
    return { periods, added: result.added, lost: result.lost };
  });
}

// -------------------------------------------------- Phase 2: Konsum & Stadtleben

/** Trinken/Essen aus dem Inventar (Kap. 8/9): verändert den Promillepegel. */
export function consumeItem(db: Db, userId: number, invIdRaw: unknown): Res {
  const invId = Number(invIdRaw);
  if (!Number.isInteger(invId)) return err("Ungültiger Gegenstand.");
  return withTx(db, () => {
    const entry = getInventoryEntry(db, userId, invId);
    if (!entry) return err("Das liegt nicht in deinem Inventar.");
    if (!isConsumable(entry)) return err(`„${entry.name}" kann man nicht essen oder trinken.`);
    if (entry.quantity > 1) {
      db.prepare("UPDATE inventory SET quantity = quantity - 1 WHERE id = ?").run(invId);
    } else {
      db.prepare("DELETE FROM inventory WHERE id = ?").run(invId);
    }
    const user = getUser(db, userId)!;
    const result = applyPromilleDelta(db, user, entry.promille_delta);
    if (result.hospital) {
      return ok(
        `„${entry.name}" war eine ganz schlechte Idee: Lebensgefahr! Der Rettungswagen bringt dich ins Krankenhaus. ` +
          `Behandlung: ${fmtMoney(result.fee)}. Du wachst stocknüchtern wieder auf (0,0 ‰).`,
      );
    }
    const verb = entry.category === "drink" ? "getrunken" : "gegessen";
    return ok(
      `„${entry.name}" ${verb} — Pegel jetzt ${fmtPromille(result.promille)}, Laune: ${moodLabel(result.promille)}.`,
    );
  });
}

/** Waschhaus (Kap. 8): günstig +20 Prozentpunkte, gründlich → 100 %. */
export function washUser(db: Db, userId: number, optionRaw: unknown): Res {
  const option = String(optionRaw);
  if (option !== "guenstig" && option !== "gruendlich") {
    return err("So wäscht hier niemand.");
  }
  return withTx(db, () => {
    const user = getUser(db, userId)!;
    if (user.cleanliness >= 100) {
      return err("Du bist schon blitzsauber — spar dir das Geld.");
    }
    const cost = option === "guenstig" ? GAME.WASH_CHEAP_COST : GAME.WASH_FULL_COST;
    if (user.money < cost) {
      return err(`Zu wenig Geld: Diese Wäsche kostet ${fmtMoney(cost)}.`);
    }
    const next =
      option === "guenstig"
        ? Math.min(100, user.cleanliness + GAME.WASH_CHEAP_GAIN)
        : 100;
    db.prepare("UPDATE users SET money = money - ?, cleanliness = ? WHERE id = ?").run(
      cost,
      next,
      userId,
    );
    return ok(
      option === "guenstig"
        ? `Katzenwäsche für ${fmtMoney(cost)} — Sauberkeit jetzt ${next} %.`
        : `Vollprogramm mit Schaum für ${fmtMoney(cost)} — du glänzt: 100 % sauber.`,
    );
  });
}

/** Umzug in einen anderen Stadtteil (Kap. 8): kostet einmalig Umzugskosten. */
export function moveToDistrict(db: Db, userId: number, districtIdRaw: unknown): Res {
  const districtId = Number(districtIdRaw);
  if (!Number.isInteger(districtId)) return err("Dieses Viertel gibt es nicht.");
  return withTx(db, () => {
    const user = getUser(db, userId)!;
    const target = getDistrict(db, districtId);
    if (!target) return err("Dieses Viertel gibt es nicht.");
    if (user.district_id === target.id) return err(`Du wohnst schon am ${target.name}.`);
    if (user.money < target.move_cost) {
      return err(
        `Der Umzug zum ${target.name} kostet ${fmtMoney(target.move_cost)} — so viel hast du nicht.`,
      );
    }
    db.prepare("UPDATE users SET money = money - ?, district_id = ? WHERE id = ?").run(
      target.move_cost,
      target.id,
      userId,
    );
    // Stadtteilgebundene Unterkunft verliert ihren Nutzen, wenn man wegzieht.
    const activeHome = db
      .prepare(
        `SELECT inventory.id AS invId, items.name, items.min_district_tier
         FROM inventory JOIN items ON items.id = inventory.item_id
         WHERE inventory.user_id = ? AND inventory.is_active = 1 AND items.category = 'home'`,
      )
      .get(userId) as unknown as
      | { invId: number; name: string; min_district_tier: number | null }
      | undefined;
    let homeNote = "";
    if (
      activeHome?.min_district_tier &&
      activeHome.min_district_tier > target.tier
    ) {
      db.prepare("UPDATE inventory SET is_active = 0 WHERE id = ?").run(activeHome.invId);
      homeNote = ` Deine Unterkunft „${activeHome.name}" liegt jetzt zu weit weg und bringt dir keinen Schutz mehr!`;
    }
    return ok(
      `Umgezogen: Du lebst jetzt am ${target.name} (Sammel-Faktor ×${target.factor.toLocaleString("de-DE")}).${homeNote}`,
    );
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
       WHERE id != ? AND points BETWEEN ? AND ? AND vacation_until <= ?
       ORDER BY ABS(points - ?) ASC, id ASC LIMIT ?`,
    )
    .all(me.id, range.min, range.max, now(), me.points, limit) as unknown as Array<{
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
