import AppKit
import ShowCodexIQCore
import SwiftUI

struct AboutView: View {
    var body: some View {
        VStack(spacing: 18) {
            Image(nsImage: NSApplication.shared.applicationIconImage)
                .resizable()
                .scaledToFit()
                .frame(width: 86, height: 86)

            VStack(spacing: 5) {
                Text("Show Codex IQ")
                    .font(.title2.bold())
                Text("版本 \(AppMetadata.version) （\(AppMetadata.build)）")
                    .foregroundStyle(.secondary)
            }

            Text("在 macOS 菜单栏快速查看 Codex 模型的智商、费用、耗时和综合排名。")
                .multilineTextAlignment(.center)
                .frame(maxWidth: 360)

            HStack(spacing: 16) {
                Link("查看 GitHub", destination: AppMetadata.repositoryURL)
                Link("Codex 雷达", destination: AppMetadata.radarURL)
            }

            GroupBox("数据与隐私") {
                Text("数据来自 Codex 雷达 codexradar.com。应用仅在本地保存最后一次快照和费用趋势，不收集个人信息，不包含分析 SDK。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }

            Spacer()
        }
        .padding(28)
    }
}
