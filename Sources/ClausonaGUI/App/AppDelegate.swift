import AppKit

@MainActor
public final class AppDelegate: NSObject, NSApplicationDelegate {
    private var model: AppModel?
    private var statusController: StatusItemController?
    private var hotkey: HotkeyManager?
    private var scheduler: RefreshScheduler?
    private var windowController: MainWindowController?
    private var usageStore: UsageStore?

    public func applicationDidFinishLaunching(_ notification: Notification) {
        let model = AppModel(deps: .live())
        self.model = model

        let controller = StatusItemController(model: model)
        statusController = controller

        let usage = UsageStore()
        usageStore = usage
        let windowController = MainWindowController(model: model, usage: usage)
        self.windowController = windowController
        model.onOpenMainWindow = { [weak controller, weak windowController] in
            controller?.close()
            windowController?.show()
        }

        let hotkey = HotkeyManager { [weak controller] in
            controller?.toggle()
        }
        if !hotkey.register() {
            NSLog("ClausonaGUI: ⌃⌥⌘L registration failed (combo already taken?) — menu bar icon still works")
        }
        self.hotkey = hotkey

        let scheduler = RefreshScheduler(
            onUsageTick: { Task { await model.refreshUsage() } },
            onHealthTick: { Task { await model.refreshHealth() } })
        scheduler.start()
        self.scheduler = scheduler

        model.refreshLaunchAtLogin()
        Task {
            await model.refreshUsage()
            await model.refreshHealth()
        }

        // Debug/manual-test hook: launch straight into the main window.
        if CommandLine.arguments.contains("--window") {
            windowController.show()
        }
    }

    public func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if !flag { windowController?.show() }
        return true
    }
}
