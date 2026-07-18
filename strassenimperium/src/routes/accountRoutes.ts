import { Router } from "express";
import type { Db, UserRow } from "../db.js";
import {
  hashPassword,
  requireAuth,
  setFlash,
  verifyPassword,
} from "../auth.js";
import { ACHIEVEMENT_TIER_NAMES, ACHIEVEMENTS, GAME } from "../config.js";
import * as svc from "../game/svc.js";

export function accountRoutes(db: Db): Router {
  const r = Router();
  r.use(requireAuth);

  // ------------------------------------------------------------ Auszeichnungen
  r.get("/auszeichnungen", (req, res) => {
    const user = res.locals.user as UserRow;
    const unlocked = db
      .prepare("SELECT type, tier, unlocked_at FROM achievements WHERE user_id = ?")
      .all(user.id) as unknown as Array<{ type: string; tier: number; unlocked_at: number }>;
    const unlockedMap = new Map(unlocked.map((a) => [`${a.type}:${a.tier}`, a.unlocked_at]));
    const rows = ACHIEVEMENTS.map((def) => ({
      def,
      progress: user[def.metric],
      tiers: def.thresholds.map((threshold, index) => ({
        tier: index + 1,
        tierName: ACHIEVEMENT_TIER_NAMES[index],
        threshold,
        unlockedAt: unlockedMap.get(`${def.type}:${index + 1}`) ?? null,
      })),
    }));
    res.render("auszeichnungen", {
      title: "Auszeichnungen",
      active: "auszeichnungen",
      rows,
      rankPoints: user.rank_points,
      showAchievements: user.show_achievements === 1,
    });
  });

  // -------------------------------------------------------------- Einstellungen
  r.get("/einstellungen", (req, res) => {
    const user = res.locals.user as UserRow;
    res.render("einstellungen", {
      title: "Einstellungen",
      active: "einstellungen",
      showAchievements: user.show_achievements === 1,
      onVacation: svc.isOnVacation(user),
      vacationUntil: user.vacation_until,
      vacationDaysLeft: svc.vacationDaysLeft(user),
      vacationDaysPerMonth: GAME.VACATION_DAYS_PER_MONTH,
    });
  });

  r.post("/einstellungen/anzeige", (req, res) => {
    const user = res.locals.user as UserRow;
    const show = (req.body as any).show_achievements === "1" ? 1 : 0;
    db.prepare("UPDATE users SET show_achievements = ? WHERE id = ?").run(show, user.id);
    setFlash(db, res.locals.session.token, {
      type: "ok",
      msg: show
        ? "Auszeichnungen sind jetzt öffentlich sichtbar."
        : "Auszeichnungen sind jetzt verborgen — niemand sieht, wie stark du wirklich bist.",
    });
    res.redirect("/einstellungen");
  });

  r.post("/einstellungen/passwort", (req, res) => {
    const user = res.locals.user as UserRow;
    const body = req.body as any;
    const fail = (msg: string) => {
      setFlash(db, res.locals.session.token, { type: "err", msg });
      res.redirect("/einstellungen");
    };
    if (!verifyPassword(String(body.aktuell ?? ""), user.password_hash)) {
      return fail("Das aktuelle Passwort stimmt nicht.");
    }
    const neu = String(body.neu ?? "");
    if (neu.length < 8) return fail("Das neue Passwort braucht mindestens 8 Zeichen.");
    if (neu !== String(body.neu2 ?? "")) return fail("Die neuen Passwörter stimmen nicht überein.");
    db.prepare("UPDATE users SET password_hash = ? WHERE id = ?").run(
      hashPassword(neu),
      user.id,
    );
    setFlash(db, res.locals.session.token, { type: "ok", msg: "Passwort geändert." });
    res.redirect("/einstellungen");
  });

  r.post("/einstellungen/urlaub/start", (req, res) => {
    const user = res.locals.user as UserRow;
    const result = svc.startVacation(db, user.id, (req.body as any).tage);
    setFlash(db, res.locals.session.token, {
      type: result.ok ? "ok" : "err",
      msg: result.msg,
    });
    res.redirect("/einstellungen");
  });

  r.post("/einstellungen/urlaub/ende", (req, res) => {
    const user = res.locals.user as UserRow;
    const result = svc.endVacation(db, user.id);
    setFlash(db, res.locals.session.token, {
      type: result.ok ? "ok" : "err",
      msg: result.msg,
    });
    res.redirect("/einstellungen");
  });

  return r;
}
