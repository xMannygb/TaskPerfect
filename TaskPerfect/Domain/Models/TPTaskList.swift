import Foundation

/// An Exchange folder containing task items.
///
/// Most mailboxes have exactly one — the distinguished `tasks` folder. Users can
/// create additional task folders in desktop Outlook, so do not assume a single list.
public struct TPTaskList: Identifiable, Hashable, Codable, Sendable {

    /// EWS `FolderId`.
    public var folderID: String
    public var changeKey: String
    public var displayName: String

    /// True for the mailbox's default Tasks folder (`DistinguishedFolderId Id="tasks"`).
    public var isDefault: Bool

    public var totalCount: Int
    public var unreadCount: Int

    public var id: String { folderID }

    public init(
        folderID: String,
        changeKey: String = "",
        displayName: String,
        isDefault: Bool = false,
        totalCount: Int = 0,
        unreadCount: Int = 0
    ) {
        self.folderID = folderID
        self.changeKey = changeKey
        self.displayName = displayName
        self.isDefault = isDefault
        self.totalCount = totalCount
        self.unreadCount = unreadCount
    }
}
