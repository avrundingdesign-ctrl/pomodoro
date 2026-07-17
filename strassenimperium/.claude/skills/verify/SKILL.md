---
name: verify
description: Straßenimperium end-to-end verifizieren — Server bauen/starten und den Spielfluss über HTTP bzw. Browser fahren
---

# Straßenimperium verifizieren

Oberfläche ist ein SSR-HTTP-Server (Express + EJS). Verifizieren heißt:
Server starten, Spielfluss über die echten Seiten fahren, HTML/Flashes lesen.

## Bauen & Starten

```bash
cd strassenimperium
npm install && npx tsc
DB_PATH=/tmp/verify.db DEV_TIME_SCALE=600 PORT=3210 node dist/src/server.js &
```

- `DEV_TIME_SCALE=600` staucht alle Wartezeiten (10 Min. → 1 Sek.; Minimum 1 Sek. pro Timer).
  Auch der Angriffs-Cooldown (36 Std. → 216 Sek.) skaliert mit.
- Frische DB = frisches Spiel; `DB_PATH` weglassen ⇒ `data/strassenimperium.db`.

## Spielfluss per curl

```bash
# Registrieren liefert Session-Cookie via 302:
curl -si -X POST localhost:3210/registrieren \
  -d 'username=TestA&email=a@ex.com&password=strasse123&password2=strasse123' | grep -i set-cookie
# CSRF-Token steht in jeder Seite (Logout-Form): name="_csrf" value="…"
curl -s localhost:3210/uebersicht -H "Cookie: sid=…" | grep -o 'name="_csrf" value="[0-9a-f]*"'
# Alle Spiel-POSTs brauchen Cookie + _csrf:
#   /weiterbildung/start (skill=angriff|verteidigung|geschick)
#   /aktionen/sammeln/start (minutes=10|30|60|120|240|480|720)
#   /kampf/angriff (defenderId=…)  — IDs stehen in /kampf im defenderId-Hidden-Field
#   /inventar/verkaufen · /inventar/kaufen (itemId) · /inventar/aktivieren (invId)
```

Timer werden bei **jedem** Request lazy aufgelöst — nach Ablauf reicht ein
beliebiger GET (z. B. `/healthz`), dann zeigt `/uebersicht` das Ergebnis
unter „Letzte Ereignisse" bzw. `/kampf` im Kampflog.

## Browser-Drive (Screenshots)

`npm i --no-save playwright-core`, dann Chromium mit
`executablePath: "/opt/pw-browsers/chromium"` starten (kein Download nötig).
Formulare echt ausfüllen: Registrieren → Sammeln-Radio + „Losziehen" →
Countdown `.countdown` auf der Übersicht.

## Stolperfallen

- `node --test dist/test/` (Verzeichnis) schlägt fehl — Glob nutzen:
  `node --test "dist/test/*.test.js"`.
- Server killen ohne Selbstmord der eigenen Shell: `pkill -f 'dist/src/server[.]js'`
  (Zeichenklasse verhindert Selbst-Match).
- Kein `sqlite3`-CLI im Container — DB-Inspektion per
  `node -e "const {DatabaseSync}=require('node:sqlite'); …"`.
- Flash-Texte enthalten EJS-escaped Anführungszeichen (`&#34;`) — beim Greppen beachten.
