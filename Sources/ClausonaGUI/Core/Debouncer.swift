import Foundation

/// Trailing-edge debounce: the action runs once, `interval` after the last call.
@MainActor
public final class Debouncer {
    private let interval: TimeInterval
    private let action: @MainActor () -> Void
    private var pending: Task<Void, Never>?

    public init(interval: TimeInterval, action: @escaping @MainActor () -> Void) {
        self.interval = interval
        self.action = action
    }

    public func call() {
        pending?.cancel()
        pending = Task { [interval] in
            try? await Task.sleep(for: .seconds(interval))
            guard !Task.isCancelled else { return }
            action()
        }
    }
}
