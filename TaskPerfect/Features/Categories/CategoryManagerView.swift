import SwiftUI

/// Add, rename, recolor and delete the mailbox's master categories.
///
/// These edits reach desktop Outlook — the list lives in the mailbox, not on the
/// device. That's why every destructive step names how many tasks it touches.
public struct CategoryManagerView: View {

    @Environment(TaskStore.self) private var store
    @Environment(\.dismiss) private var dismiss

    @State private var editing: TPCategory?
    @State private var isAdding = false
    @State private var pendingDeletion: TPCategory?

    public init() {}

    public var body: some View {
        List {
            Section {
                ForEach(store.orderedCategories) { category in
                    Button {
                        editing = category
                    } label: {
                        row(for: category)
                    }
                    .buttonStyle(.plain)
                    .swipeActions(edge: .trailing) {
                        Button(role: .destructive) {
                            pendingDeletion = category
                        } label: {
                            Label("Delete", systemImage: "trash")
                        }
                    }
                }
                .onMove { source, destination in
                    store.moveCategories(fromOffsets: source, toOffset: destination)
                }
            } header: {
                // Note above its own rows, as on the other category-length
                // screens. Applied per section here rather than hoisting every
                // note to the top of the screen, so no note travels away from
                // what it explains.
                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Text("Your categories")
                        // Names the orphans section without moving it. Below
                        // thirty rows that section is invisible; a count says
                        // it's there without competing for the top of the screen.
                        if !orphans.isEmpty {
                            Text("· \(orphans.count) unlisted")
                                .foregroundStyle(Theme.Palette.slate)
                        }
                        Spacer()
                        EditButton().font(.caption)
                    }
                    Text("Drag the handles to reorder. Name and color changes appear in Outlook on your computer too; the order is kept on this device.")
                        .textCase(nil)
                        .font(.footnote)
                        .foregroundStyle(Theme.Palette.slate)
                    // Top copy of the bulk action, mirroring All on / All off
                    // elsewhere. The button alone — the note above already
                    // covers the list, and repeating it would crowd the header.
                    // No Reset button here, deliberately. Bulk *toggles* get
                    // mirrored to the top for reachability; a destructive reset
                    // doesn't. It discards a hand-built order with no undo, and
                    // this spot sits in the path of a thumb reaching for the
                    // list rather than somewhere you arrive on purpose.
                }
            }

            Section {
                Button {
                    withAnimation { store.resetCategoryOrder() }
                } label: {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Reset to alphabetical order")
                        Text("This reorders the category tabs too.")
                            .font(.caption2)
                            .foregroundStyle(Theme.Palette.slate)
                    }
                }
            }

            if !orphans.isEmpty {
                Section {
                    ForEach(orphans, id: \.self) { name in
                        Button {
                            isAdding = true
                            draftName = name
                        } label: {
                            HStack {
                                Circle()
                                    .strokeBorder(Theme.Palette.hairline, lineWidth: 1)
                                    .frame(width: 12, height: 12)
                                Text(name)
                                Spacer()
                                Text("\(store.taskCount(forCategory: name)) task\(store.taskCount(forCategory: name) == 1 ? "" : "s")")
                                    .font(Theme.numeric(13))
                                    .foregroundStyle(Theme.Palette.slate)
                            }
                        }
                        .buttonStyle(.plain)
                    }
                } header: {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Used but not in your list")
                        Text("These names are on tasks but have no color assigned. Tap one to add it to your list.")
                            .textCase(nil)
                            .font(.footnote)
                            .foregroundStyle(Theme.Palette.slate)
                    }
                }
            }
        }
        .navigationTitle("Categories")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    draftName = ""
                    isAdding = true
                } label: {
                    Image(systemName: "plus")
                }
            }
        }
        .sheet(item: $editing) { category in
            NavigationStack {
                CategoryEditorView(category: category)
            }
        }
        .sheet(isPresented: $isAdding) {
            NavigationStack {
                CategoryEditorView(category: nil, initialName: draftName)
            }
        }
        .confirmationDialog(
            "Delete this category?",
            isPresented: Binding(
                get: { pendingDeletion != nil },
                set: { if !$0 { pendingDeletion = nil } }
            ),
            titleVisibility: .visible,
            presenting: pendingDeletion
        ) { target in
            Button("Delete Category", role: .destructive) {
                pendingDeletion = nil
                Task { await store.deleteCategory(target) }
            }
            let count = store.taskCount(forCategory: pendingDeletion?.name ?? "")
            if count > 0 {
                Button("Delete and Remove from \(count) Task\(count == 1 ? "" : "s")", role: .destructive) {
                    pendingDeletion = nil
                    Task { await store.deleteCategory(target, removingFromTasks: true) }
                }
            }
            Button("Cancel", role: .cancel) { pendingDeletion = nil }
        } message: { target in
            let count = store.taskCount(forCategory: target.name)
            Text(count == 0
                 ? "\"\(target.name)\" isn't used by any task."
                 : "\(count) task\(count == 1 ? "" : "s") use \"\(target.name)\". They'll keep the label but lose its color unless you remove it from them too.")
        }
    }

    @State private var draftName = ""

    private func row(for category: TPCategory) -> some View {
        HStack(spacing: 12) {
            Circle()
                .fill(category.hasColor ? category.color : Color.clear)
                .overlay(Circle().strokeBorder(Theme.Palette.hairline, lineWidth: category.hasColor ? 0 : 1))
                .frame(width: 16, height: 16)
            VStack(alignment: .leading, spacing: 2) {
                let style = store.settings.textStyle(for: category.name) ?? .standard
                Text(category.name)
                    .font(style.font)
                    .italic(style.isItalic)
                    .foregroundStyle(style.textColor)
                if !style.isDefault {
                    Text(style.summary)
                        .font(.caption2)
                        .foregroundStyle(Theme.Palette.slate)
                }
            }
            Spacer()
            let count = store.taskCount(forCategory: category.name)
            if count > 0 {
                Text("\(count)")
                    .font(Theme.numeric(13))
                    .foregroundStyle(Theme.Palette.slate)
            }
            Image(systemName: "chevron.right")
                .font(.caption2)
                .foregroundStyle(Theme.Palette.slate)
        }
    }

    /// Names on tasks with no master-list entry.
    private var orphans: [String] {
        let known = Set(store.categories.map(\.name))
        return Array(Set(store.tasks.flatMap(\.categories)).subtracting(known)).sorted()
    }
}

#Preview {
    let store = TaskStore(backend: MockBackend(latency: .zero), settings: AppSettings(),
        reachability: Reachability()
    )
    NavigationStack { CategoryManagerView() }
        .environment(store)
        .task { await store.load() }
}
