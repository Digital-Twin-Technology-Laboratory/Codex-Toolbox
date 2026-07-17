import SwiftUI

enum ToolboxMotion {
    static let spring = Animation.spring(response: 0.35, dampingFraction: 1.0)
    static let reduced = Animation.easeOut(duration: 0.20)

    static func dashboard(reduceMotion: Bool) -> Animation {
        reduceMotion ? reduced : spring
    }

    static func hoverTransition(reduceMotion: Bool) -> AnyTransition {
        if reduceMotion { return .opacity }
        return .scale(scale: 0.94).combined(with: .opacity)
    }
}

struct ToolboxPressButtonStyle: ButtonStyle {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(reduceMotion ? 1 : (configuration.isPressed ? 0.97 : 1))
            .opacity(configuration.isPressed ? 0.82 : 1)
            .animation(
                reduceMotion
                    ? .easeOut(duration: 0.14)
                    : .spring(response: 0.14, dampingFraction: 1.0),
                value: configuration.isPressed
            )
    }
}

extension View {
    @ViewBuilder
    func toolboxMatchedGeometryEffect<ID: Hashable>(
        id: ID,
        in namespace: Namespace.ID,
        enabled: Bool
    ) -> some View {
        if enabled {
            matchedGeometryEffect(id: id, in: namespace)
        } else {
            self
        }
    }
}
