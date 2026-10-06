import AppKit
import SwiftUI
import Observation
import CodexToolboxCore

@MainActor
final class StatusItemController: NSObject {
    private struct Entry {
        let item: NSStatusItem
        let button: NSStatusBarButton
    }
    private var entries: [UUID: Entry] = [:]
    private var orderedIDs: [UUID] = []
    private var anchorID: UUID?
    private let popover: NSPopover
    private let appModel: AppModel
    private let dashboardLayoutState: DashboardLayoutState
    private var pendingPopoverSize: NSSize?
    private var isPopoverSizeUpdateScheduled = false
    private var localMouseMonitor: Any?
    private var globalMouseMonitor: Any?

    init(appModel: AppModel) {
        self.appModel = appModel
        popover = NSPopover()
        dashboardLayoutState = DashboardLayoutState()
        super.init()
        reconcileItems()
        observeConfiguration()
        configurePopover(appModel: appModel)
        #if DEBUG
        if ProcessInfo.processInfo.arguments.contains("--show-dashboard") {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
                guard let self, let id = self.orderedIDs.first else { return }
                self.showPopover(from: id)
            }
        }
        #endif
    }

    private func observeConfiguration() {
        withObservationTracking {
            _ = appModel.settings.menuBarConfiguration
            _ = appModel.settings.experimentalLocalCostEstimatesEnabled
            _ = appModel.radarScoreLabel
        } onChange: { [weak self] in
            Task { @MainActor in
                self?.reconcileItems()
                self?.observeConfiguration()
            }
        }
    }

    private func reconcileItems() {
        let configurations = appModel.settings.menuBarConfiguration.items
        if let anchorID, !configurations.contains(where: { $0.id == anchorID && $0.isEnabled }) { closePopover() }
        orderedIDs = configurations.map(\.id)
        // Each slot owns one stable status item. AppKit owns its saved position.
        for configuration in configurations.reversed() {
            let content = configuration.content.resolved(localCostEstimatesEnabled: appModel.settings.experimentalLocalCostEstimatesEnabled)
            if let entry = entries[configuration.id] {
                entry.item.isVisible = configuration.isEnabled
                entry.button.setAccessibilityLabel("Codex Toolbox：\((content == .iq ? appModel.radarScoreLabel : content.displayName))")
                entry.button.toolTip = (content == .iq ? appModel.radarScoreLabel : content.displayName)
                continue
            }
            let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
            item.autosaveName = "CodexToolbox-\(configuration.id.uuidString)"
            item.isVisible = configuration.isEnabled
            guard let button = item.button else { continue }
            button.identifier = NSUserInterfaceItemIdentifier(configuration.id.uuidString)
            button.target = self
            button.action = #selector(statusItemClicked(_:))
            button.setAccessibilityLabel("Codex Toolbox：\((content == .iq ? appModel.radarScoreLabel : content.displayName))")
            button.toolTip = (content == .iq ? appModel.radarScoreLabel : content.displayName)
            let hostingView = StatusLabelHostingView(rootView: MenuBarLabel(
                appModel: appModel, itemID: configuration.id,
                onPreferredWidthChange: { [weak self] width in
                    Task { @MainActor in self?.entries[configuration.id]?.item.length = ceil(max(1, width)) }
                }
            ).frame(height: 22).allowsHitTesting(false))
            hostingView.translatesAutoresizingMaskIntoConstraints = false
            button.addSubview(hostingView)
            NSLayoutConstraint.activate([
                hostingView.leadingAnchor.constraint(equalTo: button.leadingAnchor),
                hostingView.trailingAnchor.constraint(equalTo: button.trailingAnchor),
                hostingView.topAnchor.constraint(equalTo: button.topAnchor),
                hostingView.bottomAnchor.constraint(equalTo: button.bottomAnchor)
            ])
            item.length = max(30, hostingView.fittingSize.width)
            entries[configuration.id] = Entry(item: item, button: button)
        }
    }

    @objc private func statusItemClicked(_ sender: NSStatusBarButton) {
        guard let raw = sender.identifier?.rawValue, let id = UUID(uuidString: raw) else { return }
        if popover.isShown, anchorID == id { closePopover(); return }
        if popover.isShown {
            let animates = popover.animates
            popover.animates = false
            closePopover()
            popover.animates = animates
        }
        showPopover(from: id)
    }

    private func configurePopover(appModel: AppModel) {
        popover.behavior = .transient
        popover.animates = true
        popover.delegate = self
        popover.contentViewController = NSHostingController(
            rootView: DashboardView(
                appModel: appModel,
                layoutState: dashboardLayoutState,
                onPreferredHeightChange: { [weak self] height in
                    self?.updatePopoverHeight(to: height)
                }
            )
        )
        updateMaximumPopoverHeight()
    }

    private func updatePopoverHeight(to height: CGFloat) {
        let size = NSSize(width: DashboardLayout.width, height: ceil(height))
        guard size != pendingPopoverSize else { return }
        if size == popover.contentSize {
            pendingPopoverSize = nil
            return
        }
        pendingPopoverSize = size
        guard !isPopoverSizeUpdateScheduled else { return }
        isPopoverSizeUpdateScheduled = true

        // A SwiftUI layout callback is still inside NSHostingView.layout().
        // Mutating NSPopover.contentSize synchronously can re-enter AppKit's
        // animated resize path and crash in NSMoveHelper on macOS 27.
        DispatchQueue.main.async { [weak self] in
            self?.applyPendingPopoverSize()
        }
    }

    private func applyPendingPopoverSize() {
        isPopoverSizeUpdateScheduled = false
        guard let size = pendingPopoverSize else { return }
        pendingPopoverSize = nil
        guard popover.contentSize != size else { return }

        // Keep the normal presentation animation, but never ask AppKit to
        // animate a live content-size mutation. SwiftUI owns the content
        // transition and remains fully interruptible.
        let presentationAnimates = popover.animates
        popover.animates = false
        popover.contentSize = size
        popover.animates = presentationAnimates
    }

    private func updateMaximumPopoverHeight() {
        let screen = anchorID.flatMap { entries[$0]?.button.window?.screen } ?? NSScreen.main
        dashboardLayoutState.maximumHeight = DashboardLayout.maximumHeight(for: screen)
        if popover.contentSize.height > dashboardLayoutState.maximumHeight {
            updatePopoverHeight(to: dashboardLayoutState.maximumHeight)
        }
    }

    private func showPopover(from id: UUID) {
        guard !popover.isShown, let entry = entries[id],
              let configuration = appModel.settings.menuBarConfiguration.items.first(where: { $0.id == id }) else { return }
        anchorID = id
        dashboardLayoutState.focus(configuration.content.resolved(localCostEstimatesEnabled: appModel.settings.experimentalLocalCostEstimatesEnabled), settings: appModel.settings)
        updateMaximumPopoverHeight()
        applyPendingPopoverSize()
        NSApplication.shared.activate(ignoringOtherApps: true)
        popover.show(relativeTo: entry.button.bounds, of: entry.button, preferredEdge: .minY)
        popover.contentViewController?.view.window?.makeKey()
        beginOutsideClickMonitoring()
    }

    private func closePopover() {
        guard popover.isShown else {
            endOutsideClickMonitoring()
            return
        }
        popover.performClose(nil)
    }

    private func beginOutsideClickMonitoring() {
        guard localMouseMonitor == nil, globalMouseMonitor == nil else { return }
        let eventMask: NSEvent.EventTypeMask = [.leftMouseDown, .rightMouseDown, .otherMouseDown]

        // Local monitors receive normal application events, while AppKit keeps
        // menu tracking inside its own nested event loop. This lets SwiftUI
        // menus finish normally and restores deterministic outside-click
        // dismissal immediately after the menu closes.
        localMouseMonitor = NSEvent.addLocalMonitorForEvents(matching: eventMask) { [weak self] event in
            guard let self, self.popover.isShown else { return event }
            guard !self.isEventInsidePresentedInterface(event) else { return event }
            self.closePopover()
            return event
        }

        // Global mouse monitoring does not require Accessibility permission;
        // only key-event monitoring has that restriction.
        globalMouseMonitor = NSEvent.addGlobalMonitorForEvents(matching: eventMask) { [weak self] _ in
            Task { @MainActor in
                self?.closePopover()
            }
        }
    }

    private func endOutsideClickMonitoring() {
        if let localMouseMonitor {
            NSEvent.removeMonitor(localMouseMonitor)
            self.localMouseMonitor = nil
        }
        if let globalMouseMonitor {
            NSEvent.removeMonitor(globalMouseMonitor)
            self.globalMouseMonitor = nil
        }
    }

    private func isEventInsidePresentedInterface(_ event: NSEvent) -> Bool {
        if event.window === popover.contentViewController?.view.window {
            return true
        }

        return entries.values.contains { entry in
            guard event.window === entry.button.window else { return false }
            return entry.button.bounds.contains(entry.button.convert(event.locationInWindow, from: nil))
        }
    }
}

extension StatusItemController: NSPopoverDelegate {
    func popoverDidClose(_ notification: Notification) {
        endOutsideClickMonitoring()
        dashboardLayoutState.endFocus()
    }
}

@MainActor
private final class StatusLabelHostingView<Content: View>: NSHostingView<Content> {
    override func hitTest(_ point: NSPoint) -> NSView? { nil }
}
