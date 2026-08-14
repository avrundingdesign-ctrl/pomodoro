# Setting up the watchOS target

The Swift in this folder is complete but has no target to build against yet.
Creating the target is a few clicks in Xcode that are much easier to get right
there than by hand-editing `project.pbxproj` (`objectVersion = 77`, where one
wrong entry is nearly invisible in a diff).

The filenames here deliberately avoid the ones Xcode's wizard generates
(`FocusPieceWatchApp.swift`, `ContentView.swift`, `Assets.xcassets`), so nothing
collides. Because the folder becomes a `PBXFileSystemSynchronizedRootGroup`,
Xcode picks these files up on its own once the target exists.

## 1. Create the target

`File > New > Target > watchOS > App`

| Field | Value |
|---|---|
| Product Name | `FocusPieceWatch` |
| Bundle Identifier | `com.focuspiece.app.watchkitapp` — **must** be exactly `<iOS bundle id>.watchkitapp`, or the system will not recognise the pairing |
| Interface / Language | SwiftUI / Swift |
| Include Notification Scene | yes |
| Deployment Target | **watchOS 10.0** — covers Series 4 and up, and is what `containerBackground(_:for:)` needs |

When Xcode asks, let it create the folder here (`FocusPieceWatch`). Delete the
`ContentView.swift` it generates; keep its `Assets.xcassets` for the app icon.

## 2. Wire up the entry point

Replace the body of Xcode's generated `FocusPieceWatchApp.swift` with:

```swift
import SwiftUI

@main
struct FocusPieceWatchApp: App {
    @StateObject private var model = WatchModel()

    var body: some Scene {
        WindowGroup {
            WatchRootView()
                .environmentObject(model)
                .task { model.activate() }
        }
    }
}
```

## 3. Share the iPhone code

Select each file below and tick **FocusPieceWatch** in the File Inspector's
Target Membership. Xcode writes a `PBXFileSystemSynchronizedBuildFileExceptionSet`
for it, exactly as it already does for `FocusPieceWidgetExtension`.

| File | Why |
|---|---|
| `FocusPiece/Models/SessionModel.swift` | the state machine, shared rather than reimplemented |
| `FocusPiece/Models/SessionSnapshot.swift` | the wire format |
| `FocusPiece/Models/Artwork.swift` | pure Foundation since the `seedCollection` move |
| `FocusPiece/Services/NotificationManager.swift` | `UserNotifications` is fully available on watchOS |
| `FocusPiece/Services/Feedback.swift` | has a `WKInterfaceDevice` branch |
| `FocusPiece/Theme.swift` | palette + type scale; `Color(light:dark:)` resolves to the dark value on watchOS |
| `FocusPiece/Views/Components/ArtworkImage.swift` | watchOS's UIKit subset includes `UIImage` |

Do **not** share `WidgetState.swift` (WidgetKit + app group are phone-side) or
`ArtworkPack.swift` (it would drag all 37 works' translations in — the watch
only ever shows the one painting the snapshot names).

## 4. Fonts

Add `Newsreader-Light.ttf`, `Newsreader-Regular.ttf`, `Newsreader-Medium.ttf`
and `HankenGrotesk-Regular/Medium/SemiBold.ttf` from
`FocusPiece/Resources/Fonts/` to the target, and list them under `UIAppFonts` in
the watch `Info.plist`. Not all eight — the italic and bold faces are unused
here.

If a font is missing, SwiftUI falls back to the system face silently rather than
crashing, so this is worth checking visually on a real 41 mm device: at these
sizes `Newsreader-Light` is thin, and switching the labels to system-rounded may
read better.

## 5. Strings

`String(localized:)` resolves against `Bundle.main`, so the watch bundle needs
its own catalogue. Add `Localizable.xcstrings` to the target and give it keys
for what the shared code and these views use:

- from `SessionModel`: `"\(n) VON \(m) TEILEN"`, `"Runde \(r) von \(t)"`, and the
  four `scheduleEndNotification` strings (unused while the phone owns the alert,
  but they compile)
- from the views: `FOKUS`, `BEREIT`, `PAUSIERT`, `FOKUS LÄUFT`, `KURZE PAUSE`,
  `LANGE PAUSE`, `"Fokus beginnen"`, `"\(u) von \(t) Werken"`,
  `"\(n)/\(m) Teile"`, `"iPhone nicht in Reichweite"`, `"Lange Pause"`, `"Fertig"`

Source language is German, same as the other two catalogues.

## 6. Thumbnails

```
./Scripts/make_watch_thumbs.sh
```

Writes `FocusPieceWatch/Resources/Thumbs/` — 37 JPGs, 320 px long edge, ~800 KB
all told, versus the 20 MB the phone bundles. Add the folder to the target. Re-run
it whenever a pack is added.

## 7. Entitlements

Create `FocusPieceWatch/FocusPieceWatch.entitlements` with the app group
`group.com.focuspiece.app`. Unused today — app groups do not span iPhone and
Watch, which is why the link uses WatchConnectivity — but a complication reading
a local snapshot later will want it, and adding it now is cheaper than adding it
then.

Also: register `com.focuspiece.app.watchkitapp` in the Developer portal with App
Groups enabled. No new App Store Connect record — the watch app ships inside the
existing one — but it does need its own app icon and screenshots to submit.

## 8. Build and check

```
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild build \
  -project FocusPiece.xcodeproj -scheme FocusPieceWatch \
  -destination 'platform=watchOS Simulator,name=Apple Watch Series 10 (46mm)' \
  CODE_SIGNING_ALLOWED=NO
```

The watchOS 26.2 simulator runtime is installed. Paired simulators
(`xcrun simctl list pairs`) do carry WCSession, so the two-way flow is testable
without hardware: snapshot delivery, commands in both directions, Lamport
ordering, and recovery after unreachability (pause the watch sim, start on the
phone, resume it — the context must arrive late and still be correct).

## Still open

- **The double buzz.** The phone schedules `fp.sessionEnd`; watchOS also forwards
  iPhone notifications to the wrist. `WatchModel.observe` additionally buzzes
  from the local clock while the app is open. Whether that adds up to one buzz or
  two cannot be settled from the documentation — it needs a real paired device.
  If it turns out to be two, the fix is the `watchOwnsAlert` route: let the watch
  schedule and pass `notifyOnCompletion: false` on the phone.
- **Device builds hang from the CLI** on this Mac (signing waits on something
  only Xcode's UI shows). Use the Run button for anything on hardware.

The Smart Stack layout is live: the app now targets iOS 18, so
`FocusLiveActivity` declares the `small` family directly and a paired watch on
watchOS 11 gets `WatchBanner` in its Smart Stack whether or not this watch app
is installed. Worth looking at on a real wrist alongside the app itself, since
the two are separate surfaces that will be seen side by side.
