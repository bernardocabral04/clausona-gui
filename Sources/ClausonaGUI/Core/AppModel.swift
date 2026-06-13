import Foundation
import Observation

@MainActor @Observable
public final class AppModel {
    public enum SetupState: Equatable {
        case loading, notSetUp, ready
    }

    public private(set) var setupState: SetupState = .loading
    public private(set) var snapshots: [ProfileSnapshot] = []
    public private(set) var profilesFile: ProfilesFile?
    public private(set) var activeProfile: String?
    public private(set) var lastUpdated: Date?
    public private(set) var isRefreshing = false
    public private(set) var launchAtLoginEnabled = false
    public private(set) var doctorError: String?
    public var toast: String?

    public var totalIssueCount: Int {
        snapshots.reduce(0) { count, snapshot in
            if case .issues(let issues) = snapshot.health { return count + issues.count }
            return count
        }
    }

    public let cliAvailable: Bool
    public static let pollInterval: TimeInterval = 300

    private let deps: AppDependencies

    public init(deps: AppDependencies) {
        self.deps = deps
        self.cliAvailable = deps.cli != nil
    }

    /// Set by AppDelegate; invoked from the popover footer.
    @ObservationIgnored public var onOpenMainWindow: (@MainActor () -> Void)?

    public func openMainWindow() {
        onOpenMainWindow?()
    }

    @ObservationIgnored public var onOpenSettings: (@MainActor () -> Void)?

    public func openSettings() {
        onOpenSettings?()
    }

    // MARK: - Terminal handoffs

    public var canStartFlows: Bool { deps.launchFlow != nil }

    public func startFlow(_ flow: ClausonaFlow) {
        guard let launch = deps.launchFlow else { return }
        if let notice = launch(flow) {
            toast = notice
        }
    }

    public var isStale: Bool {
        Staleness.isStale(lastSuccess: lastUpdated, now: deps.now(), pollInterval: Self.pollInterval)
    }

    public func popoverDidOpen() {
        refreshLaunchAtLogin()
        Task { await refreshUsageIfStale() }
    }

    /// On-demand refresh: usage is only fetched when someone is looking and the
    /// cache is older than `maxAge` (no background polling — it fed rate limits
    /// for data nothing consumed). The Refresh button still forces via refreshUsage().
    public func refreshUsageIfStale(maxAge: TimeInterval = 60) async {
        if let lastUpdated, deps.now().timeIntervalSince(lastUpdated) < maxAge { return }
        await refreshUsage()
    }

    // MARK: - Usage

    private enum FetchOutcome: Sendable {
        case ok(UsageReport)
        case failed(String)
    }

    public func refreshUsage() async {
        if isRefreshing { return }
        guard let file = deps.loadProfiles() else {
            setupState = .notSetUp
            snapshots = []
            return
        }
        setupState = .ready
        mergeProfiles(file)
        isRefreshing = true
        defer { isRefreshing = false }

        let deps = self.deps
        let outcomes = await withTaskGroup(of: (String, FetchOutcome, CredentialStatus).self,
                                           returning: [String: (FetchOutcome, CredentialStatus)].self) { group in
            for profile in file.profiles {
                group.addTask {
                    switch await deps.token(profile) {
                    case .missing:
                        return (profile.name, .failed("no credentials found"), .missing)
                    case .expired:
                        return (profile.name, .failed("login needed — clausona login \(profile.name)"), .expired)
                    case .ok(let token):
                        let credential = CredentialStatus.valid(until: token.expiresAt)
                        switch await deps.fetchUsage(token.accessToken) {
                        case .success(let report): return (profile.name, .ok(report), credential)
                        case .failure(let error): return (profile.name, .failed(error.message), credential)
                        }
                    }
                }
            }
            var collected: [String: (FetchOutcome, CredentialStatus)] = [:]
            for await (name, outcome, credential) in group { collected[name] = (outcome, credential) }
            return collected
        }

        var anySuccess = false
        for index in snapshots.indices {
            guard let (outcome, credential) = outcomes[snapshots[index].name] else { continue }
            snapshots[index].credential = credential
            switch outcome {
            case .ok(let report):
                snapshots[index].usage = .ok(report)
                anySuccess = true
            case .failed(let message):
                snapshots[index].usage = .error(message: message,
                                                lastGood: snapshots[index].usage.lastGoodReport)
            }
        }
        if anySuccess { lastUpdated = deps.now() }
    }

    private func mergeProfiles(_ file: ProfilesFile) {
        profilesFile = file
        activeProfile = file.activeProfile
        let existing = Dictionary(uniqueKeysWithValues: snapshots.map { ($0.name, $0) })
        snapshots = file.profiles.map { profile in
            var snapshot = existing[profile.name] ?? ProfileSnapshot(
                name: profile.name, email: profile.email, isActive: false,
                usage: .loading, health: .unknown, isRepairing: false)
            snapshot.isActive = profile.name == file.activeProfile
            return snapshot
        }
    }

    // MARK: - Health

    public func refreshHealth() async {
        guard let cli = deps.cli else { return }
        switch await cli.doctor() {
        case .success(let output):
            doctorError = nil
            let statuses = DoctorParser.parse(output)
            for index in snapshots.indices {
                snapshots[index].health = statuses[snapshots[index].name] ?? .unknown
            }
        case .failure(let error):
            doctorError = error.message   // keep last known health states
        }
    }

    // MARK: - Actions

    public func switchProfile(_ name: String) async {
        guard let cli = deps.cli else { return }
        let previous = activeProfile
        setActive(name)
        if case .failure(let error) = await cli.use(name) {
            setActive(previous)
            toast = error.message
        }
    }

    public func repair(_ name: String) async {
        guard let cli = deps.cli, let index = snapshots.firstIndex(where: { $0.name == name }) else { return }
        snapshots[index].isRepairing = true
        if case .failure(let error) = await cli.repair(name) {
            toast = error.message
        }
        await refreshHealth()
        if let index = snapshots.firstIndex(where: { $0.name == name }) {
            snapshots[index].isRepairing = false
        }
    }

    private func setActive(_ name: String?) {
        activeProfile = name
        for index in snapshots.indices {
            snapshots[index].isActive = snapshots[index].name == name
        }
    }

    // MARK: - Launch at login

    public func refreshLaunchAtLogin() {
        launchAtLoginEnabled = deps.launchAtLoginStatus()
    }

    public func setLaunchAtLogin(_ enabled: Bool) {
        do {
            try deps.setLaunchAtLogin(enabled)
            launchAtLoginEnabled = enabled
        } catch {
            toast = "Launch at Login failed: \(error.localizedDescription)"
        }
    }
}
