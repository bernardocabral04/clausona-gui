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
