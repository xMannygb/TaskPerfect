import SwiftUI

public struct TaskRowView: View {

    let task: TPTask
    let categories: [TPCategory]
    let subjectLineLimit: Int
    let textStyle: CategoryTextStyle
    let shadesOverdue: Bool
    let shadesUndated: Bool
    /// Subject, category colors and due date only. Everything else moves into
    /// the task itself. Set per tab in Settings → Appearance.
    let hidesDetails: Bool
    let onToggle: () -> Void

    public init(
        task: TPTask,
        categories: [TPCategory],
        subjectLineLimit: Int = 2,
        textStyle: CategoryTextStyle = .standard,
        shadesOverdue: Bool = true,
        shadesUndated: Bool = true,
        hidesDetails: Bool = false,
        onToggle: @escaping () -> Void
    ) {
        self.task = task
        self.categories = categories
        self.subjectLineLimit = subjectLineLimit
        self.textStyle = textStyle
        self.shadesOverdue = shadesOverdue
        self.shadesUndated = shadesUndated
        self.hidesDetails = hidesDetails
        self.onToggle = onToggle
    }

    public var body: some View {
        HStack(alignment: .top, spacing: Theme.Metrics.rowSpacing) {

            CategorySpine(categories: categories)

            Button(action: onToggle) {
                Image(systemName: task.isComplete ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 22, weight: .light))
                    .foregroundStyle(task.isComplete ? Theme.Palette.ink : Theme.Palette.slate)
                    .contentTransition(.symbolEffect(.replace))
                    // Pinned width: the filled and hollow glyphs are not
                    // guaranteed to measure the same, and any difference would
                    // shift the subject when a task is completed.
                    .frame(width: 24, alignment: .center)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(task.isComplete ? "Mark not started" : "Mark complete")

            VStack(alignment: .leading, spacing: 4) {
                // No leading glyphs here. Anything placed before the subject
                // shifts its left edge, and rows stop sharing a margin — status
                // markers belong in the trailing gutter instead.
                Text(task.subject)
                    .font(subjectFont)
                    // Per-task override wins; nil falls back to the category.
                    .italic(task.emphasis.italic ?? textStyle.isItalic)
                    .foregroundStyle(subjectColor)
                    .strikethrough(task.isComplete, color: Theme.Palette.slate)
                    .lineLimit(subjectLineLimit)

                if !metadata.isEmpty || !categories.isEmpty {
                    HStack(spacing: 8) {
                        ForEach(metadata, id: \.text) { item in
                            HStack(spacing: 3) {
                                if let symbol = item.symbol {
                                    Image(systemName: symbol).font(.system(size: 10))
                                }
                                Text(item.text).font(Theme.numeric(12))
                            }
                            .foregroundStyle(item.tint)
                        }

                        // Each name in its own category's color. Separated by a
                        // neutral dot so two adjacent names don't read as one.
                        ForEach(Array(categories.enumerated()), id: \.offset) { index, category in
                            HStack(spacing: 8) {
                                if index > 0 || !metadata.isEmpty {
                                    Text("·")
                                        .font(.system(size: 12))
                                        .foregroundStyle(Theme.Palette.hairline)
                                }
                                Text(category.name)
                                    .font(.system(size: 12, weight: category.hasColor ? .medium : .regular))
                                    .foregroundStyle(category.labelColor)
                            }
                        }
                    }
                }

                // Bottom-right of the row. Shown for any completed task that
                // carries a stamp, not only inside the Completed tab — a row in
                // the All Tasks completed section answers the same question.
                // One line carrying both. The assignee left, the completion
                // stamp right, so they grow toward each other rather than into
                // each other. The meta line above already runs to ~50
                // characters on a third of rows, so a name there would wrap it.
                if !hidesDetails,
                   !task.assignee.isEmpty || (task.isComplete && task.completeDate != nil) {
                    HStack(alignment: .firstTextBaseline, spacing: 10) {
                        if !task.assignee.isEmpty {
                            Label {
                                Text(task.companies.count > 1
                                     ? "\(task.assignee) +\(task.companies.count - 1)"
                                     : task.assignee)
                                    .lineLimit(1)
                                    .truncationMode(.tail)
                            } icon: {
                                Image(systemName: "person")
                            }
                            // Slate with a small figure, so a name doesn't read
                            // as another category — they sit inches apart and
                            // would otherwise look alike.
                            .font(.system(size: 11))
                            .foregroundStyle(Theme.Palette.slate)
                            .accessibilityLabel("Assigned to \(task.companies.joined(separator: ", "))")
                        }
                        Spacer(minLength: 0)
                        if task.isComplete, let completed = task.completeDate {
                            Text("Completed \(TaskRowView.format(completed))")
                                .font(Theme.numeric(11))
                                .foregroundStyle(Theme.Palette.slate)
                                .fixedSize()
                        }
                    }
                    .padding(.top, 2)
                }

                if !hidesDetails, task.percentComplete > 0, !task.isComplete {
                    ProgressView(value: task.percentComplete, total: 100)
                        .progressViewStyle(.linear)
                        .tint(Theme.Palette.ink)
                        .frame(maxWidth: 120)
                        .padding(.top, 2)
                }
            }

            Spacer(minLength: 0)

            VStack(alignment: .trailing, spacing: 4) {
                if task.importance == .high {
                    Image(systemName: "exclamationmark")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundStyle(Theme.Palette.flag)
                        .accessibilityLabel("High importance")
                }
                if task.isDirty {
                    // Not yet pushed. Quiet, not alarming — it resolves on its own.
                    Image(systemName: "arrow.triangle.2.circlepath")
                        .font(.system(size: 11))
                        .foregroundStyle(Theme.Palette.slate)
                        .accessibilityLabel("Waiting to sync")
                }
            }
            .padding(.top, 2)
        }
        .padding(.vertical, 8)
        .listRowBackground(rowBackground)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
        .accessibilityLabel(accessibilityDescription)
    }

    // MARK: Subject appearance
    //
    // Precedence, strongest first: completed → overdue → category style.
    // State beats decoration — a task should read as finished, or as late,
    // before it reads as belonging to something.

    private var isLate: Bool { task.isOverdue() }

    /// Overdue wins where a row could be both. It can't here — an undated task is
    /// never overdue — but the precedence is stated rather than implied.
    private var rowBackground: Color {
        if isLate { return shadesOverdue ? Theme.Palette.overdueWash : Theme.Palette.paper }
        if task.dueDate == nil, !task.isComplete {
            return shadesUndated ? Theme.Palette.undatedWash : Theme.Palette.paper
        }
        return Theme.Palette.paper
    }

    /// Overdue forces bold but keeps the category's size and design, so a row
    /// doesn't change shape as it crosses its due date — only its weight and
    /// color. Italic is left alone for the same reason.
    private var subjectFont: Font {
        textStyle.font(forcingBold: isLate, emphasis: task.emphasis)
    }

    private var subjectColor: Color {
        if task.isComplete { return Theme.Palette.slate }
        if isLate { return Theme.Palette.overdue }
        return textStyle.textColor
    }

    // MARK: Metadata line

    private struct MetaItem {
        let symbol: String?
        let text: String
        let tint: Color
    }

    /// With details hidden this is the due date alone — kept because it's the
    /// field people navigate by, and the only one that turns red when late.
    /// The bell, the repeat summary and "Waiting" all drop.
    private var metadata: [MetaItem] {
        var items: [MetaItem] = []

        if let due = task.dueDate {
            let overdue = task.isOverdue()
            items.append(MetaItem(
                symbol: overdue ? "exclamationmark.circle" : "calendar",
                text: Self.format(due),
                tint: overdue ? Theme.Palette.overdue : Theme.Palette.slate
            ))
        }

        if hidesDetails { return items }

        if task.hasReminder {
            items.append(MetaItem(symbol: "bell", text: "", tint: Theme.Palette.slate))
        }

        if let recurrence = task.recurrence {
            // Show what it repeats, not just that it repeats. "Weekly · Mon" costs
            // the same row space as a bare icon and answers the actual question.
            items.append(MetaItem(
                symbol: "repeat",
                text: recurrence.shortSummary,
                tint: Theme.Palette.slate
            ))
        }

        if task.status == .waitingOnOthers {
            items.append(MetaItem(symbol: nil, text: "Waiting", tint: Theme.Palette.slate))
        }

        // Category names are rendered separately, each in its own color.
        return items
    }

    /// Abbreviated weekday, full month, day, year — "Thu, August 20, 2026".
    ///
    /// Always the explicit date, never "Today" or "Tomorrow". The section heading
    /// already says which day it is; repeating it on the row wastes the line, and
    /// in the Overdue tab a relative label would be actively unhelpful.
    ///
    /// Built from a template so field *order* follows the device locale, matching
    /// how the section headings are formatted.
    private static let rowDateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.setLocalizedDateFormatFromTemplate("EEE MMMM d yyyy")
        return formatter
    }()

    static func format(_ date: Date) -> String {
        rowDateFormatter.string(from: date)
    }

    private var accessibilityDescription: String {
        var parts: [String] = [task.subject]
        if task.isComplete { parts.append("completed") }
        if task.isOverdue() { parts.append("overdue") }
        if let due = task.dueDate { parts.append("due \(Self.format(due))") }
        if task.importance == .high { parts.append("high importance") }
        if let recurrence = task.recurrence {
            parts.append("repeats \(recurrence.summary)")
        }
        if !task.categories.isEmpty {
            parts.append("categories: \(task.categories.joined(separator: ", "))")
        }
        return parts.joined(separator: ", ")
    }
}
