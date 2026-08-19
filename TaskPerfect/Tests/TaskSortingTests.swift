import XCTest
@testable import TaskPerfect

/// Tests for `CategorySortOptions` — the comparator chain and level pruning.
///
/// ⚠️ **These have never been executed.** Same caveat as
/// `RecurrenceEngineTests`: written by reading the implementation, not by running
/// it. A failure is a question, not necessarily a bug in the test.
///
/// The behavior being pinned down is the chain's contract: each level returns
/// `nil` when it cannot separate two tasks, and the next level decides. That is
/// what makes "High Priority, then Recurring, then A–Z" mean what a user expects,
/// and it is easy to break by making a level return a total order instead.
final class TaskSortingTests: XCTestCase {

    // MARK: Fixtures

    private let cal: Calendar = {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "UTC")!
        return c
    }()

    private func date(_ y: Int, _ m: Int, _ d: Int) -> Date {
        cal.date(from: DateComponents(
            timeZone: TimeZone(identifier: "UTC"), year: y, month: m, day: d, hour: 9
        ))!
    }

    private func task(
        _ subject: String,
        due: Date? = nil,
        categories: [String] = [],
        importance: TPImportance = .normal,
        assignedTo: String? = nil,
        recurring: Bool = false,
        completedOn: Date? = nil
    ) -> TPTask {
        var t = TPTask(
            subject: subject,
            categories: categories,
            importance: importance,
            dueDate: due,
            companies: assignedTo.map { [$0] } ?? []
        )
        if recurring {
            t.recurrence = TPRecurrence(
                pattern: .daily(interval: 1),
                range: .noEnd(start: due ?? Date())
            )
        }
        if let completedOn {
            t.setStatus(.completed, now: completedOn)
        }
        return t
    }

    private func subjects(_ tasks: [TPTask]) -> [String] { tasks.map(\.subject) }

    // MARK: - Single levels

    func testDueDateSoonestOrdersAscending() {
        let options = CategorySortOptions(grouping: .ungrouped, levels: [.dueDateSoonest])
        let sorted = options.sorted([
            task("Later", due: date(2026, 3, 1)),
            task("Sooner", due: date(2026, 1, 1)),
            task("Middle", due: date(2026, 2, 1))
        ])
        XCTAssertEqual(subjects(sorted), ["Sooner", "Middle", "Later"])
    }

    /// Undated tasks sink in **both** directions. Their placement is governed by
    /// the No Due Date setting, not by this comparator — so furthest-first must
    /// not float them to the top.
    func testUndatedTasksSinkInBothDirections() {
        let items = [
            task("No date"),
            task("Dated", due: date(2026, 1, 1))
        ]
        for level in [CategorySortOptions.SortLevel.dueDateSoonest, .dueDateFurthest] {
            let options = CategorySortOptions(grouping: .ungrouped, levels: [level])
            XCTAssertEqual(subjects(options.sorted(items)), ["Dated", "No date"],
                           "undated floated to the top under \(level)")
        }
    }

    /// High priority is a yes/no split, not a sequence. It puts one pile ahead of
    /// the other and leaves ordering inside each pile to the next level.
    func testHighPriorityIsASplitAndTheNextLevelOrdersWithinIt() {
        let options = CategorySortOptions(
            grouping: .ungrouped,
            levels: [.highPriorityFirst, .alphabeticalAZ]
        )
        let sorted = options.sorted([
            task("Zebra", importance: .high),
            task("Apple"),
            task("Aardvark", importance: .high),
            task("Banana")
        ])
        XCTAssertEqual(subjects(sorted), ["Aardvark", "Zebra", "Apple", "Banana"])
    }

    func testRecurringFirstIsAlsoASplit() {
        let options = CategorySortOptions(
            grouping: .ungrouped,
            levels: [.recurringFirst, .alphabeticalAZ]
        )
        let sorted = options.sorted([
            task("One-off B"),
            task("Repeats Z", recurring: true),
            task("One-off A"),
            task("Repeats A", recurring: true)
        ])
        XCTAssertEqual(subjects(sorted), ["Repeats A", "Repeats Z", "One-off A", "One-off B"])
    }

    /// A task files under its **first** tag — the order Exchange returns them,
    /// normally the order they were applied in Outlook. Not the highest-ranked.
    func testHomeCategoryIsTheFirstTagNotTheAlphabeticalOne() {
        let options = CategorySortOptions(grouping: .ungrouped, levels: [.categoryAZ])
        let sorted = options.sorted([
            task("Filed under Zulu", categories: ["Zulu", "Alpha"]),
            task("Filed under Bravo", categories: ["Bravo"])
        ])
        XCTAssertEqual(subjects(sorted), ["Filed under Bravo", "Filed under Zulu"])
    }

    func testUntaggedTasksSinkUnderCategoryLevels() {
        let items = [
            task("Untagged"),
            task("Tagged", categories: ["Anything"])
        ]
        for level in [CategorySortOptions.SortLevel.categoryAZ, .categoryZA] {
            let options = CategorySortOptions(grouping: .ungrouped, levels: [level])
            XCTAssertEqual(subjects(options.sorted(items)), ["Tagged", "Untagged"],
                           "untagged floated to the top under \(level)")
        }
    }

    /// Assigned To reads from `companies.first`. Unassigned sinks either way, as
    /// undated tasks do.
    func testUnassignedSinksInBothDirections() {
        let items = [
            task("Nobody"),
            task("Somebody", assignedTo: "Dana")
        ]
        for level in [CategorySortOptions.SortLevel.assignedAZ, .assignedZA] {
            let options = CategorySortOptions(grouping: .ungrouped, levels: [level])
            XCTAssertEqual(subjects(options.sorted(items)), ["Somebody", "Nobody"],
                           "unassigned floated to the top under \(level)")
        }
    }

    /// Completion dates are all in the past, so "most recent" means descending.
    func testCompletionMostRecentIsDescending() {
        let options = CategorySortOptions(grouping: .ungrouped, levels: [.completionMostRecent])
        let sorted = options.sorted([
            task("Old", completedOn: date(2026, 1, 1)),
            task("New", completedOn: date(2026, 3, 1)),
            task("Mid", completedOn: date(2026, 2, 1))
        ])
        XCTAssertEqual(subjects(sorted), ["New", "Mid", "Old"])
    }

    /// Exchange doesn't always populate completeDate — an older client can mark
    /// something done without it. Those sink rather than sorting as epoch zero.
    func testMissingCompletionDateSinks() {
        let items = [
            task("No stamp"),                                       // completeDate is nil
            task("Stamped", completedOn: date(2026, 1, 1))
        ]
        for level in [CategorySortOptions.SortLevel.completionMostRecent, .completionOldest] {
            let options = CategorySortOptions(grouping: .ungrouped, levels: [level])
            XCTAssertEqual(subjects(options.sorted(items)), ["Stamped", "No stamp"],
                           "an unstamped task floated to the top under \(level)")
        }
    }

    // MARK: - categoryTabOrder

    func testCategoryTabOrderFollowsTheManualOrder() {
        let order = ["Lawsuit", "Projects", "Administration"]
        let options = CategorySortOptions(grouping: .ungrouped, levels: [.categoryTabOrder])
        let sorted = options.sorted([
            task("A", categories: ["Administration"]),
            task("B", categories: ["Lawsuit"]),
            task("C", categories: ["Projects"])
        ], order: order)
        XCTAssertEqual(subjects(sorted), ["B", "C", "A"])
    }

    /// Categories absent from the manual order fall to the end **together**, and
    /// the next level separates them. If this level returned a total order
    /// instead, the alphabetical tiebreak below would never run.
    func testCategoriesOutsideTheManualOrderTieAndDeferToTheNextLevel() {
        let order = ["Known"]
        let options = CategorySortOptions(
            grouping: .ungrouped,
            levels: [.categoryTabOrder, .alphabeticalAZ]
        )
        let sorted = options.sorted([
            task("Zed", categories: ["Unlisted B"]),
            task("Alf", categories: ["Unlisted A"]),
            task("Known one", categories: ["Known"])
        ], order: order)
        XCTAssertEqual(subjects(sorted), ["Known one", "Alf", "Zed"])
    }

    // MARK: - The chain

    /// `.none` decides nothing, so a chain of nothing but `.none` falls through to
    /// the subject fallback. That fallback exists so the order is stable between
    /// renders rather than arbitrary.
    func testAllTiedFallsBackToSubject() {
        let options = CategorySortOptions(grouping: .ungrouped, levels: [.none, .none, .none])
        let sorted = options.sorted([task("Charlie"), task("alpha"), task("Bravo")])
        XCTAssertEqual(subjects(sorted), ["alpha", "Bravo", "Charlie"],
                       "the fallback is case-insensitive")
    }

    /// A level below `alphabeticalAZ` is effectively inert, because a tie requires
    /// identical subjects. The README calls this correct rather than a fault, and
    /// this test is here so nobody "fixes" it.
    func testALevelBelowAlphabeticalRarelyDecidesAnything() {
        let options = CategorySortOptions(
            grouping: .ungrouped,
            levels: [.alphabeticalAZ, .highPriorityFirst]
        )
        let sorted = options.sorted([
            task("Beta", importance: .high),
            task("Alpha")
        ])
        XCTAssertEqual(subjects(sorted), ["Alpha", "Beta"],
                       "alphabetical separated them, so priority never got a vote")
    }

    /// The whole point of the chain: high priority splits, recurring splits within
    /// that, a date orders within that, and a name settles the rest.
    func testFourLevelChainAppliesInOrder() {
        let options = CategorySortOptions(
            grouping: .ungrouped,
            levels: [.highPriorityFirst, .recurringFirst, .dueDateSoonest, .alphabeticalAZ]
        )
        let sorted = options.sorted([
            task("normal, plain, late",     due: date(2026, 6, 1)),
            task("high, recurring, early",  due: date(2026, 1, 1), importance: .high, recurring: true),
            task("high, plain, early",      due: date(2026, 1, 1), importance: .high),
            task("high, recurring, late",   due: date(2026, 6, 1), importance: .high, recurring: true),
            task("normal, plain, early",    due: date(2026, 1, 1))
        ])
        XCTAssertEqual(subjects(sorted), [
            "high, recurring, early",
            "high, recurring, late",
            "high, plain, early",
            "normal, plain, early",
            "normal, plain, late"
        ])
    }

    // MARK: - Available levels

    /// A category tab never offers the category levels: its tasks are already
    /// filtered to one category, so ordering by "first tag" would order by
    /// something that isn't the tab.
    func testCategoryTabsNeverOfferCategoryLevels() {
        for grouping in CategorySortOptions.Grouping.allCases {
            let options = CategorySortOptions(grouping: grouping)
            let offered = Set(options.availableLevels(forMainTabs: false))
            XCTAssertFalse(offered.contains(.categoryAZ), "grouping \(grouping)")
            XCTAssertFalse(offered.contains(.categoryZA), "grouping \(grouping)")
            XCTAssertFalse(offered.contains(.categoryTabOrder), "grouping \(grouping)")
        }
    }

    /// Grouping by due date makes each section a single day, so the date levels
    /// would decide nothing and aren't offered. Horizon re-earns them, because a
    /// weekly or monthly section spans several days.
    func testDueDateGroupingDropsDateLevelsButHorizonKeepsThem() {
        let byDate = CategorySortOptions(grouping: .dueDate)
        XCTAssertFalse(byDate.availableLevels(forMainTabs: true).contains(.dueDateSoonest))

        let byHorizon = CategorySortOptions(grouping: .horizon)
        XCTAssertTrue(byHorizon.availableLevels(forMainTabs: true).contains(.dueDateSoonest))
    }

    /// `.none` must be offered under every grouping, on both kinds of tab —
    /// otherwise pruning has nothing safe to fall back to.
    func testNoneIsAlwaysOffered() {
        for grouping in CategorySortOptions.Grouping.allCases {
            for isMain in [true, false] {
                let options = CategorySortOptions(grouping: grouping)
                XCTAssertTrue(options.availableLevels(forMainTabs: isMain).contains(.none),
                              "grouping \(grouping), main: \(isMain)")
            }
        }
    }

    // MARK: - pruneLevels

    /// Switching grouping otherwise leaves a level selected that the menu no
    /// longer lists: the picker shows a blank row and the sort uses something the
    /// user cannot see.
    func testPruningReplacesDisallowedLevelsWithNone() {
        var options = CategorySortOptions(
            grouping: .dueDate,
            levels: [.dueDateSoonest, .highPriorityFirst, .alphabeticalAZ, .none]
        )
        options.pruneLevels(forMainTabs: true)

        XCTAssertEqual(options.levels[0], .none, "date levels aren't offered under due-date grouping")
        XCTAssertEqual(options.levels[1], .highPriorityFirst, "still offered, so left alone")
        XCTAssertEqual(options.levels[2], .alphabeticalAZ)
        XCTAssertEqual(options.levels.count, 4, "pruning replaces in place; it never drops rungs")
    }

    func testPruningIsIdempotent() {
        var once = CategorySortOptions(grouping: .category, levels: [.categoryTabOrder, .alphabeticalAZ])
        once.pruneLevels(forMainTabs: true)
        var twice = once
        twice.pruneLevels(forMainTabs: true)
        XCTAssertEqual(once.levels, twice.levels)
    }

    /// Pruning must never leave a level the menu doesn't list, for any starting
    /// combination. This is the property the individual cases above are examples of.
    func testPruningLeavesOnlyOfferedLevelsForEveryGrouping() {
        for grouping in CategorySortOptions.Grouping.allCases {
            for isMain in [true, false] {
                var options = CategorySortOptions(
                    grouping: grouping,
                    levels: CategorySortOptions.SortLevel.allCases
                )
                options.pruneLevels(forMainTabs: isMain)
                let allowed = Set(options.availableLevels(forMainTabs: isMain))
                for level in options.levels {
                    XCTAssertTrue(allowed.contains(level),
                                  "\(level) survived pruning under \(grouping), main: \(isMain)")
                }
            }
        }
    }

    // MARK: - Stability

    /// The comparator must be a strict weak ordering or `sorted(by:)` is allowed
    /// to misbehave. Cheap check: no pair may claim both directions.
    func testComparatorIsNeverTrueInBothDirections() {
        let options = CategorySortOptions(
            grouping: .ungrouped,
            levels: [.highPriorityFirst, .recurringFirst, .dueDateSoonest, .alphabeticalAZ]
        )
        let items = [
            task("A", due: date(2026, 1, 1), importance: .high),
            task("A", due: date(2026, 1, 1)),
            task("B"),
            task("B", categories: ["X"], recurring: true),
            task("C", due: date(2026, 5, 1), assignedTo: "Dana")
        ]
        for a in items {
            for b in items {
                let forward = options.comparator(a, b)
                let backward = options.comparator(b, a)
                XCTAssertFalse(forward && backward,
                               "both orders claimed for \(a.subject) vs \(b.subject)")
            }
        }
    }
}
