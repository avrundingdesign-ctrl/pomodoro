import { Router } from "express";
import type { ActionRow, Db, UserRow } from "../db.js";
import { requireAuth, setFlash } from "../auth.js";
import { ACHIEVEMENT_TIER_NAMES, ACHIEVEMENTS, GAME, PET_STANCES } from "../config.js";
import { gangOf } from "../game/gangs.js";
import * as pets from "../game/pets.js";
import { attackRange } from "../game/formulas.js";
import { effectiveStats, rankOf } from "../game/stats.js";
import { fightDisplay, type FightRowNamed } from "../game/logtext.js";
import * as svc from "../game/svc.js";

export function fightRoutes(db: Db): Router {
  const r = Router();
  r.use(requireAuth);

  r.get("/kampf", (req, res) => {
    const user = res.locals.user as UserRow;
    const stats = effectiveStats(db, user.id);
    const action = svc.activePhysicalAction(db, user.id) as
      | (ActionRow & { defender_name?: string })
      | null;
    if (action?.type === "kampf" && action.target_user_id) {
      action.defender_name = svc.getUser(db, action.target_user_id)?.username ?? "???";
    }
    const incomingVisible = stats.skills.geschick >= GAME.INCOMING_VISIBLE_AT_SKILL;
    const incoming = incomingVisible ? svc.incomingAttacks(db, user.id) : null;

    const targets = svc.attackableTargets(db, user, 20).map((t) => ({
      ...t,
      rank: rankOf(db, { id: t.id, points: t.points }),
    }));

    const fights = db
      .prepare(
        `SELECT f.*, ua.username AS attacker_name, ud.username AS defender_name
         FROM fights f
         JOIN users ua ON ua.id = f.attacker_id
         JOIN users ud ON ud.id = f.defender_id
         WHERE f.attacker_id = ? OR f.defender_id = ?
         ORDER BY f.occurred_at DESC LIMIT 15`,
      )
      .all(user.id, user.id) as unknown as FightRowNamed[];

    res.render("kampf", {
      title: "Kampf",
      active: "kampf",
      action,
      incoming,
      incomingVisible,
      targets,
      range: attackRange(user.points),
      log: fights.map((f) => fightDisplay(f, user.id)),
      incomingUnlockLevel: GAME.INCOMING_VISIBLE_AT_SKILL,
    });
  });

  r.post("/kampf/angriff", (req, res) => {
    const user = res.locals.user as UserRow;
    const result = svc.startAttack(db, user.id, (req.body as any).defenderId);
    setFlash(db, res.locals.session.token, {
      type: result.ok ? "ok" : "err",
      msg: result.msg,
    });
    res.redirect("/kampf");
  });

  // ------------------------------------------------- Haustierkämpfe (Kap. 7.2)
  r.get("/kampf/haustier", (req, res) => {
    const user = res.locals.user as UserRow;
    res.render("haustierkampf", {
      title: "Haustierkämpfe",
      active: "kampf",
      myPets: pets.ownedPets(db, user.id),
      open: pets.openChallenges(db, user.id),
      mine: pets.myChallenges(db, user.id),
      history: pets.challengeHistory(db, user.id),
      meId: user.id,
      stances: PET_STANCES,
      maxOpen: GAME.PET_MAX_OPEN_CHALLENGES,
    });
  });

  r.post("/kampf/haustier/erstellen", (req, res) => {
    const user = res.locals.user as UserRow;
    const body = req.body as any;
    const result = pets.createChallenge(
      db,
      user,
      body.petId,
      body.einsatz,
      body.haltung,
      body.passwort,
    );
    setFlash(db, res.locals.session.token, {
      type: result.ok ? "ok" : "err",
      msg: result.msg,
    });
    res.redirect("/kampf/haustier");
  });

  r.post("/kampf/haustier/annehmen", (req, res) => {
    const user = res.locals.user as UserRow;
    const body = req.body as any;
    const result = pets.acceptChallenge(
      db,
      user,
      body.id,
      body.petId,
      body.haltung,
      body.passwort,
    );
    setFlash(db, res.locals.session.token, {
      type: result.ok ? "ok" : "err",
      msg: result.msg,
    });
    res.redirect("/kampf/haustier");
  });

  r.post("/kampf/haustier/zurueckziehen", (req, res) => {
    const user = res.locals.user as UserRow;
    const result = pets.cancelChallenge(db, user, (req.body as any).id);
    setFlash(db, res.locals.session.token, {
      type: result.ok ? "ok" : "err",
      msg: result.msg,
    });
    res.redirect("/kampf/haustier");
  });

  // ------------------------------------------------------------- Highscore
  r.get("/highscore", (req, res) => {
    const user = res.locals.user as UserRow;
    if (String((req.query as any).typ) === "banden") {
      const gangRows = db
        .prepare(
          `SELECT gangs.id, gangs.name,
                  COUNT(gang_members.user_id) AS members,
                  COALESCE(SUM(users.points), 0) AS points
           FROM gangs
           LEFT JOIN gang_members ON gang_members.gang_id = gangs.id
           LEFT JOIN users ON users.id = gang_members.user_id
           GROUP BY gangs.id
           ORDER BY points DESC, gangs.id ASC LIMIT 50`,
        )
        .all() as unknown as Array<{
        id: number;
        name: string;
        members: number;
        points: number;
      }>;
      const myGang = gangOf(db, user.id);
      return res.render("highscore-banden", {
        title: "Banden-Highscore",
        active: "highscore",
        rows: gangRows,
        myGangId: myGang?.gang.id ?? null,
      });
    }
    const pageSize = 25;
    const total = (
      db.prepare("SELECT COUNT(*) AS n FROM users").get() as unknown as { n: number }
    ).n;
    const pages = Math.max(1, Math.ceil(total / pageSize));
    const page = Math.min(
      pages,
      Math.max(1, Number((req.query as any).seite) || 1),
    );
    const rows = db
      .prepare(
        `SELECT id, username, points, created_at FROM users
         ORDER BY points DESC, id ASC LIMIT ? OFFSET ?`,
      )
      .all(pageSize, (page - 1) * pageSize) as unknown as Array<{
      id: number;
      username: string;
      points: number;
      created_at: number;
    }>;
    res.render("highscore", {
      title: "Highscore",
      active: "highscore",
      rows,
      startRank: (page - 1) * pageSize + 1,
      page,
      pages,
      total,
      meId: user.id,
    });
  });

  // --------------------------------------------------------------- Profil
  r.get("/profil/:username", (req, res) => {
    const me = res.locals.user as UserRow;
    const them = db
      .prepare("SELECT * FROM users WHERE username = ?")
      .get(String(req.params.username)) as unknown as UserRow | undefined;
    if (!them) {
      return res.status(404).render("error", {
        title: "Nicht gefunden",
        code: 404,
        message: "Diesen Bewohner der Straße kennt hier niemand.",
      });
    }
    const busy = svc.activePhysicalAction(db, me.id);
    const check = me.id === them.id ? null : svc.canAttack(db, me, them);
    // Auszeichnungen: höchste Stufe je Typ, nur wenn öffentlich (Kap. 10/12).
    const achievements =
      them.show_achievements === 1
        ? (db
            .prepare(
              `SELECT type, MAX(tier) AS tier FROM achievements
               WHERE user_id = ? GROUP BY type`,
            )
            .all(them.id) as unknown as Array<{ type: string; tier: number }>)
            .map((a) => {
              const def = ACHIEVEMENTS.find((d) => d.type === a.type);
              return def
                ? { name: def.name, tierName: ACHIEVEMENT_TIER_NAMES[a.tier - 1] }
                : null;
            })
            .filter((a): a is { name: string; tierName: string } => a !== null)
        : null;
    res.render("profil", {
      title: `Profil von ${them.username}`,
      active: "kampf",
      them,
      themRank: rankOf(db, them),
      themGang: gangOf(db, them.id)?.gang ?? null,
      themOnVacation: svc.isOnVacation(them),
      achievements,
      isMe: me.id === them.id,
      canAttackNow: check !== null && check.ok && !busy,
      attackBlockReason:
        check === null ? null : !check.ok ? check.msg : busy ? "Du bist gerade beschäftigt." : null,
    });
  });

  return r;
}
