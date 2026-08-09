import AppKit
import CodexToolboxCore
import SwiftUI

struct AboutView: View {
    let onOpenPrivacyDetails: () -> Void

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
                VStack(alignment: .leading, spacing: 10) {
                    Text("模型数据来自 Codex Radar；Token 与重置卡只读取当前 Mac 上的必要数据。应用不调用模型、不上传任务内容，也不包含分析 SDK。")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    Button(action: onOpenPrivacyDetails) {
                        HStack {
                            Label("查看数据与隐私详情", systemImage: "hand.raised")
                            Spacer()
                            Image(systemName: "chevron.right")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(.tertiary)
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }

            Spacer()
        }
        .padding(28)
    }
}

struct AboutPrivacySettingsView: View {
    let onBack: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()

            Form {
                Section("模型数据") {
                    Label("只访问 Codex Radar 的公开聚合数据", systemImage: "network")
                    Text("榜单与趋势不会发送 Codex 账户、本机任务或系统画像。")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Section("Token 用量") {
                    Label("只读本机 Codex 数据", systemImage: "externaldrive.badge.checkmark")
                    Text("账本保存 Token 汇总、增量检查点和额度估算所需的脱敏观察；不调用模型、不上传任务内容。")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Section("重置卡") {
                    Label("仅通过本机 app-server 只读查询", systemImage: "lock.shield")
                    Text("不会兑换、删除或自动使用重置卡；不保存或输出 access token、refresh token、cookie、文字说明或完整唯一 ID。")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Section("软件更新") {
                    Label("使用 Ed25519 与 Apple 代码签名校验", systemImage: "checkmark.shield")
                    Text("更新只从项目的 GitHub Release 下载，不携带 Codex/ChatGPT 账户凭据或本机任务信息。")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .formStyle(.grouped)
            .padding(8)
        }
    }

    private var header: some View {
        ZStack {
            Text("数据与隐私详情")
                .font(.headline)

            HStack {
                Button(action: onBack) {
                    Label("返回", systemImage: "chevron.left")
                }
                .buttonStyle(.borderless)
                .keyboardShortcut(.cancelAction)
                .help("返回关于")

                Spacer()
            }
        }
        .padding(.horizontal, 14)
        .frame(height: 44)
    }
}
