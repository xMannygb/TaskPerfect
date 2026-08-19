import SwiftUI

/// The full category filter list.
///
/// Its own screen because the hamburger shows only the first five: at thirty or
/// forty categories that menu becomes a scroll, and a filter you have to scroll
/// to find is barely faster than opening Settings.
public struct CategoryFilterView: View {

    @Environment(TaskStore.self) private var store
    @Environment(\.dismiss) private var dismiss

    public init() {}

    public var body: some View {
        List {
            // Top copy, mirroring the bulk controls on the other category-length
            // screens: with thirty categories the button at the foot is out of
            // reach from where you're working. Only shown when a filter is
            // active, so it costs nothing on the common path.
            if !store.selectedCategories.isEmpty {
                Section {
                    Button("Clear filter") { store.selectedCategories.removeAll() }
                }
            }

            Section {
                ForEach(store.categoriesInUse) { category in
                    Button {
                        toggle(category.name)
                    } label: {
                        HStack {
                            Circle()
                                .fill(category.hasColor ? category.color : Color.clear)
                                .overlay(
                                    Circle().strokeBorder(
                                        category.hasColor ? .clear : Theme.Palette.hairline,
                                        lineWidth: 1
                                    )
                                )
                                .frame(width: 10, height: 10)
                            Text(category.name)
                                .foregroundStyle(Theme.Palette.ink)
                            // Present on tasks but absent from the master list.
                            // Easy to forget when moving this screen, because
                            // they only appear with certain data.
                            if !store.categories.contains(where: { $0.name == category.name }) {
                                Text("not in list")
                                    .font(.caption2)
                                    .foregroundStyle(Theme.Palette.slate)
                            }
                            Spacer()
                            if store.selectedCategories.contains(category.name) {
                                Image(systemName: "checkmark")
                                    .foregroundStyle(Theme.Palette.ink)
                            }
                        }
                    }
                }
            } header: {
                // Above the rows: this list is as long as the category list, so
                // a footer sits below the fold and explains the screen only
                // after it's been used.
                Text("Ticked categories are the only ones shown in the task list. Categories marked \"not in list\" appear on tasks but aren't in your category list — add them in Categories Development & Controls.")
                    .textCase(nil)
                    .font(.footnote)
                    .foregroundStyle(Theme.Palette.slate)
            }

            // Bottom copy. Both are the same button calling the same method —
            // no state either one holds, so nothing to keep in sync.
            if !store.selectedCategories.isEmpty {
                Section {
                    Button("Clear filter") { store.selectedCategories.removeAll() }
                }
            }
        }
        .navigationTitle("Filter By Category")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("Done") { dismiss() }.fontWeight(.semibold)
            }
        }
    }

    private func toggle(_ name: String) {
        if store.selectedCategories.contains(name) {
            store.selectedCategories.remove(name)
        } else {
            store.selectedCategories.insert(name)
        }
    }
}
