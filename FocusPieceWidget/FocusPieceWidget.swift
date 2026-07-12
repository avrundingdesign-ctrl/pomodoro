import WidgetKit
import SwiftUI

// MARK: - Timeline

struct FocusEntry: TimelineEntry {
    let date: Date
    let snapshot: WidgetSnapshot
}

/// Single-entry timeline: the app pushes a fresh snapshot (and reloads the
/// timeline) on every relevant state change, so the widget never has to guess.
struct FocusProvider: TimelineProvider {
    func placeholder(in context: Context) -> FocusEntry {
        FocusEntry(date: .now, snapshot: .placeholder)
    }

    func getSnapshot(in context: Context, completion: @escaping (FocusEntry) -> Void) {
        completion(FocusEntry(date: .now,
                              snapshot: context.isPreview ? .placeholder : WidgetStore.load()))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<FocusEntry>) -> Void) {
        let snapshot = WidgetStore.load()
        let now = FocusEntry(date: .now, snapshot: snapshot)
        // While running, Text(timerInterval:) animates the countdown on its own;
        // one extra entry flips the face back to "bereit" when time is up.
        if snapshot.phase == .running, let end = snapshot.endDate, end > .now {
            var done = snapshot
            done.phase = .ready
            done.remainingSeconds = nil
            done.endDate = nil
            completion(Timeline(entries: [now, FocusEntry(date: end, snapshot: done)],
                                policy: .never))
        } else {
            completion(Timeline(entries: [now], policy: .never))
        }
    }
}

// MARK: - Widget

struct FocusPieceWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "FocusPieceWidget", provider: FocusProvider()) { entry in
            FocusWidgetView(entry: entry)
        }
        .configurationDisplayName("Fokus")
        .description("Nächste Session, Sammlung und Fokuszeit im Blick.")
        .supportedFamilies([.systemSmall, .systemMedium, .accessoryRectangular])
    }
}

// MARK: - Views

struct FocusWidgetView: View {
    @Environment(\.widgetFamily) private var family
    let entry: FocusEntry

    var body: some View {
        switch family {
        case .systemMedium:
            MediumFocusView(entry: entry)
                .containerBackground(for: .widget) { Theme.Palette.paper }
        case .accessoryRectangular:
            AccessoryFocusView(entry: entry)
                .containerBackground(for: .widget) { Color.clear }
                .widgetURL(WidgetStore.startURL)
        default:
            SmallFocusView(entry: entry)
                .containerBackground(for: .widget) { Theme.Palette.paper }
                .widgetURL(WidgetStore.startURL)
        }
    }
}

/// The big serif countdown: live while running, frozen otherwise.
private struct TimerText: View {
    let entry: FocusEntry
    var size: CGFloat

    var body: some View {
        Group {
            if entry.snapshot.phase == .running,
               let end = entry.snapshot.endDate, end > entry.date {
                Text(timerInterval: entry.date...end, countsDown: true)
            } else {
                Text(entry.snapshot.frozenTimeString)
            }
        }
        .font(Theme.Font.serif(size, weight: .light))
        .tracking(0.5)
        .monospacedDigit()
        .lineLimit(1)
        .minimumScaleFactor(0.6)
    }
}

/// Uppercase state label in the app's eyebrow style.
private struct EyebrowText: View {
    let text: String
    var size: CGFloat = 11

    var body: some View {
        Text(text)
            .font(Theme.Font.sans(size, weight: .semibold))
            .tracking(1.8)
            .foregroundStyle(Theme.Palette.accent)
            .lineLimit(1)
            .minimumScaleFactor(0.8)
    }
}

/// Terracotta start pill — the widget's PrimaryButton.
private struct StartPill: View {
    let title: String

    var body: some View {
        Text(title)
            .font(Theme.Font.sans(15, weight: .semibold))
            .foregroundStyle(.white)
            .padding(.horizontal, 22)
            .frame(height: 44)
            .background(
                Theme.Palette.accent,
                in: RoundedRectangle(cornerRadius: Theme.Radius.primaryButton,
                                     style: .continuous))
    }
}

/// "✓ 3 | ▢ 2 | 1 Std 15 Min" — sessions, collected works, total focus time.
private struct StatsRow: View {
    let snapshot: WidgetSnapshot

    var body: some View {
        HStack(spacing: 9) {
            stat(icon: "checkmark.seal.fill", tint: Theme.Palette.accent,
                 value: "\(snapshot.sessionsCompleted)")
            divider
            stat(icon: "photo.on.rectangle", tint: Theme.Palette.muted3,
                 value: "\(snapshot.worksUnlocked)")
            divider
            stat(icon: "clock", tint: Theme.Palette.muted3,
                 value: snapshot.focusTimeString)
        }
        .lineLimit(1)
    }

    private func stat(icon: String, tint: Color, value: String) -> some View {
        HStack(spacing: 4) {
            Image(systemName: icon)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(tint)
            Text(value)
                .font(Theme.Font.sans(13, weight: .semibold))
                .foregroundStyle(Theme.Palette.ink)
        }
    }

    private var divider: some View {
        Rectangle()
            .fill(Theme.Palette.hairline)
            .frame(width: 1, height: 12)
    }
}

/// Medium widget — the layout from the design mock, in museum paper & ink:
/// label + timer + stats on the left, the Start pill on the right.
private struct MediumFocusView: View {
    let entry: FocusEntry
    private var snapshot: WidgetSnapshot { entry.snapshot }

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 0) {
                EyebrowText(text: snapshot.eyebrowText)
                TimerText(entry: entry, size: 46)
                    .foregroundStyle(Theme.Palette.ink)
                    .padding(.top, 2)
                Spacer(minLength: 4)
                StatsRow(snapshot: snapshot)
            }
            Spacer(minLength: 0)
            if snapshot.phase != .running {
                Link(destination: WidgetStore.startURL) {
                    StartPill(title: snapshot.phase == .paused ? "Weiter" : "Start")
                }
            }
        }
    }
}

/// Small widget — label, timer, one quiet stats line.
private struct SmallFocusView: View {
    let entry: FocusEntry
    private var snapshot: WidgetSnapshot { entry.snapshot }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            EyebrowText(text: snapshot.eyebrowText, size: 10)
            TimerText(entry: entry, size: 37)
                .foregroundStyle(Theme.Palette.ink)
                .padding(.top, 3)
            Spacer(minLength: 4)
            HStack(spacing: 4) {
                Image(systemName: "checkmark.seal.fill")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(Theme.Palette.accent)
                Text("\(snapshot.sessionsCompleted) · \(snapshot.focusTimeString)")
                    .font(Theme.Font.sans(11, weight: .medium))
                    .foregroundStyle(Theme.Palette.muted2)
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
    }
}

/// Lock-screen rectangular widget — the system renders it vibrant/tinted.
private struct AccessoryFocusView: View {
    let entry: FocusEntry
    private var snapshot: WidgetSnapshot { entry.snapshot }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(snapshot.eyebrowText)
                .font(Theme.Font.sans(11, weight: .semibold))
                .tracking(1.4)
                .widgetAccentable()
            TimerText(entry: entry, size: 24)
            Text("\(snapshot.sessionsCompleted) vollendet · \(snapshot.focusTimeString)")
                .font(Theme.Font.sans(11, weight: .medium))
                .opacity(0.8)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

// MARK: - Previews

#Preview("Medium · bereit", as: .systemMedium) {
    FocusPieceWidget()
} timeline: {
    FocusEntry(date: .now, snapshot: .placeholder)
}

#Preview("Small · bereit", as: .systemSmall) {
    FocusPieceWidget()
} timeline: {
    FocusEntry(date: .now, snapshot: .placeholder)
}
