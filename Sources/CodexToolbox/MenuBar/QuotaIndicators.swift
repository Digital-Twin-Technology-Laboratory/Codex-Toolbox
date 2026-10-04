import CodexToolboxCore
import SwiftUI

struct QuotaIndicators: View {
    let remainingPercent: Double
    let options: QuotaDisplayOptions
    var compact = false
    private var fraction: Double { min(1, max(0, remainingPercent / 100)) }
    private var indicatorColor: Color { options.usesColor ? .blue : .primary }
    var body: some View {
        HStack(spacing: compact ? 3 : 8) {
            if options.indicator == .bar {
                GeometryReader { geometry in
                    ZStack(alignment: .leading) {
                        Capsule().fill(.secondary.opacity(0.2))
                        Capsule().fill(indicatorColor).frame(width: geometry.size.width * fraction)
                    }
                }.frame(width: compact ? 32 : 100, height: compact ? 4 : 7)
            }
            if options.indicator == .ring {
                ZStack {
                    Circle().stroke(.secondary.opacity(0.2), lineWidth: 2)
                    Circle().trim(from: 0, to: fraction).stroke(indicatorColor, style: StrokeStyle(lineWidth: 2, lineCap: .round)).rotationEffect(.degrees(-90))
                }.frame(width: compact ? 9 : 18, height: compact ? 9 : 18)
            }
            if options.percentage {
                Text(DashboardSummaryFormatter.remainingPercent(remainingPercent)).monospacedDigit()
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("剩余 \(DashboardSummaryFormatter.remainingPercent(remainingPercent))")
    }
}
