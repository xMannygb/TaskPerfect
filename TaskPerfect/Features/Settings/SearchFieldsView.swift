import SwiftUI

/// Which fields the search bar looks in.
///
/// Global and sticky: the same scope applies in every tab and persists until
/// changed here. That's the point — a narrow configuration follows you around,
/// which is why the note says so rather than leaving it implicit.
///
/// **The last field on can't be switched off.** Its row disables while it's
/// alone, and unlocks the moment another is ticked, so no particular field is
/// ever stuck — you simply can't reach zero. The alternative, allowing zero and
/// letting search return nothing, fails silently and far from the cause: you'd
/// meet it later, in a tab, with no hint that a setting explained it.
public struct SearchFieldsView: View {

    @Environment(TaskStore.self) private var store

    public init() {}

    public var body: some View {
        List {
            Section {
                ForEach(SearchField.allCases) { field in
                    let locked = store.settings.isOnlySearchField(field)
                    Toggle(isOn: Binding(
                        get: { store.settings.searches(field) },
                        set: { store.settings.setSearches($0, field: field) }
                    )) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(field.title)
                            Text(field.detail)
                                .font(.caption2)
                                .foregroundStyle(Theme.Palette.slate)
                        }
                    }
                    .disabled(locked)
                    .accessibilityHint(locked ? "At least one field stays selected" : "")
                }
            } header: {
                // Above the rows, as everywhere else — and here it carries the
                // one rule that isn't visible from the controls themselves.
                VStack(alignment: .leading, spacing: 6) {
                    Text("Search Bar Fields")
                    Text("Select the fields you want the Search Bar to search in each tab. At least one field stays selected.")
                        .textCase(nil)
                        .font(.footnote)
                        .foregroundStyle(Theme.Palette.slate)
                }
            }
        }
        .navigationTitle("Search Bar Fields")
        .navigationBarTitleDisplayMode(.inline)
    }
}

#Preview {
    NavigationStack { SearchFieldsView() }
        .environment(TaskStore(backend: MockBackend(latency: .zero), settings: AppSettings(),
            reachability: Reachability()
                              )
                     )
}
