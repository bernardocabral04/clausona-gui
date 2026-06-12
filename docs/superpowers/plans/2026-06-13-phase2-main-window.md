# Clausona GUI Phase 2 — Main Window Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** A resizable main window with a usage/cost dashboard (Swift Charts over `usage.json`, live-updating), per-profile detail panels, and a doctor view with repair actions — opened from the popover footer.

**Architecture:** Reuses Phase 1's `AppModel` as the shared source of truth (snapshots, health, repair/use); adds a `UsageStore` (`@Observable`) that loads/watches/aggregates `usage.json` via pure, unit-tested functions (`UsageLog`, `UsageRange`, `UsageMath`) and a `FileWatcher` (DispatchSource). `MainWindowController` owns a singleton `NSWindow` hosting `MainWindowView` (NavigationSplitView: Dashboard / Profiles / Doctor) and flips activation policy `.accessory`↔`.regular` on open/close.

**Tech Stack:** Swift 6, SwiftPM, macOS 14+, SwiftUI + Swift Charts (system framework), AppKit window management, XCTest.

**Spec:** `docs/superpowers/specs/2026-06-12-phase2-main-window-design.md`

---

## Verified ground truth (collected 2026-06-13)

- `~/.clausona/usage.json` shape: `{ "<profile>": { "records": [ { "ts": "2026-06-11T16:30:49+01:00", "tz": "+01:00", "cost": 144.376668, "inputTokens": 106840, "outputTokens": 485753 } ], "seenSessions": … } }`. `ts` is ISO8601 **with offset, no fractional seconds** (offsets vary per record: `+00:00`, `+01:00`). All current records have all 5 keys.
- clausona's `cutoffForPeriod` (from `~/.local/share/clausona/index.js`, src/core/usage.ts): local midnight today; **week → back to Monday** (`delta = weekday===0 ? 6 : weekday-1`); month → 1st of month; all → no cutoff. Records included when `ts >= cutoff`, **no upper bound**. The `6/6 – 6/13` header in `clausona list` is a cosmetic trailing-7-days string — totals use the Monday week. "This week" must mirror the Monday logic to satisfy success criterion 1.
- "Last week" doesn't exist in clausona; define as `[monday-7d, monday)` (bounded).
- Phase 1 `DoctorParser` already stores each issue's verbatim text in `HealthStatus.issues([String])` — no parser change needed. What's missing for the Doctor view: stderr when the doctor *run* fails (currently `ClausonaCLI.doctor()` returns `String?`).
- Phase 1 `AppModel` discards token expiry after fetching usage; profile detail needs it → capture a `CredentialStatus` per snapshot during `refreshUsage()`.

## File structure

```
Sources/ClausonaGUI/
├── Model/UsageRecord.swift                    — UsageRecord, ProfileTotals, DailyProfileCost, UsageLog.decode
├── Model/ProfileSnapshot.swift                — MODIFY: add CredentialStatus + snapshot field
├── Core/UsageRange.swift                      — range enum + Monday-week interval math
├── Core/UsageMath.swift                       — totals + per-day-per-profile aggregation
├── Core/Formatting.swift                      — MODIFY: add cost/tokens formatters
├── Core/FileWatcher.swift                     — DispatchSource watcher, survives atomic replace
├── Core/ClausonaCLI.swift                     — MODIFY: doctor() → Result<String, CLIError>
├── Core/AppDependencies.swift                 — MODIFY: CLIActions.doctor type
├── Core/AppModel.swift                        — MODIFY: credential capture, doctorError, totalIssueCount, onOpenMainWindow
├── MainWindow/MainWindowController.swift      — NSWindow singleton, frame autosave, policy flip
├── MainWindow/MainWindowView.swift            — NavigationSplitView root + MainSection + SidebarView
├── MainWindow/Dashboard/UsageStore.swift      — load + watch + aggregate (@Observable)
├── MainWindow/Dashboard/DashboardView.swift   — range picker, stacked bar chart, totals table
├── MainWindow/Profiles/ProfileDetailView.swift
├── MainWindow/Doctor/DoctorView.swift
├── UI/FooterView.swift                        — MODIFY: "Open Clausona…" button
├── App/AppDelegate.swift                      — MODIFY: wire MainWindowController (+ --window debug flag)
Tests/ClausonaGUITests/
├── UsageLogTests.swift, UsageRangeTests.swift, UsageMathTests.swift,
├── FileWatcherTests.swift, UsageStoreTests.swift
├── FormattingTests.swift (extend), ClausonaCLITests.swift (doctor change), AppModelTests.swift (extend)
```

---

### Task 0: Branch

- [ ] **Step 1:** `git checkout -b phase2-main-window`

### Task 1: UsageRecord + UsageLog decoding

**Files:**
- Create: `Sources/ClausonaGUI/Model/UsageRecord.swift`
- Test: `Tests/ClausonaGUITests/UsageLogTests.swift`

- [ ] **Step 1: Failing tests** (real-shape fixture; malformed record skipped; garbage throws; missing profile records tolerated; offset parsing checked against calendar-built dates, not raw epochs):

```swift
import XCTest
@testable import ClausonaGUI

final class UsageLogTests: XCTestCase {
    static let lisbon: Calendar = {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "Europe/Lisbon")!
        return cal
    }()

    static func date(_ y: Int, _ mo: Int, _ d: Int, _ h: Int = 0, _ mi: Int = 0, _ s: Int = 0) -> Date {
        lisbon.date(from: DateComponents(year: y, month: mo, day: d, hour: h, minute: mi, second: s))!
    }

    func testRealShape() throws {
        let json = """
        {
          "personal": {
            "records": [
              { "ts": "2026-05-12T19:56:52+00:00", "tz": "+00:00", "cost": 0.128298, "inputTokens": 694, "outputTokens": 340 },
              { "ts": "2026-06-11T16:30:49+01:00", "tz": "+01:00", "cost": 144.376668, "inputTokens": 106840, "outputTokens": 485753 }
            ],
            "seenSessions": ["abc"]
          },
          "work": { "records": [], "seenSessions": [] }
        }
        """
        let log = try UsageLog.decode(Data(json.utf8))
        XCTAssertEqual(log.keys.sorted(), ["personal", "work"])
        XCTAssertEqual(log["personal"]?.count, 2)
        // May 12 19:56:52Z == 20:56:52 Lisbon (WEST, +01:00)
        XCTAssertEqual(log["personal"]?[0].ts, Self.date(2026, 5, 12, 20, 56, 52))
        XCTAssertEqual(log["personal"]?[0].cost, 0.128298)
        XCTAssertEqual(log["personal"]?[1].ts, Self.date(2026, 6, 11, 16, 30, 49))
        XCTAssertEqual(log["personal"]?[1].inputTokens, 106840)
        XCTAssertEqual(log["personal"]?[1].outputTokens, 485753)
        XCTAssertEqual(log["work"], [])
    }

    func testMalformedRecordSkippedNotFatal() throws {
        let json = """
        {
          "p": { "records": [
            { "ts": "2026-06-11T10:00:00+01:00", "cost": 1.5, "inputTokens": 1, "outputTokens": 2 },
            { "ts": "not a date", "cost": 9.9, "inputTokens": 1, "outputTokens": 2 },
            { "cost": 9.9 },
            "junk"
          ] }
        }
        """
        let log = try UsageLog.decode(Data(json.utf8))
        XCTAssertEqual(log["p"]?.count, 1)
        XCTAssertEqual(log["p"]?[0].cost, 1.5)
    }

    func testProfileWithoutRecordsTolerated() throws {
        let log = try UsageLog.decode(Data(#"{ "p": { "seenSessions": [] } }"#.utf8))
        XCTAssertEqual(log["p"], [])
    }

    func testGarbageThrows() {
        XCTAssertThrowsError(try UsageLog.decode(Data("nope".utf8)))
    }
}
```

- [ ] **Step 2: Run** `swift test --filter UsageLogTests` — expected FAIL (`UsageLog` undefined).

- [ ] **Step 3: Implement**

```swift
import Foundation

public struct UsageRecord: Equatable, Sendable {
    public let ts: Date
    public let cost: Double
    public let inputTokens: Int
    public let outputTokens: Int

    public init(ts: Date, cost: Double, inputTokens: Int, outputTokens: Int) {
        self.ts = ts
        self.cost = cost
        self.inputTokens = inputTokens
        self.outputTokens = outputTokens
    }
}

public struct ProfileTotals: Equatable, Sendable {
    public var cost: Double
    public var inputTokens: Int
    public var outputTokens: Int

    public static let zero = ProfileTotals(cost: 0, inputTokens: 0, outputTokens: 0)

    public init(cost: Double, inputTokens: Int, outputTokens: Int) {
        self.cost = cost
        self.inputTokens = inputTokens
        self.outputTokens = outputTokens
    }
}

public struct DailyProfileCost: Equatable, Sendable, Identifiable {
    public var id: String { "\(day.timeIntervalSince1970)-\(profile)" }
    public let day: Date
    public let profile: String
    public let cost: Double

    public init(day: Date, profile: String, cost: Double) {
        self.day = day
        self.profile = profile
        self.cost = cost
    }
}

/// Decodes ~/.clausona/usage.json. Tolerant per record: a malformed record is
/// skipped, never fatal (the file is owned by clausona; we only read it).
public enum UsageLog {
    public static func decode(_ data: Data) throws -> [String: [UsageRecord]] {
        // Lossy wrapper: a record that fails to decode becomes nil instead of
        // failing the whole array.
        struct Lossy: Decodable {
            let record: RawRecord?
            init(from decoder: Decoder) {
                record = try? RawRecord(from: decoder)
            }
        }
        struct RawRecord: Decodable {
            var ts: String
            var cost: Double
            var inputTokens: Int
            var outputTokens: Int
        }
        struct RawProfile: Decodable {
            var records: [Lossy]?
        }
        let raw = try JSONDecoder().decode([String: RawProfile].self, from: data)
        return raw.mapValues { profile in
            (profile.records ?? []).compactMap { lossy in
                guard let r = lossy.record, let ts = APIDate.parse(r.ts) else { return nil }
                return UsageRecord(ts: ts, cost: r.cost, inputTokens: r.inputTokens, outputTokens: r.outputTokens)
            }
        }
    }
}
```

(`APIDate.parse` from Phase 1 handles offsets and strips any fractional seconds.)

- [ ] **Step 4: Run** `swift test --filter UsageLogTests` — expected PASS.
- [ ] **Step 5: Commit** `git add -A && git commit -m "feat: usage.json decoding with per-record tolerance"`

### Task 2: UsageRange

**Files:**
- Create: `Sources/ClausonaGUI/Core/UsageRange.swift`
- Test: `Tests/ClausonaGUITests/UsageRangeTests.swift`

- [ ] **Step 1: Failing tests** (Monday math mirroring clausona, incl. Sunday/Monday edges; bounded last-week; open-ended this-month; nil all-time):

```swift
import XCTest
@testable import ClausonaGUI

final class UsageRangeTests: XCTestCase {
    static let lisbon: Calendar = {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "Europe/Lisbon")!
        return cal
    }()

    static func date(_ y: Int, _ mo: Int, _ d: Int, _ h: Int = 0) -> Date {
        lisbon.date(from: DateComponents(year: y, month: mo, day: d, hour: h))!
    }

    func testThisWeekFromSaturday() {
        let interval = UsageRange.thisWeek.interval(now: Self.date(2026, 6, 13, 12), calendar: Self.lisbon)
        XCTAssertEqual(interval?.start, Self.date(2026, 6, 8))          // Monday 00:00
        XCTAssertEqual(interval?.end, Date.distantFuture)
    }

    func testThisWeekSundayEdge() {
        let interval = UsageRange.thisWeek.interval(now: Self.date(2026, 6, 14, 23), calendar: Self.lisbon)
        XCTAssertEqual(interval?.start, Self.date(2026, 6, 8))          // Sunday still belongs to Mon 6/8 week
    }

    func testThisWeekMondayEdge() {
        let interval = UsageRange.thisWeek.interval(now: Self.date(2026, 6, 8, 0), calendar: Self.lisbon)
        XCTAssertEqual(interval?.start, Self.date(2026, 6, 8))
    }

    func testLastWeekBounded() {
        let interval = UsageRange.lastWeek.interval(now: Self.date(2026, 6, 13, 12), calendar: Self.lisbon)
        XCTAssertEqual(interval?.start, Self.date(2026, 6, 1))
        XCTAssertEqual(interval?.end, Self.date(2026, 6, 8))
    }

    func testThisMonth() {
        let interval = UsageRange.thisMonth.interval(now: Self.date(2026, 6, 13, 12), calendar: Self.lisbon)
        XCTAssertEqual(interval?.start, Self.date(2026, 6, 1))
        XCTAssertEqual(interval?.end, Date.distantFuture)
    }

    func testAllTimeIsNil() {
        XCTAssertNil(UsageRange.allTime.interval(now: Self.date(2026, 6, 13), calendar: Self.lisbon))
    }
}
```

- [ ] **Step 2: Run** `swift test --filter UsageRangeTests` — expected FAIL.

- [ ] **Step 3: Implement**

```swift
import Foundation

/// Time ranges for the dashboard. "This week" mirrors clausona's Monday-start
/// week exactly (success criterion: totals match `clausona list`).
public enum UsageRange: String, CaseIterable, Identifiable, Sendable {
    case thisWeek = "This week"
    case lastWeek = "Last week"
    case thisMonth = "This month"
    case allTime = "All time"

    public var id: String { rawValue }

    /// nil = all time (no filtering). `end` is exclusive; open-ended ranges use distantFuture.
    public func interval(now: Date, calendar: Calendar) -> DateInterval? {
        let todayStart = calendar.startOfDay(for: now)
        switch self {
        case .allTime:
            return nil
        case .thisWeek:
            return DateInterval(start: monday(of: todayStart, calendar: calendar), end: .distantFuture)
        case .lastWeek:
            let thisMonday = monday(of: todayStart, calendar: calendar)
            let lastMonday = calendar.date(byAdding: .day, value: -7, to: thisMonday)!
            return DateInterval(start: lastMonday, end: thisMonday)
        case .thisMonth:
            let comps = calendar.dateComponents([.year, .month], from: todayStart)
            return DateInterval(start: calendar.date(from: comps)!, end: .distantFuture)
        }
    }

    /// Port of clausona's cutoffForPeriod week branch: weekday 1=Sunday → back 6 days,
    /// otherwise back (weekday - 2) days.
    private func monday(of dayStart: Date, calendar: Calendar) -> Date {
        let weekday = calendar.component(.weekday, from: dayStart)
        let delta = weekday == 1 ? 6 : weekday - 2
        return calendar.date(byAdding: .day, value: -delta, to: dayStart)!
    }
}
```

- [ ] **Step 4: Run** `swift test --filter UsageRangeTests` — expected PASS.
- [ ] **Step 5: Commit** `git add -A && git commit -m "feat: dashboard time ranges with clausona-compatible Monday weeks"`

### Task 3: UsageMath

**Files:**
- Create: `Sources/ClausonaGUI/Core/UsageMath.swift`
- Test: `Tests/ClausonaGUITests/UsageMathTests.swift`

- [ ] **Step 1: Failing tests** (hand-computed totals; interval filtering incl. exclusive end; daily stacking sorted by day then profile):

```swift
import XCTest
@testable import ClausonaGUI

final class UsageMathTests: XCTestCase {
    static let lisbon: Calendar = {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "Europe/Lisbon")!
        return cal
    }()

    static func date(_ y: Int, _ mo: Int, _ d: Int, _ h: Int = 0) -> Date {
        lisbon.date(from: DateComponents(year: y, month: mo, day: d, hour: h))!
    }

    static func rec(_ d: Date, cost: Double, input: Int = 10, output: Int = 20) -> UsageRecord {
        UsageRecord(ts: d, cost: cost, inputTokens: input, outputTokens: output)
    }

    func testTotalsFiltersByIntervalEndExclusive() {
        let interval = DateInterval(start: Self.date(2026, 6, 8), end: Self.date(2026, 6, 15))
        let records = [
            Self.rec(Self.date(2026, 6, 7, 23), cost: 100),          // before start: excluded
            Self.rec(Self.date(2026, 6, 8, 0), cost: 1.5, input: 1, output: 2),   // at start: included
            Self.rec(Self.date(2026, 6, 12), cost: 2.25, input: 3, output: 4),
            Self.rec(Self.date(2026, 6, 15, 0), cost: 50),           // at end: excluded
        ]
        let totals = UsageMath.totals(records, in: interval)
        XCTAssertEqual(totals.cost, 3.75, accuracy: 0.0001)
        XCTAssertEqual(totals.inputTokens, 4)
        XCTAssertEqual(totals.outputTokens, 6)
    }

    func testTotalsNilIntervalSumsEverything() {
        let records = [Self.rec(Self.date(2020, 1, 1), cost: 1), Self.rec(Self.date(2026, 6, 1), cost: 2)]
        XCTAssertEqual(UsageMath.totals(records, in: nil).cost, 3, accuracy: 0.0001)
    }

    func testTotalsByProfile() {
        let byProfile = [
            "a": [Self.rec(Self.date(2026, 6, 9), cost: 1)],
            "b": [Self.rec(Self.date(2026, 6, 9), cost: 2), Self.rec(Self.date(2026, 6, 10), cost: 3)],
        ]
        let totals = UsageMath.totalsByProfile(byProfile, in: nil)
        XCTAssertEqual(totals["a"]?.cost, 1)
        XCTAssertEqual(totals["b"]?.cost ?? 0, 5, accuracy: 0.0001)
    }

    func testDailyCostsStacksByDayThenProfile() {
        let byProfile = [
            "b": [Self.rec(Self.date(2026, 6, 9, 8), cost: 1), Self.rec(Self.date(2026, 6, 9, 22), cost: 2)],
            "a": [Self.rec(Self.date(2026, 6, 9, 12), cost: 4), Self.rec(Self.date(2026, 6, 10, 1), cost: 8)],
        ]
        let daily = UsageMath.dailyCosts(byProfile, in: nil, calendar: Self.lisbon)
        XCTAssertEqual(daily, [
            DailyProfileCost(day: Self.date(2026, 6, 9), profile: "a", cost: 4),
            DailyProfileCost(day: Self.date(2026, 6, 9), profile: "b", cost: 3),
            DailyProfileCost(day: Self.date(2026, 6, 10), profile: "a", cost: 8),
        ])
    }

    func testDailyCostsRespectsInterval() {
        let byProfile = ["a": [Self.rec(Self.date(2026, 6, 1), cost: 1), Self.rec(Self.date(2026, 6, 9), cost: 2)]]
        let interval = DateInterval(start: Self.date(2026, 6, 8), end: .distantFuture)
        let daily = UsageMath.dailyCosts(byProfile, in: interval, calendar: Self.lisbon)
        XCTAssertEqual(daily, [DailyProfileCost(day: Self.date(2026, 6, 9), profile: "a", cost: 2)])
    }
}
```

- [ ] **Step 2: Run** `swift test --filter UsageMathTests` — expected FAIL.

- [ ] **Step 3: Implement**

```swift
import Foundation

public enum UsageMath {
    /// interval end is exclusive (a record exactly at .end belongs to the next bucket).
    public static func totals(_ records: [UsageRecord], in interval: DateInterval?) -> ProfileTotals {
        records.reduce(into: .zero) { acc, record in
            guard contains(interval, record.ts) else { return }
            acc.cost += record.cost
            acc.inputTokens += record.inputTokens
            acc.outputTokens += record.outputTokens
        }
    }

    public static func totalsByProfile(_ byProfile: [String: [UsageRecord]],
                                       in interval: DateInterval?) -> [String: ProfileTotals] {
        byProfile.mapValues { totals($0, in: interval) }
    }

    /// One entry per (local day, profile) with non-zero cost, sorted by day then profile —
    /// ready for a stacked BarMark chart.
    public static func dailyCosts(_ byProfile: [String: [UsageRecord]],
                                  in interval: DateInterval?,
                                  calendar: Calendar) -> [DailyProfileCost] {
        var buckets: [Date: [String: Double]] = [:]
        for (profile, records) in byProfile {
            for record in records where contains(interval, record.ts) {
                let day = calendar.startOfDay(for: record.ts)
                buckets[day, default: [:]][profile, default: 0] += record.cost
            }
        }
        return buckets
            .flatMap { day, profiles in
                profiles.map { DailyProfileCost(day: day, profile: $0.key, cost: $0.value) }
            }
            .sorted { ($0.day, $0.profile) < ($1.day, $1.profile) }
    }

    private static func contains(_ interval: DateInterval?, _ date: Date) -> Bool {
        guard let interval else { return true }
        return date >= interval.start && date < interval.end
    }
}
```

(Tuple comparison `($0.day, $0.profile) < …` works because Date and String are Comparable.)

- [ ] **Step 4: Run** `swift test --filter UsageMathTests` — expected PASS.
- [ ] **Step 5: Commit** `git add -A && git commit -m "feat: usage aggregation (totals + stacked daily costs)"`

### Task 4: Cost/token formatters

**Files:**
- Modify: `Sources/ClausonaGUI/Core/Formatting.swift`
- Test: `Tests/ClausonaGUITests/FormattingTests.swift` (append)

- [ ] **Step 1: Failing tests** — append to FormattingTests:

```swift
    func testCost() {
        XCTAssertEqual(Formatting.cost(1388.034), "$1,388.03")
        XCTAssertEqual(Formatting.cost(0), "$0.00")
        XCTAssertEqual(Formatting.cost(581.83), "$581.83")
        XCTAssertEqual(Formatting.cost(4500.5), "$4,500.50")
    }

    func testTokens() {
        XCTAssertEqual(Formatting.tokens(2_365_402), "2,365,402")
        XCTAssertEqual(Formatting.tokens(0), "0")
        XCTAssertEqual(Formatting.tokens(694), "694")
    }
```

- [ ] **Step 2: Run** `swift test --filter FormattingTests` — expected FAIL.

- [ ] **Step 3: Implement** — append to `Formatting`:

```swift
    private static let costFormatter: NumberFormatter = {
        let f = NumberFormatter()
        f.locale = Locale(identifier: "en_US")   // deterministic separators, matching the CLI
        f.numberStyle = .decimal
        f.minimumFractionDigits = 2
        f.maximumFractionDigits = 2
        return f
    }()

    private static let tokensFormatter: NumberFormatter = {
        let f = NumberFormatter()
        f.locale = Locale(identifier: "en_US")
        f.numberStyle = .decimal
        f.maximumFractionDigits = 0
        return f
    }()

    public static func cost(_ value: Double) -> String {
        "$" + (costFormatter.string(from: value as NSNumber) ?? String(format: "%.2f", value))
    }

    public static func tokens(_ value: Int) -> String {
        tokensFormatter.string(from: value as NSNumber) ?? String(value)
    }
```

(`NumberFormatter` isn't Sendable; if Swift 6 complains about the stored statics, mark them `nonisolated(unsafe)` — they're configured once and only read.)

- [ ] **Step 4: Run** `swift test --filter FormattingTests` — expected PASS.
- [ ] **Step 5: Commit** `git add -A && git commit -m "feat: cost and token-count formatters"`

### Task 5: FileWatcher

**Files:**
- Create: `Sources/ClausonaGUI/Core/FileWatcher.swift`
- Test: `Tests/ClausonaGUITests/FileWatcherTests.swift`

- [ ] **Step 1: Failing tests** (detects in-place write; survives atomic replace, which is how clausona rewrites usage.json):

```swift
import XCTest
@testable import ClausonaGUI

@MainActor
final class FileWatcherTests: XCTestCase {
    private func tempFile(_ contents: String) throws -> String {
        let path = NSTemporaryDirectory() + "watch-\(UUID().uuidString).json"
        try contents.write(toFile: path, atomically: true, encoding: .utf8)
        return path
    }

    func testDetectsInPlaceWrite() async throws {
        let path = try tempFile("one")
        let changed = expectation(description: "change detected")
        changed.assertForOverFulfill = false
        let watcher = FileWatcher(path: path) { changed.fulfill() }
        watcher.start()
        defer { watcher.stop() }

        try await Task.sleep(for: .milliseconds(100))
        let handle = FileHandle(forWritingAtPath: path)!
        try handle.seekToEnd()
        try handle.write(contentsOf: Data("two".utf8))
        try handle.close()

        await fulfillment(of: [changed], timeout: 5)
    }

    func testSurvivesAtomicReplace() async throws {
        let path = try tempFile("one")
        let changes = expectation(description: "two changes detected")
        changes.expectedFulfillmentCount = 2
        changes.assertForOverFulfill = false
        let watcher = FileWatcher(path: path) { changes.fulfill() }
        watcher.start()
        defer { watcher.stop() }

        try await Task.sleep(for: .milliseconds(100))
        try "two".write(toFile: path, atomically: true, encoding: .utf8)   // rename-over
        try await Task.sleep(for: .milliseconds(300))
        try "three".write(toFile: path, atomically: true, encoding: .utf8) // watcher must have re-armed
        await fulfillment(of: [changes], timeout: 5)
    }
}
```

- [ ] **Step 2: Run** `swift test --filter FileWatcherTests` — expected FAIL.

- [ ] **Step 3: Implement**

```swift
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
}
```

- [ ] **Step 4: Run** `swift test --filter FileWatcherTests` — expected PASS.
- [ ] **Step 5: Commit** `git add -A && git commit -m "feat: file watcher resilient to atomic replaces"`

### Task 6: CredentialStatus on snapshots

**Files:**
- Modify: `Sources/ClausonaGUI/Model/ProfileSnapshot.swift`, `Sources/ClausonaGUI/Core/AppModel.swift`
- Test: `Tests/ClausonaGUITests/AppModelTests.swift` (append)

- [ ] **Step 1: Failing tests** — append to AppModelTests:

```swift
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
```

- [ ] **Step 2: Run** `swift test --filter AppModelTests` — expected FAIL (`credential` undefined).

- [ ] **Step 3: Implement**

In `ProfileSnapshot.swift`, add above `ProfileSnapshot`:

```swift
public enum CredentialStatus: Equatable, Sendable {
    case unknown            // not checked yet
    case valid(until: Date)
    case expired
    case missing
}
```

Add to `ProfileSnapshot`: field `public var credential: CredentialStatus` and an init parameter with default `credential: CredentialStatus = .unknown` (keeps Phase 1 call sites compiling):

```swift
    public var credential: CredentialStatus

    public init(name: String, email: String?, isActive: Bool,
                usage: UsageState, health: HealthStatus, isRepairing: Bool,
                credential: CredentialStatus = .unknown) {
        self.name = name
        self.email = email
        self.isActive = isActive
        self.usage = usage
        self.health = health
        self.isRepairing = isRepairing
        self.credential = credential
    }
```

In `AppModel.refreshUsage()`, extend the task group payload to carry credential status. Replace the `FetchOutcome` enum and the group with:

```swift
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
```

- [ ] **Step 4: Run** `swift test --filter AppModelTests` — expected PASS (all, including Phase 1 tests).
- [ ] **Step 5: Commit** `git add -A && git commit -m "feat: capture per-profile credential status during refresh"`

### Task 7: Doctor failures surfaced (Result + doctorError + issue count)

**Files:**
- Modify: `Sources/ClausonaGUI/Core/ClausonaCLI.swift`, `Core/AppDependencies.swift`, `Core/AppModel.swift`
- Test: `Tests/ClausonaGUITests/ClausonaCLITests.swift`, `Tests/ClausonaGUITests/AppModelTests.swift`

- [ ] **Step 1: Update + add failing tests.**

In `ClausonaCLITests`, replace `testDoctorReturnsStdout` with:

```swift
    func testDoctorReturnsStdout() async throws {
        let stub = try makeStub("echo '  personal (a@b.c)'; echo '    ✔ healthy'")
        let result = await ClausonaCLI(binaryPath: stub).doctor()
        XCTAssertEqual(try result.get().contains("✔ healthy"), true)
    }

    func testDoctorNonZeroWithIssuesStillSucceeds() async throws {
        let stub = try makeStub("echo '  p (a@b.c)'; echo '    ✘ 1 issue'; exit 1")
        let result = await ClausonaCLI(binaryPath: stub).doctor()
        XCTAssertEqual(try result.get().contains("✘ 1 issue"), true)
    }

    func testDoctorFailureSurfacesStderr() async throws {
        let stub = try makeStub("echo 'doctor exploded: cannot read profiles' >&2; exit 2")
        let result = await ClausonaCLI(binaryPath: stub).doctor()
        guard case .failure(let error) = result else { return XCTFail("expected failure") }
        XCTAssertEqual(error.message, "doctor exploded: cannot read profiles")
    }
```

In `AppModelTests`, update every `CLIActions(... doctor: { nil })` to `doctor: { .failure(CLIError(message: "no doctor")) }` and `doctor: { doctorOutput }` to `doctor: { .success(doctorOutput) }`. Then append:

```swift
    func testDoctorFailureSetsErrorAndKeepsHealth() async {
        nonisolated(unsafe) var failDoctor = false
        let cli = CLIActions(use: { _ in .success(()) }, repair: { _ in .success(()) },
                             doctor: { failDoctor ? .failure(CLIError(message: "boom")) : .success("  personal (a@b.c)\n    ✔ healthy") })
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
            ✘ 2 issues
            ├─ one
            ╰─ two
          work (w@b.c)
            ✘ 1 issue
            ╰─ three
        """
        let cli = CLIActions(use: { _ in .success(()) }, repair: { _ in .success(()) },
                             doctor: { .success(output) })
        let model = AppModel(deps: deps(profiles: file(), cli: cli))
        await model.refreshUsage()
        await model.refreshHealth()
        XCTAssertEqual(model.totalIssueCount, 3)
    }
```

- [ ] **Step 2: Run** `swift test --filter "ClausonaCLITests|AppModelTests"` — expected FAIL (type mismatch / missing members).

- [ ] **Step 3: Implement.**

`ClausonaCLI.doctor()` becomes:

```swift
    /// Success carries raw stdout (doctor exits non-zero when issues exist — that's
    /// still a successful run). Failure = couldn't launch, or produced no report.
    public func doctor() async -> Result<String, CLIError> {
        guard let result = await Subprocess.run(binaryPath, ["doctor"]) else {
            return .failure(CLIError(message: "could not launch clausona"))
        }
        if result.stdout.isEmpty && result.exitCode != 0 {
            let stderr = result.stderr.trimmingCharacters(in: .whitespacesAndNewlines)
            return .failure(CLIError(message: stderr.isEmpty ? "clausona doctor exited with status \(result.exitCode)" : stderr))
        }
        return .success(result.stdout)
    }
```

`CLIActions.doctor` property and init parameter become `@Sendable () async -> Result<String, CLIError>`.

In `AppModel`: add `public private(set) var doctorError: String?`, add

```swift
    public var totalIssueCount: Int {
        snapshots.reduce(0) { count, snapshot in
            if case .issues(let issues) = snapshot.health { return count + issues.count }
            return count
        }
    }
```

and replace `refreshHealth()`:

```swift
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
```

- [ ] **Step 4: Run** `swift test` (full suite) — expected all PASS.
- [ ] **Step 5: Commit** `git add -A && git commit -m "feat: surface doctor run failures + total issue count"`

### Task 8: UsageStore

**Files:**
- Create: `Sources/ClausonaGUI/MainWindow/Dashboard/UsageStore.swift`
- Test: `Tests/ClausonaGUITests/UsageStoreTests.swift`

- [ ] **Step 1: Failing tests** (loads from CLAUSONA_HOME, aggregates through range, missing file → loadFailed):

```swift
import XCTest
@testable import ClausonaGUI

@MainActor
final class UsageStoreTests: XCTestCase {
    nonisolated static let lisbon: Calendar = {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "Europe/Lisbon")!
        return cal
    }()
    nonisolated static let now = lisbon.date(from: DateComponents(year: 2026, month: 6, day: 13, hour: 12))!

    private func makeHome(usageJSON: String?) throws -> String {
        let dir = NSTemporaryDirectory() + "clausona-home-\(UUID().uuidString)"
        try FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
        if let usageJSON {
            try usageJSON.write(toFile: dir + "/usage.json", atomically: true, encoding: .utf8)
        }
        return dir
    }

    func testLoadAndAggregate() throws {
        let home = try makeHome(usageJSON: """
        {
          "personal": { "records": [
            { "ts": "2026-06-09T10:00:00+01:00", "tz": "+01:00", "cost": 1.5, "inputTokens": 100, "outputTokens": 200 },
            { "ts": "2026-06-01T10:00:00+01:00", "tz": "+01:00", "cost": 8.0, "inputTokens": 1, "outputTokens": 1 }
          ] },
          "work": { "records": [
            { "ts": "2026-06-12T09:00:00+01:00", "tz": "+01:00", "cost": 2.5, "inputTokens": 10, "outputTokens": 20 }
          ] }
        }
        """)
        let store = UsageStore(environment: ["CLAUSONA_HOME": home],
                               calendar: Self.lisbon, now: { Self.now })
        store.reload()
        XCTAssertFalse(store.loadFailed)
        XCTAssertEqual(store.range, .thisWeek)
        // This week = Mon 6/8 onward: 1.5 + 2.5
        XCTAssertEqual(store.grandTotalCost(), 4.0, accuracy: 0.0001)
        XCTAssertEqual(store.totalsByProfile()["personal"]?.cost ?? 0, 1.5, accuracy: 0.0001)
        XCTAssertEqual(store.dailyCosts().count, 2)

        store.range = .allTime
        XCTAssertEqual(store.grandTotalCost(), 12.0, accuracy: 0.0001)
    }

    func testMissingFileIsLoadFailed() throws {
        let home = try makeHome(usageJSON: nil)
        let store = UsageStore(environment: ["CLAUSONA_HOME": home],
                               calendar: Self.lisbon, now: { Self.now })
        store.reload()
        XCTAssertTrue(store.loadFailed)
        XCTAssertEqual(store.grandTotalCost(), 0)
        XCTAssertTrue(store.dailyCosts().isEmpty)
    }
}
```

- [ ] **Step 2: Run** `swift test --filter UsageStoreTests` — expected FAIL.

- [ ] **Step 3: Implement**

```swift
import Foundation
import Observation

/// Loads, watches, and aggregates ~/.clausona/usage.json for the dashboard.
/// The file is owned by clausona — strictly read-only here.
@MainActor @Observable
public final class UsageStore {
    public private(set) var recordsByProfile: [String: [UsageRecord]] = [:]
    public private(set) var loadFailed = false
    public var range: UsageRange = .thisWeek

    private let usagePath: String
    private let calendar: Calendar
    private let now: @Sendable () -> Date
    private var watcher: FileWatcher?

    public init(environment: [String: String] = ProcessInfo.processInfo.environment,
                home: String = NSHomeDirectory(),
                calendar: Calendar = .current,
                now: @escaping @Sendable () -> Date = { Date() }) {
        let base = environment["CLAUSONA_HOME"] ?? home + "/.clausona"
        usagePath = base + "/usage.json"
        self.calendar = calendar
        self.now = now
    }

    /// Initial load + live reload while sessions run.
    public func start() {
        reload()
        if watcher == nil {
            watcher = FileWatcher(path: usagePath) { [weak self] in self?.reload() }
            watcher?.start()
        }
    }

    public func reload() {
        guard let data = FileManager.default.contents(atPath: usagePath),
              let log = try? UsageLog.decode(data) else {
            recordsByProfile = [:]
            loadFailed = true
            return
        }
        recordsByProfile = log
        loadFailed = false
    }

    public var interval: DateInterval? {
        range.interval(now: now(), calendar: calendar)
    }

    public func totalsByProfile() -> [String: ProfileTotals] {
        UsageMath.totalsByProfile(recordsByProfile, in: interval)
    }

    public func grandTotalCost() -> Double {
        totalsByProfile().values.reduce(0) { $0 + $1.cost }
    }

    public func dailyCosts() -> [DailyProfileCost] {
        UsageMath.dailyCosts(recordsByProfile, in: interval, calendar: calendar)
    }
}
```

- [ ] **Step 4: Run** `swift test --filter UsageStoreTests` — expected PASS.
- [ ] **Step 5: Commit** `git add -A && git commit -m "feat: UsageStore (load + watch + aggregate usage.json)"`

### Task 9: Window plumbing (controller, popover button, delegate wiring)

**Files:**
- Create: `Sources/ClausonaGUI/MainWindow/MainWindowController.swift`
- Modify: `Sources/ClausonaGUI/Core/AppModel.swift` (open hook), `Sources/ClausonaGUI/UI/FooterView.swift`, `Sources/ClausonaGUI/App/AppDelegate.swift`, `Sources/ClausonaGUI/App/StatusItemController.swift` (expose close for wiring — already public)

No unit tests (AppKit window glue); verified by build + Task 14 checklist.

- [ ] **Step 1: AppModel hook** — add to `AppModel`:

```swift
    /// Set by AppDelegate; invoked from the popover footer.
    @ObservationIgnored public var onOpenMainWindow: (@MainActor () -> Void)?

    public func openMainWindow() {
        onOpenMainWindow?()
    }
```

- [ ] **Step 2: MainWindowController** (placeholder root view swapped in Task 10):

```swift
import AppKit
import SwiftUI

/// Singleton main window. While open the app behaves like a regular app
/// (Dock icon, ⌘-Tab); on close it returns to menu-bar-only.
@MainActor
public final class MainWindowController: NSObject, NSWindowDelegate {
    private let model: AppModel
    private let usage: UsageStore
    private var window: NSWindow?

    public init(model: AppModel, usage: UsageStore) {
        self.model = model
        self.usage = usage
        super.init()
    }

    public func show() {
        if window == nil {
            window = makeWindow()
        }
        usage.start()
        NSApp.setActivationPolicy(.regular)
        window?.makeKeyAndOrderFront(nil)
        NSApp.activate()
        Task { await model.refreshHealth() }
    }

    private func makeWindow() -> NSWindow {
        let win = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 920, height: 560),
                           styleMask: [.titled, .closable, .miniaturizable, .resizable],
                           backing: .buffered, defer: false)
        win.title = "Clausona"
        win.isReleasedWhenClosed = false
        win.center()
        win.setFrameAutosaveName("ClausonaMainWindow")
        win.delegate = self
        win.contentViewController = NSHostingController(rootView: MainWindowView(model: model, usage: usage))
        win.minSize = NSSize(width: 720, height: 420)
        return win
    }

    public func windowWillClose(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
    }
}
```

- [ ] **Step 3: FooterView button** — in the `HStack` with the Launch at Login toggle, insert between the toggle and `Spacer()`:

```swift
                Button("Open Clausona…") { model.openMainWindow() }
                    .controlSize(.small)
```

- [ ] **Step 4: AppDelegate wiring** — add properties `private var windowController: MainWindowController?` and `private var usageStore: UsageStore?`; in `applicationDidFinishLaunching` after creating `controller`:

```swift
        let usage = UsageStore()
        usageStore = usage
        let windowController = MainWindowController(model: model, usage: usage)
        self.windowController = windowController
        model.onOpenMainWindow = { [weak controller, weak windowController] in
            controller?.close()
            windowController?.show()
        }
        // Debug/manual-test hook: launch straight into the main window.
        if CommandLine.arguments.contains("--window") {
            windowController.show()
        }
```

Also: clicking the Dock icon while the window exists should re-show it — add to AppDelegate:

```swift
    public func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if !flag { windowController?.show() }
        return true
    }
```

- [ ] **Step 5: Temporary placeholder** so it compiles before Task 10 — create `Sources/ClausonaGUI/MainWindow/MainWindowView.swift`:

```swift
import SwiftUI

public struct MainWindowView: View {
    let model: AppModel
    let usage: UsageStore

    public init(model: AppModel, usage: UsageStore) {
        self.model = model
        self.usage = usage
    }

    public var body: some View {
        Text("Clausona")   // replaced in Task 10
            .frame(minWidth: 400, minHeight: 300)
    }
}
```

- [ ] **Step 6: Build + suite** `swift build && swift test` — expected: clean, all pass.
- [ ] **Step 7: Commit** `git add -A && git commit -m "feat: main window plumbing + popover entry point"`

### Task 10: MainWindowView + sidebar navigation

**Files:**
- Modify: `Sources/ClausonaGUI/MainWindow/MainWindowView.swift`

- [ ] **Step 1: Implement navigation root** (detail views are stubs filled by Tasks 11–13):

```swift
import SwiftUI

public enum MainSection: Hashable {
    case dashboard
    case profile(String)
    case doctor
}

public struct MainWindowView: View {
    let model: AppModel
    let usage: UsageStore
    @State private var selection: MainSection? = .dashboard

    public init(model: AppModel, usage: UsageStore) {
        self.model = model
        self.usage = usage
    }

    public var body: some View {
        NavigationSplitView {
            List(selection: $selection) {
                Label("Dashboard", systemImage: "chart.bar.xaxis")
                    .tag(MainSection.dashboard)

                Section("Profiles") {
                    ForEach(model.snapshots) { snapshot in
                        HStack(spacing: 6) {
                            Circle()
                                .fill(dotColor(snapshot.health))
                                .frame(width: 7, height: 7)
                            Text(snapshot.name)
                            if snapshot.isActive {
                                Spacer()
                                Image(systemName: "arrowtriangle.right.fill")
                                    .font(.system(size: 7))
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .tag(MainSection.profile(snapshot.name))
                    }
                }

                Label("Doctor", systemImage: "stethoscope")
                    .badge(model.totalIssueCount)
                    .tag(MainSection.doctor)
            }
            .navigationSplitViewColumnWidth(min: 170, ideal: 190)
        } detail: {
            switch selection {
            case .dashboard, nil:
                DashboardView(model: model, usage: usage)
            case .profile(let name):
                if let snapshot = model.snapshots.first(where: { $0.name == name }) {
                    ProfileDetailView(snapshot: snapshot, model: model, usage: usage, selection: $selection)
                } else {
                    ContentUnavailableView("Profile not found", systemImage: "person.crop.circle.badge.questionmark")
                }
            case .doctor:
                DoctorView(model: model)
            }
        }
        .frame(minWidth: 720, minHeight: 420)
    }

    private func dotColor(_ health: HealthStatus) -> Color {
        switch health {
        case .healthy: .green
        case .issues: .red
        case .unknown: .gray
        }
    }
}
```

- [ ] **Step 2: Stub detail views** so it compiles (each replaced in its task) — create the three files with minimal bodies:

`MainWindow/Dashboard/DashboardView.swift`:
```swift
import SwiftUI

struct DashboardView: View {
    let model: AppModel
    let usage: UsageStore

    var body: some View {
        Text("Dashboard")   // Task 11
    }
}
```

`MainWindow/Profiles/ProfileDetailView.swift`:
```swift
import SwiftUI

struct ProfileDetailView: View {
    let snapshot: ProfileSnapshot
    let model: AppModel
    let usage: UsageStore
    @Binding var selection: MainSection?

    var body: some View {
        Text(snapshot.name)   // Task 12
    }
}
```

`MainWindow/Doctor/DoctorView.swift`:
```swift
import SwiftUI

struct DoctorView: View {
    let model: AppModel

    var body: some View {
        Text("Doctor")   // Task 13
    }
}
```

- [ ] **Step 3: Build + smoke** `swift build && .build/debug/ClausonaApp --window &` — window appears with sidebar (Dashboard / 5 profiles with dots / Doctor with badge); kill it.
- [ ] **Step 4: Commit** `git add -A && git commit -m "feat: main window navigation (sidebar + sections)"`

### Task 11: DashboardView

**Files:**
- Modify: `Sources/ClausonaGUI/MainWindow/Dashboard/DashboardView.swift`

- [ ] **Step 1: Implement**

```swift
import Charts
import SwiftUI

struct DashboardView: View {
    let model: AppModel
    @Bindable var usage: UsageStore

    init(model: AppModel, usage: UsageStore) {
        self.model = model
        self._usage = Bindable(usage)
    }

    private struct Row: Identifiable {
        let name: String
        let totals: ProfileTotals
        let isActive: Bool
        var id: String { name }
    }

    private var rows: [Row] {
        usage.totalsByProfile()
            .map { Row(name: $0.key, totals: $0.value, isActive: $0.key == model.activeProfile) }
            .sorted { $0.totals.cost > $1.totals.cost }
    }

    var body: some View {
        let daily = usage.dailyCosts()
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Picker("Range", selection: $usage.range) {
                    ForEach(UsageRange.allCases) { range in
                        Text(range.rawValue).tag(range)
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .fixedSize()
                Spacer()
                Text("Total \(Formatting.cost(usage.grandTotalCost()))")
                    .font(.title3.weight(.semibold))
                    .monospacedDigit()
            }

            if usage.loadFailed || usage.recordsByProfile.isEmpty {
                ContentUnavailableView(
                    "No usage data",
                    systemImage: "chart.bar.xaxis",
                    description: Text("clausona records usage as you run sessions."))
                    .frame(maxHeight: .infinity)
            } else if daily.isEmpty {
                ContentUnavailableView(
                    "No usage recorded in this range",
                    systemImage: "calendar.badge.minus")
                    .frame(maxHeight: .infinity)
            } else {
                Chart(daily) { entry in
                    BarMark(
                        x: .value("Day", entry.day, unit: .day),
                        y: .value("Cost", entry.cost))
                        .foregroundStyle(by: .value("Profile", entry.profile))
                }
                .chartYAxis {
                    AxisMarks { value in
                        AxisGridLine()
                        AxisValueLabel {
                            if let cost = value.as(Double.self) {
                                Text(Formatting.cost(cost))
                            }
                        }
                    }
                }
                .frame(minHeight: 200, maxHeight: 280)

                Table(rows) {
                    TableColumn("Profile") { row in
                        HStack(spacing: 4) {
                            Image(systemName: "arrowtriangle.right.fill")
                                .font(.system(size: 7))
                                .opacity(row.isActive ? 1 : 0)
                            Text(row.name)
                                .fontWeight(row.isActive ? .semibold : .regular)
                        }
                    }
                    TableColumn("Cost") { row in
                        Text(Formatting.cost(row.totals.cost)).monospacedDigit()
                    }
                    TableColumn("Input") { row in
                        Text(Formatting.tokens(row.totals.inputTokens)).monospacedDigit()
                    }
                    TableColumn("Output") { row in
                        Text(Formatting.tokens(row.totals.outputTokens)).monospacedDigit()
                    }
                }
            }
        }
        .padding()
        .navigationTitle("Dashboard")
    }
}
```

- [ ] **Step 2: Build + visual check** `swift build && .build/debug/ClausonaApp --window &` — chart shows stacked daily bars colored by profile, totals table sorted by cost, range picker switches (Last week / This month / All time), total updates. Kill after.
- [ ] **Step 3: Commit** `git add -A && git commit -m "feat: usage dashboard with stacked cost chart and totals table"`

### Task 12: ProfileDetailView

**Files:**
- Modify: `Sources/ClausonaGUI/MainWindow/Profiles/ProfileDetailView.swift`

- [ ] **Step 1: Implement** (needs `Profile` flags — fetch from `ProfileStore` via model snapshots? Snapshots don't carry configDir/flags. Add a lookup: `AppModel` gets `public private(set) var profilesFile: ProfilesFile?` set in `refreshUsage`'s `mergeProfiles` (one line: `profilesFile = file`) so detail views can read configDir/isPrimary. Include that change here.)

In `AppModel`: add `public private(set) var profilesFile: ProfilesFile?` and set `profilesFile = file` as the first line of `mergeProfiles(_:)`.

```swift
import SwiftUI

struct ProfileDetailView: View {
    let snapshot: ProfileSnapshot
    let model: AppModel
    let usage: UsageStore
    @Binding var selection: MainSection?

    private var profile: Profile? {
        model.profilesFile?.profiles.first { $0.name == snapshot.name }
    }

    var body: some View {
        Form {
            Section("Account") {
                LabeledContent("Profile", value: snapshot.name)
                if let email = profile?.email { LabeledContent("Email", value: email) }
                if let org = profile?.orgName { LabeledContent("Organization", value: org) }
                if let dir = profile?.configDir {
                    LabeledContent("Config directory") {
                        Button {
                            NSWorkspace.shared.selectFile(nil, inFileViewerRootedAtPath: dir)
                        } label: {
                            HStack(spacing: 4) {
                                Text(dir)
                                Image(systemName: "arrow.up.forward.square")
                            }
                        }
                        .buttonStyle(.link)
                        .help("Reveal in Finder")
                    }
                }
                LabeledContent("Primary", value: profile?.isPrimary == true ? "Yes" : "No")
            }

            Section("Credentials") {
                LabeledContent("Status", value: credentialText)
            }

            Section("Rate limits") {
                limitsRow
            }

            Section("Health") {
                HStack {
                    Text(healthText)
                    Spacer()
                    Button("View in Doctor") { selection = .doctor }
                        .buttonStyle(.link)
                }
            }

            Section("Usage — \(usage.range.rawValue)") {
                let totals = usage.totalsByProfile()[snapshot.name] ?? .zero
                LabeledContent("Cost", value: Formatting.cost(totals.cost))
                LabeledContent("Input tokens", value: Formatting.tokens(totals.inputTokens))
                LabeledContent("Output tokens", value: Formatting.tokens(totals.outputTokens))
            }
        }
        .formStyle(.grouped)
        .navigationTitle(snapshot.name)
    }

    private var credentialText: String {
        switch snapshot.credential {
        case .unknown: "Not checked yet"
        case .valid(let until): "Valid until \(until.formatted(date: .abbreviated, time: .shortened))"
        case .expired: "Expired — run clausona login \(snapshot.name)"
        case .missing: "No credentials found"
        }
    }

    private var healthText: String {
        switch snapshot.health {
        case .healthy: "Healthy"
        case .issues(let issues): "\(issues.count) issue\(issues.count == 1 ? "" : "s")"
        case .unknown: "Unknown"
        }
    }

    @ViewBuilder private var limitsRow: some View {
        switch snapshot.usage {
        case .loading:
            Text("Loading…").foregroundStyle(.secondary)
        case .ok(let report):
            windowLine("5-hour window", report.fiveHour)
            windowLine("7-day window", report.sevenDay)
        case .error(let message, let lastGood):
            if let lastGood {
                windowLine("5-hour window", lastGood.fiveHour)
                windowLine("7-day window", lastGood.sevenDay)
            }
            Text(message).foregroundStyle(.secondary)
        }
    }

    private func windowLine(_ label: String, _ window: UsageWindow?) -> some View {
        LabeledContent(label) {
            if let window {
                Text("\(window.utilization)%" + suffix(window.resetsAt)).monospacedDigit()
            } else {
                Text("—")
            }
        }
    }

    private func suffix(_ resetsAt: Date?) -> String {
        guard let resetsAt else { return "" }
        return "  (resets in \(Formatting.duration(seconds: Int(resetsAt.timeIntervalSinceNow))))"
    }
}
```

- [ ] **Step 2: Build + suite** `swift build && swift test` — clean, all pass (AppModel change is additive).
- [ ] **Step 3: Visual check** `.build/debug/ClausonaApp --window` → select each profile; verify fields, click config dir (Finder opens), "View in Doctor" jumps. Kill after.
- [ ] **Step 4: Commit** `git add -A && git commit -m "feat: profile detail view"`

### Task 13: DoctorView

**Files:**
- Modify: `Sources/ClausonaGUI/MainWindow/Doctor/DoctorView.swift`

- [ ] **Step 1: Implement**

```swift
import SwiftUI

struct DoctorView: View {
    let model: AppModel
    @State private var isRunning = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                if !model.cliAvailable {
                    banner("clausona CLI not found — doctor and repair are unavailable.",
                           systemImage: "exclamationmark.triangle", color: .orange)
                }
                if let error = model.doctorError {
                    banner("Doctor run failed: \(error)", systemImage: "xmark.octagon", color: .red)
                }
                ForEach(model.snapshots) { snapshot in
                    profileSection(snapshot)
                }
            }
            .padding()
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .navigationTitle("Doctor")
        .toolbar {
            Button {
                runDoctor()
            } label: {
                if isRunning {
                    ProgressView().controlSize(.small)
                } else {
                    Label("Run doctor again", systemImage: "arrow.clockwise")
                }
            }
            .disabled(isRunning || !model.cliAvailable)
        }
    }

    private func runDoctor() {
        isRunning = true
        Task {
            await model.refreshHealth()
            isRunning = false
        }
    }

    private func banner(_ text: String, systemImage: String, color: Color) -> some View {
        Label(text, systemImage: systemImage)
            .padding(10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(color.opacity(0.12), in: RoundedRectangle(cornerRadius: 8))
    }

    @ViewBuilder private func profileSection(_ snapshot: ProfileSnapshot) -> some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 6) {
                switch snapshot.health {
                case .healthy:
                    Label("Healthy", systemImage: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                case .unknown:
                    Label("Health unknown", systemImage: "questionmark.circle")
                        .foregroundStyle(.secondary)
                case .issues(let issues):
                    ForEach(Array(issues.enumerated()), id: \.offset) { _, issue in
                        Label(issue, systemImage: "xmark.circle.fill")
                            .foregroundStyle(.red)
                            .font(.system(size: 12))
                    }
                    if model.cliAvailable {
                        Button {
                            Task { await model.repair(snapshot.name) }
                        } label: {
                            if snapshot.isRepairing {
                                ProgressView().controlSize(.small)
                            } else {
                                Label("Repair", systemImage: "wrench.and.screwdriver")
                            }
                        }
                        .disabled(snapshot.isRepairing)
                        .padding(.top, 4)
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(4)
        } label: {
            HStack(spacing: 6) {
                Text(snapshot.name).font(.headline)
                if let email = snapshot.email {
                    Text(email).font(.subheadline).foregroundStyle(.secondary)
                }
            }
        }
    }
}
```

- [ ] **Step 2: Build + suite** `swift build && swift test` — clean, all pass.
- [ ] **Step 3: Visual check** `--window` → Doctor: sections match `clausona doctor` (same issues verbatim), badge count in sidebar, "Run doctor again" spins and refreshes. Kill after.
- [ ] **Step 4: Commit** `git add -A && git commit -m "feat: doctor view with repair actions"`

### Task 14: Install + verification

- [ ] **Step 1:** `swift test` (full suite, fresh) — all pass; `make install` — rebuilds release bundle to `~/Applications`.
- [ ] **Step 2: Success criterion 1** — run `clausona list` and compare with our pure pipeline over the same file at the same moment:
  the dashboard "This week" totals per profile must equal the CLI's COST/INPUT/OUTPUT columns. (Compute via a quick harness: decode `~/.clausona/usage.json` with `UsageLog`, aggregate with `UsageMath.totalsByProfile` over `UsageRange.thisWeek.interval(now: Date(), calendar: .current)`, print; diff against `clausona list`.)
- [ ] **Step 3: Success criterion 2** — Doctor view lists exactly the issues `clausona doctor` prints; a Repair click clears the repairable issues on the re-run.
- [ ] **Step 4: Success criterion 3** — Profile detail credential expiry: `personal` shows expired (known state), `personal3` shows a concrete "Valid until …" timestamp consistent with the keychain blob's `expiresAt`.
- [ ] **Step 5: Manual checklist** — open via popover button: popover closes, window opens, Dock icon appears; close window: Dock icon disappears, popover still works; resize/move window, relaunch app, frame restored; live update: while a Claude session runs (or `touch`-simulate by appending a record to a COPY — never edit the real file… instead just verify FileWatcher tests + observe during a real session), dashboard refreshes without reopening.
- [ ] **Step 6:** screenshots of Dashboard / Profile / Doctor; final commit.

---

## Self-review notes

- Spec coverage: usage.json decode+watch → T1/T5/T8; ranges/aggregation → T2/T3; dashboard UI → T11; profile detail (account, configDir reveal, flags, credential status, 5h/7d, health link, range totals) → T6/T12; doctor view (verbatim issues, repair, re-run, stderr on failure, badge) → T7/T13; window/activation/restore → T9; popover entry → T9; error-handling table → T1 (malformed record), T8 (missing file), T7 (doctor failure), T13 (CLI missing hint); success criteria → T14.
- Type consistency: `UsageStore.range/dailyCosts/totalsByProfile/grandTotalCost` (T8) match usage in T11/T12; `CredentialStatus` (T6) matches T12; `doctorError`/`totalIssueCount` (T7) match T10/T13; `MainSection` (T10) matches T12 binding.
- Known deviations: "Last week" is bounded `[monday-7d, monday)` (clausona has no such period — our definition); `clausona list`'s 7-day *header* string is intentionally not replicated (totals are what criterion 1 compares).
