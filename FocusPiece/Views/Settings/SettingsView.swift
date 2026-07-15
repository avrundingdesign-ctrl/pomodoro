import SwiftUI

/// Legal links shown in settings. Replace the privacy URL with the final
/// policy address before App Store submission.
enum LegalLinks {
    /// Apple's standard EULA for paid apps/content.
    static let terms = URL(string: "https://www.apple.com/legal/internet-services/itunes/dev/stdeula/")!
    static let privacy = URL(string: "https://focuspiece.app/datenschutz")!
}

/// Screen 10 — grouped settings.
struct SettingsView: View {
    @EnvironmentObject var app: AppModel

    private let durations = [15, 25, 45, 60]
    private let shortBreaks = [3, 5, 10]
    private let longBreaks = [10, 15, 20, 30]
    private let roundCounts = [1, 2, 3, 4, 5, 6]
    private let themes = ["Hell", "Dunkel", "System"]

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Einstellungen")
                    .font(Theme.Font.serif(32))
                    .tracking(-0.3)
                    .foregroundStyle(Theme.Palette.ink)
                Spacer()
            }
            .padding(.horizontal, 28)
            .padding(.top, 8).padding(.bottom, 16)
            .contentColumn()

            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    SettingsGroup(title: "Session") {
                        PickerRow(label: "Fokusdauer",
                                  value: "\(app.settings.selectedDuration) Min",
                                  options: durations.map { "\($0) Min" }) { picked in
                            if let m = leadingNumber(in: picked) { app.settings.selectedDuration = m }
                        }
                        Divider().overlay(Theme.Palette.hairline3)
                        PickerRow(label: "Runden",
                                  value: roundsLabel(app.settings.roundsPerCycle),
                                  options: roundCounts.map(roundsLabel)) { picked in
                            if let n = leadingNumber(in: picked) { app.settings.roundsPerCycle = n }
                        }
                        Divider().overlay(Theme.Palette.hairline3)
                        PickerRow(label: "Kurze Pause",
                                  value: "\(app.settings.shortBreakMinutes) Min",
                                  options: shortBreaks.map { "\($0) Min" }) { picked in
                            if let m = leadingNumber(in: picked) { app.settings.shortBreakMinutes = m }
                        }
                        Divider().overlay(Theme.Palette.hairline3)
                        PickerRow(label: "Lange Pause",
                                  value: "\(app.settings.longBreakMinutes) Min",
                                  options: longBreaks.map { "\($0) Min" }) { picked in
                            if let m = leadingNumber(in: picked) { app.settings.longBreakMinutes = m }
                        }
                        Divider().overlay(Theme.Palette.hairline3)
                        ToggleRow(label: "Sanfter Start", isOn: $app.settings.gentleStart)
                    }

                    SettingsGroup(title: "Klang & Haptik") {
                        ToggleRow(label: "Abschluss-Ton", isOn: $app.settings.completionTone)
                        Divider().overlay(Theme.Palette.hairline3)
                        ToggleRow(label: "Haptisches Feedback", isOn: $app.settings.haptics)
                    }

                    SettingsGroup(title: "Darstellung") {
                        PickerRow(label: "Thema",
                                  value: app.settings.theme,
                                  options: themes) { app.settings.theme = $0 }
                        Divider().overlay(Theme.Palette.hairline3)
                        ToggleRow(label: "Benachrichtigungen", isOn: $app.settings.notifications)
                            .onChange(of: app.settings.notifications) { _, isOn in
                                if isOn { NotificationManager.shared.requestPermissionIfNeeded() }
                            }
                    }

                    SettingsGroup(title: "Rechtliches") {
                        LinkRow(label: "Datenschutz", url: LegalLinks.privacy)
                        Divider().overlay(Theme.Palette.hairline3)
                        LinkRow(label: "Nutzungsbedingungen", url: LegalLinks.terms)
                    }

                    Text("FocusPiece · Version 1.0")
                        .font(Theme.Font.sans(13))
                        .foregroundStyle(Theme.Palette.muted3Soft)
                        .frame(maxWidth: .infinity)
                        .padding(.top, 4)
                }
                .padding(.horizontal, 24)
                .padding(.bottom, 24)
                .contentColumn()
            }
        }
        .background(Theme.Palette.paper)
    }

    /// "4 Runden" / "1 Runde" — the picker option labels.
    private func roundsLabel(_ n: Int) -> String { n == 1 ? "1 Runde" : "\(n) Runden" }
    /// Parse the leading integer out of a picked option like "15 Min".
    private func leadingNumber(in text: String) -> Int? { Int(text.prefix(while: \.isNumber)) }
}

// MARK: - Building blocks
private struct SettingsGroup<Content: View>: View {
    let title: String
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(Theme.Font.sans(11, weight: .semibold))
                .tracking(1.1)
                .textCase(.uppercase)
                .foregroundStyle(Theme.Palette.muted3)
                .padding(.leading, 12)
            VStack(spacing: 0) { content }
                .padding(.horizontal, 16)
                .background(Theme.Palette.surface)
                .overlay(
                    RoundedRectangle(cornerRadius: Theme.Radius.settingCard, style: .continuous)
                        .stroke(Theme.Palette.hairline2, lineWidth: 1)
                )
                .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.settingCard, style: .continuous))
        }
    }
}

private struct ToggleRow: View {
    let label: String
    @Binding var isOn: Bool

    var body: some View {
        HStack {
            Text(label)
                .font(Theme.Font.sans(15))
                .foregroundStyle(Theme.Palette.ink)
            Spacer()
            AppToggle(isOn: $isOn)
        }
        .padding(.vertical, 14)
    }
}

private struct LinkRow: View {
    let label: String
    let url: URL

    var body: some View {
        Link(destination: url) {
            HStack {
                Text(label)
                    .font(Theme.Font.sans(15))
                    .foregroundStyle(Theme.Palette.ink)
                Spacer()
                Image(systemName: "arrow.up.right")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Color(hex: 0xBCB3A5))
            }
            .padding(.vertical, 14)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

private struct PickerRow: View {
    let label: String
    let value: String
    let options: [String]
    let onSelect: (String) -> Void

    var body: some View {
        Menu {
            ForEach(options, id: \.self) { opt in
                Button(opt) { onSelect(opt) }
            }
        } label: {
            HStack {
                Text(label)
                    .font(Theme.Font.sans(15))
                    .foregroundStyle(Theme.Palette.ink)
                Spacer()
                Text(value)
                    .font(Theme.Font.sans(15))
                    .foregroundStyle(Theme.Palette.muted2)
                Image(systemName: "chevron.right")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Color(hex: 0xBCB3A5))
            }
            .padding(.vertical, 14)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}
