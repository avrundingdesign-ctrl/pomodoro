import type { Db, UserRow } from "../db.js";
import { FORUM_CATEGORIES, GAME } from "../config.js";
import { now } from "../clock.js";

export type Res = { ok: true; msg: string; id?: number } | { ok: false; msg: string };
const ok = (msg: string, id?: number): Res => ({ ok: true, msg, id });
const err = (msg: string): Res => ({ ok: false, msg });

// ------------------------------------------------------------------- Chat

export interface ChatMessageView {
  id: number;
  username: string;
  body: string;
  sent_at: number;
}

export function chatMessages(db: Db, sinceId = 0): ChatMessageView[] {
  return (
    db
      .prepare(
        `SELECT c.id, u.username, c.body, c.sent_at
         FROM chat_messages c JOIN users u ON u.id = c.user_id
         WHERE c.id > ?
         ORDER BY c.id DESC LIMIT ?`,
      )
      .all(sinceId, GAME.CHAT_HISTORY_LIMIT) as unknown as ChatMessageView[]
  ).reverse();
}

export function sendChatMessage(db: Db, user: UserRow, bodyRaw: unknown): Res {
  const body = String(bodyRaw ?? "").trim();
  if (!body) return err("Ohne Text kein Spruch.");
  if (body.length > GAME.CHAT_MAX_LENGTH) {
    return err(`Maximal ${GAME.CHAT_MAX_LENGTH} Zeichen.`);
  }
  const recent = (
    db
      .prepare("SELECT COUNT(*) AS n FROM chat_messages WHERE user_id = ? AND sent_at > ?")
      .get(user.id, now() - 60_000) as unknown as { n: number }
  ).n;
  if (recent >= GAME.CHAT_MESSAGES_PER_MINUTE) {
    return err("Langsam — der Kanal ist keine Litfaßsäule.");
  }
  const result = db
    .prepare("INSERT INTO chat_messages (user_id, body, sent_at) VALUES (?, ?, ?)")
    .run(user.id, body, now());
  return ok("Gesendet.", Number(result.lastInsertRowid));
}

// ------------------------------------------------------------------- Forum

export function isValidCategory(category: string): boolean {
  return Object.hasOwn(FORUM_CATEGORIES, category);
}

function postRateLimited(db: Db, userId: number): boolean {
  const recent = (
    db
      .prepare("SELECT COUNT(*) AS n FROM forum_posts WHERE author_id = ? AND created_at > ?")
      .get(userId, now() - 3_600_000) as unknown as { n: number }
  ).n;
  return recent >= GAME.FORUM_POSTS_PER_HOUR;
}

export function createThread(
  db: Db,
  user: UserRow,
  gangId: number | null,
  categoryRaw: unknown,
  titleRaw: unknown,
  bodyRaw: unknown,
): Res {
  const category = gangId === null ? String(categoryRaw) : "bande";
  if (gangId === null && !isValidCategory(category)) {
    return err("Diese Rubrik gibt es nicht.");
  }
  const title = String(titleRaw ?? "").trim();
  const body = String(bodyRaw ?? "").trim();
  if (title.length < 3 || title.length > GAME.FORUM_TITLE_MAX) {
    return err(`Der Titel braucht 3–${GAME.FORUM_TITLE_MAX} Zeichen.`);
  }
  if (!body || body.length > GAME.FORUM_POST_MAX) {
    return err(`Der Beitrag braucht 1–${GAME.FORUM_POST_MAX} Zeichen.`);
  }
  if (postRateLimited(db, user.id)) return err("Genug geschrieben für diese Stunde.");
  const thread = db
    .prepare(
      `INSERT INTO forum_threads (gang_id, category, title, author_id, created_at, last_post_at)
       VALUES (?, ?, ?, ?, ?, ?)`,
    )
    .run(gangId, category, title, user.id, now(), now());
  const threadId = Number(thread.lastInsertRowid);
  db.prepare(
    "INSERT INTO forum_posts (thread_id, author_id, body, created_at) VALUES (?, ?, ?, ?)",
  ).run(threadId, user.id, body, now());
  return ok("Thema erstellt.", threadId);
}

export function replyToThread(
  db: Db,
  user: UserRow,
  threadIdRaw: unknown,
  bodyRaw: unknown,
  gangId: number | null,
): Res {
  const body = String(bodyRaw ?? "").trim();
  if (!body || body.length > GAME.FORUM_POST_MAX) {
    return err(`Der Beitrag braucht 1–${GAME.FORUM_POST_MAX} Zeichen.`);
  }
  const thread = db
    .prepare("SELECT * FROM forum_threads WHERE id = ?")
    .get(Number(threadIdRaw)) as unknown as
    | { id: number; gang_id: number | null }
    | undefined;
  if (!thread) return err("Dieses Thema gibt es nicht.");
  if ((thread.gang_id ?? null) !== gangId) return err("Dieses Thema liegt woanders.");
  if (postRateLimited(db, user.id)) return err("Genug geschrieben für diese Stunde.");
  db.prepare(
    "INSERT INTO forum_posts (thread_id, author_id, body, created_at) VALUES (?, ?, ?, ?)",
  ).run(thread.id, user.id, body, now());
  db.prepare("UPDATE forum_threads SET last_post_at = ? WHERE id = ?").run(now(), thread.id);
  return ok("Antwort gespeichert.", thread.id);
}

export function threadList(db: Db, gangId: number | null, category: string | null) {
  const where =
    gangId === null
      ? "gang_id IS NULL AND category = ?"
      : "gang_id = ?";
  const param = gangId === null ? category : gangId;
  return db
    .prepare(
      `SELECT t.*, u.username AS author_name,
              (SELECT COUNT(*) FROM forum_posts p WHERE p.thread_id = t.id) AS post_count
       FROM forum_threads t JOIN users u ON u.id = t.author_id
       WHERE ${where}
       ORDER BY t.last_post_at DESC LIMIT 50`,
    )
    .all(param) as unknown as Array<{
    id: number;
    title: string;
    author_name: string;
    created_at: number;
    last_post_at: number;
    post_count: number;
    gang_id: number | null;
    category: string;
  }>;
}

export function getThread(db: Db, threadIdRaw: unknown) {
  return db
    .prepare(
      `SELECT t.*, u.username AS author_name
       FROM forum_threads t JOIN users u ON u.id = t.author_id
       WHERE t.id = ?`,
    )
    .get(Number(threadIdRaw)) as unknown as
    | {
        id: number;
        gang_id: number | null;
        category: string;
        title: string;
        author_name: string;
        created_at: number;
      }
    | undefined;
}

export function threadPosts(db: Db, threadId: number) {
  return db
    .prepare(
      `SELECT p.*, u.username AS author_name
       FROM forum_posts p JOIN users u ON u.id = p.author_id
       WHERE p.thread_id = ?
       ORDER BY p.created_at ASC LIMIT 200`,
    )
    .all(threadId) as unknown as Array<{
    id: number;
    author_name: string;
    body: string;
    created_at: number;
  }>;
}

/** News-Feed für die Übersicht (Kap. 13): neueste Ankündigungs-Themen. */
export function latestAnnouncements(db: Db, limit = 3) {
  return db
    .prepare(
      `SELECT id, title, last_post_at FROM forum_threads
       WHERE gang_id IS NULL AND category = 'ankuendigungen'
       ORDER BY last_post_at DESC LIMIT ?`,
    )
    .all(limit) as unknown as Array<{ id: number; title: string; last_post_at: number }>;
}
