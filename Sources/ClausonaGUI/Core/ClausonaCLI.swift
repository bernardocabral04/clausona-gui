import Foundation

public struct CLIError: Error, Equatable, Sendable {
    public let message: String

    public init(message: String) { self.message = message }
}

/// Mutations go through the clausona CLI only — never reimplemented here.
public struct ClausonaCLI: Sendable {
    public let binaryPath: String

    public init(binaryPath: String) { self.binaryPath = binaryPath }

    /// ~/.local/bin first (GUI apps don't inherit the shell PATH), then PATH,
    /// then the common Homebrew locations.
    public static func locate(environment: [String: String] = ProcessInfo.processInfo.environment,
                              home: String = NSHomeDirectory(),
                              fileExists: (String) -> Bool = { FileManager.default.isExecutableFile(atPath: $0) }) -> String? {
        var candidates = [home + "/.local/bin/clausona"]
        candidates += (environment["PATH"] ?? "").split(separator: ":").map { String($0) + "/clausona" }
        candidates += ["/opt/homebrew/bin/clausona", "/usr/local/bin/clausona"]
        return candidates.first(where: fileExists)
    }

    public func use(profile: String) async -> Result<Void, CLIError> {
        await run(["use", profile])
    }

    public func repair(profile: String) async -> Result<Void, CLIError> {
        await run(["repair", profile])
    }

    /// Returns raw stdout regardless of exit status — the parser is tolerant.
    public func doctor() async -> String? {
        await Subprocess.run(binaryPath, ["doctor"])?.stdout
    }

    private func run(_ arguments: [String]) async -> Result<Void, CLIError> {
        guard let result = await Subprocess.run(binaryPath, arguments) else {
            return .failure(CLIError(message: "could not launch clausona"))
        }
        guard result.exitCode == 0 else {
            let firstLine = result.stderr.split(separator: "\n").first.map(String.init)
                ?? result.stdout.split(separator: "\n").first.map(String.init)
                ?? "clausona exited with status \(result.exitCode)"
            return .failure(CLIError(message: firstLine))
        }
        return .success(())
    }
}
