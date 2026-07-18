import { Router, type Response } from "express";
import type { Db, ItemRow, UserRow } from "../db.js";
import { requireAuth, setFlash } from "../auth.js";
import { SKILL_INFO, type SkillType } from "../config.js";
import { districtOf, listDistricts } from "../game/districts.js";
import { skillLevels } from "../game/stats.js";
import * as svc from "../game/svc.js";
import { fmtMoney } from "../util.js";
import { fmtPromille, promilleOf } from "../game/promille.js";

export interface ShopRow {
  id: number;
  name: string;
  tier: number;
  effectText: string;
  requirementText: string | null;
  price: number;
  ownedQuantity: number;
  isConsumable: boolean;
  unlocked: boolean;
  affordable: boolean;
}

function effectText(item: ItemRow): string {
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
    default:
      return "";
  }
}

function shopRows(db: Db, user: UserRow, categories: string[]): ShopRow[] {
  const levels = skillLevels(db, user.id);
  const district = districtOf(db, user);
  const placeholders = categories.map(() => "?").join(",");
  const items = db
    .prepare(
      `SELECT * FROM items WHERE category IN (${placeholders}) ORDER BY category, tier`,
    )
    .all(...categories) as unknown as ItemRow[];
  const owned = db
    .prepare("SELECT item_id, quantity FROM inventory WHERE user_id = ?")
    .all(user.id) as unknown as Array<{ item_id: number; quantity: number }>;
  const ownedMap = new Map(owned.map((o) => [o.item_id, o.quantity]));

  return items.map((item) => {
    const reqParts: string[] = [];
    let unlocked = true;
    if (item.unlock_skill) {
      const skillName =
        SKILL_INFO[item.unlock_skill as SkillType]?.name ?? item.unlock_skill;
      reqParts.push(`${skillName} Stufe ${item.unlock_level}`);
      if ((levels[item.unlock_skill as SkillType] ?? 0) < (item.unlock_level ?? 0)) {
        unlocked = false;
      }
    }
    if (item.min_district_tier) {
      reqParts.push(`ab Viertel-Stufe ${item.min_district_tier}`);
      if (district.tier < item.min_district_tier) unlocked = false;
    }
    const isConsumable = item.category === "drink" || item.category === "food";
    return {
      id: item.id,
      name: item.name,
      tier: item.tier,
      effectText: effectText(item),
      requirementText: reqParts.length ? reqParts.join(" · ") : null,
      price: item.price,
      ownedQuantity: ownedMap.get(item.id) ?? 0,
      isConsumable,
      unlocked,
      affordable: user.money >= item.price,
    };
  });
}

function renderShop(
  db: Db,
  res: Response,
  opts: {
    title: string;
    blurb: string;
    categories: string[];
    path: string;
    hint?: string;
  },
): void {
  const user = res.locals.user as UserRow;
  res.render("shop", {
    title: opts.title,
    active: "stadt",
    blurb: opts.blurb,
    hint: opts.hint ?? null,
    currentPath: opts.path,
    rows: shopRows(db, user, opts.categories),
  });
}

export function stadtRoutes(db: Db): Router {
  const r = Router();
  r.use(requireAuth);

  r.get("/stadt", (req, res) => {
    const user = res.locals.user as UserRow;
    res.render("stadt", {
      title: "Stadt",
      active: "stadt",
      district: districtOf(db, user),
      promille: fmtPromille(promilleOf(user)),
    });
  });

  r.get("/stadt/karte", (req, res) => {
    const user = res.locals.user as UserRow;
    res.render("karte", {
      title: "Stadtkarte",
      active: "stadt",
      districts: listDistricts(db),
      current: districtOf(db, user),
    });
  });

  r.post("/stadt/umzug", (req, res) => {
    const user = res.locals.user as UserRow;
    const result = svc.moveToDistrict(db, user.id, (req.body as any).districtId);
    setFlash(db, res.locals.session.token, {
      type: result.ok ? "ok" : "err",
      msg: result.msg,
    });
    res.redirect("/stadt/karte");
  });

  r.get("/stadt/supermarkt", (req, res) => {
    renderShop(db, res, {
      path: "/stadt/supermarkt",
      title: "Supermarkt",
      blurb:
        "Alkohol hebt Pegel und Laune (gute Laune = schnelleres Training), macht dich im Kampf aber schwammig. Essen macht wieder nüchtern.",
      categories: ["drink", "food"],
      hint: "Gekauftes landet im Inventar und muss dort getrunken/gegessen werden. Ab 4,0 ‰ droht das Krankenhaus!",
    });
  });

  r.get("/stadt/waffenladen", (req, res) => {
    renderShop(db, res, {
      path: "/stadt/waffenladen",
      title: "Waffenladen",
      blurb: "Mehr ATT für deine Raubzüge. Freischaltung über den Angriff-Skill.",
      categories: ["weapon"],
    });
  });

  r.get("/stadt/immobilien", (req, res) => {
    renderShop(db, res, {
      path: "/stadt/immobilien",
      title: "Immobilienbüro",
      blurb:
        "Unterkünfte geben DEF und schützen dein Geld bei Überfällen. Die besten Adressen gibt es nur in besseren Vierteln.",
      categories: ["home"],
      hint: "Ziehst du in ein zu schlechtes Viertel, verliert eine gebundene Unterkunft ihren Schutz.",
    });
  });

  r.get("/stadt/tierhandlung", (req, res) => {
    renderShop(db, res, {
      path: "/stadt/tierhandlung",
      title: "Tierhandlung",
      blurb:
        "Treue Begleiter: geben ATT/DEF und ihr Mitleidswert erhöht deine Spenden-Einnahmen beim Betteln.",
      categories: ["pet"],
    });
  });

  r.get("/stadt/zubehoer", (req, res) => {
    renderShop(db, res, {
      path: "/stadt/zubehoer",
      title: "Zubehörladen",
      blurb: "Größere Behälter = mehr Geld, das du behalten kannst (Überlauf ist futsch).",
      categories: ["container"],
    });
  });

  r.post("/stadt/kaufen", (req, res) => {
    const user = res.locals.user as UserRow;
    const body = req.body as any;
    const result = svc.buyItem(db, user.id, body.itemId);
    setFlash(db, res.locals.session.token, {
      type: result.ok ? "ok" : "err",
      msg: result.msg,
    });
    const back = String(body.back ?? "");
    const allowed = [
      "/stadt/supermarkt",
      "/stadt/waffenladen",
      "/stadt/immobilien",
      "/stadt/tierhandlung",
      "/stadt/zubehoer",
    ];
    res.redirect(allowed.includes(back) ? back : "/stadt");
  });

  r.get("/stadt/waschhaus", (req, res) => {
    const user = res.locals.user as UserRow;
    res.render("waschhaus", {
      title: "Waschhaus",
      active: "stadt",
      cleanliness: user.cleanliness,
    });
  });

  r.post("/stadt/waschhaus", (req, res) => {
    const user = res.locals.user as UserRow;
    const result = svc.washUser(db, user.id, (req.body as any).option);
    setFlash(db, res.locals.session.token, {
      type: result.ok ? "ok" : "err",
      msg: result.msg,
    });
    res.redirect("/stadt/waschhaus");
  });

  return r;
}
