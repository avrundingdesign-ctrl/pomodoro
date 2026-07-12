# FocusPiece

A calm, museum-like focus timer for iOS. During a focus session a hidden,
blurred Public-Domain painting is revealed tile by tile — every focused stretch
of time turns one more 4×5 tile from *blurred* to *sharp*. Finishing a session
unlocks the work and files it in a personal gallery. No streaks, no confetti —
quiet and focused.

Built in **SwiftUI** from the `design_handoff_focuspiece` hi-fi spec.

## Screens

| Group | Screens |
|---|---|
| Onboarding | Willkommen · So funktioniert es · Erste Session |
| Session | Bereit · Fokus läuft · Fast enthüllt · Vollendet |
| Galerie | Sammlung · Werk-Detail |
| Einstellungen | Einstellungen |
| Widget | Home-Screen (klein/mittel) · Sperrbildschirm (rechteckig) |

## The reveal mechanic

A sharp painting sits under a 20-tile grid (4 columns × 5 rows). Hidden tiles
show a blurred copy of the region plus a faint paper veil; revealed tiles show
the sharp image. Tiles turn sharp one at a time in a fixed, scattered order so
the reveal feels organic:

```
[7, 14, 2, 11, 18, 5, 9, 0, 16, 3, 12, 19, 6, 1, 15, 8, 17, 4, 13, 10]
```

`revealedCount = floor(progress · 20)`, driven by the countdown. Leaving the app
or pausing halts both the timer and the reveal. See
`FocusPiece/Views/Session/RevealGridView.swift`.

## Running it

Requirements: **Xcode 16+**, iOS 17 SDK.

```sh
open FocusPiece.xcodeproj
# pick an iPhone simulator and Run (⌘R)
```

The app builds and runs out of the box. The eight paintings are **not**
committed (large Public-Domain JPGs); until you fetch them the app shows a calm
placeholder. To bundle the real art:

```sh
./Scripts/fetch_artworks.sh        # downloads to FocusPiece/Resources/Artworks
```

Then re-build. (The fonts — Hanken Grotesk & Newsreader, OFL — *are* bundled.)

## Project layout

```
FocusPiece/
  FocusPieceApp.swift          App entry point
  Theme.swift                  Design tokens (colors, type scale, radii)
  Models/
    Artwork.swift              Artwork model + the 8 seed works
    AppModel.swift             Persistent app state (settings, collection)
    SessionModel.swift         Countdown + reveal logic
  Views/
    RootView.swift             Onboarding gate + custom tab bar
    Onboarding/                3 onboarding screens
    Session/                   Ready/Running/Complete + RevealGridView
    Gallery/                   Collection grid + work detail
    Settings/                  Grouped settings
    Components/                Buttons, toggle, tab bar, image loader
  Resources/Fonts/             Bundled OFL fonts
  Assets.xcassets/             AccentColor, AppIcon, LaunchBackground
FocusPieceWidget/              WidgetKit extension (home & lock screen)
  FocusPieceWidget.swift       Timeline provider + widget views
  FocusPieceWidgetBundle.swift Widget bundle entry point
Scripts/fetch_artworks.sh      Download the Public-Domain paintings
```

## Widget

A WidgetKit extension mirrors the session in the app's museum style — paper
background, terracotta eyebrow, serif countdown:

- **Home screen (small & medium):** next session ("FOKUS · 25:00"), the stats
  row (vollendete Sessions · gesammelte Werke · Fokuszeit) and a terracotta
  **Start** pill. While a session runs the label flips to "FOKUS LÄUFT" with a
  live countdown; paused sessions show "PAUSIERT" and a **Weiter** pill.
- **Lock screen (rectangular):** the same state, rendered vibrant by iOS.

The app publishes a `WidgetSnapshot` (`Models/WidgetState.swift`) into the
app-group container `group.com.focuspiece.app` on every relevant change; the
widget only reads. The Start/Weiter pill deep-links via `focuspiece://start`,
which switches to the Fokus tab and begins the session. On a real device,
enable the App Group capability for both targets under Signing & Capabilities
(the simulator needs no provisioning).

## Notes

- Design tokens are taken verbatim from the handoff and centralised in
  `Theme.swift`. The HTML reference is binding for visuals.
- Settings & collection persist via `UserDefaults` (Codable).
- Artworks are Public Domain (Wikimedia Commons); fonts are OFL.
