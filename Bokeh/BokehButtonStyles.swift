import SwiftUI

// MARK: - Micro-interactions

struct ScaleButtonStyle: ButtonStyle {
    var minScale: CGFloat = 0.96
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? minScale : 1)
            .animation(.easeInOut(duration: 0.12), value: configuration.isPressed)
    }
}

struct OpacityButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .opacity(configuration.isPressed ? 0.8 : 1)
            .animation(.easeInOut(duration: 0.1), value: configuration.isPressed)
    }
}

struct GlowButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
            .shadow(
                color: Color.theme.bokehTeal.opacity(configuration.isPressed ? 0.3 : 0),
                radius: configuration.isPressed ? 8 : 0,
                y: 0
            )
            .animation(.easeInOut(duration: 0.2), value: configuration.isPressed)
    }
}
