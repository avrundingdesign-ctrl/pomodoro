import { DatabaseSync } from "node:sqlite";
import fs from "node:fs";
import path from "node:path";

export type Db = DatabaseSync;

export interface UserRow {
  id: number;
  username: string;
  email: string;
  password_hash: string;
  created_at: number;
  last_login_at: number | null;
  money: number;
  points: number;
  bottles: number;
  district_id: number;
  cleanliness: number;
  alcohol_pm: number;
  alcohol_at: number;
  donation_code: string;
}

export interface DistrictRow {
  id: number;
  name: string;
  tier: number;
  factor: number;
  move_cost: number;
  blurb: string;
}

export interface SkillRow {
  user_id: number;
  type: string;
  level: number;
}

export interface TrainingRow {
  id: number;
  user_id: number;
  skill_type: string;
  target_level: number;
  cost: number;
  started_at: number;
  ends_at: number;
  resolved_at: number | null;
}

export interface ActionRow {
  id: number;
  user_id: number;
  type: string;
  target_user_id: number | null;
  payload: string | null;
  result: string | null;
  started_at: number;
  ends_at: number;
  resolved_at: number | null;
}

export interface FightRow {
  id: number;
  attacker_id: number;
  defender_id: number;
  att_score: number;
  def_score: number;
  outcome: string; // 'win' | 'loss' | 'draw' — aus Angreifer-Sicht
  money_loot: number;
  money_kept: number;
  points_attacker: number;
  points_defender: number;
  occurred_at: number;
}

export interface ItemRow {
  id: number;
  key: string;
  category: string; // 'weapon' | 'container' | 'home' | 'pet' | 'drink' | 'food'
  name: string;
  tier: number;
  att_bonus: number;
  def_bonus: number;
  capacity: number;
  price: number;
  unlock_skill: string | null;
  unlock_level: number | null;
  empathy_bonus: number;
  promille_delta: number;
  min_district_tier: number | null;
}

/** Kategorien, die man anlegt/aktiviert (genau 1 aktiv pro Kategorie). */
export const EQUIP_CATEGORIES = ["weapon", "container", "home", "pet"] as const;
/** Kategorien, die man konsumiert (stapelbar, Menge im Inventar). */
export const CONSUMABLE_CATEGORIES = ["drink", "food"] as const;

export interface InventoryRow {
  id: number;
  user_id: number;
  item_id: number;
  is_active: number;
  acquired_at: number;
  quantity: number;
}

export interface SessionRow {
  token: string;
  user_id: number;
  csrf: string;
  flash: string | null;
  created_at: number;
  expires_at: number;
}

export function openDb(dbPath: string): Db {
  if (dbPath !== ":memory:") {
    fs.mkdirSync(path.dirname(dbPath), { recursive: true });
  }
  const db = new DatabaseSync(dbPath);
  db.exec("PRAGMA foreign_keys = ON;");
  if (dbPath !== ":memory:") {
    db.exec("PRAGMA journal_mode = WAL;");
  }
  migrate(db);
  seedItems(db);
  return db;
}

export function migrate(db: Db): void {
  db.exec(`
    CREATE TABLE IF NOT EXISTS users (
      id            INTEGER PRIMARY KEY AUTOINCREMENT,
      username      TEXT NOT NULL UNIQUE COLLATE NOCASE,
      email         TEXT NOT NULL UNIQUE,
      password_hash TEXT NOT NULL,
      created_at    INTEGER NOT NULL,
      last_login_at INTEGER,
      money         INTEGER NOT NULL DEFAULT 0,
      points        INTEGER NOT NULL DEFAULT 0,
      bottles       INTEGER NOT NULL DEFAULT 0
    );

    CREATE TABLE IF NOT EXISTS skills (
      user_id INTEGER NOT NULL REFERENCES users(id) ON DELETE CASCADE,
      type    TEXT NOT NULL,
      level   INTEGER NOT NULL DEFAULT 0,
      PRIMARY KEY (user_id, type)
    );

    CREATE TABLE IF NOT EXISTS trainings (
      id           INTEGER PRIMARY KEY AUTOINCREMENT,
      user_id      INTEGER NOT NULL REFERENCES users(id) ON DELETE CASCADE,
      skill_type   TEXT NOT NULL,
      target_level INTEGER NOT NULL,
      cost         INTEGER NOT NULL,
      started_at   INTEGER NOT NULL,
      ends_at      INTEGER NOT NULL,
      resolved_at  INTEGER
    );
    CREATE INDEX IF NOT EXISTS idx_trainings_due
      ON trainings (resolved_at, ends_at);

    CREATE TABLE IF NOT EXISTS actions (
      id             INTEGER PRIMARY KEY AUTOINCREMENT,
      user_id        INTEGER NOT NULL REFERENCES users(id) ON DELETE CASCADE,
      type           TEXT NOT NULL,
      target_user_id INTEGER REFERENCES users(id) ON DELETE SET NULL,
      payload        TEXT,
      result         TEXT,
      started_at     INTEGER NOT NULL,
      ends_at        INTEGER NOT NULL,
      resolved_at    INTEGER
    );
    CREATE INDEX IF NOT EXISTS idx_actions_due
      ON actions (resolved_at, ends_at);
    CREATE INDEX IF NOT EXISTS idx_actions_user
      ON actions (user_id, resolved_at);

    CREATE TABLE IF NOT EXISTS fights (
      id               INTEGER PRIMARY KEY AUTOINCREMENT,
      attacker_id      INTEGER NOT NULL REFERENCES users(id) ON DELETE CASCADE,
      defender_id      INTEGER NOT NULL REFERENCES users(id) ON DELETE CASCADE,
      att_score        REAL NOT NULL,
      def_score        REAL NOT NULL,
      outcome          TEXT NOT NULL,
      money_loot       INTEGER NOT NULL DEFAULT 0,
      money_kept       INTEGER NOT NULL DEFAULT 0,
      points_attacker  INTEGER NOT NULL DEFAULT 0,
      points_defender  INTEGER NOT NULL DEFAULT 0,
      occurred_at      INTEGER NOT NULL
    );
    CREATE INDEX IF NOT EXISTS idx_fights_pair
      ON fights (attacker_id, defender_id, occurred_at);
    CREATE INDEX IF NOT EXISTS idx_fights_defender
      ON fights (defender_id, occurred_at);

    CREATE TABLE IF NOT EXISTS items (
      id           INTEGER PRIMARY KEY AUTOINCREMENT,
      key          TEXT NOT NULL UNIQUE,
      category     TEXT NOT NULL,
      name         TEXT NOT NULL,
      tier         INTEGER NOT NULL,
      att_bonus    INTEGER NOT NULL DEFAULT 0,
      def_bonus    INTEGER NOT NULL DEFAULT 0,
      capacity     INTEGER NOT NULL DEFAULT 0,
      price        INTEGER NOT NULL,
      unlock_skill TEXT,
      unlock_level INTEGER
    );

    CREATE TABLE IF NOT EXISTS inventory (
      id          INTEGER PRIMARY KEY AUTOINCREMENT,
      user_id     INTEGER NOT NULL REFERENCES users(id) ON DELETE CASCADE,
      item_id     INTEGER NOT NULL REFERENCES items(id),
      is_active   INTEGER NOT NULL DEFAULT 0,
      acquired_at INTEGER NOT NULL,
      UNIQUE (user_id, item_id)
    );

    CREATE TABLE IF NOT EXISTS sessions (
      token      TEXT PRIMARY KEY,
      user_id    INTEGER NOT NULL REFERENCES users(id) ON DELETE CASCADE,
      csrf       TEXT NOT NULL,
      flash      TEXT,
      created_at INTEGER NOT NULL,
      expires_at INTEGER NOT NULL
    );
    CREATE INDEX IF NOT EXISTS idx_sessions_expiry ON sessions (expires_at);

    CREATE INDEX IF NOT EXISTS idx_users_points ON users (points DESC, id ASC);

    CREATE TABLE IF NOT EXISTS districts (
      id        INTEGER PRIMARY KEY AUTOINCREMENT,
      name      TEXT NOT NULL UNIQUE,
      tier      INTEGER NOT NULL,
      factor    REAL NOT NULL,
      move_cost INTEGER NOT NULL,
      blurb     TEXT NOT NULL DEFAULT ''
    );

    CREATE TABLE IF NOT EXISTS donation_clicks (
      id         INTEGER PRIMARY KEY AUTOINCREMENT,
      user_id    INTEGER NOT NULL REFERENCES users(id) ON DELETE CASCADE,
      ip_hash    TEXT NOT NULL,
      day        TEXT NOT NULL,
      amount     INTEGER NOT NULL,
      created_at INTEGER NOT NULL,
      UNIQUE (user_id, ip_hash, day)
    );
    CREATE INDEX IF NOT EXISTS idx_donations_user_day ON donation_clicks (user_id, day);
  `);

  // Idempotente Spalten-Migrationen (Phase 2 auf bestehenden Phase-1-Datenbanken).
  ensureColumn(db, "users", "district_id", "INTEGER NOT NULL DEFAULT 1");
  ensureColumn(db, "users", "cleanliness", "INTEGER NOT NULL DEFAULT 50");
  ensureColumn(db, "users", "alcohol_pm", "REAL NOT NULL DEFAULT 0");
  ensureColumn(db, "users", "alcohol_at", "INTEGER NOT NULL DEFAULT 0");
  ensureColumn(db, "users", "donation_code", "TEXT");
  ensureColumn(db, "inventory", "quantity", "INTEGER NOT NULL DEFAULT 1");
  ensureColumn(db, "items", "empathy_bonus", "INTEGER NOT NULL DEFAULT 0");
  ensureColumn(db, "items", "promille_delta", "REAL NOT NULL DEFAULT 0");
  ensureColumn(db, "items", "min_district_tier", "INTEGER");
  db.exec(
    "UPDATE users SET donation_code = lower(hex(randomblob(8))) WHERE donation_code IS NULL",
  );
  db.exec(
    "CREATE UNIQUE INDEX IF NOT EXISTS idx_users_donation_code ON users (donation_code)",
  );
}

function ensureColumn(db: Db, table: string, column: string, ddl: string): void {
  const cols = db.prepare(`PRAGMA table_info(${table})`).all() as unknown as Array<{
    name: string;
  }>;
  if (!cols.some((c) => c.name === column)) {
    db.exec(`ALTER TABLE ${table} ADD COLUMN ${column} ${ddl}`);
  }
}

/**
 * Item-Katalog (Kap. 6/19): Content ist datengetrieben — neue Gegenstände
 * sind nur neue Zeilen, kein neuer Code. Seed ist idempotent (Key-basiert).
 */
export function seedItems(db: Db): void {
  const insert = db.prepare(`
    INSERT OR IGNORE INTO items
      (key, category, name, tier, att_bonus, def_bonus, capacity, price,
       unlock_skill, unlock_level, empathy_bonus, promille_delta, min_district_tier)
    VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
  `);
  type Seed = [
    string, string, string, number, number, number, number, number,
    string | null, number | null, number, number, number | null,
  ];
  const items: Seed[] = [
    // Waffen (freigeschaltet über den Angriff-Skill, Preise in Cent)
    ["weapon_1", "weapon", "Zerbrochene Flasche", 1, 2, 0, 0, 350, "angriff", 1, 0, 0, null],
    ["weapon_2", "weapon", "Stinkender Turnschuh", 2, 5, 0, 0, 1200, "angriff", 3, 0, 0, null],
    ["weapon_3", "weapon", "Alter Gehstock", 3, 9, 0, 0, 3500, "angriff", 6, 0, 0, null],
    ["weapon_4", "weapon", "Rostige Bratpfanne", 4, 15, 0, 0, 9000, "angriff", 10, 0, 0, null],
    // Behälter (erhöhen die Geld-Kapazität; Überlauf geht verloren, Kap. 3/6)
    ["container_1", "container", "Plastiktüte", 1, 0, 0, 15000, 800, null, null, 0, 0, null],
    ["container_2", "container", "Einkaufsbeutel", 2, 0, 0, 40000, 3000, null, null, 0, 0, null],
    ["container_3", "container", "Bauchtasche", 3, 0, 0, 120000, 10000, null, null, 0, 0, null],
    ["container_4", "container", "Einkaufswagen", 4, 0, 0, 500000, 40000, null, null, 0, 0, null],
    // Unterkünfte (+DEF; freigeschaltet über Verteidigung, teils stadtteilgebunden — Kap. 6)
    ["home_1", "home", "Pappkarton", 1, 0, 1, 0, 250, "verteidigung", 1, 0, 0, null],
    ["home_2", "home", "Parkbank-Stammplatz", 2, 0, 3, 0, 900, "verteidigung", 2, 0, 0, null],
    ["home_3", "home", "Zelt am Kanal", 3, 0, 6, 0, 2500, "verteidigung", 4, 0, 0, null],
    ["home_4", "home", "Bauwagen", 4, 0, 10, 0, 8000, "verteidigung", 6, 0, 0, 2],
    ["home_5", "home", "Kellerverschlag", 5, 0, 15, 0, 20000, "verteidigung", 9, 0, 0, 3],
    ["home_6", "home", "Hinterhof-Laube", 6, 0, 21, 0, 45000, "verteidigung", 12, 0, 0, 4],
    ["home_7", "home", "WG-Zimmer", 7, 0, 28, 0, 100000, "verteidigung", 16, 0, 0, 5],
    ["home_8", "home", "Dachbude mit Aussicht", 8, 0, 36, 0, 220000, "verteidigung", 20, 0, 0, 6],
    // Haustiere (+ATT/+DEF + Mitleidswert für Spenden; über Sozialkontakte — Kap. 6)
    ["pet_1", "pet", "Straßentaube", 1, 0, 1, 0, 500, "sozial", 1, 2, 0, null],
    ["pet_2", "pet", "Ratte Rudi", 2, 1, 1, 0, 1500, "sozial", 2, 3, 0, null],
    ["pet_3", "pet", "Streunerkatze", 3, 1, 2, 0, 4000, "sozial", 3, 5, 0, null],
    ["pet_4", "pet", "Promenadenmischung", 4, 2, 3, 0, 10000, "sozial", 5, 8, 0, null],
    ["pet_5", "pet", "Wachgans", 5, 4, 5, 0, 25000, "sozial", 7, 6, 0, null],
    ["pet_6", "pet", "Bernhardiner", 6, 6, 8, 0, 60000, "sozial", 9, 12, 0, null],
    ["pet_7", "pet", "Hängebauchschwein", 7, 5, 7, 0, 120000, "sozial", 10, 16, 0, null],
    // Supermarkt: Alkohol erhöht Promille, Nahrung senkt sie (Kap. 8)
    ["drink_1", "drink", "Dosenbier", 1, 0, 0, 0, 80, null, null, 0, 0.3, null],
    ["drink_2", "drink", "Fusel „Roter Oktober“", 2, 0, 0, 0, 150, null, null, 0, 0.6, null],
    ["drink_3", "drink", "Doppelkorn", 3, 0, 0, 0, 300, null, null, 0, 1.0, null],
    ["drink_4", "drink", "Edel-Absinth", 4, 0, 0, 0, 800, null, null, 0, 1.6, null],
    ["food_1", "food", "Brezel", 1, 0, 0, 0, 120, null, null, 0, -0.3, null],
    ["food_2", "food", "Currywurst", 2, 0, 0, 0, 250, null, null, 0, -0.6, null],
    ["food_3", "food", "Erbseneintopf", 3, 0, 0, 0, 500, null, null, 0, -1.2, null],
  ];
  for (const row of items) insert.run(...row);
  seedDistricts(db);
}

/** Stadtteile (Kap. 8/19): eine Stadt, 12 Viertel, steigende Faktoren/Kosten. */
export function seedDistricts(db: Db): void {
  const insert = db.prepare(`
    INSERT OR IGNORE INTO districts (name, tier, factor, move_cost, blurb)
    VALUES (?, ?, ?, ?, ?)
  `);
  const districts: Array<[string, number, number, number, string]> = [
    ["Gleisdreieck", 1, 1.0, 0, "Zugige Ecke hinterm Bahnhof — hier fängt jede Karriere an."],
    ["Kanalufer", 1, 1.02, 300, "Feucht, aber die Angler lassen Pfandflaschen liegen."],
    ["Industriehof", 2, 1.05, 800, "Zwischen Schichtwechsel und Werkstor klimpert es ordentlich."],
    ["Flohmarktplatz", 2, 1.08, 1500, "Wo gehandelt wird, fällt immer etwas ab."],
    ["Altstadtgassen", 3, 1.12, 3000, "Touristen! Die werfen Flaschen UND Münzen weg."],
    ["Hafenkante", 3, 1.15, 6000, "Raue Gegend, gute Geschäfte."],
    ["Universitätsallee", 4, 1.2, 12000, "Studierende spenden wenig, feiern aber viel — Pfand satt."],
    ["Theaterplatz", 4, 1.25, 25000, "Nach der Premiere rollt der Sekt in Flaschenform."],
    ["Parkviertel", 5, 1.32, 50000, "Gepflegte Hecken, großzügige Spaziergänger."],
    ["Galerienmeile", 5, 1.4, 100000, "Kunstpublikum: distinguiert, spendabel, durstig."],
    ["Villenhang", 6, 1.5, 250000, "Hier oben ist sogar das Leergut edel."],
    ["Schlossblick", 7, 1.65, 600000, "Die beste Adresse der Stadt. Noch."],
  ];
  for (const row of districts) insert.run(...row);
}

/** Kleine Transaktions-Hilfe (node:sqlite hat keinen eingebauten Helper). */
export function withTx<T>(db: Db, fn: () => T): T {
  db.exec("BEGIN IMMEDIATE");
  try {
    const result = fn();
    db.exec("COMMIT");
    return result;
  } catch (err) {
    db.exec("ROLLBACK");
    throw err;
  }
}
