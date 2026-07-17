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
  category: string; // 'weapon' | 'container'
  name: string;
  tier: number;
  att_bonus: number;
  def_bonus: number;
  capacity: number;
  price: number;
  unlock_skill: string | null;
  unlock_level: number | null;
}

export interface InventoryRow {
  id: number;
  user_id: number;
  item_id: number;
  is_active: number;
  acquired_at: number;
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
  `);
}

/**
 * Item-Katalog (Kap. 6/19): Content ist datengetrieben — neue Gegenstände
 * sind nur neue Zeilen, kein neuer Code. Seed ist idempotent (Key-basiert).
 */
export function seedItems(db: Db): void {
  const insert = db.prepare(`
    INSERT OR IGNORE INTO items
      (key, category, name, tier, att_bonus, def_bonus, capacity, price, unlock_skill, unlock_level)
    VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
  `);
  const items: Array<
    [string, string, string, number, number, number, number, number, string | null, number | null]
  > = [
    // Waffen (freigeschaltet über den Angriff-Skill, Preise in Cent)
    ["weapon_1", "weapon", "Zerbrochene Flasche", 1, 2, 0, 0, 350, "angriff", 1],
    ["weapon_2", "weapon", "Stinkender Turnschuh", 2, 5, 0, 0, 1200, "angriff", 3],
    ["weapon_3", "weapon", "Alter Gehstock", 3, 9, 0, 0, 3500, "angriff", 6],
    ["weapon_4", "weapon", "Rostige Bratpfanne", 4, 15, 0, 0, 9000, "angriff", 10],
    // Behälter (erhöhen die Geld-Kapazität; Überlauf geht verloren, Kap. 3/6)
    ["container_1", "container", "Plastiktüte", 1, 0, 0, 15000, 800, null, null],
    ["container_2", "container", "Einkaufsbeutel", 2, 0, 0, 40000, 3000, null, null],
    ["container_3", "container", "Bauchtasche", 3, 0, 0, 120000, 10000, null, null],
    ["container_4", "container", "Einkaufswagen", 4, 0, 0, 500000, 40000, null, null],
  ];
  for (const row of items) insert.run(...row);
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
