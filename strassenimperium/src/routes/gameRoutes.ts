import { Router } from "express";
import type { ActionRow, Db, UserRow } from "../db.js";
import { requireAuth, setFlash } from "../auth.js";
import { GAME, SKILL_INFO, SKILL_TYPES, scaledMs } from "../config.js";
import {
  collectYield,
  trainingCost,
  trainingDurationMinutes,
} from "../game/formulas.js";
import { effectiveStats } from "../game/stats.js";
import { fightDisplay, type FightRowNamed, type LogEntry } from "../game/logtext.js";
import * as svc from "../game/svc.js";
import { fmtDuration } from "../util.js";

interface PendingAttackRow extends ActionRow {
  defender_name: string | null;
}

export function gameRoutes(db: Db): Router {
  const r = Router();
  r.use(requireAuth);

  // ------------------------------------------------------------- Übersicht
  r.get("/uebersicht", (req, res) => {
    const user = res.locals.user as UserRow;
    const stats = effectiveStats(db, user.id);
    const trainings = svc.activeTrainings(db, user.id);
    const action = svc.activePhysicalAction(db, user.id) as PendingAttackRow | null;
    if (action?.type === "kampf" && action.target_user_id) {
      const target = svc.getUser(db, action.target_user_id);
      action.defender_name = target?.username ?? "???";
    }
    const incoming =
      stats.skills.geschick >= GAME.INCOMING_VISIBLE_AT_SKILL
        ? svc.incomingAttacks(db, user.id)
        : null;

    // Letzte Ereignisse: aufgelöste Sammelaktionen + Kämpfe, gemischt.
    const recentActions = db
      .prepare(
        `SELECT * FROM actions
         WHERE user_id = ? AND resolved_at IS NOT NULL AND type = 'sammeln'
         ORDER BY resolved_at DESC LIMIT 4`,
      )
      .all(user.id) as unknown as ActionRow[];
    const recentFights = db
      .prepare(
        `SELECT f.*, ua.username AS attacker_name, ud.username AS defender_name
         FROM fights f
         JOIN users ua ON ua.id = f.attacker_id
         JOIN users ud ON ud.id = f.defender_id
         WHERE f.attacker_id = ? OR f.defender_id = ?
         ORDER BY f.occurred_at DESC LIMIT 4`,
      )
      .all(user.id, user.id) as unknown as FightRowNamed[];
    const events: LogEntry[] = [
      ...recentActions.map((a) => {
        const result = JSON.parse(a.result ?? "{}") as { bottles?: number; minutes?: number };
        return {
          ts: a.resolved_at ?? a.ends_at,
          cls: "draw" as const,
          text: `Sammeln (${fmtDuration((result.minutes ?? 0) * 60_000)}): ${result.bottles ?? 0} Pfandflaschen mitgebracht.`,
        };
      }),
      ...recentFights.map((f) => fightDisplay(f, user.id)),
    ]
      .sort((a, b) => b.ts - a.ts)
      .slice(0, 6);

    res.render("dashboard", {
      title: "Übersicht",
      active: "uebersicht",
      stats,
      trainings,
      action,
      incoming,
      events,
      kurs: svc.kursToday(),
      skillInfo: SKILL_INFO,
    });
  });

  // ---------------------------------------------------------- Weiterbildung
  r.get("/weiterbildung", (req, res) => {
    const user = res.locals.user as UserRow;
    const stats = effectiveStats(db, user.id);
    const trainings = svc.activeTrainings(db, user.id);
    const slotsFree = GAME.MAX_PARALLEL_TRAININGS - trainings.length;
    const offers = SKILL_TYPES.map((type) => {
      const level = stats.skills[type];
      const target = level + 1;
      const cost = trainingCost(target);
      const durationMs = scaledMs(trainingDurationMinutes(target) * 60_000);
      const alreadyRunning = trainings.some((t) => t.skill_type === type);
      let blocked: string | null = null;
      if (alreadyRunning) blocked = "läuft bereits";
      else if (slotsFree <= 0) blocked = "kein Platz frei";
      else if (user.money < cost) blocked = "zu teuer";
      return {
        type,
        name: SKILL_INFO[type].name,
        effect: SKILL_INFO[type].effect,
        level,
        target,
        cost,
        durationMs,
        blocked,
      };
    });
    res.render("weiterbildung", {
      title: "Weiterbildung",
      active: "weiterbildung",
      trainings,
      slotsFree,
      offers,
      skillInfo: SKILL_INFO,
    });
  });

  r.post("/weiterbildung/start", (req, res) => {
    const user = res.locals.user as UserRow;
    const result = svc.startTraining(db, user.id, (req.body as any).skill);
    setFlash(db, res.locals.session.token, {
      type: result.ok ? "ok" : "err",
      msg: result.msg,
    });
    res.redirect("/weiterbildung");
  });

  // ---------------------------------------------------------------- Sammeln
  r.get("/aktionen/sammeln", (req, res) => {
    const user = res.locals.user as UserRow;
    const stats = effectiveStats(db, user.id);
    const action = svc.activePhysicalAction(db, user.id);
    const kurs = svc.kursToday();
    const options = GAME.COLLECT_MINUTES.map((minutes) => {
      const bottles = collectYield(minutes, stats.skills.geschick);
      return {
        minutes,
        label: fmtDuration(minutes * 60_000),
        bottles,
        estCents: bottles * kurs,
        perHour: Math.round((bottles / minutes) * 60),
      };
    });
    res.render("sammeln", {
      title: "Flaschen sammeln",
      active: "sammeln",
      action,
      options,
      kurs,
      geschick: stats.skills.geschick,
    });
  });

  r.post("/aktionen/sammeln/start", (req, res) => {
    const user = res.locals.user as UserRow;
    const result = svc.startCollect(db, user.id, (req.body as any).minutes);
    setFlash(db, res.locals.session.token, {
      type: result.ok ? "ok" : "err",
      msg: result.msg,
    });
    res.redirect(result.ok ? "/uebersicht" : "/aktionen/sammeln");
  });

  return r;
}
