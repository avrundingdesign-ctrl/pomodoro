import { Router } from "express";
import type { Db, UserRow } from "../db.js";
import { requireAuth, setFlash } from "../auth.js";
import { GAME, LEAGUES } from "../config.js";
import * as gangs from "../game/gangs.js";
import * as wars from "../game/wars.js";
import * as community from "../game/community.js";

export function gangRoutes(db: Db): Router {
  const r = Router();
  r.use(requireAuth);

  const flashResult = (res: any, result: gangs.Res, redirect: string) => {
    setFlash(db, res.locals.session.token, {
      type: result.ok ? "ok" : "err",
      msg: result.msg,
    });
    res.redirect(redirect);
  };

  r.get("/bande", (req, res) => {
    const user = res.locals.user as UserRow;
    const membership = gangs.gangOf(db, user.id);
    if (!membership) {
      return res.render("bande-beitritt", {
        title: "Bande",
        active: "bande",
        foundCost: GAME.GANG_FOUND_COST,
      });
    }
    res.render("bande", {
      title: `Bande „${membership.gang.name}“`,
      active: "bande",
      gang: membership.gang,
      role: membership.role,
      memberCount: gangs.gangMembers(db, membership.gang.id).length,
      points: gangs.gangPoints(db, membership.gang.id),
      buildings: gangs.GANG_BUILDINGS,
    });
  });

  r.post("/bande/gruenden", (req, res) => {
    const user = res.locals.user as UserRow;
    const body = req.body as any;
    flashResult(res, gangs.foundGang(db, user, body.name, body.password), "/bande");
  });

  r.post("/bande/beitreten", (req, res) => {
    const user = res.locals.user as UserRow;
    const body = req.body as any;
    flashResult(res, gangs.joinGang(db, user, body.name, body.password), "/bande");
  });

  r.post("/bande/verlassen", (req, res) => {
    const user = res.locals.user as UserRow;
    flashResult(res, gangs.leaveGang(db, user), "/bande");
  });

  r.get("/bande/kasse", (req, res) => {
    const user = res.locals.user as UserRow;
    const membership = gangs.gangOf(db, user.id);
    if (!membership) return res.redirect("/bande");
    res.render("bande-kasse", {
      title: "Bandenkasse",
      active: "bande",
      gang: membership.gang,
      role: membership.role,
      limit: gangs.payoutLimit(membership.gang),
      usedToday: gangs.payoutUsedToday(db, membership.gang),
      members: gangs.gangMembers(db, membership.gang.id),
    });
  });

  r.post("/bande/kasse/einzahlen", (req, res) => {
    const user = res.locals.user as UserRow;
    flashResult(res, gangs.depositToGang(db, user, (req.body as any).betrag), "/bande/kasse");
  });

  r.post("/bande/kasse/auszahlen", (req, res) => {
    const user = res.locals.user as UserRow;
    const body = req.body as any;
    flashResult(
      res,
      gangs.payoutFromGang(db, user, body.mitglied, body.betrag),
      "/bande/kasse",
    );
  });

  r.get("/bande/eigentum", (req, res) => {
    const user = res.locals.user as UserRow;
    const membership = gangs.gangOf(db, user.id);
    if (!membership) return res.redirect("/bande");
    const buildings = (
      Object.keys(gangs.GANG_BUILDINGS) as gangs.GangBuilding[]
    ).map((key) => {
      const level = membership.gang[key];
      return {
        key,
        name: gangs.GANG_BUILDINGS[key].name,
        effect: gangs.GANG_BUILDINGS[key].effectPerLevel,
        level,
        max: GAME.GANG_BUILDING_MAX,
        nextCost: level < GAME.GANG_BUILDING_MAX ? gangs.buildingCost(level + 1) : null,
      };
    });
    res.render("bande-eigentum", {
      title: "Bandeneigentum",
      active: "bande",
      gang: membership.gang,
      role: membership.role,
      buildings,
    });
  });

  r.post("/bande/eigentum/ausbauen", (req, res) => {
    const user = res.locals.user as UserRow;
    flashResult(
      res,
      gangs.upgradeBuilding(db, user, (req.body as any).gebaeude),
      "/bande/eigentum",
    );
  });

  r.get("/bande/mitglieder", (req, res) => {
    const user = res.locals.user as UserRow;
    const membership = gangs.gangOf(db, user.id);
    if (!membership) return res.redirect("/bande");
    const windowMs = GAME.ONLINE_WINDOW_MINUTES * 60_000;
    res.render("bande-mitglieder", {
      title: "Mitglieder",
      active: "bande",
      gang: membership.gang,
      role: membership.role,
      meId: user.id,
      members: gangs.gangMembers(db, membership.gang.id).map((m) => ({
        ...m,
        online: m.last_seen_at > Date.now() - windowMs,
      })),
    });
  });

  r.post("/bande/mitglieder/aktion", (req, res) => {
    const user = res.locals.user as UserRow;
    const body = req.body as any;
    flashResult(
      res,
      gangs.manageMember(db, user, body.userId, body.aktion),
      "/bande/mitglieder",
    );
  });

  // ------------------------------------------------------ Phase 4: Bandenkriege
  r.get("/bande/kriege", (req, res) => {
    const user = res.locals.user as UserRow;
    const membership = gangs.gangOf(db, user.id);
    if (!membership) return res.redirect("/bande");
    const war = wars.activeWarOf(db, membership.gang.id);
    let warView = null;
    if (war) {
      const nameOf = (id: number) =>
        (db.prepare("SELECT name FROM gangs WHERE id = ?").get(id) as any)?.name ?? "?";
      warView = {
        ...war,
        nameA: nameOf(war.gang_a),
        nameB: nameOf(war.gang_b),
        weAreA: war.gang_a === membership.gang.id,
      };
    }
    res.render("bande-kriege", {
      title: "Bandenkriege",
      active: "bande",
      gang: membership.gang,
      role: membership.role,
      war: warView,
      history: wars.warHistory(db, membership.gang.id),
      pointLimit: GAME.WAR_POINT_LIMIT,
      durationHours: GAME.WAR_DURATION_HOURS,
    });
  });

  r.post("/bande/kriege/erklaeren", (req, res) => {
    const user = res.locals.user as UserRow;
    flashResult(res, wars.declareWar(db, user, (req.body as any).name), "/bande/kriege");
  });

  // -------------------------------------------------------- Phase 4: Bündnisse
  r.get("/bande/buendnisse", (req, res) => {
    const user = res.locals.user as UserRow;
    const membership = gangs.gangOf(db, user.id);
    if (!membership) return res.redirect("/bande");
    res.render("bande-buendnisse", {
      title: "Bündnisse",
      active: "bande",
      gang: membership.gang,
      role: membership.role,
      alliances: wars.alliancesOf(db, membership.gang.id),
      myGangId: membership.gang.id,
    });
  });

  r.post("/bande/buendnisse/anbieten", (req, res) => {
    const user = res.locals.user as UserRow;
    flashResult(
      res,
      wars.proposeAlliance(db, user, (req.body as any).name),
      "/bande/buendnisse",
    );
  });

  r.post("/bande/buendnisse/antworten", (req, res) => {
    const user = res.locals.user as UserRow;
    const body = req.body as any;
    flashResult(
      res,
      wars.respondAlliance(db, user, body.id, body.antwort === "annehmen"),
      "/bande/buendnisse",
    );
  });

  r.post("/bande/buendnisse/loesen", (req, res) => {
    const user = res.locals.user as UserRow;
    flashResult(
      res,
      wars.dissolveAlliance(db, user, (req.body as any).id),
      "/bande/buendnisse",
    );
  });

  // ------------------------------------------------------------ Phase 4: Liga
  r.get("/bande/liga", (req, res) => {
    const user = res.locals.user as UserRow;
    const membership = gangs.gangOf(db, user.id);
    if (!membership) return res.redirect("/bande");
    const leagueCounts = (
      db
        .prepare("SELECT league, COUNT(*) AS n FROM gangs GROUP BY league")
        .all() as unknown as Array<{ league: number; n: number }>
    ).reduce((acc, row) => {
      acc[row.league] = row.n;
      return acc;
    }, {} as Record<number, number>);
    res.render("bande-liga", {
      title: "Bandenliga",
      active: "bande",
      gang: membership.gang,
      leagues: LEAGUES,
      leagueCounts,
      standings: wars.leagueStandings(db, membership.gang.league),
      rewardText: wars.leagueRewardText(),
      promote: GAME.LEAGUE_PROMOTE,
      demote: GAME.LEAGUE_DEMOTE,
    });
  });

  // ---------------------------------------------------- Phase 4: Banden-Forum
  r.get("/bande/forum", (req, res) => {
    const user = res.locals.user as UserRow;
    const membership = gangs.gangOf(db, user.id);
    if (!membership) return res.redirect("/bande");
    res.render("forum-kategorie", {
      title: `Banden-Forum — ${membership.gang.name}`,
      active: "bande",
      categoryName: `Internes Forum von „${membership.gang.name}“`,
      categoryBlurb: "Nur für Mitglieder. Was hier steht, bleibt in der Bande.",
      threads: community.threadList(db, membership.gang.id, null),
      newThreadAction: "/bande/forum/neu",
      backLink: "/bande",
      backLabel: "Zur Bande",
    });
  });

  r.post("/bande/forum/neu", (req, res) => {
    const user = res.locals.user as UserRow;
    const membership = gangs.gangOf(db, user.id);
    if (!membership) return res.redirect("/bande");
    const body = req.body as any;
    const result = community.createThread(
      db,
      user,
      membership.gang.id,
      null,
      body.titel,
      body.text,
    );
    setFlash(db, res.locals.session.token, {
      type: result.ok ? "ok" : "err",
      msg: result.msg,
    });
    res.redirect(result.ok ? `/forum/thema/${result.id}` : "/bande/forum");
  });

  return r;
}
