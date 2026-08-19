import SwiftUI

/// How much each tab's rows show.
///
/// Per tab rather than one global switch, because density is a per-list
/// preference: a category pill you scan for what's next wants subjects only,
/// while All Tasks may still want the full picture.
///
/// Modeled on `BadgeSettingsView`, which already solves the ordering problem —
/// the category rows come from `orderedCategories`, so they follow the manual
/// order set in Categories management, a rename carries the row with it, and a
/// new category appears here on its own.
public struct TaskDetailsView: View {

    @Environment(TaskStore.self) private var store

    public init() {}

    /// Every configurable tab, not just the ones currently earning a pill — a
    /// setting screen that hides rows when a category empties would look like
    /// it had lost them.
    ///
    /// Completed is absent on purpose. See the footer.
    private var tabs: [TaskTab] {
        [.all, .today, .overdue, .noDueDate, .noCategory]
            + store.orderedCategories.map { TaskTab.category($0.name) }
    }

    public var body: some View {
        List {
            Section {
                // Top and bottom, matching the badge screen — this list grows
                // with every category, so a single copy at either end is out of
                // reach from the other.
                bulkRow
                ForEach(tabs) { tab in
                    Toggle(isOn: Binding(
                        get: { store.settings.hidesDetails(forTabID: tab.id) },
                        set: { store.settings.setHidesDetails($0, forTabID: tab.id) }
                    )) {
                        Text(tab.title)
                    }
                    .accessibilityLabel("Hide task details in \(tab.title)")
                }
                bulkRow
            } header: {
                // Above the rows, not below them. The note explains what the
                // whole screen does, and with a dozen categories listed a footer
                // sits well below the fold — read, if at all, only after the
                // screen has already been used.
                VStack(alignment: .leading, spacing: 6) {
                    Text("Hide task details")
                    Text("With details hidden, a row shows the subject, its category colors and the due date. Reminders, repeats, assignees, \"Waiting\", completion dates and progress bars are only in the task itself.")
                    Text("The Completed tab isn't listed — its rows always show the completion date.")
                }
                .textCase(nil)
                .font(.footnote)
                .foregroundStyle(Theme.Palette.slate)
            }
        }
        .navigationTitle("Task details in lists")
        .navigationBarTitleDisplayMode(.inline)
    }

    /// Both spelled out rather than one button that flips. With a few tabs
    /// switched and the rest not — the normal state — a single label is wrong
    /// for half the screen whichever way it reads.
    private var bulkRow: some View {
        HStack {
            Button("Hide in all tabs") {
                store.settings.hideDetailsEverywhere(tabIDs: tabs.map(\.id))
            }
            Spacer(minLength: 0)
            Button("Show in all tabs") {
                store.settings.showDetailsEverywhere()
            }
        }
        .font(.footnote)
        .buttonStyle(.borderless)
    }
}

#Preview {
    NavigationStack { TaskDetailsView() }
        .environment(TaskStore(backend: MockBackend(latency: .zero), settings: AppSettings()))
}
