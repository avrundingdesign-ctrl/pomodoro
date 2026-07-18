import type { Db, GangMemberRow, GangRow, UserRow } from "../db.js";
import { withTx } from "../db.js";
import { GAME } from "../config.js";
import { now } from "../clock.js";
import { hashPassword, verifyPassword } from "../auth.js";
import { addMoney } from "./money.js";
import { fmtMoney } from "../util.js";

export type Res = { ok: true; msg: string } | { ok: false; msg: string };
const ok = (msg: string): Res => ({ ok: true, msg });
const err = (msg: string): Res => ({ ok: false, msg });

export type GangBuilding = "armory" | "house" | "training" | "account";
export const GANG_BUILDINGS: Record<
  GangBuilding,
  { name: string; effectPerLevel: string }
> = {
  armory: { name: "Waffenkammer", effectPerLevel: "+5 % ATT für alle Mitglieder" },
  house: { name: "Bandenhaus", effectPerLevel: "+5 % DEF für alle Mitglieder" },
  training: { name: "Bandentraining", effectPerLevel: "+4 % Trainingsgeschwindigkeit" },
  account: {
    name: "Bandenkonto",
    effectPerLevel: "+3 % Einnahmen aller Mitglieder, doppeltes Auszahlungslimit",
  },
};

export interface GangMembership {
  gang: GangRow;
  role: string;
}

export function gangOf(db: Db, userId: number): GangMembership | null {
  const row = db
    .prepare(
      `SELECT gangs.*, gang_members.role AS member_role
       FROM gang_members JOIN gangs ON gangs.id = gang_members.gang_id
       WHERE gang_members.user_id = ?`,
    )
    .get(userId) as unknown as (GangRow & { member_role: string }) | undefined;
  if (!row) return null;
  const { member_role, ...gang } = row;
  return { gang: gang as GangRow, role: member_role };
}

const NAME_RE = /^[A-Za-z0-9_ÄÖÜäöüß .\-]{3,30}$/;

export function foundGang(
  db: Db,
  user: UserRow,
  nameRaw: unknown,
  passwordRaw: unknown,
): Res {
  const name = String(nameRaw ?? "").trim();
  const password = String(passwordRaw ?? "");
  if (!NAME_RE.test(name)) {
    return err("Der Bandenname braucht 3–30 Zeichen (Buchstaben, Zahlen, Leerzeichen).");
  }
  if (password.length < 4) return err("Das Banden-Passwort braucht mindestens 4 Zeichen.");
  return withTx(db, () => {
    if (gangOf(db, user.id)) return err("Du bist schon in einer Bande.");
    const existing = db.prepare("SELECT id FROM gangs WHERE name = ?").get(name);
    if (existing) return err("Diesen Bandennamen gibt es schon.");
    const fresh = db
      .prepare("SELECT money FROM users WHERE id = ?")
      .get(user.id) as unknown as { money: number };
    if (fresh.money < GAME.GANG_FOUND_COST) {
      return err(`Eine Bande zu gründen kostet ${fmtMoney(GAME.GANG_FOUND_COST)}.`);
    }
    db.prepare("UPDATE users SET money = money - ? WHERE id = ?").run(
      GAME.GANG_FOUND_COST,
      user.id,
    );
    const result = db
      .prepare(
        `INSERT INTO gangs (name, password_hash, founder_id, created_at)
         VALUES (?, ?, ?, ?)`,
      )
      .run(name, hashPassword(password), user.id, now());
    db.prepare(
      "INSERT INTO gang_members (gang_id, user_id, role, joined_at) VALUES (?, ?, 'admin', ?)",
    ).run(Number(result.lastInsertRowid), user.id, now());
    return ok(`Bande „${name}“ gegründet — du bist der Boss.`);
  });
}

export function joinGang(
  db: Db,
  user: UserRow,
  nameRaw: unknown,
  passwordRaw: unknown,
): Res {
  const name = String(nameRaw ?? "").trim();
  return withTx(db, () => {
    if (gangOf(db, user.id)) return err("Du bist schon in einer Bande.");
    const gang = db.prepare("SELECT * FROM gangs WHERE name = ?").get(name) as unknown as
      | GangRow
      | undefined;
    if (!gang || !verifyPassword(String(passwordRaw ?? ""), gang.password_hash)) {
      return err("Bande unbekannt oder Passwort falsch.");
    }
    db.prepare(
      "INSERT INTO gang_members (gang_id, user_id, role, joined_at) VALUES (?, ?, 'member', ?)",
    ).run(gang.id, user.id, now());
    return ok(`Willkommen bei „${gang.name}“.`);
  });
}

export function leaveGang(db: Db, user: UserRow): Res {
  return withTx(db, () => {
    const membership = gangOf(db, user.id);
    if (!membership) return err("Du bist in keiner Bande.");
    const memberCount = (
      db
        .prepare("SELECT COUNT(*) AS n FROM gang_members WHERE gang_id = ?")
        .get(membership.gang.id) as unknown as { n: number }
    ).n;
    if (membership.role === "admin" && memberCount > 1) {
      return err("Als Boss musst du erst jemandem die Bande übertragen (Mitglieder-Seite).");
    }
    db.prepare("DELETE FROM gang_members WHERE user_id = ?").run(user.id);
    if (memberCount === 1) {
      db.prepare("DELETE FROM gangs WHERE id = ?").run(membership.gang.id);
      return ok(`Du hast „${membership.gang.name}“ aufgelöst. Die Kasse verfällt an die Straße.`);
    }
    return ok(`Du hast „${membership.gang.name}“ verlassen.`);
  });
}

export function depositToGang(db: Db, user: UserRow, amountRaw: unknown): Res {
  const amount = Math.floor(Number(amountRaw) * 100); // Eingabe in Euro
  if (!Number.isFinite(amount) || amount <= 0) return err("Ungültiger Betrag.");
  return withTx(db, () => {
    const membership = gangOf(db, user.id);
    if (!membership) return err("Du bist in keiner Bande.");
    const fresh = db
      .prepare("SELECT money FROM users WHERE id = ?")
      .get(user.id) as unknown as { money: number };
    if (fresh.money < amount) return err("So viel hast du nicht dabei.");
    db.prepare("UPDATE users SET money = money - ? WHERE id = ?").run(amount, user.id);
    db.prepare("UPDATE gangs SET treasury = treasury + ? WHERE id = ?").run(
      amount,
      membership.gang.id,
    );
    return ok(`${fmtMoney(amount)} in die Bandenkasse eingezahlt.`);
  });
}

export function payoutLimit(gang: GangRow): number {
  return GAME.GANG_PAYOUT_BASE_LIMIT * Math.pow(2, gang.account);
}

export function payoutUsedToday(db: Db, gang: GangRow): number {
  const today = new Date(now()).toISOString().slice(0, 10);
  return gang.payout_day === today ? gang.payout_used : 0;
}

export function payoutFromGang(
  db: Db,
  user: UserRow,
  targetUserIdRaw: unknown,
  amountRaw: unknown,
): Res {
  const amount = Math.floor(Number(amountRaw) * 100);
  const targetUserId = Number(targetUserIdRaw);
  if (!Number.isFinite(amount) || amount <= 0) return err("Ungültiger Betrag.");
  return withTx(db, () => {
    const membership = gangOf(db, user.id);
    if (!membership) return err("Du bist in keiner Bande.");
    if (membership.role === "member") {
      return err("Nur Boss und Co-Bosse dürfen auszahlen.");
    }
    const gang = db
      .prepare("SELECT * FROM gangs WHERE id = ?")
      .get(membership.gang.id) as unknown as GangRow;
    const target = db
      .prepare(
        `SELECT users.* FROM users
         JOIN gang_members ON gang_members.user_id = users.id
         WHERE users.id = ? AND gang_members.gang_id = ?`,
      )
      .get(targetUserId, gang.id) as unknown as UserRow | undefined;
    if (!target) return err("Auszahlungen gehen nur an Bandenmitglieder.");
    if (gang.treasury < amount) return err("So viel ist nicht in der Kasse.");
    const today = new Date(now()).toISOString().slice(0, 10);
    const used = gang.payout_day === today ? gang.payout_used : 0;
    const limit = payoutLimit(gang);
    if (used + amount > limit) {
      return err(
        `Tageslimit erreicht: heute sind nur noch ${fmtMoney(Math.max(0, limit - used))} drin (Bandenkonto ausbauen hilft).`,
      );
    }
    db.prepare(
      "UPDATE gangs SET treasury = treasury - ?, payout_day = ?, payout_used = ? WHERE id = ?",
    ).run(amount, today, used + amount, gang.id);
    const result = addMoney(db, target.id, amount);
    let msg = `${fmtMoney(result.added)} an ${target.username} ausgezahlt.`;
    if (result.lost > 0) {
      msg += ` ${fmtMoney(result.lost)} passten nicht in den Behälter des Empfängers und sind futsch!`;
    }
    return ok(msg);
  });
}

export function upgradeBuilding(db: Db, user: UserRow, buildingRaw: unknown): Res {
  const building = String(buildingRaw) as GangBuilding;
  if (!Object.hasOwn(GANG_BUILDINGS, building)) return err("Dieses Gebäude gibt es nicht.");
  return withTx(db, () => {
    const membership = gangOf(db, user.id);
    if (!membership) return err("Du bist in keiner Bande.");
    if (membership.role === "member") return err("Nur Boss und Co-Bosse bauen aus.");
    const gang = db
      .prepare("SELECT * FROM gangs WHERE id = ?")
      .get(membership.gang.id) as unknown as GangRow;
    const level = gang[building];
    if (level >= GAME.GANG_BUILDING_MAX) {
      return err(`${GANG_BUILDINGS[building].name} ist schon voll ausgebaut.`);
    }
    const cost = buildingCost(level + 1);
    if (gang.treasury < cost) {
      return err(
        `Ausbau auf Stufe ${level + 1} kostet ${fmtMoney(cost)} aus der Bandenkasse.`,
      );
    }
    db.prepare(
      `UPDATE gangs SET treasury = treasury - ?, ${building} = ${building} + 1 WHERE id = ?`,
    ).run(cost, gang.id);
    return ok(
      `${GANG_BUILDINGS[building].name} auf Stufe ${level + 1} ausgebaut (${GANG_BUILDINGS[building].effectPerLevel}).`,
    );
  });
}

export function buildingCost(targetLevel: number): number {
  return GAME.GANG_BUILDING_BASE_COST * Math.pow(3, targetLevel - 1);
}

export function gangMembers(db: Db, gangId: number) {
  return db
    .prepare(
      `SELECT users.id, users.username, users.points, users.last_seen_at,
              gang_members.role, gang_members.joined_at
       FROM gang_members JOIN users ON users.id = gang_members.user_id
       WHERE gang_members.gang_id = ?
       ORDER BY CASE gang_members.role WHEN 'admin' THEN 0 WHEN 'coadmin' THEN 1 ELSE 2 END,
                users.points DESC`,
    )
    .all(gangId) as unknown as Array<{
    id: number;
    username: string;
    points: number;
    last_seen_at: number;
    role: string;
    joined_at: number;
  }>;
}

export function gangPoints(db: Db, gangId: number): number {
  const row = db
    .prepare(
      `SELECT COALESCE(SUM(users.points), 0) AS total
       FROM gang_members JOIN users ON users.id = gang_members.user_id
       WHERE gang_members.gang_id = ?`,
    )
    .get(gangId) as unknown as { total: number };
  return row.total;
}

/** Mitglieder verwalten: kick / befördern / degradieren / Bande übertragen. */
export function manageMember(
  db: Db,
  actor: UserRow,
  targetIdRaw: unknown,
  actionRaw: unknown,
): Res {
  const targetId = Number(targetIdRaw);
  const action = String(actionRaw);
  return withTx(db, () => {
    const membership = gangOf(db, actor.id);
    if (!membership) return err("Du bist in keiner Bande.");
    const target = db
      .prepare("SELECT * FROM gang_members WHERE user_id = ? AND gang_id = ?")
      .get(targetId, membership.gang.id) as unknown as GangMemberRow | undefined;
    if (!target) return err("Kein Mitglied deiner Bande.");
    if (targetId === actor.id) return err("Auf dich selbst wendest du das nicht an.");
    const targetName =
      (db.prepare("SELECT username FROM users WHERE id = ?").get(targetId) as any)
        ?.username ?? "???";

    if (action === "kick") {
      if (membership.role === "member") return err("Nur Boss und Co-Bosse werfen raus.");
      if (target.role === "admin") return err("Der Boss fliegt nicht raus.");
      if (membership.role === "coadmin" && target.role === "coadmin") {
        return err("Co-Bosse werfen sich nicht gegenseitig raus.");
      }
      db.prepare("DELETE FROM gang_members WHERE user_id = ?").run(targetId);
      return ok(`${targetName} fliegt aus der Bande.`);
    }
    if (membership.role !== "admin") return err("Das darf nur der Boss.");
    if (action === "promote" && target.role === "member") {
      db.prepare("UPDATE gang_members SET role = 'coadmin' WHERE user_id = ?").run(targetId);
      return ok(`${targetName} ist jetzt Co-Boss.`);
    }
    if (action === "demote" && target.role === "coadmin") {
      db.prepare("UPDATE gang_members SET role = 'member' WHERE user_id = ?").run(targetId);
      return ok(`${targetName} ist wieder einfaches Mitglied.`);
    }
    if (action === "transfer") {
      db.prepare("UPDATE gang_members SET role = 'admin' WHERE user_id = ?").run(targetId);
      db.prepare("UPDATE gang_members SET role = 'coadmin' WHERE user_id = ?").run(actor.id);
      return ok(`${targetName} ist jetzt der Boss — du bist Co-Boss.`);
    }
    return err("Diese Aktion kennt hier niemand.");
  });
}

/** Einnahmen-Multiplikator durch das Bandenkonto (Kap. 11). */
export function gangIncomeFactor(db: Db, userId: number): number {
  const membership = gangOf(db, userId);
  if (!membership) return 1;
  return 1 + GAME.GANG_ACCOUNT_INCOME_PER_LEVEL * membership.gang.account;
}

/** Trainingszeit-Faktor durch das Bandentraining (Kap. 11). */
export function gangTrainingFactor(db: Db, userId: number): number {
  const membership = gangOf(db, userId);
  if (!membership) return 1;
  return Math.max(0.5, 1 - GAME.GANG_TRAINING_SPEED_PER_LEVEL * membership.gang.training);
}
