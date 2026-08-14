import ActivityKit
import WidgetKit
import SwiftUI

/// Live Activity for a running cycle: the lock-screen banner, the three Dynamic
/// Island presentations, and the Apple Watch Smart Stack.
///
/// Like the home screen widget, the countdown is `Text(timerInterval:)` against
/// the phase's wall-clock end — the system ticks it without waking the
/// extension, so a running session costs no updates at all.
///
/// watchOS 11 mirrors iPhone Live Activities onto the wrist by itself, but in a
/// generic layout that was never designed for 44 mm. Declaring the `small`
/// family replaces it with `WatchBanner`. The modifier is iOS-side only
/// (`@available(watchOS, unavailable)`) — the watch is the renderer, not the
/// declarer.
struct FocusLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: FocusActivityAttributes.self) { context in
            FamilyAwareBanner(state: context.state)
                .activityBackgroundTint(Theme.Palette.paper)
                .activitySystemActionForegroundColor(Theme.Palette.ink)
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    ActivityEyebrow(state: context.state)
                        .padding(.leading, 4)
                }
                DynamicIslandExpandedRegion(.trailing) {
                    ActivityTimer(state: context.state, size: 22)
                        .foregroundStyle(Theme.Palette.ink)
                        .padding(.trailing, 4)
                }
                DynamicIslandExpandedRegion(.bottom) {
                    RevealBar(state: context.state)
                        .padding(.top, 2)
                }
            } compactLeading: {
                Circle()
                    .fill(Theme.Palette.accent)
                    .frame(width: 8, height: 8)
            } compactTrailing: {
                ActivityTimer(state: context.state, size: 14)
                    .foregroundStyle(Theme.Palette.accent)
            } minimal: {
                ActivityTimer(state: context.state, size: 13)
                    .foregroundStyle(Theme.Palette.accent)
            }
            .widgetURL(WidgetStore.startURL)
            .keylineTint(Theme.Palette.accent)
        }
        .supplementalActivityFamilies([.small])
    }
}

// MARK: - Building blocks

/// Picks the presentation for the surface the activity is being drawn on: the
/// watch's `small` family gets `WatchBanner`, everything else the lock screen's.
private struct FamilyAwareBanner: View {
    @Environment(\.activityFamily) private var family
    let state: FocusActivityAttributes.ContentState

    var body: some View {
        switch family {
        case .small: WatchBanner(state: state)
        default:     LockScreenBanner(state: state)
        }
    }
}

/// mm:ss — live while running, frozen while paused.
private struct ActivityTimer: View {
    let state: FocusActivityAttributes.ContentState
    var size: CGFloat

    var body: some View {
        Group {
            if !state.isTicking || state.endDate <= .now {
                Text(frozen)
            } else {
                Text(timerInterval: Date.now...state.endDate, countsDown: true)
            }
        }
        .font(Theme.Font.serif(size, weight: .light))
        .monospacedDigit()
        .lineLimit(1)
        .minimumScaleFactor(0.6)
    }

    private var frozen: String {
        String(format: "%02d:%02d", state.remainingSeconds / 60, state.remainingSeconds % 60)
    }
}

/// Uppercase status line in the app's eyebrow style.
private struct ActivityEyebrow: View {
    let state: FocusActivityAttributes.ContentState

    var body: some View {
        Text(label)
            .font(Theme.Font.sans(11, weight: .semibold))
            .tracking(1.6)
            .foregroundStyle(Theme.Palette.accent)
            .lineLimit(1)
            .minimumScaleFactor(0.8)
    }

    private var label: LocalizedStringKey {
        if state.isPaused { return "PAUSIERT" }
        switch state.phase {
        case .focus:      return "FOKUS LÄUFT"
        case .shortBreak: return "KURZE PAUSE"
        case .longBreak:  return "LANGE PAUSE"
        }
    }
}

/// Reveal progress: a thin bar plus "9 von 20 Teilen".
private struct RevealBar: View {
    let state: FocusActivityAttributes.ContentState

    private var fraction: Double {
        guard state.totalTiles > 0 else { return 0 }
        return min(1, Double(state.revealedTiles) / Double(state.totalTiles))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(Theme.Palette.progressTrack)
                    Capsule().fill(Theme.Palette.accent)
                        .frame(width: max(0, geo.size.width * fraction))
                }
            }
            .frame(height: 4)

            Text("\(state.revealedTiles) von \(state.totalTiles) Teilen enthüllt")
                .font(Theme.Font.sans(11))
                .foregroundStyle(Theme.Palette.muted2)
                .lineLimit(1)
        }
    }
}

/// The Apple Watch Smart Stack presentation.
///
/// Tighter than the lock screen in every dimension: the round label sits beside
/// the eyebrow instead of opposite it, the timer drops to 30pt, and the reveal
/// is a bar with a bare "9/20" — at this size the spelled-out
/// "9 von 20 Teilen enthüllt" is the first thing that stops being legible.
private struct WatchBanner: View {
    let state: FocusActivityAttributes.ContentState

    private var fraction: Double {
        guard state.totalTiles > 0 else { return 0 }
        return min(1, Double(state.revealedTiles) / Double(state.totalTiles))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 6) {
                ActivityEyebrow(state: state)
                if state.totalRounds > 1 {
                    Text(verbatim: "· \(state.round)/\(state.totalRounds)")
                        .font(Theme.Font.sans(11, weight: .medium))
                        .foregroundStyle(Theme.Palette.muted2)
                }
                Spacer(minLength: 0)
            }

            HStack(alignment: .firstTextBaseline, spacing: 8) {
                ActivityTimer(state: state, size: 30)
                    .foregroundStyle(Theme.Palette.ink)
                Spacer(minLength: 0)
                Text(verbatim: "\(state.revealedTiles)/\(state.totalTiles)")
                    .font(Theme.Font.sans(12, weight: .medium))
                    .foregroundStyle(Theme.Palette.muted2)
            }

            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(Theme.Palette.progressTrack)
                    Capsule().fill(Theme.Palette.accent)
                        .frame(width: max(0, geo.size.width * fraction))
                }
            }
            .frame(height: 3)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// The lock-screen / banner presentation.
private struct LockScreenBanner: View {
    let state: FocusActivityAttributes.ContentState

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline) {
                ActivityEyebrow(state: state)
                Spacer(minLength: 8)
                if state.totalRounds > 1 {
                    Text("Runde \(state.round) von \(state.totalRounds)")
                        .font(Theme.Font.sans(11, weight: .medium))
                        .foregroundStyle(Theme.Palette.muted2)
                        .lineLimit(1)
                }
            }

            ActivityTimer(state: state, size: 40)
                .foregroundStyle(Theme.Palette.ink)

            RevealBar(state: state)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
