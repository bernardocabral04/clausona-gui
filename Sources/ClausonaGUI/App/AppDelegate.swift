import AppKit

@MainActor
public final class AppDelegate: NSObject, NSApplicationDelegate {
    private var model: AppModel?
    private var statusController: StatusItemController?
    private var hotkey: HotkeyManager?
    private var scheduler: RefreshScheduler?
    private var windowController: MainWindowController?
    private var usageStore: UsageStore?
    private var settings: AppSettings?
    private var settingsController: SettingsWindowController?
    private var stateWatcher: FileWatcher?
    private var profilesWatcher: FileWatcher?
    private var stateDebouncer: Debouncer?

    public func applicationDidFinishLaunching(_ notification: Notification) {
        let settings = AppSettings()
        self.settings = settings
        let model = AppModel(deps: .live(settings: settings))
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

        let settingsController = SettingsWindowController(settings: settings, model: model)
        self.settingsController = settingsController
        model.onOpenSettings = { [weak controller, weak settingsController] in
            controller?.close()
            settingsController?.show()
        }

        let hotkey = HotkeyManager { [weak controller] in
            controller?.toggle()
        }
        if !hotkey.register() {
            NSLog("ClausonaGUI: ⌃⌥⌘L registration failed (combo already taken?) — menu bar icon still works")
        }
        self.hotkey = hotkey

        let scheduler = RefreshScheduler(
            onUsageTick: { [weak self] in
                self?.stateWatcher?.startIfNeeded()
                Task { await model.refreshUsage() }
            },
            onHealthTick: { Task { await model.refreshHealth() } })
        scheduler.updateUsageInterval(TimeInterval(settings.refreshMinutes * 60))
        scheduler.start()
        self.scheduler = scheduler
        settings.onRefreshIntervalChange = { [weak self, weak settings] in
            guard let settings else { return }
            self?.scheduler?.updateUsageInterval(TimeInterval(settings.refreshMinutes * 60))
        }

        // StateWatcher: any change in ~/.clausona (add/remove/init/config — from the
        // GUI or a plain terminal) refreshes the model after a debounce.
        let debouncer = Debouncer(interval: 0.7) {
            Task {
                await model.refreshUsage()
                await model.refreshHealth()
            }
        }
        stateDebouncer = debouncer
        let clausonaHome = ProcessInfo.processInfo.environment["CLAUSONA_HOME"] ?? NSHomeDirectory() + "/.clausona"
        // profiles.json is rewritten IN PLACE by clausona (verified: same inode
        // across `clausona use`), which a directory watch cannot see — so watch
        // the file directly. The directory watch covers creation/deletion (init,
        // remove, first-run) and re-arms the file watch when the file appears.
        let profilesWatcher = FileWatcher(path: clausonaHome + "/profiles.json") { [weak debouncer] in
            debouncer?.call()
        }
        self.profilesWatcher = profilesWatcher
        profilesWatcher.start()
        let watcher = FileWatcher(path: clausonaHome) { [weak debouncer, weak profilesWatcher] in
            debouncer?.call()
            profilesWatcher?.startIfNeeded()
        }
        stateWatcher = watcher
        watcher.start()

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
