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

    /// Keep plan identity readable on both light and dark dashboard surfaces.
    func accountPlan(_ raw: String?, colorScheme: ColorScheme) -> Color {
        let dark = colorScheme == .dark
        switch raw {
        case "free": return .secondary
        case "go":
            return dark ? Color(red: 0.35, green: 0.88, blue: 0.94) : Color(red: 0.00, green: 0.39, blue: 0.46)
        case "plus":
            return dark ? Color(red: 0.45, green: 0.72, blue: 1.00) : Color(red: 0.12, green: 0.34, blue: 0.70)
        case "prolite":
            return dark ? Color(red: 1.00, green: 0.80, blue: 0.27) : Color(red: 0.50, green: 0.34, blue: 0.02)
        case "pro":
            return dark ? Color(red: 1.00, green: 0.65, blue: 0.32) : Color(red: 0.62, green: 0.28, blue: 0.02)
        case "promax":
            return dark ? Color(red: 0.82, green: 0.65, blue: 1.00) : Color(red: 0.47, green: 0.25, blue: 0.70)
        case "team", "business", "self_serve_business_prolite", "self_serve_business_usage_based",
             "enterprise", "ent26", "enterprise_cbp_automation", "enterprise_cbp_usage_based":
            return dark ? Color(red: 0.36, green: 0.82, blue: 0.88) : Color(red: 0.04, green: 0.39, blue: 0.45)
        case "edu", "edu_plus", "edu_pro":
            return dark ? Color(red: 0.47, green: 0.85, blue: 0.60) : Color(red: 0.12, green: 0.42, blue: 0.23)
        default: return .secondary
        }
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
