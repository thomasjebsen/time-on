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
make test            # Run both test suites below
make test-session    # SessionManager idle/break/pomodoro tests (script with a mirror copy of SessionManager)
make test-analytics  # SessionAnalytics tests, compiled against the real source files
```

## Development Context

This codebase is 100% vibe coded — the owner does not have deep knowledge of the implementation details.

## Architecture

Single-target Swift Package Manager project. All source in `Sources/TimeOn/`. No storyboards or XIBs — all UI is programmatic.

### Component Relationships

```
AppDelegate (@main entry point, coordinator)
               ├── SessionManager (core business logic)
               │     └── IdleDetector (CoreGraphics CGEventSource idle time queries)
               ├── NotificationManager (all UserNotifications use: auth, delivery, delegate, logging)
               ├── StatusBarController (menu bar UI + context menu)
               │     ├── CaffeineManager (IOKit power assertions)
               │     ├── BadgePanelController (drop-down badge under the menu bar icon)
               │     └── InsightsWindowController (analytics dashboard, lazy)
               │           ├── SessionAnalytics (pure Foundation: history → InsightsSnapshot)
               │           ├── StatTileView ×3
               │           ├── BarChartView ×2 (28 days, 24 hours)
               │           └── DayTimelineView
               └── PreferencesWindowController (settings window, lazy)

Preferences (static UserDefaults wrapper, used by all components)
LaunchAtLoginManager (SMAppService wrapper)
ChartSupport (ChartStyle colors, bar paths, HoverChartView base class)
```

### Key Patterns

- **Closure callbacks** for communication (`onUpdate`, `onBreakReminder`, `onStateChanged`) — not delegates, not Combine, not async/await
- **1-second Timer** on main RunLoop drives SessionManager ticks — checks idle, accumulates time, fires callbacks
- **Idle = session end**: when idle threshold exceeded, session ends and a new one starts on return (not pause/resume)
- **System events** (sleep/wake/lock/unlock) routed through AppDelegate to SessionManager
- **Windows** use `isReleasedWhenClosed = false` for reuse
- **Charts are hand-drawn `NSView`s** (macOS 12 floor rules out Swift Charts); colors come from `ChartStyle` computed properties so they resolve at draw time and survive light/dark switches
- **`SessionAnalytics` is pure**: no AppKit, UserDefaults, or `Date()` — `now` and `Calendar` are injected, which is what lets `make test-analytics` compile the real file

### Data

- Preferences: `UserDefaults` via `Preferences.swift` static accessors
- Session history: `~/Library/Application Support/TimeOn/history.json` — array of `{date, durationSeconds}` (`SessionEntry.swift`), 60-day retention, sessions ≤ 60 s never saved
- Insights derive everything from that file plus the live session. "Continue last session" keeps the original start (since 1.4.0); history written by older versions can hold entries whose `start + duration` overshoots the next session, so `SessionAnalytics.intervals` clips the display span while keeping the seconds
- Export: JSON or CSV via menu

## Release

Tagging `v*` triggers `.github/workflows/release.yml`: builds app, zips it, publishes to GitHub Releases with SHA256. Update `Casks/time-on.rb` with new version/SHA after release.

## Conductor

Project context artifacts live in `conductor/` — see `conductor/index.md` for navigation.
