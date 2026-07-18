import path from "node:path";
import { ROOT } from "./paths.js";

/**
 * Laufzeit-Konfiguration über Umgebungsvariablen.
 *
 * DEV_TIME_SCALE: Zeitraffer NUR für Entwicklung/Tests (z. B. 60 = alle
 * Wartezeiten laufen 60× schneller). Im Produktivbetrieb weglassen (= 1).
 */
export const PORT = Number(process.env.PORT ?? 3000);
export const DB_PATH =
  process.env.DB_PATH ?? path.join(ROOT, "data", "strassenimperium.db");
export const TIME_SCALE = Math.max(
  0.0001,
  Number(process.env.DEV_TIME_SCALE ?? 1) || 1,
);

/** Dauer (ms) unter Berücksichtigung des Entwicklungs-Zeitraffers. */
export function scaledMs(ms: number): number {
  return Math.max(1000, Math.round(ms / TIME_SCALE));
}

/**
 * Spielbalance-Konstanten (Phase 1). Alle Werte sind bewusst zentral und
 * frei tunbar — siehe Lastenheft Kap. 3–7 („frei tunbar; wichtig ist nur,
 * dass ATT/DEF-Verhältnis + Zufall einfließen").
 */
export const GAME = {
  /** Startgeld in Cent (5,00 €). */
  START_MONEY: 500,
  /** Basis-Geldkapazität ohne Behälter, in Cent („Hosentasche", 50,00 €). */
  BASE_CAPACITY: 5000,

  /** Wählbare Sammeldauern in Minuten (10 Min. – 12 Std., Kap. 5). */
  COLLECT_MINUTES: [10, 30, 60, 120, 240, 480, 720],
  /** Exponent < 1: kürzere Sammel-Sessions sind pro Minute ertragreicher. */
  COLLECT_EXP: 0.8,
  /** Ertragsbonus pro Geschicklichkeits-Stufe (+5 %). */
  COLLECT_SKILL_BONUS: 0.05,

  /** Tageskurs pro Pfandflasche: 8–15 Cent, deterministisch pro Datum. */
  KURS_MIN: 8,
  KURS_SPAN: 8,

  /** Weiterbildung (Kap. 4): Kosten/Dauer wachsen exponentiell pro Stufe. */
  TRAINING_BASE_COST: 200,
  TRAINING_COST_GROWTH: 1.3,
  TRAINING_BASE_MINUTES: 10,
  TRAINING_DURATION_GROWTH: 1.25,
  /** Max. 2 Weiterbildungen gleichzeitig (Kap. 4). */
  MAX_PARALLEL_TRAININGS: 2,

  /** Kampf (Kap. 7.1). */
  FIGHT_DURATION_MINUTES: 5,
  FIGHT_COOLDOWN_HOURS: 36,
  /** Zufallsfaktor 0,85–1,15 auf beide Seiten. */
  FIGHT_RANDOM_MIN: 0.85,
  FIGHT_RANDOM_SPAN: 0.3,
  /** Unentschieden, wenn die Wurf-Ergebnisse < 2 % auseinanderliegen. */
  FIGHT_DRAW_MARGIN: 0.02,
  /** Max. Beuteanteil am Bargeld des Verlierers (DEF reduziert weiter). */
  FIGHT_LOOT_FACTOR: 0.1,
  FIGHT_POINTS: {
    attackerWin: 8,
    defenderLossPenalty: 4,
    attackerLossPenalty: 3,
    defenderWin: 6,
    draw: 1,
  },
  /** Angreifbare Punkte-Spanne relativ zu den eigenen Punkten (Kap. 7.1). */
  RANGE_LOWER_FACTOR: 0.5,
  RANGE_UPPER_FACTOR: 2,
  RANGE_SLACK: 25,
  /** Ab dieser Geschicklichkeits-Stufe werden eingehende Angriffe sichtbar. */
  INCOMING_VISIBLE_AT_SKILL: 20,

  /** Wiederverkaufswert von Gegenständen (Kap. 9: < Kaufpreis, Geld-Sink). */
  ITEM_RESALE_FACTOR: 0.5,

  /** Session-Lebensdauer: 30 Tage. */
  SESSION_TTL_MS: 30 * 24 * 60 * 60 * 1000,

  // ---------------------------------------------------- Phase 2: Promille (Kap. 3)
  /** Natürlicher Abbau pro (Spiel-)Stunde in ‰. */
  PROMILLE_DECAY_PER_HOUR: 0.15,
  /** Ab hier: „Lebensgefahr" → Krankenhaus-Event (Kap. 3: 4,0 ‰). */
  PROMILLE_HOSPITAL_AT: 4.0,
  /** Krankenhaus kostet diesen Anteil des Bargelds. */
  PROMILLE_HOSPITAL_FEE_FACTOR: 0.25,
  /** Warnstufe laut Beispielkurve. */
  PROMILLE_WARN_AT: 3.5,

  // ------------------------------------------------- Phase 2: Sauberkeit (Kap. 3/8)
  /** Sauberkeitsverlust pro Stunde Sammeln (Prozentpunkte). */
  CLEANLINESS_LOSS_PER_HOUR: 2,
  /** Startwert bei Registrierung. */
  CLEANLINESS_START: 50,
  /** Waschhaus (Kap. 8): günstig +20 %-Punkte, gründlich → 100 %. */
  WASH_CHEAP_COST: 150,
  WASH_CHEAP_GAIN: 20,
  WASH_FULL_COST: 600,

  // ------------------------------------- Phase 2: Betteln/Spendenlink (Kap. 5/10)
  /** Basis-Auszahlung pro Klick in Cent (vor Faktoren). */
  DONATION_BASE_CENTS: 8,
  /** Max. vergütete Klicks pro Tag (Bot-/Missbrauchsbremse). */
  DONATION_DAILY_CAP: 50,

  // --------------------------------------------------- Phase 2: Skill-Stufenlimits
  /** Stufenlimits (Kap. 4): Nebenskills sind gedeckelt, Kampfskills nicht. */
  SKILL_MAX_LEVEL: {
    sozial: 10,
    bildung: 8,
    musik: 5,
    konzentration: 4,
  } as Partial<Record<string, number>>,

  // ------------------------------------------------ Schritt A: Konzentrieren (Kap. 5)
  /** Beschleunigung laufender Weiterbildungen pro Konzentrations-Stufe. */
  KONZ_BOOST_PER_LEVEL: 0.1,
  /** Cooldown zwischen zwei Konzentrations-Schüben (Stunden). */
  KONZ_COOLDOWN_HOURS: 6,
  /** Ab dieser Stufe auch während Sammeln/Kampf nutzbar (Kap. 5). */
  KONZ_COMBINABLE_AT: 3,

  // ---------------------------------------------- Schritt A: Straßenmusik (Kap. 4/6)
  /** Instrumente zahlen alle 6 Stunden aus (Kap. 6). */
  MUSIC_PAYOUT_HOURS: 6,
} as const;

/**
 * Verbrechen (Kap. 5): gestaffelt von klein bis groß. Höhere Stufen erfordern
 * mehr Geschick UND eine teurere Unterkunft; die Strafe bei Fehlschlag wächst
 * mit der Verbrechensgröße. Erfolgschance steigt mit überschüssigem Geschick.
 */
export interface CrimeDef {
  key: string;
  name: string;
  minGeschick: number;
  /** Mindest-Stufe der AKTIVEN Unterkunft („teurer Wohnort"). 0 = egal. */
  minHomeTier: number;
  minutes: number;
  baseChance: number;
  lootMin: number;
  lootMax: number;
  fine: number;
}
export const CRIMES: CrimeDef[] = [
  { key: "automat", name: "Kaugummiautomat knacken", minGeschick: 1, minHomeTier: 0, minutes: 15, baseChance: 0.75, lootMin: 150, lootMax: 400, fine: 200 },
  { key: "lieferwagen", name: "Lieferwagen „entladen“", minGeschick: 3, minHomeTier: 0, minutes: 30, baseChance: 0.65, lootMin: 500, lootMax: 1200, fine: 600 },
  { key: "kiosk", name: "Kiosk-Kasse „ausleihen“", minGeschick: 6, minHomeTier: 2, minutes: 60, baseChance: 0.55, lootMin: 1500, lootMax: 4000, fine: 2000 },
  { key: "buero", name: "Büro-Einbruch", minGeschick: 10, minHomeTier: 3, minutes: 120, baseChance: 0.45, lootMin: 5000, lootMax: 12000, fine: 6000 },
  { key: "juwelier", name: "Juwelier ausräumen", minGeschick: 15, minHomeTier: 5, minutes: 240, baseChance: 0.35, lootMin: 15000, lootMax: 40000, fine: 20000 },
  { key: "bank", name: "Bank überfallen", minGeschick: 22, minHomeTier: 6, minutes: 480, baseChance: 0.25, lootMin: 60000, lootMax: 150000, fine: 80000 },
];
/** Zusätzliche Erfolgschance pro Geschick-Stufe über der Anforderung. */
export const CRIME_SKILL_BONUS = 0.02;
/** Obergrenze der Erfolgschance. */
export const CRIME_MAX_CHANCE = 0.9;

export type SkillType =
  | "angriff"
  | "verteidigung"
  | "geschick"
  | "sozial"
  | "bildung"
  | "musik"
  | "konzentration";
export const SKILL_TYPES: SkillType[] = [
  "angriff",
  "verteidigung",
  "geschick",
  "sozial",
  "bildung",
  "musik",
  "konzentration",
];

export const SKILL_INFO: Record<
  SkillType,
  { name: string; effect: string }
> = {
  angriff: {
    name: "Angriff",
    effect: "+1 ATT pro Stufe, schaltet neue Waffen frei.",
  },
  verteidigung: {
    name: "Verteidigung",
    effect:
      "+1 DEF pro Stufe, reduziert Verluste bei Überfällen und schaltet Unterkünfte frei.",
  },
  geschick: {
    name: "Geschicklichkeit",
    effect:
      "+5 % Sammelertrag pro Stufe. Ab Stufe 20 siehst du eingehende Angriffe vorab.",
  },
  sozial: {
    name: "Sozialkontakte",
    effect: "Schaltet Haustiere frei (max. Stufe 10).",
  },
  bildung: {
    name: "Bildungsstufe",
    effect: "Schaltet Bettelspots frei — bessere Standorte, mehr Spenden (max. Stufe 8).",
  },
  musik: {
    name: "Musik",
    effect: "Schaltet Instrumente frei — passives Einkommen alle 6 Stunden (max. Stufe 5).",
  },
  konzentration: {
    name: "Konzentration",
    effect:
      "Schaltet „Konzentrieren“ frei: beschleunigt laufende Weiterbildungen, ab Stufe 3 sogar nebenbei (max. Stufe 4).",
  },
};
