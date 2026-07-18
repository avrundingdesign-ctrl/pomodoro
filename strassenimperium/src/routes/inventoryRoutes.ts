import { Router } from "express";
import type { Db, ItemRow, UserRow } from "../db.js";
import { CONSUMABLE_CATEGORIES } from "../db.js";
import { requireAuth, setFlash } from "../auth.js";
import { GAME } from "../config.js";
import { effectiveStats } from "../game/stats.js";
import { fmtPromille, moodLabel, promilleOf } from "../game/promille.js";
import * as svc from "../game/svc.js";
import { fmtMoney } from "../util.js";

export interface OwnedItemView extends ItemRow {
  invId: number;
  isActive: boolean;
  quantity: number;
  resale: number;
  effectText: string;
}

function ownedEffectText(item: ItemRow): string {
  switch (item.category) {
    case "weapon":
      return `+${item.att_bonus} ATT`;
    case "container":
      return `Kapazität ${fmtMoney(item.capacity)}`;
    case "home":
      return `+${item.def_bonus} DEF`;
    case "pet": {
      const parts = [];
      if (item.att_bonus) parts.push(`+${item.att_bonus} ATT`);
      if (item.def_bonus) parts.push(`+${item.def_bonus} DEF`);
      parts.push(`Mitleid +${item.empathy_bonus}`);
      return parts.join(" · ");
    }
    case "drink":
      return `+${item.promille_delta.toLocaleString("de-DE")} ‰`;
    case "food":
      return `${item.promille_delta.toLocaleString("de-DE")} ‰`;
    case "instrument":
      return `+${fmtMoney(item.income)} alle ${GAME.MUSIC_PAYOUT_HOURS} Std.`;
    case "spot":
      return `+${item.donation_bonus} % Spenden`;
    default:
      return "";
  }
}

export function inventoryRoutes(db: Db): Router {
  const r = Router();
  r.use(requireAuth);

  r.get("/inventar", (req, res) => {
    const user = res.locals.user as UserRow;
    const stats = effectiveStats(db, user.id);
    const kurs = svc.kursToday();

    const ownedRows = db
      .prepare(
        `SELECT inventory.id AS invId, inventory.is_active AS isActiveNum,
                inventory.quantity AS quantity, items.*
         FROM inventory JOIN items ON items.id = inventory.item_id
         WHERE inventory.user_id = ?
         ORDER BY items.category, items.tier`,
      )
      .all(user.id) as unknown as Array<
      ItemRow & { invId: number; isActiveNum: number; quantity: number }
    >;
    const owned: OwnedItemView[] = ownedRows.map((row) => ({
      ...row,
      invId: row.invId,
      isActive: row.isActiveNum === 1,
      quantity: row.quantity,
      resale: Math.floor(row.price * GAME.ITEM_RESALE_FACTOR),
      effectText: ownedEffectText(row),
    }));
    const isConsumable = (o: OwnedItemView) =>
      (CONSUMABLE_CATEGORIES as readonly string[]).includes(o.category);

    const promille = promilleOf(user);
    res.render("inventar", {
      title: "Inventar",
      active: "inventar",
      stats,
      kurs,
      bottleProceeds: user.bottles * kurs,
      equipment: owned.filter((o) => !isConsumable(o)),
      consumables: owned.filter(isConsumable),
      promilleLabel: fmtPromille(promille),
      mood: moodLabel(promille),
    });
  });

  const redirectWithResult = (res: any, result: svc.Res) => {
    setFlash(db, res.locals.session.token, {
      type: result.ok ? "ok" : "err",
      msg: result.msg,
    });
    res.redirect("/inventar");
  };

  r.post("/inventar/verkaufen", (req, res) => {
    redirectWithResult(res, svc.sellBottles(db, (res.locals.user as UserRow).id));
  });

  r.post("/inventar/aktivieren", (req, res) => {
    redirectWithResult(
      res,
      svc.activateItem(db, (res.locals.user as UserRow).id, (req.body as any).invId),
    );
  });

  r.post("/inventar/verkaufen-item", (req, res) => {
    redirectWithResult(
      res,
      svc.sellInventoryItem(db, (res.locals.user as UserRow).id, (req.body as any).invId),
    );
  });

  r.post("/inventar/konsumieren", (req, res) => {
    redirectWithResult(
      res,
      svc.consumeItem(db, (res.locals.user as UserRow).id, (req.body as any).invId),
    );
  });

  return r;
}
