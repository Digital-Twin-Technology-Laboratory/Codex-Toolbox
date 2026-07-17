import AppKit
import CodexToolboxCore
import SwiftUI

struct AboutView: View {
    var body: some View {
        VStack(spacing: 18) {
            Image(nsImage: NSApplication.shared.applicationIconImage)
                .resizable()
                .scaledToFit()
                .frame(width: 86, height: 86)

            VStack(spacing: 5) {
                Text("Codex Toolbox")
                    .font(.title2.bold())
                Text("版本 \(AppMetadata.version) （\(AppMetadata.build)）")
                    .foregroundStyle(.secondary)
            }

            Text("在 macOS 菜单栏查看 Codex 模型智商、本机 Token 用量与账户重置卡。")
                .multilineTextAlignment(.center)
                .frame(maxWidth: 360)

            HStack(spacing: 16) {
                Link("查看 GitHub", destination: AppMetadata.repositoryURL)
                Link("Codex 雷达", destination: AppMetadata.radarURL)
            }

            GroupBox("数据与隐私") {
                Text("模型数据来自 Codex Radar；Token 账本只读取本机 Codex 数据；重置卡只通过本机 app-server 查询。应用不调用模型、不上传任务内容、不保存重置卡 opaque ID，也不包含分析 SDK。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }

            Spacer()
        }
        .padding(28)
    }
}
