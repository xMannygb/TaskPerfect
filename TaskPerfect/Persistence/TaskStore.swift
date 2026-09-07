import Foundation
import Observation
import SwiftUI

/// In-memory source of truth for the UI.
///
/// The UI reads only from here and never awaits the network. When you add
/// SwiftData, this class keeps its API — swap the arrays for a model context and
/// nothing in `Features/` changes.
@MainActor
@Observable
public final class TaskStore {

    // MARK: State

    public private(set) var tasks: [TPTask] = []
    public private(set) var categories: [TPCategory] = []
    public private(set) var folders: [TPTaskList] = []
    public private(set) var isLoading = false
    /// True during an incremental sync, so the toolbar button can show progress
    /// without the list flashing its full-screen loading state.
    public private(set) var isSyncing = false
    public private(set) var lastError: TaskBackendError?
    public private(set) var lastSynced: Date?

    /// Filter state, owned here so it survives navigation.
    public var searchText: String = ""
    public var selectedCategories: Set<String> = []
    public var selectedTab: TaskTab = .all

    /// Reminders dismissed from the on-open banner.
    ///
    /// **Local to this launch, and deliberately so.** Exchange keeps one
    /// reminder per task and Outlook holds its own dismissal state; writing
    /// `reminderIsSet = false` from here would clear the reminder on every
    /// client, which is not what tapping "Dismiss" on a phone means. The cost
    /// is that the same reminder can greet you on two devices — the right
    /// trade, since the alternative silently destroys data.
    ///
    /// Clearing a reminder for good is what the task editor is for.
    public private(set) var dismissedReminderIDs: Set<String> = []

    /// Set once the banner has been shown and closed for this launch, so it
    /// doesn't reappear every time the list redraws.
    public var remindersBannerHandled = false

    /// Reminders that came due while you were away: set, in the past, and not
    /// yet done. Sorted oldest first — the one you're most likely to have
    /// missed leads.
    public var dueReminders: [TPTask] {
        let now = Date()
        return tasks.filter { task in
            task.hasReminder
                && !task.isComplete
                && !dismissedReminderIDs.contains(task.itemID)
                && (task.reminderDueBy ?? .distantFuture) <= now
        }
        .sorted { ($0.reminderDueBy ?? .distantPast) < ($1.reminderDueBy ?? .distantPast) }
    }

    public func dismissReminder(_ id: String) {
        dismissedReminderIDs.insert(id)
    }

    public func dismissAllReminders() {
        dismissedReminderIDs.formUnion(dueReminders.map(\.itemID))
    }

    /// Display preferences. Shared, not copied — the settings screen mutates the
    /// same object the list reads from, so changes land without a round trip.
    public let settings: AppSettings

    private let backend: any TaskBackend
    private var syncToken: SyncToken?
    private var activeFolderID: String?
    private var autoSyncTask: Task<Void, Never>?

    /// On-disk store. Optional so previews and tests can run without SwiftData.
    private let local: LocalStore?
    public let reachability: Reachability

    /// Changes waiting for the server, read from disk so the count survives a
    /// relaunch. The in-memory `isDirty` flags drive the row indicator; this
    /// drives the toolbar.
    public private(set) var queuedChangeCount = 0

    /// Separate coordinators, so deleting a task never cuts short a pending
    /// category delete. That independence is the point of having two.
    /// Tasks batch, categories don't — see `UndoCoordinator.batches`.
    public let taskUndo = UndoCoordinator(batches: true)
    public let categoryUndo = UndoCoordinator(batches: false)

    public init(
        backend: any TaskBackend,
        settings: AppSettings,
        local: LocalStore? = nil,
        reachability: Reachability
    ) {
        self.backend = backend
        self.settings = settings
        self.local = local
        self.reachability = reachability
        self.taskUndo.window = settings.taskUndoWindow.duration
        self.categoryUndo.window = settings.categoryUndoWindow.duration

        // Drain the moment a connection returns, rather than waiting for the
        // user to notice and tap sync.
        self.reachability.onReconnect = { [weak self] in
            Task { await self?.syncChanges() }
        }
    }

    // MARK: Offline

    public var isOffline: Bool { !reachability.isOnline }

    /// Load from disk. Fast, works with no connection, and is what makes the app
    /// open to a full list on a plane.
    public func loadFromDisk() async {
        guard let local else { return }
        do {
            let cached = try await local.allTasks()
            if !cached.isEmpty { tasks = cached }
            let cachedCategories = try await local.allCategories()
            if !cachedCategories.isEmpty { categories = cachedCategories }
            lastSynced = try await local.lastSynced()
            queuedChangeCount = try await local.pendingCount()
            if let folderID = activeFolderID ?? folders.first(where: \.isDefault)?.folderID {
                syncToken = try await local.syncToken(folderID: folderID)
            }
        } catch {
            // A cache read failure isn't fatal — the next sync repopulates it.
            lastError = .malformedResponse(detail: "Couldn't read local data")
        }
    }

    private func persist(_ task: TPTask) async {
        try? await local?.save(task)
    }

    private func refreshQueueCount() async {
        queuedChangeCount = (try? await local?.pendingCount()) ?? queuedChangeCount
    }

    /// Queue an outbound change and write the task to disk in one step, so the
    /// two can't disagree if the app is killed between them.
    private func queue(
        _ operation: PendingChange.Operation,
        _ task: TPTask
    ) async {
        guard let local else { return }
        if operation != .delete { try? await local.save(task) }
        try? await local.enqueue(
            operation,
            taskLocalID: task.localID,
            itemID: task.itemID,
            changeKey: task.changeKey
        )
        await refreshQueueCount()
    }

    public var capabilities: BackendCapabilities { backend.capabilities }

    public var resolver: TPCategoryResolver { TPCategoryResolver(master: categories) }

    /// Categories in the user's chosen order. Everything that lists categories
    /// reads this, so one reorder moves the filter menu, the manager and the
    /// picker together.
    public var orderedCategories: [TPCategory] { settings.ordered(categories) }

    /// Move one category to a new position and persist the whole ordering.
    public func moveCategory(_ name: String, by offset: Int) {
        var names = orderedCategories.map(\.name)
        guard let from = names.firstIndex(of: name) else { return }
        let to = from + offset
        guard names.indices.contains(to) else { return }
        names.swapAt(from, to)
        settings.setCategoryOrder(names)
    }

    public func moveCategories(fromOffsets source: IndexSet, toOffset destination: Int) {
        var names = orderedCategories.map(\.name)
        names.move(fromOffsets: source, toOffset: destination)
        settings.setCategoryOrder(names)
    }

    public func resetCategoryOrder() {
        settings.resetCategoryOrderAlphabetically(categories)
    }

    // MARK: Loading

    public func load() async {
        isLoading = true
        lastError = nil
        defer { isLoading = false }

        do {
            async let foldersTask = backend.taskFolders()
            async let categoriesTask = backend.masterCategories()
            folders = try await foldersTask
            categories = try await categoriesTask

            let folderID = activeFolderID
                ?? folders.first(where: \.isDefault)?.folderID
                ?? folders.first?.folderID
            guard let folderID else { return }
            activeFolderID = folderID

            let delta = try await backend.changes(in: folderID, since: syncToken)
            apply(delta)
        } catch let error as TaskBackendError {
            lastError = error
        } catch {
            lastError = .malformedResponse(detail: error.localizedDescription)
        }
    }

    /// Throw away everything cached and pull the mailbox again.
    ///
    /// The escape hatch for "sync looks wrong and I can't tell why" — a stale
    /// token, a half-applied delta, anything that leaves the local copy out of
    /// step. An action rather than a mode: it self-corrects and then resumes
    /// delta syncing, so there's no way to leave the app permanently doing full
    /// syncs.
    ///
    /// Pending changes are pushed first. Clearing the store without sending them
    /// would silently discard edits that never reached Exchange.
    public func resetCache() async {
        guard !isSyncing else { return }
        isSyncing = true
        lastError = nil

        await pushPendingChanges()
        try? await local?.clearTasks()
        syncToken = nil
        tasks = []
        lastSynced = nil
        isSyncing = false

        await load()
    }

    /// Full reload — folders, categories and a fresh snapshot. Used on first run
    /// and when the server says our sync state is no good.
    public func refresh() async {
        syncToken = nil
        await load()
    }

    /// **Sync only what changed.**
    ///
    /// Three things a plain reload doesn't do:
    ///
    /// 1. **Pushes pending local edits first.** Pulling before pushing means the
    ///    server's older copy overwrites work that never left the device.
    /// 2. **Drains every page.** EWS returns changes in batches; one call can
    ///    leave changes behind, and the next sync would start from a token that
    ///    claims they were already seen.
    /// 3. **Skips folders and categories.** Those rarely change and cost a round
    ///    trip each — they're only re-read when the server forces a full resync.
    public func syncChanges() async {
        guard !isSyncing else { return }        // a second tap shouldn't double-run
        // Offline isn't an error — the queue is already holding the work and
        // will drain on reconnect. Reporting a failure here would be noise.
        guard reachability.isOnline else { return }
        isSyncing = true
        defer { isSyncing = false }
        lastError = nil

        await pushPendingChanges()

        guard let folderID = activeFolderID else {
            await load()
            return
        }

        do {
            var pages = 0
            while pages < 50 {                  // stop a bad server spinning forever
                let delta = try await backend.changes(in: folderID, since: syncToken)
                apply(delta)

                if delta.isFullResync {
                    // Our state was rejected; the category list may have moved on too.
                    categories = try await backend.masterCategories()
                }
                if delta.includesLastItemInRange { break }
                pages += 1
            }
            lastSynced = Date()
        } catch TaskBackendError.syncStateInvalid {
            // Normal, not an error: start over from a clean snapshot.
            syncToken = nil
            await load()
        } catch let error as TaskBackendError {
            lastError = error
        } catch {
            lastError = .malformedResponse(detail: error.localizedDescription)
        }
    }

    /// Everything edited locally and not yet accepted by the server.
    public var pendingChanges: [TPTask] {
        tasks.filter(\.isDirty)
    }

    public var pendingChangeCount: Int { pendingChanges.count }

    /// Drain the durable queue.
    ///
    /// Reads each change from disk, sends it, and removes it only on success.
    /// A failure records the error and backs off — the change survives the app
    /// being killed and is retried when the network returns.
    private func pushPendingChanges() async {
        guard let local, let folderID = activeFolderID else {
            await pushInMemoryChanges()     // no disk store (previews, tests)
            return
        }
        guard reachability.isOnline else { return }

        let queued = (try? await local.pendingChanges()) ?? []
        for change in queued {
            guard change.isReady else { continue }     // still backing off

            do {
                switch change.operation {
                case .delete:
                    try await backend.delete(itemID: change.itemID, changeKey: change.changeKey)

                case .create, .update:
                    // Read the payload fresh, so edits made after queueing ride
                    // along instead of being lost or needing their own entry.
                    guard let current = try await local.task(localID: change.taskLocalID) else {
                        try await local.remove(changeID: change.id)   // deleted since
                        continue
                    }
                    let stored = change.operation == .create || !current.existsOnServer
                        ? try await backend.create(current, in: folderID)
                        : try await backend.update(current)

                    var settled = stored
                    settled.isDirty = false
                    try await local.save(settled)
                    if let index = tasks.firstIndex(where: { $0.localID == settled.localID }) {
                        tasks[index] = settled
                    }
                }
                try await local.remove(changeID: change.id)

            } catch TaskBackendError.conflict {
                // Someone edited elsewhere. The server copy wins; drop our change
                // and let the pull below bring theirs in. Retrying would just
                // fail again on the same stale changeKey.
                try? await local.remove(changeID: change.id)
                lastError = .conflict(itemID: change.itemID)

            } catch TaskBackendError.itemNotFound {
                try? await local.remove(changeID: change.id)   // already gone

            } catch let error as TaskBackendError {
                try? await local.recordFailure(changeID: change.id, message: error.localizedDescription)
                if !error.isRetryable { lastError = error }

            } catch {
                try? await local.recordFailure(changeID: change.id, message: error.localizedDescription)
            }
        }
        await refreshQueueCount()
    }

    /// Fallback for the no-disk case, which is how previews and tests run.
    private func pushInMemoryChanges() async {
        guard let folderID = activeFolderID else { return }
        for task in pendingChanges {
            guard let index = tasks.firstIndex(where: { $0.id == task.id }) else { continue }
            do {
                let stored = task.existsOnServer
                    ? try await backend.update(tasks[index])
                    : try await backend.create(tasks[index], in: folderID)
                if let current = tasks.firstIndex(where: { $0.id == stored.id }) {
                    tasks[current] = stored
                }
            } catch let error as TaskBackendError {
                lastError = error
            } catch {
                continue
            }
        }
    }

    private func apply(_ delta: TaskDelta) {
        if delta.isFullResync { tasks.removeAll() }
        for incoming in delta.upserted {
            if let index = tasks.firstIndex(where: { $0.itemID == incoming.itemID }) {
                // Never let a server copy stomp an unpushed local edit.
                if !tasks[index].isDirty { tasks[index] = incoming }
            } else {
                tasks.append(incoming)
            }
        }
        tasks.removeAll { delta.deletedItemIDs.contains($0.itemID) }
        syncToken = delta.nextToken
        lastSynced = Date()

        // Write through, so the next cold launch has this without a network.
        if let local, let folderID = activeFolderID {
            let upserted = delta.upserted
            let deleted = delta.deletedItemIDs
            let token = delta.nextToken
            let synced = lastSynced
            let wasFullResync = delta.isFullResync
            Task {
                if wasFullResync { try? await local.clearTasks() }
                try? await local.upsert(upserted)
                try? await local.deleteTasks(itemIDs: deleted)
                try? await local.setSyncToken(token, folderID: folderID, syncedAt: synced)
            }
        }
    }

    // MARK: Mutations

    /// Optimistic: the row updates immediately, the server catches up.
    ///
    /// Recurring tasks take a different path — see `completeRecurring`.
    public func toggleComplete(_ task: TPTask) async {
        guard let index = tasks.firstIndex(where: { $0.id == task.id }) else { return }

        if task.recurrence != nil && !task.isComplete {
            await completeRecurring(task, at: index)
            scheduleAutoSync()
            return
        }

        tasks[index].toggleComplete()
        await queue(.update, tasks[index])
        scheduleAutoSync()
    }

    /// Checking off a recurring task closes the current occurrence and opens the next.
    ///
    /// Matches Outlook: the finished one stays in the list as a completed record
    /// without its recurrence, and a fresh task appears for the next date. When the
    /// series has run out, only the completed record remains.
    private func completeRecurring(_ task: TPTask, at index: Int) async {
        let (finished, next) = RecurrenceEngine.complete(task)

        tasks[index] = finished
        await queue(.update, finished)

        guard let next else { return }
        tasks.append(next)
        await queue(.create, next)
    }

    /// Advance a recurring task without marking it done — "skip this one".
    public func skipOccurrence(_ task: TPTask) async {
        guard let index = tasks.firstIndex(where: { $0.id == task.id }),
              let recurrence = task.recurrence,
              let nextDue = RecurrenceEngine.nextDate(
                  after: task.dueDate ?? Date(), recurrence: recurrence
              )
        else { return }

        var advanced = task
        advanced.dueDate = nextDue
        advanced.markDirty()
        tasks[index] = advanced
        await queue(.update, advanced)
        scheduleAutoSync()
    }

    public func save(_ edited: TPTask) async {
        guard let index = tasks.firstIndex(where: { $0.id == edited.id }) else { return }
        var updated = edited
        updated.markDirty()
        tasks[index] = updated
        await queue(.update, updated)
        scheduleAutoSync()
    }

    public func create(subject: String) async {
        guard let folderID = activeFolderID else { return }
        await create(TPTask(folderID: folderID, subject: subject))
    }

    /// Create from a fully-formed draft — dates, categories, recurrence and all.
    public func create(_ task: TPTask) async {
        guard let folderID = activeFolderID else { return }
        var draft = task
        draft.folderID = folderID
        draft.markDirty()
        tasks.append(draft)
        // Queued, not pushed. A task added offline has to stay on screen —
        // deleting it because the network was down would lose the user's work.
        await queue(.create, draft)
        scheduleAutoSync()
    }

    /// Remove the row now, send the delete in five seconds.
    ///
    /// The row vanishing immediately is what makes it feel instant; the delay is
    /// what makes it safe. Nothing reaches Exchange until the window closes.
    public func delete(_ task: TPTask) async {
        tasks.removeAll { $0.id == task.id }
        // Undo off: send it now. Staging with a zero window would still flash a
        // bar the user can't use.
        guard settings.offersTaskUndo else {
            await commitDelete(task)
            return
        }
        taskUndo.window = settings.taskUndoWindow.duration
        taskUndo.stage(
            describe: { count in
                count == 1 ? "Task deleted" : "\(count) tasks deleted"
            },
            restore: { [weak self] in
                guard let self, !self.tasks.contains(where: { $0.localID == task.localID })
                else { return }
                self.tasks.append(task)
            },
            commit: { [weak self] in await self?.commitDelete(task) }
        )
    }

    public func undoTaskDelete() { taskUndo.undo() }
    public func undoCategoryDelete() { categoryUndo.undo() }

    /// Dismissing the bar means "yes, I meant it" — send it now rather than
    /// hiding the bar while the delete stays secretly cancellable.
    public func dismissTaskUndo() async { await taskUndo.commitNow() }
    public func dismissCategoryUndo() async { await categoryUndo.commitNow() }

    /// Send a delete for real. Only ever called by the undo window closing.
    private func commitDelete(_ task: TPTask) async {
        try? await local?.delete(localID: task.localID)
        // A task never sent to the server just disappears; `enqueue` cancels the
        // matching create rather than asking Exchange to delete an item it has
        // never heard of.
        await queue(.delete, task)
        scheduleAutoSync()
    }

    /// Flush any staged delete. Called when the app backgrounds — a pending
    /// delete that survived a quit would look deleted, not be, and offer no way
    /// back.
    public func commitPendingDeletes() async {
        await taskUndo.commitNow()
        await categoryUndo.commitNow()
    }

    public func clearError() { lastError = nil }

    // MARK: Sync after changes

    /// Queue a sync following a change, if the setting allows it.
    ///
    /// Coalesced rather than immediate. Checking off five tasks in a row is five
    /// changes but should be one round trip — firing on each would put the app
    /// in a permanent sync spin and, on a slow connection, queue syncs faster
    /// than they complete. Each call cancels the one before it, so the sync runs
    /// shortly after you stop.
    private func scheduleAutoSync() {
        guard settings.syncsAfterChanges else { return }
        autoSyncTask?.cancel()
        autoSyncTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(2))
            guard !Task.isCancelled else { return }
            await self?.syncChanges()
        }
    }

    /// Sync now, skipping the coalescing delay.
    public func syncAfterChangeNow() async {
        autoSyncTask?.cancel()
        await syncChanges()
    }

    // MARK: Category management

    /// How many tasks currently carry this category name.
    /// Shown before rename and delete, because both are only meaningful in
    /// proportion to how much is tagged with it.
    public func taskCount(forCategory name: String) -> Int {
        tasks.filter { $0.categories.contains(name) }.count
    }

    @discardableResult
    public func addCategory(name rawName: String, colorIndex: Int) async -> Bool {
        let name = rawName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { return false }
        guard !categories.contains(where: { $0.name.caseInsensitiveCompare(name) == .orderedSame }) else {
            lastError = .duplicateCategory(name: name)
            return false
        }
        let snapshot = categories
        categories.append(TPCategory(name: name, colorIndex: colorIndex, guid: UUID().uuidString))
        await pushCategories(rollingBackTo: snapshot)
        return true
    }

    public func recolor(_ category: TPCategory, to colorIndex: Int) async {
        guard let index = categories.firstIndex(where: { $0.name == category.name }) else { return }
        let snapshot = categories
        categories[index].colorIndex = colorIndex
        await pushCategories(rollingBackTo: snapshot)
    }

    /// Rename a category **and every task carrying it**.
    ///
    /// This cascade is the whole point. Exchange stores category *names* on task
    /// items, not references — rename the list entry alone and every tagged task
    /// silently becomes an orphan pointing at a name that no longer exists.
    @discardableResult
    public func rename(_ category: TPCategory, to rawName: String) async -> Bool {
        let newName = rawName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !newName.isEmpty, newName != category.name else { return false }
        guard !categories.contains(where: {
            $0.name.caseInsensitiveCompare(newName) == .orderedSame && $0.name != category.name
        }) else {
            lastError = .duplicateCategory(name: newName)
            return false
        }
        guard let index = categories.firstIndex(where: { $0.name == category.name }) else { return false }

        let snapshot = categories
        categories[index].name = newName
        settings.migrateTextStyle(from: category.name, to: newName)
        // The completed flag is keyed by name too, so it has to follow.
        settings.renameCategoryCompletedFlag(from: category.name, to: newName)
        settings.renameInCategoryOrder(from: category.name, to: newName)
        await pushCategories(rollingBackTo: snapshot)

        // Carry the rename onto every tagged task.
        for position in tasks.indices where tasks[position].categories.contains(category.name) {
            tasks[position].categories = tasks[position].categories.map {
                $0 == category.name ? newName : $0
            }
            tasks[position].markDirty()
            await pushTask(at: position)
        }

        // Any active filter was keyed on the old name.
        if selectedCategories.remove(category.name) != nil {
            selectedCategories.insert(newName)
        }
        return true
    }

    /// Remove a category from the master list.
    ///
    /// Tasks keep the label — this matches desktop Outlook, where a deleted
    /// category leaves its name on items, rendered uncolored. `TPCategoryResolver`
    /// already handles those orphans, so nothing breaks; the tag just loses its
    /// color. Stripping the name off tasks instead would be a silent data loss.
    /// Remove the category now, send it when the window closes.
    ///
    /// Undo restores the styling and ordering too, not just the list entry —
    /// both are keyed by name and were cleared on the way out.
    public func deleteCategory(_ category: TPCategory) async {
        let snapshot = categories
        let style = settings.textStyle(for: category.name)
        // Captured before the delete clears it, so undo puts it back too.
        let showedCompleted = settings.showsCompleted(inCategory: category.name)
        let orderIndex = settings.categoryOrder.firstIndex(of: category.name)
        let wasFiltered = selectedCategories.contains(category.name)

        categories.removeAll { $0.name == category.name }
        settings.resetTextStyle(for: category.name)
        settings.clearCompletedFlag(for: category.name)
        settings.removeFromCategoryOrder(category.name)
        selectedCategories.remove(category.name)

        guard settings.offersCategoryUndo else {
            await pushCategories(rollingBackTo: snapshot)
            return
        }
        categoryUndo.window = settings.categoryUndoWindow.duration
        categoryUndo.stage(
            describe: { _ in "\(category.name) deleted" },
            restore: { [weak self] in
                guard let self else { return }
                self.categories = snapshot
                if let style { self.settings.setTextStyle(style, for: category.name) }
                if showedCompleted {
                    self.settings.setShowsCompleted(true, inCategory: category.name)
                }
                if let orderIndex {
                    var order = self.settings.categoryOrder
                    order.insert(category.name, at: min(orderIndex, order.count))
                    self.settings.setCategoryOrder(order)
                }
                if wasFiltered { self.selectedCategories.insert(category.name) }
            },
            commit: { [weak self] in
                await self?.pushCategories(rollingBackTo: snapshot)
            }
        )
    }

    /// Also strip the name from every task. Explicit, opt-in destruction.
    ///
    /// The affected task IDs are snapshotted *before* the strip, because undo
    /// has to know which tasks to re-tag — after the fact there's nothing left
    /// to identify them by.
    public func deleteCategory(_ category: TPCategory, removingFromTasks: Bool) async {
        guard removingFromTasks else {
            await deleteCategory(category)
            return
        }

        let snapshot = categories
        let style = settings.textStyle(for: category.name)
        // Captured before the delete clears it, so undo puts it back too.
        let showedCompleted = settings.showsCompleted(inCategory: category.name)
        let orderIndex = settings.categoryOrder.firstIndex(of: category.name)
        let taggedIDs = tasks.filter { $0.categories.contains(category.name) }.map(\.localID)

        categories.removeAll { $0.name == category.name }
        settings.resetTextStyle(for: category.name)
        settings.clearCompletedFlag(for: category.name)
        settings.removeFromCategoryOrder(category.name)
        for position in tasks.indices where tasks[position].categories.contains(category.name) {
            tasks[position].categories.removeAll { $0 == category.name }
        }

        let count = taggedIDs.count
        guard settings.offersCategoryUndo else {
            await pushCategories(rollingBackTo: snapshot)
            for position in tasks.indices where taggedIDs.contains(tasks[position].localID) {
                tasks[position].markDirty()
                await queue(.update, tasks[position])
            }
            scheduleAutoSync()
            return
        }
        categoryUndo.window = settings.categoryUndoWindow.duration
        categoryUndo.stage(
            describe: { _ in
                "\(category.name) deleted from \(count) task\(count == 1 ? "" : "s")"
            },
            restore: { [weak self] in
                guard let self else { return }
                self.categories = snapshot
                if let style { self.settings.setTextStyle(style, for: category.name) }
                if showedCompleted {
                    self.settings.setShowsCompleted(true, inCategory: category.name)
                }
                if let orderIndex {
                    var order = self.settings.categoryOrder
                    order.insert(category.name, at: min(orderIndex, order.count))
                    self.settings.setCategoryOrder(order)
                }
                for position in self.tasks.indices
                where taggedIDs.contains(self.tasks[position].localID)
                   && !self.tasks[position].categories.contains(category.name) {
                    self.tasks[position].categories.append(category.name)
                }
            },
            commit: { [weak self] in
                guard let self else { return }
                await self.pushCategories(rollingBackTo: snapshot)
                for position in self.tasks.indices
                where taggedIDs.contains(self.tasks[position].localID) {
                    self.tasks[position].markDirty()
                    await self.queue(.update, self.tasks[position])
                }
                self.scheduleAutoSync()
            }
        )
    }

    private func pushCategories(rollingBackTo snapshot: [TPCategory]) async {
        defer { scheduleAutoSync() }   // covers add / rename / recolor / delete
        do {
            try await backend.saveMasterCategories(categories)
        } catch let error as TaskBackendError {
            categories = snapshot
            lastError = error
        } catch {
            categories = snapshot
        }
    }

    private func pushTask(at index: Int) async {
        guard tasks.indices.contains(index), tasks[index].existsOnServer else { return }
        let snapshot = tasks[index]
        do {
            let stored = try await backend.update(tasks[index])
            if let current = tasks.firstIndex(where: { $0.id == stored.id }) {
                tasks[current] = stored
            }
        } catch let error as TaskBackendError {
            if let current = tasks.firstIndex(where: { $0.id == snapshot.id }) {
                tasks[current] = snapshot
            }
            lastError = error
        } catch {
            if let current = tasks.firstIndex(where: { $0.id == snapshot.id }) {
                tasks[current] = snapshot
            }
        }
    }
}

// MARK: - Derived views of the data

public extension TaskStore {

    /// Whether a task falls inside the configured date window.
    ///
    /// Anchored on the completion date when there is one, otherwise the due
    /// date — a task finished yesterday shouldn't vanish because it was *due*
    /// two years ago. Undated tasks have no anchor and always pass; the No Due
    /// Date placement setting governs those instead.
    func withinDateRange(_ task: TPTask, now: Date = Date(), calendar: Calendar = .current) -> Bool {
        guard let anchor = task.completeDate ?? task.dueDate else { return true }
        if let earliest = settings.earliestInRange(from: now, calendar: calendar),
           anchor < calendar.startOfDay(for: earliest) {
            return false
        }
        // Both edges snap to whole days, or the window is lopsided: an exact
        // timestamp on the far edge would hide a task due at 5pm on the last
        // day while showing its counterpart the same distance back.
        if let latest = settings.latestInRange(from: now, calendar: calendar),
           let endOfDay = calendar.date(bySettingHour: 23, minute: 59, second: 59, of: latest),
           anchor > endOfDay {
            return false
        }
        return true
    }

    /// Tasks the date range is currently hiding. Surfaced in Settings so a
    /// narrow window never means "silently gone".
    var outOfRangeCount: Int {
        guard settings.hasDateRangeLimit else { return 0 }
        return tasks.filter { !withinDateRange($0) }.count
    }

    /// Search and category filters only — the parts that apply on every tab.
    func matchesFilters(_ task: TPTask) -> Bool {
        // The window applies everywhere, so it lives here rather than in each tab.
        if !withinDateRange(task) { return false }
        if !selectedCategories.isEmpty,
           selectedCategories.isDisjoint(with: Set(task.categories)) {
            return false
        }
        if !searchText.isEmpty {
            let needle = searchText.lowercased()
            if !searchHaystack(for: task).contains(needle) { return false }
        }
        return true
    }

    /// The text search looks through, built from the fields ticked in Settings →
    /// Appearance → Search fields. Never empty: `AppSettings` guarantees at
    /// least one field, so search can't be configured to match nothing.
    ///
    /// Notes use `plainText`, never the raw HTML — searching markup for "li"
    /// would match every bulleted note, and "b" every bold word. Deriving it
    /// costs a string per task per keystroke and changes nothing on disk; the
    /// stored body keeps its formatting.
    func searchHaystack(for task: TPTask) -> String {
        var parts: [String] = []
        let settings = self.settings
        if settings.searches(.subject)    { parts.append(task.subject) }
        if settings.searches(.notes)      { parts.append(task.body.plainText) }
        if settings.searches(.categories) { parts.append(task.categories.joined(separator: " ")) }
        if settings.searches(.assignedTo) { parts.append(task.companies.joined(separator: " ")) }
        if settings.searches(.status)     { parts.append(task.status.displayName) }
        // High only — the word is added when the task carries it, so "high"
        // matches and "low"/"normal" find nothing, which is what the row says.
        if settings.searches(.highPriority), task.importance == .high {
            parts.append("High")
        }
        return parts.joined(separator: " ").lowercased()
    }

    var visibleTasks: [TPTask] { visibleTasks(for: activeTab) }

    /// The tab is a parameter, never read from `activeTab`.
    ///
    /// Badges compute every tab at once, so a filter that consulted the tab you
    /// happen to be standing in gave every other tab that tab's answer — which
    /// is why turning completed on in All Tasks pushed the No Category badge up,
    /// and why it dropped again the moment you navigated away.
    func visibleTasks(for tab: TaskTab) -> [TPTask] {
        tasks.filter { task in
            guard matchesFilters(task) else { return false }
            if task.isComplete && !settings.showsCompleted(inTab: tab.id) { return false }
            // Hidden undated tasks still exist and still sync — they're only
            // withheld from this list.
            if settings.noDueDatePlacement == .hidden,
               task.dueDate == nil, !task.isComplete {
                return false
            }
            return true
        }
    }

    /// What the Today tab shows: overdue first, then today. Never completed,
    /// never undated — the display preferences for those govern All Tasks, where
    /// they're a matter of taste. Here they'd contradict what the tab means.
    var todayTasks: [TPTask] {
        let calendar = Calendar.current
        return tasks.filter { task in
            guard matchesFilters(task) else { return false }
            // Completed tasks appear only when asked for, and only if they were
            // completed today — a task finished last week isn't a today task,
            // however it was scheduled. Without this the banner counted them
            // and offered to show them, but the list never changed.
            if task.isComplete {
                guard settings.showsCompleted(inTab: TaskTab.today.id),
                      let done = task.completeDate ?? task.dueDate
                else { return false }
                return calendar.isDateInToday(done)
            }
            let group = DueGroup.group(for: task)
            return group == .overdue || group == .today
        }
    }

    /// Every task past due and not finished.
    var overdueTasks: [TPTask] {
        tasks.filter { matchesFilters($0) && !$0.isComplete && DueGroup.group(for: $0) == .overdue }
    }

    /// Deliberately ignores search and category filters.
    ///
    /// Tab *visibility* keys off this rather than `overdueTasks` so the pill
    /// doesn't vanish mid-keystroke when a search happens to exclude everything
    /// late. The tab stays, its badge reads 0, and the empty state explains why.
    var hasOverdueTasks: Bool {
        tasks.contains { !$0.isComplete && DueGroup.group(for: $0) == .overdue }
    }

    /// Active tasks with no due date at all.
    ///
    /// Deliberately ignores the "Don't show" display preference. That setting
    /// governs All Tasks, where undated work is a matter of taste; a tab whose
    /// entire job is showing undated tasks can't honor a preference to hide them.
    var undatedTasks: [TPTask] {
        tasks.filter { task in
            guard matchesFilters(task), task.dueDate == nil else { return false }
            // Completed undated tasks appear only when this tab asks for them.
            // Without this the tab had nothing to reveal and so carried no
            // banner at all.
            if task.isComplete { return settings.showsCompleted(inTab: TaskTab.noDueDate.id) }
            return true
        }
    }

    /// Same rules as All Tasks — completed hidden unless asked for, undated
    /// placement honored — narrowed to one category. A category tab is a view of
    /// the list, not a different kind of list.
    /// Everything tagged with this category.
    ///
    /// A task carrying two categories appears in both pills — that's what the
    /// tag means, and hiding it from the second would diverge from Outlook,
    /// where opening the task shows both.
    ///
    /// Completed tasks follow the category-tab setting rather than the global
    /// "Show completed", because the question "is this category finished?" is
    /// different from "do I want done items in my main list?".
    func tasks(inCategory name: String) -> [TPTask] {
        tasks.filter { task in
            guard matchesFilters(task), task.categories.contains(name) else { return false }
            if task.isComplete { return settings.showsCompleted(inCategory: name) }
            // The undated placement setting still applies; its own tab is the
            // exception, not this one.
            if settings.noDueDatePlacement == .hidden, task.dueDate == nil { return false }
            return true
        }
    }

    /// Active tasks only — what pill visibility keys off.
    func activeCount(inCategory name: String) -> Int {
        tasks.filter { !$0.isComplete && $0.categories.contains(name) }.count
    }

    /// Completed tasks the current main tab would show.
    ///
    /// All Tasks counts everything in range; Today counts only what was
    /// completed today, so its banner is usually absent.
    var completedCountForMainTab: Int {
        let calendar = Calendar.current
        return tasks.filter { task in
            guard task.isComplete, withinDateRange(task) else { return false }
            if activeTab == .today {
                guard let done = task.completeDate ?? task.dueDate else { return false }
                return calendar.isDateInToday(done)
            }
            if activeTab == .noCategory {
                return task.categories.isEmpty && matchesFilters(task)
            }
            // Completed tasks that never had a due date — the only ones this
            // tab could reveal.
            if activeTab == .noDueDate {
                return task.dueDate == nil && matchesFilters(task)
            }
            return matchesFilters(task)
        }.count
    }

    func completedCount(inCategory name: String) -> Int {
        tasks.filter { $0.isComplete && $0.categories.contains(name) }.count
    }

    /// Same rules as All Tasks, narrowed to the untagged.
    var uncategorizedTasks: [TPTask] {
        // Its own tab, not whichever is active — otherwise this badge borrowed
        // the current tab's completed setting.
        visibleTasks(for: .noCategory).filter { $0.categories.isEmpty }
    }

    /// Visibility ignores search and category filters, like the Overdue and No
    /// Due Date pills: a tab shouldn't blink out mid-keystroke.
    var hasUncategorizedTasks: Bool {
        tasks.contains { $0.categories.isEmpty && !$0.isComplete }
    }

    /// Finished tasks, newest completion first.
    ///
    /// Ignores the "Show completed" display preference for the same reason the
    /// No Due Date tab ignores its own: that setting governs All Tasks, and a tab
    /// whose entire job is showing completed work can't honor a preference to
    /// hide it.
    var completedTasks: [TPTask] {
        tasks.filter { matchesFilters($0) && $0.isComplete }
            .sorted(by: DueSection.recentlyCompleted)
    }

    /// Same reasoning as `hasOverdueTasks`: ignores search and category filters
    /// so the pill doesn't blink out mid-keystroke.
    var hasUndatedTasks: Bool {
        tasks.contains { !$0.isComplete && $0.dueDate == nil }
    }

    /// Whether a category still earns a pill.
    ///
    /// Visible when it has active tasks, or has completed tasks and the category
    /// tab is showing those. Otherwise it goes — except while you're standing in
    /// it, which is the reprieve applied below.
    func categoryEarnsPill(_ name: String) -> Bool {
        if settings.isAlwaysShown(tabID: TaskTab.category(name).id) { return true }
        if activeCount(inCategory: name) > 0 { return true }
        return settings.showsCompleted(inCategory: name) && completedCount(inCategory: name) > 0
    }

    /// Overdue and No Due Date only earn a pill when they'd have something in
    /// them. All Tasks and Today are always meaningful, so they always show.
    var availableTabs: [TaskTab] {
        let fixed = TaskTab.fixed.filter { tab in
            switch tab {
            case .overdue:   return settings.isAlwaysShown(tabID: tab.id) || hasOverdueTasks
            case .noDueDate: return settings.isAlwaysShown(tabID: tab.id) || hasUndatedTasks
            default:         return true
            }
        }
        // No Category sits with the fixed tabs rather than at the end of the
        // categories: it isn't a category, it's the absence of one.
        let uncategorized: [TaskTab] =
            (hasUncategorizedTasks || settings.isAlwaysShown(tabID: TaskTab.noCategory.id))
            ? [.noCategory] : []

        // Category pills follow, in the order set in the category manager.
        //
        // A pill you're currently standing in keeps its place even when it stops
        // earning one, so completing the last task in a category doesn't yank
        // the tab out from under you. It goes on the next tab you select — the
        // reprieve is per-pill, and sheets or Settings don't count as leaving.
        let standingIn = selectedTab.categoryName
        let categoryTabs = orderedCategories
            .filter { categoryEarnsPill($0.name) || $0.name == standingIn }
            .map { TaskTab.category($0.name) }

        return fixed + uncategorized + categoryTabs
    }

    /// The tab actually being shown.
    ///
    /// `selectedTab` is what the user last tapped; this is what survives. Clear
    /// the final overdue task while standing in that tab and the pill disappears
    /// underneath you — without this fallback you'd be left on a tab that no
    /// longer exists. Computed rather than assigned so nothing mutates state
    /// during a view update.
    var activeTab: TaskTab {
        availableTabs.contains(selectedTab) ? selectedTab : .all
    }

    var sections: [DueSection] {
        switch activeTab {
        case .all:
            return mainSections(of: visibleTasks, options: settings.mainSort)
        case .today:
            // Today holds overdue plus today's, so due-date grouping yields the
            // two sections it already had. Grouping by category is where this
            // setting actually does something here.
            return mainSections(of: todayTasks, options: settings.todaySort)
        case .overdue:
            return overdueSections
        case .noDueDate:
            return undatedSections()
        case .completed:
            return completedSections()
        case .category(let name):
            return categorySections(for: name)
        case .noCategory:
            return noCategorySections()
        }
    }

    /// One section per person, from Assigned To.
    ///
    /// A task files under its **first** assignee, matching the first-category
    /// rule — it appears once, not once per name. Unassigned sinks to the
    /// bottom whichever direction is chosen, like undated tasks.
    /// Note there are no pinned Overdue or No Due Date sections here.
    ///
    /// Grouping by assignee answers "what does this person owe me", so every
    /// task files under a name — including overdue and undated ones, which
    /// every other grouping pins into their own sections. Pinning them here
    /// would put the most urgent assigned work somewhere other than under the
    /// person responsible for it. They keep their red date and warning icon
    /// inside the section.
    private func assignedSections(
        _ source: [TPTask],
        options: CategorySortOptions,
        descending: Bool,
        urgent: Bool = false
    ) -> [DueSection] {
        let order = orderedCategories.map(\.name)
        let grouped = Dictionary(grouping: source) { $0.assignee }
        return grouped
            .map { name, items in
                DueSection(group: name.isEmpty ? .unassigned : .assignedTo(name),
                           tasks: options.sorted(items, order: order),
                           forcesUrgent: urgent)
            }
            .sorted { lhs, rhs in
                switch (lhs.group, rhs.group) {
                case (.unassigned, _): return false
                case (_, .unassigned): return true
                default:
                    let result = lhs.group.title.localizedCaseInsensitiveCompare(rhs.group.title)
                    return descending
                        ? result == .orderedDescending
                        : result == .orderedAscending
                }
            }
    }

    /// The Completed tab, grouped and sorted by `completedSort`.
    ///
    /// Completion dates are all in the past, so the levels are labelled "most
    /// recent / oldest" rather than the future-facing "soonest / furthest" used
    /// for due dates.
    private func completedSections() -> [DueSection] {
        let options = settings.completedSort
        let source = completedTasks
        guard !source.isEmpty else { return [] }

        let order = orderedCategories.map(\.name)
        let calendar = Calendar.current

        switch options.grouping {
        case .completionDate:
            // Exchange doesn't always populate completeDate — a task marked done
            // by an older client can arrive without it. Those get their own
            // section at the bottom rather than being dropped or guessed at.
            let dated = source.filter { $0.completeDate != nil }
            let undated = source.filter { $0.completeDate == nil }

            var result = Dictionary(grouping: dated) {
                calendar.startOfDay(for: $0.completeDate ?? Date())
            }
            .map { day, items in
                DueSection(group: .day(day), tasks: options.sorted(items, order: order))
            }
            // Most recently completed first, matching the tab's existing order.
            .sorted { $0.group.sortKey() > $1.group.sortKey() }

            if !undated.isEmpty {
                result.append(DueSection(group: .noCompletionDate,
                                         tasks: options.sorted(undated, order: order)))
            }
            return result

        case .dueDate:
            let dated = source.filter { $0.dueDate != nil }
            let undated = source.filter { $0.dueDate == nil }

            var result = Dictionary(grouping: dated) {
                calendar.startOfDay(for: $0.dueDate ?? Date())
            }
            .map { day, items in
                DueSection(group: .day(day), tasks: options.sorted(items, order: order))
            }
            .sorted { $0.group.sortKey() < $1.group.sortKey() }

            if !undated.isEmpty {
                result.append(DueSection(group: .noDate,
                                         tasks: options.sorted(undated, order: order)))
            }
            return result

        case .assignedAZ, .assignedZA:
            return assignedSections(source, options: options,
                                    descending: options.grouping == .assignedZA)

        // Category grouping isn't offered here, so anything else is one list.
        // Horizon isn't offered here — All Tasks only, for now.
        case .ungrouped, .category, .horizon:
            return [DueSection(group: .completed, tasks: options.sorted(source, order: order))]
        }
    }

    /// The No Category tab, grouped and sorted by `noCategorySort`.
    ///
    /// Both groupings offer the same levels — nothing here carries a category,
    /// so the category levels would have nothing to order by. Overdue and
    /// undated stay pinned, as they do in the main tabs.
    private func noCategorySections() -> [DueSection] {
        let options = settings.noCategorySort
        let source = uncategorizedTasks
        guard !source.isEmpty else { return [] }

        let undatedFirst = settings.noDueDatePlacement == .top
        let calendar = Calendar.current

        switch options.grouping {
        case .dueDate:
            return Dictionary(grouping: source) { DueGroup.group(for: $0, calendar: calendar) }
                .map { group, items in
                    /* Overdue alone keeps its own ordering: how late something
                       is *is* the organizing idea, and no sort level expresses
                       it under due-date grouping. No Due Date has no date to
                       order by, so exempting it bought nothing — it just meant
                       choosing Z–A and finding one section still in A–Z. */
                    let sorted = (group == .overdue)
                        ? items.sorted(by: DueSection.dueThenAlphabetical)
                        : options.sorted(items)
                    return DueSection(group: group, tasks: sorted)
                }
                .sorted { $0.group.sortKey(undatedFirst: undatedFirst)
                        < $1.group.sortKey(undatedFirst: undatedFirst) }

        // Category grouping isn't offered here, so anything else is one list.
        case .assignedAZ, .assignedZA:
            return assignedSections(source, options: options,
                                    descending: options.grouping == .assignedZA)

        case .ungrouped, .category, .completionDate, .horizon:
            return pinnedSections(source, options: options, order: [],
                                  undatedFirst: undatedFirst, bodyGroup: .allTasks)
        }
    }

    /// The No Due Date tab, grouped and sorted by `undatedSort`.
    ///
    /// This tab deliberately ignores the "Don't show undated tasks" placement
    /// setting — a tab whose job is showing undated tasks can't honour a
    /// preference to hide them. So it can show tasks hidden everywhere else.
    private func undatedSections() -> [DueSection] {
        let options = settings.undatedSort
        let source = undatedTasks
        guard !source.isEmpty else { return [] }

        let order = orderedCategories.map(\.name)

        switch options.grouping {
        case .category:
            let grouped = Dictionary(grouping: source) {
                CategorySortOptions.SortLevel.homeCategory($0) ?? ""
            }
            let rank = Dictionary(uniqueKeysWithValues: order.enumerated().map { ($1, $0) })
            return grouped.keys.sorted { a, b in
                if a.isEmpty != b.isEmpty { return b.isEmpty }
                let i = rank[a] ?? Int.max, j = rank[b] ?? Int.max
                if i != j { return i < j }
                return a.localizedCaseInsensitiveCompare(b) == .orderedAscending
            }.compactMap { key in
                guard let items = grouped[key] else { return nil }
                return DueSection(
                    group: .categoryNamed(key.isEmpty ? "No Category" : key),
                    tasks: options.sorted(items, order: order)
                )
            }

        // Due-date grouping isn't offered here — nothing has a date — so
        // anything but `.category` is one list.
        case .assignedAZ, .assignedZA:
            return assignedSections(source, options: options,
                                    descending: options.grouping == .assignedZA)

        case .ungrouped, .dueDate, .completionDate, .horizon:
            return [DueSection(group: .noDate, tasks: options.sorted(source, order: order))]
        }
    }

    /// The Overdue tab, grouped and sorted by `overdueSort`.
    ///
    /// **No pinned overdue section here.** Elsewhere overdue tasks are lifted
    /// out and exempted from the configured sort; in this tab every task is
    /// overdue, so that rule would make the whole thing one exempt section and
    /// leave the settings inert. No undated section either — an undated task is
    /// never overdue.
    private var overdueSections: [DueSection] {
        let options = settings.overdueSort
        let source = overdueTasks
        guard !source.isEmpty else { return [] }

        let order = orderedCategories.map(\.name)
        let calendar = Calendar.current

        switch options.grouping {
        case .dueDate:
            // One section per past date, oldest first. Tends toward many sparse
            // groups, since overdue tasks spread across whatever dates they
            // missed — Ungrouped often reads better in this tab.
            return Dictionary(grouping: source) {
                calendar.startOfDay(for: $0.dueDate ?? Date())
            }
            .map { day, items in
                DueSection(group: .day(day),
                           tasks: options.sorted(items, order: order),
                           forcesUrgent: true)
            }
            .sorted { $0.group.sortKey() < $1.group.sortKey() }

        case .category:
            let grouped = Dictionary(grouping: source) {
                CategorySortOptions.SortLevel.homeCategory($0) ?? ""
            }
            let rank = Dictionary(uniqueKeysWithValues: order.enumerated().map { ($1, $0) })
            return grouped.keys.sorted { a, b in
                if a.isEmpty != b.isEmpty { return b.isEmpty }
                let i = rank[a] ?? Int.max, j = rank[b] ?? Int.max
                if i != j { return i < j }
                return a.localizedCaseInsensitiveCompare(b) == .orderedAscending
            }.compactMap { key in
                guard let items = grouped[key] else { return nil }
                return DueSection(
                    group: .categoryNamed(key.isEmpty ? "No Category" : key),
                    tasks: options.sorted(items, order: order),
                    forcesUrgent: true
                )
            }

        case .assignedAZ, .assignedZA:
            return assignedSections(source, options: options,
                                    descending: options.grouping == .assignedZA, urgent: true)

        // Completion grouping isn't offered here. Horizon belongs with them
        // rather than with .dueDate: every task in this tab is already in the
        // past, so the horizon classifier puts all of them under one Overdue
        // heading — which is exactly the single section built below.
        case .ungrouped, .completionDate, .horizon:
            return [DueSection(group: .overdue,
                               tasks: options.sorted(source, order: order),
                               forcesUrgent: true)]
        }
    }

    /// All Tasks and Today, grouped and sorted by `mainSort`.
    ///
    /// Overdue stays pinned at the top and No Due Date keeps its placement in
    /// every grouping — they're pinned sections with their own ordering, not
    /// part of the configured sort.
    private func mainSections(
        of source: [TPTask],
        options: CategorySortOptions
    ) -> [DueSection] {
        guard !source.isEmpty else { return [] }

        let undatedFirst = settings.noDueDatePlacement == .top
        let order = orderedCategories.map(\.name)
        let calendar = Calendar.current

        switch options.grouping {
        case .dueDate:
            return Dictionary(grouping: source) { DueGroup.group(for: $0, calendar: calendar) }
                .map { group, items in
                    // Overdue and undated keep their own ordering.
                    /* Overdue alone keeps its own ordering: how late something
                       is *is* the organizing idea, and no sort level expresses
                       it under due-date grouping. No Due Date has no date to
                       order by, so exempting it bought nothing — it just meant
                       choosing Z–A and finding one section still in A–Z. */
                    let sorted = (group == .overdue)
                        ? items.sorted(by: DueSection.dueThenAlphabetical)
                        : options.sorted(items, order: order)
                    return DueSection(group: group, tasks: sorted)
                }
                .sorted { $0.group.sortKey(undatedFirst: undatedFirst)
                        < $1.group.sortKey(undatedFirst: undatedFirst) }

        case .horizon:
            /* Same shape as due-date grouping — only the classifier differs, so
               Overdue, Today, Tomorrow and No Due Date behave identically and
               the placement setting needs no special case. Empty sections are
               never built, which is what makes "Rest of This Week" vanish on a
               Saturday. */
            return Dictionary(grouping: source) {
                DueGroup.horizonGroup(for: $0, calendar: calendar)
            }
            .map { group, items in
                let sorted = (group == .overdue)
                    ? items.sorted(by: DueSection.dueThenAlphabetical)
                    : options.sorted(items, order: order)
                return DueSection(group: group, tasks: sorted)
            }
            .sorted { $0.group.sortKey(undatedFirst: undatedFirst)
                    < $1.group.sortKey(undatedFirst: undatedFirst) }

        case .category:
            return categoryGroupedSections(source, options: options, order: order,
                                           undatedFirst: undatedFirst)

        case .assignedAZ, .assignedZA:
            return assignedSections(source, options: options,
                                    descending: options.grouping == .assignedZA)

        // Completion grouping isn't offered here.
        case .ungrouped, .completionDate, .horizon:
            return pinnedSections(source, options: options, order: order,
                                  undatedFirst: undatedFirst, bodyGroup: .allTasks)
        }
    }

    /// One section per category, a task filing under its **first** tag.
    ///
    /// A partition, not a filter: a task with two categories appears once.
    /// Overlapping groups would make the section counts exceed the task total.
    /// Note this differs from a category *tab*, where the same task appears in
    /// both pills — a tab is a filtered view, a group is a partition.
    private func categoryGroupedSections(
        _ source: [TPTask],
        options: CategorySortOptions,
        order: [String],
        undatedFirst: Bool
    ) -> [DueSection] {
        var result: [DueSection] = []

        // Overdue and undated stay pinned, out of the category partition —
        // otherwise a late task would hide inside a category section.
        let overdue = source.filter { DueGroup.group(for: $0) == .overdue }
        let undated = source.filter { $0.dueDate == nil && !$0.isComplete }
        let body = source.filter {
            DueGroup.group(for: $0) != .overdue && !($0.dueDate == nil && !$0.isComplete)
        }

        if !overdue.isEmpty {
            result.append(DueSection(group: .overdue,
                                     tasks: overdue.sorted(by: DueSection.dueThenAlphabetical),
                                     forcesUrgent: true))
        }
        // Follows the configured sort, like every other section. Only Overdue
        // keeps an ordering of its own.
        let undatedSection = undated.isEmpty ? nil
            : DueSection(group: .noDate, tasks: options.sorted(undated, order: order))
        if undatedFirst, let undatedSection { result.insert(undatedSection, at: 0) }

        let grouped = Dictionary(grouping: body) {
            CategorySortOptions.SortLevel.homeCategory($0) ?? ""
        }
        // Manual pill order, then anything unknown A–Z, then untagged last.
        let rank = Dictionary(uniqueKeysWithValues: order.enumerated().map { ($1, $0) })
        let sortedKeys = grouped.keys.sorted { a, b in
            if a.isEmpty != b.isEmpty { return b.isEmpty }
            let i = rank[a] ?? Int.max, j = rank[b] ?? Int.max
            if i != j { return i < j }
            return a.localizedCaseInsensitiveCompare(b) == .orderedAscending
        }
        for key in sortedKeys {
            guard let items = grouped[key] else { continue }
            result.append(DueSection(
                group: .categoryNamed(key.isEmpty ? "No Category" : key),
                tasks: options.sorted(items, order: order)
            ))
        }

        if !undatedFirst, let undatedSection { result.append(undatedSection) }
        return result
    }

    /// Overdue pinned, undated placed, everything else in one body section.
    private func pinnedSections(
        _ source: [TPTask],
        options: CategorySortOptions,
        order: [String],
        undatedFirst: Bool,
        bodyGroup: DueGroup
    ) -> [DueSection] {
        var result: [DueSection] = []
        let overdue = source.filter { DueGroup.group(for: $0) == .overdue }
        let undated = source.filter { $0.dueDate == nil && !$0.isComplete }
        let rest = source.filter {
            DueGroup.group(for: $0) != .overdue && !($0.dueDate == nil && !$0.isComplete)
        }

        if !overdue.isEmpty {
            result.append(DueSection(group: .overdue,
                                     tasks: overdue.sorted(by: DueSection.dueThenAlphabetical),
                                     forcesUrgent: true))
        }
        // Follows the configured sort, like every other section. Only Overdue
        // keeps an ordering of its own.
        let undatedSection = undated.isEmpty ? nil
            : DueSection(group: .noDate, tasks: options.sorted(undated, order: order))
        if undatedFirst, let undatedSection { result.insert(undatedSection, at: 0) }
        if !rest.isEmpty {
            result.append(DueSection(group: bodyGroup, tasks: options.sorted(rest, order: order)))
        }
        if !undatedFirst, let undatedSection { result.append(undatedSection) }
        return result
    }

    /// Category tabs group and sort by their own settings.
    ///
    /// Overdue stays pinned at the top and No Due Date keeps its placement, in
    /// both groupings — which is why "Ungrouped" can still yield three sections
    /// rather than one.
    private func categorySections(for name: String) -> [DueSection] {
        let options = settings.categorySort
        let source = tasks(inCategory: name)
        guard !source.isEmpty else { return [] }

        let undatedFirst = settings.noDueDatePlacement == .top
        let calendar = Calendar.current

        switch options.grouping {
        case .dueDate:
            return Dictionary(grouping: source) { DueGroup.group(for: $0, calendar: calendar) }
                .map { DueSection(group: $0.key, tasks: options.sorted($0.value)) }
                .sorted { $0.group.sortKey(undatedFirst: undatedFirst)
                        < $1.group.sortKey(undatedFirst: undatedFirst) }

        case .horizon:
            /* Suits a pill better than it suits All Tasks: a category holds
               fewer tasks over the same span, which is exactly when day-by-day
               grouping reads worst — fifteen tasks making fourteen headings that
               hold one row each. */
            return Dictionary(grouping: source) {
                DueGroup.horizonGroup(for: $0, calendar: calendar)
            }
            .map { DueSection(group: $0.key, tasks: options.sorted($0.value)) }
            .sorted { $0.group.sortKey(undatedFirst: undatedFirst)
                    < $1.group.sortKey(undatedFirst: undatedFirst) }

        case .assignedAZ, .assignedZA:
            return assignedSections(source, options: options,
                                    descending: options.grouping == .assignedZA)

        // Completion grouping isn't offered here. Horizon has its own case above.
        case .ungrouped, .completionDate, .category:
            // Three buckets at most: late, undated, everything else. The
            // configured sort orders within each.
            var result: [DueSection] = []
            let overdue = source.filter { DueGroup.group(for: $0) == .overdue }
            let undated = source.filter { $0.dueDate == nil && !$0.isComplete }
            let rest = source.filter {
                DueGroup.group(for: $0) != .overdue && !($0.dueDate == nil && !$0.isComplete)
            }

            if !overdue.isEmpty {
                result.append(DueSection(group: .overdue,
                                         tasks: overdue.sorted(by: DueSection.dueThenAlphabetical),
                                         forcesUrgent: true))
            }
            let undatedSection = undated.isEmpty ? nil
                : DueSection(group: .noDate, tasks: options.sorted(undated))
            if undatedFirst, let undatedSection { result.insert(undatedSection, at: 0) }

            if !rest.isEmpty {
                result.append(DueSection(group: .allTasks, tasks: options.sorted(rest)))
            }
            if !undatedFirst, let undatedSection { result.append(undatedSection) }
            return result
        }
    }

    private func sections(of source: [TPTask], undatedFirst: Bool) -> [DueSection] {
        let calendar = Calendar.current
        // Every group sorts the same way now: due date, then A–Z. Within a dated
        // section that still ranks by time of day, and undated tasks fall
        // straight through to alphabetical.
        return Dictionary(grouping: source) { DueGroup.group(for: $0, calendar: calendar) }
            .map { DueSection(group: $0.key, tasks: $0.value.sorted(by: DueSection.dueThenAlphabetical)) }
            .sorted { $0.group.sortKey(undatedFirst: undatedFirst)
                    < $1.group.sortKey(undatedFirst: undatedFirst) }
    }

    // MARK: Tab badges

    /// Everything the All Tasks tab is currently listing — so the badge always
    /// matches what's on screen, including the effect of filters and settings.
    var allTabCount: Int { visibleTasks(for: .all).count }

    /// Active tasks due **today only**. Overdue is excluded on purpose: it has
    /// its own section and its own red, and folding it in here would make the
    /// number mean two different things at once.
    /// What the tab actually lists, completed included when that tab asks for
    /// them — otherwise its badge never moved while its list did.
    var todayTabCount: Int { todayTasks.count }

    /// Work still to do: overdue plus due today, never completed.
    ///
    /// Drives both the line under the logo and the app icon badge. It
    /// deliberately differs from the Today tab's badge, which counts what the
    /// tab *lists* — so revealing completed tasks raises the badge but not this,
    /// because finishing something shouldn't make the app look busier.
    var todayOutstanding: Int {
        tasks.filter { task in
            guard matchesFilters(task), !task.isComplete else { return false }
            let group = DueGroup.group(for: task)
            return group == .today || group == .overdue
        }.count
    }

    /// Whether this tab's badge should be drawn *and computed*. Skipping the
    /// count is the point — hiding a number you already calculated saves nothing.
    func showsBadge(for tab: TaskTab) -> Bool {
        settings.showsBadge(forTabID: tab.id)
    }

    func badge(for tab: TaskTab) -> Int {
        switch tab {
        case .all:     return allTabCount
        case .today:   return todayTabCount
        case .overdue:   return overdueTasks.count
        case .noDueDate: return undatedTasks.count
        case .completed: return completedTasks.count
        case .category(let name): return tasks(inCategory: name).count
        case .noCategory: return uncategorizedTasks.count
        }
    }

    /// Incomplete tasks with no due date, whether or not they're currently listed.
    /// Surfaced in the UI so "Don't show" never means "silently lost".
    var undatedCount: Int {
        tasks.filter { $0.dueDate == nil && !$0.isComplete }.count
    }

    /// The same count narrowed to one category, for the per-category tabs. A
    /// banner reading the global figure on a category tab would point at tasks
    /// that aren't in it.
    /// Undated *and* untagged, for the hidden-tasks banner on the No Category tab.
    var undatedUncategorizedCount: Int {
        tasks.filter { $0.dueDate == nil && !$0.isComplete && $0.categories.isEmpty }.count
    }

    func undatedCount(inCategory name: String) -> Int {
        tasks.filter { $0.dueDate == nil && !$0.isComplete && $0.categories.contains(name) }.count
    }

    var overdueCount: Int {
        tasks.filter { !$0.isComplete && $0.isOverdue() }.count
    }

    /// Categories actually in use, for the filter menu. Showing all 25 when only
    /// six are used is noise.
    /// Categories offered in the filter list and the hamburger.
    ///
    /// Uses `categoryEarnsPill`, the same test the tab bar uses, so a category
    /// leaves both places at the same moment. It previously counted any task
    /// carrying the name, completed or not — which meant finishing the last task
    /// in a category dropped its pill while leaving it in the filter list, and
    /// the two screens contradicted each other.
    ///
    /// Filtering to a category holding only completed tasks is what the
    /// Completed tab is for, and is still reachable by switching on completed
    /// tasks for that category, which restores its pill too.
    var categoriesInUse: [TPCategory] {
        let used = Set(tasks.flatMap(\.categories))
        let resolver = self.resolver
        let known = orderedCategories.filter { categoryEarnsPill($0.name) }
        // Orphans — on tasks but absent from the list — have no position, so
        // they follow the ordered ones alphabetically. Held to the same test.
        let orphans = used
            .subtracting(orderedCategories.map(\.name))
            .filter { categoryEarnsPill($0) }
            .sorted()
            .map(resolver.resolve)
        return known + orphans
    }
}

// MARK: - Tabs

public enum TaskTab: Hashable, Identifiable, Sendable {
    case all, today, overdue, noDueDate, completed
    /// Keyed by category name rather than an index, so a rename carries the tab
    /// with it and a delete takes it away — no separate identity to keep in sync.
    case category(String)
    /// Tasks carrying no category at all. A case rather than a reserved category
    /// name, so it can't collide with anything a user creates.
    case noCategory

    public var id: String {
        switch self {
        case .all:       return "all"
        case .today:     return "today"
        case .overdue:   return "overdue"
        case .noDueDate: return "noDueDate"
        case .completed: return "completed"
        case .category(let name): return "cat:\(name)"
        case .noCategory: return "nocat"
        }
    }

    public var title: String {
        switch self {
        case .all:       return "All Tasks"
        case .today:     return "Today"
        case .overdue:   return "Overdue"
        case .noDueDate: return "No Due Date"
        case .completed: return "Completed"
        case .category(let name): return name
        case .noCategory: return "No Category"
        }
    }

    public var categoryName: String? {
        if case .category(let name) = self { return name }
        return nil
    }

    static let fixed: [TaskTab] = [.all, .today, .overdue, .noDueDate, .completed]
}

// MARK: - Due date grouping

/// How the list is sectioned.
///
/// Today and Tomorrow get named sections because that is how people think about
/// them. Everything further out gets its own dated section — one per calendar day,
/// so the list reads as a schedule rather than a pile.
///
/// Overdue stays a single group rather than splitting by past day. Anything late
/// needs attention now; *which* day it slipped is detail the row already carries.
public enum DueGroup: Hashable, Sendable {
    case overdue
    case today
    case tomorrow
    /// A specific future day, normalized to midnight so grouping is stable.
    case day(Date)
    /// Horizon grouping only: what's left of this week after today and tomorrow.
    /// Carries the week's end so it sorts with the weeks that follow.
    case restOfWeek(Date)
    /// Horizon grouping only: one whole Sunday–Saturday week, keyed by its start.
    case week(Date)
    /// Horizon grouping only: the tail of the month the weekly sections end in.
    /// Named "Rest of September" — calling it "September" would be a lie when
    /// most of it sits in the sections above.
    case restOfMonth(Date)
    /// Horizon grouping only: one whole month, keyed by its first day.
    case month(Date)
    case noDate
    case completed
    /// The single body section of an ungrouped tab. Not produced by
    /// `group(for:)` — only by the sectioning helpers, where everything not
    /// overdue and not undated goes into one list.
    case allTasks
    /// A section headed by a category name, when grouping by category.
    case categoryNamed(String)
    /// Completed tasks Exchange returned without a completion date.
    case noCompletionDate
    /// A section headed by an assignee's name.
    case assignedTo(String)
    /// Tasks with nobody in Assigned To.
    case unassigned

    public static func group(for task: TPTask, now: Date = Date(), calendar: Calendar = .current) -> DueGroup {
        if task.isComplete { return .completed }
        guard let due = task.dueDate else { return .noDate }
        if calendar.isDateInToday(due) { return .today }
        if calendar.isDateInTomorrow(due) { return .tomorrow }
        if due < now { return .overdue }
        return .day(calendar.startOfDay(for: due))
    }

    /// Which horizon section a task belongs in.
    ///
    /// Overdue, Today and Tomorrow are decided exactly as `group(for:)` decides
    /// them, so the first three sections behave identically under both
    /// groupings. Everything past tomorrow coarsens: what's left of this week,
    /// then four whole Sunday–Saturday weeks, then whole months.
    ///
    /// Weeks start *after* the current one rather than four weeks from today, so
    /// the headings are stable calendar blocks that don't rename themselves each
    /// morning.
    static func horizonGroup(for task: TPTask,
                             now: Date = Date(),
                             calendar: Calendar = .current) -> DueGroup {
        if task.isComplete { return .completed }
        guard let due = task.dueDate else { return .noDate }
        if calendar.isDateInToday(due) { return .today }
        if calendar.isDateInTomorrow(due) { return .tomorrow }
        if due < now { return .overdue }

        let dueDay = calendar.startOfDay(for: due)
        // `dateInterval` respects the locale's first weekday; the spec is
        // Sunday–Saturday, which is what a US calendar gives.
        guard let thisWeek = calendar.dateInterval(of: .weekOfYear, for: now) else {
            return .day(dueDay)
        }

        /* Tomorrow can fall in *next* week — on a Saturday it does — so the
           carve-out has to come before the week test, or Sunday's tasks would
           land in Tomorrow and in the first weekly section both. Anything left
           inside this week's interval is "Rest of This Week", which is
           legitimately empty on a Saturday and on a Friday with nothing due
           Saturday. An empty section simply isn't built. */
        if dueDay < thisWeek.end {
            return .restOfWeek(calendar.startOfDay(for: thisWeek.end))
        }

        // Four whole weeks after the current one.
        guard let firstWeekStart = calendar.date(byAdding: .day, value: 7,
                                                 to: thisWeek.start) else {
            return .day(dueDay)
        }
        for index in 0..<4 {
            guard let start = calendar.date(byAdding: .day, value: index * 7,
                                            to: firstWeekStart),
                  let end = calendar.date(byAdding: .day, value: 7, to: start)
            else { break }
            if dueDay >= start && dueDay < end { return .week(start) }
        }

        // Past the weeks: whole months, except the first, which is only the tail
        // of whatever month the weekly sections ended in.
        guard let weeksEnd = calendar.date(byAdding: .day, value: 28, to: firstWeekStart),
              let monthOfEnd = calendar.dateInterval(of: .month, for: weeksEnd)
        else { return .day(dueDay) }

        if dueDay < monthOfEnd.end { return .restOfMonth(monthOfEnd.start) }
        return .month(calendar.dateInterval(of: .month, for: dueDay)?.start
                      ?? calendar.startOfDay(for: dueDay))
    }

    public var title: String {
        switch self {
        case .overdue:   return "Overdue"
        case .today:     return "Today"
        case .tomorrow:  return "Tomorrow"
        case .day(let date): return DueGroup.headerFormatter.string(from: date)
        case .restOfWeek: return "Rest of This Week"
        case .week(let start): return DueGroup.weekTitle(start)
        case .restOfMonth(let start): return "Rest of " + DueGroup.monthFormatter.string(from: start)
        case .month(let start): return DueGroup.monthFormatter.string(from: start)
        case .noDate:    return "No Due Date"
        case .completed: return "Completed"
        case .allTasks:  return "Tasks"
        case .categoryNamed(let name): return name
        case .noCompletionDate: return "No Completion Date"
        case .assignedTo(let name): return name
        case .unassigned: return "Unassigned"
        }
    }

    /// Abbreviated weekday, full month, day, year — "Thu, August 13, 2026".
    ///
    /// Built from a template rather than a literal format string so the field
    /// *order* follows the device locale. A UK phone gets "Thu, 13 August 2026"
    /// from the same code.
    /// "Aug 23–29", or "Aug 30 – Sep 5" when a week straddles two months.
    /// Compact enough for the small uppercase heading; "Week of Aug 23" is
    /// friendlier but noticeably wider.
    static func weekTitle(_ start: Date, calendar: Calendar = .current) -> String {
        let end = calendar.date(byAdding: .day, value: 6, to: start) ?? start
        let startText = dayMonthFormatter.string(from: start)
        let sameMonth = calendar.isDate(start, equalTo: end, toGranularity: .month)
        let endText = sameMonth
            ? dayOnlyFormatter.string(from: end)
            : dayMonthFormatter.string(from: end)
        return sameMonth ? "\(startText)–\(endText)" : "\(startText) – \(endText)"
    }

    private static let dayMonthFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.setLocalizedDateFormatFromTemplate("MMM d")
        return formatter
    }()

    private static let dayOnlyFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.setLocalizedDateFormatFromTemplate("d")
        return formatter
    }()

    private static let monthFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.setLocalizedDateFormatFromTemplate("MMMM yyyy")
        return formatter
    }()

    private static let headerFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.setLocalizedDateFormatFromTemplate("EEE MMMM d yyyy")
        return formatter
    }()

    /// Overdue first, then today, tomorrow, each dated day in order,
    /// then undated, then completed.
    ///
    /// `undatedFirst` lifts No Due Date above everything — the ranks below start
    /// at 1 precisely so 0 stays free for it.
    func sortKey(undatedFirst: Bool = false) -> (Int, Date) {
        switch self {
        case .noDate:    return (undatedFirst ? 0 : 5, .distantFuture)
        case .overdue:   return (1, .distantPast)
        case .today:     return (2, .distantPast)
        case .tomorrow:  return (3, .distantPast)
        case .day(let date): return (4, date)
        // Rank 4 with the days, ordered by date — the horizon sections form one
        // ascending run, so nothing special is needed to interleave them.
        case .restOfWeek(let end): return (4, end)
        case .week(let start): return (4, start)
        case .restOfMonth(let start): return (4, start)
        case .month(let start): return (4, start)
        case .allTasks:  return (4, .distantPast)
        // Category sections keep the order the caller built them in, so they all
        // share a rank and the stable sort preserves it.
        case .categoryNamed: return (4, .distantPast)
        // Bottom, like undated tasks elsewhere.
        case .noCompletionDate: return (7, .distantFuture)
        // Ordered by name in `assignedSections`, not by this key.
        case .assignedTo: return (3, .distantPast)
        case .unassigned: return (6, .distantFuture)
        case .completed: return (6, .distantFuture)
        }
    }

    /// True for sections that should carry the overdue accent.
    public var isUrgent: Bool { self == .overdue }
}

public struct DueSection: Identifiable {
    public let group: DueGroup
    public let tasks: [TPTask]
    /// Set by the Overdue tab, where dated sections all describe late work and
    /// should carry the red the single Overdue heading carries elsewhere.
    public let forcesUrgent: Bool

    public var id: DueGroup { group }
    public var isUrgent: Bool { forcesUrgent || group.isUrgent }

    public init(group: DueGroup, tasks: [TPTask], forcesUrgent: Bool = false) {
        self.group = group
        self.tasks = tasks
        self.forcesUrgent = forcesUrgent
    }

    /// A–Z by subject. The Overdue tab sorts this way inside each day, since
    /// everything in a section shares a due date and nothing else ranks them.
    static func alphabetical(_ a: TPTask, _ b: TPTask) -> Bool {
        a.subject.localizedCaseInsensitiveCompare(b.subject) == .orderedAscending
    }

    /// Newest completion first. Tasks finished without a stamped completion date
    /// — which happens when they're closed elsewhere — sort to the bottom rather
    /// than pretending to be ancient.
    static func recentlyCompleted(_ a: TPTask, _ b: TPTask) -> Bool {
        switch (a.completeDate, b.completeDate) {
        case let (x?, y?) where x != y: return x > y
        case (nil, _?): return false
        case (_?, nil): return true
        default: return alphabetical(a, b)
        }
    }

    /// Oldest due date first, then A–Z. The ordering for every group in every
    /// tab. Importance deliberately doesn't rank here — the row already flags it,
    /// and letting it jump tasks around made scanning unpredictable.
    static func dueThenAlphabetical(_ a: TPTask, _ b: TPTask) -> Bool {
        switch (a.dueDate, b.dueDate) {
        case let (x?, y?) where x != y: return x < y
        case (nil, _?): return false
        case (_?, nil): return true
        default: return alphabetical(a, b)
        }
    }
}
