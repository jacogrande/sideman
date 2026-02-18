import SwiftUI

struct GlassActionButtonStyle: ButtonStyle {
    let tint: Color
    let isPrimary: Bool

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 11, weight: .semibold, design: .rounded))
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(buttonFill(configuration: configuration))
            .overlay(
                Capsule()
                    .strokeBorder(borderColor, lineWidth: 0.8)
            )
            .foregroundStyle(isPrimary ? Color.white : tint)
            .brightness(configuration.isPressed ? -0.08 : 0)
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
            .animation(.easeOut(duration: 0.14), value: configuration.isPressed)
    }

    @ViewBuilder
    private func buttonFill(configuration: Configuration) -> some View {
        if isPrimary {
            Capsule()
                .fill(tint)
                .shadow(color: tint, radius: configuration.isPressed ? 0 : 4, x: 0, y: 2)
        } else {
            Capsule()
                .fill(.thinMaterial)
        }
    }

    private var borderColor: Color {
        isPrimary ? Color.white : tint
    }
}
