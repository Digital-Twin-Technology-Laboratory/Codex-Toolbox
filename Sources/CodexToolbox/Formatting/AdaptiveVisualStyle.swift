import AppKit
import CodexToolboxCore
import SwiftUI

extension View {
    func adaptiveGlassCard(
        tint: Color,
        id: String,
        namespace: Namespace.ID,
        isInteractive: Bool = false
    ) -> some View {
        modifier(
            AdaptiveCardSurfaceModifier(
                colorfulTint: tint,
                id: id,
                namespace: namespace,
                isInteractive: isInteractive
            )
        )
    }

    func adaptiveInteractiveCardFeedback(
        tint: Color,
        isHovered: Bool,
        isEnabled: Bool = true
    ) -> some View {
        modifier(
            AdaptiveInteractiveCardFeedbackModifier(
                colorfulTint: tint,
                isHovered: isHovered,
                isEnabled: isEnabled
            )
        )
    }

    func adaptiveDashboardInsetSurface(
        tint: Color,
        cornerRadius: CGFloat = 9
    ) -> some View {
        modifier(
            AdaptiveDashboardInsetSurfaceModifier(
                colorfulTint: tint,
                cornerRadius: cornerRadius
            )
        )
    }

    func adaptiveDashboardFloatingSurface(cornerRadius: CGFloat = 7) -> some View {
        modifier(AdaptiveDashboardFloatingSurfaceModifier(cornerRadius: cornerRadius))
    }

    func adaptiveGlassControlStyle() -> some View {
        modifier(AdaptiveGlassControlStyleModifier())
    }

    func adaptiveGlassIconStyle() -> some View {
        modifier(AdaptiveGlassIconStyleModifier())
    }
}

private struct AdaptiveDashboardFloatingSurfaceModifier: ViewModifier {
    let cornerRadius: CGFloat

    @Environment(\.dashboardTheme) private var theme
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.colorSchemeContrast) private var contrast

    @ViewBuilder
    func body(content: Content) -> some View {
        let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
        if theme == .colorfulGlass,
           !reduceTransparency,
           contrast != .increased {
            content.background(.regularMaterial, in: shape)
        } else {
            content
                .background(theme.palette.opaqueCard, in: shape)
                .overlay {
                    shape.stroke(
                        theme.palette.separator.opacity(contrast == .increased ? 0.95 : 0.72),
                        lineWidth: contrast == .increased ? 1.25 : 0.75
                    )
                }
        }
    }
}

private struct AdaptiveCardSurfaceModifier: ViewModifier {
    let colorfulTint: Color
    let id: String
    let namespace: Namespace.ID
    let isInteractive: Bool

    @Environment(\.dashboardTheme) private var theme
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.colorSchemeContrast) private var contrast

    @ViewBuilder
    func body(content: Content) -> some View {
        let shape = RoundedRectangle(cornerRadius: 14, style: .continuous)
        let palette = theme.palette
        let tint = palette.decorativeAccent(colorfulTint)

        if reduceTransparency || contrast == .increased {
            content
                .background(palette.opaqueCard, in: shape)
                .overlay {
                    shape.stroke(
                        accessibilityBorderColor(tint: tint, palette: palette),
                        lineWidth: 1
                    )
                }
        } else {
            switch theme {
            case .colorfulGlass:
                colorfulGlass(content: content, shape: shape, tint: tint)
            case .clearGlass:
                clearGlass(content: content, shape: shape)
            case .flatNeutral:
                content
                    .background(palette.opaqueCard, in: shape)
                    .overlay {
                        shape.stroke(palette.separator.opacity(0.72), lineWidth: 0.75)
                    }
            }
        }
    }

    @ViewBuilder
    private func colorfulGlass(
        content: Content,
        shape: RoundedRectangle,
        tint: Color
    ) -> some View {
        if #available(macOS 26.0, *) {
            if isInteractive {
                content
                    .overlay { shape.stroke(.white.opacity(0.16), lineWidth: 0.75) }
                    .glassEffect(.regular.tint(tint.opacity(0.10)).interactive(), in: shape)
                    .glassEffectID(id, in: namespace)
            } else {
                content
                    .overlay { shape.stroke(.white.opacity(0.16), lineWidth: 0.75) }
                    .glassEffect(.regular.tint(tint.opacity(0.10)), in: shape)
                    .glassEffectID(id, in: namespace)
            }
        } else {
            content
                .background(.regularMaterial, in: shape)
                .overlay { shape.stroke(tint.opacity(0.20), lineWidth: 1) }
        }
    }

    @ViewBuilder
    private func clearGlass(
        content: Content,
        shape: RoundedRectangle
    ) -> some View {
        if #available(macOS 26.0, *) {
            if isInteractive {
                content
                    .overlay { shape.stroke(.primary.opacity(0.14), lineWidth: 0.75) }
                    .glassEffect(.regular.interactive(), in: shape)
                    .glassEffectID(id, in: namespace)
            } else {
                content
                    .overlay { shape.stroke(.primary.opacity(0.14), lineWidth: 0.75) }
                    .glassEffect(.regular, in: shape)
                    .glassEffectID(id, in: namespace)
            }
        } else {
            content
                .background(.regularMaterial, in: shape)
                .overlay { shape.stroke(.primary.opacity(0.14), lineWidth: 0.75) }
        }
    }

    private func accessibilityBorderColor(
        tint: Color,
        palette: DashboardThemePalette
    ) -> Color {
        switch theme {
        case .colorfulGlass:
            tint.opacity(contrast == .increased ? 0.48 : 0.28)
        case .clearGlass, .flatNeutral:
            palette.separator.opacity(contrast == .increased ? 0.95 : 0.72)
        }
    }
}

private struct AdaptiveDashboardInsetSurfaceModifier: ViewModifier {
    let colorfulTint: Color
    let cornerRadius: CGFloat

    @Environment(\.dashboardTheme) private var theme
    @Environment(\.colorSchemeContrast) private var contrast

    func body(content: Content) -> some View {
        let palette = theme.palette
        let tint = palette.decorativeAccent(colorfulTint)
        let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)

        content
            .background(fillColor(tint: tint, palette: palette), in: shape)
            .overlay {
                shape.stroke(
                    borderColor(tint: tint, palette: palette),
                    lineWidth: contrast == .increased ? 1.25 : 1
                )
            }
    }

    private func fillColor(tint: Color, palette: DashboardThemePalette) -> Color {
        switch theme {
        case .colorfulGlass:
            tint.opacity(contrast == .increased ? 0.16 : 0.09)
        case .clearGlass:
            palette.separator.opacity(contrast == .increased ? 0.20 : 0.10)
        case .flatNeutral:
            palette.separator.opacity(contrast == .increased ? 0.24 : 0.14)
        }
    }

    private func borderColor(tint: Color, palette: DashboardThemePalette) -> Color {
        switch theme {
        case .colorfulGlass:
            tint.opacity(contrast == .increased ? 0.42 : 0.18)
        case .clearGlass, .flatNeutral:
            palette.separator.opacity(contrast == .increased ? 0.95 : 0.68)
        }
    }
}

private struct AdaptiveInteractiveCardFeedbackModifier: ViewModifier {
    let colorfulTint: Color
    let isHovered: Bool
    let isEnabled: Bool

    @Environment(\.dashboardTheme) private var theme
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.colorSchemeContrast) private var contrast

    func body(content: Content) -> some View {
        let activeHover = isEnabled && isHovered
        let tint = theme.palette.decorativeAccent(colorfulTint)
        let shape = RoundedRectangle(cornerRadius: 14, style: .continuous)

        content
            .overlay {
                shape.stroke(
                    tint.opacity(isEnabled ? strokeOpacity : 0),
                    lineWidth: activeHover || contrast == .increased ? 1.25 : 0.75
                )
            }
            .shadow(
                color: shadowColor(tint: tint, activeHover: activeHover),
                radius: activeHover ? 10 : 5,
                y: 3
            )
    }

    private var strokeOpacity: Double {
        if contrast == .increased {
            return isHovered ? 0.72 : 0.38
        }
        if reduceTransparency {
            return isHovered ? 0.52 : 0.22
        }
        return isHovered ? 0.42 : 0.12
    }

    private func shadowColor(tint: Color, activeHover: Bool) -> Color {
        guard theme == .colorfulGlass,
              !reduceTransparency,
              contrast != .increased,
              isEnabled else {
            return .clear
        }
        return tint.opacity(activeHover ? 0.11 : 0.04)
    }
}

private struct AdaptiveGlassControlStyleModifier: ViewModifier {
    @Environment(\.dashboardTheme) private var theme

    @ViewBuilder
    func body(content: Content) -> some View {
        if theme == .flatNeutral {
            content.buttonStyle(.bordered)
        } else if #available(macOS 26.0, *) {
            content.buttonStyle(.glass)
        } else {
            content.buttonStyle(.bordered)
        }
    }
}

private struct AdaptiveGlassIconStyleModifier: ViewModifier {
    @Environment(\.dashboardTheme) private var theme

    @ViewBuilder
    func body(content: Content) -> some View {
        if theme == .flatNeutral {
            content.buttonStyle(.bordered)
        } else if #available(macOS 26.0, *) {
            content.buttonStyle(.glass)
        } else {
            content.buttonStyle(.plain)
        }
    }
}
