import CodexToolboxCore
import SwiftUI

struct ResetCreditsModuleView: View {
    @Bindable var appModel: AppModel
    @Namespace private var glassNamespace
    @Environment(\.dashboardTheme) private var dashboardTheme

    var body: some View {
        VStack(alignment: .leading, spacing: 11) {
            if let snapshot = appModel.resetCreditsSnapshot {
                HStack(alignment: .firstTextBaseline) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("\(snapshot.availableCount)")
                            .font(.system(size: 28, weight: .bold, design: .rounded))
                            .monospacedDigit()
                        Text("账户可用重置卡")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    if let expiration = snapshot.nearestExpiration {
                        VStack(alignment: .trailing, spacing: 2) {
                            Text("最近过期")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                            Text(beijingDate(expiration))
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(expirationColor(expiration))
                        }
                    }
                }

                creditDetails(snapshot)

                Text("更新于 \(beijingDate(snapshot.fetchedAt))（北京时间）")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                    .frame(maxWidth: .infinity, alignment: .trailing)
            } else if appModel.isResetCreditsInitialLoading {
                HStack(spacing: 8) {
                    ProgressView().controlSize(.small)
                    Text("正在读取账户重置卡…")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, minHeight: 72)
            } else {
                ContentUnavailableView {
                    Label("重置卡暂不可用", systemImage: "person.crop.circle.badge.exclamationmark")
                } description: {
                    Text("请安装并登录 Codex 或 ChatGPT，然后重新刷新。")
                }
                .frame(minHeight: 104)
            }

            if let error = appModel.resetCreditsErrorMessage {
                InlineModuleNotice(
                    text: error,
                    systemImage: "exclamationmark.triangle.fill",
                    color: .orange
                )
            }
        }
        .padding(12)
        .adaptiveGlassCard(tint: tint, id: "reset-credits", namespace: glassNamespace)
        .accessibilityElement(children: .contain)
    }

    @ViewBuilder
    private func creditDetails(_ snapshot: ResetCreditsSnapshot) -> some View {
        if snapshot.credits.isEmpty {
            Text(snapshot.availableCount == 0 ? "当前没有可用重置卡" : "服务仅返回了数量，暂未提供逐卡详情")
                .font(.caption)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, minHeight: 34, alignment: .leading)
        } else {
            VStack(spacing: 0) {
                ForEach(Array(snapshot.credits.enumerated()), id: \.element.id) { index, credit in
                    HStack(alignment: .top, spacing: 9) {
                        Image(systemName: "clock")
                            .foregroundStyle(tint)
                            .frame(width: 16)
                        VStack(alignment: .leading, spacing: 2) {
                            Text("重置卡 \(index + 1)")
                                .font(.caption.weight(.semibold))
                            Text("发放：\(credit.grantedAt.map(beijingDate) ?? "服务未提供")")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                            Text("过期：\(credit.expiresAt.map(beijingDate) ?? "服务未提供")")
                                .font(.caption2)
                                .foregroundStyle(credit.expiresAt.map(expirationColor) ?? .secondary)
                        }
                        Spacer()
                    }
                    .padding(.vertical, 7)
                    if credit.id != snapshot.credits.last?.id { Divider() }
                }
            }

            Text("上述时间均为北京时间（UTC+8）")
                .font(.caption2)
                .foregroundStyle(.tertiary)

            let missingDetails = max(0, snapshot.availableCount - snapshot.availableCredits.count)
            if missingDetails > 0 {
                Text("另有 \(missingDetails) 张可用卡未返回详细信息")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func expirationColor(_ date: Date) -> Color {
        let warningDays = appModel.settings.resetExpiryWarning.rawValue
        guard warningDays > 0,
              date <= Calendar.current.date(byAdding: .day, value: warningDays, to: Date()) ?? Date() else {
            return .secondary
        }
        return .orange
    }

    private func beijingDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_CN")
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.timeZone = TimeZone(identifier: "Asia/Shanghai")
        formatter.dateFormat = "yyyy年M月d日 HH:mm"
        return formatter.string(from: date)
    }

    private var tint: Color {
        dashboardTheme.palette.accent(for: .resetCredits)
    }
}
