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

    /// Success carries raw stdout (doctor exits non-zero when issues exist — that's
    /// still a successful run). Failure = couldn't launch, or produced no report.
    public func doctor() async -> Result<String, CLIError> {
        guard let result = await Subprocess.run(binaryPath, ["doctor"]) else {
            return .failure(CLIError(message: "could not launch clausona"))
        }
        if result.stdout.isEmpty && result.exitCode != 0 {
            let stderr = result.stderr.trimmingCharacters(in: .whitespacesAndNewlines)
            return .failure(CLIError(message: stderr.isEmpty ? "clausona doctor exited with status \(result.exitCode)" : stderr))
        }
        return .success(result.stdout)
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
