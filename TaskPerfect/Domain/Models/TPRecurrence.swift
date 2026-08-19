import Foundation

/// Normalized recurrence pattern.
///
/// EWS expresses recurrence as a `<Recurrence>` element pairing a *pattern* with a
/// *range*. This type keeps that split rather than flattening it, because the two
/// map independently onto the wire format.
public struct TPRecurrence: Hashable, Codable, Sendable {

    public var pattern: Pattern
    public var range: Range

    public init(pattern: Pattern, range: Range = .noEnd(start: Date())) {
        self.pattern = pattern
        self.range = range
    }

    // MARK: Pattern

    public enum Pattern: Hashable, Codable, Sendable {
        case daily(interval: Int)
        case weekly(interval: Int, daysOfWeek: Set<Weekday>)
        /// Day D of every N months, e.g. the 15th.
        case monthlyAbsolute(dayOfMonth: Int, interval: Int)
        /// e.g. "the second Tuesday of every 3 months".
        case monthlyRelative(ordinal: Ordinal, weekday: Weekday, interval: Int)
        /// e.g. "March 15 every year".
        case yearlyAbsolute(month: Int, dayOfMonth: Int)
        /// e.g. "the last Friday of November".
        case yearlyRelative(ordinal: Ordinal, weekday: Weekday, month: Int)

        /// Outlook task-specific: the next due date is measured from the date the
        /// task was *completed*, not from the previous due date. There is no
        /// Microsoft Graph equivalent.
        case regenerating(unit: Frequency, interval: Int)
    }

    // MARK: Range

    public enum Range: Hashable, Codable, Sendable {
        case noEnd(start: Date)
        case numbered(start: Date, occurrences: Int)
        case endDate(start: Date, end: Date)

        public var startDate: Date {
            switch self {
            case .noEnd(let s), .numbered(let s, _), .endDate(let s, _): return s
            }
        }

        public func withStart(_ date: Date) -> Range {
            switch self {
            case .noEnd: return .noEnd(start: date)
            case .numbered(_, let n): return .numbered(start: date, occurrences: n)
            case .endDate(_, let e): return .endDate(start: date, end: e)
            }
        }
    }

    // MARK: Supporting types

    public enum Frequency: String, CaseIterable, Codable, Sendable {
        case daily = "Daily", weekly = "Weekly", monthly = "Monthly", yearly = "Yearly"

        public var unitNoun: String {
            switch self {
            case .daily: return "day"
            case .weekly: return "week"
            case .monthly: return "month"
            case .yearly: return "year"
            }
        }

        /// Compact form for task rows, where "months" won't fit.
        public var abbreviation: String {
            switch self {
            case .daily: return "d"
            case .weekly: return "w"
            case .monthly: return "mo"
            case .yearly: return "y"
            }
        }

        public var calendarComponent: Calendar.Component {
            switch self {
            case .daily: return .day
            case .weekly: return .weekOfYear
            case .monthly: return .month
            case .yearly: return .year
            }
        }
    }

    public enum Weekday: String, CaseIterable, Codable, Sendable {
        case sunday = "Sunday", monday = "Monday", tuesday = "Tuesday"
        case wednesday = "Wednesday", thursday = "Thursday"
        case friday = "Friday", saturday = "Saturday"

        public var shortLabel: String { String(rawValue.prefix(3)) }
        public var initial: String { String(rawValue.prefix(1)) }

        /// 1 = Sunday, matching `Calendar.component(.weekday:)`.
        public var calendarIndex: Int {
            (Self.allCases.firstIndex(of: self) ?? 0) + 1
        }

        public static func from(calendarIndex: Int) -> Weekday {
            allCases[max(0, min(6, calendarIndex - 1))]
        }
    }

    public enum Ordinal: String, CaseIterable, Codable, Sendable {
        case first = "First", second = "Second", third = "Third"
        case fourth = "Fourth", last = "Last"

        /// Value `Calendar` wants for `nthWeekday`; `last` is handled separately.
        public var index: Int {
            switch self {
            case .first: return 1
            case .second: return 2
            case .third: return 3
            case .fourth: return 4
            case .last: return -1
            }
        }
    }
}

// MARK: - Frequency access

public extension TPRecurrence {

    /// Which of the four tabs the editor should show for this pattern.
    var frequency: Frequency {
        switch pattern {
        case .daily: return .daily
        case .weekly: return .weekly
        case .monthlyAbsolute, .monthlyRelative: return .monthly
        case .yearlyAbsolute, .yearlyRelative: return .yearly
        case .regenerating(let unit, _): return unit
        }
    }

    var interval: Int {
        switch pattern {
        case .daily(let n), .weekly(let n, _),
             .monthlyAbsolute(_, let n), .monthlyRelative(_, _, let n),
             .regenerating(_, let n):
            return n
        case .yearlyAbsolute, .yearlyRelative:
            return 1
        }
    }

    var isRegenerating: Bool {
        if case .regenerating = pattern { return true }
        return false
    }

    /// A sensible default pattern when the user picks a frequency tab.
    /// Seeded from `date` so "Monthly" means the day the task is already due.
    static func defaultPattern(
        for frequency: Frequency,
        on date: Date,
        interval: Int = 1,
        calendar: Calendar = .current
    ) -> Pattern {
        let comps = calendar.dateComponents([.day, .month, .weekday], from: date)
        switch frequency {
        case .daily:
            return .daily(interval: interval)
        case .weekly:
            let day = Weekday.from(calendarIndex: comps.weekday ?? 1)
            return .weekly(interval: interval, daysOfWeek: [day])
        case .monthly:
            return .monthlyAbsolute(dayOfMonth: comps.day ?? 1, interval: interval)
        case .yearly:
            return .yearlyAbsolute(month: comps.month ?? 1, dayOfMonth: comps.day ?? 1)
        }
    }
}

// MARK: - Descriptions

public extension TPRecurrence {

    /// Full sentence for the editor and detail screen.
    var summary: String {
        let base: String
        switch pattern {
        case .daily(let n):
            base = n == 1 ? "Every day" : "Every \(n) days"

        case .weekly(let n, let days):
            let names = Weekday.allCases
                .filter { days.contains($0) }
                .map(\.shortLabel)
                .joined(separator: ", ")
            let every = n == 1 ? "Every week" : "Every \(n) weeks"
            base = names.isEmpty ? every : "\(every) on \(names)"

        case .monthlyAbsolute(let day, let n):
            let every = n == 1 ? "month" : "\(n) months"
            base = "Day \(day) of every \(every)"

        case .monthlyRelative(let ord, let day, let n):
            let every = n == 1 ? "month" : "\(n) months"
            base = "The \(ord.rawValue.lowercased()) \(day.rawValue) of every \(every)"

        case .yearlyAbsolute(let month, let day):
            base = "Every \(TPRecurrence.monthName(month)) \(day)"

        case .yearlyRelative(let ord, let day, let month):
            base = "The \(ord.rawValue.lowercased()) \(day.rawValue) of \(TPRecurrence.monthName(month))"

        case .regenerating(let unit, let n):
            base = n == 1
                ? "A \(unit.unitNoun) after completion"
                : "\(n) \(unit.unitNoun)s after completion"
        }

        switch range {
        case .noEnd:
            return base
        case .numbered(_, let count):
            return "\(base), \(count) times"
        case .endDate(_, let end):
            return "\(base), until \(end.formatted(date: .abbreviated, time: .omitted))"
        }
    }

    /// Compact form for a task row, where horizontal space is scarce.
    /// Never includes the range — the row shows what repeats, not for how long.
    var shortSummary: String {
        switch pattern {
        case .daily(let n):
            return n == 1 ? "Daily" : "Every \(n)d"
        case .weekly(let n, let days):
            let names = Weekday.allCases
                .filter { days.contains($0) }
                .map(\.shortLabel)
                .joined(separator: " ")
            let head = n == 1 ? "Weekly" : "Every \(n)w"
            return names.isEmpty ? head : "\(head) · \(names)"
        case .monthlyAbsolute(let day, let n):
            return n == 1 ? "Monthly · day \(day)" : "Every \(n)mo · day \(day)"
        case .monthlyRelative(let ord, let day, let n):
            let head = n == 1 ? "Monthly" : "Every \(n)mo"
            return "\(head) · \(ord.rawValue.lowercased()) \(day.shortLabel)"
        case .yearlyAbsolute(let month, let day):
            return "Yearly · \(TPRecurrence.shortMonthName(month)) \(day)"
        case .yearlyRelative(let ord, let day, let month):
            return "Yearly · \(ord.rawValue.lowercased()) \(day.shortLabel) of \(TPRecurrence.shortMonthName(month))"
        case .regenerating(let unit, let n):
            return "\(n)\(unit.abbreviation) after done"
        }
    }

    static func monthName(_ index: Int) -> String {
        let symbols = DateFormatter().monthSymbols ?? []
        guard (1...12).contains(index), symbols.count == 12 else { return "\(index)" }
        return symbols[index - 1]
    }

    static func shortMonthName(_ index: Int) -> String {
        let symbols = DateFormatter().shortMonthSymbols ?? []
        guard (1...12).contains(index), symbols.count == 12 else { return "\(index)" }
        return symbols[index - 1]
    }
}
