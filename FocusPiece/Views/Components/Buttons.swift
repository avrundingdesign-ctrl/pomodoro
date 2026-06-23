import SwiftUI

/// Primary accent button — 56–60h, radius 18–20, terracotta with soft shadow.
struct PrimaryButton: View {
    let title: String
    var height: CGFloat = 56
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(Theme.Font.sans(16, weight: .semibold))
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity)
                .frame(height: height)
                .background(Theme.Palette.accent)
                .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.primaryButton, style: .continuous))
                .shadow(color: Theme.Palette.accent.opacity(0.6), radius: 13, x: 0, y: 12)
        }
        .buttonStyle(.plain)
    }
}

/// Secondary / ghost button — bordered, paper background.
struct GhostButton: View {
    let title: String
    var icon: String? = nil
    var height: CGFloat = 54
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                if let icon { Image(systemName: icon).font(.system(size: 15, weight: .medium)) }
                Text(title).font(Theme.Font.sans(16, weight: .semibold))
            }
            .foregroundStyle(Theme.Palette.ink)
            .frame(maxWidth: .infinity)
            .frame(height: height)
            .overlay(
                RoundedRectangle(cornerRadius: Theme.Radius.primaryButton, style: .continuous)
                    .stroke(Color(hex: 0xDDD5C7), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }
}

/// Round icon button used for back / close / pause controls.
struct CircleIconButton: View {
    let systemName: String
    var diameter: CGFloat = 40
    var background: Color = Theme.Palette.circleButton
    var iconColor: Color = Theme.Palette.ink
    var iconSize: CGFloat = 16
    var identifier: String? = nil
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: iconSize, weight: .medium))
                .foregroundStyle(iconColor)
                .frame(width: diameter, height: diameter)
                .background(background)
                .clipShape(Circle())
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier(identifier ?? "")
    }
}

/// Onboarding page indicator — active pill 22×6 accent, inactive 6×6 dot.
struct PageDots: View {
    let count: Int
    let index: Int

    var body: some View {
        HStack(spacing: 7) {
            ForEach(0..<count, id: \.self) { i in
                Capsule()
                    .fill(i == index ? Theme.Palette.accent : Theme.Palette.dotInactive)
                    .frame(width: i == index ? 22 : 6, height: 6)
            }
        }
        .animation(.easeInOut(duration: 0.25), value: index)
    }
}
