import Foundation

@MainActor
public final class RefreshScheduler {
    private let usageInterval: TimeInterval
    private let healthInterval: TimeInterval
    private let onUsageTick: @MainActor () -> Void
    private let onHealthTick: @MainActor () -> Void
    private var timers: [Timer] = []

    public init(usageInterval: TimeInterval = 300,
                healthInterval: TimeInterval = 1800,
                onUsageTick: @escaping @MainActor () -> Void,
                onHealthTick: @escaping @MainActor () -> Void) {
        self.usageInterval = usageInterval
        self.healthInterval = healthInterval
        self.onUsageTick = onUsageTick
        self.onHealthTick = onHealthTick
    }

    public func start() {
        stop()
        let usage = Timer.scheduledTimer(withTimeInterval: usageInterval, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.onUsageTick() }
        }
        let health = Timer.scheduledTimer(withTimeInterval: healthInterval, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.onHealthTick() }
        }
        timers = [usage, health]
    }

    public func stop() {
        timers.forEach { $0.invalidate() }
        timers = []
    }
}
