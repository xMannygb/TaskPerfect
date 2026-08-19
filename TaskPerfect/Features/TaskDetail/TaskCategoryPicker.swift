import SwiftUI

/// Every category, for picking on a task.
///
/// The task sheet shows six; this is what "Click for more categories" opens.
/// Six was chosen because the list grows with every category added and the
/// sheet has a lot else to show — but the cap creates a trap, which the sheet
/// avoids by promoting ticked categories into its visible six. Set one here and
/// it stays reachable there.
struct TaskCategoryPicker: View {

    @Environment(TaskStore.self) private var store
    @Environment(\.dismiss) private var dismiss

    @Binding var selected: [String]

    var body: some View {
        List {
            Section {
                ForEach(store.orderedCategories) { category in
                    Button {
                        toggle(category.name)
                    } label: {
                        HStack {
                            CategoryChip(category: category)
                            Spacer()
                            if selected.contains(category.name) {
                                Image(systemName: "checkmark")
                                    .foregroundStyle(Theme.Palette.ink)
                            }
                        }
                    }
                    .buttonStyle(.plain)
                }
            } header: {
                // Above the rows: this list is as long as the category list, so
                // a footer explains it only after it's been scrolled past.
                Text("In the order set in Categories Development & Controls. A task can carry several; the first one decides where it files when the list is grouped by category. Use up to two, and only when needed.")
                    .textCase(nil)
                    .font(.footnote)
                    .foregroundStyle(Theme.Palette.slate)
            }
        }
        .navigationTitle("Categories")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("Done") { dismiss() }.fontWeight(.semibold)
            }
        }
    }

    private func toggle(_ name: String) {
        if let index = selected.firstIndex(of: name) {
            selected.remove(at: index)
        } else {
            // Appended, not inserted: the first category decides where a task
            // files under category grouping, and reordering it silently would
            // move the task to a different section.
            selected.append(name)
        }
    }
}
