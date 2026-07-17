import AppKit
import Observation

enum DashboardLayout {
    static let width: CGFloat = 430
    static let minimumHeight: CGFloat = 280
    static let maximumHeight: CGFloat = 760
    static let screenEdgeMargin: CGFloat = 16
    static let emptyContentHeight: CGFloat = 220

    static func maximumHeight(for screen: NSScreen?) -> CGFloat {
        guard let screen else { return maximumHeight }
        let availableHeight = screen.visibleFrame.height - screenEdgeMargin
        return max(minimumHeight, min(maximumHeight, availableHeight))
    }
}

@MainActor
@Observable
final class DashboardLayoutState {
    var maximumHeight: CGFloat

    init(maximumHeight: CGFloat = DashboardLayout.maximumHeight) {
        self.maximumHeight = maximumHeight
    }
}
