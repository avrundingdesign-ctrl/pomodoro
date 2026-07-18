import { Router } from "express";
import type { Db, UserRow } from "../db.js";
import { requireAuth, setFlash } from "../auth.js";
import { FORUM_CATEGORIES, GAME } from "../config.js";
import * as community from "../game/community.js";
import { gangOf } from "../game/gangs.js";

export function communityRoutes(db: Db): Router {
  const r = Router();
  r.use(requireAuth);

  // -------------------------------------------------------------------- Chat
  r.get("/chat", (req, res) => {
    res.render("chat", {
      title: "Live-Chat",
      active: "chat",
      messages: community.chatMessages(db),
      maxLength: GAME.CHAT_MAX_LENGTH,
    });
  });

  r.get("/chat/neu", (req, res) => {
    const since = Number((req.query as any).seit) || 0;
    res.json({
      messages: community.chatMessages(db, since).map((m) => ({
        id: m.id,
        user: m.username,
        body: m.body,
        ts: m.sent_at,
      })),
    });
  });

  r.post("/chat/senden", (req, res) => {
    const user = res.locals.user as UserRow;
    const result = community.sendChatMessage(db, user, (req.body as any).text);
    if ((req.headers.accept ?? "").includes("application/json")) {
      return res.status(result.ok ? 200 : 400).json(result);
    }
    if (!result.ok) {
      setFlash(db, res.locals.session.token, { type: "err", msg: result.msg });
    }
    res.redirect("/chat");
  });

  // ------------------------------------------------------------------- Forum
  r.get("/forum", (req, res) => {
    const categories = Object.entries(FORUM_CATEGORIES).map(([key, info]) => {
      const stats = db
        .prepare(
          `SELECT COUNT(*) AS threads, COALESCE(MAX(last_post_at), 0) AS latest
           FROM forum_threads WHERE gang_id IS NULL AND category = ?`,
        )
        .get(key) as unknown as { threads: number; latest: number };
      return { key, ...info, threads: stats.threads, latest: stats.latest };
    });
    res.render("forum", { title: "Forum", active: "forum", categories });
  });

  r.get("/forum/rubrik/:cat", (req, res) => {
    const cat = String(req.params.cat);
    if (!community.isValidCategory(cat)) {
      return res.status(404).render("error", {
        title: "Nicht gefunden",
        code: 404,
        message: "Diese Rubrik gibt es nicht.",
      });
    }
    res.render("forum-kategorie", {
      title: FORUM_CATEGORIES[cat].name,
      active: "forum",
      categoryName: FORUM_CATEGORIES[cat].name,
      categoryBlurb: FORUM_CATEGORIES[cat].blurb,
      threads: community.threadList(db, null, cat),
      newThreadAction: `/forum/rubrik/${cat}/neu`,
      backLink: "/forum",
      backLabel: "Zum Forum",
    });
  });

  r.post("/forum/rubrik/:cat/neu", (req, res) => {
    const user = res.locals.user as UserRow;
    const cat = String(req.params.cat);
    const body = req.body as any;
    const result = community.createThread(db, user, null, cat, body.titel, body.text);
    setFlash(db, res.locals.session.token, {
      type: result.ok ? "ok" : "err",
      msg: result.msg,
    });
    res.redirect(result.ok ? `/forum/thema/${result.id}` : `/forum/rubrik/${cat}`);
  });

  r.get("/forum/thema/:id", (req, res) => {
    const user = res.locals.user as UserRow;
    const thread = community.getThread(db, req.params.id);
    if (!thread) {
      return res.status(404).render("error", {
        title: "Nicht gefunden",
        code: 404,
        message: "Dieses Thema wurde nie eröffnet oder längst überklebt.",
      });
    }
    // Banden-Threads sind nur für Mitglieder sichtbar (Kap. 11).
    if (thread.gang_id !== null) {
      const membership = gangOf(db, user.id);
      if (!membership || membership.gang.id !== thread.gang_id) {
        return res.status(403).render("error", {
          title: "Verboten",
          code: 403,
          message: "Dieses Thema gehört einem Banden-Forum, in dem du nicht bist.",
        });
      }
    }
    res.render("forum-thema", {
      title: thread.title,
      active: thread.gang_id === null ? "forum" : "bande",
      thread,
      posts: community.threadPosts(db, thread.id),
      backLink:
        thread.gang_id === null ? `/forum/rubrik/${thread.category}` : "/bande/forum",
    });
  });

  r.post("/forum/thema/:id/antworten", (req, res) => {
    const user = res.locals.user as UserRow;
    const thread = community.getThread(db, req.params.id);
    if (!thread) return res.redirect("/forum");
    let gangId: number | null = null;
    if (thread.gang_id !== null) {
      const membership = gangOf(db, user.id);
      if (!membership || membership.gang.id !== thread.gang_id) {
        return res.redirect("/forum");
      }
      gangId = membership.gang.id;
    }
    const result = community.replyToThread(db, user, thread.id, (req.body as any).text, gangId);
    setFlash(db, res.locals.session.token, {
      type: result.ok ? "ok" : "err",
      msg: result.msg,
    });
    res.redirect(`/forum/thema/${thread.id}`);
  });

  // ----------------------------------------------------------------- Premium
  r.get("/premium", (req, res) => {
    const user = res.locals.user as UserRow;
    res.render("premium", {
      title: "Premium",
      active: "premium",
      isPremium: user.premium_until > Date.now(),
      premiumUntil: user.premium_until,
    });
  });

  return r;
}
