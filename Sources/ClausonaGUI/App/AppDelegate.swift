import AppKit

@MainActor
public final class AppDelegate: NSObject, NSApplicationDelegate {
    private var model: AppModel?
    private var statusController: StatusItemController?
    private var hotkey: HotkeyManager?
    private var scheduler: RefreshScheduler?

    public func applicationDidFinishLaunching(_ notification: Notification) {
        let model = AppModel(deps: .live())
        self.model = model

        let controller = StatusItemController(model: model)
        statusController = controller

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
    }
}
