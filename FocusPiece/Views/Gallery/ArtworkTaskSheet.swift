import SwiftUI

/// What a locked tile offers: the task, not the painting.
///
/// Tapping a veiled tile in the gallery opens this. It names the cycle the work
/// asks for and nothing that would give the work away — no title, no artist, no
/// year. Epoch and set are the one concession: they place the piece without
/// naming it, which is what makes one task more tempting than the next.
struct ArtworkTaskSheet: View {
    @Environment(\.dismiss) private var dismiss
    let artwork: Artwork
    /// Begin this task. The caller owns replacing any running cycle.
    let onStart: () -> Void

    private var packTitle: String {
        ArtworkCatalog.pack(id: artwork.packID)?.title ?? ArtworkCatalog.freePack.title
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                HStack {
                    Text("AUFGABE").eyebrow()
                    Spacer()
                    CircleIconButton(systemName: "xmark") { dismiss() }
                        .accessibilityIdentifier("task.close")
                }
                .padding(.bottom, 14)

                Text("Verborgenes Werk")
                    .font(Theme.Font.serif(28))
                    .tracking(-0.3)
                    .foregroundStyle(Theme.Palette.ink)
                    .padding(.bottom, 4)
                    .accessibilityIdentifier("task.title")

                Text("Schließe diesen Zyklus ab, um zu sehen, was dahinter liegt.")
                    .font(Theme.Font.sans(15))
                    .lineSpacing(6)
                    .foregroundStyle(Theme.Palette.bodySoft)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.bottom, 22)

                // Rounds and minutes as two rows rather than one sentence: it
                // keeps every language free of a plural rule for "Runde".
                VStack(spacing: 0) {
                    row("Runden", "\(artwork.requirement.rounds)")
                    row("Pro Runde", artwork.requirement.minutesLabel)
                    row("Epoche", artwork.collectionTag)
                    row("Bildband", packTitle, last: true)
                }
                .padding(.horizontal, 16)
                .background(Theme.Palette.surface)
                .overlay(
                    RoundedRectangle(cornerRadius: Theme.Radius.settingCard, style: .continuous)
                        .stroke(Theme.Palette.hairline2, lineWidth: 1)
                )
                .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.settingCard, style: .continuous))
                .padding(.bottom, 24)

                PrimaryButton(title: "Aufgabe starten") {
                    dismiss()
                    onStart()
                }
                .accessibilityIdentifier("task.start")
            }
            .padding(.horizontal, Theme.Pad.screenH)
            .padding(.top, 22)
            .padding(.bottom, 28)
        }
        .background(Theme.Palette.paper)
        .presentationDetents([.medium])
        .presentationDragIndicator(.visible)
    }

    private func row(_ label: LocalizedStringKey, _ value: String, last: Bool = false) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text(label)
                .font(Theme.Font.sans(14))
                .foregroundStyle(Theme.Palette.muted2)
            Spacer(minLength: 16)
            Text(value)
                .font(Theme.Font.sans(14, weight: .medium))
                .foregroundStyle(Theme.Palette.ink)
                .multilineTextAlignment(.trailing)
        }
        .padding(.vertical, 13)
        .overlay(alignment: .bottom) {
            if !last { Rectangle().fill(Theme.Palette.hairline).frame(height: 1) }
        }
    }
}
