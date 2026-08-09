import SwiftUI

struct SettingsView: View {
    @Bindable var appModel: AppModel
    @State private var page: SettingsPage = .root
    @State private var selectedTab: SettingsTab = .general

    var body: some View {
        Group {
            switch page {
            case .root:
                rootSettings
            case .menuBarAliases:
                MenuBarAliasesSettingsView(
                    appModel: appModel,
                    onBack: { page = .root }
                )
            case .privacyDetails:
                AboutPrivacySettingsView(onBack: { page = .root })
            }
        }
        .frame(width: 640, height: 580)
    }

    private var rootSettings: some View {
        TabView(selection: $selectedTab) {
            GeneralDashboardSettingsView(appModel: appModel)
                .tabItem {
                    Label {
                        Text("通用与看板")
                    } icon: {
                        UpdateBadgedIcon(
                            systemName: "slider.horizontal.3",
                            showsBadge: appModel.updateManager.showsUpdateBadge
                        )
                    }
                }
                .tag(SettingsTab.general)

            ModelRadarSettingsView(
                appModel: appModel,
                onOpenMenuBarAliases: { page = .menuBarAliases }
            )
            .tabItem {
                Label("智商显示", systemImage: "brain.head.profile")
            }
            .tag(SettingsTab.modelRadar)

            TokenUsageSettingsView(appModel: appModel)
                .tabItem {
                    Label("Token 用量", systemImage: "chart.bar.xaxis")
                }
                .tag(SettingsTab.tokenUsage)

            ResetCreditsSettingsView(appModel: appModel)
                .tabItem {
                    Label("重置卡", systemImage: "arrow.clockwise.circle")
                }
                .tag(SettingsTab.resetCredits)

            AboutView(onOpenPrivacyDetails: { page = .privacyDetails })
                .tabItem {
                    Label("关于", systemImage: "info.circle")
                }
                .tag(SettingsTab.about)
        }
    }
}

private struct UpdateBadgedIcon: View {
    let systemName: String
    let showsBadge: Bool

    var body: some View {
        Image(systemName: systemName)
            .overlay(alignment: .topTrailing) {
                if showsBadge {
                    Circle()
                        .fill(.red)
                        .frame(width: 7, height: 7)
                        .offset(x: 4, y: -3)
                        .accessibilityHidden(true)
                }
            }
    }
}

private enum SettingsPage {
    case root
    case menuBarAliases
    case privacyDetails
}

private enum SettingsTab: Hashable {
    case general
    case modelRadar
    case tokenUsage
    case resetCredits
    case about
}
