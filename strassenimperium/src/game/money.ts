import type { Db, ItemRow, UserRow } from "../db.js";
import { GAME } from "../config.js";

/** Aktiver Behälter des Spielers (oder null = Hosentasche). */
export function activeContainer(db: Db, userId: number): ItemRow | null {
  const row = db
    .prepare(
      `SELECT items.* FROM inventory
       JOIN items ON items.id = inventory.item_id
       WHERE inventory.user_id = ? AND inventory.is_active = 1
         AND items.category = 'container'
       LIMIT 1`,
    )
    .get(userId) as unknown as ItemRow | undefined;
  return row ?? null;
}

/** Maximale Geld-Kapazität in Cent (Kap. 3: Überlauf = Verlust!). */
export function capacityFor(db: Db, userId: number): number {
  const c = activeContainer(db, userId);
  return c ? c.capacity : GAME.BASE_CAPACITY;
}

export interface AddMoneyResult {
  added: number;
  lost: number;
  newBalance: number;
}

/**
 * Geld gutschreiben, hart begrenzt durch die Behälter-Kapazität.
 * Alles über der Kapazität geht verloren — das zentrale Geld-Sink-Prinzip
 * der Vorlage.
 */
export function addMoney(db: Db, userId: number, amount: number): AddMoneyResult {
  const user = db
    .prepare("SELECT money FROM users WHERE id = ?")
    .get(userId) as unknown as Pick<UserRow, "money">;
  const cap = capacityFor(db, userId);
  // Nie reduzieren: Läge der Kontostand (durch was auch immer) über der
  // Kapazität, verfällt nur der Neuzugang — Bestand bleibt unangetastet.
  const target = Math.max(user.money, Math.min(cap, user.money + amount));
  const added = Math.max(0, target - user.money);
  const lost = Math.max(0, amount - added);
  db.prepare("UPDATE users SET money = ? WHERE id = ?").run(target, userId);
  return { added, lost, newBalance: target };
}

/**
 * Nach Behälter-Wechsel/-Verkauf: Bargeld auf die neue Kapazität stutzen.
 * Liefert den verlorenen Betrag (0, wenn alles passte).
 */
export function clampToCapacity(db: Db, userId: number): number {
  const user = db
    .prepare("SELECT money FROM users WHERE id = ?")
    .get(userId) as unknown as Pick<UserRow, "money">;
  const cap = capacityFor(db, userId);
  if (user.money <= cap) return 0;
  const lost = user.money - cap;
  db.prepare("UPDATE users SET money = ? WHERE id = ?").run(cap, userId);
  return lost;
}
