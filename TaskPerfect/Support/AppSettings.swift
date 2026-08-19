import Foundation
import Observation

/// User-facing display preferences.
///
/// Persisted to `UserDefaults` — these are device preferences, not mailbox data,
/// so they deliberately do not sync to Exchange. Someone who wants undated tasks
/// hidden on their phone may still want them visible in desktop Outlook.
@MainActor
@Observable
public final class AppSettings {

    /// Where tasks with no due date appear in the list.
    public enum NoDueDatePlacement: String, CaseIterable, Codable, Sendable {
        /// Above Overdue — for people who treat undated items as a someday list
        /// they want in front of them.
        case top
        /// Below everything dated, above Completed. The default: dated work leads,
        /// undated work waits.
        case bottom
        /// Not shown at all. They still exist and still sync — they just don't
        /// compete for attention.
        case hidden

        public var label: String {
            switch self {
            case .top:    return "Top of list"
            case .bottom: return "Bottom of list"
            case .hidden: return "Don't show"
            }
        }

        public var explanation: String {
            switch self {
            case .top:
                return "Undated tasks appear above Overdue, so they're the first thing you see."
            case .bottom:
                return "Undated tasks sit below everything with a date, above Completed."
            case .hidden:
                return "Undated tasks stay in your mailbox and keep syncing — they're just not listed here."
            }
        }
    }

    public var noDueDatePlacement: NoDueDatePlacement {
        didSet { defaults.set(noDueDatePlacement.rawValue, forKey: Keys.noDueDatePlacement) }
    }

    /// Tabs showing their completed tasks, by tab id.
    ///
    /// A set rather than one flag: a single value meant the banner in All Tasks
    /// also revealed completed tasks in Today. The banner sits in a tab, so it
    /// should answer for that tab.
    ///
    /// Only four tabs qualify — Overdue excludes completed tasks by definition,
    /// and the Completed tab shows nothing else, so a toggle in either would be
    /// meaningless. Category tabs have their own per-category set.
    public private(set) var tabsShowingCompleted: Set<String> = [] {
        didSet { defaults.set(Array(tabsShowingCompleted), forKey: Keys.tabsShowingCompleted) }
    }

    /// These are `TaskTab.id` values — `noCategory` is "nocat", not "noCategory".
    public static let completedToggleTabIDs = ["all", "today", "noDueDate", "nocat"]

    public func showsCompleted(inTab id: String) -> Bool {
        tabsShowingCompleted.contains(id)
    }

    public func setShowsCompleted(_ shows: Bool, inTab id: String) {
        if shows { tabsShowingCompleted.insert(id) } else { tabsShowingCompleted.remove(id) }
    }


    /// How many lines of the subject a row shows before truncating: 1...4.
    ///
    /// Two is the default because it fits most subjects on a phone without
    /// halving how many rows are on screen. Long, prefixed subjects
    /// ("Q3 — Vendor renewal — draft summary for legal") need more.
    /// Whether tapping a section heading collapses it.
    ///
    /// Defaults on: a heading with a chevron teaches itself, and there's no cost
    /// to a feature you simply don't use.
    public var collapsibleSections: Bool {
        didSet {
            defaults.set(collapsibleSections, forKey: Keys.collapsibleSections)
        }
    }

    /// Whether the No Due Date heading in All Tasks keeps its collapsed state
    /// across launches.
    ///
    /// Defaults **off**: every heading reopens on launch, which is the safer
    /// behavior — a section that reopens can't hide work indefinitely. Someone
    /// who wants the undated list folded away is making a deliberate choice.
    ///
    /// A child of `collapsibleSections`. With the parent off there are no
    /// chevrons to tap, so this governs nothing; the Settings row is disabled
    /// rather than hidden, and the stored value is kept so turning the parent
    /// back on restores the preference intact.
    ///
    /// Scoped to All Tasks and to No Due Date alone. That section is *pinned* —
    /// `TaskStore` builds it separately in every grouping from
    /// `noDueDatePlacement` — so unlike a date section it still exists after a
    /// regrouping, which is what makes a stored key safe here and nowhere else.
    public var remembersUndatedCollapse: Bool {
        didSet {
            defaults.set(remembersUndatedCollapse, forKey: Keys.remembersUndatedCollapse)
        }
    }

    /// The remembered state itself: is No Due Date collapsed in All Tasks?
    ///
    /// One Boolean rather than a set of keys, which is the whole reason this can
    /// persist when session collapse can't. Written whenever that heading is
    /// tapped while `remembersUndatedCollapse` is on, and read on launch.
    ///
    /// Kept — not cleared — when either toggle goes off, so the preference
    /// survives being switched off and on again.
    public var undatedCollapsedInAllTasks: Bool {
        didSet {
            defaults.set(undatedCollapsedInAllTasks, forKey: Keys.undatedCollapsedInAllTasks)
        }
    }

    /// Whether the app surfaces reminders that have come due while you were away.
    ///
    /// Defaults **on**. Unlike the No Due Date memory, the safe default and the
    /// useful one agree here: this only ever surfaces work you asked to be
    /// reminded about.
    ///
    /// It exists because notifications alone can't be trusted to cover this.
    /// iOS caps an app at 64 pending notifications and silently drops the rest,
    /// so a reminder outside that window never fires at all; and the permission
    /// can be declined at the prompt or revoked later in iOS Settings, which
    /// kills the feature with nothing to show for it. This path reads the task
    /// list itself, so it has neither limit.
    ///
    /// A toggle rather than fixed behavior: a banner on every launch becomes
    /// noise you learn to dismiss unread, and somebody who works that way needs
    /// a way out that isn't "stop setting reminders".
    public var showsRemindersOnOpen: Bool {
        didSet {
            defaults.set(showsRemindersOnOpen, forKey: Keys.showsRemindersOnOpen)
        }
    }

    public var subjectLineLimit: Int {
        didSet {
            subjectLineLimit = min(max(subjectLineLimit, 1), 6)
            defaults.set(subjectLineLimit, forKey: Keys.subjectLineLimit)
        }
    }

    /// How long a delete can be taken back.
    public enum UndoWindow: Int, CaseIterable, Codable, Sendable {
        case fiveSeconds = 5, tenSeconds = 10, fifteenSeconds = 15
        case thirtySeconds = 30, fortyFiveSeconds = 45, oneMinute = 60

        public var label: String {
            rawValue == 60 ? "1 minute" : "\(rawValue) seconds"
        }

        public var duration: Duration { .seconds(rawValue) }
    }

    /// Offer an undo window after deleting a task.
    ///
    /// Off means the delete is sent immediately with no bar and no way back —
    /// so the confirmation becomes the only safety net, which is why turning
    /// this off switches the task-delete confirmation on.
    public var offersTaskUndo: Bool {
        didSet { defaults.set(offersTaskUndo, forKey: Keys.offersTaskUndo) }
    }

    /// Offer an undo window after deleting a category.
    public var offersCategoryUndo: Bool {
        didSet { defaults.set(offersCategoryUndo, forKey: Keys.offersCategoryUndo) }
    }

    /// Separate windows: a category delete is more consequential than a task
    /// delete and reasonably wants longer to think about.
    public var taskUndoWindow: UndoWindow {
        didSet { defaults.set(taskUndoWindow.rawValue, forKey: Keys.taskUndoWindow) }
    }

    public var categoryUndoWindow: UndoWindow {
        didSet { defaults.set(categoryUndoWindow.rawValue, forKey: Keys.categoryUndoWindow) }
    }

    /// Ask before deleting a task.
    ///
    /// Off by default, because undo covers it better: a confirmation costs a tap
    /// every time to guard against a mistake that undo fixes after the fact.
    public var confirmsTaskDeletion: Bool {
        didSet { defaults.set(confirmsTaskDeletion, forKey: Keys.confirmsTaskDeletion) }
    }

    /// Ask before deleting a category.
    ///
    /// On by default and worth keeping: that confirmation isn't only a safety
    /// prompt, it's where you choose between leaving the label on tasks and
    /// stripping it from all of them. Undo can't express that choice.
    public var confirmsCategoryDeletion: Bool {
        didSet { defaults.set(confirmsCategoryDeletion, forKey: Keys.confirmsCategoryDeletion) }
    }

    /// Ask before checking a task off in the list.
    ///
    /// Only guards *completing*. Reopening a completed task is never confirmed —
    /// it undoes rather than does, and making undo expensive is how people end up
    /// afraid of the checkbox.
    public var confirmsCompletion: Bool {
        didSet { defaults.set(confirmsCompletion, forKey: Keys.confirmsCompletion) }
    }

    /// How the All Tasks and Today tabs group and sort. One setting drives both.
    /// Changes whenever any tab's grouping changes.
    ///
    /// Collapsed sections are keyed by title, and regrouping replaces the
    /// sections entirely — so the view watches this to clear state that would
    /// otherwise point at sections which no longer exist.
    public var sortSignature: String {
        [mainSort, todaySort, overdueSort, undatedSort,
         noCategorySort, completedSort, categorySort]
            .map { "\($0.grouping.rawValue)" }
            .joined(separator: "|")
    }

    public var mainSort: CategorySortOptions {
        didSet {
            guard let data = try? JSONEncoder().encode(mainSort) else { return }
            defaults.set(data, forKey: Keys.mainSort)
        }
    }

    /// How the Today tab groups and sorts.
    ///
    /// Separate from `mainSort`: Today holds overdue plus today's work, so it
    /// wants different defaults from a full task list even though the options
    /// are identical.
    public var todaySort: CategorySortOptions {
        didSet {
            guard let data = try? JSONEncoder().encode(todaySort) else { return }
            defaults.set(data, forKey: Keys.todaySort)
        }
    }

    /// How the Overdue tab groups and sorts.
    ///
    /// Its own setting rather than sharing with the main tabs: every task here
    /// is already overdue, so the pinned-overdue rule that governs elsewhere
    /// would make this whole tab one exempt section and leave the sort inert.
    public var overdueSort: CategorySortOptions {
        didSet {
            guard let data = try? JSONEncoder().encode(overdueSort) else { return }
            defaults.set(data, forKey: Keys.overdueSort)
        }
    }

    /// How the No Due Date tab groups and sorts.
    ///
    /// Only two groupings: nothing here has a date, so due-date grouping would
    /// produce a single section labelled "No Due Date".
    public var undatedSort: CategorySortOptions {
        didSet {
            guard let data = try? JSONEncoder().encode(undatedSort) else { return }
            defaults.set(data, forKey: Keys.undatedSort)
        }
    }

    /// How the No Category tab groups and sorts.
    ///
    /// Both groupings offer the same levels: nothing here carries a category,
    /// so the category levels would have nothing to order by.
    public var noCategorySort: CategorySortOptions {
        didSet {
            guard let data = try? JSONEncoder().encode(noCategorySort) else { return }
            defaults.set(data, forKey: Keys.noCategorySort)
        }
    }

    /// How the Completed tab groups and sorts.
    public var completedSort: CategorySortOptions {
        didSet {
            guard let data = try? JSONEncoder().encode(completedSort) else { return }
            defaults.set(data, forKey: Keys.completedSort)
        }
    }

    /// How category pills group and sort their tasks.
    public var categorySort: CategorySortOptions {
        didSet {
            guard let data = try? JSONEncoder().encode(categorySort) else { return }
            defaults.set(data, forKey: Keys.categorySort)
        }
    }

    /// Category tabs showing their completed tasks, by category name.
    ///
    /// A set rather than one flag on `categorySort`: that made every category
    /// tab share a single value, so revealing completed tasks in Personal also
    /// revealed them in LMC Projects. Each tab now answers only for itself.
    ///
    /// Stores the categories that **do** show them, so a category created later
    /// defaults to hiding completed work without anything written for it — the
    /// same inversion used by the badge and visibility sets.
    public private(set) var categoriesShowingCompleted: Set<String> = [] {
        didSet {
            defaults.set(Array(categoriesShowingCompleted), forKey: Keys.categoriesShowingCompleted)
        }
    }

    public func showsCompleted(inCategory name: String) -> Bool {
        categoriesShowingCompleted.contains(name)
    }

    public func setShowsCompleted(_ shows: Bool, inCategory name: String) {
        if shows { categoriesShowingCompleted.insert(name) }
        else { categoriesShowingCompleted.remove(name) }
    }

    /// Follow a rename, so the setting stays with the category it belongs to.
    public func renameCategoryCompletedFlag(from old: String, to new: String) {
        guard categoriesShowingCompleted.remove(old) != nil else { return }
        categoriesShowingCompleted.insert(new)
    }

    public func clearCompletedFlag(for name: String) {
        categoriesShowingCompleted.remove(name)
    }

    /// Tabs pinned visible even when empty, by tab id.
    ///
    /// Stores the **pinned** set rather than the disappearing one, so a category
    /// added next year inherits the default — disappearing when empty — without
    /// anything having to be written here first. Same inversion as
    /// `hiddenBadgeTabs`, for the same reason.
    public private(set) var alwaysShownTabs: Set<String> = [] {
        didSet { defaults.set(Array(alwaysShownTabs), forKey: Keys.alwaysShownTabs) }
    }

    /// Tabs that never disappear regardless of this setting. Their toggles are
    /// shown but disabled — hiding them would be more confusing than a control
    /// that visibly can't be changed.
    public static let alwaysVisibleTabIDs: Set<String> = ["all", "today", "done"]

    public func isAlwaysShown(tabID id: String) -> Bool {
        AppSettings.alwaysVisibleTabIDs.contains(id) || alwaysShownTabs.contains(id)
    }

    public func canToggleVisibility(tabID id: String) -> Bool {
        !AppSettings.alwaysVisibleTabIDs.contains(id)
    }

    public func setAlwaysShown(_ shown: Bool, tabID id: String) {
        guard canToggleVisibility(tabID: id) else { return }
        if shown { alwaysShownTabs.insert(id) } else { alwaysShownTabs.remove(id) }
    }

    public func pinAllTabs(_ ids: [String]) {
        alwaysShownTabs = Set(ids.filter { canToggleVisibility(tabID: $0) })
    }

    public func unpinAllTabs() { alwaysShownTabs.removeAll() }

    /// Tabs whose badge is switched off, by tab id.
    ///
    /// Stores the **disabled** set rather than the enabled one, so a tab that
    /// doesn't exist yet — a category added next year — defaults to showing its
    /// badge without anything having to be written here first.
    public private(set) var hiddenBadgeTabs: Set<String> = [] {
        didSet { defaults.set(Array(hiddenBadgeTabs), forKey: Keys.hiddenBadgeTabs) }
    }

    public func showsBadge(forTabID id: String) -> Bool {
        !hiddenBadgeTabs.contains(id)
    }

    public func setBadgeVisible(_ visible: Bool, forTabID id: String) {
        if visible { hiddenBadgeTabs.remove(id) } else { hiddenBadgeTabs.insert(id) }
    }

    public func toggleBadge(forTabID id: String) {
        setBadgeVisible(hiddenBadgeTabs.contains(id), forTabID: id)
    }

    /// Tabs whose rows show only the subject, category colors and due date.
    ///
    /// Stored as the set that *differs* from the default, like `hiddenBadgeTabs`
    /// — so a new category needs no migration and a deleted one leaves nothing
    /// orphaned. Empty by default: every tab shows everything, and turning a tab
    /// on is what hides its detail.
    ///
    /// Completed is deliberately not offered. Hiding detail there removes the
    /// completion stamp, which is often the only thing distinguishing one
    /// finished row from another.
    public private(set) var detailsHiddenTabs: Set<String> = [] {
        didSet { defaults.set(Array(detailsHiddenTabs), forKey: Keys.detailsHiddenTabs) }
    }

    public func hidesDetails(forTabID id: String) -> Bool {
        detailsHiddenTabs.contains(id)
    }

    public func setHidesDetails(_ hides: Bool, forTabID id: String) {
        if hides { detailsHiddenTabs.insert(id) } else { detailsHiddenTabs.remove(id) }
    }

    /// Two buttons rather than one that flips its label: once a few tabs differ,
    /// a single button has to decide what to call itself, and whichever it picks
    /// is wrong for half the screen.
    public func hideDetailsEverywhere(tabIDs: [String]) { detailsHiddenTabs = Set(tabIDs) }
    public func showDetailsEverywhere() { detailsHiddenTabs.removeAll() }

    /// Which fields the search bar looks in. Global — the same scope applies in
    /// every tab, and it persists until changed here.
    ///
    /// Subject and notes on by default: today's behavior, split so either can be
    /// switched off. Notes off is the useful case — a long note generates hits
    /// you didn't want, and subject-only search is precise.
    ///
    /// **Never empty.** With one field left the UI disables that row, so search
    /// can't be configured to match nothing. Enforced here too, since a stored
    /// value could arrive empty from a future migration.
    public private(set) var searchFields: Set<String> = [] {
        didSet {
            if searchFields.isEmpty { searchFields = [SearchField.subject.rawValue] }
            defaults.set(Array(searchFields), forKey: Keys.searchFields)
        }
    }

    public func searches(_ field: SearchField) -> Bool {
        searchFields.contains(field.rawValue)
    }

    /// Ignored when it would empty the set — the row is disabled in that state,
    /// so this is a backstop rather than the mechanism.
    public func setSearches(_ on: Bool, field: SearchField) {
        if on {
            searchFields.insert(field.rawValue)
        } else if searchFields.count > 1 {
            searchFields.remove(field.rawValue)
        }
    }

    /// True when this is the only field left, and so can't be switched off.
    /// Not a fixed row — whichever field is alone is the locked one.
    public func isOnlySearchField(_ field: SearchField) -> Bool {
        searchFields == [field.rawValue]
    }

    public func showAllBadges() { hiddenBadgeTabs.removeAll() }

    public func hideAllBadges(tabIDs: [String]) { hiddenBadgeTabs = Set(tabIDs) }

    /// How the app unlocks on reopening. One value, so the three states can't
    /// contradict each other.
    public var lockMode: AppLockMode {
        didSet { defaults.set(lockMode.rawValue, forKey: Keys.lockMode) }
    }

    /// Tint overdue rows with a faint red wash.
    ///
    /// Separate toggles rather than one "row shading" switch: the two washes
    /// answer different questions, and wanting the late warning without the
    /// undated one is a reasonable preference.
    public var shadesOverdueRows: Bool {
        didSet { defaults.set(shadesOverdueRows, forKey: Keys.shadesOverdueRows) }
    }

    /// Tint rows with no due date with a faint blue wash.
    public var shadesUndatedRows: Bool {
        didSet { defaults.set(shadesUndatedRows, forKey: Keys.shadesUndatedRows) }
    }

    /// Show the count of tasks due today on the app icon.
    ///
    /// Counts due-today only — not overdue, not completed — so the icon, the
    /// line under the title and the Today pill all say the same number. A badge
    /// that disagrees with what's inside the app is worse than no badge.
    public var showsAppBadge: Bool {
        didSet { defaults.set(showsAppBadge, forKey: Keys.showsAppBadge) }
    }

    /// How far out from today the app will list tasks.
    public enum DateRangeLimit: String, CaseIterable, Codable, Sendable {
        case all, eightDays, oneMonth, threeMonths, sixMonths, oneYear,
             eighteenMonths, twentySevenMonths

        /// Window size. `nil` means no limit.
        ///
        /// Expressed as days *or* months rather than one unit: eight days can't
        /// be said in months, and "1 month" has to stay a calendar month rather
        /// than becoming 30 days — otherwise a range set in January would end
        /// mid-February.
        public var days: Int? {
            switch self {
            case .eightDays: return 8
            default:         return nil
            }
        }

        public var months: Int? {
            switch self {
            case .all, .eightDays:   return nil
            case .oneMonth:          return 1
            case .threeMonths:       return 3
            case .sixMonths:         return 6
            case .oneYear:           return 12
            case .eighteenMonths:    return 18
            case .twentySevenMonths: return 27
            }
        }

        public var isLimited: Bool { self != .all }

        public var label: String {
            switch self {
            case .all:            return "All"
            case .eightDays:      return "8 days"
            case .oneMonth:       return "1 month"
            case .threeMonths:    return "3 months"
            case .sixMonths:      return "6 months"
            case .oneYear:        return "1 year"
            case .eighteenMonths: return "18 months"
            case .twentySevenMonths: return "27 months"
            }
        }

        /// Backwards tops out at a year; forwards at twenty-seven months.
        ///
        /// `all` sits last in both lists: the options are an increasing scale, and
        /// "no limit" is the end of it rather than the start.
        public static let pastOptions: [DateRangeLimit] =
            [.eightDays, .oneMonth, .threeMonths, .sixMonths, .oneYear, .all]
        public static let futureOptions: [DateRangeLimit] =
            [.eightDays, .oneMonth, .threeMonths, .sixMonths, .oneYear,
             .eighteenMonths, .twentySevenMonths, .all]
    }

    public var pastLimit: DateRangeLimit {
        didSet { defaults.set(pastLimit.rawValue, forKey: Keys.pastLimit) }
    }

    public var futureLimit: DateRangeLimit {
        didSet { defaults.set(futureLimit.rawValue, forKey: Keys.futureLimit) }
    }

    public var hasDateRangeLimit: Bool { pastLimit.isLimited || futureLimit.isLimited }

    /// The earliest date still inside the window, or `nil` for no limit.
    public func earliestInRange(from now: Date = Date(), calendar: Calendar = .current) -> Date? {
        boundary(pastLimit, sign: -1, from: now, calendar: calendar)
    }

    /// The latest date still inside the window, or `nil` for no limit.
    public func latestInRange(from now: Date = Date(), calendar: Calendar = .current) -> Date? {
        boundary(futureLimit, sign: 1, from: now, calendar: calendar)
    }

    private func boundary(
        _ limit: DateRangeLimit, sign: Int, from now: Date, calendar: Calendar
    ) -> Date? {
        if let days = limit.days {
            return calendar.date(byAdding: .day, value: sign * days, to: now)
        }
        if let months = limit.months {
            return calendar.date(byAdding: .month, value: sign * months, to: now)
        }
        return nil
    }

    /// Sync straight after anything changes — a task edited, completed, added or
    /// deleted, or a category added, renamed, recolored or removed.
    ///
    /// Display preferences are deliberately not included. They live in
    /// `UserDefaults` on this device and Exchange has nowhere to put them, so
    /// there would be nothing to send.
    public var syncsAfterChanges: Bool {
        didSet { defaults.set(syncsAfterChanges, forKey: Keys.syncsAfterChanges) }
    }

    /// Sync automatically when the app comes to the foreground.
    public var syncsOnOpen: Bool {
        didSet { defaults.set(syncsOnOpen, forKey: Keys.syncsOnOpen) }
    }

    /// Sync automatically when the app goes to the background.
    ///
    /// Independent toggles rather than one three-way picker: wanting both is a
    /// reasonable setup, and a picker would force a choice between them. With
    /// both off, syncing is manual only — the toolbar button is always there.
    public var syncsOnClose: Bool {
        didSet { defaults.set(syncsOnClose, forKey: Keys.syncsOnClose) }
    }

    /// True when neither automatic trigger is on.
    public var syncsManuallyOnly: Bool { !syncsOnOpen && !syncsOnClose }

    /// The user's chosen category order, by name.
    ///
    /// Empty means "however the mailbox returned them". Stored locally rather
    /// than written back to Exchange: the CategoryList blob does carry an order,
    /// but desktop Outlook sorts its own dialog alphabetically regardless, so
    /// pushing this to the server would be a write that nothing reads.
    public private(set) var categoryOrder: [String] = [] {
        didSet { defaults.set(categoryOrder, forKey: Keys.categoryOrder) }
    }

    /// Apply the stored order. Names not in it — newly created, or renamed since
    /// the order was set — fall to the bottom A–Z rather than disappearing.
    public func ordered(_ categories: [TPCategory]) -> [TPCategory] {
        guard !categoryOrder.isEmpty else { return categories }
        let rank = Dictionary(uniqueKeysWithValues: categoryOrder.enumerated().map { ($1, $0) })
        return categories.sorted { a, b in
            switch (rank[a.name], rank[b.name]) {
            case let (x?, y?): return x < y
            case (_?, nil):    return true
            case (nil, _?):    return false
            case (nil, nil):   return a.name.localizedCaseInsensitiveCompare(b.name) == .orderedAscending
            }
        }
    }

    public func setCategoryOrder(_ names: [String]) {
        categoryOrder = names
    }

    /// "Reset to alphabetical" stores the A–Z order explicitly rather than
    /// clearing it — clearing would fall back to the mailbox's own order, which
    /// isn't alphabetical and isn't what the button says.
    public func resetCategoryOrderAlphabetically(_ categories: [TPCategory]) {
        categoryOrder = categories
            .map(\.name)
            .sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }
    }

    public func renameInCategoryOrder(from oldName: String, to newName: String) {
        guard let index = categoryOrder.firstIndex(of: oldName) else { return }
        categoryOrder[index] = newName
    }

    public func removeFromCategoryOrder(_ name: String) {
        categoryOrder.removeAll { $0 == name }
    }

    /// Per-category subject styling, keyed by category name.
    ///
    /// A task can carry several categories, so the resolution rule has to be
    /// deterministic: **the first category on the task that has a custom style
    /// wins**, in the order the task itself stores them — which is the same order
    /// the color spine paints. What you see leftmost is what styles the text.
    public private(set) var categoryTextStyles: [String: CategoryTextStyle] = [:] {
        didSet { persistStyles() }
    }

    public func textStyle(for name: String) -> CategoryTextStyle? {
        categoryTextStyles[name]
    }

    /// The style a row should use, given everything tagged on the task.
    public func textStyle(forAny names: [String]) -> CategoryTextStyle {
        for name in names {
            if let style = categoryTextStyles[name], !style.isDefault { return style }
        }
        return .standard
    }

    public func setTextStyle(_ style: CategoryTextStyle, for name: String) {
        if style.isDefault {
            categoryTextStyles.removeValue(forKey: name)
        } else {
            categoryTextStyles[name] = style
        }
    }

    public func resetTextStyle(for name: String) {
        categoryTextStyles.removeValue(forKey: name)
    }

    /// Styles are keyed by name, so a rename has to carry its styling across or
    /// the category silently reverts to default.
    public func migrateTextStyle(from oldName: String, to newName: String) {
        guard let style = categoryTextStyles.removeValue(forKey: oldName) else { return }
        categoryTextStyles[newName] = style
    }

    private func persistStyles() {
        guard let data = try? JSONEncoder().encode(categoryTextStyles) else { return }
        defaults.set(data, forKey: Keys.categoryTextStyles)
    }

    private let defaults: UserDefaults

    private enum Keys {
        static let noDueDatePlacement = "display.noDueDatePlacement"
        static let tabsShowingCompleted = "display.tabsShowingCompleted"
        static let confirmsCompletion = "display.confirmsCompletion"
        static let confirmsTaskDeletion = "display.confirmsTaskDeletion"
        static let offersTaskUndo = "undo.offersTask"
        static let offersCategoryUndo = "undo.offersCategory"
        static let taskUndoWindow = "undo.taskWindow"
        static let categoryUndoWindow = "undo.categoryWindow"
        static let confirmsCategoryDeletion = "display.confirmsCategoryDeletion"
        static let subjectLineLimit = "display.subjectLineLimit"
        static let collapsibleSections = "display.collapsibleSections"
        static let remembersUndatedCollapse = "display.remembersUndatedCollapse"
        static let undatedCollapsedInAllTasks = "display.undatedCollapsedInAllTasks"
        static let showsRemindersOnOpen = "reminders.showOnOpen"
        static let categoryTextStyles = "display.categoryTextStyles"
        static let categoryOrder = "display.categoryOrder"
        static let syncsOnOpen = "sync.onOpen"
        static let syncsOnClose = "sync.onClose"
        static let syncsAfterChanges = "sync.afterChanges"
        static let pastLimit = "range.past"
        static let futureLimit = "range.future"
        static let showsAppBadge = "badge.showsToday"
        static let lockMode = "auth.lockMode"
        static let hiddenBadgeTabs = "display.hiddenBadgeTabs"
        static let searchFields = "search.fields"
        static let detailsHiddenTabs = "display.detailsHiddenTabs"
        static let alwaysShownTabs = "display.alwaysShownTabs"
        static let categoriesShowingCompleted = "display.categoriesShowingCompleted"
        static let categorySort = "sort.category"
        static let mainSort = "sort.main"
        static let todaySort = "sort.today"
        static let overdueSort = "sort.overdue"
        static let undatedSort = "sort.undated"
        static let noCategorySort = "sort.noCategory"
        static let completedSort = "sort.completed"
        static let shadesOverdueRows = "display.shadeOverdue"
        static let shadesUndatedRows = "display.shadeUndated"
    }

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        let raw = defaults.string(forKey: Keys.noDueDatePlacement) ?? ""
        self.noDueDatePlacement = NoDueDatePlacement(rawValue: raw) ?? .bottom
        self.tabsShowingCompleted =
            Set(defaults.stringArray(forKey: Keys.tabsShowingCompleted) ?? [])
        // `bool(forKey:)` returns false for an unset key, so default on explicitly.
        self.confirmsCompletion = defaults.object(forKey: Keys.confirmsCompletion) as? Bool ?? true
        self.confirmsTaskDeletion = defaults.bool(forKey: Keys.confirmsTaskDeletion)
        self.offersTaskUndo = defaults.object(forKey: Keys.offersTaskUndo) as? Bool ?? true
        self.offersCategoryUndo = defaults.object(forKey: Keys.offersCategoryUndo) as? Bool ?? true
        self.taskUndoWindow = UndoWindow(rawValue: defaults.integer(forKey: Keys.taskUndoWindow)) ?? .fiveSeconds
        self.categoryUndoWindow = UndoWindow(rawValue: defaults.integer(forKey: Keys.categoryUndoWindow)) ?? .tenSeconds
        self.confirmsCategoryDeletion = defaults.object(forKey: Keys.confirmsCategoryDeletion) as? Bool ?? true
        // `integer(forKey:)` returns 0 for an unset key — reject anything off-range.
        self.collapsibleSections = defaults.object(forKey: Keys.collapsibleSections) as? Bool ?? true
        // Both default false — `bool(forKey:)` returning false for an unset key
        // is the wanted default here, unlike the toggle above.
        self.remembersUndatedCollapse = defaults.bool(forKey: Keys.remembersUndatedCollapse)
        self.undatedCollapsedInAllTasks = defaults.bool(forKey: Keys.undatedCollapsedInAllTasks)
        // Default on, like sync on open: it surfaces work rather than hiding it.
        self.showsRemindersOnOpen = defaults.object(forKey: Keys.showsRemindersOnOpen) as? Bool ?? true
        let storedLines = defaults.integer(forKey: Keys.subjectLineLimit)
        self.subjectLineLimit = (1...6).contains(storedLines) ? storedLines : 2

        self.categoryOrder = defaults.stringArray(forKey: Keys.categoryOrder) ?? []
        // Default on: an app that opens showing yesterday's tasks feels broken.
        self.syncsOnOpen = defaults.object(forKey: Keys.syncsOnOpen) as? Bool ?? true
        self.syncsOnClose = defaults.bool(forKey: Keys.syncsOnClose)
        self.syncsAfterChanges = defaults.object(forKey: Keys.syncsAfterChanges) as? Bool ?? true
        // Default to no limit: a range that hides tasks the user never asked to
        // hide is the wrong thing to do on first launch.
        // Off by default: switching it on is what triggers the permission
        // prompt, and a prompt nobody asked for gets declined.
        self.showsAppBadge = defaults.bool(forKey: Keys.showsAppBadge)
        // On by default — the shading is subtle enough to be a help rather than
        // an imposition, and it's the behavior the app shipped with.
        // Default to password: storing someone's mailbox credentials is a choice
        // they should make, not one made for them on first launch.
        self.hiddenBadgeTabs = Set(defaults.stringArray(forKey: Keys.hiddenBadgeTabs) ?? [])
        let storedFields = Set(defaults.stringArray(forKey: Keys.searchFields) ?? [])
        self.searchFields = storedFields.isEmpty
            ? [SearchField.subject.rawValue, SearchField.notes.rawValue]
            : storedFields
        self.detailsHiddenTabs = Set(defaults.stringArray(forKey: Keys.detailsHiddenTabs) ?? [])
        self.alwaysShownTabs = Set(defaults.stringArray(forKey: Keys.alwaysShownTabs) ?? [])
        self.categoriesShowingCompleted =
            Set(defaults.stringArray(forKey: Keys.categoriesShowingCompleted) ?? [])
        if let data = defaults.data(forKey: Keys.mainSort),
           let decoded = try? JSONDecoder().decode(CategorySortOptions.self, from: data) {
            self.mainSort = decoded
        } else {
            // Default matches what All Tasks already did before this was
            // configurable, so nothing changes for someone who never opens it.
            self.mainSort = CategorySortOptions(
                grouping: .dueDate,
                levels: [.dueDateSoonest, .alphabeticalAZ, .none, .none]
            )
        }
        if let data = defaults.data(forKey: Keys.todaySort),
           let decoded = try? JSONDecoder().decode(CategorySortOptions.self, from: data) {
            self.todaySort = decoded
        } else {
            // Ungrouped, alphabetical: matches what the tab already showed —
            // overdue pinned at the top, then today's work. Due-date grouping
            // isn't offered here, so it can't be the default.
            self.todaySort = CategorySortOptions(
                grouping: .ungrouped,
                levels: [.alphabeticalAZ, .none, .none, .none]
            )
        }
        if let data = defaults.data(forKey: Keys.overdueSort),
           let decoded = try? JSONDecoder().decode(CategorySortOptions.self, from: data) {
            self.overdueSort = decoded
        } else {
            // Matches what the Overdue tab already did, so nothing changes for
            // someone who never opens it.
            self.overdueSort = CategorySortOptions(
                grouping: .dueDate,
                levels: [.dueDateSoonest, .alphabeticalAZ, .none, .none]
            )
        }
        if let data = defaults.data(forKey: Keys.undatedSort),
           let decoded = try? JSONDecoder().decode(CategorySortOptions.self, from: data) {
            self.undatedSort = decoded
        } else {
            // Matches what the tab already did: one list, A–Z.
            self.undatedSort = CategorySortOptions(
                grouping: .ungrouped,
                levels: [.alphabeticalAZ, .none, .none, .none]
            )
        }
        if let data = defaults.data(forKey: Keys.noCategorySort),
           let decoded = try? JSONDecoder().decode(CategorySortOptions.self, from: data) {
            self.noCategorySort = decoded
        } else {
            self.noCategorySort = CategorySortOptions(
                grouping: .dueDate,
                levels: [.dueDateSoonest, .alphabeticalAZ, .none, .none]
            )
        }
        if let data = defaults.data(forKey: Keys.completedSort),
           let decoded = try? JSONDecoder().decode(CategorySortOptions.self, from: data) {
            self.completedSort = decoded
        } else {
            // Matches what the tab already did: one list, most recently
            // finished first. Switching this on changes nothing until you do.
            self.completedSort = CategorySortOptions(
                grouping: .ungrouped,
                levels: [.completionMostRecent, .alphabeticalAZ, .none, .none]
            )
        }
        if let data = defaults.data(forKey: Keys.categorySort),
           let decoded = try? JSONDecoder().decode(CategorySortOptions.self, from: data) {
            self.categorySort = decoded
        } else {
            self.categorySort = CategorySortOptions()
        }
        let storedMode = AppLockMode(rawValue: defaults.string(forKey: Keys.lockMode) ?? "")
        self.lockMode = storedMode ?? .password
        self.shadesOverdueRows = defaults.object(forKey: Keys.shadesOverdueRows) as? Bool ?? true
        self.shadesUndatedRows = defaults.object(forKey: Keys.shadesUndatedRows) as? Bool ?? true
        self.pastLimit = DateRangeLimit(rawValue: defaults.string(forKey: Keys.pastLimit) ?? "") ?? .all
        self.futureLimit = DateRangeLimit(rawValue: defaults.string(forKey: Keys.futureLimit) ?? "") ?? .all

        if let data = defaults.data(forKey: Keys.categoryTextStyles),
           let decoded = try? JSONDecoder().decode([String: CategoryTextStyle].self, from: data) {
            self.categoryTextStyles = decoded
        }
    }
}
