import Foundation
import WidgetKit

/// Snapshot of app state shared with the home/lock screen widget through the
/// app-group container. The app writes it; the widget only reads.
struct WidgetSnapshot: Codable, Equatable {
    enum Phase: String, Codable { case ready, running, paused }

    var phase: Phase = .ready
    /// Configured session length ("Standarddauer") in minutes — the ready timer.
    var selectedMinutes: Int = 25
    /// Seconds left while paused (frozen countdown).
    var remainingSeconds: Int? = nil
    /// Wall-clock end of a running session (drives the live countdown).
    var endDate: Date? = nil
    var worksUnlocked: Int = 0
    var worksTotal: Int = 8
    var totalFocusMinutes: Int = 0

    /// Sample shown in the widget gallery ("1 Std 15 Min").
    static let placeholder = WidgetSnapshot(worksUnlocked: 3,
                                            worksTotal: 8,
                                            totalFocusMinutes: 75)

    // MARK: Display helpers
    /// The frozen mm:ss shown when not running — ready: full duration, paused: remainder.
    var frozenTimeString: String {
        let seconds = phase == .paused ? (remainingSeconds ?? selectedMinutes * 60)
                                       : selectedMinutes * 60
        return String(format: "%02d:%02d", seconds / 60, seconds % 60)
    }

    /// Total focus time in app vocabulary — "45 Min", "2 Std", "1 Std 15 Min".
    /// This type is compiled into the app *and* the widget extension, so both
    /// bundles carry these keys in their own string catalog.
    var focusTimeString: String {
        let h = totalFocusMinutes / 60, m = totalFocusMinutes % 60
        if h == 0 { return String(localized: "\(m) Min") }
        return m == 0 ? String(localized: "\(h) Std")
                      : String(localized: "\(h) Std \(m) Min")
    }

    /// Uppercase state label, mirroring the in-app status line.
    var eyebrowText: String {
        switch phase {
        case .ready:   return String(localized: "FOKUS")
        case .running: return String(localized: "FOKUS LÄUFT")
        case .paused:  return String(localized: "PAUSIERT")
        }
    }
}

/// Reads/writes the snapshot in the shared app-group defaults.
enum WidgetStore {
    static let appGroupID = "group.com.focuspiece.app"
    static let snapshotKey = "fp.widgetSnapshot"
    /// Deep link the widget's Start button sends into the app.
    static let startURL = URL(string: "focuspiece://start")!

    static var defaults: UserDefaults {
        UserDefaults(suiteName: appGroupID) ?? .standard
    }

    /// App-side: persist the snapshot and ask WidgetKit to re-render.
    static func publish(_ snapshot: WidgetSnapshot) {
        if let data = try? JSONEncoder().encode(snapshot) {
            defaults.set(data, forKey: snapshotKey)
        }
        WidgetCenter.shared.reloadAllTimelines()
    }

    /// Widget-side: last published snapshot; a neutral default before first launch.
    static func load() -> WidgetSnapshot {
        guard let data = defaults.data(forKey: snapshotKey),
              let snapshot = try? JSONDecoder().decode(WidgetSnapshot.self, from: data)
        else { return WidgetSnapshot() }
        return snapshot
    }
}
