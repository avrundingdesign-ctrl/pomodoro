import type { Db, ItemRow, UserRow } from "../db.js";
import { SKILL_TYPES, type SkillType } from "../config.js";
import { activeContainer, capacityFor } from "./money.js";

export type SkillLevels = Record<SkillType, number>;

export function skillLevels(db: Db, userId: number): SkillLevels {
  const rows = db
    .prepare("SELECT type, level FROM skills WHERE user_id = ?")
    .all(userId) as unknown as Array<{ type: string; level: number }>;
  const levels = Object.fromEntries(SKILL_TYPES.map((t) => [t, 0])) as SkillLevels;
  for (const r of rows) {
    if ((SKILL_TYPES as string[]).includes(r.type)) {
      levels[r.type as SkillType] = r.level;
    }
  }
  return levels;
}

export function activeWeapon(db: Db, userId: number): ItemRow | null {
  const row = db
    .prepare(
      `SELECT items.* FROM inventory
       JOIN items ON items.id = inventory.item_id
       WHERE inventory.user_id = ? AND inventory.is_active = 1
         AND items.category = 'weapon'
       LIMIT 1`,
    )
    .get(userId) as unknown as ItemRow | undefined;
  return row ?? null;
}

export interface EffectiveStats {
  skills: SkillLevels;
  weapon: ItemRow | null;
  container: ItemRow | null;
  attEff: number;
  defEff: number;
  capacity: number;
}

/** Effektive Kampf-/Statuswerte: Skill-Stufe + aktive Ausrüstung (Kap. 3/6). */
export function effectiveStats(db: Db, userId: number): EffectiveStats {
  const skills = skillLevels(db, userId);
  const weapon = activeWeapon(db, userId);
  const container = activeContainer(db, userId);
  return {
    skills,
    weapon,
    container,
    attEff: skills.angriff + (weapon?.att_bonus ?? 0),
    defEff: skills.verteidigung + (weapon?.def_bonus ?? 0),
    capacity: capacityFor(db, userId),
  };
}

/** Highscore-Rang: Punkte absteigend, bei Gleichstand ist der Ältere vorn. */
export function rankOf(db: Db, user: Pick<UserRow, "id" | "points">): number {
  const row = db
    .prepare(
      `SELECT COUNT(*) AS better FROM users
       WHERE points > ? OR (points = ? AND id < ?)`,
    )
    .get(user.points, user.points, user.id) as unknown as { better: number };
  return row.better + 1;
}
