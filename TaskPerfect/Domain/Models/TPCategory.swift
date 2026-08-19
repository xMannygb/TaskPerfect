import Foundation

/// An Outlook master category.
///
/// Task items carry category *names* only. The color definitions live in a hidden
/// folder-associated item named `CategoryList`, stored in the **Calendar** folder —
/// not the Tasks folder. Fetch it with EWS `GetUserConfiguration`.
public struct TPCategory: Identifiable, Hashable, Codable, Sendable {

    /// The display name. This is the join key — it is what appears on a task.
    public var name: String

    /// Outlook color index, 0...24. Maps into `OutlookCategoryPalette`.
    /// -1 means "no color assigned" (Outlook shows these as clear/none).
    public var colorIndex: Int

    /// GUID from the CategoryList blob. Preserve it on write-back or Outlook
    /// desktop may treat the category as newly created.
    public var guid: String?

    /// Ctrl+F2..F12 shortcut slot, 0 = none. Round-tripped, not used on iOS.
    public var keyboardShortcut: Int

    public var id: String { name }

    public init(
        name: String,
        colorIndex: Int = -1,
        guid: String? = nil,
        keyboardShortcut: Int = 0
    ) {
        self.name = name
        self.colorIndex = colorIndex
        self.guid = guid
        self.keyboardShortcut = keyboardShortcut
    }

    public var hasColor: Bool { (0...24).contains(colorIndex) }
}

// MARK: - Resolution

/// Resolves category names found on tasks against the mailbox's master list.
///
/// A task can legitimately reference a category that is not in the master list —
/// it happens when a category is deleted while tasks still carry the name.
/// Do not drop those; render them uncolored.
public struct TPCategoryResolver: Sendable {

    private let byName: [String: TPCategory]

    public init(master: [TPCategory]) {
        self.byName = Dictionary(
            master.map { ($0.name.lowercased(), $0) },
            uniquingKeysWith: { first, _ in first }
        )
    }

    public func resolve(_ name: String) -> TPCategory {
        byName[name.lowercased()] ?? TPCategory(name: name, colorIndex: -1)
    }

    public func resolve(all names: [String]) -> [TPCategory] {
        names.map(resolve)
    }

    /// Names on tasks with no matching master-list entry.
    /// Surfacing these lets you offer "add to category list" in the UI.
    public func orphans(in names: [String]) -> [String] {
        names.filter { byName[$0.lowercased()] == nil }
    }
}
