import Foundation

// Tests for SessionAnalytics, compiled together with the real source files by `make test-analytics`.
// No mirror copies here: Sources/TimeOn/SessionEntry.swift and SessionAnalytics.swift are the code under test.

// ─── Test harness ───

var passed = 0
var failed = 0

func assert(_ condition: Bool, _ message: String, file: String = #file, line: Int = #line) {
    if condition {
        passed += 1
    } else {
        failed += 1
        print("  FAIL: \(message) (\(file):\(line))")
    }
}

func test(_ name: String, _ body: () -> Void) {
    print("• \(name)")
    body()
}

// ─── Fixtures ───

/// Gregorian calendar pinned to Oslo with Monday as the first weekday, so results do not depend on the machine.
let oslo: Calendar = {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(identifier: "Europe/Oslo")!
    calendar.firstWeekday = 2
    calendar.locale = Locale(identifier: "en_US_POSIX")
    return calendar
}()

/// Parses an Oslo wall-clock time such as "2026-09-03 09:04".
func local(_ text: String) -> Date {
    let formatter = DateFormatter()
    formatter.calendar = oslo
    formatter.timeZone = oslo.timeZone
    formatter.locale = Locale(identifier: "en_US_POSIX")
    formatter.dateFormat = "yyyy-MM-dd HH:mm"
    guard let date = formatter.date(from: text) else { fatalError("Bad fixture date: \(text)") }
    return date
}

/// Builds a SessionEntry exactly as the app stores it: ISO8601 UTC "Z" start plus duration in seconds.
func entry(_ localStart: String, minutes: Int) -> SessionEntry {
    let iso = ISO8601DateFormatter()
    return SessionEntry(date: iso.string(from: local(localStart)), durationSeconds: minutes * 60)
}

// ─── DurationFormatter ───

func durationFormatterTests() {
    test("compact renders hours and minutes, dropping hours when zero") {
        assert(DurationFormatter.compact(5 * 3600 + 12 * 60) == "5h 12m", "5h 12m")
        assert(DurationFormatter.compact(42 * 60) == "42m", "42m")
        assert(DurationFormatter.compact(3600) == "1h 0m", "whole hour keeps the minutes part")
        assert(DurationFormatter.compact(0) == "0m", "zero")
        assert(DurationFormatter.compact(59) == "0m", "sub-minute rounds down to 0m")
    }

    test("signedCompact uses a leading plus or a true minus sign") {
        assert(DurationFormatter.signedCompact(80 * 60) == "+1h 20m", "positive delta")
        assert(DurationFormatter.signedCompact(-40 * 60) == "\u{2212}40m", "negative delta uses U+2212")
        assert(DurationFormatter.signedCompact(0) == "0m", "zero has no sign")
    }

    test("minutes rounds to the nearest whole minute") {
        assert(DurationFormatter.minutes(41.6) == "42 min", "rounds up")
        assert(DurationFormatter.minutes(0) == "0 min", "zero")
    }

    test("clock formats a minute of day as HH:mm") {
        assert(DurationFormatter.clock(minuteOfDay: 8 * 60 + 52) == "08:52", "zero-padded hour")
        assert(DurationFormatter.clock(minuteOfDay: 0) == "00:00", "midnight")
        assert(DurationFormatter.clock(minuteOfDay: 24 * 60) == "24:00", "end of day")
    }
}

// ─── median ───

func medianTests() {
    test("median is nil for no values") {
        assert(SessionAnalytics.median([]) == nil, "empty → nil")
    }

    test("median picks the middle value, averaging the two middles for even counts") {
        assert(SessionAnalytics.median([30, 10, 20]) == 20, "odd count, unsorted input")
        assert(SessionAnalytics.median([10, 40, 20, 30]) == 25, "even count averages 20 and 30")
        assert(SessionAnalytics.median([7]) == 7, "single value")
    }
}

// ─── intervals ───

func intervalTests() {
    let noon = local("2026-09-03 12:00")

    test("intervals parses UTC entries into sorted spans with end = start + duration") {
        let result = SessionAnalytics.intervals(
            from: [entry("2026-09-03 10:00", minutes: 30), entry("2026-09-03 09:00", minutes: 60)],
            live: nil, now: noon)
        assert(result.count == 2, "two intervals")
        assert(result.first?.start == local("2026-09-03 09:00"), "sorted by start")
        assert(result.first?.end == local("2026-09-03 10:00"), "end is start + duration")
        assert(result.first?.seconds == 3600, "seconds preserved")
        assert(result.first?.isLive == false, "stored entries are not live")
    }

    test("intervals drops unparsable dates, non-positive durations and future starts") {
        let result = SessionAnalytics.intervals(
            from: [SessionEntry(date: "garbage", durationSeconds: 600),
                   entry("2026-09-03 09:00", minutes: 0),
                   entry("2026-09-03 13:00", minutes: 10)],
            live: nil, now: noon)
        assert(result.isEmpty, "nothing usable remains")
    }

    test("intervals appends the live session ending now, carrying its active seconds") {
        let live = LiveSession(start: local("2026-09-03 11:00"), activeSeconds: 900)
        let result = SessionAnalytics.intervals(from: [entry("2026-09-03 09:00", minutes: 60)], live: live, now: noon)
        assert(result.count == 2, "stored + live")
        assert(result.last?.isLive == true, "last is live")
        assert(result.last?.start == local("2026-09-03 11:00"), "live start")
        assert(result.last?.end == noon, "live span ends now")
        assert(result.last?.seconds == 900, "live seconds are the active seconds")
    }

    test("intervals clips a stored span that overshoots into the next session but keeps its seconds") {
        // "Continue last session" stores start = continue moment with the merged duration,
        // so start + duration can run past the next session's start.
        let result = SessionAnalytics.intervals(
            from: [entry("2026-09-03 09:35", minutes: 55), entry("2026-09-03 10:10", minutes: 30)],
            live: nil, now: noon)
        assert(result[0].end == local("2026-09-03 10:10"), "first span clipped to the next start")
        assert(result[0].seconds == 55 * 60, "first keeps its stored seconds")
        assert(result[1].start == local("2026-09-03 10:10") && result[1].seconds == 30 * 60, "second untouched")
    }

    test("intervals clamps a stored span to now and clips into a live session") {
        let live = LiveSession(start: local("2026-09-03 11:50"), activeSeconds: 600)
        let result = SessionAnalytics.intervals(
            from: [entry("2026-09-03 11:00", minutes: 70)], live: live, now: noon)
        assert(result[0].end == local("2026-09-03 11:50"), "stored span ends where the live one begins")
        assert(result[0].seconds == 70 * 60, "stored seconds kept")
        assert(result[1].end == noon, "live span ends now")
    }
}

/// A stored (non-live) interval between two Oslo wall-clock times.
func span(_ start: String, _ end: String) -> SessionInterval {
    let s = local(start), e = local(end)
    return SessionInterval(start: s, end: e, seconds: Int(e.timeIntervalSince(s)), isLive: false)
}

func day(_ text: String) -> Date { oslo.startOfDay(for: local(text + " 12:00")) }

// ─── dailyTotals ───

func dailyTotalsTests() {
    let today = day("2026-09-03")

    test("dailyTotals returns one entry per day, oldest first, with zeros for missing days") {
        let totals = SessionAnalytics.dailyTotals(
            [span("2026-09-03 09:00", "2026-09-03 10:00"), span("2026-09-01 10:00", "2026-09-01 10:30")],
            today: today, days: 3, calendar: oslo)
        assert(totals.count == 3, "three days")
        assert(totals[0].dayStart == day("2026-09-01") && totals[0].seconds == 1800 && totals[0].sessionCount == 1, "oldest first")
        assert(totals[1].seconds == 0 && totals[1].hasData == false, "gap day has no data")
        assert(totals[2].dayStart == today && totals[2].seconds == 3600, "today last")
    }

    test("dailyTotals attributes a session crossing midnight to its start day") {
        let totals = SessionAnalytics.dailyTotals(
            [span("2026-09-02 23:30", "2026-09-03 00:30")], today: today, days: 2, calendar: oslo)
        assert(totals[0].seconds == 3600, "all on Sep 2")
        assert(totals[1].seconds == 0, "nothing on Sep 3")
    }

    test("dailyTotals uses the authoritative seconds, so a continued live session counts fully") {
        let live = SessionInterval(start: local("2026-09-03 11:50"), end: local("2026-09-03 12:00"), seconds: 3000, isLive: true)
        let totals = SessionAnalytics.dailyTotals([live], today: today, days: 1, calendar: oslo)
        assert(totals[0].seconds == 3000, "seconds, not span length")
    }

    test("dailyTotals ignores sessions outside the window") {
        let totals = SessionAnalytics.dailyTotals(
            [span("2026-08-01 09:00", "2026-08-01 10:00"), span("2026-09-04 09:00", "2026-09-04 10:00")],
            today: today, days: 2, calendar: oslo)
        assert(totals.allSatisfy { $0.seconds == 0 }, "nothing inside the window")
    }

    test("averageSeconds averages over days with data only, nil when there are none") {
        let totals = SessionAnalytics.dailyTotals(
            [span("2026-09-03 09:00", "2026-09-03 10:00"), span("2026-09-01 10:00", "2026-09-01 10:30")],
            today: today, days: 3, calendar: oslo)
        assert(SessionAnalytics.averageSeconds(totals) == 2700, "(1800 + 3600) / 2")
        assert(SessionAnalytics.averageSeconds(SessionAnalytics.dailyTotals([], today: today, days: 3, calendar: oslo)) == nil, "no data → nil")
    }
}

// ─── hourSegments / hourProfile ───

func hourProfileTests() {
    test("hourSegments splits a span at hour boundaries") {
        let segments = SessionAnalytics.hourSegments(span("2026-09-03 09:30", "2026-09-03 11:15"), calendar: oslo)
        assert(segments.map { $0.hour } == [9, 10, 11], "three hours touched")
        assert(segments.map { Int($0.seconds) } == [1800, 3600, 900], "seconds per hour")
        assert(segments.allSatisfy { $0.dayStart == day("2026-09-03") }, "same day")
    }

    test("hourSegments rolls across midnight into the next day") {
        let segments = SessionAnalytics.hourSegments(span("2026-09-02 23:30", "2026-09-03 00:30"), calendar: oslo)
        assert(segments.count == 2, "two segments")
        assert(segments[0].dayStart == day("2026-09-02") && segments[0].hour == 23 && segments[0].seconds == 1800, "before midnight")
        assert(segments[1].dayStart == day("2026-09-03") && segments[1].hour == 0 && segments[1].seconds == 1800, "after midnight")
    }

    test("hourSegments on the DST fall-back day keeps hours in 0...23 and sums to the span") {
        // Oslo leaves DST on 2026-10-25 at 03:00 CEST → 02:00 CET, so 02:xx happens twice.
        let start = local("2026-10-25 01:30")
        let end = start.addingTimeInterval(3 * 3600)
        let interval = SessionInterval(start: start, end: end, seconds: 3 * 3600, isLive: false)
        let segments = SessionAnalytics.hourSegments(interval, calendar: oslo)
        assert(segments.allSatisfy { (0...23).contains($0.hour) }, "hours in range")
        assert(Int(segments.reduce(0) { $0 + $1.seconds }) == 3 * 3600, "sums to three hours")
        assert(Int(segments.filter { $0.hour == 2 }.reduce(0) { $0 + $1.seconds }) == 7200, "repeated hour 2 collects both passes")
    }

    test("hourProfile averages per hour over days with data inside the window") {
        let days = [day("2026-09-01"), day("2026-09-02"), day("2026-09-03")]
        let profile = SessionAnalytics.hourProfile(
            [span("2026-08-31 09:00", "2026-08-31 10:00"),   // outside the window
             span("2026-09-01 09:00", "2026-09-01 10:00"),
             span("2026-09-02 09:00", "2026-09-02 09:30")],
            days: days, calendar: oslo)
        assert(profile.daysWithData == 2, "Sep 3 has no data, Aug 31 is outside")
        assert(profile.averageMinutes.count == 24, "24 buckets")
        assert(profile.averageMinutes[9] == 45, "(60 + 30) / 2")
        assert(profile.averageMinutes[10] == 0, "nothing at 10")
    }

    test("hourProfile with no data is all zeros") {
        let profile = SessionAnalytics.hourProfile([], days: [day("2026-09-01")], calendar: oslo)
        assert(profile.daysWithData == 0 && profile.averageMinutes == Array(repeating: 0, count: 24), "empty profile")
    }
}

// ─── minuteOfDay ───

func minuteOfDayTests() {
    test("fractionalMinuteOfDay carries seconds as a fraction and minuteOfDay truncates them") {
        let date = local("2026-09-03 09:04").addingTimeInterval(30)
        assert(SessionAnalytics.fractionalMinuteOfDay(date, calendar: oslo) == 544.5, "09:04:30 → 544.5")
        assert(SessionAnalytics.minuteOfDay(date, calendar: oslo) == 544, "09:04:30 → 544")
    }
}

// ─── typicalHours ───

func typicalHoursTests() {
    // 2026-08-31 is a Monday; 2026-09-05/06 are Saturday/Sunday.
    let week = SessionAnalytics.dayStarts(endingAt: day("2026-09-06"), count: 7, calendar: oslo)

    test("typicalHours takes medians of first start and last end over weekdays, ignoring weekends") {
        let result = SessionAnalytics.typicalHours(
            [span("2026-08-31 08:50", "2026-08-31 12:00"), span("2026-08-31 13:00", "2026-08-31 17:30"),
             span("2026-09-01 09:00", "2026-09-01 12:00"), span("2026-09-01 13:00", "2026-09-01 17:40"),
             span("2026-09-02 08:30", "2026-09-02 18:00"),
             span("2026-09-05 11:00", "2026-09-05 12:00")],
            days: week, calendar: oslo)
        assert(result == TypicalHours(startMinuteOfDay: 8 * 60 + 50, stopMinuteOfDay: 17 * 60 + 40), "08:50 / 17:40, Saturday ignored")
    }

    test("typicalHours falls back to all days when fewer than three weekdays have data") {
        let result = SessionAnalytics.typicalHours(
            [span("2026-08-31 09:00", "2026-08-31 17:00"), span("2026-09-01 09:00", "2026-09-01 17:00"),
             span("2026-09-05 10:00", "2026-09-05 16:00"), span("2026-09-06 10:00", "2026-09-06 16:00")],
            days: week, calendar: oslo)
        assert(result == TypicalHours(startMinuteOfDay: 9 * 60 + 30, stopMinuteOfDay: 16 * 60 + 30), "median over all four days")
    }

    test("typicalHours is nil with fewer than three days of data") {
        let result = SessionAnalytics.typicalHours(
            [span("2026-08-31 09:00", "2026-08-31 17:00"), span("2026-09-01 09:00", "2026-09-01 17:00")],
            days: week, calendar: oslo)
        assert(result == nil, "two samples is not enough")
    }

    test("typicalHours clips a session that ends after midnight to the end of its start day") {
        let result = SessionAnalytics.typicalHours(
            [span("2026-08-31 09:00", "2026-08-31 17:00"),
             span("2026-09-01 22:00", "2026-09-02 00:30"),
             span("2026-09-02 20:00", "2026-09-02 23:50")],
            days: week, calendar: oslo)
        assert(result?.stopMinuteOfDay == 23 * 60 + 50, "median of 17:00, 23:59 (clipped), 23:50")
    }
}

// ─── weekComparison ───

func weekComparisonTests() {
    let now = local("2026-09-03 12:00")   // Thursday

    test("weekComparison sums Monday-start weeks, counting Sunday as the end of the previous week") {
        let result = SessionAnalytics.weekComparison(
            [span("2026-08-30 10:00", "2026-08-30 11:00"),   // Sunday → last week
             span("2026-08-31 09:00", "2026-08-31 10:00"),   // Monday → this week
             span("2026-09-03 09:00", "2026-09-03 09:30")],
            now: now, calendar: oslo)
        assert(result.thisWeekSeconds == 5400, "this week")
        assert(result.lastWeekSeconds == 3600, "last week")
        assert(result.percentChange == 50, "+50%")
    }

    test("weekComparison has no percent when last week was empty") {
        let result = SessionAnalytics.weekComparison([span("2026-09-01 09:00", "2026-09-01 10:00")], now: now, calendar: oslo)
        assert(result.percentChange == nil, "division by zero avoided")
    }

    test("weekComparison rounds the percent change to the nearest whole percent") {
        let thisWeek = SessionInterval(start: local("2026-09-01 09:00"), end: local("2026-09-01 10:00"), seconds: 79800, isLive: false)
        let lastWeek = SessionInterval(start: local("2026-08-25 09:00"), end: local("2026-08-25 10:00"), seconds: 90300, isLive: false)
        let result = SessionAnalytics.weekComparison([thisWeek, lastWeek], now: now, calendar: oslo)
        assert(result.percentChange == -12, "−11.6% rounds to −12")
    }
}

// ─── todayStats ───

func todayStatsTests() {
    let today = day("2026-09-03")             // Thursday
    let noon = local("2026-09-03 12:00")
    let live = SessionInterval(start: local("2026-09-03 11:40"), end: noon, seconds: 1200, isLive: true)
    let todaySessions = [span("2026-09-03 09:00", "2026-09-03 10:30"), span("2026-09-03 10:45", "2026-09-03 11:30"), live]
    // Three earlier Thursdays. By noon they hold 4h / 3h / 2h45m, with 0 / 0 / 1 breaks.
    let thursdays = [
        span("2026-08-27 08:00", "2026-08-27 12:00"), span("2026-08-27 13:00", "2026-08-27 17:00"),
        span("2026-08-20 09:00", "2026-08-20 13:00"), span("2026-08-20 14:00", "2026-08-20 18:00"),
        span("2026-08-13 08:30", "2026-08-13 10:00"), span("2026-08-13 10:15", "2026-08-13 11:30"), span("2026-08-13 12:30", "2026-08-13 16:30"),
    ]
    let hugeWednesday = [span("2026-09-02 06:00", "2026-09-02 12:00"), span("2026-09-02 13:00", "2026-09-02 20:00")]

    test("todayStats reports today's total, longest stretch and breaks including the live session") {
        let stats = SessionAnalytics.todayStats(todaySessions + thursdays, today: today, now: noon, calendar: oslo)
        assert(stats.totalSeconds == 5400 + 2700 + 1200, "total")
        assert(stats.longestSeconds == 5400, "longest")
        assert(stats.breaks == 2, "three sessions → two breaks")
    }

    test("todayStats compares against the same weekday's median, clipped to the current time of day") {
        let stats = SessionAnalytics.todayStats(todaySessions + thursdays + hugeWednesday, today: today, now: noon, calendar: oslo)
        assert(stats.totalVsUsual == .delta(seconds: 9300 - 10800, usual: 10800), "median of 4h/3h/2h45m by noon is 3h; Wednesday ignored")
        assert(stats.usualLongestSeconds == 10800, "median longest by noon")
        assert(stats.usualBreaks == 0, "median breaks by noon")
    }

    test("todayStats falls back to all days when fewer than two same-weekday samples exist") {
        let others = [span("2026-08-27 08:00", "2026-08-27 12:00"),   // one Thursday: 4h by noon
                      span("2026-09-02 10:00", "2026-09-02 12:00"),   // Wednesday: 2h
                      span("2026-09-01 10:00", "2026-09-01 12:00")]   // Tuesday: 2h
        let stats = SessionAnalytics.todayStats(todaySessions + others, today: today, now: noon, calendar: oslo)
        assert(stats.totalVsUsual == .delta(seconds: 9300 - 7200, usual: 7200), "median over all three days")
    }

    test("todayStats has no comparison with fewer than two days of history") {
        let stats = SessionAnalytics.todayStats(todaySessions + [span("2026-08-27 08:00", "2026-08-27 12:00")], today: today, now: noon, calendar: oslo)
        assert(stats.totalVsUsual == .notEnoughData, "one sample is not enough")
        assert(stats.usualLongestSeconds == nil && stats.usualBreaks == nil, "no usual figures either")
    }

    test("todayStats reads about usual when within ten minutes of the median") {
        let closeToday = [span("2026-09-03 08:00", "2026-09-03 11:05")]   // 3h05m vs usual 3h
        let stats = SessionAnalytics.todayStats(closeToday + thursdays, today: today, now: noon, calendar: oslo)
        assert(stats.totalVsUsual == .aboutUsual(usual: 10800), "5 minutes over is about usual")
    }

    test("todayStats counts a candidate day as a sample even when all its activity is after the cutoff") {
        let dawn = local("2026-09-03 07:00")
        let stats = SessionAnalytics.todayStats(thursdays, today: today, now: dawn, calendar: oslo)
        assert(stats.totalVsUsual == .aboutUsual(usual: 0), "nothing yet today, and nothing by 07:00 on a usual Thursday")
    }
}

// ─── dayDetail ───

func dayDetailTests() {
    let sep3 = day("2026-09-03")

    test("dayDetail lists the day's sessions in order with total and longest") {
        let detail = SessionAnalytics.dayDetail(
            [span("2026-09-02 09:00", "2026-09-02 10:00"),
             span("2026-09-03 09:00", "2026-09-03 10:30"), span("2026-09-03 11:00", "2026-09-03 11:20")],
            dayStart: sep3, calendar: oslo)
        assert(detail.dayStart == sep3, "day")
        assert(detail.sessions.count == 2, "only Sep 3 sessions")
        assert(detail.sessions.first?.start == local("2026-09-03 09:00"), "in order")
        assert(detail.totalSeconds == 5400 + 1200 && detail.longestSeconds == 5400, "total and longest")
    }

    test("dayDetail defaults the timeline to 06:00–22:00") {
        let detail = SessionAnalytics.dayDetail([span("2026-09-03 09:00", "2026-09-03 17:00")], dayStart: sep3, calendar: oslo)
        assert(detail.timelineStartMinute == 6 * 60 && detail.timelineEndMinute == 22 * 60, "default bounds")
    }

    test("dayDetail widens the timeline to whole hours around early or late sessions") {
        let detail = SessionAnalytics.dayDetail(
            [span("2026-09-03 05:20", "2026-09-03 06:00"), span("2026-09-03 21:30", "2026-09-03 22:40")],
            dayStart: sep3, calendar: oslo)
        assert(detail.timelineStartMinute == 5 * 60 && detail.timelineEndMinute == 23 * 60, "05:00–23:00")
    }

    test("dayDetail clips a session crossing midnight to the day end and caps the timeline at 24:00") {
        let detail = SessionAnalytics.dayDetail([span("2026-09-03 23:30", "2026-09-04 00:30")], dayStart: sep3, calendar: oslo)
        assert(detail.sessions.first?.end == day("2026-09-04"), "span ends at midnight")
        assert(detail.sessions.first?.seconds == 3600, "seconds untouched")
        assert(detail.timelineEndMinute == 24 * 60, "capped")
    }

    test("dayDetail for a day without sessions is empty with the default timeline") {
        let detail = SessionAnalytics.dayDetail([], dayStart: sep3, calendar: oslo)
        assert(detail.sessions.isEmpty && detail.totalSeconds == 0 && detail.longestSeconds == 0, "empty")
        assert(detail.timelineStartMinute == 6 * 60 && detail.timelineEndMinute == 22 * 60, "default bounds")
    }
}

// ─── snapshot ───

func snapshotTests() {
    let now = local("2026-09-03 12:00")   // Thursday
    let today = day("2026-09-03")

    test("snapshot on an empty history yields zeros and no comparisons") {
        let snap = SessionAnalytics.snapshot(entries: [], live: nil, selectedDayOffset: 0, now: now, calendar: oslo)
        assert(snap.today == today, "today is the start of now's day")
        assert(snap.dailyTotals.count == 28 && snap.dailyTotals.allSatisfy { !$0.hasData }, "28 empty days")
        assert(snap.windowAverageSeconds == nil, "no average")
        assert(snap.todayStats.totalSeconds == 0 && snap.todayStats.totalVsUsual == .notEnoughData, "no today figures")
        assert(snap.hourProfile.daysWithData == 0, "empty profile")
        assert(snap.typicalHours == nil, "no typical hours")
        assert(snap.weeks == WeekComparison(thisWeekSeconds: 0, lastWeekSeconds: 0), "empty weeks")
        assert(snap.dayDetail.sessions.isEmpty && snap.dayDetail.timelineStartMinute == 6 * 60, "empty day")
    }

    // Six weeks of weekdays with 09:00–12:00 and 13:00–17:00, then today 09:00–11:00 plus a live session.
    let iso = ISO8601DateFormatter()
    var entries: [SessionEntry] = []
    for dayStart in SessionAnalytics.dayStarts(endingAt: day("2026-09-02"), count: 42, calendar: oslo)
    where (2...6).contains(oslo.component(.weekday, from: dayStart)) {
        let morning = oslo.date(byAdding: .hour, value: 9, to: dayStart)!
        let afternoon = oslo.date(byAdding: .hour, value: 13, to: dayStart)!
        entries.append(SessionEntry(date: iso.string(from: morning), durationSeconds: 3 * 3600))
        entries.append(SessionEntry(date: iso.string(from: afternoon), durationSeconds: 4 * 3600))
    }
    entries.append(entry("2026-09-03 09:00", minutes: 120))
    let live = LiveSession(start: local("2026-09-03 11:15"), activeSeconds: 2700)

    test("snapshot assembles every section from a six-week history") {
        let snap = SessionAnalytics.snapshot(entries: entries, live: live, selectedDayOffset: 0, now: now, calendar: oslo)
        assert(snap.dailyTotals.last?.dayStart == today && snap.dailyTotals.last?.seconds == 7200 + 2700, "today's bar includes the live session")
        assert(snap.windowAverageSeconds == 25200, "mean over the 19 completed weekdays in the window; today's partial day is excluded")
        assert(snap.todayStats.totalVsUsual == .delta(seconds: 9900 - 10800, usual: 10800), "vs 3h by noon on a usual Thursday")
        assert(snap.hourProfile.daysWithData == 20 && snap.hourProfile.averageMinutes[9] == 60 && snap.hourProfile.averageMinutes[12] == 0, "hour profile over the 28 days before today")
        assert(snap.typicalHours == TypicalHours(startMinuteOfDay: 9 * 60, stopMinuteOfDay: 17 * 60), "09:00–17:00")
        assert(snap.weeks.thisWeekSeconds == 3 * 25200 + 9900 && snap.weeks.lastWeekSeconds == 5 * 25200, "Mon–Wed + today vs a full week")
        assert(snap.weeks.percentChange == -32, "−32%")
        assert(snap.dayDetail.sessions.count == 2 && snap.dayDetail.sessions.last?.isLive == true, "today's detail is the stored session then the live one")
    }

    test("snapshot selects the detail day by offset from today") {
        let snap = SessionAnalytics.snapshot(entries: entries, live: live, selectedDayOffset: -1, now: now, calendar: oslo)
        assert(snap.dayDetail.dayStart == day("2026-09-02") && snap.dayDetail.sessions.count == 2, "yesterday")
        assert(snap.dayDetail.totalSeconds == 25200, "yesterday's total")
    }
}

// ─── Entry point ───

@main
enum AnalyticsTests {
    static func main() {
        durationFormatterTests()
        medianTests()
        intervalTests()
        dailyTotalsTests()
        hourProfileTests()
        minuteOfDayTests()
        typicalHoursTests()
        weekComparisonTests()
        todayStatsTests()
        dayDetailTests()
        snapshotTests()

        print("\n\(passed) passed, \(failed) failed")
        if failed > 0 {
            exit(1)
        }
    }
}
