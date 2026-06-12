# Clausona GUI — Phase 2: Main window

**Date:** 2026-06-12
**Status:** Approved 2026-06-13
**Depends on:** [Phase 1 — menu bar core](2026-06-12-phase1-menubar-core-design.md) (reuses ProfileStore, HealthChecker, ClausonaCLI, models)

## Overview

A proper window for everything too big for the popover: a usage/cost dashboard
(what `clausona list` / `clausona usage` show, but visual and over selectable time
ranges), a per-profile detail panel, and a doctor detail view listing every health
issue with repair actions. Opened from a "Open Clausona…" item in the popover footer.

## Goals

- See cost and token spend per profile over a chosen time range (this week, last week, this month, all time), as totals and as a trend chart.
- Inspect one profile: account, org, config dir, credential status, settings flags, health issues.
- See the full `clausona doctor` picture in one place and repair from there.

## Non-goals

- Mutating anything except `repair` (and `use`, carried over from Phase 1). Lifecycle operations stay in Phase 3.
- Historical data beyond what clausona already records in `usage.json`.
- Exporting/reporting.

## Data sources (read-only)

**`~/.clausona/usage.json`** — per profile: `records: [{ ts, tz, cost, inputTokens, outputTokens }]`
(one record per session-ish event; `seenSessions` ignored). The dashboard aggregates
records client-side by day and by profile. The file is owned by clausona; we never
write it. A `DispatchSource` file watcher reloads on change, so the dashboard updates
live while sessions run.

**Doctor / profiles / credentials** — same components as Phase 1 (HealthChecker,
ProfileStore, TokenProvider). Opening the doctor view triggers a fresh `clausona doctor`
run; the HealthChecker parser is extended to also capture each issue's text lines so
the detail view can show them verbatim (e.g. "`stats-cache.json` replaced an expected
shared symlink").

## Architecture

```
Sources/ClausonaGUI/
├── MainWindow/
│   ├── MainWindowController.swift     (NSWindow + SwiftUI root; singleton, restored frame)
│   ├── SidebarView.swift              (Dashboard / Profiles / Doctor sections)
│   ├── Dashboard/                     UsageStore (usage.json load+watch+aggregate), DashboardView, charts
│   ├── Profiles/                      ProfileDetailView
│   └── Doctor/                        DoctorView
```

- `NavigationSplitView`: sidebar with **Dashboard**, **Profiles** (one entry per profile, with health dot), **Doctor**.
- The window is a normal resizable window (`NSWindow`, not LSUIElement-suppressed — activation policy flips to `.regular` while the window is open so it gets a Dock presence and ⌘-Tab entry, back to `.accessory` on close).
- Charts via the system **Swift Charts** framework (macOS 14+, no dependency).

## Views

### Dashboard

```
┌────────────┬──────────────────────────────────────────────┐
│ Dashboard  │  Range: [This week ▾]            Total $4,500 │
│ Profiles   │  ┌ stacked bar chart: cost per day, by profile┐│
│  ▸ personal│  └──────────────────────────────────────────┘│
│  …         │  PROFILE      COST      INPUT      OUTPUT     │
│ Doctor (10)│  personal     $1,388    2.4M       6.1M       │
│            │  work         $1,056    3.8M       4.0M  …    │
└────────────┴──────────────────────────────────────────────┘
```

- Range picker: This week (default, matching `clausona list`'s Mon–Sun window in the local timezone), Last week, This month, All time.
- Stacked bar chart of cost per day colored by profile; table below with cost / input / output totals per profile, sorted by cost, active profile marked.
- Empty range → "no usage recorded in this range".

### Profile detail

Selected from the sidebar. Shows: name, email, org, `configDir` (click to reveal in
Finder), `isPrimary` / `mergeSessions` flags, credential status (valid until / expired /
missing — from TokenProvider, no token material shown), current 5h/7d windows (reusing
Phase 1 snapshot), health summary with a "View in Doctor" link, and this profile's
usage totals for the selected range.

### Doctor

One section per profile mirroring the CLI output: health state, each issue's verbatim
text, and a **Repair** button per unhealthy profile (same ClausonaCLI call as Phase 1,
with spinner and re-run of doctor on completion). A "Run doctor again" toolbar button
re-checks everything. Sidebar badge shows total issue count.

## Error handling

| Failure | Behavior |
| --- | --- |
| `usage.json` missing/unparseable | Dashboard empty state: "no usage data — clausona records usage as you run sessions" |
| Single malformed record | Skipped, not fatal |
| Doctor run fails | Doctor view shows stderr text + "Run doctor again" |
| Window opened while CLI missing | Dashboard and profile detail work (file/keychain reads); Doctor shows the degraded-mode hint |

## Testing

- **Unit tests:** usage.json decoding (real-shape fixture, malformed records, missing file); range aggregation (week boundaries in local tz, month, all-time; verify totals against a hand-computed fixture); extended doctor parser (issue text capture) against captured real output.
- **Manual checklist:** live dashboard update while a Claude session runs; repair from Doctor view clears the issue; window restore (size/position) across relaunch; activation policy flip (Dock icon appears only while window open).

## Success criteria

1. Dashboard totals for "This week" match `clausona list` output for the same window.
2. Doctor view shows the same issues as `clausona doctor`, and repair clears them.
3. Profile detail shows accurate credential expiry per profile.
