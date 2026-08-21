import CodexToolboxCore
import SwiftUI

struct DashboardModuleHeader: View {
    let module: ToolboxModule
    let subtitle: String
    let collapsedSummary: String?
    let isCollapsed: Bool
    let isRefreshing: Bool
    let refresh: () -> Void
    let toggleCollapsed: () -> Void

    @Environment(\.dashboardTheme) private var dashboardTheme

    var body: some View {
        ZStack(alignment: .trailing) {
            Button(action: toggleCollapsed) {
                HStack(spacing: 10) {
                    Image(systemName: module.systemImage)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(tint)
                        .frame(width: 22, height: 22)

                    VStack(alignment: .leading, spacing: 1) {
                        HStack(spacing: 6) {
                            Text(module.displayName)
                                .font(.system(size: 13, weight: .bold))
                            if isCollapsed, let collapsedSummary {
                                Text(collapsedSummary)
                                    .font(.caption.weight(.semibold))
                                    .foregroundStyle(tint)
                                    .monospacedDigit()
                                    .lineLimit(1)
                            }
                        }
                        Text(subtitle)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }

                    Spacer(minLength: 8)

                    // Reserve the refresh control's hit region while letting
                    // the rest of the 44 pt row toggle the module.
                    Color.clear.frame(width: 32, height: 32)

                    Image(systemName: "chevron.down")
                        .font(.system(size: 10, weight: .bold))
                        .rotationEffect(.degrees(isCollapsed ? -90 : 0))
                        .frame(width: 28, height: 32)
                }
                .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                .contentShape(Rectangle())
            }
            .buttonStyle(ToolboxPressButtonStyle())
            .help(isCollapsed ? "展开\(module.displayName)" : "折叠\(module.displayName)")
            .accessibilityLabel(toggleAccessibilityLabel)
            .accessibilityHint("也可点击整行标题切换")

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
            .frame(width: 32, height: 32)
            .padding(.trailing, 38)
            .adaptiveGlassIconStyle()
            .controlSize(.small)
            .disabled(isRefreshing)
            .help("刷新\(module.displayName)")
            .accessibilityLabel("刷新\(module.displayName)")
        }
    }

    private var tint: Color {
        dashboardTheme.palette.accent(for: module)
    }

    private var toggleAccessibilityLabel: String {
        let action = isCollapsed ? "展开" : "折叠"
        guard isCollapsed, let collapsedSummary else {
            return "\(action)\(module.displayName)"
        }
        return "\(action)\(module.displayName)，\(collapsedSummary)"
    }
}
