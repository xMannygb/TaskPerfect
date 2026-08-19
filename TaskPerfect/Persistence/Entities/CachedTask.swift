import Foundation
import SwiftData

/// A task as stored on disk.
///
/// Deliberately a flat mirror of `TPTask` rather than a graph of relationships:
/// tasks arrive from Exchange as independent items, and a flat row maps to a
/// delta upsert without a fetch-merge dance on every sync.
@Model
public final class CachedTask {

    /// Stable across the item's life, including before it reaches the server.
    @Attribute(.unique) public var localID: UUID

    public var itemID: String
    public var changeKey: String
    public var folderID: String

    public var subject: String
    public var bodyContent: String
    public var bodyIsHTML: Bool
    public var categories: [String]
    public var importanceRaw: String
    public var sensitivityRaw: String

    public var startDate: Date?
    public var dueDate: Date?
    public var reminderDueBy: Date?
    public var reminderIsSet: Bool

    public var statusRaw: String
    public var percentComplete: Double
    public var completeDate: Date?

    public var totalWork: Int?
    public var actualWork: Int?
    public var mileage: String?
    public var billingInformation: String?
    public var companies: [String]
    public var owner: String?

    /// Recurrence as JSON. It's a nested enum with associated values — modelling
    /// it as SwiftData entities would mean a half-dozen tables for something
    /// that's only ever read and written whole.
    public var recurrenceData: Data?

    public var lastModified: Date?
    public var isDirty: Bool

    public init(from task: TPTask) {
        self.localID = task.localID
        self.itemID = task.itemID
        self.changeKey = task.changeKey
        self.folderID = task.folderID
        self.subject = task.subject
        self.bodyContent = task.body.content
        self.bodyIsHTML = task.body.isHTML
        self.categories = task.categories
        self.importanceRaw = task.importance.rawValue
        self.sensitivityRaw = task.sensitivity.rawValue
        self.startDate = task.startDate
        self.dueDate = task.dueDate
        self.reminderDueBy = task.reminderDueBy
        self.reminderIsSet = task.reminderIsSet
        self.statusRaw = task.status.rawValue
        self.percentComplete = task.percentComplete
        self.completeDate = task.completeDate
        self.totalWork = task.totalWork
        self.actualWork = task.actualWork
        self.mileage = task.mileage
        self.billingInformation = task.billingInformation
        self.companies = task.companies
        self.owner = task.owner
        self.recurrenceData = task.recurrence.flatMap { try? JSONEncoder().encode($0) }
        self.lastModified = task.lastModified
        self.isDirty = task.isDirty
    }

    public func apply(_ task: TPTask) {
        itemID = task.itemID
        changeKey = task.changeKey
        folderID = task.folderID
        subject = task.subject
        bodyContent = task.body.content
        bodyIsHTML = task.body.isHTML
        categories = task.categories
        importanceRaw = task.importance.rawValue
        sensitivityRaw = task.sensitivity.rawValue
        startDate = task.startDate
        dueDate = task.dueDate
        reminderDueBy = task.reminderDueBy
        reminderIsSet = task.reminderIsSet
        statusRaw = task.status.rawValue
        percentComplete = task.percentComplete
        completeDate = task.completeDate
        totalWork = task.totalWork
        actualWork = task.actualWork
        mileage = task.mileage
        billingInformation = task.billingInformation
        companies = task.companies
        owner = task.owner
        recurrenceData = task.recurrence.flatMap { try? JSONEncoder().encode($0) }
        lastModified = task.lastModified
        isDirty = task.isDirty
    }

    public var asTask: TPTask {
        TPTask(
            localID: localID,
            itemID: itemID,
            changeKey: changeKey,
            folderID: folderID,
            subject: subject,
            body: TPBody(content: bodyContent, isHTML: bodyIsHTML),
            categories: categories,
            importance: TPImportance(rawValue: importanceRaw) ?? .normal,
            sensitivity: TPSensitivity(rawValue: sensitivityRaw) ?? .normal,
            startDate: startDate,
            dueDate: dueDate,
            reminderDueBy: reminderDueBy,
            reminderIsSet: reminderIsSet,
            status: TPTaskStatus(rawValue: statusRaw) ?? .notStarted,
            percentComplete: percentComplete,
            completeDate: completeDate,
            totalWork: totalWork,
            actualWork: actualWork,
            mileage: mileage,
            billingInformation: billingInformation,
            companies: companies,
            owner: owner,
            recurrence: recurrenceData.flatMap { try? JSONDecoder().decode(TPRecurrence.self, from: $0) },
            lastModified: lastModified,
            isDirty: isDirty
        )
    }
}

/// The mailbox's category list, cached so colors survive a cold offline launch.
@Model
public final class CachedCategory {
    @Attribute(.unique) public var name: String
    public var colorIndex: Int
    public var guid: String?
    public var keyboardShortcut: Int
    /// Position in the mailbox's own ordering, so the cache round-trips.
    public var sortIndex: Int

    public init(from category: TPCategory, sortIndex: Int) {
        self.name = category.name
        self.colorIndex = category.colorIndex
        self.guid = category.guid
        self.keyboardShortcut = category.keyboardShortcut
        self.sortIndex = sortIndex
    }

    public var asCategory: TPCategory {
        TPCategory(name: name, colorIndex: colorIndex, guid: guid, keyboardShortcut: keyboardShortcut)
    }
}

/// Per-folder sync cursor. Persisted, so a relaunch resumes the delta stream
/// instead of pulling the whole mailbox again.
@Model
public final class CachedSyncState {
    @Attribute(.unique) public var folderID: String
    public var token: String
    public var lastSynced: Date?

    public init(folderID: String, token: String, lastSynced: Date? = nil) {
        self.folderID = folderID
        self.token = token
        self.lastSynced = lastSynced
    }
}
