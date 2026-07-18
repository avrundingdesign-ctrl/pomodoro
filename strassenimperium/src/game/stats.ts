import type { Db, ItemRow, UserRow } from "../db.js";
import { GAME, SKILL_TYPES, type SkillType } from "../config.js";
import { activeContainer, capacityFor } from "./money.js";
import { gangOf } from "./gangs.js";

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

export function activeItemOf(
  db: Db,
  userId: number,
  category: string,
): ItemRow | null {
  const row = db
    .prepare(
      `SELECT items.* FROM inventory
       JOIN items ON items.id = inventory.item_id
       WHERE inventory.user_id = ? AND inventory.is_active = 1
         AND items.category = ?
       LIMIT 1`,
    )
    .get(userId, category) as unknown as ItemRow | undefined;
  return row ?? null;
}

export function activeWeapon(db: Db, userId: number): ItemRow | null {
  return activeItemOf(db, userId, "weapon");
}

export interface EffectiveStats {
  skills: SkillLevels;
  weapon: ItemRow | null;
  container: ItemRow | null;
  home: ItemRow | null;
  pet: ItemRow | null;
  instrument: ItemRow | null;
  spot: ItemRow | null;
  attEff: number;
  defEff: number;
  capacity: number;
}

/**
 * Effektive Kampf-/Statuswerte: Skill-Stufe + aktive Ausrüstung (Kap. 3/6).
 * ATT = Angriff + Waffe + Haustier; DEF = Verteidigung + Unterkunft + Haustier.
 */
export function effectiveStats(db: Db, userId: number): EffectiveStats {
  const skills = skillLevels(db, userId);
  const weapon = activeWeapon(db, userId);
  const container = activeContainer(db, userId);
  const home = activeItemOf(db, userId, "home");
  const pet = activeItemOf(db, userId, "pet");
  const instrument = activeItemOf(db, userId, "instrument");
  const spot = activeItemOf(db, userId, "spot");
  // Bandengebäude verstärken alle Mitglieder prozentual (Kap. 11).
  const membership = gangOf(db, userId);
  const armoryFactor = 1 + GAME.GANG_ARMORY_ATT_PER_LEVEL * (membership?.gang.armory ?? 0);
  const houseFactor = 1 + GAME.GANG_HOUSE_DEF_PER_LEVEL * (membership?.gang.house ?? 0);
  const attBase = skills.angriff + (weapon?.att_bonus ?? 0) + (pet?.att_bonus ?? 0);
  const defBase =
    skills.verteidigung +
    (weapon?.def_bonus ?? 0) +
    (home?.def_bonus ?? 0) +
    (pet?.def_bonus ?? 0);
  return {
    skills,
    weapon,
    container,
    home,
    pet,
    instrument,
    spot,
    attEff: Math.round(attBase * armoryFactor),
    defEff: Math.round(defBase * houseFactor),
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
