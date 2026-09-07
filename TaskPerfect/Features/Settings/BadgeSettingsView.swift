import SwiftUI

/// Which tabs show a count, and which stay visible when empty.
///
/// Both are per-tab visibility settings, so they share a screen rather than
/// splitting into two that would list every tab twice. Two columns keeps each
/// tab on one row; the headers carry the meaning, since a bare pair of switches
/// wouldn't say which is which.
public struct BadgeSettingsView: View {

    @Environment(TaskStore.self) private var store

    public init() {}

    private var tabs: [TaskTab] { store.availableTabs }

    public var body: some View {
        List {
            Section {
                header
                // Above the rows and below them. On a twenty-category list a
                // reset should be in reach from either end, and the copy under
                // the headers inherits their alignment — no labels needed to say
                // which column each pair applies to.
                bulkRow
                ForEach(tabs) { tab in
                    row(for: tab)
                }
                bulkRow
            } header: {
                // Above the rows for the same reason as the task-details screen:
                // this list grows with every category, so a footer sits below the
                // fold and is read, if at all, only after the screen has been used.
                VStack(alignment: .leading, spacing: 6) {
                    Text("**Badge count** puts the number of tasks in a tab on its pill. Switch it off and the pill shows the name alone, this can reduce processing time.")
                    Text("**Always show** keeps a tab in the bar even when it holds nothing — All Tasks, Today and Completed are always there regardless.")
                    Text("New categories start with their count showing and their tab hiding when empty.")
                }
                .textCase(nil)
                .font(.footnote)
                .foregroundStyle(Theme.Palette.slate)
            }

        }
        .navigationTitle("Tab Badge & Visibility Controls")
        .navigationBarTitleDisplayMode(.inline)
    }

    /// Directly beneath the column each pair controls, rather than as separately
    /// labelled rows — the alignment says what they apply to. Stacked, because
    /// two buttons side by side won't fit the column width.
    private var bulkRow: some View {
        HStack(spacing: 12) {
            Spacer(minLength: 0)
            VStack(spacing: 4) {
                Button("All on") { store.settings.showAllBadges() }
                Button("All off") { store.settings.hideAllBadges(tabIDs: tabs.map(\.id)) }
            }
            .frame(width: 62)
            VStack(spacing: 4) {
                Button("All on") { store.settings.pinAllTabs(tabs.map(\.id)) }
                Button("All off") { store.settings.unpinAllTabs() }
            }
            .frame(width: 62)
        }
        .font(.footnote)
        .buttonStyle(.borderless)
    }

    private var header: some View {
        HStack(spacing: 12) {
            Spacer(minLength: 0)
            Text("Badge\ncount")
                .multilineTextAlignment(.center)
                .frame(width: 62)
            Text("Always\nshow")
                .multilineTextAlignment(.center)
                .frame(width: 62)
        }
        .font(.caption2)
        .foregroundStyle(Theme.Palette.slate)
        .listRowBackground(Color.clear)
    }

    private func row(for tab: TaskTab) -> some View {
        let showsBadge = store.settings.showsBadge(forTabID: tab.id)
        let canToggle = store.settings.canToggleVisibility(tabID: tab.id)

        return HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 1) {
                Text(tab.title)
                // Only for tabs already showing a count — computing it for a
                // hidden one would undo the saving the toggle exists to produce.
                if showsBadge {
                    Text("\(store.badge(for: tab))")
                        .font(Theme.numeric(11))
                        .foregroundStyle(Theme.Palette.slate)
                }
            }
            Spacer(minLength: 0)

            Toggle("", isOn: Binding(
                get: { showsBadge },
                set: { store.settings.setBadgeVisible($0, forTabID: tab.id) }
            ))
            .labelsHidden()
            .frame(width: 62)
            .accessibilityLabel("\(tab.title) badge count")

            Toggle("", isOn: Binding(
                get: { store.settings.isAlwaysShown(tabID: tab.id) },
                set: { store.settings.setAlwaysShown($0, tabID: tab.id) }
            ))
            .labelsHidden()
            // Shown but disabled rather than hidden: an absent control raises
            // "where did it go", a disabled one answers itself.
            .disabled(!canToggle)
            .frame(width: 62)
            .accessibilityLabel("\(tab.title) always show")
            .accessibilityHint(canToggle ? "" : "This tab is always visible")
        }
    }
}

#Preview {
    let store = TaskStore(backend: MockBackend(latency: .zero), settings: AppSettings(),
        reachability: Reachability()
    )
    NavigationStack { BadgeSettingsView() }
        .environment(store)
        .task { await store.load() }
}
