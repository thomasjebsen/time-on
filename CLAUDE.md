# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What is Time On

A macOS menu bar app combining screen time tracking (like Pandan) and keep-awake (like Caffeine) in one tool. All data stays local — no accounts, no telemetry. Distributed via Homebrew Cask + GitHub Releases.

## Build & Run

```sh
make app          # Build release binary + macOS app bundle (ad-hoc signed)
make run          # Build and launch
make install      # Copy to /Applications
make uninstall    # Remove from /Applications
make clean        # Clean .build/
```

Requires Swift 5.9+ and macOS 12+. No external dependencies — only system frameworks (Cocoa, CoreGraphics, IOKit, UserNotifications, ServiceManagement).

```sh
make test         # Run SessionManager idle detection tests
```

## Development Context

This codebase is 100% vibe coded — the owner does not have deep knowledge of the implementation details.

## Architecture

Single-target Swift Package Manager project. All source in `Sources/TimeOn/`. No storyboards or XIBs — all UI is programmatic.

### Component Relationships

```
main.swift → AppDelegate (coordinator)
               ├── SessionManager (core business logic)
               │     └── IdleDetector (CoreGraphics CGEventSource idle time queries)
               ├── StatusBarController (menu bar UI + context menu)
               │     └── CaffeineManager (IOKit power assertions)
               ├── PreferencesWindowController (settings window, lazy)
               └── HistoryWindowController (session history, lazy)

Preferences (static UserDefaults wrapper, used by all components)
LaunchAtLoginManager (SMAppService wrapper)
```

### Key Patterns

- **Closure callbacks** for communication (`onUpdate`, `onBreakReminder`, `onStateChanged`) — not delegates, not Combine, not async/await
- **1-second Timer** on main RunLoop drives SessionManager ticks — checks idle, accumulates time, fires callbacks
- **Idle = session end**: when idle threshold exceeded, session ends and a new one starts on return (not pause/resume)
- **System events** (sleep/wake/lock/unlock) routed through AppDelegate to SessionManager
- **Windows** use `isReleasedWhenClosed = false` for reuse

### Data

- Preferences: `UserDefaults` via `Preferences.swift` static accessors
- Session history: `~/Library/Application Support/TimeOn/history.json` — array of `{date, durationSeconds}`, 60-day retention
- Export: JSON or CSV via menu

## Release

Tagging `v*` triggers `.github/workflows/release.yml`: builds app, zips it, publishes to GitHub Releases with SHA256. Update `Casks/time-on.rb` with new version/SHA after release.

## Conductor

Project context artifacts live in `conductor/` — see `conductor/index.md` for navigation.
