import CodexToolboxCore
import SwiftUI

struct ResetCreditsModuleView: View {
    @Bindable var appModel: AppModel
    @Namespace private var glassNamespace

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
                            Text(expiration.formatted(date: .abbreviated, time: .shortened))
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(expirationColor(expiration))
                        }
                    }
                }

                creditDetails(snapshot)

                Text("更新于 \(snapshot.fetchedAt.formatted(date: .omitted, time: .shortened))")
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
        .adaptiveGlassCard(tint: .teal, id: "reset-credits", namespace: glassNamespace)
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
                ForEach(snapshot.credits) { credit in
                    HStack(alignment: .top, spacing: 9) {
                        Image(systemName: credit.isAvailable ? "checkmark.circle.fill" : "clock.badge.xmark")
                            .foregroundStyle(credit.isAvailable ? .teal : .secondary)
                            .frame(width: 16)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(credit.title ?? credit.resetType ?? "重置卡")
                                .font(.caption.weight(.semibold))
                            if let expiration = credit.expiresAt {
                                Text("过期：\(expiration.formatted(date: .abbreviated, time: .shortened))")
                                    .font(.caption2)
                                    .foregroundStyle(expirationColor(expiration))
                            }
                            if appModel.settings.showsResetCreditDescriptions,
                               let description = credit.description,
                               !description.isEmpty {
                                Text(description)
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                        }
                        Spacer()
                    }
                    .padding(.vertical, 7)
                    if credit.id != snapshot.credits.last?.id { Divider() }
                }
            }

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
}
