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

            GroupBox("数据、隐私与高级选项") {
                VStack(alignment: .leading, spacing: 10) {
                    Text("模型与可选站长推荐数据来自 Codex Radar；Credits 费率与 API 等值价格来自项目托管的版本化清单。应用不调用模型、不上传任务正文或 Token 明细，也不包含分析 SDK。")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    Button(action: onOpenPrivacyDetails) {
                        HStack {
                            Label("查看数据、隐私与高级选项", systemImage: "hand.raised")
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
    @Bindable var appModel: AppModel
    let onBack: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()

            Form {
                Section("模型数据") {
                    Label("只访问 Codex Radar 的公开聚合数据", systemImage: "network")
                    Text("站长推荐默认关闭；榜单、趋势与推荐都不会发送 Codex 账户、Token、本机任务或系统画像。")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Section("用量分析") {
                    Label("只读本机 Codex 数据", systemImage: "externaldrive.badge.checkmark")
                    Text("本机账本保存原始 Token 分项、执行上下文和脱敏账户窗口；原生任务快照另按账户隔离保存 90 天。成本换算默认关闭，开启后按历史价格派生 API 等值成本与本机 Credits。")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Section("原生任务额度") {
                    Text("当前 ChatGPT 账户的原生任务查询仅向官方服务发送聊天 ID、创建日期和子代理 ID，不发送标题、正文或文件内容。每 5 分钟保存快照，完整日数据使用等号，差值或估算使用约等号；API 登录不查询套餐任务额度。")
                        .font(.caption).foregroundStyle(.secondary)
                }

                Section("费率与 API 价格更新") {
                    Label("只读取项目托管的版本化 JSON", systemImage: "dollarsign.arrow.circlepath")
                    Text("仅在开启本机成本换算后查询价格。OpenAI 价格优先采用官方 API 定价，其他供应商采用构建时同步的 models.dev 快照；客户端只请求项目托管清单。GET/ETag 不携带账户、任务、Token 或设备信息，无效远程数据不会覆盖上次有效版本。")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Section("账户额度&重置卡") {
                    Label("识别当前 Codex 登录方式", systemImage: "gauge.with.dots.needle.50percent")
                    Text("读取组件只识别 ChatGPT、API 或未登录状态，向界面返回脱敏账户标识；不查询账户分析报表，不发送聊天 ID、标题或正文。额度缓存绑定已验证账户，切换账户时拒收旧请求。界面不会接收令牌、Cookie、邮箱或原始账户 ID。")
                        .font(.caption).foregroundStyle(.secondary)
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

                Section("高级显示") {
                    Toggle(
                        "显示实验性功能入口",
                        isOn: Binding(
                            get: { appModel.settings.showsExperimentalFeaturesEntry },
                            set: { appModel.settings.showsExperimentalFeaturesEntry = $0 }
                        )
                    )
                    Text("仅控制设置首页是否显示入口，不会关闭已经启用的实验功能。")
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
            Text("数据、隐私与高级选项")
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
