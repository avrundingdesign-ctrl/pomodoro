import express from "express";
import type { Db, UserRow } from "./db.js";
import { PUBLIC_DIR, VIEWS_DIR } from "./paths.js";
import { GAME, TIME_SCALE } from "./config.js";
import { now } from "./clock.js";
import { attachSession, csrfProtect, setFlash, takeFlashes } from "./auth.js";
import { resolveAllDue } from "./game/resolve.js";
import { effectiveStats, rankOf } from "./game/stats.js";
import { collectMusicIncome, kursToday } from "./game/svc.js";
import { districtOf } from "./game/districts.js";
import { fmtPromille, moodLabel, promilleOf } from "./game/promille.js";
import { hashIp, recordDonationClick } from "./game/donation.js";
import { unreadCount } from "./game/social.js";
import { activeEvent } from "./game/events.js";
import { fmtDateTime, fmtDuration, fmtMoney } from "./util.js";
import { authRoutes } from "./routes/authRoutes.js";
import { gameRoutes } from "./routes/gameRoutes.js";
import { inventoryRoutes } from "./routes/inventoryRoutes.js";
import { fightRoutes } from "./routes/fightRoutes.js";
import { stadtRoutes } from "./routes/stadtRoutes.js";
import { socialRoutes } from "./routes/socialRoutes.js";
import { gangRoutes } from "./routes/gangRoutes.js";
import { accountRoutes } from "./routes/accountRoutes.js";
import { communityRoutes } from "./routes/communityRoutes.js";

export function createApp(db: Db): express.Express {
  const app = express();
  app.set("view engine", "ejs");
  app.set("views", VIEWS_DIR);
  app.set("trust proxy", true);
  app.disable("x-powered-by");

  // Template-Helfer
  app.locals.fmtMoney = fmtMoney;
  app.locals.fmtDuration = fmtDuration;
  app.locals.fmtDateTime = fmtDateTime;
  app.locals.GAME = GAME;
  app.locals.TIME_SCALE = TIME_SCALE;

  app.use(express.urlencoded({ extended: false }));
  app.use(express.static(PUBLIC_DIR, { maxAge: "1h" }));

  app.use(attachSession(db));

  // Idle-Kern: fällige Timer bei jedem Request serverseitig auflösen.
  app.use((req, res, next) => {
    try {
      resolveAllDue(db);
    } catch (err) {
      console.error("Timer-Auflösung fehlgeschlagen:", err);
    }
    next();
  });

  // Nach der Auflösung: frische Nutzerdaten + Kopfzeilen-Status bereitstellen.
  app.use((req, res, next) => {
    res.locals.serverNow = now();
    res.locals.csrf = res.locals.session?.csrf ?? "";
    res.locals.flashes = [];
    res.locals.seasonEvent = activeEvent();
    if (res.locals.user) {
      // Online-Status (Kap. 10): höchstens einmal pro Minute schreiben.
      const seen = res.locals.user as UserRow;
      if (seen.last_seen_at < Date.now() - 60_000) {
        db.prepare("UPDATE users SET last_seen_at = ? WHERE id = ?").run(
          Date.now(),
          seen.id,
        );
      }
      // Straßenmusik-Einnahmen lazy abrechnen, bevor Status & Flashes gelesen werden.
      const music = collectMusicIncome(db, (res.locals.user as UserRow).id);
      if (music && music.periods > 0 && res.locals.session) {
        let msg = `🎶 Straßenmusik: ${music.periods} Auftritt${music.periods > 1 ? "e" : ""}, +${fmtMoney(music.added)}.`;
        if (music.lost > 0) msg += ` ${fmtMoney(music.lost)} passten nicht in deinen Behälter!`;
        setFlash(db, res.locals.session.token, { type: "ok", msg });
      }
      const fresh = db
        .prepare("SELECT * FROM users WHERE id = ?")
        .get((res.locals.user as UserRow).id) as unknown as UserRow;
      res.locals.user = fresh;
      const stats = effectiveStats(db, fresh.id);
      const promille = promilleOf(fresh);
      res.locals.status = {
        money: fresh.money,
        capacity: stats.capacity,
        bottles: fresh.bottles,
        points: fresh.points,
        rank: rankOf(db, fresh),
        att: stats.attEff,
        def: stats.defEff,
        geschick: stats.skills.geschick,
        kurs: kursToday(),
        cleanliness: fresh.cleanliness,
        promille,
        promilleLabel: fmtPromille(promille),
        mood: moodLabel(promille),
        districtName: districtOf(db, fresh).name,
        unreadMessages: unreadCount(db, fresh.id),
        onVacation: fresh.vacation_until > now(),
        vacationUntil: fresh.vacation_until,
      };
      if (res.locals.session) {
        res.locals.flashes = takeFlashes(db, res.locals.session.token);
      }
    }
    next();
  });

  app.use(csrfProtect);

  app.get("/", (req, res) => {
    res.redirect(res.locals.user ? "/uebersicht" : "/login");
  });
  app.get("/healthz", (req, res) => {
    res.json({ ok: true, now: now() });
  });

  /**
   * Öffentlicher Spendenlink (Kap. 5/10): bewusst OHNE Login erreichbar —
   * jeder Klick eines Dritten zahlt dem Besitzer einen kleinen Betrag aus
   * (dedupliziert pro Quelle und Tag, mit Tagesdeckel).
   */
  app.get("/spende/:code", (req, res) => {
    const code = String(req.params.code);
    const owner = db
      .prepare("SELECT * FROM users WHERE donation_code = ?")
      .get(code) as unknown as UserRow | undefined;
    if (!owner) {
      return res.status(404).render("error", {
        title: "Nicht gefunden",
        code: 404,
        message: "Dieser Spendenlink ist abgelaufen oder hat nie existiert.",
      });
    }
    const result = recordDonationClick(db, owner, hashIp(req.ip ?? "?", code));
    res.render("spende", {
      title: "Spende",
      ownerName: owner.username,
      result,
    });
  });

  app.use(authRoutes(db));
  app.use(gameRoutes(db));
  app.use(inventoryRoutes(db));
  app.use(fightRoutes(db));
  app.use(stadtRoutes(db));
  app.use(socialRoutes(db));
  app.use(gangRoutes(db));
  app.use(accountRoutes(db));
  app.use(communityRoutes(db));

  app.use((req, res) => {
    res.status(404).render("error", {
      title: "Nicht gefunden",
      code: 404,
      message: "Diese Straßenecke gibt es nicht.",
    });
  });

  const errorHandler: express.ErrorRequestHandler = (err, req, res, next) => {
    console.error("Unerwarteter Fehler:", err);
    if (res.headersSent) return next(err);
    res.status(500).render("error", {
      title: "Serverfehler",
      code: 500,
      message: "Da ist etwas gründlich schiefgelaufen. Versuch es gleich noch einmal.",
    });
  };
  app.use(errorHandler);

  return app;
}
