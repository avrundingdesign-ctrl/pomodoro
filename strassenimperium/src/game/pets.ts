import type { Db, ItemRow, PetChallengeRow, UserRow } from "../db.js";
import { withTx } from "../db.js";
import { GAME, PET_STANCES, type PetStance } from "../config.js";
import { now } from "../clock.js";
import { hashPassword, verifyPassword } from "../auth.js";
import { addMoney } from "./money.js";
import { fmtMoney } from "../util.js";

export type Res = { ok: true; msg: string } | { ok: false; msg: string };
const ok = (msg: string): Res => ({ ok: true, msg });
const err = (msg: string): Res => ({ ok: false, msg });

/** Alle Haustiere im Besitz eines Spielers. */
export function ownedPets(db: Db, userId: number): ItemRow[] {
  return db
    .prepare(
      `SELECT items.* FROM inventory
       JOIN items ON items.id = inventory.item_id
       WHERE inventory.user_id = ? AND items.category = 'pet'
       ORDER BY items.tier`,
    )
    .all(userId) as unknown as ItemRow[];
}

function ownsPet(db: Db, userId: number, petItemId: number): ItemRow | undefined {
  return db
    .prepare(
      `SELECT items.* FROM inventory
       JOIN items ON items.id = inventory.item_id
       WHERE inventory.user_id = ? AND items.id = ? AND items.category = 'pet'`,
    )
    .get(userId, petItemId) as unknown as ItemRow | undefined;
}

/**
 * Wettkampf-Wert eines Haustiers je Haltung (Kap. 7.2): offensiv zählt ATT,
 * defensiv DEF, neutral der Schnitt — plus Zufallsfaktor.
 */
export function petScore(pet: ItemRow, stance: PetStance, rnd: () => number = Math.random): number {
  const base =
    stance === "offensiv"
      ? pet.att_bonus
      : stance === "defensiv"
        ? pet.def_bonus
        : (pet.att_bonus + pet.def_bonus) / 2;
  const roll = GAME.PET_RANDOM_MIN + GAME.PET_RANDOM_SPAN * rnd();
  return (1 + base) * roll;
}

export function createChallenge(
  db: Db,
  user: UserRow,
  petItemIdRaw: unknown,
  stakeEuroRaw: unknown,
  stanceRaw: unknown,
  passwordRaw: unknown,
): Res {
  const stake = Math.floor(Number(stakeEuroRaw) * 100);
  const stance = String(stanceRaw) as PetStance;
  if (!Number.isFinite(stake) || stake <= 0) return err("Ungültiger Einsatz.");
  if (!PET_STANCES.includes(stance)) return err("Diese Haltung kennt kein Haustier.");
  return withTx(db, () => {
    const pet = ownsPet(db, user.id, Number(petItemIdRaw));
    if (!pet) return err("Dieses Haustier gehört dir nicht.");
    const openCount = (
      db
        .prepare(
          "SELECT COUNT(*) AS n FROM pet_challenges WHERE owner_id = ? AND status = 'open'",
        )
        .get(user.id) as unknown as { n: number }
    ).n;
    if (openCount >= GAME.PET_MAX_OPEN_CHALLENGES) {
      return err(`Mehr als ${GAME.PET_MAX_OPEN_CHALLENGES} offene Herausforderungen gehen nicht.`);
    }
    const fresh = db
      .prepare("SELECT money FROM users WHERE id = ?")
      .get(user.id) as unknown as { money: number };
    if (fresh.money < stake) return err("So viel Einsatz hast du nicht dabei.");
    // Einsatz wird hinterlegt (Treuhand), bis der Kampf entschieden ist.
    db.prepare("UPDATE users SET money = money - ? WHERE id = ?").run(stake, user.id);
    const password = String(passwordRaw ?? "").trim();
    db.prepare(
      `INSERT INTO pet_challenges (owner_id, pet_item_id, stake, stance, password_hash, created_at)
       VALUES (?, ?, ?, ?, ?, ?)`,
    ).run(user.id, pet.id, stake, stance, password ? hashPassword(password) : null, now());
    return ok(
      `„${pet.name}“ wartet ${password ? "passwortgeschützt " : ""}auf Herausforderer — Einsatz ${fmtMoney(stake)} (${stance}).`,
    );
  });
}

export function cancelChallenge(db: Db, user: UserRow, idRaw: unknown): Res {
  return withTx(db, () => {
    const challenge = db
      .prepare("SELECT * FROM pet_challenges WHERE id = ? AND owner_id = ? AND status = 'open'")
      .get(Number(idRaw), user.id) as unknown as PetChallengeRow | undefined;
    if (!challenge) return err("Diese Herausforderung läuft nicht (mehr).");
    db.prepare("UPDATE pet_challenges SET status = 'cancelled', resolved_at = ? WHERE id = ?").run(
      now(),
      challenge.id,
    );
    const back = addMoney(db, user.id, challenge.stake);
    return ok(
      `Herausforderung zurückgezogen — ${fmtMoney(back.added)} Einsatz zurück${back.lost > 0 ? ` (${fmtMoney(back.lost)} passten nicht in den Behälter!)` : ""}.`,
    );
  });
}

export interface PetFightResult {
  ok: boolean;
  msg: string;
  outcome?: "win" | "loss" | "draw";
}

/**
 * Herausforderung annehmen: beide Einsätze in den Topf, Vergleich der
 * Haltungs-Werte, Gewinner nimmt alles (Unentschieden: Einsätze zurück).
 * Mit Passwort ist das der gezielte Geld-Transfer-Kanal des Originals —
 * abgesichert über Cooldowns/Limits gegen Multi-Accounting (Kap. 7.2).
 */
export function acceptChallenge(
  db: Db,
  user: UserRow,
  idRaw: unknown,
  petItemIdRaw: unknown,
  stanceRaw: unknown,
  passwordRaw: unknown,
): PetFightResult {
  const stance = String(stanceRaw) as PetStance;
  if (!PET_STANCES.includes(stance)) return { ok: false, msg: "Ungültige Haltung." };
  return withTx(db, () => {
    const challenge = db
      .prepare("SELECT * FROM pet_challenges WHERE id = ? AND status = 'open'")
      .get(Number(idRaw)) as unknown as PetChallengeRow | undefined;
    if (!challenge) return { ok: false, msg: "Diese Herausforderung läuft nicht (mehr)." };
    if (challenge.owner_id === user.id) {
      return { ok: false, msg: "Gegen dein eigenes Tier wettest du nicht." };
    }
    if (
      challenge.password_hash &&
      !verifyPassword(String(passwordRaw ?? ""), challenge.password_hash)
    ) {
      return { ok: false, msg: "Falsches Passwort für diese Herausforderung." };
    }
    const myPet = ownsPet(db, user.id, Number(petItemIdRaw));
    if (!myPet) return { ok: false, msg: "Dieses Haustier gehört dir nicht." };
    const fresh = db
      .prepare("SELECT money FROM users WHERE id = ?")
      .get(user.id) as unknown as { money: number };
    if (fresh.money < challenge.stake) {
      return { ok: false, msg: `Der Einsatz beträgt ${fmtMoney(challenge.stake)} — so viel hast du nicht.` };
    }
    const ownerPet = db
      .prepare("SELECT * FROM items WHERE id = ?")
      .get(challenge.pet_item_id) as unknown as ItemRow;

    db.prepare("UPDATE users SET money = money - ? WHERE id = ?").run(challenge.stake, user.id);

    const ownerScore = petScore(ownerPet, challenge.stance as PetStance);
    const challengerScore = petScore(myPet, stance);
    const margin = GAME.PET_DRAW_MARGIN * Math.max(ownerScore, challengerScore, 1);
    const pot = challenge.stake * 2;

    let outcome: "win" | "loss" | "draw";
    let winnerId: number | null = null;
    let msg: string;
    if (Math.abs(ownerScore - challengerScore) <= margin) {
      outcome = "draw";
      addMoney(db, challenge.owner_id, challenge.stake);
      addMoney(db, user.id, challenge.stake);
      msg = `Unentschieden zwischen „${myPet.name}“ und „${ownerPet.name}“ — Einsätze zurück.`;
    } else if (challengerScore > ownerScore) {
      outcome = "win";
      winnerId = user.id;
      const won = addMoney(db, user.id, pot);
      msg = `„${myPet.name}“ (${stance}) schlägt „${ownerPet.name}“ — du gewinnst ${fmtMoney(won.added)}${won.lost > 0 ? ` (${fmtMoney(won.lost)} passten nicht in den Behälter!)` : ""}.`;
    } else {
      outcome = "loss";
      winnerId = challenge.owner_id;
      addMoney(db, challenge.owner_id, pot);
      msg = `„${ownerPet.name}“ (${challenge.stance}) gewinnt gegen „${myPet.name}“ — dein Einsatz ist weg.`;
    }
    db.prepare(
      `UPDATE pet_challenges
       SET status = 'done', challenger_id = ?, challenger_pet_id = ?, winner_id = ?, resolved_at = ?
       WHERE id = ?`,
    ).run(user.id, myPet.id, winnerId, now(), challenge.id);
    return { ok: true, msg, outcome };
  });
}

export function openChallenges(db: Db, excludeUserId: number) {
  return db
    .prepare(
      `SELECT c.*, u.username AS owner_name, items.name AS pet_name,
              items.att_bonus, items.def_bonus, items.tier
       FROM pet_challenges c
       JOIN users u ON u.id = c.owner_id
       JOIN items ON items.id = c.pet_item_id
       WHERE c.status = 'open' AND c.owner_id != ?
       ORDER BY c.created_at DESC LIMIT 30`,
    )
    .all(excludeUserId) as unknown as Array<
    PetChallengeRow & {
      owner_name: string;
      pet_name: string;
      att_bonus: number;
      def_bonus: number;
      tier: number;
    }
  >;
}

export function myChallenges(db: Db, userId: number) {
  return db
    .prepare(
      `SELECT c.*, items.name AS pet_name
       FROM pet_challenges c JOIN items ON items.id = c.pet_item_id
       WHERE c.owner_id = ? AND c.status = 'open'
       ORDER BY c.created_at DESC`,
    )
    .all(userId) as unknown as Array<PetChallengeRow & { pet_name: string }>;
}

export function challengeHistory(db: Db, userId: number, limit = 10) {
  return db
    .prepare(
      `SELECT c.*, u.username AS owner_name,
              COALESCE(uc.username, '?') AS challenger_name,
              items.name AS pet_name,
              COALESCE(ic.name, '?') AS challenger_pet_name
       FROM pet_challenges c
       JOIN users u ON u.id = c.owner_id
       LEFT JOIN users uc ON uc.id = c.challenger_id
       JOIN items ON items.id = c.pet_item_id
       LEFT JOIN items ic ON ic.id = c.challenger_pet_id
       WHERE c.status = 'done' AND (c.owner_id = ? OR c.challenger_id = ?)
       ORDER BY c.resolved_at DESC LIMIT ?`,
    )
    .all(userId, userId, limit) as unknown as Array<
    PetChallengeRow & {
      owner_name: string;
      challenger_name: string;
      pet_name: string;
      challenger_pet_name: string;
    }
  >;
}
