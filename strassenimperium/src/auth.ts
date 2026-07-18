import crypto from "node:crypto";
import type { NextFunction, Request, Response } from "express";
import type { Db, SessionRow, UserRow } from "./db.js";
import { now } from "./clock.js";
import { GAME } from "./config.js";

// ------------------------------------------------------------------ Passwörter

export function hashPassword(password: string): string {
  const salt = crypto.randomBytes(16);
  const hash = crypto.scryptSync(password, salt, 32);
  return `s1:${salt.toString("hex")}:${hash.toString("hex")}`;
}

export function verifyPassword(password: string, stored: string): boolean {
  const parts = stored.split(":");
  if (parts.length !== 3 || parts[0] !== "s1") return false;
  const salt = Buffer.from(parts[1], "hex");
  const expected = Buffer.from(parts[2], "hex");
  const actual = crypto.scryptSync(password, salt, 32);
  return (
    expected.length === actual.length && crypto.timingSafeEqual(expected, actual)
  );
}

// -------------------------------------------------------------------- Sessions

export function createSession(db: Db, userId: number): SessionRow {
  const token = crypto.randomBytes(24).toString("hex");
  const csrf = crypto.randomBytes(16).toString("hex");
  const t = now();
  db.prepare(
    `INSERT INTO sessions (token, user_id, csrf, created_at, expires_at)
     VALUES (?, ?, ?, ?, ?)`,
  ).run(token, userId, csrf, t, t + GAME.SESSION_TTL_MS);
  return {
    token,
    user_id: userId,
    csrf,
    flash: null,
    created_at: t,
    expires_at: t + GAME.SESSION_TTL_MS,
  };
}

export function destroySession(db: Db, token: string): void {
  db.prepare("DELETE FROM sessions WHERE token = ?").run(token);
}

function parseCookies(req: Request): Record<string, string> {
  const header = req.headers.cookie;
  const out: Record<string, string> = {};
  if (!header) return out;
  for (const part of header.split(";")) {
    const idx = part.indexOf("=");
    if (idx === -1) continue;
    out[part.slice(0, idx).trim()] = decodeURIComponent(part.slice(idx + 1).trim());
  }
  return out;
}

export function setSessionCookie(req: Request, res: Response, token: string): void {
  const secure =
    req.secure || req.headers["x-forwarded-proto"] === "https" ? "; Secure" : "";
  res.setHeader(
    "Set-Cookie",
    `sid=${token}; Path=/; HttpOnly; SameSite=Lax; Max-Age=${Math.floor(GAME.SESSION_TTL_MS / 1000)}${secure}`,
  );
}

export function clearSessionCookie(res: Response): void {
  res.setHeader("Set-Cookie", "sid=; Path=/; HttpOnly; SameSite=Lax; Max-Age=0");
}

// ----------------------------------------------------------- Flash-Nachrichten

export interface Flash {
  type: "ok" | "err";
  msg: string;
}

export function setFlash(db: Db, token: string, flash: Flash): void {
  const row = db
    .prepare("SELECT flash FROM sessions WHERE token = ?")
    .get(token) as unknown as { flash: string | null } | undefined;
  let flashes: Flash[] = [];
  if (row?.flash) {
    try {
      flashes = JSON.parse(row.flash) as Flash[];
    } catch {
      flashes = [];
    }
  }
  flashes.push(flash);
  db.prepare("UPDATE sessions SET flash = ? WHERE token = ?").run(
    JSON.stringify(flashes.slice(-3)),
    token,
  );
}

export function takeFlashes(db: Db, token: string): Flash[] {
  const row = db
    .prepare("SELECT flash FROM sessions WHERE token = ?")
    .get(token) as unknown as { flash: string | null } | undefined;
  if (!row?.flash) return [];
  db.prepare("UPDATE sessions SET flash = NULL WHERE token = ?").run(token);
  try {
    return JSON.parse(row.flash) as Flash[];
  } catch {
    return [];
  }
}

// ------------------------------------------------------------------ Middleware

/** Session + Nutzer laden und an res.locals hängen. */
export function attachSession(db: Db) {
  return (req: Request, res: Response, next: NextFunction) => {
    res.locals.user = null;
    res.locals.session = null;
    const token = parseCookies(req)["sid"];
    if (token) {
      db.prepare("DELETE FROM sessions WHERE expires_at <= ?").run(now());
      const session = db
        .prepare("SELECT * FROM sessions WHERE token = ? AND expires_at > ?")
        .get(token, now()) as unknown as SessionRow | undefined;
      if (session) {
        const user = db
          .prepare("SELECT * FROM users WHERE id = ?")
          .get(session.user_id) as unknown as UserRow | undefined;
        if (user) {
          res.locals.session = session;
          res.locals.user = user;
        }
      }
    }
    next();
  };
}

export function requireAuth(req: Request, res: Response, next: NextFunction): void {
  if (!res.locals.user) {
    res.redirect("/login");
    return;
  }
  next();
}

/** CSRF-Schutz für alle eingeloggten POSTs (Token pro Session). */
export function csrfProtect(req: Request, res: Response, next: NextFunction): void {
  if (req.method !== "POST") return next();
  if (req.path === "/login" || req.path === "/registrieren") return next();
  const session = res.locals.session as SessionRow | null;
  const sent = (req.body as Record<string, unknown>)?._csrf;
  if (!session || sent !== session.csrf) {
    res.status(403).render("error", {
      title: "Verboten",
      code: 403,
      message: "Ungültiges oder fehlendes Sicherheits-Token. Bitte Seite neu laden.",
    });
    return;
  }
  next();
}

// ------------------------------------------------- simples Login-Rate-Limiting

const attempts = new Map<string, { count: number; resetAt: number }>();

export function loginRateLimited(key: string): boolean {
  const t = Date.now();
  const entry = attempts.get(key);
  if (!entry || entry.resetAt <= t) {
    attempts.set(key, { count: 1, resetAt: t + 15 * 60_000 });
    return false;
  }
  entry.count++;
  if (attempts.size > 10_000) attempts.clear();
  return entry.count > 20;
}
