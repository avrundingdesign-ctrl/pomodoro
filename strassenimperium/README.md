# 🛒 Straßenimperium

Browserbasiertes Text-/Klick-Aufbauspiel (Idle-RPG) nach dem Lastenheft
*„STRASSENIMPERIUM — Spielkonzept & technisches Lastenheft, Version 1.0"*.
Dies ist die Umsetzung von **Phase 1 der MVP-Roadmap (Kap. 20): der Kern-Loop** —
vollständig spielbar.

> Fiktives Satirespiel mit bewusst comichafter Überzeichnung (Kap. 21):
> eigenes Branding, Fiktions-Hinweis im Footer, keine Übernahme von
> Namen/Texten/Grafiken der Vorlage.

## Was ist drin (Phase 1)

| Feature | Lastenheft | Umsetzung |
|---|---|---|
| Account & Login | Kap. 14 | Registrierung, Login (Name oder E-Mail), Logout, Sessions (30 Tage), scrypt-Passwort-Hashing, CSRF-Schutz, Login-Rate-Limit |
| Übersicht | Kap. 18 | Status, Geld-Kapazitätsbalken, laufende Timer mit Live-Countdown, letzte Ereignisse, Tageskurs |
| Sammeln | Kap. 5 | Dauer 10 Min.–12 Std.; kurze Touren sind pro Stunde ertragreicher (Exponent 0,8); Geschick-Bonus; Flaschen ins Inventar |
| Weiterbildung | Kap. 4 | ATT/DEF/Geschick, max. 2 parallel, exponentiell steigende Kosten/Dauern, Punkte pro Abschluss |
| Inventar & Läden | Kap. 6/9 | Flaschen zum Tageskurs verkaufen; Waffen (per ATT-Skill freigeschaltet) und Geld-Behälter kaufen/aktivieren/mit Verlust wiederverkaufen |
| Geld-Kapazität | Kap. 3 | Überlauf geht verloren — beim Verkauf, bei Beute, beim Behälter-Wechsel (mit Warnhinweisen) |
| PvP-Kampf | Kap. 7.1 | Punkte-Spanne, 36-Std.-Cooldown pro Ziel, Kampf dauert 5 Min. (asynchron), Formel `(1+ATT)×Zufall(0,85–1,15)` vs. `(1+DEF)×…`, Beute DEF-reduziert, farbiges Kampflog |
| Eingehende Angriffe | Kap. 3/7.1 | Ab Geschicklichkeit 20 vorab sichtbar (mit Countdown) |
| Highscore & Profil | Kap. 12/18 | Punkte-Rangliste mit Pagination, öffentliche Profile mit Angriffs-Button |
| Tageskurs | Kap. 5/9 | Deterministisch pro UTC-Datum (8–15 Cent), serverseitig berechnet |

**Kern-Prinzip (Kap. 16, „Kritisch"):** Alle Timer und Belohnungen werden
ausschließlich serverseitig berechnet. Fällige Trainings/Aktionen/Kämpfe werden
bei jedem Request chronologisch aufgelöst („Lazy Resolution") — der Client zeigt
nur Countdowns an und lädt nach Ablauf neu.

## Schnellstart

Voraussetzung: Node.js ≥ 22.5 (nutzt das eingebaute `node:sqlite`).

```bash
cd strassenimperium
npm install
npm start            # baut und startet auf http://localhost:3000
```

Zum Ausprobieren mit Zeitraffer (alle Wartezeiten ×60 schneller):

```bash
npm run dev          # DEV_TIME_SCALE=60
```

Zwei Accounts registrieren (z. B. in zwei Browsern/Inkognito) und losspielen:
sammeln → verkaufen → weiterbilden → Waffe kaufen → überfallen.

### Konfiguration (Umgebungsvariablen)

| Variable | Default | Bedeutung |
|---|---|---|
| `PORT` | `3000` | HTTP-Port |
| `DB_PATH` | `data/strassenimperium.db` | SQLite-Datei (`:memory:` für Tests) |
| `DEV_TIME_SCALE` | `1` | Zeitraffer, **nur für Entwicklung** (60 = 60× schneller; skaliert auch den Kampf-Cooldown) |

Spielbalance (Kosten, Erträge, Kampf-/Beuteformeln, Cooldowns, Item-Katalog):
zentral in `src/config.ts` und `src/db.ts` (`seedItems`) — neue Waffen/Behälter
sind nur neue Datenzeilen, kein neuer Code (Kap. 19).

## Tests

```bash
npm test
```

- `test/formulas.test.ts` — Ertrags-/Kosten-/Kampf-/Kurs-Formeln, Kapazitäts-Überlauf
- `test/integration.test.ts` — kompletter Spielfluss über HTTP: Registrieren →
  Training → Kampf (inkl. Cooldown & Aktions-Sperre) → Sammeln → Verkaufen →
  Behälterkauf → Highscore, plus CSRF-/Auth-Negativfälle

Zusätzlich liegt unter `.claude/skills/verify/` ein Rezept, um den Spielfluss
manuell gegen den laufenden Server zu fahren (curl/Playwright).

## Architektur & bewusste MVP-Entscheidungen

- **Stack:** Node.js 22 + TypeScript, Express, EJS-SSR, `node:sqlite`.
  Das Lastenheft (Kap. 16) nennt React/Next.js **oder** „schlankes SSR" — für
  ein Grind-&-Wait-Spiel dieser Ära ist SSR die einfachste robuste Wahl
  (kleine interaktive Panels, ein bisschen Vanilla-JS für Countdowns).
- **SQLite statt PostgreSQL:** keine nativen/externen Abhängigkeiten, eine
  Datei, ideal für MVP und Tests. Das Schema ist relational gehalten
  (Kap. 17), sodass ein Umzug auf PostgreSQL ein reines Treiber-Thema ist.
- **Lazy Resolution statt Redis/BullMQ:** Auflösung ist idempotent,
  transaktional und rein von Serverzeit + DB abhängig. Bei Wachstum kann ein
  Worker/Cron dieselben Funktionen (`resolveAllDue`) zusätzlich aufrufen.
- **Noch nicht drin (bewusst, laut Roadmap):** E-Mail-Bestätigung,
  Sauberkeit/Laune/Promille (Phase 2), Stadtteile & weitere Läden (Phase 2),
  Verbrechen/Konzentrieren/Betteln (Phase 2+), Freunde/Nachrichten/Banden
  (Phase 3), Bandenkriege/Liga/Haustierkämpfe/Chat/Forum/Premium (Phase 4).

## Roadmap-Status

- [x] **Phase 1 — Kern-Loop** (dieses Verzeichnis)
- [ ] Phase 2 — Welt & Wirtschaft (Stadtteile, Supermarkt/Waschhaus, Promille-/Sauberkeitssystem, Haustiere)
- [ ] Phase 3 — Sozial & Wettbewerb (Freunde, Nachrichten, Banden-Basis, Auszeichnungen)
- [ ] Phase 4 — Endgame & Bindung (Bandenkriege, Liga, Haustierkämpfe, Chat, Forum, Premium)
- [ ] Phase 5 — Wachstum (Mobile-Feinschliff, weitere Städte/Sprachen, Events)

## Rechtliches (Kap. 21, fürs Launch-To-do)

Eigenes Branding ✓ · Fiktions-/Satire-Hinweis im Footer ✓ · Vor einem echten
Launch fehlen noch: Impressum, AGB, Datenschutzerklärung, Alterskennzeichnung
(16+), E-Mail-Verifizierung.
