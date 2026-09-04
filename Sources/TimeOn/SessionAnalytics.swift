import Foundation

// Pure analytics over persisted sessions. No AppKit, no UserDefaults, no Date() calls:
// everything is derived from the entries, an injected `now`, and an injected `Calendar`,
// so the whole file compiles into the analytics test binary (see `make test-analytics`).

// MARK: - Model

/// The in-progress session, as reported by SessionManager.
struct LiveSession: Equatable {
    let start: Date
    /// Active seconds so far. Can exceed `now - start` after "Continue last session".
    let activeSeconds: TimeInterval
}

/// One session, normalized for analytics.
///
/// `seconds` is the authoritative duration used for totals. `[start, end]` is the span used for
/// drawing and hour bucketing; it never overlaps a neighbour and never extends past `now`, which
/// can make it shorter than `seconds` for a session that was continued after a break.
struct SessionInterval: Equatable {
    let start: Date
    let end: Date
    let seconds: Int
    let isLive: Bool
}

/// Active time on one local calendar day.
struct DayTotal: Equatable {
    let dayStart: Date
    let seconds: Int
    let sessionCount: Int
    var hasData: Bool { sessionCount > 0 }
}

/// The part of a session that falls inside one clock hour of one day.
struct HourSegment: Equatable {
    let dayStart: Date
    let hour: Int
    let seconds: TimeInterval
}

/// Average active minutes per clock hour over the days that had any activity.
struct HourProfile: Equatable {
    let averageMinutes: [Double]
    let daysWithData: Int
}

/// Median first-start and last-stop times, as minutes after local midnight.
struct TypicalHours: Equatable {
    let startMinuteOfDay: Int
    let stopMinuteOfDay: Int
}

/// Active seconds in the current calendar week versus the previous one.
struct WeekComparison: Equatable {
    let thisWeekSeconds: Int
    let lastWeekSeconds: Int

    /// Whole-percent change from last week; nil when last week had no activity.
    var percentChange: Int? {
        guard lastWeekSeconds > 0 else { return nil }
        return Int((Double(thisWeekSeconds - lastWeekSeconds) * 100 / Double(lastWeekSeconds)).rounded())
    }
}

/// How today's figure relates to the user's usual figure for this weekday at this time of day.
enum Comparison: Equatable {
    case notEnoughData
    case aboutUsual(usual: Int)
    case delta(seconds: Int, usual: Int)
}

/// Today's headline figures plus the "usual" values they are compared against.
struct TodayStats: Equatable {
    let totalSeconds: Int
    let longestSeconds: Int
    let breaks: Int
    let totalVsUsual: Comparison
    let usualLongestSeconds: Int?
    let usualBreaks: Int?
}

/// One day's sessions prepared for the timeline and session list.
struct DayDetail: Equatable {
    let dayStart: Date
    /// Sessions that started on this day, in order, with spans clipped at the day's end.
    let sessions: [SessionInterval]
    let totalSeconds: Int
    let longestSeconds: Int
    let timelineStartMinute: Int
    let timelineEndMinute: Int
}

/// Everything the Insights window shows, computed in one pass.
struct InsightsSnapshot: Equatable {
    let now: Date
    let today: Date
    /// The last 28 days, oldest first; the last element is today.
    let dailyTotals: [DayTotal]
    /// Mean over the completed days with data in the window. Today is excluded so the line does not drift all day.
    let windowAverageSeconds: Int?
    let todayStats: TodayStats
    let hourProfile: HourProfile
    let typicalHours: TypicalHours?
    let weeks: WeekComparison
    let dayDetail: DayDetail
}

// MARK: - Analytics

enum SessionAnalytics {

    static let windowDays = 28

    /// Computes the full snapshot. `selectedDayOffset` is 0 for today, negative for earlier days.
    static func snapshot(entries: [SessionEntry], live: LiveSession?, selectedDayOffset: Int,
                         now: Date, calendar: Calendar) -> InsightsSnapshot {
        let today = calendar.startOfDay(for: now)
        let all = intervals(from: entries, live: live, now: now)
        let totals = dailyTotals(all, today: today, days: windowDays, calendar: calendar)
        // Rhythm figures use full days only, so today (still in progress) is excluded.
        let completedDays = Array(dayStarts(endingAt: today, count: windowDays + 1, calendar: calendar).dropLast())
        let selectedDay = calendar.date(byAdding: .day, value: min(0, selectedDayOffset), to: today) ?? today

        return InsightsSnapshot(
            now: now,
            today: today,
            dailyTotals: totals,
            windowAverageSeconds: averageSeconds(Array(totals.dropLast())),
            todayStats: todayStats(all, today: today, now: now, calendar: calendar),
            hourProfile: hourProfile(all, days: completedDays, calendar: calendar),
            typicalHours: typicalHours(all, days: completedDays, calendar: calendar),
            weeks: weekComparison(all, now: now, calendar: calendar),
            dayDetail: dayDetail(all, dayStart: selectedDay, calendar: calendar))
    }

    static let usualLookbackDays = 56
    static let minimumUsualSamples = 2
    static let aboutUsualThresholdSeconds = 600
    static let defaultTimelineStartMinute = 6 * 60
    static let defaultTimelineEndMinute = 22 * 60

    /// Total, longest and session count for one day's sessions, optionally only counting activity
    /// before `cutoff` (sessions starting later are skipped, the running one is clipped).
    private struct DaySummary {
        var total = 0
        var longest = 0
        var count = 0
        var breaks: Int { max(0, count - 1) }

        init(_ intervals: [SessionInterval], cutoff: Date?) {
            for interval in intervals {
                var seconds = interval.seconds
                if let cutoff = cutoff {
                    guard interval.start < cutoff else { continue }
                    seconds = min(seconds, Int(cutoff.timeIntervalSince(interval.start)))
                }
                total += seconds
                longest = max(longest, seconds)
                count += 1
            }
        }
    }

    /// Today's figures compared with the median of the same weekday over the previous eight weeks,
    /// each candidate day clipped to the current time of day so the comparison is fair all day long.
    /// Falls back to all days with data when fewer than two same-weekday samples exist.
    static func todayStats(_ intervals: [SessionInterval], today: Date, now: Date, calendar: Calendar) -> TodayStats {
        let byDay = Dictionary(grouping: intervals) { calendar.startOfDay(for: $0.start) }
        let todaySummary = DaySummary(byDay[today] ?? [], cutoff: nil)

        let candidates = dayStarts(endingAt: today, count: usualLookbackDays + 1, calendar: calendar)
            .dropLast()
            .filter { byDay[$0] != nil }
        let weekday = calendar.component(.weekday, from: today)
        var samples = candidates.filter { calendar.component(.weekday, from: $0) == weekday }
        if samples.count < minimumUsualSamples {
            samples = Array(candidates)
        }
        guard samples.count >= minimumUsualSamples else {
            return TodayStats(totalSeconds: todaySummary.total, longestSeconds: todaySummary.longest,
                              breaks: todaySummary.breaks, totalVsUsual: .notEnoughData,
                              usualLongestSeconds: nil, usualBreaks: nil)
        }

        let elapsed = now.timeIntervalSince(today)
        let summaries = samples.map { DaySummary(byDay[$0] ?? [], cutoff: $0.addingTimeInterval(elapsed)) }
        let usualTotal = median(summaries.map { $0.total }) ?? 0
        let delta = todaySummary.total - usualTotal
        let comparison: Comparison = abs(delta) <= aboutUsualThresholdSeconds
            ? .aboutUsual(usual: usualTotal)
            : .delta(seconds: delta, usual: usualTotal)

        return TodayStats(totalSeconds: todaySummary.total, longestSeconds: todaySummary.longest,
                          breaks: todaySummary.breaks, totalVsUsual: comparison,
                          usualLongestSeconds: median(summaries.map { $0.longest }),
                          usualBreaks: median(summaries.map { $0.breaks }))
    }

    /// The sessions of one day with timeline bounds: 06:00–22:00 by default, widened to whole hours
    /// around earlier or later sessions and capped at 24:00.
    static func dayDetail(_ intervals: [SessionInterval], dayStart: Date, calendar: Calendar) -> DayDetail {
        let dayEnd = calendar.date(byAdding: .day, value: 1, to: dayStart) ?? dayStart.addingTimeInterval(86400)
        let sessions = intervals
            .filter { $0.start >= dayStart && $0.start < dayEnd }
            .map { $0.end > dayEnd ? SessionInterval(start: $0.start, end: dayEnd, seconds: $0.seconds, isLive: $0.isLive) : $0 }

        var startMinute = defaultTimelineStartMinute
        var endMinute = defaultTimelineEndMinute
        if let first = sessions.first {
            startMinute = min(startMinute, minuteOfDay(first.start, calendar: calendar) / 60 * 60)
        }
        if let lastEnd = sessions.map({ $0.end }).max() {
            let lastMinute = lastEnd >= dayEnd ? 24 * 60 : minuteOfDay(lastEnd, calendar: calendar)
            endMinute = min(24 * 60, max(endMinute, (lastMinute + 59) / 60 * 60))
        }

        return DayDetail(dayStart: dayStart, sessions: sessions,
                         totalSeconds: sessions.reduce(0) { $0 + $1.seconds },
                         longestSeconds: sessions.map { $0.seconds }.max() ?? 0,
                         timelineStartMinute: startMinute, timelineEndMinute: endMinute)
    }

    /// Fewer samples than this and a "usual" figure is not shown.
    static let minimumTypicalSamples = 3

    /// Minutes after local midnight, with seconds as a fraction (09:04:30 → 544.5). Used for drawing.
    static func fractionalMinuteOfDay(_ date: Date, calendar: Calendar) -> Double {
        let components = calendar.dateComponents([.hour, .minute, .second], from: date)
        return Double(components.hour ?? 0) * 60 + Double(components.minute ?? 0) + Double(components.second ?? 0) / 60
    }

    /// Whole minutes after local midnight (09:04:30 → 544).
    static func minuteOfDay(_ date: Date, calendar: Calendar) -> Int {
        Int(fractionalMinuteOfDay(date, calendar: calendar))
    }

    /// Median first start and last stop over Monday–Friday days with data, falling back to all days
    /// with data when fewer than three weekdays qualify. Nil when even that is under three samples.
    /// A session that runs past midnight counts as stopping at 23:59 on its start day.
    static func typicalHours(_ intervals: [SessionInterval], days: [Date], calendar: Calendar) -> TypicalHours? {
        let window = Set(days)
        var firstStart: [Date: Int] = [:]
        var lastStop: [Date: Int] = [:]
        for interval in intervals {
            let dayStart = calendar.startOfDay(for: interval.start)
            guard window.contains(dayStart) else { continue }
            let start = minuteOfDay(interval.start, calendar: calendar)
            let stop = calendar.isDate(interval.end, inSameDayAs: interval.start)
                ? minuteOfDay(interval.end, calendar: calendar)
                : 24 * 60 - 1
            firstStart[dayStart] = min(firstStart[dayStart] ?? start, start)
            lastStop[dayStart] = max(lastStop[dayStart] ?? stop, stop)
        }

        var sampleDays = firstStart.keys.filter { (2...6).contains(calendar.component(.weekday, from: $0)) }
        if sampleDays.count < minimumTypicalSamples {
            sampleDays = Array(firstStart.keys)
        }
        guard sampleDays.count >= minimumTypicalSamples,
              let start = median(sampleDays.compactMap { firstStart[$0] }),
              let stop = median(sampleDays.compactMap { lastStop[$0] }) else { return nil }
        return TypicalHours(startMinuteOfDay: start, stopMinuteOfDay: stop)
    }

    /// Sums sessions by start time into the calendar week containing `now` and the week before it.
    static func weekComparison(_ intervals: [SessionInterval], now: Date, calendar: Calendar) -> WeekComparison {
        guard let thisWeek = calendar.dateInterval(of: .weekOfYear, for: now),
              let lastWeekAnchor = calendar.date(byAdding: .weekOfYear, value: -1, to: now),
              let lastWeek = calendar.dateInterval(of: .weekOfYear, for: lastWeekAnchor) else {
            return WeekComparison(thisWeekSeconds: 0, lastWeekSeconds: 0)
        }
        func sum(in week: DateInterval) -> Int {
            intervals.filter { week.start <= $0.start && $0.start < week.end }.reduce(0) { $0 + $1.seconds }
        }
        return WeekComparison(thisWeekSeconds: sum(in: thisWeek), lastWeekSeconds: sum(in: lastWeek))
    }

    /// `count` consecutive day-start dates ending at `last`, oldest first.
    static func dayStarts(endingAt last: Date, count: Int, calendar: Calendar) -> [Date] {
        (0..<count).reversed().compactMap { calendar.date(byAdding: .day, value: -$0, to: last) }
    }

    /// One total per day for the `days` days ending today, oldest first. A session counts entirely
    /// towards the day it started on, using its authoritative `seconds`.
    static func dailyTotals(_ intervals: [SessionInterval], today: Date, days: Int, calendar: Calendar) -> [DayTotal] {
        var seconds: [Date: Int] = [:]
        var counts: [Date: Int] = [:]
        for interval in intervals {
            let key = calendar.startOfDay(for: interval.start)
            seconds[key, default: 0] += interval.seconds
            counts[key, default: 0] += 1
        }
        return dayStarts(endingAt: today, count: days, calendar: calendar).map {
            DayTotal(dayStart: $0, seconds: seconds[$0] ?? 0, sessionCount: counts[$0] ?? 0)
        }
    }

    /// Mean daily seconds over the days that have data. Nil when none do.
    static func averageSeconds(_ totals: [DayTotal]) -> Int? {
        let withData = totals.filter { $0.hasData }
        guard !withData.isEmpty else { return nil }
        return withData.reduce(0) { $0 + $1.seconds } / withData.count
    }

    /// Splits a span at clock-hour boundaries. Uses real hour intervals from the calendar, so on a
    /// DST fall-back day the repeated hour lands in the same bucket twice and totals stay exact.
    static func hourSegments(_ interval: SessionInterval, calendar: Calendar) -> [HourSegment] {
        var segments: [HourSegment] = []
        var cursor = interval.start
        while cursor < interval.end {
            guard let hour = calendar.dateInterval(of: .hour, for: cursor), hour.end > cursor else { break }
            let segmentEnd = min(hour.end, interval.end)
            segments.append(HourSegment(
                dayStart: calendar.startOfDay(for: cursor),
                hour: calendar.component(.hour, from: cursor),
                seconds: segmentEnd.timeIntervalSince(cursor)))
            cursor = hour.end
        }
        return segments
    }

    /// Average active minutes per hour over the given days, dividing by the days that had activity.
    static func hourProfile(_ intervals: [SessionInterval], days: [Date], calendar: Calendar) -> HourProfile {
        let window = Set(days)
        var buckets = Array(repeating: 0.0, count: 24)
        var daysSeen = Set<Date>()
        for interval in intervals {
            for segment in hourSegments(interval, calendar: calendar) where window.contains(segment.dayStart) {
                buckets[segment.hour] += segment.seconds
                daysSeen.insert(segment.dayStart)
            }
        }
        guard !daysSeen.isEmpty else { return HourProfile(averageMinutes: buckets, daysWithData: 0) }
        let divisor = Double(daysSeen.count) * 60
        return HourProfile(averageMinutes: buckets.map { $0 / divisor }, daysWithData: daysSeen.count)
    }

    /// Middle value of the inputs, averaging the two middles for an even count. Nil for no values.
    static func median(_ values: [Int]) -> Int? {
        guard !values.isEmpty else { return nil }
        let sorted = values.sorted()
        let mid = sorted.count / 2
        if sorted.count % 2 == 1 {
            return sorted[mid]
        }
        return (sorted[mid - 1] + sorted[mid]) / 2
    }

    /// Parses stored entries (plus the live session) into sorted, non-overlapping intervals.
    /// Unparsable dates, non-positive durations and sessions starting at or after `now` are dropped.
    static func intervals(from entries: [SessionEntry], live: LiveSession?, now: Date) -> [SessionInterval] {
        let parser = ISO8601DateFormatter()

        var raw: [(start: Date, seconds: Int, isLive: Bool)] = []
        for entry in entries {
            guard entry.durationSeconds > 0, let start = parser.date(from: entry.date), start < now else { continue }
            raw.append((start, entry.durationSeconds, false))
        }
        if let live = live, live.start < now {
            raw.append((live.start, Int(live.activeSeconds.rounded()), true))
        }
        raw.sort { $0.start < $1.start }

        var result: [SessionInterval] = []
        for (index, item) in raw.enumerated() {
            var end = item.isLive ? now : min(now, item.start.addingTimeInterval(TimeInterval(item.seconds)))
            if index + 1 < raw.count {
                end = min(end, raw[index + 1].start)
            }
            end = max(end, item.start)
            result.append(SessionInterval(start: item.start, end: end, seconds: item.seconds, isLive: item.isLive))
        }
        return result
    }
}

// MARK: - Formatting

/// Compact duration strings for the Insights window ("5h 12m", "+1h 20m", "42 min", "08:52").
enum DurationFormatter {
    /// "5h 12m", "42m", "0m". Sub-minute remainders are dropped.
    static func compact(_ seconds: Int) -> String {
        let total = max(0, seconds)
        let hours = total / 3600
        let minutes = (total % 3600) / 60
        return hours > 0 ? "\(hours)h \(minutes)m" : "\(minutes)m"
    }

    /// "+1h 20m" / "−40m" (U+2212 minus). Zero renders as "0m" with no sign.
    static func signedCompact(_ seconds: Int) -> String {
        if seconds > 0 { return "+" + compact(seconds) }
        if seconds < 0 { return "\u{2212}" + compact(-seconds) }
        return compact(0)
    }

    /// "42 min", rounded to the nearest whole minute.
    static func minutes(_ minutes: Double) -> String {
        "\(Int(minutes.rounded())) min"
    }

    /// "08:52" for a minute-of-day value; 1440 renders as "24:00".
    static func clock(minuteOfDay: Int) -> String {
        String(format: "%02d:%02d", minuteOfDay / 60, minuteOfDay % 60)
    }
}
