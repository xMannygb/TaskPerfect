import Foundation

/// Date arithmetic for recurring tasks.
///
/// Pure and calendar-injected, so it is fully testable and honors the user's
/// locale (first weekday, calendar system) rather than assuming Gregorian/Sunday.
public enum RecurrenceEngine {

    // MARK: - Next occurrence

    /// The next due date after `date`.
    ///
    /// - Parameters:
    ///   - reference: the previous due date for normal patterns; the **completion
    ///     date** for regenerating patterns. Outlook measures those from when the
    ///     work actually finished, not from when it was scheduled.
    /// - Returns: `nil` when the series has ended.
    public static func nextDate(
        after reference: Date,
        recurrence: TPRecurrence,
        calendar: Calendar = .current
    ) -> Date? {
        guard let candidate = advance(reference, by: recurrence.pattern, calendar: calendar) else {
            return nil
        }
        return withinRange(candidate, recurrence: recurrence, calendar: calendar) ? candidate : nil
    }

    /// The next `count` due dates. Powers the editor's live preview — the fastest
    /// way for someone to confirm a pattern does what they meant.
    public static func upcoming(
        from reference: Date,
        recurrence: TPRecurrence,
        count: Int = 3,
        calendar: Calendar = .current
    ) -> [Date] {
        var dates: [Date] = []
        var cursor = reference
        for _ in 0..<count {
            guard let next = nextDate(after: cursor, recurrence: recurrence, calendar: calendar) else {
                break
            }
            dates.append(next)
            cursor = next
        }
        return dates
    }

    // MARK: - Pattern advance

    private static func advance(
        _ date: Date,
        by pattern: TPRecurrence.Pattern,
        calendar: Calendar
    ) -> Date? {
        switch pattern {

        case .daily(let interval):
            return calendar.date(byAdding: .day, value: max(1, interval), to: date)

        case .weekly(let interval, let days):
            return nextWeekly(after: date, interval: max(1, interval), days: days, calendar: calendar)

        case .monthlyAbsolute(let day, let interval):
            guard let base = calendar.date(byAdding: .month, value: max(1, interval), to: date) else { return nil }
            return setDayClamped(day, in: base, calendar: calendar, preserving: date)

        case .monthlyRelative(let ordinal, let weekday, let interval):
            guard let base = calendar.date(byAdding: .month, value: max(1, interval), to: date) else { return nil }
            return nthWeekday(ordinal, weekday, inMonthOf: base, calendar: calendar, preserving: date)

        case .yearlyAbsolute(let month, let day):
            guard let base = calendar.date(byAdding: .year, value: 1, to: date) else { return nil }
            var comps = calendar.dateComponents([.year], from: base)
            comps.month = month
            comps.day = 1
            guard let monthStart = calendar.date(from: comps) else { return nil }
            return setDayClamped(day, in: monthStart, calendar: calendar, preserving: date)

        case .yearlyRelative(let ordinal, let weekday, let month):
            guard let base = calendar.date(byAdding: .year, value: 1, to: date) else { return nil }
            var comps = calendar.dateComponents([.year], from: base)
            comps.month = month
            comps.day = 1
            guard let monthStart = calendar.date(from: comps) else { return nil }
            return nthWeekday(ordinal, weekday, inMonthOf: monthStart, calendar: calendar, preserving: date)

        case .regenerating(let unit, let interval):
            return calendar.date(byAdding: unit.calendarComponent, value: max(1, interval), to: date)
        }
    }

    /// Weekly with selected days: step through the remaining chosen days of the
    /// current week first, then jump `interval` weeks to the earliest chosen day.
    private static func nextWeekly(
        after date: Date,
        interval: Int,
        days: Set<TPRecurrence.Weekday>,
        calendar: Calendar
    ) -> Date? {
        guard !days.isEmpty else {
            return calendar.date(byAdding: .weekOfYear, value: interval, to: date)
        }
        let wanted = Set(days.map(\.calendarIndex))

        // Remaining days this week.
        for offset in 1...6 {
            guard let candidate = calendar.date(byAdding: .day, value: offset, to: date) else { continue }
            if calendar.compare(candidate, to: date, toGranularity: .weekOfYear) != .orderedSame {
                break
            }
            if wanted.contains(calendar.component(.weekday, from: candidate)) {
                return candidate
            }
        }

        // Jump ahead, then take the earliest wanted day of that week.
        guard let jumped = calendar.date(byAdding: .weekOfYear, value: interval, to: date),
              let weekStart = calendar.dateInterval(of: .weekOfYear, for: jumped)?.start
        else { return nil }

        for offset in 0...6 {
            guard let candidate = calendar.date(byAdding: .day, value: offset, to: weekStart) else { continue }
            if wanted.contains(calendar.component(.weekday, from: candidate)) {
                return preserveTime(of: date, on: candidate, calendar: calendar)
            }
        }
        return nil
    }

    /// Set day-of-month, clamping to the month's length.
    /// "Day 31 of every month" lands on Feb 28 or 29, not March 3.
    private static func setDayClamped(
        _ day: Int,
        in month: Date,
        calendar: Calendar,
        preserving timeSource: Date
    ) -> Date? {
        let length = calendar.range(of: .day, in: .month, for: month)?.count ?? 28
        var comps = calendar.dateComponents([.year, .month], from: month)
        comps.day = min(max(1, day), length)
        guard let base = calendar.date(from: comps) else { return nil }
        return preserveTime(of: timeSource, on: base, calendar: calendar)
    }

    /// e.g. "the last Friday" of the month containing `month`.
    private static func nthWeekday(
        _ ordinal: TPRecurrence.Ordinal,
        _ weekday: TPRecurrence.Weekday,
        inMonthOf month: Date,
        calendar: Calendar,
        preserving timeSource: Date
    ) -> Date? {
        guard let interval = calendar.dateInterval(of: .month, for: month) else { return nil }
        var matches: [Date] = []
        var cursor = interval.start
        while cursor < interval.end {
            if calendar.component(.weekday, from: cursor) == weekday.calendarIndex {
                matches.append(cursor)
            }
            guard let next = calendar.date(byAdding: .day, value: 1, to: cursor) else { break }
            cursor = next
        }
        guard !matches.isEmpty else { return nil }
        let picked: Date
        if ordinal == .last {
            picked = matches[matches.count - 1]
        } else {
            // "Fifth Tuesday" doesn't exist in every month — fall back to the last.
            picked = matches[min(ordinal.index - 1, matches.count - 1)]
        }
        return preserveTime(of: timeSource, on: picked, calendar: calendar)
    }

    /// Carry the original time-of-day onto a newly computed date.
    /// Without this, a task due at 5pm drifts to midnight on its second occurrence.
    private static func preserveTime(of source: Date, on target: Date, calendar: Calendar) -> Date {
        let time = calendar.dateComponents([.hour, .minute, .second], from: source)
        return calendar.date(
            bySettingHour: time.hour ?? 0,
            minute: time.minute ?? 0,
            second: time.second ?? 0,
            of: target
        ) ?? target
    }

    // MARK: - Range

    private static func withinRange(
        _ candidate: Date,
        recurrence: TPRecurrence,
        calendar: Calendar
    ) -> Bool {
        switch recurrence.range {
        case .noEnd:
            return true
        case .endDate(_, let end):
            return candidate <= calendar.startOfDay(for: end).addingTimeInterval(86_399)
        case .numbered(let start, let occurrences):
            // Walk the series from its start and stop after `occurrences` dates.
            // Stateless, so a task carries no counter that could drift out of sync.
            guard occurrences > 1 else { return false }
            var cursor = start
            for _ in 1..<occurrences {
                guard let next = advance(cursor, by: recurrence.pattern, calendar: calendar) else {
                    return false
                }
                if calendar.isDate(next, inSameDayAs: candidate) { return true }
                if next > candidate { return false }
                cursor = next
            }
            return false
        }
    }

    // MARK: - Completion

    /// What happens when a recurring task is checked off.
    ///
    /// Matches Outlook: the finished occurrence stays as a completed record, and a
    /// fresh task appears for the next date. The completed copy does **not** keep
    /// the recurrence — otherwise reopening it would spawn duplicates.
    ///
    /// - Returns: the task to mark complete, plus the next occurrence (`nil` when
    ///   the series has ended).
    public static func complete(
        _ task: TPTask,
        on completionDate: Date = Date(),
        calendar: Calendar = .current
    ) -> (completed: TPTask, next: TPTask?) {

        var finished = task
        finished.setStatus(.completed, now: completionDate)
        finished.recurrence = nil

        guard let recurrence = task.recurrence else {
            return (finished, nil)
        }

        // Regenerating patterns measure from completion; the rest from the due date.
        let reference = recurrence.isRegenerating
            ? completionDate
            : (task.dueDate ?? completionDate)

        guard let nextDue = nextDate(after: reference, recurrence: recurrence, calendar: calendar) else {
            return (finished, nil)   // series exhausted
        }

        var next = TPTask(
            folderID: task.folderID,
            subject: task.subject,
            body: task.body,
            categories: task.categories,
            importance: task.importance,
            sensitivity: task.sensitivity,
            dueDate: nextDue,
            reminderIsSet: task.reminderIsSet,
            totalWork: task.totalWork,
            mileage: task.mileage,
            billingInformation: task.billingInformation,
            companies: task.companies,
            owner: task.owner,
            recurrence: recurrence
        )

        // Shift the start date by the same span so a multi-day task keeps its window.
        if let oldStart = task.startDate, let oldDue = task.dueDate {
            let span = calendar.dateComponents([.day], from: oldStart, to: oldDue).day ?? 0
            next.startDate = calendar.date(byAdding: .day, value: -span, to: nextDue)
        }

        // Keep the reminder the same distance ahead of the due date.
        if task.reminderIsSet, let oldReminder = task.reminderDueBy, let oldDue = task.dueDate {
            let offset = oldDue.timeIntervalSince(oldReminder)
            next.reminderDueBy = nextDue.addingTimeInterval(-offset)
        }

        next.markDirty(now: completionDate)
        return (finished, next)
    }
}
