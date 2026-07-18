import crypto from "node:crypto";
import type { Db, UserRow } from "../db.js";
import { withTx } from "../db.js";
import { GAME } from "../config.js";
import { now } from "../clock.js";
import { addMoney } from "./money.js";
import { effectiveStats } from "./stats.js";
import { districtOf } from "./districts.js";
import { promilleOf } from "./promille.js";

/**
 * Betteln per Spendenlink (Kap. 5/10): Jeder Klick eines Dritten zahlt einen
 * kleinen Betrag aus. Höhe hängt von Sauberkeit, Standort und dem
 * Mitleidswert des Haustiers ab — exakt die im Lastenheft genannten Faktoren
 * (geworbene Spieler folgen mit dem Referral-System in einer späteren Phase).
 */
export function donationAmountFor(db: Db, user: UserRow): number {
  const stats = effectiveStats(db, user.id);
  const district = districtOf(db, user);
  const cleanlinessFactor = 0.4 + 0.012 * user.cleanliness; // 0,4–1,6
  const empathyFactor = 1 + 0.04 * (stats.pet?.empathy_bonus ?? 0);
  const spotFactor = 1 + (stats.spot?.donation_bonus ?? 0) / 100;
  return Math.max(
    1,
    Math.round(
      GAME.DONATION_BASE_CENTS *
        cleanlinessFactor *
        district.factor *
        empathyFactor *
        spotFactor,
    ),
  );
}

export interface DonationResult {
  paid: boolean;
  amount: number;
  reason: "ok" | "duplicate" | "daily_cap";
}

function dayKey(): string {
  return new Date(now()).toISOString().slice(0, 10);
}

export function hashIp(ip: string, code: string): string {
  return crypto.createHash("sha256").update(`${ip}|${code}`).digest("hex").slice(0, 32);
}

/** Klick verbuchen: pro Quelle (IP-Hash) und Tag nur einmal, Tagesdeckel gegen Bots. */
export function recordDonationClick(
  db: Db,
  user: UserRow,
  ipHash: string,
): DonationResult {
  return withTx(db, () => {
    const day = dayKey();
    const todayCount = (
      db
        .prepare(
          "SELECT COUNT(*) AS n FROM donation_clicks WHERE user_id = ? AND day = ?",
        )
        .get(user.id, day) as unknown as { n: number }
    ).n;
    if (todayCount >= GAME.DONATION_DAILY_CAP) {
      return { paid: false, amount: 0, reason: "daily_cap" as const };
    }
    const inserted = db
      .prepare(
        `INSERT OR IGNORE INTO donation_clicks (user_id, ip_hash, day, amount, created_at)
         VALUES (?, ?, ?, 0, ?)`,
      )
      .run(user.id, ipHash, day, now());
    if (inserted.changes === 0) {
      return { paid: false, amount: 0, reason: "duplicate" as const };
    }
    const amount = donationAmountFor(db, user);
    const added = addMoney(db, user.id, amount).added;
    db.prepare("UPDATE donation_clicks SET amount = ? WHERE user_id = ? AND ip_hash = ? AND day = ?").run(
      added,
      user.id,
      ipHash,
      day,
    );
    return { paid: true, amount: added, reason: "ok" as const };
  });
}

export function donationStatsToday(db: Db, userId: number): { clicks: number; earned: number } {
  const row = db
    .prepare(
      `SELECT COUNT(*) AS clicks, COALESCE(SUM(amount), 0) AS earned
       FROM donation_clicks WHERE user_id = ? AND day = ?`,
    )
    .get(userId, dayKey()) as unknown as { clicks: number; earned: number };
  return row;
}

export function renewDonationCode(db: Db, userId: number): string {
  const code = crypto.randomBytes(8).toString("hex");
  db.prepare("UPDATE users SET donation_code = ? WHERE id = ?").run(code, userId);
  return code;
}

/** Faktoren-Übersicht für die Betteln-Seite. */
export function donationBreakdown(db: Db, user: UserRow) {
  const stats = effectiveStats(db, user.id);
  const district = districtOf(db, user);
  return {
    base: GAME.DONATION_BASE_CENTS,
    cleanliness: user.cleanliness,
    cleanlinessFactor: 0.4 + 0.012 * user.cleanliness,
    district,
    pet: stats.pet,
    empathyFactor: 1 + 0.04 * (stats.pet?.empathy_bonus ?? 0),
    spot: stats.spot,
    spotFactor: 1 + (stats.spot?.donation_bonus ?? 0) / 100,
    perClick: donationAmountFor(db, user),
    promille: promilleOf(user),
  };
}
