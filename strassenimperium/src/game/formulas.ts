import { GAME } from "../config.js";

/**
 * Sammelertrag in Pfandflaschen (Kap. 5): wächst unterproportional mit der
 * Dauer (kurze Sessions sind pro Minute ertragreicher) und linear mit der
 * Geschicklichkeit. Der Stadtteil-Faktor ist in Phase 1 fix 1,0 (eine Stadt,
 * ein Viertel — Stadtteile kommen in Phase 2).
 */
export function collectYield(
  minutes: number,
  geschickLevel: number,
  districtFactor = 1,
): number {
  const base = Math.pow(minutes, GAME.COLLECT_EXP);
  const skill = 1 + GAME.COLLECT_SKILL_BONUS * geschickLevel;
  return Math.max(1, Math.round(base * skill * districtFactor));
}

/** Kosten (Cent) für die Weiterbildung auf `targetLevel`. */
export function trainingCost(targetLevel: number): number {
  return Math.round(
    GAME.TRAINING_BASE_COST * Math.pow(GAME.TRAINING_COST_GROWTH, targetLevel - 1),
  );
}

/** Dauer (Minuten) für die Weiterbildung auf `targetLevel`. */
export function trainingDurationMinutes(targetLevel: number): number {
  return Math.round(
    GAME.TRAINING_BASE_MINUTES *
      Math.pow(GAME.TRAINING_DURATION_GROWTH, targetLevel - 1),
  );
}

/**
 * Tageskurs pro Pfandflasche in Cent (Kap. 5/9): deterministisch pro
 * UTC-Datum, damit alle Spieler denselben Kurs sehen und der Server ihn
 * nicht speichern muss. FNV-1a-Hash über das Datum.
 */
export function kursCentsFor(date: Date): number {
  const key = date.toISOString().slice(0, 10);
  let h = 0x811c9dc5;
  for (let i = 0; i < key.length; i++) {
    h ^= key.charCodeAt(i);
    h = Math.imul(h, 0x01000193) >>> 0;
  }
  return GAME.KURS_MIN + (h % GAME.KURS_SPAN);
}

export type FightOutcome = "win" | "loss" | "draw";

export interface FightResult {
  attScore: number;
  defScore: number;
  outcome: FightOutcome;
}

/**
 * Kampfformel (Kap. 7.1): beide Seiten würfeln ihren Effektivwert mal
 * Zufallsfaktor 0,85–1,15. Das entspricht der Vorgabe
 * P(A) ≈ ATT_A / (ATT_A + DEF_B) × Zufall × Promille-Malus. +1 Basis, damit
 * auch frische Charaktere (Stufe 0) kämpfen können. `rnd` ist injizierbar
 * für Tests; `attFactor`/`defFactor` tragen den jeweiligen Promille-Zustand.
 */
export function fightScores(
  attEff: number,
  defEff: number,
  rnd: () => number = Math.random,
  attFactor = 1,
  defFactor = 1,
): FightResult {
  const roll = () => GAME.FIGHT_RANDOM_MIN + GAME.FIGHT_RANDOM_SPAN * rnd();
  const attScore = (1 + attEff) * roll() * attFactor;
  const defScore = (1 + defEff) * roll() * defFactor;
  const margin = GAME.FIGHT_DRAW_MARGIN * Math.max(attScore, defScore, 1);
  let outcome: FightOutcome;
  if (Math.abs(attScore - defScore) <= margin) outcome = "draw";
  else outcome = attScore > defScore ? "win" : "loss";
  return { attScore, defScore, outcome };
}

/**
 * Beute bei gewonnenem Angriff (Cent): Anteil am Bargeld des Verlierers,
 * durch dessen DEF weiter reduziert (Kap. 3: „DEF reduziert den Verlust").
 */
export function lootAmount(
  defenderMoney: number,
  attEff: number,
  defEff: number,
): number {
  const ratio = (1 + attEff) / (2 + attEff + defEff);
  return Math.max(0, Math.floor(defenderMoney * GAME.FIGHT_LOOT_FACTOR * ratio));
}

/** Angreifbare Punkte-Spanne um die eigenen Punkte (Kap. 7.1). */
export function attackRange(points: number): { min: number; max: number } {
  return {
    min: Math.max(0, Math.floor(points * GAME.RANGE_LOWER_FACTOR) - GAME.RANGE_SLACK),
    max: Math.ceil(points * GAME.RANGE_UPPER_FACTOR) + GAME.RANGE_SLACK,
  };
}
