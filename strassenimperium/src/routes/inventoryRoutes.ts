import { Router } from "express";
import type { Db, InventoryRow, ItemRow, UserRow } from "../db.js";
import { requireAuth, setFlash } from "../auth.js";
import { GAME, SKILL_INFO, type SkillType } from "../config.js";
import { effectiveStats } from "../game/stats.js";
import * as svc from "../game/svc.js";

export interface OwnedItemView extends ItemRow {
  invId: number;
  isActive: boolean;
  resale: number;
}

export interface ShopItemView extends ItemRow {
  owned: boolean;
  unlocked: boolean;
  requirementText: string | null;
  affordable: boolean;
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
        `SELECT inventory.id AS invId, inventory.is_active AS isActiveNum, items.*
         FROM inventory JOIN items ON items.id = inventory.item_id
         WHERE inventory.user_id = ?
         ORDER BY items.category, items.tier`,
      )
      .all(user.id) as unknown as Array<ItemRow & { invId: number; isActiveNum: number }>;
    const owned: OwnedItemView[] = ownedRows.map((row) => ({
      ...row,
      invId: row.invId,
      isActive: row.isActiveNum === 1,
      resale: Math.floor(row.price * GAME.ITEM_RESALE_FACTOR),
    }));
    const ownedIds = new Set(owned.map((o) => o.id));

    const catalog = db
      .prepare("SELECT * FROM items ORDER BY category, tier")
      .all() as unknown as ItemRow[];
    const shop: ShopItemView[] = catalog.map((item) => {
      let unlocked = true;
      let requirementText: string | null = null;
      if (item.unlock_skill) {
        const skillName =
          SKILL_INFO[item.unlock_skill as SkillType]?.name ?? item.unlock_skill;
        requirementText = `${skillName} Stufe ${item.unlock_level}`;
        unlocked =
          (stats.skills[item.unlock_skill as SkillType] ?? 0) >=
          (item.unlock_level ?? 0);
      }
      return {
        ...item,
        owned: ownedIds.has(item.id),
        unlocked,
        requirementText,
        affordable: user.money >= item.price,
      };
    });

    res.render("inventar", {
      title: "Inventar",
      active: "inventar",
      stats,
      kurs,
      bottleProceeds: user.bottles * kurs,
      owned,
      shopWeapons: shop.filter((s) => s.category === "weapon"),
      shopContainers: shop.filter((s) => s.category === "container"),
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

  r.post("/inventar/kaufen", (req, res) => {
    redirectWithResult(
      res,
      svc.buyItem(db, (res.locals.user as UserRow).id, (req.body as any).itemId),
    );
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

  return r;
}
