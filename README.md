# Time On

A lightweight macOS menu bar app that tracks your active screen time and keeps your Mac awake — combining the best of [Pandan](https://sindresorhus.com/pandan) and [Caffeine](https://intelliscapesolutions.com/apps/caffeine) in one tool.

## Features

**Screen time tracking**
- Shows your active session time right in the menu bar
- Idle detection — automatically resets when you step away
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
brew install --cask thomasjebsen/tap/time-on
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

- **Left-click** — toggle stay awake on/off
- **Right-click** — open the full menu

### Menu

- Current session start time
- Previous session duration and time range
- Total active time today
- Stay awake controls with preset and custom durations
- Reset timer / continue last session
- History window with daily breakdown and averages
- Settings and export options

### Settings

- Break reminder interval (default: 20 minutes)
- Reset threshold (default: 5 minutes of inactivity)
- Show seconds toggle
- Default stay awake duration (default: 5 hours)
- Indicator style picker with custom emoji support
- Launch at login

## Uninstall

```sh
brew uninstall --cask thomasjebsen/tap/time-on
# or
make uninstall
```

## License

MIT
