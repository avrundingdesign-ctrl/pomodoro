import SwiftUI

/// Onboarding flow — 3 screens: Willkommen · So funktioniert es · Erste Session.
struct OnboardingView: View {
    @EnvironmentObject var app: AppModel
    @State private var index = 0

    var body: some View {
        ZStack {
            Theme.Palette.paper.ignoresSafeArea()
            switch index {
            case 0: WelcomePage(index: $index)
            case 1: HowItWorksPage(index: $index)
            default: FirstSessionPage(onStart: { app.finishOnboarding() })
            }
        }
        .environment(\.onboardingIndex, index)
    }
}

// MARK: - 1. Willkommen
private struct WelcomePage: View {
    @Binding var index: Int

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .bottom) {
                // Full-bleed hero (Starry Night), blurred + warm.
                ArtworkImage(assetName: "Van_Gogh_-_Starry_Night_-_Google_Art_Project", contentMode: .fill)
                    .frame(width: geo.size.width, height: geo.size.height * 0.62)
                    .blur(radius: 2)
                    .saturation(1.08)
                    .clipped()
                    .overlay(
                        LinearGradient(
                            stops: [
                                .init(color: Theme.Palette.paper.opacity(0), location: 0.30),
                                .init(color: Theme.Palette.paper.opacity(0.72), location: 0.62),
                                .init(color: Theme.Palette.paper, location: 0.86),
                            ],
                            startPoint: .top, endPoint: .bottom
                        )
                    )
                    .frame(maxHeight: .infinity, alignment: .top)
                    .ignoresSafeArea()

                VStack(alignment: .leading, spacing: 0) {
                    Text("FOCUSPIECE").eyebrow(tracking: 2.9)
                        .padding(.bottom, 18)
                    Text("Aus Konzentration wird ein Meisterwerk.")
                        .font(Theme.Font.serif(40))
                        .tracking(-0.6)
                        .lineSpacing(2)
                        .foregroundStyle(Theme.Palette.ink)
                        .padding(.bottom, 16)
                    Text("Stell den Timer, bleib präsent — mit jeder fokussierten Minute tritt ein verborgenes Kunstwerk klarer hervor.")
                        .font(Theme.Font.sans(16))
                        .lineSpacing(6)
                        .foregroundStyle(Theme.Palette.muted)
                        .padding(.bottom, 30)
                    PageDots(count: 3, index: 0).padding(.bottom, 24)
                    PrimaryButton(title: "Weiter") { index = 1 }
                        .accessibilityIdentifier("onboarding.next")
                }
                .padding(.horizontal, 34)
                .padding(.bottom, 24)
            }
        }
    }
}

// MARK: - 2. So funktioniert es
private struct HowItWorksPage: View {
    @Binding var index: Int

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Spacer().frame(height: 24)
            Text("SO FUNKTIONIERT ES").eyebrow().padding(.bottom, 14)
            Text("Drei ruhige Schritte")
                .font(Theme.Font.serif(33))
                .tracking(-0.3)
                .foregroundStyle(Theme.Palette.ink)
                .padding(.bottom, 40)

            VStack(alignment: .leading, spacing: 18) {
                StepRow(icon: "clock",
                        title: "Setze deine Zeit",
                        text: "Wähle 15 bis 60 Minuten ungestörter Konzentration.")
                StepRow(icon: "eye",
                        title: "Bleib im Bild",
                        text: "Verlässt du die App, hält die Enthüllung sanft inne.")
                StepRow(icon: "photo.on.rectangle",
                        title: "Sammle Meisterwerke",
                        text: "Jede vollendete Session schaltet ein Werk frei.")
            }

            Spacer()
            PageDots(count: 3, index: 1).padding(.bottom, 24)
            PrimaryButton(title: "Weiter") { index = 2 }
                .accessibilityIdentifier("onboarding.next")
        }
        .padding(.horizontal, 24)
        .padding(.bottom, 24)
    }
}

private struct StepRow: View {
    let icon: String
    let title: String
    let text: String

    var body: some View {
        HStack(alignment: .top, spacing: 16) {
            Image(systemName: icon)
                .font(.system(size: 22, weight: .regular))
                .foregroundStyle(Theme.Palette.accent)
                .frame(width: 50, height: 50)
                .background(Theme.Palette.surface2)
                .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.iconBadge, style: .continuous))
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(Theme.Font.serif(19, weight: .medium))
                    .foregroundStyle(Theme.Palette.ink)
                Text(text)
                    .font(Theme.Font.sans(15))
                    .lineSpacing(4)
                    .foregroundStyle(Theme.Palette.muted)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
    }
}

// MARK: - 3. Erste Session
private struct FirstSessionPage: View {
    @EnvironmentObject var app: AppModel
    let onStart: () -> Void

    private let options = [15, 25, 45, 60]

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Spacer().frame(height: 24)
            Text("ERSTE SESSION").eyebrow().padding(.bottom, 14)
            Text("Wie lange möchtest du dich versenken?")
                .font(Theme.Font.serif(33))
                .tracking(-0.3)
                .lineSpacing(2)
                .foregroundStyle(Theme.Palette.ink)
                .padding(.bottom, 32)

            LazyVGrid(columns: [GridItem(.flexible(), spacing: 14),
                                GridItem(.flexible(), spacing: 14)], spacing: 14) {
                ForEach(options, id: \.self) { minutes in
                    DurationChip(minutes: minutes,
                                 isActive: app.settings.selectedDuration == minutes) {
                        app.settings.selectedDuration = minutes
                    }
                    .accessibilityIdentifier("duration.\(minutes)")
                }
            }
            .padding(.bottom, 24)

            HiddenWorkCard()

            Spacer()
            PageDots(count: 3, index: 2).padding(.bottom, 24)
            PrimaryButton(title: "Session beginnen", height: 60, action: onStart)
                .accessibilityIdentifier("onboarding.start")
        }
        .padding(.horizontal, 28)
        .padding(.bottom, 24)
    }
}

/// 2×2 duration chip — 74h, radius 18. Active = accent fill, white serif number.
struct DurationChip: View {
    let minutes: Int
    let isActive: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 2) {
                Text("\(minutes)")
                    .font(Theme.Font.serif(26))
                    .foregroundStyle(isActive ? .white : Theme.Palette.ink)
                Text("MINUTEN")
                    .font(Theme.Font.sans(11, weight: .semibold))
                    .tracking(1.2)
                    .foregroundStyle(isActive ? Color.white.opacity(0.82) : Theme.Palette.muted2)
            }
            .frame(maxWidth: .infinity)
            .frame(height: 74)
            .background(isActive ? Theme.Palette.accent : Theme.Palette.surface)
            .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.durationChip, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: Theme.Radius.durationChip, style: .continuous)
                    .stroke(Theme.Palette.cardBorder, lineWidth: isActive ? 0 : 1)
            )
            .shadow(color: isActive ? Theme.Palette.accent.opacity(0.6) : .clear,
                    radius: 11, x: 0, y: 10)
        }
        .buttonStyle(.plain)
    }
}

/// "Verborgenes Werk" info card with a blurred locked thumbnail.
struct HiddenWorkCard: View {
    var body: some View {
        HStack(spacing: 14) {
            ZStack {
                ArtworkImage(assetName: "Almond_blossom", contentMode: .fill)
                    .frame(width: 54, height: 54)
                    .blur(radius: 6)
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                Image(systemName: "lock.fill")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(.white)
            }
            .frame(width: 54, height: 54)
            .clipped()

            VStack(alignment: .leading, spacing: 3) {
                Text("Verborgenes Werk")
                    .font(Theme.Font.sans(15, weight: .semibold))
                    .foregroundStyle(Theme.Palette.ink)
                Text("Wird beim Fokussieren enthüllt")
                    .font(Theme.Font.sans(13))
                    .foregroundStyle(Theme.Palette.muted2)
            }
            Spacer(minLength: 0)
        }
        .padding(14)
        .background(Theme.Palette.surface2)
        .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.settingCard, style: .continuous))
    }
}

// Environment key (kept for potential cross-fade transitions between pages).
private struct OnboardingIndexKey: EnvironmentKey { static let defaultValue = 0 }
extension EnvironmentValues {
    var onboardingIndex: Int {
        get { self[OnboardingIndexKey.self] }
        set { self[OnboardingIndexKey.self] = newValue }
    }
}
