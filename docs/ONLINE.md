# FocusPiece Online-Modus — Architektur & Produktionsplan

Stand: Juli 2026. Dieses Dokument beschreibt, wie der Online-Modus aufgebaut
ist, was heute lokal läuft und welche konkreten Schritte für den echten
Multi-Device-Betrieb (Firebase) nötig sind.

## 1. Architektur

```
Views (SwiftUI)
   │  @EnvironmentObject
   ▼
OnlineModel (@MainActor, ObservableObject)          FocusPiece/Online/OnlineModel.swift
   │  spricht ausschließlich über das Protokoll
   ▼
FocusBackend (Protokoll)                            FocusPiece/Online/Backend.swift
   ├── LocalBackend   ← heute aktiv                 FocusPiece/Online/LocalBackend.swift
   └── FirebaseBackend ← Produktions-Slot (s. §5)
```

- **`FocusBackend`** kapselt alles Serverseitige: Konten, Profile, Freunde,
  Presence, Nachrichten, Community-Feed. Der Tausch Local → Firebase berührt
  weder `OnlineModel` noch eine einzige View.
- **`LocalBackend`** ist ein voll funktionsfähiges Offline-Backend:
  persistente Konten (Apple/Google/E-Mail), eine simulierte Community aus
  12 Personas mit deterministisch generierten 12-Wochen-Historien, laufenden
  Sessions (Start/Fortschritt/Abschluss über `tick()` alle 15 s), Antworten
  auf Nachrichten und automatische Freundschafts-Interaktionen.
  Persistenz: `Application Support/FocusPiece/online_local.json`.
- **`OnlineModel`** hält den beobachtbaren Zustand (Account, Freunde,
  Presence-Map, Chats, Feed, Wallet, Pakete) und verdrahtet StoreKit sowie
  die Session-Hooks aus dem Fokus-Tab.
- **Statistiken** (`StatsEngine`) sind reine Funktionen über
  `[FocusSessionRecord]` — identisch für das eigene Profil (echte Historie)
  und fremde Profile. **Achievements** werden daraus abgeleitet, nie separat
  gespeichert.

## 2. Features und Fundstellen

| Feature | Code |
|---|---|
| Konto (Apple echt, Google/E-Mail lokal) | `Views/Auth/AuthView.swift`, `OnlineGate` |
| Profil, Profilbild (PhotosPicker), Handle, Stadt | `Views/Profile/ProfileEditorSheet.swift` |
| Statistik-Dashboard (Woche, Heatmap, Tagesprofil, Wochentage) | `Views/Profile/StatsDashboard.swift` |
| Erfolge | `OnlineTypes.swift` (`Achievement`), `AchievementsGrid` |
| Live-Übersicht + Anfeuern | `Views/Community/LiveNowView.swift` |
| Karte (MapKit, Live-Ringe, Profil-Sheets) | `Views/Community/CommunityMapView.swift` |
| Freunde (Suche, Anfragen) | `Views/Community/FriendsView.swift` |
| Chat (Text, Nudges, Kunstgruß) + Inbox | `Views/Community/ChatView.swift` |
| Store (Pakete + Münzkauf) | `Views/Store/StoreView.swift`, `Online/ArtPacks.swift` |
| StoreKit 2 | `Online/IAPManager.swift`, `FocusPiece.storekit` |

## 3. Münz-Ökonomie

- **Verdienen** (`CoinRules`): 2 Münzen je 5 Fokus-Minuten pro Runde
  (25-Min-Runde = 10), +15 Zyklus-Bonus, +5 für die erste Runde des Tages.
  Ein typischer Tag (4×25 Min) bringt ≈ 60 Münzen.
- **Ausgeben**: Bilder-Pakete 180–260 Münzen (= 3–5 fokussierte Tage).
  Gekaufte Werke landen *gesperrt* in der Galerie — enthüllt wird nur durch
  Fokus. Der Kern-Loop bleibt intakt.
- **Kaufen** (Consumables): `com.focuspiece.coins.small/medium/large` =
  300/800/2000 Münzen für 2,99/5,99/11,99 €.
- **Produktion**: Wallet wird serverseitig geführt (Ledger, s. §5) —
  clientseitige Gutschriften sind nur die Demo-Abkürzung.

## 4. StoreKit testen & ausliefern

- **Simulator/Debug**: `FocusPiece.storekit` ist im Scheme hinterlegt.
  App über Xcode starten → Kauf-Flows laufen komplett lokal (auch
  Fehlerfälle über den StoreKit-Transaktions-Manager in Xcode testbar).
  Hinweis: Wird die App per `simctl launch` (statt Xcode) gestartet, greift
  die StoreKit-Konfiguration nicht — der Store zeigt dann einen Hinweis.
- **App Store Connect**: dieselben drei Produkt-IDs als Consumables anlegen;
  Preise wie oben. Danach funktioniert Sandbox-Testing auf dem Gerät ohne
  Codeänderung.
- **Serverseitige Validierung (Produktion)**: Cloud Function verifiziert
  Transaktionen über die App Store Server API (JWS), schreibt die Münzen in
  den Ledger und markiert die `transactionId` als verbraucht (Dedupe).

## 5. Produktionsplan: FirebaseBackend

Empfohlener Stack: **Firebase Auth + Firestore + Realtime DB (Presence) +
Storage (Avatare) + Cloud Functions + FCM (Push)**.

### 5.1 Setup
1. Firebase-Projekt anlegen, iOS-App `com.focuspiece.app` registrieren,
   `GoogleService-Info.plist` ins Projekt.
2. SPM-Pakete: `firebase-ios-sdk` (FirebaseAuth, FirebaseFirestore,
   FirebaseDatabase, FirebaseStorage, FirebaseMessaging) und `GoogleSignIn`.
3. Sign in with Apple ist clientseitig fertig (Entitlement + Button);
   in Firebase Auth nur den Apple-Provider aktivieren und das Credential
   per `OAuthProvider.credential(withProviderID: "apple.com", …)` durchreichen.
   Google: `GIDSignIn`-Flow, dann `GoogleAuthProvider.credential(…)` —
   der Demo-Pfad in `AuthView.signInGoogle()` wird dadurch ersetzt.
4. `FirebaseBackend: FocusBackend` implementieren und in
   `OnlineModel.init` einsetzen — mehr App-Änderung ist nicht nötig.

### 5.2 Datenmodell (Firestore)
```
users/{uid}:            handle, displayName, cityID, bio, photoURL, joinedAt, providers
handles/{handle}:       uid                       // Eindeutigkeit per Transaktion
users/{uid}/rounds/{id}: date, minutes, artworkID // Quelle für Stats & Coins
friendships/{uidA_uidB}: users: [a, b], since
requests/{id}:          from, to, sentAt
chats/{chatID}/messages/{id}: senderID, sentAt, kind(text|nudge|artCard), payload, readAt
events/{id}:            userID, date, kind, payload   // Community-Feed (TTL ~7 Tage)
wallets/{uid}:          coins                     // NUR Functions schreiben hier
wallets/{uid}/ledger/{id}: amount, reason, ref    // inkl. IAP-transactionId
```
**Presence** in der Realtime DB (`presence/{uid}`) mit `onDisconnect`-Hook —
genau das Verhalten, das `Presence`/`FocusStatus` heute abbilden.

### 5.3 Security Rules (Kern)
- `users`: lesbar für Angemeldete, schreibbar nur vom Besitzer
  (ohne `wallet`-Felder).
- `chats`: nur die beiden Teilnehmer.
- `wallets` + `ledger`: Client read-only; Schreiben ausschließlich über
  Cloud Functions (Coin-Gutschrift prüft die eingereichte Runde auf
  Plausibilität — Dauer, Frequenz, Tageslimit).
- `handles`: Anlage nur per Transaktion zusammen mit dem eigenen `users`-Doc.

### 5.4 Cloud Functions
- `onRoundCreated` → Münzen nach `CoinRules` gutschreiben (Anti-Cheat).
- `verifyPurchase` → App Store Server API, Ledger-Gutschrift, Dedupe.
- `onMessageCreated` / `onRequestCreated` → FCM-Push („🔥 Jonas feuert dich an“).
- `feedFanout` + TTL-Cleanup für `events`.

### 5.5 Migrationsreihenfolge
Auth → Profile/Handles → Presence → Freunde/Chat → Feed → Wallet/IAP.
Jede Stufe ist hinter dem Protokoll einzeln umschaltbar; das LocalBackend
bleibt als Offline-/Demo-Modus und für UI-Tests erhalten.

## 6. Bekannte Grenzen des lokalen Modus

- Konten, Freunde, Chats und Münzen existieren nur auf diesem Gerät.
- Die Community ist simuliert (12 Personas); echte Nutzer sieht erst das
  FirebaseBackend.
- Google-Login legt ein lokales Konto an (SDK-Anbindung siehe §5.1).
- Münzen werden clientseitig gutgeschrieben (Produktion: Ledger via Functions).

## 7. Naheliegende Ausbaustufen

- Wochen-Challenges & Freundes-Duelle („Wer enthüllt zuerst?“)
- Gemeinsame Sessions (Focus Rooms) mit geteiltem Timer
- Saisonale Pakete / tägliche Login-Münzen
- Widget & Live Activity mit Live-Fortschritt der Freunde
