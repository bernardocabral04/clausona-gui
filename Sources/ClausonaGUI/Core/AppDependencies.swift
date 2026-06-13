import Foundation
import ServiceManagement

public struct CLIActions: Sendable {
    public var use: @Sendable (String) async -> Result<Void, CLIError>
    public var repair: @Sendable (String) async -> Result<Void, CLIError>
    public var doctor: @Sendable () async -> Result<String, CLIError>

    public init(use: @escaping @Sendable (String) async -> Result<Void, CLIError>,
                repair: @escaping @Sendable (String) async -> Result<Void, CLIError>,
                doctor: @escaping @Sendable () async -> Result<String, CLIError>) {
        self.use = use
        self.repair = repair
        self.doctor = doctor
    }
}

public struct AppDependencies: Sendable {
    public var loadProfiles: @Sendable () -> ProfilesFile?
    public var token: @Sendable (Profile) async -> TokenResult
    public var fetchUsage: @Sendable (String) async -> Result<UsageReport, UsageError>
    public var cli: CLIActions?                    // nil → degraded "CLI not found" mode
    /// nil when the clausona binary is missing — handoff entry points hide.
    public var launchFlow: (@MainActor (ClausonaFlow) -> String?)?
    public var launchAtLoginStatus: @Sendable () -> Bool
    public var setLaunchAtLogin: @Sendable (Bool) throws -> Void
    public var now: @Sendable () -> Date

    public init(loadProfiles: @escaping @Sendable () -> ProfilesFile?,
                token: @escaping @Sendable (Profile) async -> TokenResult,
                fetchUsage: @escaping @Sendable (String) async -> Result<UsageReport, UsageError>,
                cli: CLIActions?,
                launchFlow: (@MainActor (ClausonaFlow) -> String?)? = nil,
                launchAtLoginStatus: @escaping @Sendable () -> Bool = { SMAppService.mainApp.status == .enabled },
                setLaunchAtLogin: @escaping @Sendable (Bool) throws -> Void = { enabled in
                    if enabled { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
                },
                now: @escaping @Sendable () -> Date = { Date() }) {
        self.loadProfiles = loadProfiles
        self.token = token
        self.fetchUsage = fetchUsage
        self.cli = cli
        self.launchFlow = launchFlow
        self.launchAtLoginStatus = launchAtLoginStatus
        self.setLaunchAtLogin = setLaunchAtLogin
        self.now = now
    }

    public static func live(settings: AppSettings? = nil) -> AppDependencies {
        let store = ProfileStore()
        let provider = TokenProvider.live()
        let fetcher = UsageFetcher.live
        let binaryPath = ClausonaCLI.locate()
        let cli = binaryPath.map { path in
            let cli = ClausonaCLI(binaryPath: path)
            return CLIActions(use: { await cli.use(profile: $0) },
                              repair: { await cli.repair(profile: $0) },
                              doctor: { await cli.doctor() })
        }
        var launchFlow: (@MainActor (ClausonaFlow) -> String?)?
        if let path = binaryPath {
            launchFlow = { flow in
                TerminalLauncher.launch(flow.command(binaryPath: path),
                                        using: settings?.terminal ?? .terminal,
                                        otherAppPath: settings?.otherTerminalPath)
            }
        }
        return AppDependencies(
            loadProfiles: { store.load() },
            token: { await provider.token(forConfigDir: $0.configDir) },
            fetchUsage: { await fetcher.fetch(token: $0) },
            cli: cli,
            launchFlow: launchFlow)
    }
}
