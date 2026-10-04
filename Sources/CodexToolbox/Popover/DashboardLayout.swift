import AppKit
import Observation
import CodexToolboxCore

enum DashboardLayout {
    static let width: CGFloat = 430
    static let minimumHeight: CGFloat = 280
    static let maximumHeight: CGFloat = 760
    /// Wait briefly after the last live layout measurement before deciding
    /// whether scrolling is genuinely required.
    static let scrollIndicatorRefreshNanoseconds: UInt64 = 90_000_000
    /// Hysteresis around the live ScrollView viewport prevents threshold jitter.
    static let scrollIndicatorShowThreshold: CGFloat = 8
    static let scrollIndicatorHideThreshold: CGFloat = 4
    static let scrollViewportChangeThreshold: CGFloat = 0.5
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
    var focusedContent: MenuBarContent?
    var focusRequestID = UUID()
    var temporarilyVisible: Set<ToolboxModule> = []
    var temporarilyCollapsed: Set<ToolboxModule> = []
    var temporarilyExpanded: Set<ToolboxModule> = []

    func focus(_ content: MenuBarContent, settings: AppSettings) {
        endFocus()
        focusedContent = content
        if settings.hiddenDashboardModules.contains(content.module) { temporarilyVisible.insert(content.module) }
        temporarilyExpanded.insert(content.module)
        focusRequestID = UUID()
    }
    func endFocus() {
        focusedContent = nil
        temporarilyVisible.removeAll()
        temporarilyExpanded.removeAll()
        temporarilyCollapsed.removeAll()
    }

    init(maximumHeight: CGFloat = DashboardLayout.maximumHeight) {
        self.maximumHeight = maximumHeight
    }
}
