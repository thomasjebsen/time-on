# Implementation Plan: Insights Window

**Track ID:** insights-window_20260904
**Spec:** [spec.md](./spec.md)
**Created:** 2026-09-04
**Status:** [x] Complete

## Overview

Three phases: a pure, test-driven analytics module; hand-drawn AppKit chart views; then the window controller and integration. The analytics tests compile the real source files rather than a mirror copy.

## Phase A: Pure analytics module (TDD)

### Tasks

- [x] Task A.1: Move `SessionEntry` to `Sources/TimeOn/SessionEntry.swift`
- [x] Task A.2: Add `make test-analytics` (swiftc -parse-as-library of the real sources + `Tests/analytics_tests.swift`) and make `make test` run both suites
- [x] Task A.3: `DurationFormatter` (compact, signed, minutes, clock)
- [x] Task A.4: `median`
- [x] Task A.5: `intervals(from:live:now:)` — parse, drop invalid, clamp to now, clip overlaps, sort
- [x] Task A.6: `dailyTotals` + `averageSeconds`
- [x] Task A.7: `hourSegments` + `hourProfile` (midnight split, DST fall-back day)
- [x] Task A.8: `typicalHours`
- [x] Task A.9: `weekComparison`
- [x] Task A.10: `todayStats` with time-of-day clipping of the "usual" candidates
- [x] Task A.11: `dayDetail`
- [x] Task A.12: `snapshot` integration (six-week fixture, empty history)

### Verification

- [x] `make test` passes (62 session assertions + 107 analytics assertions)

## Phase B: Chart views

### Tasks

- [x] Task B.1: `ChartSupport.swift` — `ChartStyle` computed colors, bar path with rounded data end, pixel snapping, `HoverChartView` base class
- [x] Task B.2: `StatTileView`
- [x] Task B.3: `BarChartView` with hover, select, reference line and axis labels
- [x] Task B.4: `DayTimelineView` with segment/gap hover

### Verification

- [x] `swift build` clean

## Phase C: Controller and integration

### Tasks

- [x] Task C.1: `InsightsWindowController` — flipped document view, sections, readouts, row pool, refresh/apply, day navigation, timer and occlusion handling
- [x] Task C.2: `StatusBarController` — property, "Insights..." menu item, `showInsights`, chained `refreshIfVisible` inside the existing `onSessionStateChanged` closure
- [x] Task C.3: Delete `HistoryWindowController.swift`
- [x] Task C.4: Docs (`CLAUDE.md`, `README.md`), conductor track, version 1.3.0

### Verification

- [x] `make app` builds
- [x] Rendered light/dark, past day, hover, empty and narrow states via a preview harness against real data
- [ ] Manual check in the running app: open Insights from the menu, hover, navigate days, toggle appearance, leave open across a session reset
