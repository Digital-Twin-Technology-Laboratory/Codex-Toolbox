import AppKit
import CodexToolboxCore
import SwiftUI

struct DashboardThemePalette {
    let theme: DashboardTheme

    var brandAccent: Color {
        switch theme {
        case .colorfulGlass, .flatNeutral:
            .blue
        case .clearGlass:
            .accentColor
        }
    }

    func accent(for metric: RankingMetric) -> Color {
        guard theme == .colorfulGlass else { return brandAccent }
        switch metric {
        case .iq: return .blue
        case .cost: return .green
        case .duration: return .orange
        case .overall: return .purple
        }
    }

    func accent(for module: ToolboxModule) -> Color {
        guard theme == .colorfulGlass else { return brandAccent }
        switch module {
        case .modelRadar: return .blue
        case .tokenUsage: return .indigo
        case .resetCredits: return .teal
        }
    }

    func decorativeAccent(_ colorfulAccent: Color) -> Color {
        theme == .colorfulGlass ? colorfulAccent : brandAccent
    }

    var opaqueRoot: Color {
        Color(nsColor: .windowBackgroundColor)
    }

    var opaqueCard: Color {
        Color(nsColor: .controlBackgroundColor)
    }

    var separator: Color {
        Color(nsColor: .separatorColor)
    }
}

extension DashboardTheme {
    var palette: DashboardThemePalette {
        DashboardThemePalette(theme: self)
    }
}

private struct DashboardThemeEnvironmentKey: EnvironmentKey {
    static let defaultValue: DashboardTheme = .colorfulGlass
}

extension EnvironmentValues {
    var dashboardTheme: DashboardTheme {
        get { self[DashboardThemeEnvironmentKey.self] }
        set { self[DashboardThemeEnvironmentKey.self] = newValue }
    }
}

struct DashboardRootBackground: View {
    @Environment(\.dashboardTheme) private var theme
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.colorSchemeContrast) private var contrast

    var body: some View {
        let palette = theme.palette
        ZStack {
            switch theme {
            case .colorfulGlass:
                if usesOpaqueSurface {
                    palette.opaqueRoot
                } else {
                    Rectangle().fill(.ultraThinMaterial)
                    LinearGradient(
                        colors: [.blue.opacity(0.045), .purple.opacity(0.035), .clear],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                }
            case .clearGlass:
                if usesOpaqueSurface {
                    palette.opaqueRoot
                } else {
                    Rectangle().fill(.ultraThinMaterial)
                }
            case .flatNeutral:
                palette.opaqueRoot
            }
        }
    }

    private var usesOpaqueSurface: Bool {
        reduceTransparency || contrast == .increased
    }
}
