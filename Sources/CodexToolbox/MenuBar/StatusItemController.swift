import AppKit
import SwiftUI

@MainActor
final class StatusItemController: NSObject {
    private let statusItem: NSStatusItem
    private let statusView: MenuBarStatusView
    private let popover: NSPopover
    private let appModel: AppModel
    private let dashboardLayoutState: DashboardLayoutState
    private var pendingPopoverSize: NSSize?
    private var isPopoverSizeUpdateScheduled = false
    private var localMouseMonitor: Any?
    private var globalMouseMonitor: Any?

    init(appModel: AppModel) {
        self.appModel = appModel
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        statusView = MenuBarStatusView(appModel: appModel)
        popover = NSPopover()
        dashboardLayoutState = DashboardLayoutState()
        super.init()

        configureStatusItem()
        configurePopover(appModel: appModel)

        #if DEBUG
        if ProcessInfo.processInfo.arguments.contains("--show-dashboard") {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
                self?.showPopover()
            }
        }
        #endif
    }

    private func configureStatusItem() {
        statusView.onClick = { [weak self] in
            self?.togglePopover()
        }
        statusView.onPreferredWidthChange = { [weak self] width in
            self?.updateStatusItemLength(to: width)
        }
        statusItem.view = statusView
        updateStatusItemLength(to: statusView.intrinsicContentSize.width)
    }

    private func updateStatusItemLength(to width: CGFloat) {
        let resolvedWidth = ceil(max(1, width))
        if statusItem.length != resolvedWidth {
            statusItem.length = resolvedWidth
        }
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
        let screen = statusView.window?.screen ?? NSScreen.main
        dashboardLayoutState.maximumHeight = DashboardLayout.maximumHeight(for: screen)
        if popover.contentSize.height > dashboardLayoutState.maximumHeight {
            updatePopoverHeight(to: dashboardLayoutState.maximumHeight)
        }
    }

    private func togglePopover() {
        if popover.isShown {
            closePopover()
        } else {
            showPopover()
        }
    }

    private func showPopover() {
        guard !popover.isShown else { return }
        updateMaximumPopoverHeight()
        applyPendingPopoverSize()
        NSApplication.shared.activate(ignoringOtherApps: true)
        popover.show(relativeTo: statusView.bounds, of: statusView, preferredEdge: .minY)
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

        guard event.window === statusView.window else { return false }
        let pointInStatusView = statusView.convert(event.locationInWindow, from: nil)
        return statusView.bounds.contains(pointInStatusView)
    }
}

extension StatusItemController: NSPopoverDelegate {
    func popoverDidClose(_ notification: Notification) {
        endOutsideClickMonitoring()
    }
}

@MainActor
private final class MenuBarStatusView: NSView {
    var onClick: (() -> Void)?
    var onPreferredWidthChange: ((CGFloat) -> Void)?
    private var preferredWidth: CGFloat = 62

    init(appModel: AppModel) {
        super.init(frame: NSRect(x: 0, y: 0, width: 94, height: 22))

        let hostingView = NSHostingView(
            rootView: MenuBarLabel(
                appModel: appModel,
                onPreferredWidthChange: { [weak self] width in
                    self?.contentWidthDidChange(width)
                }
            )
                .frame(height: 22)
                .contentShape(Rectangle())
                .allowsHitTesting(false)
        )
        hostingView.translatesAutoresizingMaskIntoConstraints = false
        addSubview(hostingView)

        NSLayoutConstraint.activate([
            hostingView.leadingAnchor.constraint(equalTo: leadingAnchor),
            hostingView.trailingAnchor.constraint(equalTo: trailingAnchor),
            hostingView.topAnchor.constraint(equalTo: topAnchor),
            hostingView.bottomAnchor.constraint(equalTo: bottomAnchor)
        ])

        setAccessibilityElement(true)
        setAccessibilityRole(.button)
        setAccessibilityLabel("Codex Toolbox 菜单栏工具")
    }

    required init?(coder: NSCoder) {
        nil
    }

    override var intrinsicContentSize: NSSize {
        NSSize(width: preferredWidth, height: 22)
    }

    private func contentWidthDidChange(_ width: CGFloat) {
        let resolvedWidth = ceil(max(1, width))
        guard preferredWidth != resolvedWidth else { return }
        preferredWidth = resolvedWidth
        invalidateIntrinsicContentSize()
        onPreferredWidthChange?(resolvedWidth)
    }

    override func hitTest(_ point: NSPoint) -> NSView? {
        self
    }

    override func mouseDown(with event: NSEvent) {
        onClick?()
    }
}
