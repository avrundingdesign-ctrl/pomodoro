import type { Db, UserRow } from "../db.js";
import { GAME, TIME_SCALE } from "../config.js";
import { now } from "../clock.js";

/**
 * Promille-System (Kap. 3): zweischneidiges Buff/Debuff-System.
 * Der Pegel wird nicht per Cronjob abgebaut, sondern bei jedem Lesen aus
 * letztem Stand + verstrichener (Spiel-)Zeit hergeleitet — serverseitig,
 * idempotent, ohne Schreiblast.
 */
export function promilleOf(user: Pick<UserRow, "alcohol_pm" | "alcohol_at">): number {
  if (user.alcohol_pm <= 0) return 0;
  const elapsedHours = ((now() - user.alcohol_at) * TIME_SCALE) / 3_600_000;
  return Math.max(0, user.alcohol_pm - GAME.PROMILLE_DECAY_PER_HOUR * elapsedHours);
}

function persist(db: Db, userId: number, value: number): void {
  db.prepare("UPDATE users SET alcohol_pm = ?, alcohol_at = ? WHERE id = ?").run(
    Math.max(0, Math.round(value * 100) / 100),
    now(),
    userId,
  );
}

export interface DrinkResult {
  promille: number;
  hospital: boolean;
  fee: number;
}

/**
 * Trinken/Essen anwenden (delta in ‰, negativ für Nahrung). Ab 4,0 ‰:
 * „Lebensgefahr" — Krankenhaus-Event: Zwangs-Nüchternwerden + Behandlungskosten
 * (Kap. 3, Beispielkurve).
 */
export function applyPromilleDelta(
  db: Db,
  user: UserRow,
  delta: number,
): DrinkResult {
  const next = Math.max(0, promilleOf(user) + delta);
  if (next >= GAME.PROMILLE_HOSPITAL_AT) {
    const current = db
      .prepare("SELECT money FROM users WHERE id = ?")
      .get(user.id) as unknown as { money: number };
    const fee = Math.floor(current.money * GAME.PROMILLE_HOSPITAL_FEE_FACTOR);
    db.prepare("UPDATE users SET money = money - ? WHERE id = ?").run(fee, user.id);
    persist(db, user.id, 0);
    return { promille: 0, hospital: true, fee };
  }
  persist(db, user.id, next);
  return { promille: next, hospital: false, fee: 0 };
}

/** Launen-Beschreibung laut Beispielkurve (Kap. 3). */
export function moodLabel(pm: number): string {
  if (pm < 1.0) return "aggressiv (kampfstark)";
  if (pm < 2.0) return "leicht gereizt";
  if (pm < GAME.PROMILLE_WARN_AT) return "bester Laune (Training schneller)";
  if (pm < GAME.PROMILLE_HOSPITAL_AT) return "⚠️ Warnstufe!";
  return "Lebensgefahr";
}

/**
 * Trainingsdauer-Faktor: gute Laune (≈2–3,5 ‰) trainiert schneller,
 * nüchtern-mies (< 1 ‰) minimal langsamer (Kap. 3: Laune ↔ Training).
 */
export function trainingDurationFactor(pm: number): number {
  if (pm >= 2.0 && pm < GAME.PROMILLE_WARN_AT) return 0.85;
  if (pm >= 1.0) return 1.0;
  return 1.05;
}

/**
 * Kampf-Faktor auf den eigenen Wurf: nüchtern = aggressiv/kampfstark,
 * betrunken = schlechtere Präzision (Kap. 3/7.1 „Promille-Malus").
 */
export function fightFactor(pm: number): number {
  if (pm < 0.5) return 1.1;
  if (pm < 1.0) return 1.05;
  if (pm < 2.0) return 1.0;
  if (pm < 3.0) return 0.9;
  if (pm < GAME.PROMILLE_WARN_AT) return 0.85;
  return 0.75;
}

/** Promille deutsch formatiert, z. B. „1,3 ‰". */
export function fmtPromille(pm: number): string {
  return `${pm.toLocaleString("de-DE", { minimumFractionDigits: 1, maximumFractionDigits: 1 })} ‰`;
}
