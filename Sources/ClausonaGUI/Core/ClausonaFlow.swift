/// A clausona lifecycle flow handed off to a terminal. Names must already be
/// ProfileName-valid (enforced at the UI boundary), so they need no quoting.
public enum ClausonaFlow: Equatable, Sendable {
    case add(name: String)
    case login(name: String)
    case remove(name: String)
    case config(name: String)
    case initialSetup

    public func command(binaryPath: String) -> String {
        let bin = "'" + binaryPath + "'"
        switch self {
        case .add(let name): return "\(bin) add \(name)"
        case .login(let name): return "\(bin) login \(name)"
        case .remove(let name): return "\(bin) remove \(name)"
        case .config(let name): return "\(bin) config \(name)"
        case .initialSetup: return "\(bin) init"
        }
    }
}
