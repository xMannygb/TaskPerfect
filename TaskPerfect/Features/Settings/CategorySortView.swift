import SwiftUI

/// Grouping and sorting for category pills.
///
/// Applies to category tabs only. The fixed tabs keep their own rules — All
/// Tasks groups by day, Overdue regroups by due date, Completed sorts by
/// completion — because each answers a specific question and shouldn't be
/// reconfigurable into answering a different one.
public struct CategorySortView: View {

    @Environment(TaskStore.self) private var store

    /// Which setting this screen edits. One screen, two stores of options —
    /// the layout is identical and duplicating it would mean fixing every
    /// future change twice.
    public enum Target { case main, today, overdue, undated, noCategory, completed, category }

    let target: Target

    public init(target: Target = .category) {
        self.target = target
    }

    private var options: Binding<CategorySortOptions> {
        @Bindable var settings = store.settings
        switch target {
        case .main:     return $settings.mainSort
        case .today:    return $settings.todaySort
        case .overdue:  return $settings.overdueSort
        case .undated:  return $settings.undatedSort
        case .noCategory: return $settings.noCategorySort
        case .completed:  return $settings.completedSort
        case .category: return $settings.categorySort
        }
    }

    /// All Tasks and Today can partition by category; a category tab can't —
    /// every task in it already shares that category.
    /// Assigned goes last in every list — it's the newest and the least
    /// populated, so it shouldn't displace the grouping people reach for first.
    private static let assignedGroupings: [CategorySortOptions.Grouping] =
        [.assignedAZ, .assignedZA]

    private var groupings: [CategorySortOptions.Grouping] {
        base + Self.assignedGroupings + [.ungrouped]
    }

    /// Without `.ungrouped` — `groupings` appends it after the assigned pair, so
    /// Ungrouped stays last in every menu.
    private var base: [CategorySortOptions.Grouping] {
        switch target {
        // Nothing here has a date, so due-date grouping would be one section.
        case .undated:  return [.category]
        // Due-date grouping in Today yields Overdue and Today — exactly what the
        // tab already shows without any setting, so it isn't offered.
        case .today:    return [.category]
        // Nothing here carries a category, so grouping by one is meaningless.
        case .noCategory: return [.dueDate]
        case .completed:  return [.completionDate, .dueDate]
        // Horizon suits a pill even better than All Tasks: fewer tasks over the
        // same span is exactly when one heading per day reads worst.
        case .category: return [.dueDate, .horizon]
        // Horizon sits directly below Due Date: the two are variations on the
        // same key at different resolutions, and adjacency is what says so.
        // All Tasks only for now — worth living with before it spreads.
        default:        return [.dueDate, .horizon, .category]
        }
    }

    /// Levels this screen offers. No Due Date has its own pair — nothing here
    /// has a date, so the date levels would decide nothing.
    private var levelChoices: [CategorySortOptions.SortLevel] {
        // Grouped by assignee, each section is already one person — so the
        // assigned levels would have nothing to separate. Same rule as category
        // levels vanishing inside category grouping.
        let grouping = options.wrappedValue.grouping
        if grouping == .assignedAZ || grouping == .assignedZA {
            return rawLevelChoices.filter { $0 != .assignedAZ && $0 != .assignedZA }
        }
        return rawLevelChoices
    }

    private var rawLevelChoices: [CategorySortOptions.SortLevel] {
        // No category levels here — nothing carries one. And no date levels
        // under due-date grouping, where each section is already a single date.
        if target == .completed {
            switch options.wrappedValue.grouping {
            case .completionDate: return CategorySortOptions.SortLevel.forCompletedByCompletion
            case .dueDate:        return CategorySortOptions.SortLevel.forCompletedByDue
            default:              return CategorySortOptions.SortLevel.forCompletedUngrouped
            }
        }
        // Today: no date levels. Overdue is a pinned section with its own
        // ordering, and everything else in the tab is due today — so a date sort
        // would only separate tasks due at different times of the same day.
        if target == .today {
            return options.wrappedValue.grouping == .category
                ? CategorySortOptions.SortLevel.forUndatedByCategory
                : CategorySortOptions.SortLevel.forUndatedUngrouped
        }
        if target == .noCategory {
            return options.wrappedValue.grouping == .dueDate
                ? CategorySortOptions.SortLevel.forNoCategoryByDate
                : CategorySortOptions.SortLevel.forCategoryGrouping
        }
        guard target == .undated else {
            return options.wrappedValue.availableLevels(forMainTabs: offersCategoryLevels)
        }
        return options.wrappedValue.grouping == .category
            ? CategorySortOptions.SortLevel.forUndatedByCategory
            : CategorySortOptions.SortLevel.forUndatedUngrouped
    }

    /// Whether the category sort levels are offered. A category tab filters to
    /// one category already, so ordering by "first tag" would sort by something
    /// that isn't the tab.
    private var offersCategoryLevels: Bool { target != .category }

    public var body: some View {
        let options = self.options

        Form {
            Section {
                Picker("Group by", selection: Binding(
                    get: { options.wrappedValue.grouping },
                    set: { newValue in
                        options.wrappedValue.grouping = newValue
                        // Drop levels the new grouping doesn't offer, or the
                        // picker shows a blank row and sorts by something
                        // invisible.
                        if target == .undated || target == .noCategory
                            || target == .completed || target == .today {
                            // Prune against this screen's own lists.
                            let allowed = Set(levelChoices)
                            options.wrappedValue.levels = options.wrappedValue.levels
                                .map { allowed.contains($0) ? $0 : .none }
                        } else {
                            options.wrappedValue.pruneLevels(forMainTabs: offersCategoryLevels)
                        }
                    }
                )) {
                    ForEach(groupings, id: \.self) {
                        Text($0.label).tag($0)
                    }
                }
            } header: {
                Text("Grouping Options")
            } footer: {
                Text(groupingExplanation(options.wrappedValue.grouping))
            }

            Section {
                ForEach(Array(options.wrappedValue.levels.indices), id: \.self) { index in
                    Picker(
                        CategorySortView.levelName(index),
                        selection: Binding(
                            get: { options.wrappedValue.levels[index] },
                            set: { options.wrappedValue.levels[index] = $0 }
                        )
                    ) {
                        // The menu changes with the grouping: category levels
                        // decide nothing inside a category group.
                        ForEach(levelChoices, id: \.self) {
                            Text($0.label).tag($0)
                        }
                    }
                }
            } header: {
                Text("Sorting Within Group")
            } footer: {
                Text("Each level only decides when the one above it ties. With Alphabetically first, ties need identical subjects — so the levels below will rarely change anything. Splits work best at the top: High Priority, then Recurring, then a date, then a name.")
            }

            if target == .overdue || target == .undated || target == .noCategory || target == .completed {
                // No completed banner: a completed task is neither overdue nor
                // waiting for a date.
                EmptyView()
            } else if target == .category {
                // No completed toggle here. It's per-category now, so there is
                // no single value this screen could show — the banner in each
                // tab is the control, and it sits where it applies.
                EmptyView()
            } else {
                // No completed toggle on any sort screen. Showing completed
                // tasks is a filtering decision, not a sorting one, and each
                // tab's banner is the control — it sits in the tab it affects
                // and reports that tab's real state, which a shared switch here
                // could not.
                EmptyView()
            }
        }
        .navigationTitle(navigationTitle)
        .navigationBarTitleDisplayMode(.inline)
    }

    private var navigationTitle: String {
        switch target {
        case .main:       return "All Tasks Tab"
        case .today:      return "Today Tab"
        case .overdue:    return "Overdue Tab"
        case .undated:    return "No Due Date Tab"
        case .noCategory: return "No Category Tab"
        case .completed:  return "Completed Tab"
        case .category:   return "Category Tabs"
        }
    }

    private func groupingExplanation(_ grouping: CategorySortOptions.Grouping) -> String {
        switch grouping {
        case .horizon:
            let base = "Overdue, Today and Tomorrow as usual, then the rest of this week, four weeks one at a time, then whole months. Detail close in, less of it further out — so the list stays about a dozen headings however far ahead your tasks run."
            // Worth saying here rather than leaving to be discovered: the pills
            // share one sort configuration, so this lands on all of them.
            return target == .category
                ? base + " Applies to every category tab."
                : base
        case .dueDate:
            switch target {
            case .main:
                return "One section per due date, as the tab already shows."
            case .today:
                return ""   // due-date grouping isn't offered here
            case .overdue:
                return "One section per past date, oldest first. Overdue tasks spread across whatever dates they missed, so this tends toward many small sections — Ungrouped often reads better here."
            case .category:
                return "One section per due date, as All Tasks does."
            case .undated:
                return ""   // due-date grouping isn't offered here
            case .completed:
                return "One section per due date, oldest first. Completed tasks without a due date go to the bottom."
            case .noCategory:
                return "One section per due date. The date levels aren't offered here — each section is already a single date, so they'd have nothing to separate."
            }
        case .completionDate:
            return "One section per day you finished something, most recent first. Exchange doesn't always record a completion date — those tasks go to a section at the bottom."
        case .category:
            return "One section per category. A task with two categories appears once, under the first one it carries — groups are a partition, so overlapping them would make the counts exceed your task total."
        case .ungrouped:
            if target == .undated {
                return "A single list. Nothing here has a due date, so a name or category order is what's left to rank by."
            }
            if target == .completed {
                return "A single list. Nothing here is pending, so there's nothing to pin."
            }
            if target == .today {
                return "A single list, with overdue tasks pinned at the top. Everything else is due today, so a name or category order is what's left to rank by."
            }
            if target == .completed {
            switch options.wrappedValue.grouping {
            case .completionDate: return CategorySortOptions.SortLevel.forCompletedByCompletion
            case .dueDate:        return CategorySortOptions.SortLevel.forCompletedByDue
            default:              return CategorySortOptions.SortLevel.forCompletedUngrouped
            }
        }
        if target == .noCategory {
                return "A single list, though overdue tasks stay pinned at the top and tasks with no due date keep the placement set in Display settings."
            }
            return target == .overdue
                ? "A single list. Everything here is already overdue, so there's nothing to pin."
                : "A single list — though overdue tasks stay pinned at the top, and tasks with no due date keep the placement set in Display settings."
        }
    }

    static func levelName(_ index: Int) -> String {
        switch index {
        case 0:  return "1st Priority Sort Level"
        case 1:  return "2nd Priority Sort Level"
        case 2:  return "3rd Priority Sort Level"
        default: return "4th Priority Sort Level"
        }
    }
}

#Preview {
    let store = TaskStore(backend: MockBackend(latency: .zero), settings: AppSettings())
    return NavigationStack { CategorySortView() }
        .environment(store)
        .task { await store.load() }
}
