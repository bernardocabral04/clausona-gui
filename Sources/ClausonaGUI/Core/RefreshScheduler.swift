import Foundation

/// Periodic background work. Only health checks run on a timer (local
/// `clausona doctor`, cheap); usage is fetched on demand when a popover or
/// window opens — see AppModel.refreshUsageIfStale.
@MainActor
public final class RefreshScheduler {
    private let healthInterval: TimeInterval
    private let onHealthTick: @MainActor () -> Void
    private var timer: Timer?

    public init(healthInterval: TimeInterval = 1800,
                onHealthTick: @escaping @MainActor () -> Void) {
        self.healthInterval = healthInterval
        self.onHealthTick = onHealthTick
    }

    public func start() {
        stop()
        timer = Timer.scheduledTimer(withTimeInterval: healthInterval, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.onHealthTick() }
        }
    }

    public func stop() {
        timer?.invalidate()
        timer = nil
    }
}
