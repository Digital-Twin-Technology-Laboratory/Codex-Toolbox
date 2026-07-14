import AppKit
import SwiftUI

@MainActor
final class StatusItemController: NSObject {
    private let statusItem: NSStatusItem
    private let statusView: MenuBarStatusView
    private let popover: NSPopover
    private let appModel: AppModel

    init(appModel: AppModel) {
        self.appModel = appModel
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        statusView = MenuBarStatusView(appModel: appModel)
        popover = NSPopover()
        super.init()

        configureStatusItem()
        configurePopover(appModel: appModel)
    }

    private func configureStatusItem() {
        statusView.onClick = { [weak self] in
            self?.togglePopover()
        }
        statusItem.view = statusView
        updateStatusItemLength()
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(settingsDidChange),
            name: UserDefaults.didChangeNotification,
            object: nil
        )
    }

    @objc private func settingsDidChange() {
        updateStatusItemLength()
        updatePopoverSize()
    }

    private func updateStatusItemLength() {
        statusView.invalidateIntrinsicContentSize()
        statusItem.length = statusView.intrinsicContentSize.width
    }

    private func configurePopover(appModel: AppModel) {
        popover.behavior = .transient
        popover.animates = true
        popover.contentViewController = NSHostingController(
            rootView: DashboardView(appModel: appModel)
        )
        updatePopoverSize()
    }

    private func updatePopoverSize() {
        let size = DashboardLayout.popoverSize(
            showsTrendChart: appModel.settings.showsTrendChart
        )
        if popover.contentSize != size {
            popover.contentSize = size
        }
    }

    private func togglePopover() {
        if popover.isShown {
            popover.performClose(nil)
        } else {
            updatePopoverSize()
            NSApplication.shared.activate(ignoringOtherApps: true)
            popover.show(relativeTo: statusView.bounds, of: statusView, preferredEdge: .minY)
            popover.contentViewController?.view.window?.makeKey()
        }
    }
}

@MainActor
private final class MenuBarStatusView: NSView {
    var onClick: (() -> Void)?
    private let appModel: AppModel

    init(appModel: AppModel) {
        self.appModel = appModel
        super.init(frame: NSRect(x: 0, y: 0, width: 94, height: 22))

        let hostingView = NSHostingView(
            rootView: MenuBarLabel(appModel: appModel)
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
        setAccessibilityLabel("Show Codex IQ 模型排名")
    }

    required init?(coder: NSCoder) {
        nil
    }

    override var intrinsicContentSize: NSSize {
        var width: CGFloat = 94
        if appModel.settings.menuBarRankStyle != .hidden {
            width += 14
        }
        if appModel.settings.showsMenuBarDetails {
            width += 38
        }
        return NSSize(width: width, height: 22)
    }

    override func hitTest(_ point: NSPoint) -> NSView? {
        self
    }

    override func mouseDown(with event: NSEvent) {
        onClick?()
    }
}
