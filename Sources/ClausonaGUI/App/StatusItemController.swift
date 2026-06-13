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
            let image = MenuBarIcon.image()
                ?? NSImage(systemSymbolName: "gauge.with.needle", accessibilityDescription: "Clausona")
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
        // .maxY = the bottom edge in the button's flipped coordinate space.
        popover.show(relativeTo: button.bounds, of: button, preferredEdge: .maxY)
        realignUnderButton(button)
        popover.contentViewController?.view.window?.makeKey()
        NSApp.activate()
        button.highlight(true)
    }

    /// Works around the OS misplacing status-item popovers (see PopoverAnchor).
    private func realignUnderButton(_ button: NSStatusBarButton) {
        guard let popoverWindow = popover.contentViewController?.view.window,
              let buttonWindow = button.window else { return }
        let buttonRect = buttonWindow.convertToScreen(button.convert(button.bounds, to: nil))
        guard PopoverAnchor.needsCorrection(popover: popoverWindow.frame, buttonScreenRect: buttonRect) else { return }
        guard let screen = NSScreen.screens.first(where: { $0.frame.intersects(buttonRect) })
            ?? buttonWindow.screen ?? NSScreen.main else { return }
        if !Self.didLogAnchorCorrection {
            Self.didLogAnchorCorrection = true
            NSLog("ClausonaGUI: correcting OS popover misplacement (\(popoverWindow.frame)) to anchor under the status icon — remove PopoverAnchor once the system places it correctly")
        }
        let fixed = PopoverAnchor.correctedFrame(popover: popoverWindow.frame,
                                                 buttonScreenRect: buttonRect,
                                                 screen: screen.frame)
        popoverWindow.setFrame(fixed, display: true)
    }

    private static var didLogAnchorCorrection = false

    public func close() {
        popover.performClose(nil)
    }

    public func popoverDidClose(_ notification: Notification) {
        statusItem.button?.highlight(false)
    }
}
