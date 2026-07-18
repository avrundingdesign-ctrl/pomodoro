import { Router } from "express";
import type { Db, UserRow } from "../db.js";
import { requireAuth, setFlash } from "../auth.js";
import * as social from "../game/social.js";

export function socialRoutes(db: Db): Router {
  const r = Router();
  r.use(requireAuth);

  const flashResult = (res: any, result: social.Res, redirect: string) => {
    setFlash(db, res.locals.session.token, {
      type: result.ok ? "ok" : "err",
      msg: result.msg,
    });
    res.redirect(redirect);
  };

  // ------------------------------------------------------ Freunde & Blockliste
  r.get("/freunde", (req, res) => {
    const user = res.locals.user as UserRow;
    res.render("freunde", {
      title: "Freunde",
      active: "freunde",
      friends: social.listRelations(db, user.id, "friend"),
      blocked: social.listRelations(db, user.id, "block"),
    });
  });

  r.post("/freunde/hinzufuegen", (req, res) => {
    const user = res.locals.user as UserRow;
    const type = (req.body as any).typ === "block" ? "block" : "friend";
    flashResult(res, social.addRelation(db, user, (req.body as any).name, type), "/freunde");
  });

  r.post("/freunde/entfernen", (req, res) => {
    const user = res.locals.user as UserRow;
    flashResult(res, social.removeRelation(db, user, (req.body as any).id), "/freunde");
  });

  r.post("/freunde/notiz", (req, res) => {
    const user = res.locals.user as UserRow;
    flashResult(
      res,
      social.updateNote(db, user, (req.body as any).id, (req.body as any).note),
      "/freunde",
    );
  });

  // ---------------------------------------------------------------- Postfach
  r.get("/nachrichten", (req, res) => {
    const user = res.locals.user as UserRow;
    const box = ["eingang", "gesendet", "archiv"].includes(String((req.query as any).box))
      ? (String((req.query as any).box) as "eingang" | "gesendet" | "archiv")
      : "eingang";
    res.render("nachrichten", {
      title: "Nachrichten",
      active: "nachrichten",
      box,
      messages: social.mailbox(db, user.id, box),
      meId: user.id,
    });
  });

  r.get("/nachrichten/neu", (req, res) => {
    res.render("nachricht-neu", {
      title: "Neue Nachricht",
      active: "nachrichten",
      an: String((req.query as any).an ?? ""),
      error: null,
      body: "",
    });
  });

  r.post("/nachrichten/neu", (req, res) => {
    const user = res.locals.user as UserRow;
    const body = req.body as any;
    const result = social.sendMessage(db, user, body.an, body.text);
    if (!result.ok) {
      return res.status(400).render("nachricht-neu", {
        title: "Neue Nachricht",
        active: "nachrichten",
        an: String(body.an ?? ""),
        error: result.msg,
        body: String(body.text ?? ""),
      });
    }
    setFlash(db, res.locals.session.token, { type: "ok", msg: result.msg });
    res.redirect("/nachrichten?box=gesendet");
  });

  r.get("/nachrichten/:id", (req, res) => {
    const user = res.locals.user as UserRow;
    const message = social.getMessage(db, user.id, req.params.id);
    if (!message) {
      return res.status(404).render("error", {
        title: "Nicht gefunden",
        code: 404,
        message: "Diese Nachricht liegt nicht in deinem Postfach.",
      });
    }
    res.render("nachricht", {
      title: "Nachricht",
      active: "nachrichten",
      message,
      meId: user.id,
    });
  });

  r.post("/nachrichten/:id/archivieren", (req, res) => {
    const user = res.locals.user as UserRow;
    flashResult(res, social.archiveMessage(db, user.id, req.params.id), "/nachrichten");
  });

  r.post("/nachrichten/:id/loeschen", (req, res) => {
    const user = res.locals.user as UserRow;
    flashResult(res, social.deleteMessage(db, user.id, req.params.id), "/nachrichten");
  });

  return r;
}
