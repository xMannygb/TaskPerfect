import Foundation

/// How a category tab arranges its tasks.
///
/// Applies to category pills only. The fixed tabs keep their own rules: All
/// Tasks groups by day, Overdue regroups by due date, Completed sorts by
/// completion. Those answer specific questions and shouldn't be reconfigurable.
public struct CategorySortOptions: Codable, Hashable, Sendable {

    public enum Grouping: String, CaseIterable, Codable, Sendable {
        /// One section per due date, as All Tasks does.
        case dueDate
        /// Overdue, Today, Tomorrow, the rest of this week, four whole weeks,
        /// then whole months.
        ///
        /// Same key as `dueDate` — the due date — at a resolution that coarsens
        /// with distance. Bounded at roughly a dozen headings however far out
        /// the tasks run, where `dueDate` can produce thirty for thirty
        /// scattered tasks.
        case horizon
        /// One section per completion date. Completed tab only.
        case completionDate
        /// One section per person, from Assigned To. Offered in every tab —
        /// unlike category grouping, a category tab can still be split by who's
        /// on what.
        case assignedAZ
        case assignedZA
        /// One section per category, a task filing under its first tag.
        ///
        /// A partition, not a filter: a task with two categories appears once,
        /// under the first. Overlapping groups would make the section counts
        /// exceed the task total.
        case category
        /// A single list.
        ///
        /// Not literally one section: Overdue is still pinned at the top and No
        /// Due Date still follows its own placement setting, so "ungrouped"
        /// means up to three. Named "Ungrouped" rather than "None" because none
        /// would promise something it can't deliver.
        case ungrouped

        public var label: String {
            switch self {
            case .dueDate:   return "Due Date"
            case .horizon:   return "Today, Tomorrow, Weeks, Months"
            case .completionDate: return "Completion Date"
            case .assignedAZ:     return "Assigned To A–Z"
            case .assignedZA:     return "Assigned To Z–A"
            case .category:  return "Category"
            case .ungrouped: return "Ungrouped"
            }
        }
    }

    /// One rung of the comparator chain.
    ///
    /// A level only decides anything when every level above it ties, which is
    /// rarer than it looks: with `alphabeticalAZ` first, a tie needs identical
    /// subjects, so the levels below will appear inert. That's correct, not a
    /// fault. The chain earns its keep with splits first — high priority, then
    /// recurring, then a date, then a name.
    public enum SortLevel: String, CaseIterable, Codable, Sendable {
        case none
        case dueDateSoonest
        case dueDateFurthest
        case alphabeticalAZ
        case alphabeticalZA
        case highPriorityFirst
        case recurringFirst
        // Only offered when grouping by due date — inside a category group every
        // task shares a category, so these would decide nothing.
        case categoryAZ
        case categoryZA
        case categoryTabOrder
        // Completed tasks only. Labelled "most recent / oldest" rather than
        // "soonest / furthest": completion dates are all in the past, so the
        // future-facing wording used for due dates would read backwards.
        case completionMostRecent
        case completionOldest
        /// From the task's Assigned To (Companies) field. Unassigned sinks in
        /// both directions, like undated tasks.
        case assignedAZ
        case assignedZA

        public var label: String {
            switch self {
            case .none:              return "None"
            case .dueDateSoonest:    return "Due Date (soonest first)"
            case .dueDateFurthest:   return "Due Date (furthest first)"
            case .alphabeticalAZ:    return "Alphabetically A–Z"
            case .alphabeticalZA:    return "Alphabetically Z–A"
            case .highPriorityFirst: return "High Priority Tasks"
            case .recurringFirst:    return "Recurring Tasks"
            case .categoryAZ:        return "Category A–Z"
            case .categoryZA:        return "Category Z–A"
            case .categoryTabOrder:  return "Category per Tab Order"
            case .completionMostRecent: return "Completion Date (most recent first)"
            case .completionOldest:     return "Completion Date (oldest first)"
            case .assignedAZ:           return "Assigned To A–Z"
            case .assignedZA:           return "Assigned To Z–A"
            }
        }

        /// Horizon on a category tab: the category levels drop out, since every
        /// task in the tab already shares one — the same rule Due Date follows
        /// there. The date levels stay, because a weekly or monthly section
        /// spans several days and ordering by date decides something real.
        public static let forHorizonCategoryTab: [SortLevel] = [
            .none, .dueDateSoonest, .dueDateFurthest,
            .alphabeticalAZ, .alphabeticalZA, .highPriorityFirst, .recurringFirst,
            .assignedAZ, .assignedZA
        ]

        /// Levels offered when grouping by horizon.
        ///
        /// Includes the due-date levels, unlike `forDueDateGrouping`: a weekly
        /// or monthly section holds tasks due on different days, so ordering
        /// them by date is meaningful here where it wasn't there.
        public static let forHorizonGrouping: [SortLevel] = [
            .none, .dueDateSoonest, .dueDateFurthest,
            .categoryAZ, .categoryZA, .categoryTabOrder,
            .alphabeticalAZ, .alphabeticalZA, .highPriorityFirst, .recurringFirst,
            .assignedAZ, .assignedZA
        ]

        /// Levels offered when grouping by due date.
        public static let forDueDateGrouping: [SortLevel] = [
            .none, .categoryAZ, .categoryZA, .categoryTabOrder,
            .alphabeticalAZ, .alphabeticalZA, .highPriorityFirst, .recurringFirst,
            .assignedAZ, .assignedZA
        ]

        /// Levels offered when grouping by category.
        public static let forCategoryGrouping: [SortLevel] = [
            .none, .dueDateSoonest, .dueDateFurthest,
            .alphabeticalAZ, .alphabeticalZA, .highPriorityFirst, .recurringFirst,
            .assignedAZ, .assignedZA
        ]

        /// Completed, grouped by completion date. No completion levels — each
        /// section is already one completion date. No High Priority either:
        /// priority stops mattering once something is done.
        public static let forCompletedByCompletion: [SortLevel] = [
            .none, .dueDateSoonest, .dueDateFurthest,
            .categoryAZ, .categoryZA,
            .alphabeticalAZ, .alphabeticalZA, .recurringFirst,
            .assignedAZ, .assignedZA
        ]

        /// Completed, grouped by due date. No date levels; completion levels
        /// instead.
        public static let forCompletedByDue: [SortLevel] = [
            .none, .completionMostRecent, .completionOldest,
            .categoryAZ, .categoryZA,
            .alphabeticalAZ, .alphabeticalZA, .recurringFirst,
            .assignedAZ, .assignedZA
        ]

        /// Completed, ungrouped. One list, so both date families apply.
        public static let forCompletedUngrouped: [SortLevel] = [
            .none, .completionMostRecent, .completionOldest,
            .dueDateSoonest, .dueDateFurthest,
            .categoryAZ, .categoryZA,
            .alphabeticalAZ, .alphabeticalZA, .recurringFirst,
            .assignedAZ, .assignedZA
        ]

        /// No Category, grouped by due date. No date levels: each section is
        /// already a single date, so they'd only separate tasks due at
        /// different times that day.
        public static let forNoCategoryByDate: [SortLevel] = [
            .none, .alphabeticalAZ, .alphabeticalZA, .highPriorityFirst, .recurringFirst,
            .assignedAZ, .assignedZA
        ]

        /// No Due Date, grouped by category. No date levels — nothing here has
        /// a date to order by.
        public static let forUndatedByCategory: [SortLevel] = [
            .none, .alphabeticalAZ, .alphabeticalZA, .highPriorityFirst, .recurringFirst,
            .assignedAZ, .assignedZA
        ]

        /// No Due Date, ungrouped. Category levels are useful here because the
        /// list mixes categories; dates still aren't.
        public static let forUndatedUngrouped: [SortLevel] = [
            .none, .categoryAZ, .categoryZA, .categoryTabOrder,
            .alphabeticalAZ, .alphabeticalZA, .highPriorityFirst, .recurringFirst,
            .assignedAZ, .assignedZA
        ]

        /// Ungrouped is one long list, so dates matter here in a way they don't
        /// under due-date grouping — there each section is already a single day.
        public static let forUngrouped: [SortLevel] = [
            .none, .dueDateSoonest, .dueDateFurthest,
            .categoryAZ, .categoryZA, .categoryTabOrder,
            .alphabeticalAZ, .alphabeticalZA, .highPriorityFirst, .recurringFirst,
            .assignedAZ, .assignedZA
        ]

        /// A task's home category: the first tag it carries.
        ///
        /// "First" is the order Exchange returns them, normally the order they
        /// were applied in Outlook. Note this is *first*, not highest-ranked —
        /// a task tagged [Friends, Special] files under Friends even if Special
        /// sits earlier in the manual pill order.
        static func homeCategory(_ task: TPTask) -> String? {
            task.categories.first
        }

        /// Ordered before `b`? `nil` means this level can't separate them, so
        /// the next level decides.
        ///
        /// - Parameter order: the manual pill order, for `categoryTabOrder`.
        func compare(_ a: TPTask, _ b: TPTask, order: [String] = []) -> Bool? {
            switch self {
            case .none:
                return nil

            case .dueDateSoonest, .dueDateFurthest:
                switch (a.dueDate, b.dueDate) {
                case let (x?, y?) where x != y:
                    return self == .dueDateSoonest ? x < y : x > y
                // Undated tasks sink either way — their placement is governed by
                // the No Due Date setting, not by this comparator.
                case (nil, _?): return false
                case (_?, nil): return true
                default:        return nil
                }

            case .alphabeticalAZ, .alphabeticalZA:
                let order = a.subject.localizedCaseInsensitiveCompare(b.subject)
                guard order != .orderedSame else { return nil }
                return self == .alphabeticalAZ
                    ? order == .orderedAscending
                    : order == .orderedDescending

            // A yes/no split, not a sequence: these put one pile ahead of the
            // other and leave ordering within each pile to the next level.
            case .highPriorityFirst:
                let x = a.importance == .high, y = b.importance == .high
                return x == y ? nil : x

            case .recurringFirst:
                let x = a.recurrence != nil, y = b.recurrence != nil
                return x == y ? nil : x

            case .categoryAZ, .categoryZA:
                let x = SortLevel.homeCategory(a), y = SortLevel.homeCategory(b)
                switch (x, y) {
                case let (i?, j?):
                    let result = i.localizedCaseInsensitiveCompare(j)
                    guard result != .orderedSame else { return nil }
                    return self == .categoryAZ
                        ? result == .orderedAscending
                        : result == .orderedDescending
                // Untagged tasks sink, either direction — they have no category
                // to order by, so putting them first would be arbitrary.
                case (nil, _?): return false
                case (_?, nil): return true
                default:        return nil
                }

            case .completionMostRecent, .completionOldest:
                switch (a.completeDate, b.completeDate) {
                case let (x?, y?) where x != y:
                    return self == .completionMostRecent ? x > y : x < y
                // Exchange doesn't always populate completeDate — a task marked
                // done by an older client can arrive without it. Those sink
                // either direction, as undated tasks do elsewhere.
                case (nil, _?): return false
                case (_?, nil): return true
                default:        return nil
                }

            case .assignedAZ, .assignedZA:
                let x = a.assignee, y = b.assignee
                switch (x.isEmpty, y.isEmpty) {
                case (false, false):
                    let result = x.localizedCaseInsensitiveCompare(y)
                    guard result != .orderedSame else { return nil }
                    return self == .assignedAZ
                        ? result == .orderedAscending
                        : result == .orderedDescending
                case (true, false): return false
                case (false, true): return true
                case (true, true):  return nil
                }

            case .categoryTabOrder:
                let x = SortLevel.homeCategory(a), y = SortLevel.homeCategory(b)
                guard let x, let y else {
                    if x == nil && y == nil { return nil }
                    return y == nil          // untagged sinks
                }
                let i = order.firstIndex(of: x) ?? Int.max
                let j = order.firstIndex(of: y) ?? Int.max
                // Categories not in the manual order fall to the end together,
                // then the next level separates them.
                return i == j ? nil : i < j
            }
        }
    }

    public var grouping: Grouping
    public var levels: [SortLevel]
    /// Show completed tasks in category tabs.
    public var includesCompleted: Bool

    public init(
        grouping: Grouping = .dueDate,
        levels: [SortLevel] = [.dueDateSoonest, .highPriorityFirst, .alphabeticalAZ, .none],
        includesCompleted: Bool = false
    ) {
        self.grouping = grouping
        self.levels = levels
        self.includesCompleted = includesCompleted
    }

    /// Walks the chain, stopping at the first level that separates the two.
    public func comparator(_ a: TPTask, _ b: TPTask, order: [String] = []) -> Bool {
        for level in levels {
            if let result = level.compare(a, b, order: order) { return result }
        }
        // Everything tied — fall back to subject so the order is at least stable
        // between renders rather than arbitrary.
        return a.subject.localizedCaseInsensitiveCompare(b.subject) == .orderedAscending
    }

    public func sorted(_ tasks: [TPTask], order: [String] = []) -> [TPTask] {
        tasks.sorted { comparator($0, $1, order: order) }
    }

    /// Levels offered, given the grouping and which tabs this governs.
    ///
    /// A category tab never offers the category levels: its tasks are already
    /// filtered to one category, so sorting by "first tag" would order by
    /// something that isn't the tab. Only All Tasks and Today, grouped by due
    /// date, have a mix of categories worth ordering.
    public func availableLevels(forMainTabs isMain: Bool) -> [SortLevel] {
        // Category tabs never offer the category levels — their tasks are
        // already filtered to one category.
        guard isMain else {
            // Category tabs: same list as ever, except horizon, which re-earns
            // the date levels Due Date can't use there.
            return grouping == .horizon
                ? SortLevel.forHorizonCategoryTab
                : SortLevel.forCategoryGrouping
        }
        switch grouping {
        case .category:       return SortLevel.forCategoryGrouping
        case .ungrouped:      return SortLevel.forUngrouped
        case .dueDate:        return SortLevel.forDueDateGrouping
        case .horizon:        return SortLevel.forHorizonGrouping
        case .completionDate: return SortLevel.forCompletedByCompletion
        case .assignedAZ, .assignedZA: return SortLevel.forCategoryGrouping
        }
    }

    /// Drop any level the current menu doesn't offer.
    ///
    /// Switching grouping otherwise leaves a stale level selected that the menu
    /// no longer lists — the picker would show a blank row and the sort would
    /// use something the user can't see.
    public mutating func pruneLevels(forMainTabs isMain: Bool) {
        let allowed = Set(availableLevels(forMainTabs: isMain))
        levels = levels.map { allowed.contains($0) ? $0 : .none }
    }
}
