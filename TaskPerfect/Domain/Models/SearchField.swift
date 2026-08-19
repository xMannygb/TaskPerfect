import Foundation

/// The fields the search bar can look in, in the order they appear in Settings.
///
/// Deliberately excluded, with reasons, so they don't get added later by
/// accident:
///
/// - **Dates.** Nobody types a date the way it's stored, and "August" matching a
///   due date but not a note mentioning August is worse than not matching at
///   all. Date ranges already exist and are the right tool.
/// - **Recurrence.** "Every 2 weeks" is generated text, not something anyone
///   wrote, so matching it is guesswork about phrasing. Sorting Options has
///   *Recurring Tasks* for gathering them.
/// - **Percent complete and effort.** Numbers. Typing "50" to find half-finished
///   work would collide with every note containing 50.
public enum SearchField: String, CaseIterable, Identifiable, Sendable {
    case subject
    case notes
    case categories
    case assignedTo
    case status
    case highPriority

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .subject:    return "Task subject line"
        case .notes:      return "Task notes"
        case .categories: return "Categories"
        case .assignedTo: return "Assigned To"
        case .status:     return "Status"
        case .highPriority: return "High priority tasks"
        }
    }

    /// Shown beneath the row. Says what typing actually finds, since several of
    /// these are non-obvious.
    public var detail: String {
        switch self {
        case .subject:
            return "The task's title."
        case .notes:
            return "The words in the notes. Formatting is ignored, so \"li\" doesn't match every bulleted list."
        case .categories:
            return "Category names on a task, including ones not in your list."
        case .assignedTo:
            return "The names in the task's Companies field."
        case .status:
            return "Not Started, In Progress, Waiting on Someone Else, Deferred, Completed."
        case .highPriority:
            // Only High. Low and Normal are the states nobody sets on purpose —
            // Normal is the default, so matching it would return most of the
            // list, and neither is a thing anyone searches for.
            return "Type \"high\" to find tasks marked High. Low and Normal aren't matched."
        }
    }

    /// On for a fresh install: today's behavior, split in two.
    public static let defaults: Set<String> = [
        SearchField.subject.rawValue, SearchField.notes.rawValue
    ]
}
