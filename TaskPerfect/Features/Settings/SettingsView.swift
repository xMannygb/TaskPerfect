import SwiftUI

public struct SettingsView: View {

    @Environment(TaskStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    /// Optional so previews work without a live session.
    @Environment(Session.self) private var session: Session?
    @State private var confirmsSignOut = false
    @State private var confirmsResetCache = false
    @State private var serverHost = ServerConfig.serverHost
    @State private var domain = ServerConfig.domain

    public init() {}

    /// Write the connection fields back, cleaning what was typed. Empty falls
    /// back to the shipped default rather than saving a blank the app can't use.
    private func commitServerFields() {
        let cleanedHost = ServerConfig.normalizedHost(serverHost)
        ServerConfig.serverHost = cleanedHost.isEmpty ? ServerConfig.defaultServerHost : cleanedHost
        let cleanedDomain = domain.trimmingCharacters(in: .whitespacesAndNewlines)
        ServerConfig.domain = cleanedDomain.isEmpty ? ServerConfig.defaultDomain : cleanedDomain
        serverHost = ServerConfig.serverHost
        domain = ServerConfig.domain
    }

    public var body: some View {
        @Bindable var settings = store.settings

        Form {

            // ── Appearance ──────────────────────────────────────────────────
            Section {
                Text("Appearance")
                    .font(.headline)
                    .foregroundStyle(Theme.Palette.ink)
                    .listRowBackground(Theme.Palette.canvas)
                    .listRowInsets(EdgeInsets(top: 14, leading: 16, bottom: 4, trailing: 16))
            }
            .listSectionSpacing(.compact)

            Section {
                Toggle("Shade overdue tasks", isOn: $settings.shadesOverdueRows)
                Toggle("Shade tasks with no due date", isOn: $settings.shadesUndatedRows)
            } header: {
                Text("Row shading")
            } footer: {
                Text("A faint red wash behind overdue rows and a faint blue one behind undated rows. Section headings and text colors are unaffected.")
            }
            Section {
                Toggle("Tap a heading to collapse it", isOn: $settings.collapsibleSections)
                // A child of the toggle above: with collapsing off there are no
                // chevrons, so this governs nothing. Disabled rather than hidden
                // — hiding it leaves people hunting for a setting they saw once.
                Toggle("Keep No Due Date as you left it in the All Tasks tab",
                       isOn: $settings.remembersUndatedCollapse)
                    .disabled(!settings.collapsibleSections)
            } header: {
                Text("Collapsible sections")
            } footer: {
                Text("Collapsing is remembered while the app is open, and clears when you change how a tab is grouped.\n\nEvery heading reopens when you open the app. This leaves the No Due Date heading in the All Tasks tab the way you last had it, open or collapsed. The heading always shows its count, so nothing is hidden without being counted.")
            }
            Section {
                Picker("Subject lines", selection: $settings.subjectLineLimit) {
                    ForEach(1...6, id: \.self) { count in
                        Text("\(count)").tag(count)
                    }
                }
                .pickerStyle(.segmented)
            } header: {
                Text("Subject lines viewable in task lists")
            } footer: {
                Text(settings.subjectLineLimit == 1
                     ? "One line fits the most tasks on screen. Longer subjects are cut off with an ellipsis."
                     : "Subjects longer than \(settings.subjectLineLimit) lines are cut off with an ellipsis.")
            }
            // Same kind of decision as subject lines — how much a row shows —
            // so it sits directly beneath it rather than in Organization, which
            // governs what appears and in what order.
            Section {
                NavigationLink("Search Bar Fields") { SearchFieldsView() }
            } footer: {
                Text(searchFieldsSummary)
            }
            Section {
                NavigationLink("Task details in lists") { TaskDetailsView() }
            } footer: {
                Text(settings.detailsHiddenTabs.isEmpty
                     ? "Choose per tab whether rows show reminders, repeats, assignees and completion dates."
                     : "Details hidden in \(settings.detailsHiddenTabs.count) tab\(settings.detailsHiddenTabs.count == 1 ? "" : "s").")
            }
            Section {
                Picker("Tasks with no due date", selection: $settings.noDueDatePlacement) {
                    ForEach(AppSettings.NoDueDatePlacement.allCases, id: \.self) { option in
                        Text(option.label).tag(option)
                    }
                }
                .pickerStyle(.inline)
                .labelsHidden()
            } header: {
                Text("Tasks with no due date")
            } footer: {
                VStack(alignment: .leading, spacing: 6) {
                    Text(settings.noDueDatePlacement.explanation)
                    if settings.noDueDatePlacement == .hidden, store.undatedCount > 0 {
                        Text("\(store.undatedCount) task\(store.undatedCount == 1 ? "" : "s") currently hidden.")
                            .foregroundStyle(Theme.Palette.overdue)
                    }
                }
            }
            Section {
                Picker("Back", selection: $settings.pastLimit) {
                    ForEach(AppSettings.DateRangeLimit.pastOptions, id: \.self) { option in
                        Text(option.label).tag(option)
                    }
                }
                Picker("Ahead", selection: $settings.futureLimit) {
                    ForEach(AppSettings.DateRangeLimit.futureOptions, id: \.self) { option in
                        Text(option.label).tag(option)
                    }
                }
            } header: {
                Text("Date range of viewable tasks")
            } footer: {
                VStack(alignment: .leading, spacing: 6) {
                    Text(settings.hasDateRangeLimit
                         ? "Only tasks dated inside this window are listed. Tasks with no due date always show."
                         : "No limit — every task is listed regardless of date.")
                    if store.outOfRangeCount > 0 {
                        Text("\(store.outOfRangeCount) task\(store.outOfRangeCount == 1 ? "" : "s") outside the range, not shown.")
                            .foregroundStyle(Theme.Palette.overdue)
                    }
                }
            }

            // ── Organization ──────────────────────────────────────────────────
            Section {
                Text("Organization")
                    .font(.headline)
                    .foregroundStyle(Theme.Palette.ink)
                    .listRowBackground(Theme.Palette.canvas)
                    .listRowInsets(EdgeInsets(top: 14, leading: 16, bottom: 4, trailing: 16))
            }
            .listSectionSpacing(.compact)

            Section {
                NavigationLink("All Tasks Tab") {
                    CategorySortView(target: .main)
                }
                NavigationLink("Today Tab") {
                    CategorySortView(target: .today)
                }
                NavigationLink("Overdue Tab") {
                    CategorySortView(target: .overdue)
                }
                NavigationLink("No Due Date Tab") {
                    CategorySortView(target: .undated)
                }
                // Same order as the tab bar: No Due Date, Completed, No Category.
                NavigationLink("Completed Tab") {
                    CategorySortView(target: .completed)
                }
                NavigationLink("No Category Tab") {
                    CategorySortView(target: .noCategory)
                }
                NavigationLink("Category Tabs") {
                    CategorySortView(target: .category)
                }
            } header: {
                Text("Sorting Options")
            }
            Section {
                // Plain navigation rows: no summaries, nothing computed. These
                // are set-once preferences, so a status line would cost a scan
                // to tell the user something they aren't looking for.
                NavigationLink("Tab Badge & Visibility Controls") { BadgeSettingsView() }
            }

            if store.capabilities.supportsCategoryManagement {
                Section {
                    NavigationLink {
                        CategoryManagerView()
                    } label: {
                        LabeledContent("Categories Development & Controls",
                                       value: "\(store.categories.count)")
                    }
                } header: {
                    Text("Categories management")
                } footer: {
                    Text("Add, rename, recolor or remove categories. Changes reach Outlook on your computer too.")
                }
            }

            // ── Behavior ──────────────────────────────────────────────────
            Section {
                Text("Behavior")
                    .font(.headline)
                    .foregroundStyle(Theme.Palette.ink)
                    .listRowBackground(Theme.Palette.canvas)
                    .listRowInsets(EdgeInsets(top: 14, leading: 16, bottom: 4, trailing: 16))
            }
            .listSectionSpacing(.compact)

            Section {
                Toggle("Confirm before completing task", isOn: $settings.confirmsCompletion)
                Toggle("Confirm before deleting a task", isOn: $settings.confirmsTaskDeletion)
                Toggle("Confirm before deleting a category", isOn: $settings.confirmsCategoryDeletion)
                Toggle("Undo a deleted task", isOn: $settings.offersTaskUndo)
                if settings.offersTaskUndo {
                    Picker("Undo window", selection: $settings.taskUndoWindow) {
                        ForEach(AppSettings.UndoWindow.allCases, id: \.self) { Text($0.label).tag($0) }
                    }
                }
                Toggle("Undo a deleted category", isOn: $settings.offersCategoryUndo)
                if settings.offersCategoryUndo {
                    Picker("Undo window ", selection: $settings.categoryUndoWindow) {
                        ForEach(AppSettings.UndoWindow.allCases, id: \.self) { Text($0.label).tag($0) }
                    }
                }
            } header: {
                Text("Confirmations")
            } footer: {
                VStack(alignment: .leading, spacing: 6) {
                    Text(settings.confirmsCompletion
                         ? "Tapping the circle in the list asks first. Reopening a completed task never asks."
                         : "Tapping the circle completes the task immediately. Tap it again to reopen.")
                    Text("With undo on, a delete can be taken back for the chosen window. With it off, the delete is sent immediately and can't be recovered from the app.")
                    // Undo off *and* confirmation off means a swipe deletes with
                    // nothing in between. Worth saying rather than silently
                    // switching the confirmation on for them.
                    if !settings.offersTaskUndo && !settings.confirmsTaskDeletion {
                        Label("A swipe will delete a task immediately, with no confirmation and no undo.",
                              systemImage: "exclamationmark.triangle")
                            .foregroundStyle(Theme.Palette.flag)
                    }
                    if !settings.offersCategoryUndo && !settings.confirmsCategoryDeletion {
                        Label("Deleting a category will be immediate, with no confirmation and no undo.",
                              systemImage: "exclamationmark.triangle")
                            .foregroundStyle(Theme.Palette.flag)
                    }
                    if (settings.offersTaskUndo && settings.taskUndoWindow == .oneMinute)
                        || (settings.offersCategoryUndo && settings.categoryUndoWindow == .oneMinute) {
                        Text("Closing the app sends any pending delete immediately, so a long window often ends early in practice.")
                            .foregroundStyle(Theme.Palette.slate)
                    }
                    if !settings.confirmsCategoryDeletion {
                        Text("Without a confirmation, deleting a category leaves its label on tasks — the option to strip it from them only appears in the prompt.")
                            .foregroundStyle(Theme.Palette.flag)
                    }
                }
            }


            // ── Sync & Notifications ──────────────────────────────────────────────────
            Section {
                Text("Sync & Notifications")
                    .font(.headline)
                    .foregroundStyle(Theme.Palette.ink)
                    .listRowBackground(Theme.Palette.canvas)
                    .listRowInsets(EdgeInsets(top: 14, leading: 16, bottom: 4, trailing: 16))
            }
            .listSectionSpacing(.compact)

            Section {
                Toggle("After every change", isOn: $settings.syncsAfterChanges)
                Toggle("When opening the app", isOn: $settings.syncsOnOpen)
                Toggle("When closing the app", isOn: $settings.syncsOnClose)
            } header: {
                Text("Sync")
            } footer: {
                VStack(alignment: .leading, spacing: 6) {
                    if settings.syncsAfterChanges {
                        Text("Edits, completions and category changes sync a couple of seconds after you stop making them.")
                    }
                    Text(settings.syncsManuallyOnly && !settings.syncsAfterChanges
                         ? "Syncing is manual only. Use the sync button on the task list whenever you want to pull changes."
                         : "You can also sync any time with the button on the task list.")
                    Text("Display settings stay on this device — Exchange has nowhere to store them.")
                        .foregroundStyle(Theme.Palette.slate)
                }
            }
            Section {
                Toggle("Show reminders when the app opens", isOn: $settings.showsRemindersOnOpen)
            } header: {
                Text("Reminders")
            } footer: {
                Text("A banner lists reminders that came due while you were away, after the app finishes syncing. Dismissing one clears it on this iPhone only — the reminder stays on the task, and on Outlook.")
            }
            Section {
                Toggle("Show today's count on the app icon", isOn: $settings.showsAppBadge)
                    .onChange(of: settings.showsAppBadge) { _, isOn in
                        Task {
                            if isOn, await AppBadge.requestAuthorization() == false {
                                // Declined — don't leave a switch on that does nothing.
                                settings.showsAppBadge = false
                                return
                            }
                            await AppBadge.apply(count: store.todayOutstanding,
                                                 enabled: settings.showsAppBadge)
                        }
                    }
            } header: {
                Text("App icon badge")
            } footer: {
                Text(settings.showsAppBadge
                     ? "The icon shows how many tasks are due today — the same number as the Today tab. Overdue and completed tasks aren't counted."
                     : "No badge on the app icon. Turning this on asks for notification permission, which is what iOS uses to draw the number.")
            }

            // ── Account ──────────────────────────────────────────────────
            Section {
                Text("Account")
                    .font(.headline)
                    .foregroundStyle(Theme.Palette.ink)
                    .listRowBackground(Theme.Palette.canvas)
                    .listRowInsets(EdgeInsets(top: 14, leading: 16, bottom: 4, trailing: 16))
            }
            .listSectionSpacing(.compact)

            Section {
                Picker("When the app opens", selection: $settings.lockMode) {
                    ForEach(AppLock.availableModes, id: \.self) { mode in
                        Text(mode.label).tag(mode)
                    }
                }
                .pickerStyle(.inline)
                .labelsHidden()
                .onChange(of: settings.lockMode) { _, mode in
                    // Re-store the password under the new protection class, or
                    // clear it. Changing the setting has to change what's on disk
                    // or it's only a label.
                    session?.applyLockMode(mode)
                }
            } header: {
                Text("How the app opens")
            } footer: {
                VStack(alignment: .leading, spacing: 6) {
                    Text(settings.lockMode.explanation)
                    if !AppLock.biometryAvailable {
                        Text("Face ID or Touch ID isn't set up on this iPhone, so that option isn't listed.")
                            .foregroundStyle(Theme.Palette.slate)
                    }
                }
            }
            Section {
                LabeledContent("Signed in as", value: CredentialStore.rememberedUsername ?? "—")
                HStack {
                    Text("Server")
                    Spacer()
                    TextField(ServerConfig.defaultServerHost, text: $serverHost)
                        .multilineTextAlignment(.trailing)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .keyboardType(.URL)
                        .foregroundStyle(Theme.Palette.slate)
                        .onSubmit { commitServerFields() }
                }
                HStack {
                    Text("Domain")
                    Spacer()
                    TextField("Optional", text: $domain)
                        .multilineTextAlignment(.trailing)
                        .textInputAutocapitalization(.characters)
                        .autocorrectionDisabled()
                        .foregroundStyle(Theme.Palette.slate)
                        .onSubmit { commitServerFields() }
                }
                if ServerConfig.isCustomized {
                    Button("Reset to defaults") {
                        ServerConfig.resetToDefaults()
                        serverHost = ServerConfig.serverHost
                        domain = ServerConfig.domain
                    }
                }
                // No password field here. Under biometric lock, reading the
                // stored password *is* the Face ID prompt — so showing it would
                // demand authentication every time this screen opened, for a
                // field nobody came to look at. Under "password every time"
                // there's nothing stored to show at all. Signing out is the
                // useful action anyway: it's how you give the app a new
                // password after changing it in Exchange.
                Button {
                    confirmsResetCache = true
                } label: {
                    Text("Reset cache")
                        .foregroundStyle(Theme.Palette.overdue)
                }
                Button(role: .destructive) {
                    confirmsSignOut = true
                } label: {
                    Text("Sign out")
                }
            } header: {
                Text("Account")
            } footer: {
                Text("Domain is usually unnecessary — signing in with your full e-mail address is enough. Change the server only if Intermedia moves your mailbox to a different host; a wrong value stops the app reaching your tasks, and the same fields are on the sign-in screen if that happens.")
            }
        }
        .onDisappear { commitServerFields() }
        .confirmationDialog("Reset the local cache?",
                            isPresented: $confirmsResetCache, titleVisibility: .visible) {
            Button("Reset Cache", role: .destructive) {
                Task { await store.resetCache() }
                dismiss()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Anything you've changed but not yet synced is sent first, then every task is downloaded again. Use this if the list looks out of step with Outlook.")
        }
        .confirmationDialog("Sign out of Task Perfect?",
                            isPresented: $confirmsSignOut, titleVisibility: .visible) {
            Button("Sign Out", role: .destructive) {
                session?.signOut()
                dismiss()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Your tasks stay on this device until the next sign-in. Anything not yet synced will be sent when you sign back in.")
        }
        .navigationTitle("Settings")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("Done") { dismiss() }.fontWeight(.semibold)
            }
        }
    }

    /// Names the current scope, so the common case is answerable without opening
    /// the screen.
    private var searchFieldsSummary: String {
        let names = SearchField.allCases
            .filter { store.settings.searches($0) }
            .map(\.title)
        // Instruction first, state second. The names alone read as a label for
        // the row rather than as something you can change; the em dash keeps
        // both in one line rather than spending two.
        return "Select the fields you want the Search Bar to search in each tab — currently "
            + names.joined(separator: ", ") + "."
    }
}

#Preview {
    let store = TaskStore(backend: MockBackend(latency: .zero), settings: AppSettings())
    return NavigationStack { SettingsView() }
        .environment(store)
        .task { await store.load() }
}
