import SwiftUI

struct RadarEmptyStateView: View {
    @Bindable var appModel: AppModel

    var body: some View {
        ContentUnavailableView {
            Label("暂无模型数据", systemImage: "antenna.radiowaves.left.and.right.slash")
        } description: {
            Text(appModel.errorMessage ?? "首次启动需要连接 CodexRadar 获取数据。")
        } actions: {
            Button("重试") {
                Task { await appModel.refresh() }
            }
            .disabled(appModel.isRefreshing)
        }
    }
}
