import SwiftUI

extension View {
    @ViewBuilder
    func adaptiveGlassCard(
        tint: Color,
        id: String,
        namespace: Namespace.ID,
        isInteractive: Bool = false
    ) -> some View {
        let shape = RoundedRectangle(cornerRadius: 14, style: .continuous)

        if #available(macOS 26.0, *) {
            if isInteractive {
                self
                    .overlay {
                        shape.stroke(.white.opacity(0.16), lineWidth: 0.75)
                    }
                    .glassEffect(.regular.tint(tint.opacity(0.10)).interactive(), in: shape)
                    .glassEffectID(id, in: namespace)
            } else {
                self
                    .overlay {
                        shape.stroke(.white.opacity(0.16), lineWidth: 0.75)
                    }
                    .glassEffect(.regular.tint(tint.opacity(0.10)), in: shape)
                    .glassEffectID(id, in: namespace)
            }
        } else {
            self
                .background(.regularMaterial, in: shape)
                .overlay {
                    shape.stroke(tint.opacity(0.20), lineWidth: 1)
                }
        }
    }

    func adaptiveInteractiveCardFeedback(
        tint: Color,
        isHovered: Bool,
        isEnabled: Bool = true
    ) -> some View {
        modifier(
            AdaptiveInteractiveCardFeedbackModifier(
                tint: tint,
                isHovered: isHovered,
                isEnabled: isEnabled
            )
        )
    }

    @ViewBuilder
    func adaptiveGlassControlStyle() -> some View {
        if #available(macOS 26.0, *) {
            self.buttonStyle(.glass)
        } else {
            self.buttonStyle(.bordered)
        }
    }

    @ViewBuilder
    func adaptiveGlassIconStyle() -> some View {
        if #available(macOS 26.0, *) {
            self.buttonStyle(.glass)
        } else {
            self.buttonStyle(.plain)
        }
    }
}

private struct AdaptiveInteractiveCardFeedbackModifier: ViewModifier {
    let tint: Color
    let isHovered: Bool
    let isEnabled: Bool

    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    @ViewBuilder
    func body(content: Content) -> some View {
        if isEnabled {
            let shape = RoundedRectangle(cornerRadius: 14, style: .continuous)
            content
                .overlay {
                    shape.stroke(
                        tint.opacity(strokeOpacity),
                        lineWidth: isHovered ? 1.25 : 0.75
                    )
                }
                .shadow(
                    color: reduceTransparency ? .clear : tint.opacity(isHovered ? 0.11 : 0.04),
                    radius: isHovered ? 10 : 5,
                    y: 3
                )
        } else {
            content
        }
    }

    private var strokeOpacity: Double {
        if reduceTransparency {
            return isHovered ? 0.52 : 0.22
        }
        return isHovered ? 0.42 : 0.12
    }
}
