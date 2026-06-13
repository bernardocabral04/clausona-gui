import AppKit
import SwiftUI

@MainActor
public final class SettingsWindowController: NSObject {
    private let settings: AppSettings
    private let model: AppModel
    private var window: NSWindow?

    public init(settings: AppSettings, model: AppModel) {
        self.settings = settings
        self.model = model
        super.init()
    }

    public func show() {
        if window == nil {
            let win = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 440, height: 280),
                               styleMask: [.titled, .closable],
                               backing: .buffered, defer: false)
            win.title = "Clausona Settings"
            win.isReleasedWhenClosed = false
            win.center()
            win.setFrameAutosaveName("ClausonaSettings")
            win.contentViewController = NSHostingController(rootView: SettingsView(settings: settings, model: model))
            window = win
        }
        window?.makeKeyAndOrderFront(nil)
        NSApp.activate()
    }
}
