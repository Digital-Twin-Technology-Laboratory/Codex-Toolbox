import AppKit

enum DashboardLayout {
    static let width: CGFloat = 430
    static let heightWithTrendChart: CGFloat = 680
    static let heightWithoutTrendChart: CGFloat = 460

    static func height(showsTrendChart: Bool) -> CGFloat {
        showsTrendChart ? heightWithTrendChart : heightWithoutTrendChart
    }

    static func popoverSize(showsTrendChart: Bool) -> NSSize {
        NSSize(width: width, height: height(showsTrendChart: showsTrendChart))
    }
}
