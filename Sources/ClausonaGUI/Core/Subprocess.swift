import Foundation

public struct SubprocessResult: Equatable, Sendable {
    public let exitCode: Int32
    public let stdout: String
    public let stderr: String

    public init(exitCode: Int32, stdout: String, stderr: String) {
        self.exitCode = exitCode
        self.stdout = stdout
        self.stderr = stderr
    }
}

public enum Subprocess {
    /// Runs a process and captures output. Returns nil if the executable can't launch.
    /// All callers here produce small outputs (doctor is ~2 KB), well under the pipe
    /// buffer, so reading after termination cannot deadlock.
    public static func run(_ executable: String, _ arguments: [String]) async -> SubprocessResult? {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments
        nonisolated(unsafe) let outPipe = Pipe()
        nonisolated(unsafe) let errPipe = Pipe()
        process.standardOutput = outPipe
        process.standardError = errPipe
        process.standardInput = FileHandle.nullDevice

        return await withCheckedContinuation { continuation in
            process.terminationHandler = { proc in
                let out = (try? outPipe.fileHandleForReading.readToEnd()) ?? Data()
                let err = (try? errPipe.fileHandleForReading.readToEnd()) ?? Data()
                continuation.resume(returning: SubprocessResult(
                    exitCode: proc.terminationStatus,
                    stdout: String(decoding: out, as: UTF8.self),
                    stderr: String(decoding: err, as: UTF8.self)))
            }
            do {
                try process.run()
            } catch {
                process.terminationHandler = nil
                continuation.resume(returning: nil)
            }
        }
    }
}
