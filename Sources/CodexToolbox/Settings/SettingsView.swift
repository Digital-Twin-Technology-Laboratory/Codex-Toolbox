import SwiftUI

struct SettingsView: View {
    @Bindable var appModel: AppModel
    @State private var page: SettingsPage = .root

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
            }
        }
        .frame(width: 620, height: 560)
    }

    private var rootSettings: some View {
        TabView {
            DashboardSettingsView(appModel: appModel)
                .tabItem {
                    Label("看板", systemImage: "rectangle.3.group")
                }

            TokenUsageSettingsView(appModel: appModel)
                .tabItem {
                    Label("Token", systemImage: "chart.bar.xaxis")
                }

            ModelRadarSettingsView(
                appModel: appModel,
                onOpenMenuBarAliases: { page = .menuBarAliases }
            )
            .tabItem {
                Label("模型智商", systemImage: "brain.head.profile")
            }

            ResetCreditsSettingsView(appModel: appModel)
                .tabItem {
                    Label("重置卡", systemImage: "arrow.clockwise.circle")
                }

            GeneralSystemSettingsView(appModel: appModel)
                .tabItem {
                    Label("通用", systemImage: "gearshape")
                }

            AboutView()
                .tabItem {
                    Label("关于", systemImage: "info.circle")
                }
        }
    }
}

private enum SettingsPage {
    case root
    case menuBarAliases
}
