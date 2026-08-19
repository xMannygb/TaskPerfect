import Foundation

/// Opaque incremental-sync cursor.
///
/// Backed by the EWS `SyncFolderItems` SyncState string today. Wrapping it means the
/// sync engine never learns which protocol produced it — which is what lets you swap
/// backends later without touching `SyncEngine`.
public struct SyncToken: Hashable, Codable, Sendable {
    public let rawValue: String

    public init(rawValue: String) {
        self.rawValue = rawValue
    }
}

/// One round of incremental changes for a single folder.
public struct TaskDelta: Sendable {
    public var upserted: [TPTask]
    public var deletedItemIDs: [String]
    public var nextToken: SyncToken

    /// Server reported the previous token unusable. Clear local state for this
    /// folder before applying. Treat as a normal path — it happens routinely.
    public var isFullResync: Bool

    /// EWS returns changes in pages. When false, call again immediately with
    /// `nextToken` before considering the folder in sync.
    public var includesLastItemInRange: Bool

    public init(
        upserted: [TPTask] = [],
        deletedItemIDs: [String] = [],
        nextToken: SyncToken,
        isFullResync: Bool = false,
        includesLastItemInRange: Bool = true
    ) {
        self.upserted = upserted
        self.deletedItemIDs = deletedItemIDs
        self.nextToken = nextToken
        self.isFullResync = isFullResync
        self.includesLastItemInRange = includesLastItemInRange
    }

    public var isEmpty: Bool { upserted.isEmpty && deletedItemIDs.isEmpty }
}
