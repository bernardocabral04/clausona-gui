import Foundation

/// Watches one file via DispatchSource. Atomic replaces (write-to-temp + rename,
/// which is how clausona rewrites usage.json) surface as .rename/.delete on the
/// old inode — on those we close and re-arm on the new file at the same path.
@MainActor
public final class FileWatcher {
    private let path: String
    private let onChange: @MainActor () -> Void
    private var source: DispatchSourceFileSystemObject?

    public init(path: String, onChange: @escaping @MainActor () -> Void) {
        self.path = path
        self.onChange = onChange
    }

    public func start() {
        stop()
        let fd = open(path, O_EVTONLY)
        guard fd >= 0 else { return }   // file missing: caller may retry via start() later
        let source = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: fd,
            eventMask: [.write, .extend, .rename, .delete],
            queue: .main)
        source.setEventHandler { [weak self] in
            let event = source.data
            MainActor.assumeIsolated {
                guard let self else { return }
                self.onChange()
                if event.contains(.rename) || event.contains(.delete) {
                    self.start()   // re-arm on the replacement file
                }
            }
        }
        source.setCancelHandler { close(fd) }
        source.resume()
        self.source = source
    }

    public func stop() {
        source?.cancel()
        source = nil
    }

    public var isActive: Bool { source != nil }

    /// Re-arm only if not currently watching (e.g. the directory appeared after launch).
    public func startIfNeeded() {
        if source == nil { start() }
    }
}
