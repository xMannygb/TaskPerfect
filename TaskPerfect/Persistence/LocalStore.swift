import Foundation
import SwiftData

/// On-disk store. Everything the UI reads comes from here, so the app opens with
/// a full task list whether or not there's a connection.
@ModelActor
public actor LocalStore {

    // MARK: Tasks

    public func allTasks() throws -> [TPTask] {
        try modelContext.fetch(FetchDescriptor<CachedTask>()).map(\.asTask)
    }

    public func upsert(_ tasks: [TPTask]) throws {
        let existing = try modelContext.fetch(FetchDescriptor<CachedTask>())
        var byLocalID = Dictionary(existing.map { ($0.localID, $0) }, uniquingKeysWith: { a, _ in a })
        // Server rows arrive keyed by itemID; the local row may predate it.
        var byItemID = Dictionary(
            existing.filter { !$0.itemID.isEmpty }.map { ($0.itemID, $0) },
            uniquingKeysWith: { a, _ in a }
        )

        for task in tasks {
            if let row = byLocalID[task.localID] ?? (task.itemID.isEmpty ? nil : byItemID[task.itemID]) {
                // Never let a server copy overwrite an edit that hasn't been
                // pushed — the queue still owes the mailbox that change.
                guard !row.isDirty else { continue }
                row.apply(task)
            } else {
                let row = CachedTask(from: task)
                modelContext.insert(row)
                byLocalID[row.localID] = row
                if !row.itemID.isEmpty { byItemID[row.itemID] = row }
            }
        }
        try modelContext.save()
    }

    public func save(_ task: TPTask) throws {
        let id = task.localID
        let descriptor = FetchDescriptor<CachedTask>(predicate: #Predicate { $0.localID == id })
        if let row = try modelContext.fetch(descriptor).first {
            row.apply(task)
        } else {
            modelContext.insert(CachedTask(from: task))
        }
        try modelContext.save()
    }

    public func task(localID: UUID) throws -> TPTask? {
        let descriptor = FetchDescriptor<CachedTask>(predicate: #Predicate { $0.localID == localID })
        return try modelContext.fetch(descriptor).first?.asTask
    }

    public func delete(localID: UUID) throws {
        let descriptor = FetchDescriptor<CachedTask>(predicate: #Predicate { $0.localID == localID })
        for row in try modelContext.fetch(descriptor) { modelContext.delete(row) }
        try modelContext.save()
    }

    public func deleteTasks(itemIDs: [String]) throws {
        guard !itemIDs.isEmpty else { return }
        let wanted = Set(itemIDs)
        for row in try modelContext.fetch(FetchDescriptor<CachedTask>()) where wanted.contains(row.itemID) {
            modelContext.delete(row)
        }
        try modelContext.save()
    }

    public func clearTasks() throws {
        for row in try modelContext.fetch(FetchDescriptor<CachedTask>()) { modelContext.delete(row) }
        try modelContext.save()
    }

    // MARK: Categories

    public func allCategories() throws -> [TPCategory] {
        let descriptor = FetchDescriptor<CachedCategory>(sortBy: [SortDescriptor(\.sortIndex)])
        return try modelContext.fetch(descriptor).map(\.asCategory)
    }

    public func replaceCategories(_ categories: [TPCategory]) throws {
        for row in try modelContext.fetch(FetchDescriptor<CachedCategory>()) { modelContext.delete(row) }
        for (index, category) in categories.enumerated() {
            modelContext.insert(CachedCategory(from: category, sortIndex: index))
        }
        try modelContext.save()
    }

    // MARK: Sync state

    public func syncToken(folderID: String) throws -> SyncToken? {
        let descriptor = FetchDescriptor<CachedSyncState>(predicate: #Predicate { $0.folderID == folderID })
        return try modelContext.fetch(descriptor).first.map { SyncToken(rawValue: $0.token) }
    }

    public func setSyncToken(_ token: SyncToken, folderID: String, syncedAt: Date?) throws {
        let descriptor = FetchDescriptor<CachedSyncState>(predicate: #Predicate { $0.folderID == folderID })
        if let row = try modelContext.fetch(descriptor).first {
            row.token = token.rawValue
            row.lastSynced = syncedAt
        } else {
            modelContext.insert(CachedSyncState(folderID: folderID, token: token.rawValue, lastSynced: syncedAt))
        }
        try modelContext.save()
    }

    public func lastSynced() throws -> Date? {
        try modelContext.fetch(FetchDescriptor<CachedSyncState>())
            .compactMap(\.lastSynced)
            .max()
    }

    // MARK: Pending changes

    /// Queued changes as value snapshots.
    ///
    /// Deliberately not `[PendingChange]`: those are `@Model` references owned by
    /// this actor's `ModelContext`, and reading their properties from the main
    /// actor is both a Swift 6 error and a real data race. Callers get copies and
    /// come back here by `id` to mutate.
    public func pendingChanges() throws -> [QueuedChange] {
        try modelContext.fetch(
            FetchDescriptor<PendingChange>(sortBy: [SortDescriptor(\.queuedAt)])
        ).map(\.snapshot)
    }

    public func pendingCount() throws -> Int {
        try modelContext.fetchCount(FetchDescriptor<PendingChange>())
    }

    /// Add a change, collapsing it against anything already queued for the task.
    ///
    /// Without this the queue grows without bound — checking a task off and on
    /// ten times would send twenty requests describing one final state.
    public func enqueue(
        _ operation: PendingChange.Operation,
        taskLocalID: UUID,
        itemID: String = "",
        changeKey: String = ""
    ) throws {
        let existing = try modelContext.fetch(
            FetchDescriptor<PendingChange>(predicate: #Predicate { $0.taskLocalID == taskLocalID })
        )

        switch operation {
        case .delete:
            let hadCreate = existing.contains { $0.operation == .create }
            for row in existing { modelContext.delete(row) }
            // Created and deleted before either reached the server: as far as
            // Exchange is concerned the task never existed, so send nothing.
            if !hadCreate {
                modelContext.insert(PendingChange(
                    operation: .delete, taskLocalID: taskLocalID,
                    itemID: itemID, changeKey: changeKey
                ))
            }

        case .update:
            // A queued create already covers it — the payload is read fresh at
            // send time, so the newer edit rides along. A queued update likewise.
            guard !existing.contains(where: { $0.operation == .create || $0.operation == .update })
            else { break }
            modelContext.insert(PendingChange(
                operation: .update, taskLocalID: taskLocalID,
                itemID: itemID, changeKey: changeKey
            ))

        case .create:
            guard existing.isEmpty else { break }
            modelContext.insert(PendingChange(operation: .create, taskLocalID: taskLocalID))
        }
        try modelContext.save()
    }

    public func remove(changeID: UUID) throws {
        let descriptor = FetchDescriptor<PendingChange>(predicate: #Predicate { $0.id == changeID })
        for row in try modelContext.fetch(descriptor) { modelContext.delete(row) }
        try modelContext.save()
    }

    public func recordFailure(changeID: UUID, message: String) throws {
        let descriptor = FetchDescriptor<PendingChange>(predicate: #Predicate { $0.id == changeID })
        guard let row = try modelContext.fetch(descriptor).first else { return }
        row.recordFailure(message)
        if row.isExhausted { modelContext.delete(row) }
        try modelContext.save()
    }
}
