import SwiftUI

/// Custom switch matching the spec: track 50×30 radius 16
/// (on = accent, off = #d8d2c6), knob 24 white, on x=23 / off x=3.
struct AppToggle: View {
    @Binding var isOn: Bool

    var body: some View {
        Button {
            withAnimation(.spring(response: 0.28, dampingFraction: 0.7)) { isOn.toggle() }
        } label: {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(isOn ? Theme.Palette.accent : Theme.Palette.toggleOff)
                .frame(width: 50, height: 30)
                .overlay(alignment: .leading) {
                    Circle()
                        .fill(.white)
                        .frame(width: 24, height: 24)
                        .shadow(color: .black.opacity(0.2), radius: 1.5, x: 0, y: 1)
                        .offset(x: isOn ? 23 : 3)
                }
        }
        .buttonStyle(.plain)
    }
}
