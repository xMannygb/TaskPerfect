import Foundation

// MARK: - Task Status

/// Mirrors the EWS `TaskStatus` element exactly.
/// Raw values are the strings Exchange expects on the wire — do not localize them.
public enum TPTaskStatus: String, CaseIterable, Codable, Sendable {
    case notStarted       = "NotStarted"
    case inProgress       = "InProgress"
    case completed        = "Completed"
    case waitingOnOthers  = "WaitingOnOthers"
    case deferred         = "Deferred"

    public var displayName: String {
        switch self {
        case .notStarted:      return "Not Started"
        case .inProgress:      return "In Progress"
        case .completed:       return "Completed"
        case .waitingOnOthers: return "Waiting on Someone Else"
        case .deferred:        return "Deferred"
        }
    }
}

// MARK: - Importance

public enum TPImportance: String, CaseIterable, Codable, Sendable, Comparable {
    case low    = "Low"
    case normal = "Normal"
    case high   = "High"

    private var rank: Int {
        switch self {
        case .low: return 0
        case .normal: return 1
        case .high: return 2
        }
    }

    public static func < (lhs: TPImportance, rhs: TPImportance) -> Bool {
        lhs.rank < rhs.rank
    }
}

// MARK: - Sensitivity

public enum TPSensitivity: String, CaseIterable, Codable, Sendable {
    case normal       = "Normal"
    case personal     = "Personal"
    case `private`    = "Private"
    case confidential = "Confidential"
}

// MARK: - Body

public struct TPBody: Hashable, Codable, Sendable {
    public var content: String
    public var isHTML: Bool

    public init(content: String = "", isHTML: Bool = false) {
        self.content = content
        self.isHTML = isHTML
    }

    public static let empty = TPBody()

    /// EWS `BodyType` attribute value.
    public var ewsBodyType: String { isHTML ? "HTML" : "Text" }

    /// The words without the markup.
    ///
    /// Used anywhere the text matters rather than its formatting — search, row
    /// previews, character counts. Without it, searching for "li" would match
    /// every bulleted note.
    public var plainText: String {
        guard isHTML else { return content }
        var text = content
        // A nested list opens before its parent `<li>` closes, so break the line
        // first or the sub-item runs on to the end of the one above it.
        text = text.replacingOccurrences(of: "<(ul|ol)[^>]*>", with: "\n",
                                         options: [.regularExpression, .caseInsensitive])
        text = text.replacingOccurrences(of: "<li[^>]*>", with: "• ",
                                         options: [.regularExpression, .caseInsensitive])
        text = text.replacingOccurrences(of: "</(p|div|li|h[1-6]|ul|ol)>", with: "\n",
                                         options: [.regularExpression, .caseInsensitive])
        text = text.replacingOccurrences(of: "<br\\s*/?>", with: "\n",
                                         options: [.regularExpression, .caseInsensitive])
        text = text.replacingOccurrences(of: "<[^>]+>", with: "",
                                         options: .regularExpression)
        // Decode last. Outlook emits plenty of &ndash;, &rsquo; and friends that
        // would otherwise show as literal text.
        for (entity, replacement) in [
            ("&nbsp;", " "), ("&ndash;", "—"), ("&mdash;", "—"),
            ("&lsquo;", "'"), ("&rsquo;", "'"), ("&#39;", "'"),
            ("&ldquo;", "\""), ("&rdquo;", "\""), ("&quot;", "\""),
            ("&lt;", "<"), ("&gt;", ">"), ("&amp;", "&")
        ] {
            text = text.replacingOccurrences(of: entity, with: replacement,
                                             options: .caseInsensitive)
        }
        text = text.replacingOccurrences(of: "\n{3,}", with: "\n\n",
                                         options: .regularExpression)
        return text.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Turn a plain body into HTML. Lossless — nothing is discarded.
    public func convertedToHTML() -> TPBody {
        guard !isHTML else { return self }
        let escaped = content
            .replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
        guard !escaped.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return TPBody(content: "", isHTML: true)
        }
        let paragraphs = escaped.components(separatedBy: "\n\n")
            .map { "<p>" + $0.replacingOccurrences(of: "\n", with: "<br>") + "</p>" }
        return TPBody(content: paragraphs.joined(), isHTML: true)
    }

    /// Flatten an HTML body to plain text.
    ///
    /// **Lossy** — colors, fonts, bullets and numbering are discarded, not
    /// hidden. Confirm before calling.
    public func convertedToPlainText() -> TPBody {
        guard isHTML else { return self }
        return TPBody(content: plainText, isHTML: false)
    }
}

// MARK: - Task

/// The full Outlook task item.
///
/// This is a value type on purpose: sync compares snapshots, and immutability
/// makes conflict resolution far easier to reason about.
///
/// ⚠️ Nothing in this file may import or reference EWS/SOAP types.
public struct TPTask: Identifiable, Hashable, Codable, Sendable {

    // Identity
    /// Stable local identity. Survives before the item has ever reached the server.
    public var localID: UUID
    /// EWS `ItemId`. Empty until the first successful `CreateItem`.
    public var itemID: String
    /// EWS `ChangeKey`. The optimistic-concurrency token — send it on update.
    public var changeKey: String
    /// EWS `ParentFolderId` of the containing Tasks folder.
    public var folderID: String

    public var id: UUID { localID }

    // Content
    public var subject: String
    public var body: TPBody
    public var categories: [String]
    public var importance: TPImportance
    public var sensitivity: TPSensitivity

    // Scheduling
    public var startDate: Date?
    public var dueDate: Date?
    public var reminderDueBy: Date?
    public var reminderIsSet: Bool

    // Progress
    public private(set) var status: TPTaskStatus
    public private(set) var percentComplete: Double   // 0...100
    public private(set) var completeDate: Date?

    // Effort tracking — EWS exposes all of these; Graph's To Do API does not.
    public var totalWork: Int?          // minutes
    public var actualWork: Int?         // minutes
    public var mileage: String?
    public var billingInformation: String?
    public var companies: [String]
    public var owner: String?

    public var recurrence: TPRecurrence?

    // Local sync bookkeeping
    public var lastModified: Date?
    /// Set when edited locally and not yet pushed. Drives `ChangeQueue`.
    public var isDirty: Bool

    public init(
        localID: UUID = UUID(),
        itemID: String = "",
        changeKey: String = "",
        folderID: String = "",
        subject: String = "",
        body: TPBody = .empty,
        categories: [String] = [],
        importance: TPImportance = .normal,
        sensitivity: TPSensitivity = .normal,
        startDate: Date? = nil,
        dueDate: Date? = nil,
        reminderDueBy: Date? = nil,
        reminderIsSet: Bool = false,
        status: TPTaskStatus = .notStarted,
        percentComplete: Double = 0,
        completeDate: Date? = nil,
        totalWork: Int? = nil,
        actualWork: Int? = nil,
        mileage: String? = nil,
        billingInformation: String? = nil,
        companies: [String] = [],
        owner: String? = nil,
        recurrence: TPRecurrence? = nil,
        lastModified: Date? = nil,
        isDirty: Bool = false
    ) {
        self.localID = localID
        self.itemID = itemID
        self.changeKey = changeKey
        self.folderID = folderID
        self.subject = subject
        self.body = body
        self.categories = categories
        self.importance = importance
        self.sensitivity = sensitivity
        self.startDate = startDate
        self.dueDate = dueDate
        self.reminderDueBy = reminderDueBy
        self.reminderIsSet = reminderIsSet
        self.status = status
        self.percentComplete = percentComplete.clamped(to: 0...100)
        self.completeDate = completeDate
        self.totalWork = totalWork
        self.actualWork = actualWork
        self.mileage = mileage
        self.billingInformation = billingInformation
        self.companies = companies
        self.owner = owner
        self.recurrence = recurrence
        self.lastModified = lastModified
        self.isDirty = isDirty
    }
}

// MARK: - Status / PercentComplete coupling

public extension TPTask {

    /// Exchange links Status, PercentComplete and CompleteDate server-side.
    /// Mirror that coupling locally or the UI will visibly flicker after each sync.
    ///
    /// Rules Exchange enforces:
    ///   - Status = Completed  →  PercentComplete = 100, CompleteDate stamped
    ///   - Status ≠ Completed  →  CompleteDate cleared
    ///   - PercentComplete = 100 → Status becomes Completed
    ///   - PercentComplete = 0   → Status becomes NotStarted (if it was InProgress)
    mutating func setStatus(_ newStatus: TPTaskStatus, now: Date = Date()) {
        status = newStatus
        switch newStatus {
        case .completed:
            percentComplete = 100
            if completeDate == nil { completeDate = now }
        case .notStarted:
            percentComplete = 0
            completeDate = nil
        case .inProgress, .waitingOnOthers, .deferred:
            if percentComplete >= 100 { percentComplete = 99 }
            completeDate = nil
        }
        markDirty(now: now)
    }

    mutating func setPercentComplete(_ value: Double, now: Date = Date()) {
        percentComplete = value.clamped(to: 0...100)
        if percentComplete >= 100 {
            status = .completed
            if completeDate == nil { completeDate = now }
        } else if percentComplete == 0, status == .inProgress {
            status = .notStarted
            completeDate = nil
        } else if status == .completed {
            status = .inProgress
            completeDate = nil
        }
        markDirty(now: now)
    }

    mutating func toggleComplete(now: Date = Date()) {
        setStatus(status == .completed ? .notStarted : .completed, now: now)
    }

    mutating func markDirty(now: Date = Date()) {
        isDirty = true
        lastModified = now
    }
}

// MARK: - Derived state

public extension TPTask {

    var isComplete: Bool { status == .completed }

    /// True only for incomplete tasks whose due date is in the past.
    func isOverdue(reference: Date = Date()) -> Bool {
        guard !isComplete, let due = dueDate else { return false }
        return due < reference
    }

    /// Has the item ever been persisted to Exchange?
    var existsOnServer: Bool { !itemID.isEmpty }

    var hasReminder: Bool { reminderIsSet && reminderDueBy != nil }

    /// Per-task emphasis, overriding the category's own bold and italic.
    ///
    /// Three states each, not two. `nil` means "follow the category", which is
    /// what makes the override work in both directions: a task in a bold
    /// category can be set explicitly non-bold, and a plain `Bool` couldn't
    /// express that — it would default to `false` and quietly un-bold every task
    /// in a bold category.
    ///
    /// Colors, fonts and sizes are deliberately not overridable. Emphasis sits
    /// *within* a category's style; a different color or typeface would make a
    /// task look like it belongs somewhere else, which is the one thing the
    /// category styling exists to communicate.
    struct Emphasis: Equatable, Sendable {
        var bold: Bool?
        var italic: Bool?
        /// A size delta, not a flag — so it carries a value rather than three
        /// states. `nil` still means "follow the category".
        var sizeDelta: Int?

        var isEmpty: Bool { bold == nil && italic == nil && sizeDelta == nil }

        /// The marker written into `mileage` so Outlook's conditional
        /// formatting has something to test. Read with *contains*, not
        /// *equals*, so "TP:bold,italic" satisfies a bold rule and an italic
        /// rule independently.
        static let markerPrefix = "TP:"

        var marker: String? {
            var parts: [String] = []
            if bold == true { parts.append("bold") }
            if italic == true { parts.append("italic") }
            // An explicit "off" needs saying, or a bold category would still
            // fire the Outlook rule for a task set non-bold.
            if bold == false { parts.append("nobold") }
            if italic == false { parts.append("noitalic") }
            // Signed, so "size+0" is meaningful: it means "explicitly at the
            // category's own size", distinct from having no override at all.
            if let delta = sizeDelta {
                parts.append("size\(delta >= 0 ? "+" : "")\(delta)")
            }
            guard !parts.isEmpty else { return nil }
            return Emphasis.markerPrefix + parts.joined(separator: ",")
        }

        static func parse(marker: String) -> Emphasis {
            var e = Emphasis()
            let body = marker.dropFirst(markerPrefix.count).lowercased()
            let parts = body.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }
            if parts.contains("nobold") { e.bold = false }
            else if parts.contains("bold") { e.bold = true }
            if parts.contains("noitalic") { e.italic = false }
            else if parts.contains("italic") { e.italic = true }
            if let token = parts.first(where: { $0.hasPrefix("size") }),
               let value = Int(token.dropFirst(4)) {
                e.sizeDelta = value
            }
            return e
        }
    }

    /// Reads the emphasis marker out of `mileage`, ignoring anything else in
    /// there — someone's actual mileage note has to survive.
    var emphasis: Emphasis {
        guard let raw = mileage else { return Emphasis() }
        for token in raw.components(separatedBy: ";") {
            let trimmed = token.trimmingCharacters(in: .whitespaces)
            if trimmed.hasPrefix(Emphasis.markerPrefix) {
                return Emphasis.parse(marker: trimmed)
            }
        }
        return Emphasis()
    }

    /// Whatever is in `mileage` that isn't ours — shown and edited as Mileage.
    var mileageText: String {
        guard let raw = mileage else { return "" }
        return raw.components(separatedBy: ";")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.hasPrefix(Emphasis.markerPrefix) && !$0.isEmpty }
            .joined(separator: "; ")
    }

    /// Writes both back into the one field, preserving the other.
    ///
    /// Mileage is a field anyone can edit in Outlook, so the app has to assume
    /// something it doesn't own may already be in there.
    mutating func setMileage(text: String? = nil, emphasis newEmphasis: Emphasis? = nil) {
        let keptText = text ?? mileageText
        let keptEmphasis = newEmphasis ?? emphasis
        var parts: [String] = []
        let trimmedText = keptText.trimmingCharacters(in: .whitespaces)
        if !trimmedText.isEmpty { parts.append(trimmedText) }
        if let marker = keptEmphasis.marker { parts.append(marker) }
        mileage = parts.isEmpty ? nil : parts.joined(separator: "; ")
    }

    /// The name a task files under when grouped or sorted by Assigned To: its
    /// **first** assignee, matching the first-category rule. A task with two
    /// names appears once, not twice.
    ///
    /// Empty when unassigned, which sinks it to the bottom in both directions.
    var assignee: String { companies.first ?? "" }

    var estimatedHours: Double? {
        guard let totalWork else { return nil }
        return Double(totalWork) / 60.0
    }
}

// MARK: - Utilities

extension Comparable {
    func clamped(to range: ClosedRange<Self>) -> Self {
        min(max(self, range.lowerBound), range.upperBound)
    }
}
