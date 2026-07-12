import SwiftUI

/// Screen 10 — grouped settings.
struct SettingsView: View {
    @EnvironmentObject var app: AppModel
    @EnvironmentObject var store: StoreModel
    @State private var showPaywall = false
    @State private var restoring = false
    @State private var restoreDone = false

    private let durations = [15, 25, 45, 60]
    private let sounds = ["Regen", "Wald", "Ozean", "Stille"]
    private let themes = ["Hell", "Dunkel", "System"]

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Einstellungen")
                    .font(Theme.Font.serif(32))
                    .tracking(-0.3)
                    .foregroundStyle(Theme.Palette.ink)
                    .accessibilityIdentifier("settings.title")
                Spacer()
            }
            .padding(.horizontal, 28)
            .padding(.top, 8).padding(.bottom, 16)

            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    SettingsGroup(title: "Session") {
                        PickerRow(label: "Standarddauer",
                                  value: "\(app.settings.selectedDuration) Min",
                                  options: durations.map { "\($0) Min" },
                                  identifier: "settings.duration") { picked in
                            if let m = Int(picked.replacingOccurrences(of: " Min", with: "")) {
                                app.settings.selectedDuration = m
                            }
                        }
                        Divider().overlay(Theme.Palette.hairline3)
                        ToggleRow(label: "Sanfter Start", isOn: $app.settings.gentleStart,
                                  identifier: "settings.toggle.gentleStart")
                    }

                    SettingsGroup(title: "Klang & Haptik") {
                        PickerRow(label: "Umgebungsklang",
                                  value: app.settings.ambientSound,
                                  options: sounds,
                                  identifier: "settings.sound") { app.settings.ambientSound = $0 }
                        Divider().overlay(Theme.Palette.hairline3)
                        ToggleRow(label: "Abschluss-Ton", isOn: $app.settings.completionTone,
                                  identifier: "settings.toggle.completionTone")
                        Divider().overlay(Theme.Palette.hairline3)
                        ToggleRow(label: "Haptisches Feedback", isOn: $app.settings.haptics,
                                  identifier: "settings.toggle.haptics")
                    }

                    SettingsGroup(title: "Darstellung") {
                        PickerRow(label: "Thema",
                                  value: app.settings.theme,
                                  options: themes,
                                  identifier: "settings.theme") { app.settings.theme = $0 }
                        Divider().overlay(Theme.Palette.hairline3)
                        ToggleRow(label: "Benachrichtigungen", isOn: $app.settings.notifications,
                                  identifier: "settings.toggle.notifications")
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

                    Text("FocusPiece · Version 1.0")
                        .font(Theme.Font.sans(13))
                        .foregroundStyle(Theme.Palette.muted3Soft)
                        .frame(maxWidth: .infinity)
                        .padding(.top, 4)
                        .accessibilityIdentifier("settings.version")
                }
                .padding(.horizontal, 24)
                .padding(.bottom, 24)
            }
        }
        .background(Theme.Palette.paper)
        .sheet(isPresented: $showPaywall) {
            PaywallView()
        }
    }
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
    var identifier: String? = nil

    var body: some View {
        HStack {
            Text(label)
                .font(Theme.Font.sans(15))
                .foregroundStyle(Theme.Palette.ink)
            Spacer()
            AppToggle(isOn: $isOn)
                .accessibilityIdentifier(identifier ?? "")
        }
        .padding(.vertical, 14)
    }
}

/// Tappable row with a trailing SF-symbol affordance (shop, restore).
private struct ActionRow: View {
    let label: String
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
    var identifier: String? = nil
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
        .accessibilityIdentifier(identifier ?? "")
    }
}
