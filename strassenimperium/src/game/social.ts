import type { Db, MessageRow, UserRow } from "../db.js";
import { withTx } from "../db.js";
import { GAME } from "../config.js";
import { now } from "../clock.js";

export type Res = { ok: true; msg: string } | { ok: false; msg: string };
const ok = (msg: string): Res => ({ ok: true, msg });
const err = (msg: string): Res => ({ ok: false, msg });

// ------------------------------------------------------- Freunde & Blockliste

export function findUserByName(db: Db, nameRaw: unknown): UserRow | undefined {
  return db
    .prepare("SELECT * FROM users WHERE username = ?")
    .get(String(nameRaw ?? "").trim()) as unknown as UserRow | undefined;
}

export function addRelation(
  db: Db,
  user: UserRow,
  otherNameRaw: unknown,
  type: "friend" | "block",
): Res {
  const other = findUserByName(db, otherNameRaw);
  if (!other) return err("Diesen Spieler kennt hier niemand.");
  if (other.id === user.id) {
    return err(type === "friend" ? "Du bist dir selbst Freund genug." : "Dich selbst blockieren? Mutig.");
  }
  const inserted = db
    .prepare(
      `INSERT OR IGNORE INTO friends (user_id, other_user_id, type, created_at)
       VALUES (?, ?, ?, ?)`,
    )
    .run(user.id, other.id, type, now());
  if (inserted.changes === 0) {
    return err(`${other.username} steht schon auf dieser Liste.`);
  }
  return ok(
    type === "friend"
      ? `${other.username} steht jetzt auf deiner Freundesliste.`
      : `${other.username} ist blockiert und kann dir nicht mehr schreiben.`,
  );
}

export function removeRelation(
  db: Db,
  user: UserRow,
  relationIdRaw: unknown,
): Res {
  const result = db
    .prepare("DELETE FROM friends WHERE id = ? AND user_id = ?")
    .run(Number(relationIdRaw), user.id);
  return result.changes > 0 ? ok("Eintrag entfernt.") : err("Eintrag nicht gefunden.");
}

export function updateNote(db: Db, user: UserRow, relationIdRaw: unknown, noteRaw: unknown): Res {
  const note = String(noteRaw ?? "").slice(0, 200);
  const result = db
    .prepare("UPDATE friends SET note = ? WHERE id = ? AND user_id = ? AND type = 'friend'")
    .run(note, Number(relationIdRaw), user.id);
  return result.changes > 0 ? ok("Notiz gespeichert.") : err("Eintrag nicht gefunden.");
}

export interface RelationView {
  id: number;
  username: string;
  note: string;
  online: boolean;
  otherUserId: number;
}

export function listRelations(db: Db, userId: number, type: "friend" | "block"): RelationView[] {
  const windowMs = GAME.ONLINE_WINDOW_MINUTES * 60_000;
  const rows = db
    .prepare(
      `SELECT friends.id, friends.note, users.username, users.last_seen_at,
              users.id AS other_id
       FROM friends JOIN users ON users.id = friends.other_user_id
       WHERE friends.user_id = ? AND friends.type = ?
       ORDER BY users.username COLLATE NOCASE`,
    )
    .all(userId, type) as unknown as Array<{
    id: number;
    note: string;
    username: string;
    last_seen_at: number;
    other_id: number;
  }>;
  return rows.map((r) => ({
    id: r.id,
    username: r.username,
    note: r.note,
    online: r.last_seen_at > Date.now() - windowMs,
    otherUserId: r.other_id,
  }));
}

export function isBlocked(db: Db, byUserId: number, whoUserId: number): boolean {
  return !!db
    .prepare(
      "SELECT id FROM friends WHERE user_id = ? AND other_user_id = ? AND type = 'block'",
    )
    .get(byUserId, whoUserId);
}

// ---------------------------------------------------------------- Nachrichten

export function sendMessage(
  db: Db,
  sender: UserRow,
  recipientNameRaw: unknown,
  bodyRaw: unknown,
): Res {
  const body = String(bodyRaw ?? "").trim();
  if (body.length === 0) return err("Ohne Text keine Nachricht.");
  if (body.length > GAME.MESSAGE_MAX_LENGTH) {
    return err(`Maximal ${GAME.MESSAGE_MAX_LENGTH} Zeichen.`);
  }
  const recipient = findUserByName(db, recipientNameRaw);
  if (!recipient) return err("Diesen Empfänger kennt hier niemand.");
  if (recipient.id === sender.id) return err("Selbstgespräche führst du bitte offline.");
  if (isBlocked(db, recipient.id, sender.id)) {
    return err(`${recipient.username} will nichts von dir hören (blockiert).`);
  }
  const recentCount = (
    db
      .prepare("SELECT COUNT(*) AS n FROM messages WHERE sender_id = ? AND sent_at > ?")
      .get(sender.id, now() - 3_600_000) as unknown as { n: number }
  ).n;
  if (recentCount >= GAME.MESSAGES_PER_HOUR) {
    return err("Genug geschrieben für diese Stunde — gönn deinem Stift eine Pause.");
  }
  db.prepare(
    "INSERT INTO messages (sender_id, recipient_id, body, sent_at) VALUES (?, ?, ?, ?)",
  ).run(sender.id, recipient.id, body, now());
  return ok(`Nachricht an ${recipient.username} geschickt.`);
}

export interface MessageView extends MessageRow {
  sender_name: string;
  recipient_name: string;
}

export function mailbox(
  db: Db,
  userId: number,
  box: "eingang" | "gesendet" | "archiv",
): MessageView[] {
  let where: string;
  if (box === "eingang") {
    where =
      "recipient_id = ? AND recipient_deleted = 0 AND recipient_archived = 0";
  } else if (box === "gesendet") {
    where = "sender_id = ? AND sender_deleted = 0 AND sender_archived = 0";
  } else {
    where = `((recipient_id = ? AND recipient_deleted = 0 AND recipient_archived = 1)
              OR (sender_id = ? AND sender_deleted = 0 AND sender_archived = 1))`;
  }
  const params = box === "archiv" ? [userId, userId] : [userId];
  return db
    .prepare(
      `SELECT messages.*, s.username AS sender_name, r.username AS recipient_name
       FROM messages
       JOIN users s ON s.id = messages.sender_id
       JOIN users r ON r.id = messages.recipient_id
       WHERE ${where}
       ORDER BY sent_at DESC LIMIT 100`,
    )
    .all(...params) as unknown as MessageView[];
}

export function unreadCount(db: Db, userId: number): number {
  return (
    db
      .prepare(
        `SELECT COUNT(*) AS n FROM messages
         WHERE recipient_id = ? AND read_at IS NULL AND recipient_deleted = 0`,
      )
      .get(userId) as unknown as { n: number }
  ).n;
}

export function getMessage(db: Db, userId: number, idRaw: unknown): MessageView | undefined {
  const message = db
    .prepare(
      `SELECT messages.*, s.username AS sender_name, r.username AS recipient_name
       FROM messages
       JOIN users s ON s.id = messages.sender_id
       JOIN users r ON r.id = messages.recipient_id
       WHERE messages.id = ? AND (sender_id = ? OR recipient_id = ?)`,
    )
    .get(Number(idRaw), userId, userId) as unknown as MessageView | undefined;
  if (message && message.recipient_id === userId && !message.read_at) {
    db.prepare("UPDATE messages SET read_at = ? WHERE id = ?").run(now(), message.id);
    message.read_at = now();
  }
  return message;
}

export function archiveMessage(db: Db, userId: number, idRaw: unknown): Res {
  return messageFlag(db, userId, idRaw, "archived", 1, "Nachricht archiviert.");
}

export function deleteMessage(db: Db, userId: number, idRaw: unknown): Res {
  return messageFlag(db, userId, idRaw, "deleted", 1, "Nachricht gelöscht.");
}

function messageFlag(
  db: Db,
  userId: number,
  idRaw: unknown,
  flag: "archived" | "deleted",
  value: number,
  okMsg: string,
): Res {
  return withTx(db, () => {
    const message = db
      .prepare("SELECT * FROM messages WHERE id = ?")
      .get(Number(idRaw)) as unknown as MessageRow | undefined;
    if (!message || (message.sender_id !== userId && message.recipient_id !== userId)) {
      return err("Nachricht nicht gefunden.");
    }
    const column =
      message.recipient_id === userId ? `recipient_${flag}` : `sender_${flag}`;
    db.prepare(`UPDATE messages SET ${column} = ? WHERE id = ?`).run(value, message.id);
    return ok(okMsg);
  });
}
