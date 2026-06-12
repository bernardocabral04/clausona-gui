import AppKit
import SwiftUI

/// Singleton main window. While open the app behaves like a regular app
/// (Dock icon, ⌘-Tab); on close it returns to menu-bar-only.
@MainActor
public final class MainWindowController: NSObject, NSWindowDelegate {
    private let model: AppModel
    private let usage: UsageStore
    private var window: NSWindow?

    public init(model: AppModel, usage: UsageStore) {
        self.model = model
        self.usage = usage
        super.init()
    }

    public func show() {
        if window == nil {
            window = makeWindow()
        }
        usage.start()
        NSApp.setActivationPolicy(.regular)
        window?.makeKeyAndOrderFront(nil)
        NSApp.activate()
        Task { await model.refreshHealth() }
    }

    private func makeWindow() -> NSWindow {
        let win = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 920, height: 560),
                           styleMask: [.titled, .closable, .miniaturizable, .resizable],
                           backing: .buffered, defer: false)
        win.title = "Clausona"
        win.isReleasedWhenClosed = false
        win.center()
        win.setFrameAutosaveName("ClausonaMainWindow")
        win.delegate = self
        win.contentViewController = NSHostingController(rootView: MainWindowView(model: model, usage: usage))
        win.minSize = NSSize(width: 720, height: 420)
        return win
    }

    public func windowWillClose(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
    }
}
