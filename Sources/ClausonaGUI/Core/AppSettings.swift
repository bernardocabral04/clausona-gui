import Foundation
import Observation

/// App-level preferences, persisted to UserDefaults. The hotkey is intentionally
/// NOT here — it stays a fixed constant (⌃⌥⌘L) until someone hits a conflict.
@MainActor @Observable
public final class AppSettings {
    @ObservationIgnored private let defaults: UserDefaults

    public var terminal: TerminalLauncher.TerminalChoice {
        didSet { defaults.set(terminal.rawValue, forKey: "terminalChoice") }
    }

    public var otherTerminalPath: String? {
        didSet { defaults.set(otherTerminalPath, forKey: "otherTerminalPath") }
    }

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        terminal = defaults.string(forKey: "terminalChoice")
            .flatMap(TerminalLauncher.TerminalChoice.init(rawValue:)) ?? .terminal
        otherTerminalPath = defaults.string(forKey: "otherTerminalPath")
    }
}
