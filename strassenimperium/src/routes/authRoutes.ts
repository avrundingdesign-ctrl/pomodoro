import crypto from "node:crypto";
import { Router } from "express";
import type { Db, UserRow } from "../db.js";
import { withTx } from "../db.js";
import { now } from "../clock.js";
import { GAME, SKILL_TYPES } from "../config.js";
import {
  clearSessionCookie,
  createSession,
  destroySession,
  hashPassword,
  loginRateLimited,
  setSessionCookie,
  verifyPassword,
} from "../auth.js";

const USERNAME_RE = /^[A-Za-z0-9_]{3,20}$/;
const EMAIL_RE = /^\S+@\S+\.\S+$/;

export function authRoutes(db: Db): Router {
  const r = Router();

  r.get("/login", (req, res) => {
    if (res.locals.user) return res.redirect("/uebersicht");
    res.render("login", { title: "Anmelden", error: null, values: {} });
  });

  r.post("/login", (req, res) => {
    const body = req.body as Record<string, string>;
    const identifier = (body.identifier ?? "").trim();
    const password = body.password ?? "";
    const fail = (error: string) =>
      res.status(401).render("login", {
        title: "Anmelden",
        error,
        values: { identifier },
      });
    if (loginRateLimited(`${req.ip}`)) {
      return fail("Zu viele Versuche — warte eine Viertelstunde.");
    }
    const user = db
      .prepare("SELECT * FROM users WHERE username = ? OR email = ?")
      .get(identifier, identifier.toLowerCase()) as unknown as UserRow | undefined;
    if (!user || !verifyPassword(password, user.password_hash)) {
      return fail("Name/E-Mail oder Passwort ist falsch.");
    }
    db.prepare("UPDATE users SET last_login_at = ? WHERE id = ?").run(now(), user.id);
    const session = createSession(db, user.id);
    setSessionCookie(req, res, session.token);
    res.redirect("/uebersicht");
  });

  r.get("/registrieren", (req, res) => {
    if (res.locals.user) return res.redirect("/uebersicht");
    res.render("register", { title: "Registrieren", error: null, values: {} });
  });

  r.post("/registrieren", (req, res) => {
    const body = req.body as Record<string, string>;
    const username = (body.username ?? "").trim();
    const email = (body.email ?? "").trim().toLowerCase();
    const password = body.password ?? "";
    const password2 = body.password2 ?? "";
    const fail = (error: string) =>
      res.status(400).render("register", {
        title: "Registrieren",
        error,
        values: { username, email },
      });

    if (!USERNAME_RE.test(username)) {
      return fail("Der Name braucht 3–20 Zeichen: Buchstaben, Zahlen, Unterstrich.");
    }
    if (!EMAIL_RE.test(email)) return fail("Das sieht nicht nach einer E-Mail-Adresse aus.");
    if (password.length < 8) return fail("Das Passwort braucht mindestens 8 Zeichen.");
    if (password !== password2) return fail("Die Passwörter stimmen nicht überein.");

    const existing = db
      .prepare("SELECT id FROM users WHERE username = ? OR email = ?")
      .get(username, email);
    if (existing) return fail("Name oder E-Mail ist schon vergeben.");

    const userId = withTx(db, () => {
      const result = db
        .prepare(
          `INSERT INTO users (username, email, password_hash, created_at, money,
                              cleanliness, donation_code)
           VALUES (?, ?, ?, ?, ?, ?, ?)`,
        )
        .run(
          username,
          email,
          hashPassword(password),
          now(),
          GAME.START_MONEY,
          GAME.CLEANLINESS_START,
          crypto.randomBytes(8).toString("hex"),
        );
      const id = Number(result.lastInsertRowid);
      const skill = db.prepare(
        "INSERT INTO skills (user_id, type, level) VALUES (?, ?, 0)",
      );
      for (const type of SKILL_TYPES) skill.run(id, type);
      return id;
    });

    const session = createSession(db, userId);
    setSessionCookie(req, res, session.token);
    res.redirect("/uebersicht");
  });

  r.post("/logout", (req, res) => {
    const session = res.locals.session;
    if (session) destroySession(db, session.token);
    clearSessionCookie(res);
    res.redirect("/login");
  });

  return r;
}
