import Foundation

public enum Staleness {
    /// Stale once two consecutive poll cycles have been missed.
    /// nil lastSuccess = still loading for the first time — not "stale".
    public static func isStale(lastSuccess: Date?, now: Date, pollInterval: TimeInterval) -> Bool {
        guard let lastSuccess else { return false }
        return now.timeIntervalSince(lastSuccess) >= pollInterval * 2
    }
}
