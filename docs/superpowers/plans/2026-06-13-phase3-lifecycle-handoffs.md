# Clausona GUI Phase 3 — Lifecycle Handoffs & Settings Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Start clausona's interactive lifecycle flows (add/login/remove/init/config) from the GUI via terminal handoff, auto-reflect results by watching `~/.clausona`, and add a Settings window (terminal choice, refresh interval, launch-at-login).

**Architecture:** A `TerminalLauncher` opens the user's chosen terminal running a clausona command — AppleScript for Terminal.app, a self-deleting `.command` wrapper for Warp/iTerm2/other, with graceful fallbacks. A `StateWatcher` (directory `FileWatcher` + `Debouncer`) refreshes the model when clausona's files change — no pending-operation state. `AppSettings` is an `@Observable` UserDefaults wrapper feeding both the launcher and the refresh scheduler.

**Tech Stack:** Swift 6, SwiftPM, macOS 14+, NSAppleScript, NSWorkspace, UserDefaults, XCTest.

**Spec:** `docs/superpowers/specs/2026-06-12-phase3-lifecycle-handoffs-design.md`

---

## Verified ground truth (collected 2026-06-13)

- `clausona help` commands: run, init, add, use, list, usage, current, config, doctor, repair, login, remove, uninstall, shell-init, version. Phase 3 handoffs: add/login/remove/init/config. (`run`, `uninstall`, `shell-init`, `version` stay CLI-only.)
- Installed terminals on this machine: `/Applications/Warp.app`, `/Applications/iTerm.app` (plus stock Terminal.app) — all three testable.
- `FileWatcher` (Phase 2) takes a path; a **directory** fd gets `.write` events when entries are created/deleted/renamed inside it — watching `~/.clausona` (the dir) catches `profiles.json` creation by `clausona init`, which a file watch on a missing file cannot.
- clausona writes several files per operation → debounce required (spec: rapid writes → one reload).

## File structure

```
Sources/ClausonaGUI/
├── Core/ProfileName.swift                  — name validation ([a-z0-9-]+)
├── Core/ClausonaFlow.swift                 — flow enum + terminal command string (quoting)
├── Core/TerminalLauncher.swift             — AppleScript / .command builders (pure) + launch glue
├── Core/AppSettings.swift                  — @Observable UserDefaults wrapper
├── Core/Debouncer.swift                    — trailing-edge debounce for state changes
├── Core/AppModel.swift                     — MODIFY: startFlow + notice via toast
├── Core/AppDependencies.swift              — MODIFY: launchFlow closure
├── Core/RefreshScheduler.swift             — MODIFY: updateUsageInterval
├── Settings/SettingsWindowController.swift — NSWindow singleton (⌘, target)
├── Settings/SettingsView.swift             — terminal/interval/launch-at-login form
├── App/AppDelegate.swift                   — MODIFY: StateWatcher wiring, settings window, launcher
├── UI/FooterView.swift                     — MODIFY: ＋ Add (sheet) + gear buttons
├── UI/AddProfileSheet.swift                — name field + validation + handoff
├── UI/ProfileRowView.swift                 — MODIFY: Login button on login-needed rows
├── UI/PopoverView.swift                    — MODIFY: empty state gets "Set up clausona…" action
├── UI/EmptyStateView.swift                 — MODIFY: optional action button
├── MainWindow/Profiles/ProfileDetailView.swift — MODIFY: Actions section (login/config/remove)
├── MainWindow/MainWindowView.swift         — MODIFY: sidebar Add Profile button + Settings in toolbar
Tests/ClausonaGUITests/
├── ProfileNameTests, ClausonaFlowTests, TerminalLauncherTests,
├── AppSettingsTests, DebouncerTests, FileWatcherTests (extend: directory watch),
├── AppModelTests (extend: startFlow)
```

Design decisions locked here:
- Handoff notices reuse the existing `toast` (popover) — no new notice UI.
- The Add-profile sheet validates live and disables Add until valid; remove has NO GUI confirmation (clausona's TUI is the gate, per spec).
- `StateWatcher` = `FileWatcher` on the `~/.clausona` directory + 700 ms `Debouncer` → `refreshUsage()` + `refreshHealth()`. Covers flows started outside the GUI too.

---

### Task 0: Branch

- [ ] **Step 1:** `git checkout -b phase3-lifecycle-handoffs`

### Task 1: ProfileName validation

**Files:**
- Create: `Sources/ClausonaGUI/Core/ProfileName.swift`
- Test: `Tests/ClausonaGUITests/ProfileNameTests.swift`

- [ ] **Step 1: Failing tests**

```swift
import XCTest
@testable import ClausonaGUI

final class ProfileNameTests: XCTestCase {
    func testValidNames() {
        XCTAssertTrue(ProfileName.isValid("personal"))
        XCTAssertTrue(ProfileName.isValid("work-belen"))
        XCTAssertTrue(ProfileName.isValid("p2"))
        XCTAssertTrue(ProfileName.isValid("123"))
    }

    func testInvalidNames() {
        XCTAssertFalse(ProfileName.isValid(""))
        XCTAssertFalse(ProfileName.isValid("Work"))          // uppercase
        XCTAssertFalse(ProfileName.isValid("my profile"))    // space
        XCTAssertFalse(ProfileName.isValid("nome_novo"))     // underscore
        XCTAssertFalse(ProfileName.isValid("a;rm -rf ~"))    // shell metacharacters
        XCTAssertFalse(ProfileName.isValid("café"))          // non-ascii
    }
}
```

- [ ] **Step 2:** `swift test --filter ProfileNameTests` — FAIL (undefined).

- [ ] **Step 3: Implement**

```swift
public enum ProfileName {
    /// Mirrors clausona's accepted names; doubles as the shell-safety gate for handoffs.
    public static func isValid(_ name: String) -> Bool {
        !name.isEmpty && name.wholeMatch(of: /[a-z0-9-]+/) != nil
    }
}
```

- [ ] **Step 4:** `swift test --filter ProfileNameTests` — PASS.
- [ ] **Step 5:** `git add -A && git commit -m "feat: profile name validation"`

### Task 2: ClausonaFlow

**Files:**
- Create: `Sources/ClausonaGUI/Core/ClausonaFlow.swift`
- Test: `Tests/ClausonaGUITests/ClausonaFlowTests.swift`

- [ ] **Step 1: Failing tests**

```swift
import XCTest
@testable import ClausonaGUI

final class ClausonaFlowTests: XCTestCase {
    func testCommands() {
        let bin = "/Users/u/.local/bin/clausona"
        XCTAssertEqual(ClausonaFlow.add(name: "work").command(binaryPath: bin),
                       "'/Users/u/.local/bin/clausona' add work")
        XCTAssertEqual(ClausonaFlow.login(name: "p2").command(binaryPath: bin),
                       "'/Users/u/.local/bin/clausona' login p2")
        XCTAssertEqual(ClausonaFlow.remove(name: "old").command(binaryPath: bin),
                       "'/Users/u/.local/bin/clausona' remove old")
        XCTAssertEqual(ClausonaFlow.config(name: "work").command(binaryPath: bin),
                       "'/Users/u/.local/bin/clausona' config work")
        XCTAssertEqual(ClausonaFlow.initialSetup.command(binaryPath: bin),
                       "'/Users/u/.local/bin/clausona' init")
    }

    func testBinaryPathWithSpacesIsQuoted() {
        let cmd = ClausonaFlow.initialSetup.command(binaryPath: "/Users/u/my tools/clausona")
        XCTAssertEqual(cmd, "'/Users/u/my tools/clausona' init")
    }
}
```

- [ ] **Step 2:** `swift test --filter ClausonaFlowTests` — FAIL.

- [ ] **Step 3: Implement**

```swift
/// A clausona lifecycle flow handed off to a terminal. Names must already be
/// ProfileName-valid (enforced at the UI boundary), so they need no quoting.
public enum ClausonaFlow: Equatable, Sendable {
    case add(name: String)
    case login(name: String)
    case remove(name: String)
    case config(name: String)
    case initialSetup

    public func command(binaryPath: String) -> String {
        let bin = "'" + binaryPath + "'"
        switch self {
        case .add(let name): return "\(bin) add \(name)"
        case .login(let name): return "\(bin) login \(name)"
        case .remove(let name): return "\(bin) remove \(name)"
        case .config(let name): return "\(bin) config \(name)"
        case .initialSetup: return "\(bin) init"
        }
    }
}
```

- [ ] **Step 4:** `swift test --filter ClausonaFlowTests` — PASS.
- [ ] **Step 5:** `git add -A && git commit -m "feat: clausona flow commands"`

### Task 3: TerminalLauncher

**Files:**
- Create: `Sources/ClausonaGUI/Core/TerminalLauncher.swift`
- Test: `Tests/ClausonaGUITests/TerminalLauncherTests.swift`

- [ ] **Step 1: Failing tests** (pure builders: AppleScript escaping, wrapper content; wrapper file creation on disk):

```swift
import XCTest
@testable import ClausonaGUI

final class TerminalLauncherTests: XCTestCase {
    func testAppleScriptEscapesQuotesAndBackslashes() {
        let script = TerminalLauncher.appleScript(for: #"'/Users/u/my "tools"/clausona' init"#)
        XCTAssertTrue(script.contains(#"do script "'/Users/u/my \"tools\"/clausona' init""#))
        XCTAssertTrue(script.contains("tell application \"Terminal\""))
        XCTAssertTrue(script.contains("activate"))
    }

    func testWrapperScriptExecsCommandAndSelfDeletes() {
        let body = TerminalLauncher.wrapperScript(for: "'/usr/local/bin/clausona' add work")
        XCTAssertTrue(body.hasPrefix("#!/bin/zsh\n"))
        XCTAssertTrue(body.contains(#"rm -f -- "$0""#))
        XCTAssertTrue(body.contains("exec '/usr/local/bin/clausona' add work"))
        // self-delete must come BEFORE exec (exec never returns)
        let rmIndex = body.range(of: "rm -f")!.lowerBound
        let execIndex = body.range(of: "exec ")!.lowerBound
        XCTAssertLessThan(rmIndex, execIndex)
    }

    func testWriteWrapperCreatesExecutableCommandFile() throws {
        let url = try TerminalLauncher.writeWrapper(for: "echo hello")
        defer { try? FileManager.default.removeItem(at: url) }
        XCTAssertEqual(url.pathExtension, "command")
        let attrs = try FileManager.default.attributesOfItem(atPath: url.path)
        let perms = (attrs[.posixPermissions] as? NSNumber)?.int16Value ?? 0
        XCTAssertEqual(perms & 0o111, 0o111)   // executable
        let body = try String(contentsOf: url, encoding: .utf8)
        XCTAssertTrue(body.contains("echo hello"))
    }
}
```

- [ ] **Step 2:** `swift test --filter TerminalLauncherTests` — FAIL.

- [ ] **Step 3: Implement**

```swift
import AppKit

/// Opens the user's terminal running a clausona command. We never reimplement
/// or script clausona's TUI — the terminal is the UI; we detect results by
/// watching clausona's state files (StateWatcher).
@MainActor
public enum TerminalLauncher {
    public enum TerminalChoice: String, CaseIterable, Sendable {
        case terminal = "Terminal"
        case warp = "Warp"
        case iterm = "iTerm2"
        case other = "Other"
    }

    /// AppleScript for Terminal.app. Quotes/backslashes in the shell command
    /// must be escaped for the AppleScript string literal.
    public static func appleScript(for command: String) -> String {
        let escaped = command
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
        return """
        tell application "Terminal"
            activate
            do script "\(escaped)"
        end tell
        """
    }

    /// Self-deleting wrapper for the `.command` route (Warp/iTerm2/other —
    /// and the fallback when Terminal automation is denied). `rm` runs before
    /// `exec` because exec never returns.
    public static func wrapperScript(for command: String) -> String {
        """
        #!/bin/zsh
        rm -f -- "$0"
        exec \(command)
        """
    }

    public static func writeWrapper(for command: String) throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("clausona-\(UUID().uuidString)")
            .appendingPathExtension("command")
        try wrapperScript(for: command).write(to: url, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: url.path)
        return url
    }

    /// Returns a user-facing notice when a fallback happened, nil on the happy path.
    public static func launch(_ command: String, using choice: TerminalChoice, otherAppPath: String?) -> String? {
        switch choice {
        case .terminal:
            return launchViaAppleScript(command)
        case .warp:
            return launchViaWrapper(command, appPath: "/Applications/Warp.app", appName: "Warp")
        case .iterm:
            return launchViaWrapper(command, appPath: "/Applications/iTerm.app", appName: "iTerm2")
        case .other:
            guard let otherAppPath, FileManager.default.fileExists(atPath: otherAppPath) else {
                let notice = launchViaAppleScript(command)
                return notice ?? "Chosen terminal not found — used Terminal.app"
            }
            return launchViaWrapper(command, appPath: otherAppPath, appName: (otherAppPath as NSString).lastPathComponent)
        }
    }

    private static func launchViaAppleScript(_ command: String) -> String? {
        var error: NSDictionary?
        let script = NSAppleScript(source: appleScript(for: command))
        script?.executeAndReturnError(&error)
        guard error != nil else { return nil }
        // Automation denied (or Terminal scripting failed) → permissionless .command route.
        do {
            let url = try writeWrapper(for: command)
            NSWorkspace.shared.open(url)
            return "Terminal automation unavailable — opened a command file instead"
        } catch {
            return "Could not open Terminal: \(error.localizedDescription)"
        }
    }

    private static func launchViaWrapper(_ command: String, appPath: String, appName: String) -> String? {
        guard FileManager.default.fileExists(atPath: appPath) else {
            let notice = launchViaAppleScript(command)
            return notice ?? "\(appName) not found — used Terminal.app"
        }
        do {
            let url = try writeWrapper(for: command)
            let config = NSWorkspace.OpenConfiguration()
            NSWorkspace.shared.open([url], withApplicationAt: URL(fileURLWithPath: appPath), configuration: config)
            return nil
        } catch {
            return "Could not launch \(appName): \(error.localizedDescription)"
        }
    }
}
```

- [ ] **Step 4:** `swift test --filter TerminalLauncherTests` — PASS. (The `launch` glue is verified manually in Task 12 — it opens real terminals.)
- [ ] **Step 5:** `git add -A && git commit -m "feat: terminal launcher with AppleScript + command-file routes"`

### Task 4: AppSettings

**Files:**
- Create: `Sources/ClausonaGUI/Core/AppSettings.swift`
- Test: `Tests/ClausonaGUITests/AppSettingsTests.swift`

- [ ] **Step 1: Failing tests** (round-trip through an isolated UserDefaults suite):

```swift
import XCTest
@testable import ClausonaGUI

@MainActor
final class AppSettingsTests: XCTestCase {
    private func makeDefaults() -> UserDefaults {
        let name = "clausona-test-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name)!
        defaults.removePersistentDomain(forName: name)
        return defaults
    }

    func testDefaults() {
        let settings = AppSettings(defaults: makeDefaults())
        XCTAssertEqual(settings.terminal, .terminal)
        XCTAssertEqual(settings.refreshMinutes, 5)
        XCTAssertNil(settings.otherTerminalPath)
    }

    func testRoundTrip() {
        let defaults = makeDefaults()
        let settings = AppSettings(defaults: defaults)
        settings.terminal = .warp
        settings.refreshMinutes = 15
        settings.otherTerminalPath = "/Applications/kitty.app"

        let reloaded = AppSettings(defaults: defaults)
        XCTAssertEqual(reloaded.terminal, .warp)
        XCTAssertEqual(reloaded.refreshMinutes, 15)
        XCTAssertEqual(reloaded.otherTerminalPath, "/Applications/kitty.app")
    }

    func testGarbageStoredValueFallsBackToDefault() {
        let defaults = makeDefaults()
        defaults.set("Kitty?", forKey: "terminalChoice")
        defaults.set(99, forKey: "refreshMinutes")
        let settings = AppSettings(defaults: defaults)
        XCTAssertEqual(settings.terminal, .terminal)
        XCTAssertEqual(settings.refreshMinutes, 5)     // not one of 2/5/15
    }
}
```

- [ ] **Step 2:** `swift test --filter AppSettingsTests` — FAIL.

- [ ] **Step 3: Implement**

```swift
import Foundation
import Observation

/// App-level preferences, persisted to UserDefaults. The hotkey is intentionally
/// NOT here — it stays a fixed constant (⌃⌥⌘L) until someone hits a conflict.
@MainActor @Observable
public final class AppSettings {
    public static let allowedRefreshMinutes = [2, 5, 15]

    @ObservationIgnored private let defaults: UserDefaults
    /// Invoked when refreshMinutes changes so AppDelegate can retune the scheduler.
    @ObservationIgnored public var onRefreshIntervalChange: (@MainActor () -> Void)?

    public var terminal: TerminalLauncher.TerminalChoice {
        didSet { defaults.set(terminal.rawValue, forKey: "terminalChoice") }
    }

    public var otherTerminalPath: String? {
        didSet { defaults.set(otherTerminalPath, forKey: "otherTerminalPath") }
    }

    public var refreshMinutes: Int {
        didSet {
            guard Self.allowedRefreshMinutes.contains(refreshMinutes) else {
                refreshMinutes = oldValue
                return
            }
            defaults.set(refreshMinutes, forKey: "refreshMinutes")
            onRefreshIntervalChange?()
        }
    }

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        terminal = defaults.string(forKey: "terminalChoice")
            .flatMap(TerminalLauncher.TerminalChoice.init(rawValue:)) ?? .terminal
        otherTerminalPath = defaults.string(forKey: "otherTerminalPath")
        let stored = defaults.integer(forKey: "refreshMinutes")
        refreshMinutes = Self.allowedRefreshMinutes.contains(stored) ? stored : 5
    }
}
```

- [ ] **Step 4:** `swift test --filter AppSettingsTests` — PASS.
- [ ] **Step 5:** `git add -A && git commit -m "feat: app settings persisted to UserDefaults"`

### Task 5: Debouncer

**Files:**
- Create: `Sources/ClausonaGUI/Core/Debouncer.swift`
- Test: `Tests/ClausonaGUITests/DebouncerTests.swift`

- [ ] **Step 1: Failing tests** (burst → one trailing fire; separate bursts → separate fires):

```swift
import XCTest
@testable import ClausonaGUI

@MainActor
final class DebouncerTests: XCTestCase {
    func testBurstFiresOnce() async throws {
        var fired = 0
        let debouncer = Debouncer(interval: 0.1) { fired += 1 }
        for _ in 0..<5 { debouncer.call() }
        try await Task.sleep(for: .milliseconds(300))
        XCTAssertEqual(fired, 1)
    }

    func testSeparateBurstsFireSeparately() async throws {
        var fired = 0
        let debouncer = Debouncer(interval: 0.05) { fired += 1 }
        debouncer.call()
        try await Task.sleep(for: .milliseconds(150))
        debouncer.call()
        try await Task.sleep(for: .milliseconds(150))
        XCTAssertEqual(fired, 2)
    }
}
```

- [ ] **Step 2:** `swift test --filter DebouncerTests` — FAIL.

- [ ] **Step 3: Implement**

```swift
import Foundation

/// Trailing-edge debounce: the action runs once, `interval` after the last call.
@MainActor
public final class Debouncer {
    private let interval: TimeInterval
    private let action: @MainActor () -> Void
    private var pending: Task<Void, Never>?

    public init(interval: TimeInterval, action: @escaping @MainActor () -> Void) {
        self.interval = interval
        self.action = action
    }

    public func call() {
        pending?.cancel()
        pending = Task { [interval] in
            try? await Task.sleep(for: .seconds(interval))
            guard !Task.isCancelled else { return }
            action()
        }
    }
}
```

- [ ] **Step 4:** `swift test --filter DebouncerTests` — PASS.
- [ ] **Step 5:** `git add -A && git commit -m "feat: trailing-edge debouncer"`

### Task 6: Directory watching (extend FileWatcher test)

**Files:**
- Test: `Tests/ClausonaGUITests/FileWatcherTests.swift` (append — implementation should already support it; this pins the behavior StateWatcher relies on)

- [ ] **Step 1: Append test**

```swift
    func testDirectoryWatchDetectsFileCreation() async throws {
        let dir = NSTemporaryDirectory() + "watchdir-\(UUID().uuidString)"
        try FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
        let changed = expectation(description: "dir change detected")
        changed.assertForOverFulfill = false
        let watcher = FileWatcher(path: dir) { changed.fulfill() }
        watcher.start()
        defer { watcher.stop() }

        try await Task.sleep(for: .milliseconds(100))
        try "{}".write(toFile: dir + "/profiles.json", atomically: true, encoding: .utf8)
        await fulfillment(of: [changed], timeout: 5)
    }
```

- [ ] **Step 2:** `swift test --filter FileWatcherTests` — expected PASS immediately (kqueue directory `.write` covers entry creation; if it FAILS, the eventMask needs `.link` added — fix and re-run).
- [ ] **Step 3:** `git add -A && git commit -m "test: pin directory-watch behavior for StateWatcher"`

### Task 7: AppModel.startFlow

**Files:**
- Modify: `Sources/ClausonaGUI/Core/AppDependencies.swift`, `Sources/ClausonaGUI/Core/AppModel.swift`
- Test: `Tests/ClausonaGUITests/AppModelTests.swift` (append)

- [ ] **Step 1: Failing tests**

```swift
    func testStartFlowLaunchesAndSurfacesNotice() async {
        nonisolated(unsafe) var launched: [ClausonaFlow] = []
        var d = deps(profiles: file())
        d.launchFlow = { flow in
            launched.append(flow)
            return flow == .initialSetup ? "fallback notice" : nil
        }
        let model = AppModel(deps: d)
        model.startFlow(.add(name: "neu"))
        XCTAssertEqual(launched, [.add(name: "neu")])
        XCTAssertNil(model.toast)
        model.startFlow(.initialSetup)
        XCTAssertEqual(model.toast, "fallback notice")
    }

    func testStartFlowNoopWithoutLauncher() {
        let model = AppModel(deps: deps())   // launchFlow nil (CLI missing)
        model.startFlow(.login(name: "x"))
        XCTAssertNil(model.toast)
        XCTAssertFalse(model.canStartFlows)
    }
```

- [ ] **Step 2:** `swift test --filter AppModelTests` — FAIL (`launchFlow` undefined).

- [ ] **Step 3: Implement.**

`AppDependencies`: add stored property + init param (default nil, after `cli`):

```swift
    /// nil when the clausona binary is missing — handoff entry points hide.
    public var launchFlow: (@MainActor (ClausonaFlow) -> String?)?
```

(add `launchFlow: (@MainActor (ClausonaFlow) -> String?)? = nil` to the init parameter list and assign it; `AppDependencies` stays Sendable because `@MainActor` closures are Sendable.)

In `live()`, after locating the CLI, build the launcher closure (settings injected by AppDelegate via this factory — change `live()` signature to `live(settings: AppSettings? = nil)` and pass the binary path):

```swift
    public static func live(settings: AppSettings? = nil) -> AppDependencies {
        let store = ProfileStore()
        let provider = TokenProvider.live()
        let fetcher = UsageFetcher.live
        let binaryPath = ClausonaCLI.locate()
        let cli = binaryPath.map { path in
            let cli = ClausonaCLI(binaryPath: path)
            return CLIActions(use: { await cli.use(profile: $0) },
                              repair: { await cli.repair(profile: $0) },
                              doctor: { await cli.doctor() })
        }
        let launchFlow: (@MainActor (ClausonaFlow) -> String?)? = binaryPath.map { path in
            { flow in
                TerminalLauncher.launch(flow.command(binaryPath: path),
                                        using: settings?.terminal ?? .terminal,
                                        otherAppPath: settings?.otherTerminalPath)
            }
        }
        return AppDependencies(
            loadProfiles: { store.load() },
            token: { await provider.token(forConfigDir: $0.configDir) },
            fetchUsage: { await fetcher.fetch(token: $0) },
            cli: cli,
            launchFlow: launchFlow)
    }
```

`AppModel`: add

```swift
    public var canStartFlows: Bool { deps.launchFlow != nil }

    public func startFlow(_ flow: ClausonaFlow) {
        guard let launch = deps.launchFlow else { return }
        if let notice = launch(flow) {
            toast = notice
        }
    }
```

- [ ] **Step 4:** `swift test` — full suite PASS.
- [ ] **Step 5:** `git add -A && git commit -m "feat: terminal flow handoff through AppModel"`

### Task 8: Scheduler interval + StateWatcher wiring

**Files:**
- Modify: `Sources/ClausonaGUI/Core/RefreshScheduler.swift`, `Sources/ClausonaGUI/App/AppDelegate.swift`

- [ ] **Step 1: RefreshScheduler** — make the usage interval mutable:

```swift
    public func updateUsageInterval(_ interval: TimeInterval) {
        usageInterval = interval
        if !timers.isEmpty { start() }   // restart with the new cadence
    }
```

(change `private let usageInterval` to `private var usageInterval`.)

- [ ] **Step 2: AppDelegate** — create settings, pass to deps, watch `~/.clausona`:

Add properties:

```swift
    private var settings: AppSettings?
    private var stateWatcher: FileWatcher?
    private var stateDebouncer: Debouncer?
```

In `applicationDidFinishLaunching`, replace `let model = AppModel(deps: .live())` with:

```swift
        let settings = AppSettings()
        self.settings = settings
        let model = AppModel(deps: .live(settings: settings))
```

After scheduler setup, add:

```swift
        settings.onRefreshIntervalChange = { [weak self, weak settings] in
            guard let settings else { return }
            self?.scheduler?.updateUsageInterval(TimeInterval(settings.refreshMinutes * 60))
        }
        scheduler.updateUsageInterval(TimeInterval(settings.refreshMinutes * 60))

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
        let watcher = FileWatcher(path: clausonaHome) { [weak debouncer, weak self] in
            debouncer?.call()
            self?.stateWatcher?.startIfNeeded()
        }
        stateWatcher = watcher
        watcher.start()
```

- [ ] **Step 3: FileWatcher.startIfNeeded** — tiny addition so a missing `~/.clausona` (pre-init machine) gets picked up later; add to `FileWatcher`:

```swift
    public var isActive: Bool { source != nil }

    /// Re-arm only if not currently watching (e.g. the directory appeared after launch).
    public func startIfNeeded() {
        if source == nil { start() }
    }
```

Also call `stateWatcher?.startIfNeeded()` inside the scheduler's usage tick closure in AppDelegate (covers the pre-init case via polling):

```swift
        let scheduler = RefreshScheduler(
            onUsageTick: { [weak self] in
                self?.stateWatcher?.startIfNeeded()
                Task { await model.refreshUsage() }
            },
            onHealthTick: { Task { await model.refreshHealth() } })
```

- [ ] **Step 4:** `swift build && swift test` — clean, all pass.
- [ ] **Step 5:** `git add -A && git commit -m "feat: state watcher + configurable refresh interval wiring"`

### Task 9: Settings window

**Files:**
- Create: `Sources/ClausonaGUI/Settings/SettingsWindowController.swift`, `Sources/ClausonaGUI/Settings/SettingsView.swift`
- Modify: `Sources/ClausonaGUI/App/AppDelegate.swift` (controller + open hook), `Sources/ClausonaGUI/Core/AppModel.swift` (open hook)

- [ ] **Step 1: AppModel hook** (mirrors onOpenMainWindow):

```swift
    @ObservationIgnored public var onOpenSettings: (@MainActor () -> Void)?

    public func openSettings() {
        onOpenSettings?()
    }
```

- [ ] **Step 2: SettingsWindowController**

```swift
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
```

- [ ] **Step 3: SettingsView**

```swift
import SwiftUI

struct SettingsView: View {
    @Bindable var settings: AppSettings
    let model: AppModel

    init(settings: AppSettings, model: AppModel) {
        self._settings = Bindable(settings)
        self.model = model
    }

    var body: some View {
        Form {
            Section("Terminal for clausona flows") {
                Picker("Terminal", selection: $settings.terminal) {
                    ForEach(TerminalLauncher.TerminalChoice.allCases, id: \.self) { choice in
                        Text(choice.rawValue).tag(choice)
                    }
                }
                .labelsHidden()
                if settings.terminal == .other {
                    LabeledContent("App") {
                        HStack {
                            Text(settings.otherTerminalPath.map { ($0 as NSString).lastPathComponent } ?? "None chosen")
                                .foregroundStyle(.secondary)
                            Button("Choose…") { chooseApp() }
                        }
                    }
                }
                if let warning = terminalWarning {
                    Label(warning, systemImage: "exclamationmark.triangle")
                        .font(.caption)
                        .foregroundStyle(.orange)
                }
            }

            Section("Refresh") {
                Picker("Background refresh", selection: $settings.refreshMinutes) {
                    ForEach(AppSettings.allowedRefreshMinutes, id: \.self) { minutes in
                        Text("Every \(minutes) minutes").tag(minutes)
                    }
                }
            }

            Section("General") {
                Toggle("Launch at Login", isOn: Binding(
                    get: { model.launchAtLoginEnabled },
                    set: { model.setLaunchAtLogin($0) }))
                LabeledContent("Hotkey", value: "⌃⌥⌘L (fixed)")
            }
        }
        .formStyle(.grouped)
        .frame(width: 440)
        .fixedSize(horizontal: false, vertical: true)
        .onAppear { model.refreshLaunchAtLogin() }
    }

    private var terminalWarning: String? {
        let path: String? = switch settings.terminal {
        case .terminal: nil
        case .warp: "/Applications/Warp.app"
        case .iterm: "/Applications/iTerm.app"
        case .other: settings.otherTerminalPath ?? "/nonexistent"
        }
        guard let path, !FileManager.default.fileExists(atPath: path) else { return nil }
        return "App not found — Terminal.app will be used instead"
    }

    private func chooseApp() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.application]
        panel.directoryURL = URL(fileURLWithPath: "/Applications")
        if panel.runModal() == .OK, let url = panel.url {
            settings.otherTerminalPath = url.path
        }
    }
}
```

- [ ] **Step 4: AppDelegate wiring** — add `private var settingsController: SettingsWindowController?`; after window controller creation:

```swift
        let settingsController = SettingsWindowController(settings: settings, model: model)
        self.settingsController = settingsController
        model.onOpenSettings = { [weak controller, weak settingsController] in
            controller?.close()
            settingsController?.show()
        }
```

- [ ] **Step 5:** `swift build && swift test` — clean. Commit: `git add -A && git commit -m "feat: settings window (terminal, refresh interval, launch at login)"`

### Task 10: Popover entry points (Add sheet, gear, Login button, init action)

**Files:**
- Create: `Sources/ClausonaGUI/UI/AddProfileSheet.swift`
- Modify: `Sources/ClausonaGUI/UI/FooterView.swift`, `UI/ProfileRowView.swift`, `UI/EmptyStateView.swift`, `UI/PopoverView.swift`

- [ ] **Step 1: AddProfileSheet**

```swift
import SwiftUI

struct AddProfileSheet: View {
    let model: AppModel
    @Binding var isPresented: Bool
    @State private var name = ""

    private var isValid: Bool { ProfileName.isValid(name) }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Add profile")
                .font(.headline)
            TextField("profile-name", text: $name)
                .textFieldStyle(.roundedBorder)
                .frame(width: 220)
                .onSubmit { submit() }
            Text("Lowercase letters, digits and dashes. The setup continues in your terminal.")
                .font(.caption)
                .foregroundStyle(.secondary)
            if !name.isEmpty && !isValid {
                Text("Invalid name — use a-z, 0-9 and dashes only.")
                    .font(.caption)
                    .foregroundStyle(.red)
            }
            HStack {
                Spacer()
                Button("Cancel") { isPresented = false }
                    .keyboardShortcut(.cancelAction)
                Button("Add") { submit() }
                    .keyboardShortcut(.defaultAction)
                    .disabled(!isValid)
            }
        }
        .padding(16)
    }

    private func submit() {
        guard isValid else { return }
        isPresented = false
        model.startFlow(.add(name: name))
    }
}
```

- [ ] **Step 2: FooterView** — replace the second HStack (toggle row) with:

```swift
            HStack {
                Toggle("Launch at Login", isOn: Binding(
                    get: { model.launchAtLoginEnabled },
                    set: { model.setLaunchAtLogin($0) }))
                    .toggleStyle(.checkbox)
                    .font(.system(size: 11))
                Button("Open Clausona…") { model.openMainWindow() }
                    .controlSize(.small)
                Spacer()
                if model.canStartFlows {
                    Button {
                        showingAddSheet = true
                    } label: {
                        Image(systemName: "plus")
                    }
                    .controlSize(.small)
                    .help("Add profile (continues in your terminal)")
                }
                Button {
                    model.openSettings()
                } label: {
                    Image(systemName: "gearshape")
                }
                .controlSize(.small)
                .keyboardShortcut(",")
                .help("Settings")
                Button("Quit") { NSApp.terminate(nil) }
                    .controlSize(.small)
                    .keyboardShortcut("q")
            }
            .sheet(isPresented: $showingAddSheet) {
                AddProfileSheet(model: model, isPresented: $showingAddSheet)
            }
```

and add `@State private var showingAddSheet = false` to the struct.

- [ ] **Step 3: ProfileRowView** — Login button for login-needed rows. In `actionButton`, extend the conditions:

```swift
    @ViewBuilder private var actionButton: some View {
        if hovering && model.cliAvailable {
            if case .issues = snapshot.health, !snapshot.isRepairing {
                Button("Repair") {
                    Task { await model.repair(snapshot.name) }
                }
                .controlSize(.small)
                .help("Runs `clausona repair \(snapshot.name)`")
            } else if needsLogin && model.canStartFlows {
                Button("Login") {
                    model.startFlow(.login(name: snapshot.name))
                }
                .controlSize(.small)
                .help("Re-authenticate in your terminal")
            } else if !snapshot.isActive {
                Button("Use") {
                    Task { await model.switchProfile(snapshot.name) }
                }
                .controlSize(.small)
                .help("Runs `clausona use \(snapshot.name)` — affects new terminals only")
            }
        }
    }

    private var needsLogin: Bool {
        if case .expired = snapshot.credential { return true }
        if case .missing = snapshot.credential { return true }
        return false
    }
```

- [ ] **Step 4: EmptyStateView + PopoverView** — give the empty state an optional action:

```swift
struct EmptyStateView: View {
    let title: String
    let hint: String
    var actionTitle: String? = nil
    var action: (() -> Void)? = nil

    var body: some View {
        VStack(spacing: 6) {
            Image(systemName: "person.crop.circle.badge.questionmark")
                .font(.system(size: 28))
                .foregroundStyle(.tertiary)
            Text(title)
                .font(.system(size: 12, weight: .medium))
            Text(LocalizedStringKey(hint))
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            if let actionTitle, let action {
                Button(actionTitle, action: action)
                    .controlSize(.small)
                    .padding(.top, 4)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 24)
        .padding(.horizontal, 16)
    }
}
```

In `PopoverView`, the `.notSetUp` branch becomes:

```swift
            case .notSetUp:
                EmptyStateView(
                    title: "clausona is not set up",
                    hint: model.canStartFlows
                        ? "Initial setup discovers your Claude accounts in a terminal."
                        : "Run `clausona init` in a terminal to get started.",
                    actionTitle: model.canStartFlows ? "Set up clausona…" : nil,
                    action: model.canStartFlows ? { model.startFlow(.initialSetup) } : nil)
```

- [ ] **Step 5:** `swift build && swift test` — clean. Commit: `git add -A && git commit -m "feat: popover handoff entry points (add, login, init, settings)"`

### Task 11: Main window entry points (profile actions + sidebar add + toolbar settings)

**Files:**
- Modify: `Sources/ClausonaGUI/MainWindow/Profiles/ProfileDetailView.swift`, `MainWindow/MainWindowView.swift`

- [ ] **Step 1: ProfileDetailView** — add an Actions section after "Usage":

```swift
            if model.canStartFlows {
                Section("Actions") {
                    LabeledContent("Re-authenticate") {
                        Button("clausona login \(snapshot.name)") {
                            model.startFlow(.login(name: snapshot.name))
                        }
                    }
                    LabeledContent("Configure") {
                        Button("clausona config \(snapshot.name)") {
                            model.startFlow(.config(name: snapshot.name))
                        }
                    }
                    LabeledContent("Remove") {
                        Button(role: .destructive) {
                            model.startFlow(.remove(name: snapshot.name))
                        } label: {
                            Text("clausona remove \(snapshot.name)…")
                        }
                        .help("Opens clausona's removal flow in your terminal — confirmation happens there")
                    }
                }
            }
```

- [ ] **Step 2: MainWindowView** — add below the `List` (still inside the sidebar column builder):

```swift
            .safeAreaInset(edge: .bottom) {
                if model.canStartFlows {
                    HStack {
                        Button {
                            showingAddSheet = true
                        } label: {
                            Label("Add Profile", systemImage: "plus")
                                .font(.system(size: 12))
                        }
                        .buttonStyle(.borderless)
                        Spacer()
                    }
                    .padding(8)
                    .sheet(isPresented: $showingAddSheet) {
                        AddProfileSheet(model: model, isPresented: $showingAddSheet)
                    }
                }
            }
```

with `@State private var showingAddSheet = false` on the struct, and add a toolbar settings button on the detail side:

```swift
        .toolbar {
            Button {
                model.openSettings()
            } label: {
                Label("Settings", systemImage: "gearshape")
            }
            .keyboardShortcut(",")
        }
```

(attach to the `NavigationSplitView`.)

- [ ] **Step 3:** `swift build && swift test` — clean. Commit: `git add -A && git commit -m "feat: main window handoff entry points + settings access"`

### Task 12: Install + verification

- [ ] **Step 1:** `swift test` fresh (all pass) + `make install`.
- [ ] **Step 2: Handoff E2E (Terminal.app default):** popover ＋ → type a test name (`zz-test`) → Add → Terminal.app opens running `clausona add zz-test`. **Abandon the flow (Ctrl-C)** — verify GUI unchanged (no pending state). First run may show the one-time Automation prompt.
- [ ] **Step 3: StateWatcher E2E without GUI:** in a terminal, run a no-op state change (e.g. `clausona use work && clausona use personal`) — popover ▸ moves within ~2 s without manual refresh (criterion 2; `use` rewrites profiles.json).
- [ ] **Step 4: Settings:** switch terminal to Warp → trigger Login on an expired profile → Warp opens with the login flow (abandon it). Set refresh to 2 min → scheduler restarts (verify by log or just settings persistence). Toggle Launch at Login from settings; confirm popover checkbox mirrors it.
- [ ] **Step 5: Fallback paths:** select Other with a nonexistent app → warning shows in settings, launch falls back to Terminal.app with a toast notice.
- [ ] **Step 6: Coverage check (criterion 1):** every `clausona help` command reachable: run/uninstall/shell-init/version CLI-only (intentional); use/repair/doctor/list/usage/current native; add/login/remove/init/config via handoff buttons.
- [ ] **Step 7:** screenshots; final commit.

---

## Self-review notes

- Spec coverage: TerminalLauncher (AppleScript default + .command alternative + fallbacks) → T3; entry-point table (＋ popover+sidebar, login row+detail, remove detail-only, init empty-state, config detail) → T10/T11; result detection (profiles.json watch, no pending state, doctor one-shot) → T6/T8; settings pane (terminal/interval/launch-at-login/fixed-hotkey note) → T4/T9; error table (AppleScript denied → .command + notice; terminal missing → fallback + settings warning; abandoned flow → nothing; profiles.json deleted → empty state, already handled by Phase 1 `load() == nil`) → T3/T9; unit tests listed in spec (name validation, wrapper escaping, settings round-trip, debounce) → T1/T3/T4/T5.
- Type consistency: `TerminalLauncher.TerminalChoice` used by `AppSettings` (T4) and `SettingsView` (T9); `ClausonaFlow` (T2) used by `launchFlow` (T7) and all UI tasks; `model.canStartFlows` (T7) gates T10/T11 UI.
- Deliberate choices: remove confirmation lives in clausona's TUI only (spec-mandated); credentials watching is NOT added (spec: keychain has no watch API; next usage refresh re-checks).
