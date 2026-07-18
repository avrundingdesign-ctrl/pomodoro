import { Router } from "express";
import type { ActionRow, Db, UserRow } from "../db.js";
import { requireAuth, setFlash } from "../auth.js";
import { CRIMES, GAME, SKILL_INFO, SKILL_TYPES, scaledMs } from "../config.js";
import { now as nowMs } from "../clock.js";
import {
  collectYield,
  trainingCost,
  trainingDurationMinutes,
} from "../game/formulas.js";
import { effectiveStats } from "../game/stats.js";
import { fightDisplay, type FightRowNamed, type LogEntry } from "../game/logtext.js";
import * as svc from "../game/svc.js";
import { districtOf } from "../game/districts.js";
import {
  donationBreakdown,
  donationStatsToday,
  renewDonationCode,
} from "../game/donation.js";
import { moodLabel, promilleOf } from "../game/promille.js";
import { fmtDuration, fmtMoney } from "../util.js";

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

    // Letzte Ereignisse: aufgelöste Sammel-/Verbrechensaktionen + Kämpfe, gemischt.
    const recentActions = db
      .prepare(
        `SELECT * FROM actions
         WHERE user_id = ? AND resolved_at IS NOT NULL AND type IN ('sammeln', 'verbrechen')
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
      ...recentActions.map((a): LogEntry => {
        const ts = a.resolved_at ?? a.ends_at;
        if (a.type === "verbrechen") {
          const r = JSON.parse(a.result ?? "{}") as {
            success?: boolean;
            kept?: number;
            lost?: number;
            fine?: number;
          };
          const payload = JSON.parse(a.payload ?? "{}") as { key?: string };
          const name = CRIMES.find((c) => c.key === payload.key)?.name ?? "Verbrechen";
          if (r.success) {
            const overflow =
              (r.lost ?? 0) > 0
                ? ` (${fmtMoney(r.lost ?? 0)} passten nicht in den Behälter)`
                : "";
            return {
              ts,
              cls: "win",
              text: `„${name}“ geglückt: +${fmtMoney(r.kept ?? 0)}${overflow}.`,
            };
          }
          return {
            ts,
            cls: "loss",
            text: `„${name}“ ging schief — erwischt! Strafe: ${fmtMoney(r.fine ?? 0)}.`,
          };
        }
        const result = JSON.parse(a.result ?? "{}") as { bottles?: number; minutes?: number };
        return {
          ts,
          cls: "draw",
          text: `Sammeln (${fmtDuration((result.minutes ?? 0) * 60_000)}): ${result.bottles ?? 0} Pfandflaschen mitgebracht.`,
        };
      }),
      ...recentFights.map((f) => fightDisplay(f, user.id)),
    ]
      .sort((a, b) => b.ts - a.ts)
      .slice(0, 6);

    const promille = promilleOf(user);
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
      district: districtOf(db, user),
      promille,
      mood: moodLabel(promille),
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
      const maxLevel = GAME.SKILL_MAX_LEVEL[type];
      const maxed = maxLevel !== undefined && target > maxLevel;
      const cost = trainingCost(target);
      const durationMs = scaledMs(trainingDurationMinutes(target) * 60_000);
      const alreadyRunning = trainings.some((t) => t.skill_type === type);
      let blocked: string | null = null;
      if (maxed) blocked = `Maximalstufe ${maxLevel}`;
      else if (alreadyRunning) blocked = "läuft bereits";
      else if (slotsFree <= 0) blocked = "kein Platz frei";
      else if (user.money < cost) blocked = "zu teuer";
      return {
        type,
        name: SKILL_INFO[type].name,
        effect: SKILL_INFO[type].effect,
        level,
        target,
        maxed,
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
    const district = districtOf(db, user);
    const options = GAME.COLLECT_MINUTES.map((minutes) => {
      const bottles = collectYield(minutes, stats.skills.geschick, district.factor);
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
      district,
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

  // -------------------------------------------------------------- Verbrechen
  r.get("/aktionen/verbrechen", (req, res) => {
    const user = res.locals.user as UserRow;
    const stats = effectiveStats(db, user.id);
    const action = svc.activePhysicalAction(db, user.id);
    const crimes = CRIMES.map((c) => {
      const check = svc.crimeRequirementCheck(db, user.id, c);
      return {
        ...c,
        chance: Math.round(svc.crimeChance(c, stats.skills.geschick) * 100),
        durationLabel: fmtDuration(c.minutes * 60_000),
        blocked: check.ok ? null : check.msg,
      };
    });
    res.render("verbrechen", {
      title: "Verbrechen",
      active: "verbrechen",
      action,
      crimes,
      geschick: stats.skills.geschick,
      homeTier: stats.home?.tier ?? 0,
    });
  });

  r.post("/aktionen/verbrechen/start", (req, res) => {
    const user = res.locals.user as UserRow;
    const result = svc.startCrime(db, user.id, (req.body as any).key);
    setFlash(db, res.locals.session.token, {
      type: result.ok ? "ok" : "err",
      msg: result.msg,
    });
    res.redirect(result.ok ? "/uebersicht" : "/aktionen/verbrechen");
  });

  // ----------------------------------------------------------- Konzentrieren
  r.get("/aktionen/konzentrieren", (req, res) => {
    const user = res.locals.user as UserRow;
    const stats = effectiveStats(db, user.id);
    const level = stats.skills.konzentration;
    const cooldownMs = scaledMs(GAME.KONZ_COOLDOWN_HOURS * 3_600_000);
    const readyAt = user.last_concentrated_at + cooldownMs;
    res.render("konzentrieren", {
      title: "Konzentrieren",
      active: "weiterbildung",
      level,
      boostPercent: Math.round(GAME.KONZ_BOOST_PER_LEVEL * level * 100),
      combinable: level >= GAME.KONZ_COMBINABLE_AT,
      combinableAt: GAME.KONZ_COMBINABLE_AT,
      readyAt: readyAt > nowMs() ? readyAt : null,
      running: svc.activeTrainings(db, user.id),
      skillInfo: SKILL_INFO,
    });
  });

  r.post("/aktionen/konzentrieren", (req, res) => {
    const user = res.locals.user as UserRow;
    const result = svc.concentrate(db, user.id);
    setFlash(db, res.locals.session.token, {
      type: result.ok ? "ok" : "err",
      msg: result.msg,
    });
    res.redirect("/aktionen/konzentrieren");
  });

  // ---------------------------------------------------- Betteln / Spendenlink
  r.get("/aktionen/betteln", (req, res) => {
    const user = res.locals.user as UserRow;
    const host = req.get("host") ?? `localhost`;
    const proto = req.headers["x-forwarded-proto"] === "https" || req.secure ? "https" : "http";
    res.render("betteln", {
      title: "Betteln",
      active: "betteln",
      link: `${proto}://${host}/spende/${user.donation_code}`,
      today: donationStatsToday(db, user.id),
      breakdown: donationBreakdown(db, user),
      dailyCap: GAME.DONATION_DAILY_CAP,
    });
  });

  r.post("/aktionen/betteln/neuer-link", (req, res) => {
    const user = res.locals.user as UserRow;
    renewDonationCode(db, user.id);
    setFlash(db, res.locals.session.token, {
      type: "ok",
      msg: "Neuer Spendenlink erstellt — der alte Link ist ab sofort ungültig.",
    });
    res.redirect("/aktionen/betteln");
  });

  return r;
}
