import Foundation

/// Parses `clausona doctor` output. Tolerant by design: anything it can't
/// match is ignored, and profiles absent from the result map to .unknown.
public enum DoctorParser {
    public static func stripANSI(_ string: String) -> String {
        string.replacingOccurrences(of: "\u{001B}\\[[0-9;]*[A-Za-z]",
                                    with: "", options: .regularExpression)
    }

    public static func parse(_ output: String) -> [String: HealthStatus] {
        var result: [String: HealthStatus] = [:]
        var currentProfile: String?
        var issues: [String] = []
        var collectingIssues = false

        func flushIssues() {
            if let name = currentProfile, collectingIssues {
                result[name] = .issues(issues)
            }
            issues = []
            collectingIssues = false
        }

        let header = /^\s*(\S+) \((.*)\)\s*$/
        for rawLine in stripANSI(output).split(separator: "\n", omittingEmptySubsequences: false) {
            let trimmed = rawLine.trimmingCharacters(in: .whitespaces)
            if trimmed.hasPrefix("├─") || trimmed.hasPrefix("╰─") {
                if collectingIssues {
                    issues.append(String(trimmed.dropFirst(2)).trimmingCharacters(in: .whitespaces))
                }
            } else if trimmed.hasPrefix("✔") {
                if let name = currentProfile { result[name] = .healthy }
                currentProfile = nil
            } else if trimmed.hasPrefix("✘") {
                collectingIssues = currentProfile != nil
            } else if let match = String(rawLine).wholeMatch(of: header) {
                flushIssues()
                currentProfile = String(match.1)
            }
            // anything else (blank lines, "Run clausona repair … to fix") is ignored
        }
        flushIssues()
        return result
    }
}
