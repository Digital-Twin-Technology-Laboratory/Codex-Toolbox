import CodexToolboxCore
import SwiftUI

struct DashboardModuleHeader: View {
    let module: ToolboxModule
    let subtitle: String
    let isCollapsed: Bool
    let isRefreshing: Bool
    let refresh: () -> Void
    let toggleCollapsed: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: module.systemImage)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(tint)
                .frame(width: 22, height: 22)

            VStack(alignment: .leading, spacing: 1) {
                Text(module.displayName)
                    .font(.system(size: 13, weight: .bold))
                Text(subtitle)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer(minLength: 8)

            Button(action: refresh) {
                Group {
                    if isRefreshing {
                        ProgressView().controlSize(.mini)
                    } else {
                        Image(systemName: "arrow.clockwise")
                    }
                }
                .frame(width: 16, height: 16)
            }
            .adaptiveGlassIconStyle()
            .controlSize(.small)
            .disabled(isRefreshing)
            .help("刷新\(module.displayName)")
            .accessibilityLabel("刷新\(module.displayName)")

            Button(action: toggleCollapsed) {
                Image(systemName: "chevron.down")
                    .font(.system(size: 10, weight: .bold))
                    .rotationEffect(.degrees(isCollapsed ? -90 : 0))
                    .frame(width: 16, height: 16)
            }
            .buttonStyle(ToolboxPressButtonStyle())
            .help(isCollapsed ? "展开\(module.displayName)" : "折叠\(module.displayName)")
            .accessibilityLabel(isCollapsed ? "展开\(module.displayName)" : "折叠\(module.displayName)")
        }
    }

    private var tint: Color {
        switch module {
        case .modelRadar: .blue
        case .tokenUsage: .indigo
        case .resetCredits: .teal
        }
    }
}
