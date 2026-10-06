import SwiftUI

struct RadarEmptyStateView: View {
    @Bindable var appModel: AppModel

    var body: some View {
        ContentUnavailableView {
            Label("暂无模型数据", systemImage: "antenna.radiowaves.left.and.right.slash")
        } description: {
            Text(appModel.errorMessage ?? "暂无榜单数据，请稍后重试。")
        } actions: {
            Button("重试") {
                Task { await appModel.refresh() }
            }
            .disabled(appModel.isRefreshing)
        }
    }
}
