import AppKit
import SwiftUI

@MainActor
public final class StatusItemController: NSObject, NSPopoverDelegate {
    private let statusItem: NSStatusItem
    private let popover = NSPopover()
    private let model: AppModel

    public init(model: AppModel) {
        self.model = model
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        super.init()

        if let button = statusItem.button {
            let image = NSImage(systemSymbolName: "gauge.with.needle", accessibilityDescription: "Clausona")
                ?? NSImage(systemSymbolName: "speedometer", accessibilityDescription: "Clausona")
            image?.isTemplate = true
            button.image = image
            button.target = self
            button.action = #selector(statusButtonClicked)
        }

        popover.behavior = .transient
        popover.animates = false
        popover.delegate = self
        popover.contentViewController = NSHostingController(rootView: PopoverView(model: model))
    }

    @objc private func statusButtonClicked() {
        toggle()
    }

    public func toggle() {
        if popover.isShown { close() } else { show() }
    }

    private func show() {
        guard let button = statusItem.button else { return }
        model.popoverDidOpen()
        popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
        popover.contentViewController?.view.window?.makeKey()
        NSApp.activate()
        button.highlight(true)
    }

    public func close() {
        popover.performClose(nil)
    }

    public func popoverDidClose(_ notification: Notification) {
        statusItem.button?.highlight(false)
    }
}
