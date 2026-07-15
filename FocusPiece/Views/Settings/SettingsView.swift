import SwiftUI

/// Screen 10 — grouped settings.
struct SettingsView: View {
    @EnvironmentObject var app: AppModel

    private let durations = [15, 25, 45, 60]

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
                        PickerRow(label: "Standarddauer",
                                  value: "\(app.settings.selectedDuration) Min",
                                  options: durations.map { "\($0) Min" }) { picked in
                            if let m = Int(picked.replacingOccurrences(of: " Min", with: "")) {
                                app.settings.selectedDuration = m
                            }
                        }
                        Divider().overlay(Theme.Palette.hairline3)
                        ToggleRow(label: "Sanfter Start", isOn: $app.settings.gentleStart)
                    }

                    SettingsGroup(title: "Klang & Haptik") {
                        ToggleRow(label: "Abschluss-Ton", isOn: $app.settings.completionTone)
                        Divider().overlay(Theme.Palette.hairline3)
                        ToggleRow(label: "Haptisches Feedback", isOn: $app.settings.haptics)
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
