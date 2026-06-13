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
