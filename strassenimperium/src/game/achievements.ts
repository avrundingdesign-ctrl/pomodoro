import type { Db, UserRow } from "../db.js";
import { ACHIEVEMENTS, GAME } from "../config.js";
import { now } from "../clock.js";

/**
 * Auszeichnungen (Kap. 12): Bronze/Silber/Gold/Platin je Meilenstein.
 * Wird nach jedem relevanten Ereignis aufgerufen — idempotent dank
 * UNIQUE(user_id, type, tier).
 */
export function awardAchievements(db: Db, userId: number): void {
  const user = db
    .prepare(
      `SELECT fights_won, trainings_done, bottles_total, crimes_done,
              donations_got, rank_points
       FROM users WHERE id = ?`,
    )
    .get(userId) as unknown as Pick<
    UserRow,
    | "fights_won"
    | "trainings_done"
    | "bottles_total"
    | "crimes_done"
    | "donations_got"
    | "rank_points"
  > | undefined;
  if (!user) return;
  const insert = db.prepare(
    `INSERT OR IGNORE INTO achievements (user_id, type, tier, unlocked_at)
     VALUES (?, ?, ?, ?)`,
  );
  for (const def of ACHIEVEMENTS) {
    const value = user[def.metric];
    def.thresholds.forEach((threshold, index) => {
      if (value >= threshold) insert.run(userId, def.type, index + 1, now());
    });
  }
}

/**
 * Tägliche Rangpunkte für die Top 7 (Kap. 12) — lazy beim ersten Request
 * eines neuen UTC-Tages vergeben, kein Cronjob nötig.
 */
export function grantDailyRankPoints(db: Db): void {
  const today = new Date(now()).toISOString().slice(0, 10);
  const row = db
    .prepare("SELECT value FROM meta WHERE key = 'rank_points_day'")
    .get() as unknown as { value: string } | undefined;
  if (row?.value === today) return;
  // Claim zuerst — verhindert Doppelvergabe bei parallelen Requests.
  const claimed = db
    .prepare(
      `INSERT INTO meta (key, value) VALUES ('rank_points_day', ?)
       ON CONFLICT(key) DO UPDATE SET value = excluded.value
       WHERE meta.value != excluded.value`,
    )
    .run(today);
  if (claimed.changes === 0) return;
  const top = db
    .prepare("SELECT id FROM users ORDER BY points DESC, id ASC LIMIT 7")
    .all() as unknown as Array<{ id: number }>;
  top.forEach((u, index) => {
    db.prepare("UPDATE users SET rank_points = rank_points + ? WHERE id = ?").run(
      GAME.DAILY_RANK_POINTS[index],
      u.id,
    );
    awardAchievements(db, u.id);
  });
}
