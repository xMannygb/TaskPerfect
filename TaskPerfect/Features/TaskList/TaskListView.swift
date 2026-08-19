import SwiftUI

public struct TaskListView: View {

    @Environment(TaskStore.self) private var store
    @Environment(\.scenePhase) private var scenePhase
    @State private var selection: TPTask?
    @State private var showsSettings = false
    /// Straight to the badge screen. Landing on Settings and making the user
    /// hunt for the row would make the shortcut worse than no shortcut.
    @State private var showsBadgeSettings = false
    @State private var showsCategoryFilter = false
    @State private var showsReminders = false

    /// The banner appears when the preference is on, something is actually due,
    /// and the launch's banner hasn't been dealt with yet. Tied to the launch
    /// rather than the tab — a missed reminder isn't a property of where you're
    /// standing.
    private var showsReminderBanner: Bool {
        store.settings.showsRemindersOnOpen
            && !store.remindersBannerHandled
            && !store.dueReminders.isEmpty
    }

    private let menuFilterLimit = 5

    /// Active filters first, so a filter you just set stays one tap from being
    /// cleared however far down the list its category sits.
    private var menuFilterCategories: [TPCategory] {
        let all = store.categoriesInUse
        let active = all.filter { store.selectedCategories.contains($0.name) }
        let inactive = all.filter { !store.selectedCategories.contains($0.name) }
        return Array((active + inactive).prefix(menuFilterLimit))
    }
    /// Whatever is waiting on a yes. One slot, one dialog — stacking multiple
    /// `confirmationDialog` modifiers on the same view doesn't reliably present.
    @State private var pending: PendingAction?

    enum PendingAction: Identifiable {
        case delete(TPTask)
        case complete(TPTask)

        var task: TPTask {
            switch self {
            case .delete(let t), .complete(let t): return t
            }
        }
        var id: String {
            switch self {
            case .delete(let t): return "delete-\(t.id)"
            case .complete(let t): return "complete-\(t.id)"
            }
        }
    }
    /// Non-nil while the new-task editor is up. Same screen as editing an
    /// existing task, so every field is available at creation rather than
    /// forcing a save-then-edit round trip.
    @State private var draftTask: TPTask?

    public init() {}

    public var body: some View {
        @Bindable var store = store

        NavigationStack {
            VStack(spacing: 0) {
                tabBar
                // The strip auto-scrolls the active pill into view, but a
                // hand-scrolled strip can leave it off-screen — with fourteen
                // pills, scrolling back to find it is a nuisance. Name only: a
                // count here would have to agree with the pill badge in every
                // case, including tabs whose badge is switched off.
                Text(store.activeTab.title)
                    .font(.system(size: 11, weight: .semibold))
                    .kerning(0.7)
                    .textCase(.uppercase)
                    .foregroundStyle(Theme.Palette.slate)
                    .lineLimit(1)
                    // Centered to sit on the same axis as the navigation title
                    // above it, rather than starting a second alignment.
                    .frame(maxWidth: .infinity)
                    .padding(.horizontal, 16)
                    .padding(.bottom, 6)
                    .background(Theme.Palette.paper)
                    .accessibilityAddTraits(.isHeader)
                Group {
                    if store.isLoading && store.tasks.isEmpty {
                        ProgressView().controlSize(.large)
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                    } else if store.sections.isEmpty {
                        emptyState
                    } else {
                        list
                    }
                }
            }
            .background(Theme.Palette.canvas)
            .overlay(alignment: .bottom) {
                // Both can be pending at once — the coordinators are independent,
                // so they stack rather than one replacing the other.
                VStack(spacing: 8) {
                    if let pending = store.categoryUndo.pending {
                        undoToast(pending,
                                  undo: { store.undoCategoryDelete() },
                                  dismiss: { await store.dismissCategoryUndo() })
                    }
                    if let pending = store.taskUndo.pending {
                        undoToast(pending,
                                  undo: { store.undoTaskDelete() },
                                  dismiss: { await store.dismissTaskUndo() })
                    }
                }
                .transition(.move(edge: .bottom).combined(with: .opacity))
            }
            .animation(.snappy(duration: 0.2), value: store.taskUndo.pending?.id)
            .animation(.snappy(duration: 0.2), value: store.categoryUndo.pending?.id)
            .navigationTitle("Task Perfect")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { toolbar }
            // Names the tab rather than saying "tasks": search is scoped to
            // whatever tab you're standing in, and a generic prompt led testers
            // to expect it searched everything.
            // The sections themselves change, so their collapse state is
        // meaningless — clear it rather than leave keys pointing at sections
        // that no longer exist.
        // No Due Date is exempt: it's pinned, so it survives a regroup intact
        // and its remembered state still points at a section that exists.
        .onChange(of: store.settings.sortSignature) { _, _ in
            collapsedSections.removeAll()
        }
        // Turning it off must expand everything, or sections would stay hidden
        // with no control left to reveal them. The remembered No Due Date flag
        // is kept rather than cleared — `isCollapsed` already ignores it while
        // this is off, and clearing would lose the preference on a stray tap.
        .onChange(of: store.settings.collapsibleSections) { _, isOn in
            if !isOn { collapsedSections.removeAll() }
        }
        // Switching the memory off shouldn't make a collapsed section jump open
        // underneath you: hand its current state to the session set instead, so
        // it stays as it looks and simply stops surviving the next launch.
        .onChange(of: store.settings.remembersUndatedCollapse) { _, isOn in
            let key = "\(TaskTab.all.id)|\(DueGroup.noDate.title)"
            if isOn {
                // Adopt what's on screen rather than the stored value, or a
                // section collapsed earlier this session would spring open the
                // moment the memory is switched on.
                store.settings.undatedCollapsedInAllTasks = collapsedSections.contains(key)
                collapsedSections.remove(key)
            } else if store.settings.undatedCollapsedInAllTasks {
                collapsedSections.insert(key)
            }
        }
        .searchable(text: $store.searchText,
                        prompt: "Search \(store.activeTab.title)")
            .refreshable { await store.syncChanges() }
            .task {
                // Disk first: the list should be on screen before any network
                // call, so a cold launch offline still shows everything.
                await store.loadFromDisk()
                if store.tasks.isEmpty { await store.load() }
                await AppBadge.apply(count: store.todayOutstanding,
                                     enabled: store.settings.showsAppBadge)
            }
            // Keep the icon honest: any change to what's due today updates it.
            .onChange(of: store.todayOutstanding) { _, count in
                Task { await AppBadge.apply(count: count, enabled: store.settings.showsAppBadge) }
            }
            .onChange(of: scenePhase) { previous, phase in
                switch phase {
                case .active where previous == .background && store.settings.syncsOnOpen:
                    Task { await store.syncChanges() }
                case .background:
                    // A staged delete must not survive a quit — it would look
                    // deleted, not be, and offer no way back.
                    Task {
                        await store.commitPendingDeletes()
                        if store.settings.syncsOnClose { await store.syncChanges() }
                    }
                default:
                    break
                }
            }
            .sheet(item: $selection) { task in
                NavigationStack {
                    TaskDetailView(task: task)
                }
            }
            .sheet(item: $draftTask) { draft in
                NavigationStack {
                    TaskDetailView(task: draft, isNew: true)
                }
            }
            .sheet(isPresented: $showsSettings) {
                NavigationStack { SettingsView() }
            }
            .sheet(isPresented: $showsBadgeSettings) {
                NavigationStack { BadgeSettingsView() }
            }
            .sheet(isPresented: $showsCategoryFilter) {
                NavigationStack { CategoryFilterView() }
            }
            .sheet(isPresented: $showsReminders) {
                NavigationStack {
                    DueRemindersView(open: { task in
                        showsReminders = false
                        selection = task
                    })
                }
            }
            .confirmationDialog(
                dialogTitle,
                isPresented: Binding(
                    get: { pending != nil },
                    set: { if !$0 { pending = nil } }
                ),
                titleVisibility: .visible,
                presenting: pending
            ) { action in
                switch action {
                case .delete(let target):
                    Button("Delete Task", role: .destructive) {
                        pending = nil
                        Task { await store.delete(target) }
                    }
                case .complete(let target):
                    Button("Complete Task") {
                        pending = nil
                        Task { await store.toggleComplete(target) }
                    }
                }
                Button("Cancel", role: .cancel) { pending = nil }
            } message: { action in
                switch action {
                case .delete(let target):
                    Text(TaskListView.deleteWarning(for: target))
                case .complete(let target):
                    Text(TaskListView.completionNote(for: target))
                }
            }
            .alert(
                "Something went wrong",
                isPresented: Binding(
                    get: { store.lastError != nil },
                    set: { if !$0 { store.clearError() } }
                ),
                presenting: store.lastError
            ) { _ in
                Button("OK") { store.clearError() }
            } message: { error in
                Text(error.errorDescription ?? "Try again.")
            }
        }
    }

    // MARK: List

    private var list: some View {
        List {
            // Only inside a category tab, and only when it would change what you
            // see. Placing it here rather than in Settings means you can flip it
            // while looking at the list it affects.
            if let name = store.activeTab.categoryName,
               store.completedCount(inCategory: name) > 0 {
                Section {
                    Toggle(isOn: Binding(
                        get: { store.settings.showsCompleted(inCategory: name) },
                        set: { store.settings.setShowsCompleted($0, inCategory: name) }
                    )) {
                        // The label says what tapping does, so it flips with the
                        // state. The count doesn't: it's the number of completed
                        // tasks either way.
                        let count = store.completedCount(inCategory: name)
                        let verb = store.settings.showsCompleted(inCategory: name) ? "Hide" : "Show"
                        Text("\(verb) \(count) completed task\(count == 1 ? "" : "s")")
                            .font(.footnote)
                            .foregroundStyle(Theme.Palette.slate)
                    }
                }
            }

            // Per tab. Overdue excludes completed tasks by definition and the
            // Completed tab shows nothing else, so neither carries a banner.
            if AppSettings.completedToggleTabIDs.contains(store.activeTab.id),
               store.completedCountForMainTab > 0 {
                Section {
                    Toggle(isOn: Binding(
                        get: { store.settings.showsCompleted(inTab: store.activeTab.id) },
                        set: { store.settings.setShowsCompleted($0, inTab: store.activeTab.id) }
                    )) {
                        let count = store.completedCountForMainTab
                        let verb = store.settings.showsCompleted(inTab: store.activeTab.id) ? "Hide" : "Show"
                        Text("\(verb) \(count) completed task\(count == 1 ? "" : "s")")
                            .font(.footnote)
                            .foregroundStyle(Theme.Palette.slate)
                    }
                }
            }

            // Reminders that came due while you were away. Above the undated
            // banner because it's a prompt to act, not a note about a filter,
            // and on every tab: a missed reminder isn't a property of the tab
            // you happen to be standing in.
            if showsReminderBanner {
                Section {
                    Button {
                        showsReminders = true
                    } label: {
                        HStack {
                            Image(systemName: "bell.badge")
                            Text("\(store.dueReminders.count) reminder\(store.dueReminders.count == 1 ? "" : "s") due")
                            Spacer()
                            Image(systemName: "chevron.right").font(.caption)
                        }
                        .font(.footnote)
                        .foregroundStyle(Theme.Palette.overdue)
                    }
                }
            }

            /* Stacks under the reminders banner rather than sharing its row:
               one says something needs attention, the other says this list isn't
               everything, and merging unrelated statements to save a row makes
               both harder to read. Reminders lead — a due reminder outranks a
               filter you set yourself a minute ago and already know about.

               The completed toggle keeps its own place above, untouched. */
            if !store.selectedCategories.isEmpty {
                Section {
                    // The whole row clears it. A filter banner exists to be
                    // dismissed, and a small "Clear" beside a large inert row is
                    // the wrong way round.
                    Button {
                        store.selectedCategories.removeAll()
                    } label: {
                        HStack {
                            Image(systemName: "line.3.horizontal.decrease.circle.fill")
                            Text("Filtered: \(filterBannerLabel)")
                            Spacer()
                            Text("Clear").fontWeight(.semibold)
                        }
                        .font(.footnote)
                        .foregroundStyle(Theme.Palette.navy)
                    }
                }
            }

            if hiddenUndatedCount > 0 {
                Section {
                    Button {
                        showsSettings = true
                    } label: {
                        HStack {
                            Image(systemName: "eye.slash")
                            Text("\(hiddenUndatedCount) task\(hiddenUndatedCount == 1 ? "" : "s") with no due date hidden")
                            Spacer()
                            Image(systemName: "chevron.right").font(.caption)
                        }
                        .font(.footnote)
                        .foregroundStyle(Theme.Palette.slate)
                    }
                }
            }

            ForEach(store.sections) { section in
                Section {
                    ForEach(isCollapsed(section) ? [] : section.tasks) { task in
                        TaskRowView(
                            task: task,
                            categories: store.resolver.resolve(all: task.categories),
                            subjectLineLimit: store.settings.subjectLineLimit,
                            textStyle: store.settings.textStyle(forAny: task.categories),
                            shadesOverdue: store.settings.shadesOverdueRows,
                            shadesUndated: store.settings.shadesUndatedRows,
                            // Keyed to the tab being shown, not the one last
                            // tapped — a pill that disappears under you falls
                            // back to All Tasks, and the rows should follow.
                            hidesDetails: store.settings.hidesDetails(forTabID: store.activeTab.id),
                            onToggle: { requestToggle(task) }
                        )
                        .listRowInsets(EdgeInsets(
                            top: 0, leading: Theme.Metrics.rowInset,
                            bottom: 0, trailing: Theme.Metrics.rowInset
                        ))
                        .onTapGesture { selection = task }
                        .swipeActions(edge: .trailing) {
                            // Stages the delete rather than performing it — the
                            // confirmation below is what actually removes it.
                            Button(role: .destructive) {
                                // With undo available, a confirmation is
                                // optional — off by default.
                                if store.settings.confirmsTaskDeletion {
                                    pending = .delete(task)
                                } else {
                                    Task { await store.delete(task) }
                                }
                            } label: {
                                Label("Delete", systemImage: "trash")
                            }
                        }
                        .swipeActions(edge: .leading) {
                            Button {
                                requestToggle(task)
                            } label: {
                                Label(
                                    task.isComplete ? "Reopen" : "Complete",
                                    systemImage: task.isComplete ? "arrow.uturn.backward" : "checkmark"
                                )
                            }
                            .tint(Theme.Palette.ink)

                            // Move a recurring task to its next date without
                            // recording it as done — "not this week".
                            if task.recurrence != nil && !task.isComplete {
                                Button {
                                    Task { await store.skipOccurrence(task) }
                                } label: {
                                    Label("Skip", systemImage: "forward.end")
                                }
                                .tint(Theme.Palette.slate)
                            }
                        }
                    }
                } header: {
                    HStack {
                        // No chevron while searching: it would offer a control
                        // that deliberately does nothing.
                        if store.settings.collapsibleSections, !isSearching {
                            // Rotates rather than swapping glyphs, so the
                            // direction of travel is obvious and the header
                            // doesn't reflow when it turns.
                            Image(systemName: "chevron.down")
                                .font(.system(size: 9, weight: .bold))
                                .rotationEffect(.degrees(isCollapsed(section) ? -90 : 0))
                                .foregroundStyle(headingColor(for: section))
                        }
                        Text(section.group.title.uppercased())
                            .font(.system(size: 12, weight: .bold))
                            .tracking(0.6)
                            .foregroundStyle(headingColor(for: section))
                        Spacer()
                        // The full count, not the visible one — a collapsed
                        // section should still say how much is inside.
                        Text("\(section.tasks.count)")
                            .font(Theme.numeric(12, weight: .semibold))
                            .foregroundStyle(
                                section.isUrgent
                                    ? Theme.Palette.overdue : Theme.Palette.slate
                            )
                    }
                    .contentShape(Rectangle())
                    .onTapGesture {
                        guard store.settings.collapsibleSections, !isSearching else { return }
                        toggleCollapsed(section)
                    }
                }
            }
        }
        .listStyle(.insetGrouped)
        .scrollDismissesKeyboard(.immediately)
    }

    /// New tasks start due **today**, at 5pm.
    ///
    /// Most tasks people add are things they mean to deal with now, so a date is
    /// the common case and None is the exception — and a task with no date can
    /// only be found in All Tasks or No Due Date, which is a quiet way to lose
    /// one. The field still opens to a None option, so clearing it is one tap.
    ///
    /// Two tabs override it, because the tab says otherwise more loudly than
    /// the default does: No Due Date, where an undated task is the entire point,
    /// and Completed, where a new task isn't finished and would vanish on save.
    /// Both then rely on the "lands somewhere visible" rule below.
    private func startNewTask() {
        var draft = TPTask()
        draft.dueDate = Self.defaultDueDate()

        switch store.activeTab {
        case .noDueDate, .completed:
            draft.dueDate = nil
        case .category(let name):
            // Adding from a category tab should arrive already tagged.
            draft.categories = [name]
        case .all, .today, .overdue, .noCategory:
            // No Category deliberately seeds no category — untagged IS the trait.
            break
        }
        draftTask = draft
    }

    /// 5pm today, matching the hour the date picker lands on elsewhere, so a
    /// task added now doesn't read as already overdue by lunchtime.
    static func defaultDueDate(now: Date = Date()) -> Date {
        Calendar.current.date(bySettingHour: 17, minute: 0, second: 0, of: now) ?? now
    }

    // MARK: Empty state

    private var emptyState: some View {
        VStack(spacing: 10) {
            Image(systemName: "checkmark.circle")
                .font(.system(size: 36, weight: .ultraLight))
                .foregroundStyle(Theme.Palette.slate)
            Text(emptyTitle)
                .font(.headline)
                .foregroundStyle(Theme.Palette.ink)
            Text(emptyGuidance)
                .font(.subheadline)
                .foregroundStyle(Theme.Palette.slate)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 40)
            Button("Add a task") {
                startNewTask()
            }
            .buttonStyle(.borderedProminent)
            .tint(Theme.Palette.ink)
            .padding(.top, 4)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var emptyTitle: String {
        if !store.searchText.isEmpty { return "No matches" }
        if !store.selectedCategories.isEmpty { return "Nothing in these categories" }
        if store.activeTab == .today { return "Nothing due today" }
        if store.activeTab == .overdue { return "Nothing overdue" }
        if store.activeTab == .noDueDate { return "Nothing undated" }
        if store.activeTab == .completed { return "Nothing completed yet" }
        if store.activeTab == .noCategory { return "Nothing uncategorized" }
        if let name = store.activeTab.categoryName { return "Nothing in \(name)" }
        return "All clear"
    }

    private var emptyGuidance: String {
        if !store.searchText.isEmpty {
            return "Try a shorter search, or clear it to see everything."
        }
        if !store.selectedCategories.isEmpty {
            return "Clear the filter to see the rest of your tasks."
        }
        if store.activeTab == .today {
            return "No overdue tasks and nothing due today. Check All Tasks for what's coming."
        }
        if store.activeTab == .overdue {
            return "You're caught up. Nothing is past its due date."
        }
        if store.activeTab == .noDueDate {
            return "Every task has a due date."
        }
        if store.activeTab == .completed {
            return "Finished tasks collect here, newest first."
        }
        if store.activeTab == .noCategory {
            return "Every task has a category."
        }
        if store.activeTab.categoryName != nil {
            return "Tag a task with this category and it shows up here."
        }
        if hiddenUndatedCount > 0 {
            return "\(hiddenUndatedCount) undated task\(hiddenUndatedCount == 1 ? " is" : "s are") hidden. Change that in Display settings."
        }
        return "Nothing is due. Add a task and it syncs to Outlook."
    }

    /// How many undated tasks the current tab is hiding.
    ///
    /// Only the tabs that actually apply the setting get a banner. Today and
    /// Overdue exclude undated tasks by definition, No Due Date deliberately
    /// ignores the setting, and Completed isn't affected — a banner on any of
    /// those would be explaining a rule that isn't in force there.
    private var hiddenUndatedCount: Int {
        guard store.settings.noDueDatePlacement == .hidden else { return 0 }
        switch store.activeTab {
        case .all:
            return store.undatedCount
        case .category(let name):
            return store.undatedCount(inCategory: name)
        case .noCategory:
            return store.undatedUncategorizedCount
        case .today, .overdue, .noDueDate, .completed:
            return 0
        }
    }

    /// Session-only, and keyed by tab + section so the same category collapsed
    /// in one tab doesn't vanish in another.
    ///
    /// Not persisted: date sections like "Wed, August 19" stop existing, so
    /// stored keys would accumulate forever.
    @State private var collapsedSections: Set<String> = []

    private func collapseKey(_ section: DueSection) -> String {
        "\(store.activeTab.id)|\(section.group.title)"
    }

    /// The one section whose collapse survives a launch: No Due Date, in All
    /// Tasks, with *Remember No Due Date in All Tasks* on.
    ///
    /// It qualifies where nothing else does because it's a pinned section —
    /// `TaskStore` builds it from `noDueDatePlacement` in every grouping — so it
    /// still exists after a regroup, and it's a single Boolean rather than an
    /// unbounded set of keys. The No Due Date *tab* is deliberately excluded:
    /// there the section is the entire list, not a slice of it, and a collapsed
    /// launch would show an empty tab.
    private func isPersistedSection(_ section: DueSection) -> Bool {
        store.settings.remembersUndatedCollapse
            && store.activeTab == .all
            && section.group == .noDate
    }

    /// A search is running. Collapse is suspended while one is.
    /// Names up to two categories, counts beyond — so the line can't wrap and
    /// double its height however many are ticked.
    private var filterBannerLabel: String {
        let names = store.orderedCategories
            .map(\.name)
            .filter { store.selectedCategories.contains($0) }
        let all = names.isEmpty ? Array(store.selectedCategories).sorted() : names
        return all.count <= 2 ? all.joined(separator: ", ") : "\(all.count) categories"
    }

    private var isSearching: Bool {
        !store.searchText.trimmingCharacters(in: .whitespaces).isEmpty
    }

    private func isCollapsed(_ section: DueSection) -> Bool {
        // A collapsed section during a search hides matches — the user asked for
        // those rows, and a heading they collapsed an hour ago silently swallows
        // them. Sections that survive a search are all expanded, on every tab and
        // whichever fields are being searched.
        //
        // Suspended, not cleared: leaving the search restores exactly the
        // arrangement you had.
        guard !isSearching else { return false }
        guard store.settings.collapsibleSections else { return false }
        if isPersistedSection(section) {
            return store.settings.undatedCollapsedInAllTasks
        }
        return collapsedSections.contains(collapseKey(section))
    }

    private func toggleCollapsed(_ section: DueSection) {
        if isPersistedSection(section) {
            store.settings.undatedCollapsedInAllTasks.toggle()
            return
        }
        let key = collapseKey(section)
        if collapsedSections.contains(key) {
            collapsedSections.remove(key)
        } else {
            collapsedSections.insert(key)
        }
    }

    private func headingColor(for section: DueSection) -> Color {
        if section.isUrgent { return Theme.Palette.overdue }
        if section.group == .noDate { return Theme.Palette.undated }
        return Theme.Palette.heading
    }

    private func undoToast(
        _ pending: UndoCoordinator.Pending,
        undo: @escaping () -> Void,
        dismiss: @escaping () async -> Void
    ) -> some View {
        UndoBar(pending: pending, undo: undo, dismiss: dismiss)
    }


    // MARK: Tab bar

    private var tabBar: some View {
        ScrollViewReader { proxy in
            ScrollView(.horizontal) {
                HStack(spacing: 8) {
                    ForEach(store.availableTabs) { tab in
                        pill(for: tab).id(tab)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.top, 10)
                .padding(.bottom, 12)
            }
            .scrollIndicators(.hidden)
            // Don't rubber-band when the pills already fit — on a wide screen
            // a bouncing row that can't actually scroll reads as broken.
            .scrollBounceBehavior(.basedOnSize, axes: .horizontal)
            // A pill you tapped at the edge, or one revealed when Overdue
            // appears, should end up fully visible rather than half cut off.
            .onChange(of: store.activeTab) { _, tab in
                withAnimation(.snappy(duration: 0.2)) {
                    proxy.scrollTo(tab, anchor: .center)
                }
            }
        }
        .background(Theme.Palette.paper)
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(Theme.Palette.hairline)
                .frame(height: 1)
        }
    }

    private func pill(for tab: TaskTab) -> some View {
        let isSelected = store.activeTab == tab
        let showsBadge = store.showsBadge(for: tab)
        // Computed lazily: with badges off this scan never runs, which is the
        // whole reason the toggle exists.
        let count = showsBadge ? store.badge(for: tab) : 0

        // Category pills always wear their own color — that IS the label. Since
        // the fill is spoken for, selection reads as a ring instead.
        // White for No Category — it needs an outline or it vanishes against
        // the paper tab bar, handled in the overlay below.
        let isNoCategory = tab == .noCategory
        let categoryColor: Color? = isNoCategory
            ? .white
            : tab.categoryName.flatMap { name in
                store.categories.first { $0.name == name }.map(\.color)
              }
        let fill = categoryColor ?? (isSelected ? Theme.Palette.ink : Theme.Palette.canvas)
        let ink: Color = isNoCategory
            ? Theme.Palette.ink
            : categoryColor == nil
                ? (isSelected ? .white : Theme.Palette.ink)
                : (tab.categoryName.flatMap { name in
                    store.categories.first { $0.name == name }
                        .map { OutlookCategoryPalette.foreground(for: $0.colorIndex) }
                  } ?? .white)

        return Button {
            withAnimation(.snappy(duration: 0.18)) { store.selectedTab = tab }
        } label: {
            HStack(spacing: 7) {
                Text(tab.title)
                    .font(.system(size: 14, weight: .semibold))
                if showsBadge {
                    Text("\(count)")
                        .font(Theme.numeric(12, weight: .semibold))
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(
                            Capsule().fill(
                                categoryColor != nil
                                    ? ink.opacity(0.18)
                                    : (isSelected ? Color.white.opacity(0.22) : Theme.Palette.hairline)
                            )
                        )
                        .foregroundStyle(categoryColor != nil ? ink : (isSelected ? .white : Theme.Palette.slate))
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .background(Capsule().fill(fill))
            .foregroundStyle(ink)
            .overlay {
                if isSelected, categoryColor != nil {
                    Capsule()
                        .strokeBorder(Theme.Palette.ink, lineWidth: 2)
                        .padding(-3)
                } else if isNoCategory {
                    Capsule().strokeBorder(Theme.Palette.hairline, lineWidth: 1)
                }
            }
        }
        .buttonStyle(.plain)
        // Long press rather than a second tap target: the pill is small and its
        // tap already means "switch to this tab". A context menu is the standard
        // iOS way to reach a secondary action without hijacking the primary one.
        .contextMenu {
            Button {
                store.settings.toggleBadge(forTabID: tab.id)
            } label: {
                Label(
                    showsBadge ? "Hide count" : "Show count",
                    systemImage: showsBadge ? "eye.slash" : "eye"
                )
            }
            Divider()
            Button("Tab counts…") { showsBadgeSettings = true }
        }
        .accessibilityLabel(showsBadge
            ? "\(tab.title), \(count) task\(count == 1 ? "" : "s")"
            : tab.title)
        .accessibilityAddTraits(isSelected ? [.isSelected, .isButton] : .isButton)
    }

    // MARK: Toolbar

    @ToolbarContentBuilder
    private var toolbar: some ToolbarContent {
        @Bindable var store = store
        @Bindable var settings = store.settings

        ToolbarItem(placement: .topBarLeading) {
            Menu {
                // Above the categories, not below them: on a long list the
                // bottom of the menu is the last place you look, and clearing is
                // usually the thing you came back to do.
                if !store.selectedCategories.isEmpty {
                    Section {
                        Button("Clear filter") { store.selectedCategories.removeAll() }
                    }
                }
                Section("Filter By Category") {
                    // At most five, preferring whatever is currently ticked —
                    // the common case is clearing a filter you just set, which
                    // should stay one tap. The rest live on their own screen.
                    ForEach(menuFilterCategories) { category in
                        Button {
                            toggleFilter(category.name)
                        } label: {
                            Label {
                                Text(category.name)
                            } icon: {
                                Image(systemName: store.selectedCategories.contains(category.name)
                                      ? "checkmark.circle.fill" : "circle")
                            }
                        }
                    }
                    if store.categoriesInUse.count > menuFilterLimit {
                        Button {
                            showsCategoryFilter = true
                        } label: {
                            Label("Click here for more categories",
                                  systemImage: "ellipsis.circle")
                        }
                    }
                }
                Divider()
                // Undated placement lives in Settings, not here. A filter menu
                // should filter; a submenu that sets where a section sits was
                // doing a different job in the same place.
                Button {
                    showsSettings = true
                } label: {
                    // Bold black rather than the ink navy: this is the way out
                    // of a filter menu into everything else, so it shouldn't
                    // read as just another row.
                    //
                    // The ellipsis stays: in Apple's language a trailing "…"
                    // means the item opens something rather than acting
                    // immediately. No chevron either — that would say "pushes a
                    // screen", and Settings arrives as a sheet.
                    Label {
                        Text("Task Perfect settings…")
                            .fontWeight(.bold)
                            .foregroundStyle(.black)
                    } icon: {
                        Image(systemName: "gearshape")
                    }
                }
            } label: {
                Image(systemName: store.selectedCategories.isEmpty
                      ? "line.3.horizontal.decrease" : "line.3.horizontal.decrease.circle.fill")
            }
        }

        ToolbarItem(placement: .topBarLeading) {
            Button {
                Task { await store.syncChanges() }
            } label: {
                if store.isLoading || store.isSyncing {
                    ProgressView().controlSize(.small)
                } else {
                    Image(systemName: store.isOffline ? "arrow.clockwise.circle.dashed" : "arrow.clockwise")
                        .foregroundStyle(store.isOffline ? Theme.Palette.slate : Theme.Palette.ink)
                }
            }
            // Tappable while offline on purpose — the attempt fails fast and
            // tells the user something, which beats a dead-looking button.
            .disabled(store.isLoading || store.isSyncing)
            .accessibilityLabel("Sync now")
        }

        ToolbarItem(placement: .principal) {
            HStack(spacing: 7) {
                AppMark(size: 26)
                VStack(spacing: 1) {
                    Text("Task Perfect").font(.headline)
                    // Active tasks due today only — not overdue, not completed.
                    // The Overdue pill carries the late count, and in red;
                    // repeating it here made the same number mean two things.
                    // Connectivity outranks the due-today count: "3 due today"
                    // while silently offline is a worse lie than a missing count.
                    if store.isOffline {
                        Label(
                            store.queuedChangeCount > 0
                                ? "Offline · \(store.queuedChangeCount) waiting"
                                : "Offline",
                            systemImage: "wifi.slash"
                        )
                        .font(Theme.numeric(11))
                        .foregroundStyle(Theme.Palette.flag)
                    } else if store.queuedChangeCount > 0 {
                        Text("\(store.queuedChangeCount) change\(store.queuedChangeCount == 1 ? "" : "s") to sync")
                            .font(Theme.numeric(11))
                            .foregroundStyle(Theme.Palette.slate)
                    } else if store.todayOutstanding > 0 {
                        // Overdue plus due today, never completed — the same
                        // number the app icon shows. It tracks the Today badge
                        // until you reveal completed tasks there, at which point
                        // the badge counts them and this doesn't.
                        Text("\(store.todayOutstanding) task\(store.todayOutstanding == 1 ? "" : "s") due")
                            .font(Theme.numeric(11))
                            .foregroundStyle(Theme.Palette.slate)
                    } else if let synced = store.lastSynced {
                        Text("Updated \(synced.formatted(date: .omitted, time: .shortened))")
                            .font(Theme.numeric(11))
                            .foregroundStyle(Theme.Palette.slate)
                    }
                }
            }
        }

        ToolbarItem(placement: .topBarTrailing) {
            Button {
                startNewTask()
            } label: {
                Image(systemName: "plus")
            }
        }
    }

    private var dialogTitle: String {
        switch pending {
        case .complete: return "Mark this task complete?"
        default:        return "Delete this task?"
        }
    }

    /// Completing is gated by a preference; reopening never is. Undo should stay
    /// cheap, or people get wary of the checkbox itself.
    private func requestToggle(_ task: TPTask) {
        if store.settings.confirmsCompletion && !task.isComplete {
            pending = .complete(task)
        } else {
            Task { await store.toggleComplete(task) }
        }
    }

    /// Recurring tasks don't simply close — they spawn the next occurrence.
    /// Naming that date is the whole reason this confirmation earns its keep.
    static func completionNote(for task: TPTask) -> String {
        guard let recurrence = task.recurrence else {
            return "\"\(task.subject)\" will be marked complete. You can reopen it afterwards."
        }
        let reference = recurrence.isRegenerating ? Date() : (task.dueDate ?? Date())
        if let next = RecurrenceEngine.nextDate(after: reference, recurrence: recurrence) {
            return "This closes the current occurrence and creates the next one, due \(next.formatted(date: .abbreviated, time: .omitted))."
        }
        return "This is the last occurrence — completing it ends the series."
    }

    /// Names the task and says what else goes with it. A recurring task takes
    /// its whole schedule down, which is not obvious from "Delete".
    static func deleteWarning(for task: TPTask) -> String {
        var text = "\"\(task.subject)\" will be removed from Outlook as well. This can't be undone."
        if task.recurrence != nil {
            text += " Future occurrences will stop."
        }
        return text
    }

    private func toggleFilter(_ name: String) {
        if store.selectedCategories.contains(name) {
            store.selectedCategories.remove(name)
        } else {
            store.selectedCategories.insert(name)
        }
    }
}

#Preview {
    let store = TaskStore(backend: MockBackend(latency: .zero))
    return TaskListView()
        .environment(store)
        .task { await store.load() }
}

/// Its own view because the drag needs per-bar state — two bars can be on
/// screen at once and must not share an offset.
private struct UndoBar: View {

    let pending: UndoCoordinator.Pending
    let undo: () -> Void
    let dismiss: () async -> Void

    @State private var dragOffset: CGFloat = 0

    var body: some View {
        HStack(spacing: 14) {
            Text(pending.message)
                .font(.subheadline)
                .foregroundStyle(.white)
            Spacer(minLength: 0)
            Button("Undo", action: undo)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(AppMark.green)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .background(
            RoundedRectangle(cornerRadius: Theme.Metrics.corner)
                .fill(Theme.Palette.ink)
        )
        // Narrower side margins than a list row: the bar is transient and reads
        // better spanning most of the screen.
        .padding(.horizontal, 8)
        .padding(.bottom, 12)
        // The bar tracks the finger the whole way — a gesture with no visual
        // response is indistinguishable from a broken one. Release past the
        // threshold commits; release short of it springs back. Downward only:
        // an accidental sideways swipe shouldn't end the window.
        .offset(y: max(0, dragOffset))
        .opacity(dragOffset > 0 ? max(0, 1 - dragOffset / 140) : 1)
        .gesture(
            DragGesture(minimumDistance: 6)
                .onChanged { value in
                    guard abs(value.translation.height) > abs(value.translation.width)
                    else { return }
                    dragOffset = value.translation.height
                }
                .onEnded { value in
                    if value.translation.height > 44,
                       abs(value.translation.height) > abs(value.translation.width) {
                        withAnimation(.snappy(duration: 0.18)) { dragOffset = 200 }
                        Task {
                            try? await Task.sleep(for: .milliseconds(140))
                            await dismiss()
                            dragOffset = 0
                        }
                    } else {
                        withAnimation(.snappy(duration: 0.18)) { dragOffset = 0 }
                    }
                }
        )
        .accessibilityElement(children: .combine)
        .accessibilityLabel(pending.message)
        .accessibilityHint("Swipe down to confirm, or tap Undo")
        // A swipe isn't reachable by VoiceOver, so the same action is named.
        .accessibilityAction(named: "Dismiss") { Task { await dismiss() } }
    }
}
