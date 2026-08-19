import XCTest
@testable import TaskPerfect

/// Tests for `RecurrenceEngine`.
///
/// ⚠️ **These have never been executed** — they were written by reading the
/// implementation, not by running it. Expect a few assertions to need adjusting
/// on the first run. Where one fails, the interesting question is whether the
/// test or the implementation is wrong, and it is worth actually asking rather
/// than editing the expectation until it goes green.
///
/// Every test injects a fixed UTC Gregorian calendar. `RecurrenceEngine` defaults
/// to `.current`, which is right for the app and useless for a test: results would
/// change with the machine's time zone and first weekday, and a suite that passes
/// in London and fails in Auckland teaches nobody anything.
final class RecurrenceEngineTests: XCTestCase {

    // MARK: Fixtures

    /// UTC Gregorian, Sunday-first. Fixed so weekly arithmetic is reproducible.
    private let cal: Calendar = {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "UTC")!
        c.firstWeekday = 1
        return c
    }()

    private func date(_ y: Int, _ m: Int, _ d: Int, _ h: Int = 9, _ min: Int = 0) -> Date {
        cal.date(from: DateComponents(
            timeZone: TimeZone(identifier: "UTC"),
            year: y, month: m, day: d, hour: h, minute: min
        ))!
    }

    private func ymd(_ date: Date) -> String {
        let c = cal.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", c.year!, c.month!, c.day!)
    }

    private func hm(_ date: Date) -> String {
        let c = cal.dateComponents([.hour, .minute], from: date)
        return String(format: "%02d:%02d", c.hour!, c.minute!)
    }

    private func rec(_ pattern: TPRecurrence.Pattern, from start: Date) -> TPRecurrence {
        TPRecurrence(pattern: pattern, range: .noEnd(start: start))
    }

    private func next(
        after reference: Date,
        _ pattern: TPRecurrence.Pattern
    ) -> Date? {
        RecurrenceEngine.nextDate(
            after: reference,
            recurrence: rec(pattern, from: reference),
            calendar: cal
        )
    }

    // MARK: - Daily

    func testDailyAdvancesByInterval() throws {
        let result = next(after: date(2026, 1, 5), .daily(interval: 3))
        XCTAssertEqual(ymd(try XCTUnwrap(result)), "2026-01-08")
    }

    /// `advance` clamps with `max(1, interval)` throughout. A zero interval would
    /// otherwise return the same date forever and `upcoming` would spin.
    func testZeroIntervalIsTreatedAsOne() throws {
        let result = next(after: date(2026, 1, 5), .daily(interval: 0))
        XCTAssertEqual(ymd(try XCTUnwrap(result)), "2026-01-06")
    }

    /// Regression guard for the drift the README calls out: without
    /// `preserveTime`, a task due at 17:30 silently moves to midnight on its
    /// second occurrence.
    func testTimeOfDayIsPreservedAcrossOccurrences() {
        let start = date(2026, 1, 5, 17, 30)
        let dates = RecurrenceEngine.upcoming(
            from: start,
            recurrence: rec(.monthlyAbsolute(dayOfMonth: 5, interval: 1), from: start),
            count: 3,
            calendar: cal
        )
        XCTAssertEqual(dates.count, 3)
        for d in dates {
            XCTAssertEqual(hm(d), "17:30", "occurrence \(ymd(d)) lost its time of day")
        }
    }

    // MARK: - Weekly

    /// From a Monday with Wednesday selected, the next occurrence is that same
    /// week's Wednesday. The interval only applies once the week runs out.
    func testWeeklyTakesRemainingDayInSameWeek() throws {
        let result = next(after: date(2026, 1, 5), .weekly(interval: 1, daysOfWeek: [.wednesday]))
        XCTAssertEqual(ymd(try XCTUnwrap(result)), "2026-01-07")
    }

    /// Every 2 weeks on Monday, starting on a Monday: nothing left in the current
    /// week matches, so it jumps two weeks and takes the earliest wanted day.
    func testWeeklyIntervalJumpsWholeWeeks() throws {
        let result = next(after: date(2026, 1, 5), .weekly(interval: 2, daysOfWeek: [.monday]))
        XCTAssertEqual(ymd(try XCTUnwrap(result)), "2026-01-19")
    }

    /// An empty day set is degenerate and the editor shouldn't produce it, but the
    /// engine still has to answer. It falls back to plain week arithmetic.
    func testWeeklyWithNoDaysSelectedFallsBackToWeekArithmetic() throws {
        let result = next(after: date(2026, 1, 5), .weekly(interval: 1, daysOfWeek: []))
        XCTAssertEqual(ymd(try XCTUnwrap(result)), "2026-01-12")
    }

    // MARK: - Monthly and the day-of-month clamp

    /// "Day 31 of every month" from Jan 31 lands on Feb 28 — not March 3.
    func testDayThirtyOneClampsToShortMonth() throws {
        let result = next(after: date(2026, 1, 31), .monthlyAbsolute(dayOfMonth: 31, interval: 1))
        XCTAssertEqual(ymd(try XCTUnwrap(result)), "2026-02-28")
    }

    /// And it recovers. The clamp is applied per month rather than rewriting the
    /// pattern, so March gets its 31st back.
    func testClampDoesNotPermanentlyShortenThePattern() throws {
        let result = next(after: date(2026, 2, 28), .monthlyAbsolute(dayOfMonth: 31, interval: 1))
        XCTAssertEqual(ymd(try XCTUnwrap(result)), "2026-03-31")
    }

    func testMonthlyRelativeSecondTuesday() throws {
        // Jan 13 2026 is the second Tuesday; Feb 10 2026 is February's.
        let result = next(
            after: date(2026, 1, 13),
            .monthlyRelative(ordinal: .second, weekday: .tuesday, interval: 1)
        )
        XCTAssertEqual(ymd(try XCTUnwrap(result)), "2026-02-10")
    }

    func testMonthlyRelativeFourthFriday() throws {
        // December 2026 has Fridays on the 4th, 11th, 18th and 25th.
        let result = next(
            after: date(2026, 11, 1),
            .monthlyRelative(ordinal: .fourth, weekday: .friday, interval: 1)
        )
        XCTAssertEqual(ymd(try XCTUnwrap(result)), "2026-12-25")
    }

    /// `.last` means the final match in the month, not the fourth. November 2026
    /// has five Mondays, so the two answers differ — which is the point.
    func testLastWeekdayIsNotTheFourth() throws {
        let fourth = next(
            after: date(2026, 10, 1),
            .monthlyRelative(ordinal: .fourth, weekday: .monday, interval: 1)
        )
        let last = next(
            after: date(2026, 10, 1),
            .monthlyRelative(ordinal: .last, weekday: .monday, interval: 1)
        )
        XCTAssertEqual(ymd(try XCTUnwrap(fourth)), "2026-11-23")
        XCTAssertEqual(ymd(try XCTUnwrap(last)), "2026-11-30")
    }

    // MARK: - Yearly

    func testYearlyRelativeLastFridayOfNovember() throws {
        // Nov 27 2026 is the last Friday; Nov 26 2027 is the following year's.
        let result = next(
            after: date(2026, 11, 27),
            .yearlyRelative(ordinal: .last, weekday: .friday, month: 11)
        )
        XCTAssertEqual(ymd(try XCTUnwrap(result)), "2027-11-26")
    }

    /// Feb 29 every year has to land somewhere in a non-leap year. It clamps.
    func testFebruaryTwentyNinthClampsInNonLeapYears() throws {
        let result = next(after: date(2024, 2, 29), .yearlyAbsolute(month: 2, dayOfMonth: 29))
        XCTAssertEqual(ymd(try XCTUnwrap(result)), "2025-02-28")
    }

    // MARK: - Range

    func testEndDateRangeStopsTheSeries() {
        let start = date(2026, 1, 5)
        let recurrence = TPRecurrence(
            pattern: .daily(interval: 1),
            range: .endDate(start: start, end: date(2026, 1, 7))
        )
        XCTAssertNotNil(RecurrenceEngine.nextDate(
            after: date(2026, 1, 6), recurrence: recurrence, calendar: cal))
        XCTAssertNil(RecurrenceEngine.nextDate(
            after: date(2026, 1, 7), recurrence: recurrence, calendar: cal))
    }

    /// The end date is inclusive of the whole final day, so a task due at 17:00 on
    /// the last day isn't dropped for being later than midnight.
    func testEndDateIsInclusiveOfTheWholeFinalDay() {
        let start = date(2026, 1, 5, 17, 0)
        let recurrence = TPRecurrence(
            pattern: .daily(interval: 1),
            range: .endDate(start: start, end: date(2026, 1, 6, 0, 0))
        )
        XCTAssertNotNil(RecurrenceEngine.nextDate(
            after: start, recurrence: recurrence, calendar: cal))
    }

    /// `.numbered` counts the start as occurrence one, and the check walks the
    /// series statelessly rather than keeping a counter that could drift.
    func testNumberedRangeCountsTheStartAsOccurrenceOne() {
        let start = date(2026, 1, 5)
        let recurrence = TPRecurrence(
            pattern: .daily(interval: 1),
            range: .numbered(start: start, occurrences: 3)
        )
        let dates = RecurrenceEngine.upcoming(
            from: start, recurrence: recurrence, count: 5, calendar: cal)
        XCTAssertEqual(dates.map(ymd), ["2026-01-06", "2026-01-07"])
    }

    func testSingleOccurrenceNeverRecurs() {
        let start = date(2026, 1, 5)
        let recurrence = TPRecurrence(
            pattern: .daily(interval: 1),
            range: .numbered(start: start, occurrences: 1)
        )
        XCTAssertNil(RecurrenceEngine.nextDate(
            after: start, recurrence: recurrence, calendar: cal))
    }

    // MARK: - upcoming()

    func testUpcomingStopsShortWhenTheSeriesEnds() {
        let start = date(2026, 1, 5)
        let recurrence = TPRecurrence(
            pattern: .daily(interval: 1),
            range: .endDate(start: start, end: date(2026, 1, 8))
        )
        let dates = RecurrenceEngine.upcoming(
            from: start, recurrence: recurrence, count: 10, calendar: cal)
        XCTAssertEqual(dates.map(ymd), ["2026-01-06", "2026-01-07", "2026-01-08"])
    }

    // MARK: - complete()

    /// The core distinction between a schedule and a regenerating task: a monthly
    /// regenerating task finished two weeks late is next due a month from *then*.
    func testRegeneratingMeasuresFromCompletionNotDueDate() throws {
        let due = date(2026, 1, 5)
        var task = TPTask(subject: "File the return", dueDate: due)
        task.recurrence = rec(.regenerating(unit: .monthly, interval: 1), from: due)

        let (_, follow) = RecurrenceEngine.complete(task, on: date(2026, 1, 19), calendar: cal)
        XCTAssertEqual(ymd(try XCTUnwrap(follow?.dueDate)), "2026-02-19")
    }

    /// A fixed schedule does not move, however late the work was finished.
    func testFixedScheduleMeasuresFromDueDate() throws {
        let due = date(2026, 1, 5)
        var task = TPTask(subject: "Monthly report", dueDate: due)
        task.recurrence = rec(.monthlyAbsolute(dayOfMonth: 5, interval: 1), from: due)

        let (_, follow) = RecurrenceEngine.complete(task, on: date(2026, 1, 19), calendar: cal)
        XCTAssertEqual(ymd(try XCTUnwrap(follow?.dueDate)), "2026-02-05")
    }

    /// The completed copy must not keep the recurrence, or reopening it spawns
    /// duplicates.
    func testCompletedCopyDropsTheRecurrence() throws {
        let due = date(2026, 1, 5)
        var task = TPTask(subject: "Standing item", dueDate: due)
        task.recurrence = rec(.daily(interval: 1), from: due)

        let (completed, follow) = RecurrenceEngine.complete(task, on: due, calendar: cal)
        XCTAssertNil(completed.recurrence)
        XCTAssertEqual(completed.status, .completed)
        XCTAssertEqual(completed.percentComplete, 100)
        XCTAssertNotNil(completed.completeDate)
        XCTAssertNotNil(try XCTUnwrap(follow).recurrence,
                        "the new occurrence carries the pattern forward")
    }

    func testNonRecurringTaskProducesNoNextOccurrence() {
        let task = TPTask(subject: "One-off", dueDate: date(2026, 1, 5))
        let (completed, follow) = RecurrenceEngine.complete(task, on: date(2026, 1, 5), calendar: cal)
        XCTAssertEqual(completed.status, .completed)
        XCTAssertNil(follow)
    }

    /// Exchange stores one reminder per task, as an absolute date. Carrying the
    /// offset rather than the date is what keeps "remind me two hours before"
    /// meaning the same thing on the next occurrence.
    func testReminderKeepsItsOffsetFromTheDueDate() throws {
        let due = date(2026, 1, 5, 17, 0)
        var task = TPTask(
            subject: "Call the vendor",
            dueDate: due,
            reminderDueBy: date(2026, 1, 5, 15, 0),
            reminderIsSet: true
        )
        task.recurrence = rec(.daily(interval: 1), from: due)

        let follow = try XCTUnwrap(RecurrenceEngine.complete(task, on: due, calendar: cal).next)
        XCTAssertTrue(follow.reminderIsSet)
        let gap = try XCTUnwrap(follow.dueDate)
            .timeIntervalSince(try XCTUnwrap(follow.reminderDueBy))
        XCTAssertEqual(gap, 2 * 3600, accuracy: 1)
    }

    /// A multi-day task keeps its window: the start date shifts by the same span.
    func testStartDateSpanIsPreserved() throws {
        let due = date(2026, 1, 5)
        var task = TPTask(subject: "Draft the brief", startDate: date(2026, 1, 1), dueDate: due)
        task.recurrence = rec(.daily(interval: 7), from: due)

        let follow = try XCTUnwrap(RecurrenceEngine.complete(task, on: due, calendar: cal).next)
        XCTAssertEqual(ymd(try XCTUnwrap(follow.dueDate)), "2026-01-12")
        XCTAssertEqual(ymd(try XCTUnwrap(follow.startDate)), "2026-01-08")
    }

    /// The next occurrence has to reach the server, so it must arrive dirty. A
    /// clean copy would sit in the local store and never be pushed.
    func testNextOccurrenceIsMarkedDirtyAndHasNoServerIdentity() throws {
        let due = date(2026, 1, 5)
        var task = TPTask(itemID: "AAA=", changeKey: "CK1", subject: "Standing item", dueDate: due)
        task.recurrence = rec(.daily(interval: 1), from: due)

        let follow = try XCTUnwrap(RecurrenceEngine.complete(task, on: due, calendar: cal).next)
        XCTAssertTrue(follow.isDirty)
        XCTAssertTrue(follow.itemID.isEmpty, "a new occurrence has never been to the server")
        XCTAssertNotEqual(follow.localID, task.localID, "it is a different task, not an edit")
    }

    /// Completing the final occurrence of a bounded series ends it rather than
    /// producing one outside the range.
    func testCompletingTheLastOccurrenceEndsTheSeries() {
        let start = date(2026, 1, 5)
        var task = TPTask(subject: "Twice only", dueDate: date(2026, 1, 6))
        task.recurrence = TPRecurrence(
            pattern: .daily(interval: 1),
            range: .numbered(start: start, occurrences: 2)
        )
        let (_, follow) = RecurrenceEngine.complete(task, on: date(2026, 1, 6), calendar: cal)
        XCTAssertNil(follow)
    }
}
