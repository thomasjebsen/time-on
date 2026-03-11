# Time On

A lightweight macOS menu bar app that tracks your active screen time and keeps your Mac awake — combining the best of [Pandan](https://sindresorhus.com/pandan) and [Caffeine](https://intelliscapesolutions.com/apps/caffeine) in one tool.

## Features

**Screen time tracking**
- Shows your active session time right in the menu bar
- Idle detection — automatically pauses when you step away
- Sleep/wake and screen lock awareness
- Break reminders at configurable intervals
- Session history with stats (daily averages, totals)
- Export history to JSON or CSV

**Stay awake**
- Left-click the timer to prevent your Mac from sleeping
- Configurable indicator style (●, ☀, ☾, ⚡, ★, or your own emoji)
- "Activate For" menu with preset and custom durations
- Automatic deactivation when the timer expires

**Privacy first** — all data stays on your machine. No accounts, no telemetry, no internet access.

## Install

### Homebrew

```sh
brew install --cask time-on
```

### Build from source

Requires Swift 5.9+ and macOS 12+.

```sh
git clone https://github.com/thomasjebsen/time-on.git
cd time-on
make app
open .build/release/TimeOn.app
```

To install to Applications:

```sh
make install
```

## Usage

After launching, Time On appears in your menu bar showing elapsed active time.

- **Left-click** — toggle Stay Awake on/off
- **Right-click** — open the full menu

### Menu

- Current session start time
- Previous session duration and time range
- Total active time today
- Stay Awake controls with "Activate For" durations
- Reset Timer / Continue Last Session
- History window with daily breakdown and averages
- Settings and export options

### Settings

- Break reminder interval (default: 20 minutes)
- Idle threshold (default: 5 minutes of inactivity)
- Show seconds toggle
- Default Stay Awake duration
- Indicator style picker with custom emoji support

## Uninstall

```sh
brew uninstall --cask time-on
# or
make uninstall
```

## License

MIT
