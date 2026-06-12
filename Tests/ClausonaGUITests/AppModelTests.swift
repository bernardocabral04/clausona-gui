import XCTest
@testable import ClausonaGUI

@MainActor
final class AppModelTests: XCTestCase {
    nonisolated static let now = Date(timeIntervalSince1970: 2_000_000)

    private func file(active: String = "personal", names: [String] = ["personal", "work"]) -> ProfilesFile {
        ProfilesFile(activeProfile: active,
                     profiles: names.map { Profile(name: $0, configDir: "/d/\($0)", email: nil, orgName: nil, isPrimary: false) })
    }

    nonisolated private static func report(_ pct: Int) -> UsageReport {
        UsageReport(fiveHour: UsageWindow(utilization: pct, resetsAt: nil), sevenDay: nil)
    }

    private func deps(profiles: ProfilesFile? = nil,
                      token: @escaping @Sendable (Profile) async -> TokenResult = { _ in .ok(.init(accessToken: "t", expiresAt: .distantFuture)) },
                      fetch: @escaping @Sendable (String) async -> Result<UsageReport, UsageError> = { _ in .success(UsageReport(fiveHour: nil, sevenDay: nil)) },
                      cli: CLIActions? = nil) -> AppDependencies {
        AppDependencies(loadProfiles: { profiles }, token: token, fetchUsage: fetch, cli: cli,
                        launchAtLoginStatus: { false }, setLaunchAtLogin: { _ in }, now: { Self.now })
    }

    func testMissingProfilesFileMeansNotSetUp() async {
        let model = AppModel(deps: deps(profiles: nil))
        await model.refreshUsage()
        XCTAssertEqual(model.setupState, .notSetUp)
        XCTAssertTrue(model.snapshots.isEmpty)
    }

    func testRefreshPopulatesRows() async {
        let model = AppModel(deps: deps(profiles: file(), fetch: { _ in .success(Self.report(42)) }))
        await model.refreshUsage()
        XCTAssertEqual(model.setupState, .ready)
        XCTAssertEqual(model.snapshots.map(\.name), ["personal", "work"])
        XCTAssertEqual(model.snapshots[0].isActive, true)
        XCTAssertEqual(model.snapshots[1].isActive, false)
        XCTAssertEqual(model.snapshots[0].usage, .ok(Self.report(42)))
        XCTAssertEqual(model.lastUpdated, Self.now)
    }

    func testTokenStatesRenderPerProfileErrors() async {
        let model = AppModel(deps: deps(profiles: file(), token: { profile in
            profile.name == "personal" ? .missing : .expired
        }))
        await model.refreshUsage()
        XCTAssertEqual(model.snapshots[0].usage, .error(message: "no credentials found", lastGood: nil))
        XCTAssertEqual(model.snapshots[1].usage, .error(message: "login needed — clausona login work", lastGood: nil))
        XCTAssertNil(model.lastUpdated)   // no successful fetch
    }

    func testFetchFailureKeepsLastGood() async {
        nonisolated(unsafe) var fail = false
        let model = AppModel(deps: deps(profiles: file(names: ["personal"]), fetch: { _ in
            fail ? .failure(.http(401)) : .success(Self.report(42))
        }))
        await model.refreshUsage()
        fail = true
        await model.refreshUsage()
        XCTAssertEqual(model.snapshots[0].usage, .error(message: "HTTP 401", lastGood: Self.report(42)))
        XCTAssertEqual(model.lastUpdated, Self.now)  // from the first, successful cycle
    }

    func testSwitchOptimisticThenRevertOnFailure() async {
        let cli = CLIActions(use: { _ in .failure(CLIError(message: "boom")) },
                             repair: { _ in .success(()) }, doctor: { .failure(CLIError(message: "no doctor")) })
        let model = AppModel(deps: deps(profiles: file(), cli: cli))
        await model.refreshUsage()
        await model.switchProfile("work")
        XCTAssertEqual(model.snapshots.first(where: { $0.name == "personal" })?.isActive, true)  // reverted
        XCTAssertEqual(model.toast, "boom")
    }

    func testSwitchSuccessMovesActive() async {
        let cli = CLIActions(use: { _ in .success(()) }, repair: { _ in .success(()) }, doctor: { .failure(CLIError(message: "no doctor")) })
        let model = AppModel(deps: deps(profiles: file(), cli: cli))
        await model.refreshUsage()
        await model.switchProfile("work")
        XCTAssertEqual(model.activeProfile, "work")
        XCTAssertEqual(model.snapshots.first(where: { $0.name == "work" })?.isActive, true)
        XCTAssertNil(model.toast)
    }

    func testRefreshHealthMapsDoctorOutputAndUnknown() async {
        let doctorOutput = """
          personal (a@b.c)
            ✔ healthy
        """
        let cli = CLIActions(use: { _ in .success(()) }, repair: { _ in .success(()) }, doctor: { .success(doctorOutput) })
        let model = AppModel(deps: deps(profiles: file(), cli: cli))
        await model.refreshUsage()
        await model.refreshHealth()
        XCTAssertEqual(model.snapshots[0].health, .healthy)
        XCTAssertEqual(model.snapshots[1].health, .unknown)
    }

    func testRepairFailureSetsToast() async {
        let cli = CLIActions(use: { _ in .success(()) },
                             repair: { _ in .failure(CLIError(message: "repair broke")) },
                             doctor: { .failure(CLIError(message: "no doctor")) })
        let model = AppModel(deps: deps(profiles: file(), cli: cli))
        await model.refreshUsage()
        await model.repair("work")
        XCTAssertEqual(model.toast, "repair broke")
        XCTAssertEqual(model.snapshots.first(where: { $0.name == "work" })?.isRepairing, false)
    }

    func testCredentialStatusCaptured() async {
        let expiry = Date(timeIntervalSince1970: 3_000_000)
        let model = AppModel(deps: deps(profiles: file(), token: { profile in
            profile.name == "personal" ? .ok(.init(accessToken: "t", expiresAt: expiry)) : .missing
        }))
        await model.refreshUsage()
        XCTAssertEqual(model.snapshots[0].credential, .valid(until: expiry))
        XCTAssertEqual(model.snapshots[1].credential, .missing)
    }

    func testCredentialStatusExpired() async {
        let model = AppModel(deps: deps(profiles: file(names: ["personal"]), token: { _ in .expired }))
        await model.refreshUsage()
        XCTAssertEqual(model.snapshots[0].credential, .expired)
    }

    func testDoctorFailureSetsErrorAndKeepsHealth() async {
        nonisolated(unsafe) var failDoctor = false
        let cli = CLIActions(use: { _ in .success(()) }, repair: { _ in .success(()) },
                             doctor: { failDoctor ? .failure(CLIError(message: "boom")) : .success("  personal (a@b.c)\n    \u{2714} healthy") })
        let model = AppModel(deps: deps(profiles: file(), cli: cli))
        await model.refreshUsage()
        await model.refreshHealth()
        XCTAssertEqual(model.snapshots[0].health, .healthy)
        XCTAssertNil(model.doctorError)
        failDoctor = true
        await model.refreshHealth()
        XCTAssertEqual(model.doctorError, "boom")
        XCTAssertEqual(model.snapshots[0].health, .healthy)   // last good health kept
    }

    func testTotalIssueCount() async {
        let output = """
          personal (a@b.c)
            \u{2718} 2 issues
            \u{251C}\u{2500} one
            \u{2570}\u{2500} two
          work (w@b.c)
            \u{2718} 1 issue
            \u{2570}\u{2500} three
        """
        let cli = CLIActions(use: { _ in .success(()) }, repair: { _ in .success(()) },
                             doctor: { .success(output) })
        let model = AppModel(deps: deps(profiles: file(), cli: cli))
        await model.refreshUsage()
        await model.refreshHealth()
        XCTAssertEqual(model.totalIssueCount, 3)
    }

    func testCliAvailabilityFlag() {
        XCTAssertFalse(AppModel(deps: deps()).cliAvailable)
        let cli = CLIActions(use: { _ in .success(()) }, repair: { _ in .success(()) }, doctor: { .failure(CLIError(message: "no doctor")) })
        XCTAssertTrue(AppModel(deps: deps(cli: cli)).cliAvailable)
    }
}
