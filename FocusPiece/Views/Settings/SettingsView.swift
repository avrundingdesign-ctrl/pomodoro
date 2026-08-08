import SwiftUI

/// Legal links shown in settings and with the purchase UI.
enum LegalLinks {
    /// Apple's standard EULA for paid apps/content.
    static let terms = URL(string: "https://www.apple.com/legal/internet-services/itunes/dev/stdeula/")!
    static let privacy = URL(string: "https://trin.studio/datenschutz")!
}

/// Screen 10 — grouped settings.
struct SettingsView: View {
    @EnvironmentObject var app: AppModel
    @EnvironmentObject var store: StoreModel
    @State private var showPaywall = false
    @State private var restoring = false
    @State private var restoreDone = false

    private let durations = [15, 25, 45, 60]
    private let shortBreaks = [3, 5, 10]
    private let longBreaks = [10, 15, 20, 30]
    private let roundCounts = [1, 2, 3, 4, 5, 6]

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
                                  selection: $app.settings.selectedDuration,
                                  options: durations, display: Self.minutesLabel)
                        Divider().overlay(Theme.Palette.hairline3)
                        PickerRow(label: "Runden",
                                  selection: $app.settings.roundsPerCycle,
                                  options: roundCounts, display: Self.roundsLabel)
                        Divider().overlay(Theme.Palette.hairline3)
                        PickerRow(label: "Kurze Pause",
                                  selection: $app.settings.shortBreakMinutes,
                                  options: shortBreaks, display: Self.minutesLabel)
                        Divider().overlay(Theme.Palette.hairline3)
                        PickerRow(label: "Lange Pause",
                                  selection: $app.settings.longBreakMinutes,
                                  options: longBreaks, display: Self.minutesLabel)
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
                                  selection: $app.settings.theme,
                                  options: AppTheme.allCases, display: { $0.label })
                        Divider().overlay(Theme.Palette.hairline3)
                        ToggleRow(label: "Benachrichtigungen", isOn: $app.settings.notifications)
                            .onChange(of: app.settings.notifications) { _, isOn in
                                if isOn { NotificationManager.shared.requestPermissionIfNeeded() }
                            }
                    }

                    SettingsGroup(title: "Sammlung") {
                        ActionRow(label: "Neue Werke entdecken",
                                  icon: "plus.square.on.square",
                                  identifier: "settings.shop") { showPaywall = true }
                        Divider().overlay(Theme.Palette.hairline3)
                        ActionRow(label: restoring ? "Wird wiederhergestellt…" : "Käufe wiederherstellen",
                                  icon: restoreDone ? "checkmark" : "arrow.counterclockwise",
                                  identifier: "settings.restore") {
                            guard !restoring else { return }
                            restoring = true
                            Task {
                                await store.restorePurchases()
                                app.applyPurchasedProducts(store.purchasedProductIDs)
                                restoring = false
                                restoreDone = true
                            }
                        }
                    }

                    SettingsGroup(title: "Rechtliches") {
                        LinkRow(label: "Datenschutz", url: LegalLinks.privacy)
                        Divider().overlay(Theme.Palette.hairline3)
                        LinkRow(label: "Nutzungsbedingungen", url: LegalLinks.terms)
                    }

                    Text(verbatim: "FocusPiece · Version 1.0")
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
        .sheet(isPresented: $showPaywall) {
            PaywallView()
        }
    }

    /// "4 Runden" / "1 Runde" — the picker option labels (plural per language).
    private static func roundsLabel(_ n: Int) -> String { String(localized: "\(n) Runden") }
    /// "25 Min"
    private static func minutesLabel(_ m: Int) -> String { String(localized: "\(m) Min") }
}

// MARK: - Building blocks
private struct SettingsGroup<Content: View>: View {
    let title: LocalizedStringKey
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
    let label: LocalizedStringKey
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

/// Tappable row with a trailing SF-symbol affordance (shop, restore).
private struct ActionRow: View {
    let label: LocalizedStringKey
    let icon: String
    var identifier: String? = nil
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack {
                Text(label)
                    .font(Theme.Font.sans(15))
                    .foregroundStyle(Theme.Palette.ink)
                Spacer()
                Image(systemName: icon)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Theme.Palette.accent)
            }
            .padding(.vertical, 14)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier(identifier ?? "")
    }
}

/// External link row (legal pages) — opens in the browser.
private struct LinkRow: View {
    let label: LocalizedStringKey
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

/// Menu row bound to a typed value. The options carry their real value, so the
/// selection never has to be parsed back out of a translated label.
private struct PickerRow<Value: Hashable>: View {
    let label: LocalizedStringKey
    @Binding var selection: Value
    let options: [Value]
    let display: (Value) -> String

    var body: some View {
        Menu {
            ForEach(options, id: \.self) { opt in
                Button(display(opt)) { selection = opt }
            }
        } label: {
            HStack {
                Text(label)
                    .font(Theme.Font.sans(15))
                    .foregroundStyle(Theme.Palette.ink)
                Spacer()
                Text(display(selection))
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
