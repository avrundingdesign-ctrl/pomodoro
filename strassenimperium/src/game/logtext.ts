import type { FightRow } from "../db.js";
import { fmtMoney } from "../util.js";

export interface FightRowNamed extends FightRow {
  attacker_name: string;
  defender_name: string;
}

export interface LogEntry {
  ts: number;
  cls: "win" | "loss" | "draw";
  text: string;
}

/** Kampflog-Zeile aus Sicht des Spielers `myId` (Farbcodes laut Kap. 7.1). */
export function fightDisplay(f: FightRowNamed, myId: number): LogEntry {
  const iAmAttacker = f.attacker_id === myId;
  if (iAmAttacker) {
    if (f.outcome === "win") {
      const overflow =
        f.money_kept < f.money_loot
          ? ` (${fmtMoney(f.money_loot - f.money_kept)} passten nicht mehr in deinen Behälter)`
          : "";
      return {
        ts: f.occurred_at,
        cls: "win",
        text: `Du hast ${f.defender_name} überfallen und gewonnen: +${fmtMoney(f.money_kept)} Beute${overflow}, +${f.points_attacker} Punkte.`,
      };
    }
    if (f.outcome === "loss") {
      return {
        ts: f.occurred_at,
        cls: "loss",
        text: `Dein Überfall auf ${f.defender_name} ging schief${f.points_attacker !== 0 ? ` (${f.points_attacker} Punkte)` : ""}.`,
      };
    }
    return {
      ts: f.occurred_at,
      cls: "draw",
      text: `Dein Kampf gegen ${f.defender_name} endete unentschieden (+${f.points_attacker} Punkt).`,
    };
  }
  if (f.outcome === "win") {
    return {
      ts: f.occurred_at,
      cls: "loss",
      text: `${f.attacker_name} hat dich überfallen und dir ${fmtMoney(f.money_loot)} abgenommen${f.points_defender !== 0 ? ` (${f.points_defender} Punkte)` : ""}.`,
    };
  }
  if (f.outcome === "loss") {
    return {
      ts: f.occurred_at,
      cls: "win",
      text: `Du hast den Überfall von ${f.attacker_name} abgewehrt: +${f.points_defender} Punkte.`,
    };
  }
  return {
    ts: f.occurred_at,
    cls: "draw",
    text: `Kampf mit ${f.attacker_name} endete unentschieden (+${f.points_defender} Punkt).`,
  };
}
