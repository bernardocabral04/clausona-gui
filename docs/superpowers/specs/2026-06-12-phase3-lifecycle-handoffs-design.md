# Clausona GUI — Phase 3: Lifecycle handoffs & settings

**Date:** 2026-06-12
**Status:** Approved 2026-06-13
**Depends on:** [Phase 1](2026-06-12-phase1-menubar-core-design.md), [Phase 2](2026-06-12-phase2-main-window-design.md)

## Overview

Profile lifecycle operations — add, login, remove, init, config — are interactive
Ink TUI flows inside the third-party clausona CLI. We do not reimplement them (OAuth
flows, account discovery, and confirmation logic belong to clausona). Instead the GUI
**hands off**: it opens the user's terminal running the right clausona command, then
detects the result by watching clausona's state files. Phase 3 also adds the app's
own settings pane.

## Goals

- Start any lifecycle flow from the GUI: Add profile, Re-authenticate (login), Remove profile, Initial setup (init), Configure profile (config).
- The GUI reflects the result automatically when the terminal flow finishes — no manual refresh.
- A settings pane for the few app-level preferences.

## Non-goals

- Embedding a terminal emulator in the app.
- Reimplementing any clausona TUI flow natively.
- Driving the TUI programmatically (expect/PTY scripting) — fragile against upstream changes.

## Terminal handoff

**TerminalLauncher** component:

- Default target: **Terminal.app** via `NSAppleScript` — `do script "clausona add"` + activate. Works on every Mac with no extra install.
- Configurable alternative (settings): **Warp** / **iTerm2** / other, launched via `open -a <App> <wrapper>.command` (a generated temp `.command` file that execs the clausona command then removes itself). Warp is the user's default, so this matters on his machine; Terminal.app remains the zero-config default for colleagues.
- AppleScript automation of Terminal.app prompts once for Automation permission ("Clausona wants to control Terminal") — expected, one-time, and only when first using a handoff feature. The `.command` route needs no permission at all; if AppleScript is denied we fall back to it.

**Entry points:**

| GUI action | Command | Where |
| --- | --- | --- |
| ＋ Add profile | `clausona add <name>` (name asked in a small GUI sheet first, validated `[a-z0-9-]+`) | Popover footer + Profiles sidebar |
| Re-authenticate | `clausona login <name>` | Profile row "login needed" state + profile detail |
| Remove profile | `clausona remove <name>` (clausona's own TUI confirmation is the safety gate; the GUI adds none) | Profile detail only — deliberately not in the popover |
| Initial setup | `clausona init` | The "clausona not set up" empty state |
| Configure | `clausona config <name>` | Profile detail |

## Result detection

**StateWatcher** — `DispatchSource` file watchers on `~/.clausona/profiles.json` and
each profile's credentials (keychain has no watch API, so credential freshness is
re-checked on the next usage refresh). When `profiles.json` changes: ProfileStore
reloads, popover and window update, and a one-shot doctor run refreshes health. This
covers add/remove/init/config regardless of whether the flow was started from the GUI
or a plain terminal — there is no "pending operation" state to track, by design.

## App settings

A standard Settings window (⌘,) with one general tab:

- **Terminal for clausona flows:** Terminal.app (default) / Warp / iTerm2 / Other (choose app).
- **Background refresh interval:** 2 / 5 (default) / 15 minutes.
- **Launch at Login** (same toggle as the popover footer, mirrored).
- Hotkey remains fixed ⌃⌥⌘L (constant in code). Making it configurable is explicitly deferred until someone actually hits a conflict.

Stored in `UserDefaults` (`com.bernardocabral.clausona`).

## Error handling

| Failure | Behavior |
| --- | --- |
| AppleScript automation denied | Fall back to `.command` file route; one-line notice in the sheet |
| Chosen terminal app missing | Fall back to Terminal.app, settings shows a warning |
| Flow abandoned in terminal | Nothing to clean up — GUI state only changes when clausona's files change |
| profiles.json deleted (uninstall) | All surfaces return to the "clausona not set up" empty state |

## Testing

- **Unit tests:** profile-name validation; `.command` wrapper generation (escaping of names); settings round-trip through UserDefaults; StateWatcher debounce (multiple rapid writes → one reload).
- **Manual checklist:** add → terminal opens → completing the flow makes the profile appear in popover without interaction; login on an expired profile clears the "login needed" row; remove updates all views; handoff works from Terminal.app, Warp, and with automation permission denied; init from the empty state on a machine without `~/.clausona`.

## Success criteria

1. Every `clausona help` command is reachable from the GUI: natively (use, repair, list/usage, current, doctor — Phases 1–2) or via handoff (add, login, remove, init, config — this phase). `uninstall`, `shell-init`, `version` are intentionally CLI-only.
2. Completing any terminal flow updates the GUI within ~2 s with no manual refresh.
3. A colleague with a stock Mac (no Karabiner, no Warp) can use every feature with at most the one-time Terminal automation prompt.
