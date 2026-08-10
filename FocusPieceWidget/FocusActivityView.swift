import ActivityKit
import WidgetKit
import SwiftUI

/// Live Activity for a running cycle: the lock-screen banner and the three
/// Dynamic Island presentations.
///
/// Like the home screen widget, the countdown is `Text(timerInterval:)` against
/// the phase's wall-clock end — the system ticks it without waking the
/// extension, so a running session costs no updates at all.
struct FocusLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: FocusActivityAttributes.self) { context in
            LockScreenBanner(state: context.state)
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
    }
}

// MARK: - Building blocks

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
