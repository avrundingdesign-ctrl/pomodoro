import type { Db, GangRow, GangWarRow, UserRow } from "../db.js";
import { withTx } from "../db.js";
import { GAME, LEAGUES, scaledMs } from "../config.js";
import { now } from "../clock.js";
import { gangOf, gangPoints } from "./gangs.js";
import { fmtMoney } from "../util.js";

export type Res = { ok: true; msg: string } | { ok: false; msg: string };
const ok = (msg: string): Res => ({ ok: true, msg });
const err = (msg: string): Res => ({ ok: false, msg });

// -------------------------------------------------------------- Bandenkriege

export function activeWarOf(db: Db, gangId: number): GangWarRow | null {
  const row = db
    .prepare(
      `SELECT * FROM gang_wars
       WHERE status = 'active' AND (gang_a = ? OR gang_b = ?) LIMIT 1`,
    )
    .get(gangId, gangId) as unknown as GangWarRow | undefined;
  return row ?? null;
}

export function activeWarBetween(db: Db, a: number, b: number): GangWarRow | null {
  const row = db
    .prepare(
      `SELECT * FROM gang_wars
       WHERE status = 'active'
         AND ((gang_a = ? AND gang_b = ?) OR (gang_a = ? AND gang_b = ?))
       LIMIT 1`,
    )
    .get(a, b, b, a) as unknown as GangWarRow | undefined;
  return row ?? null;
}

export function areAllied(db: Db, a: number, b: number): boolean {
  return !!db
    .prepare(
      `SELECT id FROM gang_alliances
       WHERE status = 'active'
         AND ((proposer_id = ? AND other_id = ?) OR (proposer_id = ? AND other_id = ?))`,
    )
    .get(a, b, b, a);
}

export function declareWar(db: Db, actor: UserRow, targetNameRaw: unknown): Res {
  return withTx(db, () => {
    const membership = gangOf(db, actor.id);
    if (!membership) return err("Du bist in keiner Bande.");
    if (membership.role === "member") return err("Kriege erklärt nur der Boss (oder Co-Boss).");
    const target = db
      .prepare("SELECT * FROM gangs WHERE name = ?")
      .get(String(targetNameRaw ?? "").trim()) as unknown as GangRow | undefined;
    if (!target) return err("Diese Bande kennt hier niemand.");
    if (target.id === membership.gang.id) return err("Bürgerkrieg? Lieber nicht.");
    if (areAllied(db, membership.gang.id, target.id)) {
      return err("Mit Verbündeten führt man keinen Krieg — erst das Bündnis lösen.");
    }
    if (activeWarOf(db, membership.gang.id)) return err("Deine Bande führt schon einen Krieg.");
    if (activeWarOf(db, target.id)) return err(`„${target.name}“ steckt schon in einem Krieg.`);
    db.prepare(
      `INSERT INTO gang_wars (gang_a, gang_b, point_limit, ends_at, started_at)
       VALUES (?, ?, ?, ?, ?)`,
    ).run(
      membership.gang.id,
      target.id,
      GAME.WAR_POINT_LIMIT,
      now() + scaledMs(GAME.WAR_DURATION_HOURS * 3_600_000),
      now(),
    );
    return ok(
      `Krieg erklärt: „${membership.gang.name}“ gegen „${target.name}“! Jeder gewonnene Mitgliederkampf zählt einen Punkt — bis ${GAME.WAR_POINT_LIMIT} Punkte oder Zeitablauf.`,
    );
  });
}

/** Kampfsieg im Krieg verbuchen (Hook aus der Kampf-Auflösung, Kap. 11). */
export function recordWarFightWin(
  db: Db,
  winnerUserId: number,
  loserUserId: number,
): void {
  const winnerGang = gangOf(db, winnerUserId);
  const loserGang = gangOf(db, loserUserId);
  if (!winnerGang || !loserGang) return;
  const war = activeWarBetween(db, winnerGang.gang.id, loserGang.gang.id);
  if (!war) return;
  const column = war.gang_a === winnerGang.gang.id ? "score_a" : "score_b";
  db.prepare(`UPDATE gang_wars SET ${column} = ${column} + 1 WHERE id = ?`).run(war.id);
  const updated = db
    .prepare("SELECT * FROM gang_wars WHERE id = ?")
    .get(war.id) as unknown as GangWarRow;
  if (updated.score_a >= updated.point_limit || updated.score_b >= updated.point_limit) {
    finishWar(db, updated);
  }
}

function finishWar(db: Db, war: GangWarRow): void {
  let winner: number | null = null;
  if (war.score_a > war.score_b) winner = war.gang_a;
  else if (war.score_b > war.score_a) winner = war.gang_b;
  db.prepare(
    `UPDATE gang_wars SET status = 'finished', winner_gang_id = ?, finished_at = ?
     WHERE id = ? AND status = 'active'`,
  ).run(winner, now(), war.id);
  if (winner) {
    db.prepare(
      "UPDATE gangs SET war_wins = war_wins + 1, treasury = treasury + ? WHERE id = ?",
    ).run(GAME.WAR_WIN_TREASURY_BONUS, winner);
  }
}

/** Abgelaufene Kriege beenden (lazy, aus resolveAllDue). */
export function finishExpiredWars(db: Db): void {
  const due = db
    .prepare("SELECT * FROM gang_wars WHERE status = 'active' AND ends_at <= ?")
    .all(now()) as unknown as GangWarRow[];
  for (const war of due) finishWar(db, war);
}

export function warHistory(db: Db, gangId: number, limit = 10) {
  return db
    .prepare(
      `SELECT w.*, ga.name AS name_a, gb.name AS name_b
       FROM gang_wars w
       JOIN gangs ga ON ga.id = w.gang_a
       JOIN gangs gb ON gb.id = w.gang_b
       WHERE (w.gang_a = ? OR w.gang_b = ?) AND w.status = 'finished'
       ORDER BY w.finished_at DESC LIMIT ?`,
    )
    .all(gangId, gangId, limit) as unknown as Array<
    GangWarRow & { name_a: string; name_b: string }
  >;
}

// ----------------------------------------------------------------- Bündnisse

export function proposeAlliance(db: Db, actor: UserRow, targetNameRaw: unknown): Res {
  return withTx(db, () => {
    const membership = gangOf(db, actor.id);
    if (!membership) return err("Du bist in keiner Bande.");
    if (membership.role !== "admin") return err("Bündnisse schließt nur der Boss.");
    const target = db
      .prepare("SELECT * FROM gangs WHERE name = ?")
      .get(String(targetNameRaw ?? "").trim()) as unknown as GangRow | undefined;
    if (!target) return err("Diese Bande kennt hier niemand.");
    if (target.id === membership.gang.id) return err("Ein Bündnis mit dir selbst hast du schon.");
    if (areAllied(db, membership.gang.id, target.id)) return err("Ihr seid schon verbündet.");
    if (activeWarBetween(db, membership.gang.id, target.id)) {
      return err("Ihr führt Krieg — erst Frieden, dann Freundschaft.");
    }
    const pending = db
      .prepare(
        `SELECT id FROM gang_alliances WHERE status = 'proposed'
         AND ((proposer_id = ? AND other_id = ?) OR (proposer_id = ? AND other_id = ?))`,
      )
      .get(membership.gang.id, target.id, target.id, membership.gang.id);
    if (pending) return err("Es liegt schon ein Bündnisangebot zwischen euch vor.");
    db.prepare(
      "INSERT INTO gang_alliances (proposer_id, other_id, created_at) VALUES (?, ?, ?)",
    ).run(membership.gang.id, target.id, now());
    return ok(`Bündnisangebot an „${target.name}“ geschickt.`);
  });
}

export function respondAlliance(
  db: Db,
  actor: UserRow,
  allianceIdRaw: unknown,
  accept: boolean,
): Res {
  return withTx(db, () => {
    const membership = gangOf(db, actor.id);
    if (!membership) return err("Du bist in keiner Bande.");
    if (membership.role !== "admin") return err("Das entscheidet der Boss.");
    const alliance = db
      .prepare(
        "SELECT * FROM gang_alliances WHERE id = ? AND status = 'proposed' AND other_id = ?",
      )
      .get(Number(allianceIdRaw), membership.gang.id) as unknown as
      | { id: number; proposer_id: number }
      | undefined;
    if (!alliance) return err("Dieses Angebot liegt nicht (mehr) vor.");
    if (accept) {
      db.prepare("UPDATE gang_alliances SET status = 'active' WHERE id = ?").run(alliance.id);
      return ok("Bündnis geschlossen — auf gute Nachbarschaft.");
    }
    db.prepare("DELETE FROM gang_alliances WHERE id = ?").run(alliance.id);
    return ok("Angebot abgelehnt.");
  });
}

export function dissolveAlliance(db: Db, actor: UserRow, allianceIdRaw: unknown): Res {
  return withTx(db, () => {
    const membership = gangOf(db, actor.id);
    if (!membership) return err("Du bist in keiner Bande.");
    if (membership.role !== "admin") return err("Das entscheidet der Boss.");
    const result = db
      .prepare(
        `DELETE FROM gang_alliances
         WHERE id = ? AND status = 'active' AND (proposer_id = ? OR other_id = ?)`,
      )
      .run(Number(allianceIdRaw), membership.gang.id, membership.gang.id);
    return result.changes > 0 ? ok("Bündnis gelöst.") : err("Bündnis nicht gefunden.");
  });
}

export function alliancesOf(db: Db, gangId: number) {
  return db
    .prepare(
      `SELECT a.id, a.status, a.proposer_id, a.other_id,
              gp.name AS proposer_name, go2.name AS other_name
       FROM gang_alliances a
       JOIN gangs gp ON gp.id = a.proposer_id
       JOIN gangs go2 ON go2.id = a.other_id
       WHERE a.proposer_id = ? OR a.other_id = ?
       ORDER BY a.created_at DESC`,
    )
    .all(gangId, gangId) as unknown as Array<{
    id: number;
    status: string;
    proposer_id: number;
    other_id: number;
    proposer_name: string;
    other_name: string;
  }>;
}

// ---------------------------------------------------------------- Bandenliga

function monthKey(): string {
  return new Date(now()).toISOString().slice(0, 7);
}

/**
 * Saisonwechsel (lazy, Kap. 11): Am Monatswechsel steigen je Liga die besten
 * zwei auf, die letzten zwei ab; die Top 3 jeder Liga bekommen Kassenprämien.
 * Gewertet wird der Punkte-Zuwachs der Mitglieder in der Saison.
 */
export function rolloverLeagueSeason(db: Db): void {
  const month = monthKey();
  const row = db
    .prepare("SELECT value FROM meta WHERE key = 'league_season'")
    .get() as unknown as { value: string } | undefined;
  if (row?.value === month) return;
  const claimed = db
    .prepare(
      `INSERT INTO meta (key, value) VALUES ('league_season', ?)
       ON CONFLICT(key) DO UPDATE SET value = excluded.value
       WHERE meta.value != excluded.value`,
    )
    .run(month);
  if (claimed.changes === 0) return;
  const isFirstSeason = row === undefined;

  const gangs = db.prepare("SELECT * FROM gangs").all() as unknown as GangRow[];
  if (!isFirstSeason) {
    for (let league = 0; league < LEAGUES.length; league++) {
      const inLeague = gangs
        .filter((g) => g.league === league)
        .map((g) => ({ gang: g, delta: gangPoints(db, g.id) - g.season_start_points }))
        .sort((a, b) => b.delta - a.delta);
      inLeague.slice(0, GAME.LEAGUE_REWARDS.length).forEach((entry, index) => {
        db.prepare("UPDATE gangs SET treasury = treasury + ? WHERE id = ?").run(
          GAME.LEAGUE_REWARDS[index],
          entry.gang.id,
        );
      });
      if (league < LEAGUES.length - 1) {
        for (const entry of inLeague.slice(0, GAME.LEAGUE_PROMOTE)) {
          if (entry.delta > 0) {
            db.prepare("UPDATE gangs SET league = league + 1 WHERE id = ?").run(entry.gang.id);
          }
        }
      }
      if (league > 0 && inLeague.length > GAME.LEAGUE_PROMOTE) {
        for (const entry of inLeague.slice(-GAME.LEAGUE_DEMOTE)) {
          db.prepare("UPDATE gangs SET league = league - 1 WHERE id = ?").run(entry.gang.id);
        }
      }
    }
  }
  // Neue Saison: Startpunkte einfrieren.
  for (const gang of db.prepare("SELECT id FROM gangs").all() as unknown as Array<{ id: number }>) {
    db.prepare("UPDATE gangs SET season = ?, season_start_points = ? WHERE id = ?").run(
      month,
      gangPoints(db, gang.id),
      gang.id,
    );
  }
}

export function leagueStandings(db: Db, league: number) {
  const gangs = db
    .prepare("SELECT * FROM gangs WHERE league = ?")
    .all(league) as unknown as GangRow[];
  return gangs
    .map((g) => ({
      id: g.id,
      name: g.name,
      warWins: g.war_wins,
      seasonDelta: gangPoints(db, g.id) - g.season_start_points,
      total: gangPoints(db, g.id),
    }))
    .sort((a, b) => b.seasonDelta - a.seasonDelta);
}

export function leagueRewardText(): string {
  return GAME.LEAGUE_REWARDS.map((r, i) => `Platz ${i + 1}: ${fmtMoney(r)}`).join(" · ");
}
