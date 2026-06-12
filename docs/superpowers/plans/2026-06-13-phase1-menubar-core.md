# Clausona GUI Phase 1 — Menu Bar Core Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Native macOS menu bar app showing 5h/7d Claude rate-limit windows per clausona profile, with one-click profile switching, health badge + repair, ⌃⌥⌘L hotkey, and launch-at-login.

**Architecture:** SwiftPM package with a library target `ClausonaGUI` (all logic + UI, fully testable) and a thin executable `ClausonaApp` (main.swift only). AppKit lifecycle (`NSStatusItem` + `NSPopover` + `NSHostingController`), SwiftUI content, `@Observable` `@MainActor` AppModel as the single source of truth, side effects injected through a `Sendable` `AppDependencies` struct so all state logic is unit-testable with fakes. Reads go straight to `~/.clausona/profiles.json`, the keychain (via `/usr/bin/security`), and the oauth usage endpoint; mutations shell out to the clausona CLI.

**Tech Stack:** Swift 6 language mode, SwiftPM, macOS 14+, AppKit + SwiftUI + Observation, Carbon `RegisterEventHotKey`, `SMAppService`, XCTest.

**Spec:** `docs/superpowers/specs/2026-06-12-phase1-menubar-core-design.md`

---

## Verified ground truth (collected 2026-06-13)

- `~/.clausona/profiles.json` shape: `{ primarySource, activeProfile, profiles: { name: { configDir, email, orgName, isPrimary?, mergeSessions? } } }`.
- Usage endpoint live response: `five_hour`/`seven_day` are `{ "utilization": 61.0, "resets_at": "2026-06-13T00:29:59.955070+00:00" }`; other keys (ignored) exist; windows may be `null`. **`resets_at` has 6-digit fractional seconds** — `ISO8601DateFormatter` needs the fraction stripped first.
- `clausona doctor` real output (no ANSI when piped; parser strips ANSI anyway):
  ```
    personal (bernardo.cabral@outlook.com)
      ✔ healthy

    work (bernardo.cabral@scaleits-solutions.com)
      ✘ 4 issues
      ├─ .last-update-result.json replaced an expected shared symlink
      ├─ mcp-needs-auth-cache.json replaced an expected shared symlink
      ├─ stats-cache.json replaced an expected shared symlink
      ╰─ plugins/ marketplaces and known_marketplaces.json are out of sync
         Run clausona repair work to fix
  ```
  Note plural `issues` and the indented `Run clausona repair … to fix` continuation line (must be ignored).
- Keychain fixtures: `sha256("/Users/test/.claude")[0..8] = 462977e4`, `sha256("/Users/bernardo/.claude")[0..8] = 756a26b6`.
- Epochs: `2026-06-13T00:29:59Z = 1781310599`, `2026-06-15T12:59:59Z = 1781528399`.
- Toolchain: Swift 6.3.1 / Xcode 26.4.1. clausona binary at `~/.local/bin/clausona`.

## File structure

```
Package.swift
Makefile
Resources/Info.plist
Sources/ClausonaApp/main.swift                     — NSApplication bootstrap only
Sources/ClausonaGUI/
├── App/AppDelegate.swift                          — wiring: model, status item, hotkey, scheduler
├── App/StatusItemController.swift                 — NSStatusItem + NSPopover + highlight
├── App/HotkeyManager.swift                        — Carbon ⌃⌥⌘L
├── Core/AppModel.swift                            — @Observable @MainActor state machine
├── Core/AppDependencies.swift                     — Sendable side-effect injection (+ .live())
├── Core/ProfileStore.swift                        — profiles.json location + load
├── Core/Credentials.swift                         — service-name hash, blob parse, freshest pick
├── Core/TokenProvider.swift                       — keychain + file-fallback orchestration
├── Core/UsageFetcher.swift                        — oauth usage HTTP (injectable transport)
├── Core/DoctorParser.swift                        — ANSI strip + doctor output parse
├── Core/ClausonaCLI.swift                         — locate binary, run use/repair/doctor
├── Core/Subprocess.swift                          — async Process helper
├── Core/RefreshScheduler.swift                    — 5 min usage / 30 min health timers
├── Core/Formatting.swift                          — duration, "ago", severity thresholds
├── Core/Staleness.swift                           — missed-cycle staleness rule
├── Model/Profile.swift                            — Profile, ProfilesFile (+decode)
├── Model/UsageWindow.swift                        — UsageWindow, UsageReport (+decode), APIDate
├── Model/HealthStatus.swift                       — healthy / issues / unknown
├── Model/ProfileSnapshot.swift                    — per-row UI state, UsageState
└── UI/PopoverView.swift, ProfileRowView.swift, FooterView.swift, EmptyStateView.swift, ToastView.swift
Tests/ClausonaGUITests/                            — one test file per Core/Model unit
```

Design deviation noted for the executor: the spec's "yellow" tier renders as `.orange` in SwiftUI (yellow is illegible on light popover backgrounds); thresholds are identical to the CLI (<70 green, <90 orange, ≥90 red).

---

### Task 0: Branch

- [ ] **Step 1: Create feature branch**

```bash
cd /Users/bernardo/Projects/personal/clausona-gui
git checkout -b phase1-menubar-core
```

### Task 1: SwiftPM scaffold

**Files:**
- Create: `Package.swift`, `.gitignore`, `Sources/ClausonaGUI/Model/Profile.swift` (placeholder type), `Sources/ClausonaApp/main.swift` (placeholder), `Tests/ClausonaGUITests/SmokeTests.swift`

- [ ] **Step 1: Write Package.swift**

```swift
// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "ClausonaGUI",
    platforms: [.macOS(.v14)],
    targets: [
        .target(name: "ClausonaGUI"),
        .executableTarget(name: "ClausonaApp", dependencies: ["ClausonaGUI"]),
        .testTarget(name: "ClausonaGUITests", dependencies: ["ClausonaGUI"]),
    ]
)
```

- [ ] **Step 2: .gitignore**

```
.build/
.swiftpm/
dist/
.DS_Store
```

- [ ] **Step 3: Minimal sources so all three targets build**

`Sources/ClausonaGUI/Model/Profile.swift`:
```swift
public struct Profile: Equatable, Sendable {
    public let name: String
    public let configDir: String
    public let email: String?
    public let orgName: String?
    public let isPrimary: Bool

    public init(name: String, configDir: String, email: String?, orgName: String?, isPrimary: Bool) {
        self.name = name
        self.configDir = configDir
        self.email = email
        self.orgName = orgName
        self.isPrimary = isPrimary
    }
}
```

`Sources/ClausonaApp/main.swift`:
```swift
import ClausonaGUI

// Placeholder until Task 14 wires the AppKit lifecycle.
print("clausona-gui placeholder")
```

`Tests/ClausonaGUITests/SmokeTests.swift`:
```swift
import XCTest
@testable import ClausonaGUI

final class SmokeTests: XCTestCase {
    func testProfileRoundTrip() {
        let p = Profile(name: "personal", configDir: "/Users/test/.claude", email: nil, orgName: nil, isPrimary: true)
        XCTAssertEqual(p.name, "personal")
    }
}
```

- [ ] **Step 4: Run** `swift test` — expected: 1 test passes.

- [ ] **Step 5: Commit** `git add -A && git commit -m "feat: SwiftPM scaffold (lib + app + tests)"`

### Task 2: Formatting (duration, ago, severity)

**Files:**
- Create: `Sources/ClausonaGUI/Core/Formatting.swift`
- Test: `Tests/ClausonaGUITests/FormattingTests.swift`

- [ ] **Step 1: Write failing tests** (port the zsh `fmt_dur` rules exactly: `d>0 → XdYh`, `h>0 → XhMMm` zero-padded minutes, else `Xm`, negative → `?`)

```swift
import XCTest
@testable import ClausonaGUI

final class FormattingTests: XCTestCase {
    func testDuration() {
        XCTAssertEqual(Formatting.duration(seconds: 3 * 3600 + 42 * 60), "3h42m")
        XCTAssertEqual(Formatting.duration(seconds: 2 * 86400 + 4 * 3600), "2d4h")
        XCTAssertEqual(Formatting.duration(seconds: 5 * 60), "5m")
        XCTAssertEqual(Formatting.duration(seconds: 3601), "1h00m")
        XCTAssertEqual(Formatting.duration(seconds: 0), "0m")
        XCTAssertEqual(Formatting.duration(seconds: -5), "?")
    }

    func testUpdatedAgo() {
        XCTAssertEqual(Formatting.updatedAgo(seconds: 12), "just now")
        XCTAssertEqual(Formatting.updatedAgo(seconds: 140), "2m ago")
        XCTAssertEqual(Formatting.updatedAgo(seconds: 2 * 3600 + 60), "2h ago")
        XCTAssertEqual(Formatting.updatedAgo(seconds: 3 * 86400), "3d ago")
    }

    func testSeverity() {
        XCTAssertEqual(UsageSeverity(percent: 0), .normal)
        XCTAssertEqual(UsageSeverity(percent: 69), .normal)
        XCTAssertEqual(UsageSeverity(percent: 70), .elevated)
        XCTAssertEqual(UsageSeverity(percent: 89), .elevated)
        XCTAssertEqual(UsageSeverity(percent: 90), .critical)
        XCTAssertEqual(UsageSeverity(percent: 100), .critical)
    }
}
```

- [ ] **Step 2: Run** `swift test --filter FormattingTests` — expected FAIL (types undefined).

- [ ] **Step 3: Implement**

```swift
import Foundation

public enum Formatting {
    /// Port of clausona-limits' fmt_dur.
    public static func duration(seconds: Int) -> String {
        guard seconds >= 0 else { return "?" }
        let days = seconds / 86400
        let hours = seconds % 86400 / 3600
        let minutes = seconds % 3600 / 60
        if days > 0 { return "\(days)d\(hours)h" }
        if hours > 0 { return String(format: "%dh%02dm", hours, minutes) }
        return "\(minutes)m"
    }

    public static func updatedAgo(seconds: Int) -> String {
        if seconds < 60 { return "just now" }
        let minutes = seconds / 60
        if minutes < 60 { return "\(minutes)m ago" }
        let hours = minutes / 60
        if hours < 24 { return "\(hours)h ago" }
        return "\(hours / 24)d ago"
    }
}

public enum UsageSeverity: Equatable, Sendable {
    case normal, elevated, critical

    public init(percent: Int) {
        self = percent >= 90 ? .critical : percent >= 70 ? .elevated : .normal
    }
}
```

- [ ] **Step 4: Run** `swift test --filter FormattingTests` — expected PASS.
- [ ] **Step 5: Commit** `git add -A && git commit -m "feat: duration/ago formatting + usage severity thresholds"`

### Task 3: profiles.json decoding + ProfileStore

**Files:**
- Modify: `Sources/ClausonaGUI/Model/Profile.swift` (add `ProfilesFile`)
- Create: `Sources/ClausonaGUI/Core/ProfileStore.swift`
- Test: `Tests/ClausonaGUITests/ProfilesDecodingTests.swift`

- [ ] **Step 1: Failing tests** — full real-shaped file, minimal file, garbage, profile missing configDir skipped:

```swift
import XCTest
@testable import ClausonaGUI

final class ProfilesDecodingTests: XCTestCase {
    func testFullFile() throws {
        let json = """
        {
          "primarySource": "/Users/test/.claude",
          "activeProfile": "personal",
          "profiles": {
            "personal": { "configDir": "/Users/test/.claude", "email": "a@b.c", "orgName": "Org", "isPrimary": true },
            "work": { "configDir": "/Users/test/.claude-work", "email": "w@b.c", "orgName": "W", "mergeSessions": false, "futureKey": 42 }
          }
        }
        """
        let file = try ProfilesFile.decode(Data(json.utf8))
        XCTAssertEqual(file.activeProfile, "personal")
        XCTAssertEqual(file.profiles.map(\.name), ["personal", "work"])
        XCTAssertEqual(file.profiles[0].configDir, "/Users/test/.claude")
        XCTAssertTrue(file.profiles[0].isPrimary)
        XCTAssertFalse(file.profiles[1].isPrimary)
        XCTAssertEqual(file.profiles[1].email, "w@b.c")
    }

    func testMinimalFile() throws {
        let file = try ProfilesFile.decode(Data("{}".utf8))
        XCTAssertNil(file.activeProfile)
        XCTAssertTrue(file.profiles.isEmpty)
    }

    func testGarbageThrows() {
        XCTAssertThrowsError(try ProfilesFile.decode(Data("not json".utf8)))
    }

    func testProfileWithoutConfigDirSkipped() throws {
        let json = #"{ "profiles": { "broken": { "email": "x@y.z" }, "ok": { "configDir": "/tmp/x" } } }"#
        let file = try ProfilesFile.decode(Data(json.utf8))
        XCTAssertEqual(file.profiles.map(\.name), ["ok"])
    }
}
```

- [ ] **Step 2: Run** `swift test --filter ProfilesDecodingTests` — expected FAIL.

- [ ] **Step 3: Implement** — append to `Profile.swift`:

```swift
import Foundation

public struct ProfilesFile: Equatable, Sendable {
    public let activeProfile: String?
    public let profiles: [Profile]   // sorted by name for stable display

    public init(activeProfile: String?, profiles: [Profile]) {
        self.activeProfile = activeProfile
        self.profiles = profiles
    }

    public static func decode(_ data: Data) throws -> ProfilesFile {
        struct RawProfile: Decodable {
            var configDir: String?
            var email: String?
            var orgName: String?
            var isPrimary: Bool?
        }
        struct RawFile: Decodable {
            var activeProfile: String?
            var profiles: [String: RawProfile]?
        }
        let raw = try JSONDecoder().decode(RawFile.self, from: data)
        let profiles = (raw.profiles ?? [:])
            .compactMap { name, p -> Profile? in
                guard let dir = p.configDir else { return nil }
                return Profile(name: name, configDir: dir, email: p.email,
                               orgName: p.orgName, isPrimary: p.isPrimary ?? false)
            }
            .sorted { $0.name < $1.name }
        return ProfilesFile(activeProfile: raw.activeProfile, profiles: profiles)
    }
}
```

`Sources/ClausonaGUI/Core/ProfileStore.swift`:

```swift
import Foundation

/// Locates and loads $CLAUSONA_HOME/profiles.json (default ~/.clausona).
public struct ProfileStore: Sendable {
    public let profilesPath: String

    public init(environment: [String: String] = ProcessInfo.processInfo.environment,
                home: String = NSHomeDirectory()) {
        let base = environment["CLAUSONA_HOME"] ?? home + "/.clausona"
        profilesPath = base + "/profiles.json"
    }

    /// nil → clausona is not set up (file missing or unparseable).
    public func load() -> ProfilesFile? {
        guard let data = FileManager.default.contents(atPath: profilesPath) else { return nil }
        return try? ProfilesFile.decode(data)
    }
}
```

- [ ] **Step 4: Run** `swift test --filter ProfilesDecodingTests` — expected PASS.
- [ ] **Step 5: Commit** `git add -A && git commit -m "feat: profiles.json decoding + ProfileStore"`

### Task 4: Usage response decoding

**Files:**
- Create: `Sources/ClausonaGUI/Model/UsageWindow.swift`
- Test: `Tests/ClausonaGUITests/UsageDecodingTests.swift`

- [ ] **Step 1: Failing tests** — uses the real captured response shape, incl. 6-digit fractional seconds:

```swift
import XCTest
@testable import ClausonaGUI

final class UsageDecodingTests: XCTestCase {
    func testBothWindows() throws {
        let json = """
        {
          "five_hour": { "utilization": 61.4, "resets_at": "2026-06-13T00:29:59.955070+00:00" },
          "seven_day": { "utilization": 52.0, "resets_at": "2026-06-15T12:59:59.955093+00:00" },
          "seven_day_sonnet": { "utilization": 0.0, "resets_at": null },
          "extra_usage": { "is_enabled": false }
        }
        """
        let report = try UsageReport.decode(Data(json.utf8))
        XCTAssertEqual(report.fiveHour?.utilization, 61)
        XCTAssertEqual(report.fiveHour?.resetsAt, Date(timeIntervalSince1970: 1_781_310_599))
        XCTAssertEqual(report.sevenDay?.utilization, 52)
        XCTAssertEqual(report.sevenDay?.resetsAt, Date(timeIntervalSince1970: 1_781_528_399))
    }

    func testMissingAndNullWindows() throws {
        let report = try UsageReport.decode(Data(#"{ "five_hour": null }"#.utf8))
        XCTAssertNil(report.fiveHour)
        XCTAssertNil(report.sevenDay)
    }

    func testWindowWithoutReset() throws {
        let report = try UsageReport.decode(Data(#"{ "five_hour": { "utilization": 12.6 } }"#.utf8))
        XCTAssertEqual(report.fiveHour?.utilization, 13)   // rounded
        XCTAssertNil(report.fiveHour?.resetsAt)
    }

    func testMalformedThrows() {
        XCTAssertThrowsError(try UsageReport.decode(Data("oops".utf8)))
    }

    func testAPIDateZuluAndOffset() {
        XCTAssertEqual(APIDate.parse("2026-06-13T00:29:59Z"), Date(timeIntervalSince1970: 1_781_310_599))
        XCTAssertEqual(APIDate.parse("2026-06-13T00:29:59.5+00:00"), Date(timeIntervalSince1970: 1_781_310_599))
        XCTAssertNil(APIDate.parse("yesterday"))
    }
}
```

- [ ] **Step 2: Run** `swift test --filter UsageDecodingTests` — expected FAIL.

- [ ] **Step 3: Implement**

```swift
import Foundation

public struct UsageWindow: Equatable, Sendable {
    public let utilization: Int      // rounded percent
    public let resetsAt: Date?

    public init(utilization: Int, resetsAt: Date?) {
        self.utilization = utilization
        self.resetsAt = resetsAt
    }
}

public struct UsageReport: Equatable, Sendable {
    public let fiveHour: UsageWindow?
    public let sevenDay: UsageWindow?

    public init(fiveHour: UsageWindow?, sevenDay: UsageWindow?) {
        self.fiveHour = fiveHour
        self.sevenDay = sevenDay
    }

    public static func decode(_ data: Data) throws -> UsageReport {
        struct RawWindow: Decodable {
            var utilization: Double?
            var resets_at: String?
        }
        struct RawUsage: Decodable {
            var five_hour: RawWindow?
            var seven_day: RawWindow?
        }
        let raw = try JSONDecoder().decode(RawUsage.self, from: data)
        func window(_ w: RawWindow?) -> UsageWindow? {
            guard let w, let utilization = w.utilization else { return nil }
            return UsageWindow(utilization: Int(utilization.rounded()),
                               resetsAt: w.resets_at.flatMap(APIDate.parse))
        }
        return UsageReport(fiveHour: window(raw.five_hour), sevenDay: window(raw.seven_day))
    }
}

/// The usage endpoint emits 6-digit fractional seconds, which ISO8601DateFormatter
/// rejects — strip the fraction first (same as clausona-limits' jq `ep` helper).
public enum APIDate {
    public static func parse(_ string: String) -> Date? {
        let stripped = string.replacingOccurrences(of: #"\.\d+"#, with: "", options: .regularExpression)
        return ISO8601DateFormatter().date(from: stripped)
    }
}
```

- [ ] **Step 4: Run** `swift test --filter UsageDecodingTests` — expected PASS.
- [ ] **Step 5: Commit** `git add -A && git commit -m "feat: oauth usage response decoding with fractional-second dates"`

### Task 5: Credentials (service name, blob parse, freshest pick)

**Files:**
- Create: `Sources/ClausonaGUI/Core/Credentials.swift`
- Test: `Tests/ClausonaGUITests/CredentialsTests.swift`

- [ ] **Step 1: Failing tests** — sha256 fixtures verified with `shasum -a 256`:

```swift
import XCTest
@testable import ClausonaGUI

final class CredentialsTests: XCTestCase {
    func testServiceName() {
        XCTAssertEqual(Credentials.serviceName(forConfigDir: "/Users/test/.claude"),
                       "Claude Code-credentials-462977e4")
        XCTAssertEqual(Credentials.serviceName(forConfigDir: "/Users/bernardo/.claude"),
                       "Claude Code-credentials-756a26b6")
    }

    func testParseValidBlob() {
        let blob = #"{ "claudeAiOauth": { "accessToken": "tok-abc", "expiresAt": 1781310599000, "scopes": ["x"] } }"#
        let token = Credentials.parse(Data(blob.utf8))
        XCTAssertEqual(token?.accessToken, "tok-abc")
        XCTAssertEqual(token?.expiresAt, Date(timeIntervalSince1970: 1_781_310_599))
    }

    func testParseRejectsEmptyTokenMissingExpiryAndGarbage() {
        XCTAssertNil(Credentials.parse(Data(#"{ "claudeAiOauth": { "accessToken": "", "expiresAt": 5 } }"#.utf8)))
        XCTAssertNil(Credentials.parse(Data(#"{ "claudeAiOauth": { "accessToken": "tok" } }"#.utf8)))
        XCTAssertNil(Credentials.parse(Data("nope".utf8)))
        XCTAssertNil(Credentials.parse(Data("{}".utf8)))
    }

    func testFreshestPicksLatestExpiry() {
        let old = Credentials.Token(accessToken: "old", expiresAt: Date(timeIntervalSince1970: 100))
        let new = Credentials.Token(accessToken: "new", expiresAt: Date(timeIntervalSince1970: 200))
        XCTAssertEqual(Credentials.freshest([old, new])?.accessToken, "new")
        XCTAssertEqual(Credentials.freshest([new, old])?.accessToken, "new")
        XCTAssertNil(Credentials.freshest([]))
    }
}
```

- [ ] **Step 2: Run** `swift test --filter CredentialsTests` — expected FAIL.

- [ ] **Step 3: Implement**

```swift
import CryptoKit
import Foundation

public enum Credentials {
    public struct Token: Equatable, Sendable {
        public let accessToken: String
        public let expiresAt: Date

        public init(accessToken: String, expiresAt: Date) {
            self.accessToken = accessToken
            self.expiresAt = expiresAt
        }
    }

    /// "Claude Code-credentials-<first 8 hex of sha256(configDir)>" — same storage Claude Code uses.
    public static func serviceName(forConfigDir dir: String) -> String {
        let digest = SHA256.hash(data: Data(dir.utf8))
        let hex = digest.map { String(format: "%02x", $0) }.joined()
        return "Claude Code-credentials-" + hex.prefix(8)
    }

    /// Requires a non-empty token AND a positive expiry, matching clausona-limits
    /// (a token without expiresAt is never selected there either).
    public static func parse(_ data: Data) -> Token? {
        struct RawOauth: Decodable {
            var accessToken: String?
            var expiresAt: Double?
        }
        struct RawBlob: Decodable {
            var claudeAiOauth: RawOauth?
        }
        guard let raw = try? JSONDecoder().decode(RawBlob.self, from: data),
              let accessToken = raw.claudeAiOauth?.accessToken, !accessToken.isEmpty,
              let expiresMS = raw.claudeAiOauth?.expiresAt, expiresMS > 0
        else { return nil }
        return Token(accessToken: accessToken, expiresAt: Date(timeIntervalSince1970: expiresMS / 1000))
    }

    public static func freshest(_ tokens: [Token]) -> Token? {
        tokens.max { $0.expiresAt < $1.expiresAt }
    }
}
```

- [ ] **Step 4: Run** `swift test --filter CredentialsTests` — expected PASS.
- [ ] **Step 5: Commit** `git add -A && git commit -m "feat: keychain service naming + credentials blob parsing"`

### Task 6: Subprocess helper

**Files:**
- Create: `Sources/ClausonaGUI/Core/Subprocess.swift`
- Test: `Tests/ClausonaGUITests/SubprocessTests.swift`

- [ ] **Step 1: Failing tests** (real processes — fast system binaries):

```swift
import XCTest
@testable import ClausonaGUI

final class SubprocessTests: XCTestCase {
    func testCapturesStdoutAndExitCode() async {
        let result = await Subprocess.run("/bin/echo", ["hello"])
        XCTAssertEqual(result?.exitCode, 0)
        XCTAssertEqual(result?.stdout, "hello\n")
        XCTAssertEqual(result?.stderr, "")
    }

    func testNonZeroExitAndStderr() async {
        let result = await Subprocess.run("/bin/sh", ["-c", "echo bad >&2; exit 3"])
        XCTAssertEqual(result?.exitCode, 3)
        XCTAssertEqual(result?.stderr, "bad\n")
    }

    func testMissingExecutableReturnsNil() async {
        let result = await Subprocess.run("/no/such/binary", [])
        XCTAssertNil(result)
    }
}
```

- [ ] **Step 2: Run** `swift test --filter SubprocessTests` — expected FAIL.

- [ ] **Step 3: Implement**

```swift
import Foundation

public struct SubprocessResult: Equatable, Sendable {
    public let exitCode: Int32
    public let stdout: String
    public let stderr: String
}

public enum Subprocess {
    /// Runs a process and captures output. Returns nil if the executable can't launch.
    /// All callers here produce small outputs (doctor is ~2 KB), well under the pipe
    /// buffer, so reading after termination cannot deadlock.
    public static func run(_ executable: String, _ arguments: [String]) async -> SubprocessResult? {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments
        let outPipe = Pipe()
        let errPipe = Pipe()
        process.standardOutput = outPipe
        process.standardError = errPipe
        process.standardInput = FileHandle.nullDevice

        return await withCheckedContinuation { continuation in
            process.terminationHandler = { proc in
                let out = (try? outPipe.fileHandleForReading.readToEnd()) ?? Data()
                let err = (try? errPipe.fileHandleForReading.readToEnd()) ?? Data()
                continuation.resume(returning: SubprocessResult(
                    exitCode: proc.terminationStatus,
                    stdout: String(decoding: out, as: UTF8.self),
                    stderr: String(decoding: err, as: UTF8.self)))
            }
            do {
                try process.run()
            } catch {
                process.terminationHandler = nil
                continuation.resume(returning: nil)
            }
        }
    }
}
```

(If Swift 6 strict concurrency rejects the pipe captures, mark the locals `nonisolated(unsafe) let outPipe = Pipe()` etc. — the handler is the only reader after launch.)

- [ ] **Step 4: Run** `swift test --filter SubprocessTests` — expected PASS.
- [ ] **Step 5: Commit** `git add -A && git commit -m "feat: async subprocess helper"`

### Task 7: TokenProvider

**Files:**
- Create: `Sources/ClausonaGUI/Core/TokenProvider.swift`
- Test: `Tests/ClausonaGUITests/TokenProviderTests.swift`

- [ ] **Step 1: Failing tests** — orchestration with fakes (legacy service only for the legacy dir; freshest across keychain + file; expiry):

```swift
import XCTest
@testable import ClausonaGUI

final class TokenProviderTests: XCTestCase {
    private func blob(token: String, expiresMS: Double) -> Data {
        Data(#"{ "claudeAiOauth": { "accessToken": "\#(token)", "expiresAt": \#(expiresMS) } }"#.utf8)
    }

    private let now = Date(timeIntervalSince1970: 1_000_000)

    private func provider(secrets: [String: Data], files: [String: Data] = [:]) -> TokenProvider {
        TokenProvider(
            readSecret: { secrets[$0] },
            readCredentialsFile: { files[$0] },
            legacyDir: "/Users/test/.claude",
            now: { [now] in now })
    }

    func testHashedServiceHit() async {
        let svc = Credentials.serviceName(forConfigDir: "/Users/test/.claude-work")
        let p = provider(secrets: [svc: blob(token: "tok-w", expiresMS: 2_000_000_000)])
        let result = await p.token(forConfigDir: "/Users/test/.claude-work")
        XCTAssertEqual(result, .ok(Credentials.Token(accessToken: "tok-w", expiresAt: Date(timeIntervalSince1970: 2_000_000))))
    }

    func testLegacyServiceOnlyForLegacyDir() async {
        let secrets = ["Claude Code-credentials": blob(token: "legacy", expiresMS: 2_000_000_000)]
        let hit = await provider(secrets: secrets).token(forConfigDir: "/Users/test/.claude")
        if case .ok(let token) = hit { XCTAssertEqual(token.accessToken, "legacy") } else { XCTFail("\(hit)") }
        let miss = await provider(secrets: secrets).token(forConfigDir: "/Users/test/.claude-work")
        XCTAssertEqual(miss, .missing)
    }

    func testFileFallbackBeatsStalerKeychain() async {
        let svc = Credentials.serviceName(forConfigDir: "/d")
        let p = provider(secrets: [svc: blob(token: "old", expiresMS: 1_500_000_000)],
                         files: ["/d": blob(token: "fresh", expiresMS: 3_000_000_000)])
        let result = await p.token(forConfigDir: "/d")
        if case .ok(let token) = result { XCTAssertEqual(token.accessToken, "fresh") } else { XCTFail("\(result)") }
    }

    func testExpired() async {
        let svc = Credentials.serviceName(forConfigDir: "/d")
        let p = provider(secrets: [svc: blob(token: "tok", expiresMS: 999_999_000)])  // before now
        let result = await p.token(forConfigDir: "/d")
        XCTAssertEqual(result, .expired)
    }

    func testMissing() async {
        let result = await provider(secrets: [:]).token(forConfigDir: "/d")
        XCTAssertEqual(result, .missing)
    }
}
```

- [ ] **Step 2: Run** `swift test --filter TokenProviderTests` — expected FAIL.

- [ ] **Step 3: Implement**

```swift
import Foundation

public enum TokenResult: Equatable, Sendable {
    case ok(Credentials.Token)
    case missing
    case expired
}

/// Port of clausona-limits' token_for_dir. Tokens stay in memory only —
/// never logged, written, or rendered.
public struct TokenProvider: Sendable {
    public var readSecret: @Sendable (String) async -> Data?
    public var readCredentialsFile: @Sendable (String) -> Data?
    public var legacyDir: String
    public var now: @Sendable () -> Date

    public init(readSecret: @escaping @Sendable (String) async -> Data?,
                readCredentialsFile: @escaping @Sendable (String) -> Data?,
                legacyDir: String,
                now: @escaping @Sendable () -> Date) {
        self.readSecret = readSecret
        self.readCredentialsFile = readCredentialsFile
        self.legacyDir = legacyDir
        self.now = now
    }

    public func token(forConfigDir dir: String) async -> TokenResult {
        var services = [Credentials.serviceName(forConfigDir: dir)]
        if dir == legacyDir { services.append("Claude Code-credentials") }

        var candidates: [Credentials.Token] = []
        for service in services {
            if let blob = await readSecret(service), let token = Credentials.parse(blob) {
                candidates.append(token)
            }
        }
        if let data = readCredentialsFile(dir), let token = Credentials.parse(data) {
            candidates.append(token)
        }
        guard let best = Credentials.freshest(candidates) else { return .missing }
        return best.expiresAt > now() ? .ok(best) : .expired
    }

    /// Live wiring: keychain via /usr/bin/security (existing ACL — no new prompts);
    /// file fallback only when .credentials.json is a real file, not clausona's
    /// symlink to the primary profile's credentials.
    public static func live(legacyDir: String = NSHomeDirectory() + "/.claude") -> TokenProvider {
        TokenProvider(
            readSecret: { service in
                guard let result = await Subprocess.run("/usr/bin/security",
                                                        ["find-generic-password", "-s", service, "-w"]),
                      result.exitCode == 0 else { return nil }
                return Data(result.stdout.trimmingCharacters(in: .whitespacesAndNewlines).utf8)
            },
            readCredentialsFile: { dir in
                let path = dir + "/.credentials.json"
                guard let attrs = try? FileManager.default.attributesOfItem(atPath: path),
                      attrs[.type] as? FileAttributeType == .typeRegular else { return nil }
                return FileManager.default.contents(atPath: path)
            },
            legacyDir: legacyDir,
            now: { Date() })
    }
}
```

- [ ] **Step 4: Run** `swift test --filter TokenProviderTests` — expected PASS.

- [ ] **Step 5: Live smoke check** (real keychain, read-only):

```bash
cat > /tmp/token-smoke.swift <<'EOF'
import ClausonaGUI
import Foundation
let provider = TokenProvider.live()
for dir in ["/Users/bernardo/.claude", "/Users/bernardo/.claude-personal3"] {
    let r = await provider.token(forConfigDir: dir)
    switch r {
    case .ok: print("\(dir): ok (token redacted)")
    case .expired: print("\(dir): expired")
    case .missing: print("\(dir): missing")
    }
}
EOF
```
Expected (as of 2026-06-13): `.claude: expired` (known-expired token), `.claude-personal3: ok`. Run via a temporary executable or verify the same logic manually with `security find-generic-password`. Do not print tokens.

- [ ] **Step 6: Commit** `git add -A && git commit -m "feat: TokenProvider with keychain + symlink-aware file fallback"`

### Task 8: HealthStatus + DoctorParser

**Files:**
- Create: `Sources/ClausonaGUI/Model/HealthStatus.swift`, `Sources/ClausonaGUI/Core/DoctorParser.swift`
- Test: `Tests/ClausonaGUITests/DoctorParserTests.swift`

- [ ] **Step 1: Failing tests** — fixture is the real captured doctor output:

```swift
import XCTest
@testable import ClausonaGUI

final class DoctorParserTests: XCTestCase {
    static let realOutput = """
      personal (bernardo.cabral@outlook.com)
        ✔ healthy

      work (bernardo.cabral@scaleits-solutions.com)
        ✘ 4 issues
        ├─ .last-update-result.json replaced an expected shared symlink
        ├─ mcp-needs-auth-cache.json replaced an expected shared symlink
        ├─ stats-cache.json replaced an expected shared symlink
        ╰─ plugins/ marketplaces and known_marketplaces.json are out of sync
           Run clausona repair work to fix

      personal3 (bradasdevelopers@gmail.com)
        ✘ 2 issues
        ├─ .last-update-result.json replaced an expected shared symlink
        ╰─ plugins/ marketplaces and known_marketplaces.json are out of sync
           Run clausona repair personal3 to fix

    """

    func testRealOutput() {
        let result = DoctorParser.parse(Self.realOutput)
        XCTAssertEqual(result["personal"], .healthy)
        guard case .issues(let workIssues)? = result["work"] else { return XCTFail("work not parsed") }
        XCTAssertEqual(workIssues.count, 4)
        XCTAssertEqual(workIssues.first, ".last-update-result.json replaced an expected shared symlink")
        XCTAssertEqual(workIssues.last, "plugins/ marketplaces and known_marketplaces.json are out of sync")
        guard case .issues(let p3)? = result["personal3"] else { return XCTFail("personal3 not parsed") }
        XCTAssertEqual(p3.count, 2)
    }

    func testRepairHintLineIgnored() {
        let result = DoctorParser.parse(Self.realOutput)
        if case .issues(let issues)? = result["work"] {
            XCTAssertFalse(issues.contains { $0.contains("Run clausona repair") })
        }
    }

    func testUnparseableYieldsEmpty() {
        XCTAssertTrue(DoctorParser.parse("random garbage\nnothing here").isEmpty)
    }

    func testSingularIssueForm() {
        let out = """
          alpha (a@b.c)
            ✘ 1 issue
            ╰─ something is wrong
        """
        XCTAssertEqual(DoctorParser.parse(out)["alpha"], .issues(["something is wrong"]))
    }

    func testStripANSI() {
        let colored = "\u{001B}[1mpersonal\u{001B}[0m (\u{001B}[2ma@b.c\u{001B}[0m)\n  \u{001B}[32m✔ healthy\u{001B}[0m"
        let stripped = DoctorParser.stripANSI(colored)
        XCTAssertFalse(stripped.contains("\u{001B}"))
        XCTAssertEqual(DoctorParser.parse(stripped)["personal"], .healthy)
    }
}
```

- [ ] **Step 2: Run** `swift test --filter DoctorParserTests` — expected FAIL.

- [ ] **Step 3: Implement**

`Model/HealthStatus.swift`:
```swift
public enum HealthStatus: Equatable, Sendable {
    case healthy
    case issues([String])
    case unknown
}
```

`Core/DoctorParser.swift`:
```swift
import Foundation

/// Parses `clausona doctor` output. Tolerant by design: anything it can't
/// match is ignored, and profiles absent from the result map to .unknown.
public enum DoctorParser {
    public static func stripANSI(_ string: String) -> String {
        string.replacingOccurrences(of: #"\u{001B}\[[0-9;]*[A-Za-z]"#,
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
```

- [ ] **Step 4: Run** `swift test --filter DoctorParserTests` — expected PASS.
- [ ] **Step 5: Commit** `git add -A && git commit -m "feat: doctor output parser with ANSI stripping"`

### Task 9: Staleness

**Files:**
- Create: `Sources/ClausonaGUI/Core/Staleness.swift`
- Test: `Tests/ClausonaGUITests/StalenessTests.swift`

- [ ] **Step 1: Failing tests** (stale after 2 missed 5-min cycles):

```swift
import XCTest
@testable import ClausonaGUI

final class StalenessTests: XCTestCase {
    let base = Date(timeIntervalSince1970: 1_000_000)

    func testFreshIsNotStale() {
        XCTAssertFalse(Staleness.isStale(lastSuccess: base, now: base.addingTimeInterval(120), pollInterval: 300))
        XCTAssertFalse(Staleness.isStale(lastSuccess: base, now: base.addingTimeInterval(599), pollInterval: 300))
    }

    func testStaleAfterTwoMissedCycles() {
        XCTAssertTrue(Staleness.isStale(lastSuccess: base, now: base.addingTimeInterval(600), pollInterval: 300))
        XCTAssertTrue(Staleness.isStale(lastSuccess: base, now: base.addingTimeInterval(3600), pollInterval: 300))
    }

    func testNeverUpdatedIsNotStale() {
        XCTAssertFalse(Staleness.isStale(lastSuccess: nil, now: base, pollInterval: 300))
    }
}
```

- [ ] **Step 2: Run** `swift test --filter StalenessTests` — expected FAIL.

- [ ] **Step 3: Implement**

```swift
import Foundation

public enum Staleness {
    /// Stale once two consecutive poll cycles have been missed.
    /// nil lastSuccess = still loading for the first time — not "stale".
    public static func isStale(lastSuccess: Date?, now: Date, pollInterval: TimeInterval) -> Bool {
        guard let lastSuccess else { return false }
        return now.timeIntervalSince(lastSuccess) >= pollInterval * 2
    }
}
```

- [ ] **Step 4: Run** `swift test --filter StalenessTests` — expected PASS.
- [ ] **Step 5: Commit** `git add -A && git commit -m "feat: staleness rule (2 missed cycles)"`

### Task 10: ClausonaCLI

**Files:**
- Create: `Sources/ClausonaGUI/Core/ClausonaCLI.swift`
- Test: `Tests/ClausonaGUITests/ClausonaCLITests.swift`

- [ ] **Step 1: Failing tests** — locate with injected probe; use/repair against a real stub script in a temp dir:

```swift
import XCTest
@testable import ClausonaGUI

final class ClausonaCLITests: XCTestCase {
    func testLocatePrefersLocalBinThenPATH() {
        let found = ClausonaCLI.locate(environment: ["PATH": "/a:/b"], home: "/home/u",
                                       fileExists: { $0 == "/home/u/.local/bin/clausona" })
        XCTAssertEqual(found, "/home/u/.local/bin/clausona")

        let viaPath = ClausonaCLI.locate(environment: ["PATH": "/a:/b"], home: "/home/u",
                                         fileExists: { $0 == "/b/clausona" })
        XCTAssertEqual(viaPath, "/b/clausona")

        XCTAssertNil(ClausonaCLI.locate(environment: ["PATH": "/a"], home: "/home/u", fileExists: { _ in false }))
    }

    private func makeStub(_ body: String) throws -> String {
        let dir = NSTemporaryDirectory() + "clausona-cli-test-\(UUID().uuidString)"
        try FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
        let path = dir + "/clausona"
        try ("#!/bin/sh\n" + body).write(toFile: path, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: path)
        return path
    }

    func testUseSuccess() async throws {
        let stub = try makeStub("[ \"$1\" = use ] && [ \"$2\" = work ] && exit 0; exit 1")
        let result = await ClausonaCLI(binaryPath: stub).use(profile: "work")
        guard case .success = result else { return XCTFail("\(result)") }
    }

    func testRepairFailureSurfacesFirstStderrLine() async throws {
        let stub = try makeStub("echo 'repair failed: profile is locked' >&2; echo second >&2; exit 2")
        let result = await ClausonaCLI(binaryPath: stub).repair(profile: "work")
        guard case .failure(let error) = result else { return XCTFail("expected failure") }
        XCTAssertEqual(error.message, "repair failed: profile is locked")
    }

    func testFailureWithoutOutputFallsBackToStatus() async throws {
        let stub = try makeStub("exit 7")
        let result = await ClausonaCLI(binaryPath: stub).use(profile: "x")
        guard case .failure(let error) = result else { return XCTFail("expected failure") }
        XCTAssertEqual(error.message, "clausona exited with status 7")
    }

    func testDoctorReturnsStdout() async throws {
        let stub = try makeStub("echo '  personal (a@b.c)'; echo '    ✔ healthy'")
        let output = await ClausonaCLI(binaryPath: stub).doctor()
        XCTAssertEqual(output?.contains("✔ healthy"), true)
    }
}
```

- [ ] **Step 2: Run** `swift test --filter ClausonaCLITests` — expected FAIL.

- [ ] **Step 3: Implement**

```swift
import Foundation

public struct CLIError: Error, Equatable, Sendable {
    public let message: String

    public init(message: String) { self.message = message }
}

/// Mutations go through the clausona CLI only — never reimplemented here.
public struct ClausonaCLI: Sendable {
    public let binaryPath: String

    public init(binaryPath: String) { self.binaryPath = binaryPath }

    /// ~/.local/bin first (GUI apps don't inherit the shell PATH), then PATH,
    /// then the common Homebrew locations.
    public static func locate(environment: [String: String] = ProcessInfo.processInfo.environment,
                              home: String = NSHomeDirectory(),
                              fileExists: (String) -> Bool = { FileManager.default.isExecutableFile(atPath: $0) }) -> String? {
        var candidates = [home + "/.local/bin/clausona"]
        candidates += (environment["PATH"] ?? "").split(separator: ":").map { String($0) + "/clausona" }
        candidates += ["/opt/homebrew/bin/clausona", "/usr/local/bin/clausona"]
        return candidates.first(where: fileExists)
    }

    public func use(profile: String) async -> Result<Void, CLIError> {
        await run(["use", profile])
    }

    public func repair(profile: String) async -> Result<Void, CLIError> {
        await run(["repair", profile])
    }

    /// Returns raw stdout regardless of exit status — the parser is tolerant.
    public func doctor() async -> String? {
        await Subprocess.run(binaryPath, ["doctor"])?.stdout
    }

    private func run(_ arguments: [String]) async -> Result<Void, CLIError> {
        guard let result = await Subprocess.run(binaryPath, arguments) else {
            return .failure(CLIError(message: "could not launch clausona"))
        }
        guard result.exitCode == 0 else {
            let firstLine = result.stderr.split(separator: "\n").first.map(String.init)
                ?? result.stdout.split(separator: "\n").first.map(String.init)
                ?? "clausona exited with status \(result.exitCode)"
            return .failure(CLIError(message: firstLine))
        }
        return .success(())
    }
}
```

- [ ] **Step 4: Run** `swift test --filter ClausonaCLITests` — expected PASS.
- [ ] **Step 5: Commit** `git add -A && git commit -m "feat: ClausonaCLI locate/use/repair/doctor"`

### Task 11: UsageFetcher

**Files:**
- Create: `Sources/ClausonaGUI/Core/UsageFetcher.swift`
- Test: `Tests/ClausonaGUITests/UsageFetcherTests.swift`

- [ ] **Step 1: Failing tests** — injected transport; assert headers, status mapping, decode:

```swift
import XCTest
@testable import ClausonaGUI

final class UsageFetcherTests: XCTestCase {
    private func response(_ status: Int) -> HTTPURLResponse {
        HTTPURLResponse(url: UsageFetcher.endpoint, statusCode: status, httpVersion: nil, headerFields: nil)!
    }

    func testSuccessSendsAuthAndBetaHeaders() async {
        let body = #"{ "five_hour": { "utilization": 12.0, "resets_at": null } }"#
        nonisolated(unsafe) var captured: URLRequest?
        let fetcher = UsageFetcher { request in
            captured = request
            return (Data(body.utf8), self.response(200))
        }
        let result = await fetcher.fetch(token: "tok-123")
        XCTAssertEqual(try? result.get().fiveHour?.utilization, 12)
        XCTAssertEqual(captured?.value(forHTTPHeaderField: "Authorization"), "Bearer tok-123")
        XCTAssertEqual(captured?.value(forHTTPHeaderField: "anthropic-beta"), "oauth-2025-04-20")
        XCTAssertEqual(captured?.timeoutInterval, 15)
    }

    func testHTTPErrorMapped() async {
        let fetcher = UsageFetcher { _ in (Data(), self.response(401)) }
        let result = await fetcher.fetch(token: "t")
        XCTAssertEqual(result, .failure(.http(401)))
        XCTAssertEqual(UsageError.http(401).message, "HTTP 401")
    }

    func testMalformedBody() async {
        let fetcher = UsageFetcher { _ in (Data("nope".utf8), self.response(200)) }
        XCTAssertEqual(await fetcher.fetch(token: "t"), .failure(.malformed))
    }

    func testNetworkErrorMapped() async {
        struct Boom: Error {}
        let fetcher = UsageFetcher { _ in throw Boom() }
        guard case .failure(.network) = await fetcher.fetch(token: "t") else { return XCTFail() }
    }
}
```

- [ ] **Step 2: Run** `swift test --filter UsageFetcherTests` — expected FAIL.

- [ ] **Step 3: Implement**

```swift
import Foundation

public enum UsageError: Error, Equatable, Sendable {
    case http(Int)
    case network(String)
    case malformed

    public var message: String {
        switch self {
        case .http(let code): "HTTP \(code)"
        case .network: "network error"
        case .malformed: "unexpected response"
        }
    }
}

public struct UsageFetcher: Sendable {
    public static let endpoint = URL(string: "https://api.anthropic.com/api/oauth/usage")!

    public var transport: @Sendable (URLRequest) async throws -> (Data, URLResponse)

    public init(transport: @escaping @Sendable (URLRequest) async throws -> (Data, URLResponse)) {
        self.transport = transport
    }

    public static let live = UsageFetcher { try await URLSession.shared.data(for: $0) }

    public func fetch(token: String) async -> Result<UsageReport, UsageError> {
        var request = URLRequest(url: Self.endpoint)
        request.timeoutInterval = 15
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("oauth-2025-04-20", forHTTPHeaderField: "anthropic-beta")
        do {
            let (data, response) = try await transport(request)
            let status = (response as? HTTPURLResponse)?.statusCode ?? 0
            guard status == 200 else { return .failure(.http(status)) }
            guard let report = try? UsageReport.decode(data) else { return .failure(.malformed) }
            return .success(report)
        } catch {
            return .failure(.network(error.localizedDescription))
        }
    }
}
```

- [ ] **Step 4: Run** `swift test --filter UsageFetcherTests` — expected PASS.
- [ ] **Step 5: Commit** `git add -A && git commit -m "feat: usage endpoint fetcher with injectable transport"`

### Task 12: ProfileSnapshot + AppDependencies + AppModel

**Files:**
- Create: `Sources/ClausonaGUI/Model/ProfileSnapshot.swift`, `Sources/ClausonaGUI/Core/AppDependencies.swift`, `Sources/ClausonaGUI/Core/AppModel.swift`
- Test: `Tests/ClausonaGUITests/AppModelTests.swift`

- [ ] **Step 1: Write models + dependencies (compile-only, no behavior yet)**

`Model/ProfileSnapshot.swift`:
```swift
import Foundation

public enum UsageState: Equatable, Sendable {
    case loading
    case ok(UsageReport)
    case error(message: String, lastGood: UsageReport?)

    public var lastGoodReport: UsageReport? {
        switch self {
        case .loading: nil
        case .ok(let report): report
        case .error(_, let lastGood): lastGood
        }
    }
}

public struct ProfileSnapshot: Equatable, Sendable, Identifiable {
    public var id: String { name }
    public let name: String
    public let email: String?
    public var isActive: Bool
    public var usage: UsageState
    public var health: HealthStatus
    public var isRepairing: Bool

    public init(name: String, email: String?, isActive: Bool,
                usage: UsageState, health: HealthStatus, isRepairing: Bool) {
        self.name = name
        self.email = email
        self.isActive = isActive
        self.usage = usage
        self.health = health
        self.isRepairing = isRepairing
    }
}
```

`Core/AppDependencies.swift`:
```swift
import Foundation
import ServiceManagement

public struct CLIActions: Sendable {
    public var use: @Sendable (String) async -> Result<Void, CLIError>
    public var repair: @Sendable (String) async -> Result<Void, CLIError>
    public var doctor: @Sendable () async -> String?

    public init(use: @escaping @Sendable (String) async -> Result<Void, CLIError>,
                repair: @escaping @Sendable (String) async -> Result<Void, CLIError>,
                doctor: @escaping @Sendable () async -> String?) {
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
    public var launchAtLoginStatus: @Sendable () -> Bool
    public var setLaunchAtLogin: @Sendable (Bool) throws -> Void
    public var now: @Sendable () -> Date

    public init(loadProfiles: @escaping @Sendable () -> ProfilesFile?,
                token: @escaping @Sendable (Profile) async -> TokenResult,
                fetchUsage: @escaping @Sendable (String) async -> Result<UsageReport, UsageError>,
                cli: CLIActions?,
                launchAtLoginStatus: @escaping @Sendable () -> Bool = { SMAppService.mainApp.status == .enabled },
                setLaunchAtLogin: @escaping @Sendable (Bool) throws -> Void = { enabled in
                    if enabled { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
                },
                now: @escaping @Sendable () -> Date = { Date() }) {
        self.loadProfiles = loadProfiles
        self.token = token
        self.fetchUsage = fetchUsage
        self.cli = cli
        self.launchAtLoginStatus = launchAtLoginStatus
        self.setLaunchAtLogin = setLaunchAtLogin
        self.now = now
    }

    public static func live() -> AppDependencies {
        let store = ProfileStore()
        let provider = TokenProvider.live()
        let fetcher = UsageFetcher.live
        let cli = ClausonaCLI.locate().map { path in
            let cli = ClausonaCLI(binaryPath: path)
            return CLIActions(use: { await cli.use(profile: $0) },
                              repair: { await cli.repair(profile: $0) },
                              doctor: { await cli.doctor() })
        }
        return AppDependencies(
            loadProfiles: { store.load() },
            token: { await provider.token(forConfigDir: $0.configDir) },
            fetchUsage: { await fetcher.fetch(token: $0) },
            cli: cli)
    }
}
```

- [ ] **Step 2: Failing tests for AppModel**

```swift
import XCTest
@testable import ClausonaGUI

@MainActor
final class AppModelTests: XCTestCase {
    static let now = Date(timeIntervalSince1970: 2_000_000)

    private func file(active: String = "personal", names: [String] = ["personal", "work"]) -> ProfilesFile {
        ProfilesFile(activeProfile: active,
                     profiles: names.map { Profile(name: $0, configDir: "/d/\($0)", email: nil, orgName: nil, isPrimary: false) })
    }

    private func report(_ pct: Int) -> UsageReport {
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
        let model = AppModel(deps: deps(profiles: file(), fetch: { _ in .success(self.report(42)) }))
        await model.refreshUsage()
        XCTAssertEqual(model.setupState, .ready)
        XCTAssertEqual(model.snapshots.map(\.name), ["personal", "work"])
        XCTAssertEqual(model.snapshots[0].isActive, true)
        XCTAssertEqual(model.snapshots[1].isActive, false)
        XCTAssertEqual(model.snapshots[0].usage, .ok(report(42)))
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
            fail ? .failure(.http(401)) : .success(self.report(42))
        }))
        await model.refreshUsage()
        fail = true
        await model.refreshUsage()
        XCTAssertEqual(model.snapshots[0].usage, .error(message: "HTTP 401", lastGood: report(42)))
        XCTAssertEqual(model.lastUpdated, Self.now)  // from the first, successful cycle
    }

    func testSwitchOptimisticThenRevertOnFailure() async {
        let cli = CLIActions(use: { _ in .failure(CLIError(message: "boom")) },
                             repair: { _ in .success(()) }, doctor: { nil })
        let model = AppModel(deps: deps(profiles: file(), cli: cli))
        await model.refreshUsage()
        await model.switchProfile("work")
        XCTAssertEqual(model.snapshots.first(where: { $0.name == "personal" })?.isActive, true)  // reverted
        XCTAssertEqual(model.toast, "boom")
    }

    func testSwitchSuccessMovesActive() async {
        let cli = CLIActions(use: { _ in .success(()) }, repair: { _ in .success(()) }, doctor: { nil })
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
        let cli = CLIActions(use: { _ in .success(()) }, repair: { _ in .success(()) }, doctor: { doctorOutput })
        let model = AppModel(deps: deps(profiles: file(), cli: cli))
        await model.refreshUsage()
        await model.refreshHealth()
        XCTAssertEqual(model.snapshots[0].health, .healthy)
        XCTAssertEqual(model.snapshots[1].health, .unknown)
    }

    func testRepairFailureSetsToast() async {
        let cli = CLIActions(use: { _ in .success(()) },
                             repair: { _ in .failure(CLIError(message: "repair broke")) },
                             doctor: { nil })
        let model = AppModel(deps: deps(profiles: file(), cli: cli))
        await model.refreshUsage()
        await model.repair("work")
        XCTAssertEqual(model.toast, "repair broke")
        XCTAssertEqual(model.snapshots.first(where: { $0.name == "work" })?.isRepairing, false)
    }

    func testCliAvailabilityFlag() {
        XCTAssertFalse(AppModel(deps: deps()).cliAvailable)
        let cli = CLIActions(use: { _ in .success(()) }, repair: { _ in .success(()) }, doctor: { nil })
        XCTAssertTrue(AppModel(deps: deps(cli: cli)).cliAvailable)
    }
}
```

- [ ] **Step 3: Run** `swift test --filter AppModelTests` — expected FAIL (AppModel undefined).

- [ ] **Step 4: Implement AppModel**

```swift
import Foundation
import Observation

@MainActor @Observable
public final class AppModel {
    public enum SetupState: Equatable {
        case loading, notSetUp, ready
    }

    public private(set) var setupState: SetupState = .loading
    public private(set) var snapshots: [ProfileSnapshot] = []
    public private(set) var activeProfile: String?
    public private(set) var lastUpdated: Date?
    public private(set) var isRefreshing = false
    public private(set) var launchAtLoginEnabled = false
    public var toast: String?

    public let cliAvailable: Bool
    public static let pollInterval: TimeInterval = 300

    private let deps: AppDependencies

    public init(deps: AppDependencies) {
        self.deps = deps
        self.cliAvailable = deps.cli != nil
    }

    public var isStale: Bool {
        Staleness.isStale(lastSuccess: lastUpdated, now: deps.now(), pollInterval: Self.pollInterval)
    }

    public func popoverDidOpen() {
        refreshLaunchAtLogin()
        Task { await refreshUsage() }
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
        let outcomes = await withTaskGroup(of: (String, FetchOutcome).self,
                                           returning: [String: FetchOutcome].self) { group in
            for profile in file.profiles {
                group.addTask {
                    switch await deps.token(profile) {
                    case .missing:
                        return (profile.name, .failed("no credentials found"))
                    case .expired:
                        return (profile.name, .failed("login needed — clausona login \(profile.name)"))
                    case .ok(let token):
                        switch await deps.fetchUsage(token.accessToken) {
                        case .success(let report): return (profile.name, .ok(report))
                        case .failure(let error): return (profile.name, .failed(error.message))
                        }
                    }
                }
            }
            var collected: [String: FetchOutcome] = [:]
            for await (name, outcome) in group { collected[name] = outcome }
            return collected
        }

        var anySuccess = false
        for index in snapshots.indices {
            switch outcomes[snapshots[index].name] {
            case .ok(let report):
                snapshots[index].usage = .ok(report)
                anySuccess = true
            case .failed(let message):
                snapshots[index].usage = .error(message: message,
                                                lastGood: snapshots[index].usage.lastGoodReport)
            case nil:
                break
            }
        }
        if anySuccess { lastUpdated = deps.now() }
    }

    private func mergeProfiles(_ file: ProfilesFile) {
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
        guard let cli = deps.cli, let output = await cli.doctor() else { return }
        let statuses = DoctorParser.parse(output)
        for index in snapshots.indices {
            snapshots[index].health = statuses[snapshots[index].name] ?? .unknown
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
```

- [ ] **Step 5: Run** `swift test --filter AppModelTests` — expected PASS. Then `swift test` (full suite) — expected all PASS.
- [ ] **Step 6: Commit** `git add -A && git commit -m "feat: AppModel state machine with injected dependencies"`

### Task 13: SwiftUI popover UI

**Files:**
- Create: `Sources/ClausonaGUI/UI/PopoverView.swift`, `UI/ProfileRowView.swift`, `UI/FooterView.swift`, `UI/EmptyStateView.swift`, `UI/ToastView.swift`

No unit tests (pure view code); verification is `swift build` + the manual checklist in Task 16. Polish notes: monospaced digits for the limit segments, hover highlight on rows, `Use`/`Repair` appear on hover, health-dot tooltips list the doctor issues, toast auto-dismisses.

- [ ] **Step 1: PopoverView**

```swift
import SwiftUI

public struct PopoverView: View {
    let model: AppModel

    public init(model: AppModel) { self.model = model }

    public var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("clausona usage limits")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.secondary)
                .padding(.horizontal, 16)
                .padding(.top, 12)
                .padding(.bottom, 8)

            switch model.setupState {
            case .loading:
                ProgressView()
                    .controlSize(.small)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 28)
            case .notSetUp:
                EmptyStateView(
                    title: "clausona is not set up",
                    hint: "Run `clausona init` in a terminal to get started.")
            case .ready:
                VStack(spacing: 1) {
                    ForEach(model.snapshots) { snapshot in
                        ProfileRowView(snapshot: snapshot, model: model)
                    }
                }
                .padding(.horizontal, 8)
            }

            Divider()
                .padding(.top, 10)
            FooterView(model: model)
        }
        .frame(width: 420)
        .overlay(alignment: .bottom) { ToastView(model: model) }
    }
}
```

- [ ] **Step 2: ProfileRowView**

```swift
import SwiftUI

struct ProfileRowView: View {
    let snapshot: ProfileSnapshot
    let model: AppModel
    @State private var hovering = false

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "arrowtriangle.right.fill")
                .font(.system(size: 7))
                .foregroundStyle(.primary)
                .opacity(snapshot.isActive ? 1 : 0)
                .frame(width: 10)

            healthDot

            Text(snapshot.name)
                .font(.system(size: 12, weight: snapshot.isActive ? .semibold : .regular))
                .lineLimit(1)

            Spacer(minLength: 8)

            usageContent

            actionButton
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 5)
        .background(RoundedRectangle(cornerRadius: 6)
            .fill(hovering ? Color.primary.opacity(0.07) : .clear))
        .onHover { hovering = $0 }
    }

    private var healthDot: some View {
        Group {
            if snapshot.isRepairing {
                ProgressView()
                    .controlSize(.mini)
            } else {
                Circle()
                    .fill(dotColor)
                    .frame(width: 7, height: 7)
            }
        }
        .frame(width: 12, height: 12)
        .help(healthTooltip)
    }

    private var dotColor: Color {
        switch snapshot.health {
        case .healthy: .green
        case .issues: .red
        case .unknown: .gray
        }
    }

    private var healthTooltip: String {
        switch snapshot.health {
        case .healthy: "Healthy"
        case .issues(let issues): issues.joined(separator: "\n")
        case .unknown: "Health unknown"
        }
    }

    @ViewBuilder private var usageContent: some View {
        switch snapshot.usage {
        case .loading:
            Text("…")
                .font(.system(size: 11))
                .foregroundStyle(.tertiary)
        case .ok(let report):
            segments(report)
        case .error(let message, let lastGood):
            if let lastGood {
                segments(lastGood)
                Text(message)
                    .font(.system(size: 10))
                    .foregroundStyle(.tertiary)
                    .lineLimit(1)
            } else {
                Text(message)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
    }

    private func segments(_ report: UsageReport) -> some View {
        HStack(spacing: 10) {
            segment(label: "5h", window: report.fiveHour)
            segment(label: "7d", window: report.sevenDay)
        }
    }

    private func segment(label: String, window: UsageWindow?) -> some View {
        HStack(spacing: 3) {
            Text(label)
                .foregroundStyle(.secondary)
            if let window {
                Text("\(window.utilization)%")
                    .fontWeight(.medium)
                    .foregroundStyle(percentColor(window.utilization))
                Text(resetText(window.resetsAt))
                    .foregroundStyle(.tertiary)
            } else {
                Text("—")
                    .foregroundStyle(.tertiary)
            }
        }
        .font(.system(size: 11, design: .monospaced))
    }

    private func resetText(_ resetsAt: Date?) -> String {
        guard let resetsAt else { return "" }
        return "(\(Formatting.duration(seconds: Int(resetsAt.timeIntervalSinceNow))))"
    }

    private func percentColor(_ percent: Int) -> Color {
        switch UsageSeverity(percent: percent) {
        case .normal: .green
        case .elevated: .orange
        case .critical: .red
        }
    }

    @ViewBuilder private var actionButton: some View {
        if hovering && model.cliAvailable {
            if case .issues = snapshot.health, !snapshot.isRepairing {
                Button("Repair") {
                    Task { await model.repair(snapshot.name) }
                }
                .controlSize(.small)
                .help("Runs `clausona repair \(snapshot.name)`")
            } else if !snapshot.isActive {
                Button("Use") {
                    Task { await model.switchProfile(snapshot.name) }
                }
                .controlSize(.small)
                .help("Runs `clausona use \(snapshot.name)` — affects new terminals only")
            }
        }
    }
}
```

- [ ] **Step 3: FooterView**

```swift
import SwiftUI

struct FooterView: View {
    let model: AppModel

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                TimelineView(.periodic(from: .now, by: 30)) { _ in
                    Text(updatedText)
                        .font(.system(size: 11))
                        .foregroundStyle(model.isStale ? AnyShapeStyle(.orange) : AnyShapeStyle(.secondary))
                }
                if model.isRefreshing {
                    ProgressView()
                        .controlSize(.mini)
                }
                Button {
                    Task { await model.refreshUsage() }
                } label: {
                    Label("Refresh", systemImage: "arrow.clockwise")
                        .font(.system(size: 11))
                }
                .buttonStyle(.borderless)
                .disabled(model.isRefreshing)
                Spacer()
            }

            HStack {
                Toggle("Launch at Login", isOn: Binding(
                    get: { model.launchAtLoginEnabled },
                    set: { model.setLaunchAtLogin($0) }))
                    .toggleStyle(.checkbox)
                    .font(.system(size: 11))
                Spacer()
                Button("Quit") { NSApp.terminate(nil) }
                    .controlSize(.small)
                    .keyboardShortcut("q")
            }

            if !model.cliAvailable {
                Text("clausona CLI not found — switching and repair disabled")
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
    }

    private var updatedText: String {
        guard let lastUpdated = model.lastUpdated else { return "Not updated yet" }
        let seconds = Int(Date().timeIntervalSince(lastUpdated))
        return "Updated \(Formatting.updatedAgo(seconds: max(0, seconds)))"
    }
}
```

- [ ] **Step 4: EmptyStateView + ToastView**

```swift
import SwiftUI

struct EmptyStateView: View {
    let title: String
    let hint: String

    var body: some View {
        VStack(spacing: 6) {
            Image(systemName: "person.crop.circle.badge.questionmark")
                .font(.system(size: 28))
                .foregroundStyle(.tertiary)
            Text(title)
                .font(.system(size: 12, weight: .medium))
            Text(LocalizedStringKey(hint))   // renders the backtick code span
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 24)
        .padding(.horizontal, 16)
    }
}
```

```swift
import SwiftUI

struct ToastView: View {
    let model: AppModel

    var body: some View {
        if let toast = model.toast {
            Text(toast)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(.white)
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(Color.red.opacity(0.92), in: Capsule())
                .padding(.bottom, 10)
                .transition(.move(edge: .bottom).combined(with: .opacity))
                .id(toast)
                .task {
                    try? await Task.sleep(for: .seconds(4))
                    model.toast = nil
                }
        }
    }
}
```

- [ ] **Step 5: Build** `swift build` — expected: succeeds with no warnings about the new files.
- [ ] **Step 6: Commit** `git add -A && git commit -m "feat: popover UI (rows, footer, empty state, toast)"`

### Task 14: App layer (status item, hotkey, scheduler, delegate, main)

**Files:**
- Create: `Sources/ClausonaGUI/App/StatusItemController.swift`, `App/HotkeyManager.swift`, `Sources/ClausonaGUI/Core/RefreshScheduler.swift`, `App/AppDelegate.swift`
- Modify: `Sources/ClausonaApp/main.swift`

- [ ] **Step 1: StatusItemController**

```swift
import AppKit
import SwiftUI

@MainActor
public final class StatusItemController: NSObject, NSPopoverDelegate {
    private let statusItem: NSStatusItem
    private let popover = NSPopover()
    private let model: AppModel

    public init(model: AppModel) {
        self.model = model
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        super.init()

        if let button = statusItem.button {
            let image = NSImage(systemSymbolName: "gauge.with.needle", accessibilityDescription: "Clausona")
                ?? NSImage(systemSymbolName: "speedometer", accessibilityDescription: "Clausona")
            image?.isTemplate = true
            button.image = image
            button.target = self
            button.action = #selector(statusButtonClicked)
        }

        popover.behavior = .transient
        popover.animates = false
        popover.delegate = self
        popover.contentViewController = NSHostingController(rootView: PopoverView(model: model))
    }

    @objc private func statusButtonClicked() {
        toggle()
    }

    public func toggle() {
        if popover.isShown { close() } else { show() }
    }

    private func show() {
        guard let button = statusItem.button else { return }
        model.popoverDidOpen()
        popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
        popover.contentViewController?.view.window?.makeKey()
        NSApp.activate()
        button.highlight(true)
    }

    public func close() {
        popover.performClose(nil)
    }

    public func popoverDidClose(_ notification: Notification) {
        statusItem.button?.highlight(false)
    }
}
```

- [ ] **Step 2: HotkeyManager** (Carbon; the one place `kHotkey` lives)

```swift
import AppKit
import Carbon.HIToolbox

/// Fixed global hotkey ⌃⌥⌘L via Carbon RegisterEventHotKey — no accessibility
/// permission needed, unlike CGEventTap.
@MainActor
public final class HotkeyManager {
    /// The hotkey, in one place: ⌃⌥⌘ + L.
    private static let kHotkeyKeyCode = UInt32(kVK_ANSI_L)
    private static let kHotkeyModifiers = UInt32(controlKey | optionKey | cmdKey)

    private var hotKeyRef: EventHotKeyRef?
    private var eventHandlerRef: EventHandlerRef?
    private let onPress: () -> Void

    public init(onPress: @escaping () -> Void) {
        self.onPress = onPress
    }

    /// Returns false when registration fails (combo taken) — caller logs and
    /// continues; the menu bar icon still works.
    @discardableResult
    public func register() -> Bool {
        var eventType = EventTypeSpec(eventClass: OSType(kEventClassKeyboard),
                                      eventKind: UInt32(kEventHotKeyPressed))
        let selfPointer = Unmanaged.passUnretained(self).toOpaque()
        guard InstallEventHandler(GetEventDispatcherTarget(), hotkeyEventCallback, 1,
                                  &eventType, selfPointer, &eventHandlerRef) == noErr else {
            return false
        }
        let hotKeyID = EventHotKeyID(signature: OSType(0x434C_534E) /* "CLSN" */, id: 1)
        let status = RegisterEventHotKey(Self.kHotkeyKeyCode, Self.kHotkeyModifiers,
                                         hotKeyID, GetApplicationEventTarget(), 0, &hotKeyRef)
        return status == noErr
    }

    fileprivate func fire() {
        onPress()
    }
}

private func hotkeyEventCallback(_ handler: EventHandlerCallRef?,
                                 _ event: EventRef?,
                                 _ userData: UnsafeMutableRawPointer?) -> OSStatus {
    guard let userData else { return noErr }
    let manager = Unmanaged<HotkeyManager>.fromOpaque(userData).takeUnretainedValue()
    // Carbon dispatches hotkey events on the main thread.
    MainActor.assumeIsolated { manager.fire() }
    return noErr
}
```

- [ ] **Step 3: RefreshScheduler**

```swift
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
```

- [ ] **Step 4: AppDelegate + main.swift**

`App/AppDelegate.swift`:
```swift
import AppKit

@MainActor
public final class AppDelegate: NSObject, NSApplicationDelegate {
    private var model: AppModel?
    private var statusController: StatusItemController?
    private var hotkey: HotkeyManager?
    private var scheduler: RefreshScheduler?

    public func applicationDidFinishLaunching(_ notification: Notification) {
        let model = AppModel(deps: .live())
        self.model = model

        let controller = StatusItemController(model: model)
        statusController = controller

        let hotkey = HotkeyManager { [weak controller] in
            controller?.toggle()
        }
        if !hotkey.register() {
            NSLog("ClausonaGUI: ⌃⌥⌘L registration failed (combo already taken?) — menu bar icon still works")
        }
        self.hotkey = hotkey

        let scheduler = RefreshScheduler(
            onUsageTick: { Task { await model.refreshUsage() } },
            onHealthTick: { Task { await model.refreshHealth() } })
        scheduler.start()
        self.scheduler = scheduler

        model.refreshLaunchAtLogin()
        Task {
            await model.refreshUsage()
            await model.refreshHealth()
        }
    }
}
```

`Sources/ClausonaApp/main.swift`:
```swift
import AppKit
import ClausonaGUI

let app = NSApplication.shared
app.setActivationPolicy(.accessory)
let delegate = AppDelegate()
app.delegate = delegate
app.run()
```

- [ ] **Step 5: Build and smoke-run**

```bash
swift build && swift test
.build/debug/ClausonaApp &
```
Expected: gauge icon appears in the menu bar; clicking opens the popover with real profile data; ⌃⌥⌘L toggles it. Kill with `kill %1` after checking. (Launch-at-login toggle is expected to fail politely outside a bundle — verified properly in Task 16.)

- [ ] **Step 6: Commit** `git add -A && git commit -m "feat: AppKit lifecycle — status item, Carbon hotkey, scheduler"`

### Task 15: App bundle + Makefile

**Files:**
- Create: `Resources/Info.plist`, `Makefile`

- [ ] **Step 1: Info.plist**

```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleDevelopmentRegion</key>
    <string>en</string>
    <key>CFBundleExecutable</key>
    <string>ClausonaApp</string>
    <key>CFBundleIdentifier</key>
    <string>com.bernardocabral.clausona</string>
    <key>CFBundleInfoDictionaryVersion</key>
    <string>6.0</string>
    <key>CFBundleName</key>
    <string>Clausona</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>CFBundleShortVersionString</key>
    <string>0.1.0</string>
    <key>CFBundleVersion</key>
    <string>1</string>
    <key>LSMinimumSystemVersion</key>
    <string>14.0</string>
    <key>LSUIElement</key>
    <true/>
    <key>NSHumanReadableCopyright</key>
    <string>© 2026 Bernardo Cabral</string>
</dict>
</plist>
```

- [ ] **Step 2: Makefile** (tabs, not spaces, for recipe lines)

```make
APP_NAME = Clausona.app
BUNDLE = dist/$(APP_NAME)
BINARY = .build/release/ClausonaApp

.PHONY: build app install clean test

build:
	swift build -c release

test:
	swift test

app: build
	rm -rf $(BUNDLE)
	mkdir -p $(BUNDLE)/Contents/MacOS
	cp Resources/Info.plist $(BUNDLE)/Contents/Info.plist
	cp $(BINARY) $(BUNDLE)/Contents/MacOS/ClausonaApp
	codesign --force --sign - $(BUNDLE)

install: app
	rm -rf ~/Applications/$(APP_NAME)
	mkdir -p ~/Applications
	cp -R $(BUNDLE) ~/Applications/
	@echo "Installed to ~/Applications/$(APP_NAME)"

clean:
	rm -rf .build dist
```

- [ ] **Step 3: Build the bundle** `make install` — expected: app at `~/Applications/Clausona.app`, `codesign -dv ~/Applications/Clausona.app` shows ad-hoc signature.
- [ ] **Step 4: Launch** `open ~/Applications/Clausona.app` — icon appears, no Dock icon.
- [ ] **Step 5: Commit** `git add -A && git commit -m "feat: Clausona.app bundle assembly + install target"`

### Task 16: Verification (manual checklist + full suite)

- [ ] **Step 1: Full test suite** `swift test` — all green; record count.
- [ ] **Step 2: Manual checklist against the running bundled app:**
  - Click icon → popover opens with all 5 profiles, cached data instant, fresh within ~2 s; icon highlighted while open.
  - ⌃⌥⌘L toggles open/closed.
  - Profile rows show 5h/7d % + countdown, colors by thresholds; `personal` shows the expired-token "login needed — clausona login personal" row (known state).
  - Health dots reflect `clausona doctor`; hover tooltip lists issues.
  - Hover non-active row → `Use`; click; ▸ moves; `clausona current` agrees. Switch back afterwards.
  - Hover red-dot row → `Repair`; click; spinner; doctor re-run clears the repairable issues.
  - Launch at Login toggle on → `SMAppService` registered (check System Settings → Login Items or `sfltool dumpbtm | grep -i clausona`); toggle off.
  - Degraded: `CLAUSONA_HOME=/tmp/nonexistent ~/Applications/Clausona.app/Contents/MacOS/ClausonaApp` → "clausona is not set up" empty state.
  - Degraded: run with PATH stripped and a fake HOME? Not feasible — instead temporarily test CLI-missing mode by injecting `ClausonaCLI.locate` failure: rename check is destructive; acceptable alternative: code-review the `cli == nil` path + unit tests already cover it. Do NOT rename the real clausona binary without putting it back.
  - No permission prompts during any of the above (keychain ACL pre-authorized for `security`).
- [ ] **Step 3: Update spec status / README note if needed; final commit.**

---

## Self-review notes

- Spec coverage: ProfileStore→T3, TokenProvider→T5/T7, UsageFetcher→T4/T11, HealthChecker→T8 (+CLI doctor in T10), ClausonaCLI→T10, RefreshScheduler→T14 (staleness logic unit-tested in T9), HotkeyManager→T14, Launch at Login→T12 (deps) + T13 (toggle UI), UI→T13, error-handling table→T7/T11/T12 tests, build & distribution→T15, success criteria→T16.
- Known intentional deviations: CLI "yellow" → SwiftUI `.orange` for legibility; `updatedAgo` says "just now" under a minute.
- Type names used consistently: `UsageReport`, `UsageWindow`, `UsageState`, `TokenResult`, `CLIError`, `CLIActions`, `AppDependencies`, `ProfileSnapshot`, `HealthStatus`, `UsageSeverity`.
