import AppKit
import SwiftUI

@MainActor
final class StatusItemController: NSObject {
    private let statusItem: NSStatusItem
    private let statusView: MenuBarStatusView
    private let popover: NSPopover
    private let appModel: AppModel
    private let dashboardLayoutState: DashboardLayoutState

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
        if popover.contentSize != size {
            popover.contentSize = size
        }
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
            popover.performClose(nil)
        } else {
            showPopover()
        }
    }

    private func showPopover() {
        guard !popover.isShown else { return }
        updateMaximumPopoverHeight()
        NSApplication.shared.activate(ignoringOtherApps: true)
        popover.show(relativeTo: statusView.bounds, of: statusView, preferredEdge: .minY)
        popover.contentViewController?.view.window?.makeKey()
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
