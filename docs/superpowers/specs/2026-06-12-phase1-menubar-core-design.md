# Clausona GUI — Phase 1: Menu bar core

**Date:** 2026-06-12
**Status:** Approved 2026-06-13
**Project:** `~/Projects/personal/clausona-gui` — a native macOS GUI for [clausona](https://github.com/larcane97/clausona), the third-party Claude Code profile manager.

## Overview

A menu bar app (no Dock icon) showing Claude rate-limit windows (5h / 7d) for every
clausona profile, with one-click profile switching and a health badge with one-click
repair. Opened by clicking the menu bar icon or pressing **⌃⌥⌘L**.

This is Phase 1 of three:

1. **Phase 1 (this spec):** menu bar core — limits popover, profile switcher, health badge + repair, hotkey, launch at login.
2. **Phase 2:** main window — usage/cost dashboard, profile detail, doctor detail ([spec](2026-06-12-phase2-main-window-design.md)).
3. **Phase 3:** lifecycle handoffs — add/login/remove/init via terminal, app settings ([spec](2026-06-12-phase3-lifecycle-handoffs-design.md)).

## Goals

- See 5h/7d utilization per profile at a glance, matching the `clausona-limits` CLI's presentation (colors, reset countdowns, active marker).
- Switch the active profile without a terminal.
- See at a glance when a profile is unhealthy; repair it with one click.
- Shareable with colleagues: no Karabiner, no personal scripts, no extra permissions required.

## Non-goals (deferred)

- Usage/cost dashboard, profile detail views (Phase 2).
- Adding/removing/re-authenticating profiles (Phase 3).
- Configurable hotkey or poll interval (Phase 3 settings, if ever).
- Windows/Linux, localization, notarized distribution.

## Decisions log (from brainstorm)

| Decision | Choice |
| --- | --- |
| Tech | Native Swift app (SwiftPM + AppKit/SwiftUI), macOS 14+ |
| Menu bar icon | Static glyph only (no numbers in the bar) |
| Refresh | On popover open (cached shown instantly) + background poll every 5 min |
| Extras | Launch at Login toggle |
| Hotkey | Native ⌃⌥⌘L via Carbon `RegisterEventHotKey` (no permissions needed); the old Karabiner Hyper+L rule gets deleted by the user |
| clausona integration | Hybrid: **reads** go to underlying state (profiles.json, keychain, usage endpoint); **safe mutations** shell out to the clausona CLI; interactive flows deferred to Phase 3 terminal handoff |
| Limits fetching | Ported to Swift (supersedes the earlier "add `--json` to clausona-limits" idea) — colleagues won't have that personal script, and the logic is small. `clausona-limits` stays untouched for terminal use. |

## Architecture

SwiftPM executable target wrapped into `Clausona.app` (`LSUIElement = true`).
AppKit lifecycle: `NSStatusItem` + `NSPopover` hosting SwiftUI content via
`NSHostingController`. `NSPopover` (not `NSMenu`) because we need live-updating
SwiftUI views and programmatic toggling from the hotkey; the status item button is
highlighted while the popover is open so it looks like a selected menu bar item.

```
Sources/ClausonaGUI/
├── App/            AppDelegate, StatusItemController (popover + highlight), HotkeyManager
├── Core/           ProfileStore, TokenProvider, UsageFetcher, HealthChecker, ClausonaCLI, RefreshScheduler
├── Model/          Profile, UsageWindow, ProfileSnapshot, HealthStatus
└── UI/             PopoverView, ProfileRowView, FooterView, EmptyStateView
```

### Components

**ProfileStore** — reads `$CLAUSONA_HOME` (default `~/.clausona`) `/profiles.json`:
`{ activeProfile, primarySource, profiles: { name: { configDir, email, orgName, isPrimary?, mergeSessions? } } }`.
Tolerant decoding: unknown keys ignored; missing file → "clausona not set up" state.

**TokenProvider** — port of `clausona-limits`' `token_for_dir`:

- Keychain service name: `Claude Code-credentials-<first 8 hex of sha256(configDir)>`; for `~/.claude` also try legacy `Claude Code-credentials`.
- Read by spawning `/usr/bin/security find-generic-password -s <svc> -w` — the keychain ACL client stays `security`, which the user has already authorized from terminal use, so no new prompts.
- Parse `claudeAiOauth.{accessToken, expiresAt}`; file fallback `<configDir>/.credentials.json` only when it is not a symlink to another profile's file; pick the freshest token; expired → per-profile "login needed" state.
- Tokens live in memory only — never logged, written, or shown in UI.

**UsageFetcher** — `GET https://api.anthropic.com/api/oauth/usage` with
`Authorization: Bearer <token>` and `anthropic-beta: oauth-2025-04-20` (15 s timeout).
Decodes `five_hour` / `seven_day` `{ utilization, resets_at }`; either window may be
absent → rendered as `—`. All profiles fetched concurrently.

**HealthChecker** — runs `clausona doctor`, strips ANSI, parses per-profile lines:
`<name> (<email>)` followed by `✔ healthy` or `✘ N issue(s)` and issue lines (`├─`/`╰─`).
Tolerant: a profile that can't be matched → `unknown` (gray), never an error. Doctor
runs are slow-ish, so health refreshes on app start, after a repair, and every 30 min —
not on every popover open.

**ClausonaCLI** — locates the binary (`~/.local/bin/clausona`, then `PATH`); runs
`clausona use <name>` and `clausona repair <name>` non-interactively, capturing exit
code + output. Missing binary → degraded mode: limits still work (they don't need the
CLI), switcher/health hidden, footer hint "clausona CLI not found".

**RefreshScheduler** — usage refresh on popover open (cached snapshot shown instantly,
spinner in footer while updating) + background `Timer` every 5 min. Failures keep the
last good snapshot and mark it stale ("updated 23m ago" turns orange after 2 missed
cycles). No retry storm: a failed cycle just waits for the next tick.

**HotkeyManager** — Carbon `RegisterEventHotKey` for ⌃⌥⌘L (constant `kHotkey` in one
place) → `StatusItemController.toggle()`. Registration failure (combo taken) → log and
continue; the icon still works.

**Launch at Login** — `SMAppService.mainApp` toggle in the footer; reflects actual
registration state on each popover open.

## UI

```
┌──────────────────────────────────────────────┐
│  clausona usage limits                       │
│                                              │
│ ▸ personal    ● 5h  29% (3h42m)  7d  61% (2d4h) │   ● = health dot (green/red/gray)
│   personal2   ● 5h  82% (0h58m)  7d  74% (4d1h) │   ▸ = active profile
│   work        ● 5h   4% (4h55m)  7d  12% (5d2h) │   row hover → [Use] button
│   work-belen  ● 5h   —          7d   —          │   red dot row → [Repair] button
│   personal3   ⚠ login needed — clausona login…  │
│ ────────────────────────────────────────────│
│  Updated 2m ago   ↻ Refresh                  │
│  ◻ Launch at Login              Quit ⌘Q      │
└──────────────────────────────────────────────┘
```

- Percent colors match the CLI: green < 70, yellow < 90, red ≥ 90. Reset countdown in dimmed `3h42m` form.
- **Switch:** hovering a non-active row reveals `Use`; click runs `clausona use <name>`, optimistically moves the ▸, reverts with an inline error toast on failure. (Affects new terminals only — worth a tooltip.)
- **Repair:** hovering a red-dot row reveals `Repair`; click runs `clausona repair <name>`, shows a spinner on the dot, then re-runs doctor for that snapshot.
- **Per-profile errors** (expired token, HTTP failure) render as a dimmed message in the row — one bad profile never blocks the others.
- **Empty states:** no `profiles.json` → "clausona is not set up — run `clausona init` in a terminal"; CLI missing → limits-only mode with hint.

## Error handling

| Failure | Behavior |
| --- | --- |
| `profiles.json` missing/unparseable | Full-popover empty state with guidance |
| Keychain item missing | Row: "no credentials found" |
| Token expired | Row: "login needed — clausona login `<name>`" |
| Usage HTTP ≠ 200 / timeout | Row keeps last good values, dimmed "HTTP 401" suffix; snapshot marked stale |
| `clausona use`/`repair` non-zero exit | Inline toast with first line of stderr; state reverted |
| Doctor output unparseable | Health dots gray ("unknown"); never blocks limits |

## Build & distribution

- `swift build -c release` + `make install`: assembles `Clausona.app` (Info.plist with `LSUIElement`, bundle id `com.bernardocabral.clausona`), ad-hoc codesigns, copies to `~/Applications`.
- Colleagues: build from source (avoids Gatekeeper), or right-click → Open a shared .app once. They need clausona itself installed; the app degrades gracefully if not.

## Testing

- **Unit tests** (XCTest, pure logic): keychain service-name hashing against a known sha256 fixture; `profiles.json` decoding (full/minimal/garbage); usage response decoding (both windows, one missing, malformed); doctor-output parser against captured real output (healthy, N issues, unparseable); duration formatting (`3h42m`, `2d4h`, `5m`, negative → `?`); staleness logic.
- **Manual checklist:** hotkey toggles with highlight; click toggles; switch moves ▸ and `clausona current` agrees; repair clears doctor issues; launch-at-login survives reboot; degraded modes (rename clausona binary, rename profiles.json).

## Success criteria

1. ⌃⌥⌘L (and icon click) opens the popover with all 5 profiles' limits in < 100 ms (cached) and fresh data within ~2 s.
2. Switching profile from the popover changes `clausona current`'s answer.
3. Repair from the popover resolves a repairable doctor issue.
4. App runs with no permission prompts beyond the existing keychain ACL.
