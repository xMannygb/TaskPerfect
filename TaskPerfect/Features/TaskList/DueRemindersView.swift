import SwiftUI

/// Reminders that came due while the app was closed.
///
/// Reached from the banner on the task list, never presented automatically. A
/// modal on every launch would be the same four reminders most mornings, and a
/// prompt you learn to dismiss unread is worse than no prompt — so the banner
/// waits to be tapped and the list stays out of the way until then.
///
/// **Dismissal is local to this launch.** Exchange stores one reminder per task
/// and Outlook keeps its own dismissal state; clearing `reminderIsSet` from here
/// would remove the reminder everywhere, which isn't what "Dismiss" means on a
/// phone. Changing a reminder for good is the task editor's job, and the row
/// opens straight into it.
struct DueRemindersView: View {

    @Environment(TaskStore.self) private var store
    @Environment(\.dismiss) private var dismiss

    /// Opens the task itself. The caller closes this sheet first, since two
    /// stacked sheets on a phone leave no obvious way back.
    let open: (TPTask) -> Void

    var body: some View {
        List {
            Section {
                ForEach(store.dueReminders) { task in
                    Button {
                        open(task)
                    } label: {
                        VStack(alignment: .leading, spacing: 3) {
                            Text(task.subject.isEmpty ? "Untitled task" : task.subject)
                                .font(.body)
                                .foregroundStyle(Theme.Palette.ink)
                            if let due = task.reminderDueBy {
                                Text(Self.relative(due))
                                    .font(.caption)
                                    .foregroundStyle(Theme.Palette.overdue)
                            }
                            if !task.categories.isEmpty {
                                Text(task.categories.joined(separator: ", "))
                                    .font(.caption2)
                                    .foregroundStyle(Theme.Palette.slate)
                            }
                        }
                    }
                    .swipeActions(edge: .trailing) {
                        Button("Dismiss") { store.dismissReminder(task.itemID) }
                            .tint(Theme.Palette.slate)
                    }
                }
            } footer: {
                Text("Dismissing clears a reminder on this iPhone only. The reminder stays on the task, and in Outlook.")
            }
        }
        .navigationTitle("Reminders due")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                // Clears the lot without touching the tasks. The banner is gone
                // for this launch either way — that's what `handled` means.
                Button("Dismiss all") {
                    store.dismissAllReminders()
                    store.remindersBannerHandled = true
                    dismiss()
                }
            }
            ToolbarItem(placement: .confirmationAction) {
                Button("Done") {
                    store.remindersBannerHandled = true
                    dismiss()
                }
            }
        }
    }

    /// "2 hours ago", "yesterday" — how late the reminder is, which is the thing
    /// worth knowing. The exact time is on the task itself.
    private static func relative(_ date: Date) -> String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .full
        return "Reminder \(formatter.localizedString(for: date, relativeTo: Date()))"
    }
}
