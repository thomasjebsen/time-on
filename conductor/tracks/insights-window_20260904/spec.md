# Specification: Insights Window

**Track ID:** insights-window_20260904
**Type:** Feature
**Created:** 2026-09-04
**Status:** Complete

## Summary

Replace the History window (six stat rows plus one card per session) with a minimal analytics dashboard called Insights: today's headline figures compared with the user's usual, the last four weeks as daily bars, a 24-hour activity profile with typical start and stop times, and one day's sessions as a timeline plus a compact list. No new data is collected; everything derives from the existing `{date, durationSeconds}` history.

## Context

The History window answered "what sessions did I have" and nothing else, and its wall of cards was hard to scan. The owner wanted actionable insight into healthy habits (breaks, long stretches, overwork), daily rhythm, trends, and looking back at a day, without bloat. The product guideline "lightweight and unobtrusive, no unnecessary UI chrome" applies.

Constraints: 100% programmatic AppKit, macOS 12 floor (no Swift Charts), semantic colors resolved at draw time, all data local.

## Acceptance Criteria

### Window and navigation

- [x] Menu item "History..." becomes "Insights..." and opens a single window titled "Insights" (default 460×640, minimum 420×520, resizable, reused on reopen, frame autosaved)
- [x] Flat sections separated by hairline separators with small section headers; no cards
- [x] Light and dark appearance both correct, including while the window is open

### Today so far

- [x] Three stat tiles: Total (including the in-progress session), Longest stretch, Breaks (sessions − 1)
- [x] Each tile compares against the user's usual: median of the same weekday over the previous 8 weeks, each candidate day clipped to the current time of day; fallback to all days with data below two same-weekday samples; "not enough data yet" below two samples overall
- [x] Within 10 minutes of usual reads "about usual"; otherwise a signed delta such as "+35m vs usual Thursday"
- [x] Subtitles are neutral in color; no red/green judgement

### Last 4 weeks

- [x] 28 daily bars, oldest left, today in full accent, others muted; weekday initial under every bar
- [x] Solid reference line at the mean over days with data, labelled "avg …"; hidden when the average is zero
- [x] Hover highlights a bar and shows "Tue, Aug 26 · 5h 12m" in a fixed readout (default "Today · …"); click selects that day in the Day section
- [x] Line beneath: "This week … · Last week … (−12%)", percent omitted when last week is empty

### When you're active

- [x] 24 bars of average active minutes per hour over the 28 completed days before today, sessions split at hour boundaries (DST-safe)
- [x] Hour labels 0/6/12/18/24; hover readout "14:00–15:00 · 42 min avg"
- [x] "Usually start HH:mm · usually stop HH:mm" from medians over Mon–Fri days with data (fallback all days; hidden below three samples)

### Day

- [x] Previous/next day buttons, "Today" button when not on today, titles "Today" / "Yesterday" / "Tuesday, Aug 26"
- [x] Timeline strip from 06:00–22:00 widened to whole hours around earlier/later sessions, capped at 24:00; sessions as accent spans, live session lighter with an accent cap
- [x] Hover readout "09:04 – 10:18 · 1h 14m" over a session and "Break · 23 min" over a gap; default is the day summary "5h 27m · 12 sessions · longest 1h 42m" or "No sessions"
- [x] Compact session list, one 22pt row per session, monospaced digits, duration right-aligned, live row ends in "now"

### Live updates

- [x] Refreshes on session state change and every 60 s while visible; timer stops when the window closes or is occluded
- [x] Refresh updates models in place; the view tree is never rebuilt
- [x] Selected day is an offset from today so a window left open across midnight keeps showing today

### Analytics module and tests

- [x] `SessionAnalytics.swift` is pure Foundation (no AppKit, UserDefaults, or `Date()`), taking `now` and `Calendar` as inputs
- [x] `SessionEntry` moved to its own file so tests compile the real sources
- [x] `make test-analytics` compiles `SessionEntry.swift` + `SessionAnalytics.swift` + `Tests/analytics_tests.swift` into a binary and runs it; `make test` runs both suites
- [x] "Continue last session" keeps the original session start, so newly saved merged sessions never overshoot; spans from older history files that do overshoot are clipped for display while their authoritative seconds still count in totals
- [x] Hover state survives the periodic refresh; the 4-week average excludes today's partial day

## Out of Scope

- New persisted fields (break acknowledgements, pomodoro counts, keep-awake usage)
- Retention change, export changes
- SwiftUI or raising the macOS floor
- A separate notes or generated-text insights block
