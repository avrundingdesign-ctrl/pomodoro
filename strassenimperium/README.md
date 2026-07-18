# 🛒 Straßenimperium

Browserbasiertes Text-/Klick-Aufbauspiel (Idle-RPG) nach dem Lastenheft
*„STRASSENIMPERIUM — Spielkonzept & technisches Lastenheft, Version 1.0"*.
Umgesetzt sind die **Phasen 1–2 der MVP-Roadmap (Kap. 20): Kern-Loop sowie
Welt & Wirtschaft** — vollständig spielbar.

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
| **Stadtteile** | Kap. 8 | 12 Viertel mit Ertragsfaktor & Umzugskosten; Faktor wirkt auf Sammeln und Spenden; Top-Unterkünfte sind stadtteilgebunden |
| **Supermarkt** | Kap. 8 | Alkohol (+Promille) und Nahrung (−Promille) als stapelbare Konsumgüter im Inventar |
| **Promille/Laune** | Kap. 3 | Pegel mit natürlichem Abbau; Laune folgt der Beispielkurve: nüchtern = kampfstark, angeheitert = schnelleres Training, ab 4,0 ‰ Krankenhaus-Event (Kosten + Zwangsnüchternheit) |
| **Sauberkeit & Waschhaus** | Kap. 3/8 | Sammeln macht dreckig; Waschhaus mit Katzenwäsche (+20 %-Punkte) und Vollprogramm (100 %); Sauberkeit erhöht Spenden |
| **Immobilienbüro** | Kap. 6/8 | 8 Unterkünfte (+DEF), freigeschaltet über Verteidigung, teils erst ab bestimmter Viertel-Stufe; Wegzug deaktiviert gebundene Unterkünfte |
| **Tierhandlung & Haustiere** | Kap. 6 | 7 Haustiere (+ATT/+DEF + Mitleidswert), freigeschaltet über den neuen Skill Sozialkontakte (max. Stufe 10) |
| **Betteln/Spendenlink** | Kap. 5/10/14 | Öffentlicher, erneuerbarer Spendenlink: jeder Klick Dritter zahlt aus (dedupliziert pro Quelle/Tag, Tagesdeckel); Betrag = Basis × Sauberkeit × Standort × Haustier-Mitleid |

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
  Verbrechen & Konzentrieren (Kap. 5), Musikinstrumente & Bettelspots,
  Apotheke/Krankenversicherung, Glücksspiele, Referral-Bonus beim Betteln,
  Freunde/Nachrichten/Banden (Phase 3),
  Bandenkriege/Liga/Haustierkämpfe/Chat/Forum/Premium (Phase 4).

## Roadmap-Status

- [x] **Phase 1 — Kern-Loop**
- [x] **Phase 2 — Welt & Wirtschaft** (Stadtteile, Supermarkt/Waschhaus/Immobilien/Tierhandlung, Promille-/Sauberkeitssystem, Haustiere, dazu der Spendenlink aus Kap. 5 als Auszahlungskanal für Sauberkeit/Mitleid; nachgereicht: Verbrechen, Konzentrieren, Musikinstrumente, Bettelspots aus Kap. 5/6)
- [x] **Phase 3 — Sozial & Wettbewerb** (Freundes-/Blockliste mit Online-Status, Postfach mit Archiv, Banden mit Kasse/Tageslimit/4 Gebäuden und Rollen, Banden-Highscore, Auszeichnungen in 4 Stufen mit täglichen Rangpunkten für die Top 7, Einstellungen mit Urlaubsmodus, Passwortwechsel und Auszeichnungs-Verschleierung)
- [x] **Phase 4 — Endgame & Bindung** (Bandenkriege mit Punkte-/Zeitlimit und Siegprämie, Bündnisse, monatliche Bandenliga mit Auf-/Abstieg und Prämien, Haustier-Wettkämpfe mit Einsatz/Haltung und passwortgeschütztem Geldtransfer, Live-Chat mit Polling, globales Forum + Banden-Forum, News-Feed auf der Übersicht, Premium-Konzeptseite ohne Pay-to-Win)
- [ ] Phase 5 — Wachstum (Mobile-Feinschliff, weitere Städte/Sprachen, Events)

## Rechtliches (Kap. 21, fürs Launch-To-do)

Eigenes Branding ✓ · Fiktions-/Satire-Hinweis im Footer ✓ · Vor einem echten
Launch fehlen noch: Impressum, AGB, Datenschutzerklärung, Alterskennzeichnung
(16+), E-Mail-Verifizierung.
