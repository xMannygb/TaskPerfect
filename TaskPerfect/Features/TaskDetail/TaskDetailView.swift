import SwiftUI

/// Task detail and editor.
///
/// Field visibility is bound to `BackendCapabilities`, not hardcoded. Today every
/// field shows, because EWS supports the full Outlook task item. If Intermedia ever
/// migrates you to Microsoft 365, flipping one constant hides the fields Graph's
/// To Do API can't store — instead of the app silently discarding user data.
public struct TaskDetailView: View {

    @Environment(TaskStore.self) private var store
    @Environment(\.dismiss) private var dismiss

    @State private var draft: TPTask
    @State private var isConfirmingDelete = false
    @State private var isConfirmingPlainText = false
    /// Non-nil while the share sheet is up. Built on demand rather than held,
    /// so the text and the attachment reflect the current edits.
    @State private var shareItems: [Any]?
    @State private var showsAllCategories = false
    @State private var isConfirmingComplete = false

    private let original: TPTask
    private let isNew: Bool

    public init(task: TPTask, isNew: Bool = false) {
        self.original = task
        self.isNew = isNew
        _draft = State(initialValue: task)
    }

    public var body: some View {
        Form {
            subjectSection
            emphasisSection
            scheduleSection
            progressSection
            if store.capabilities.supportsEffortTracking { effortSection }
            if store.capabilities.supportsMileageAndBilling { adminSection }
            notesSection
            // A task that doesn't exist yet has nothing to delete — Cancel
            // already discards it.
            if !isNew {
                completeSection
                deleteSection
            }
        }
        .sheet(isPresented: $showsAllCategories) {
            NavigationStack {
                TaskCategoryPicker(selected: $draft.categories)
            }
        }
        .sheet(isPresented: Binding(
            get: { shareItems != nil },
            set: { if !$0 { shareItems = nil } }
        )) {
            ShareSheet(items: shareItems ?? [], subject: draft.subject)
        }
        .confirmationDialog(
            "Mark this task complete?",
            isPresented: $isConfirmingComplete,
            titleVisibility: .visible
        ) {
            Button("Complete Task") { toggleCompletion() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text(TaskListView.completionNote(for: draft))
        }
        .confirmationDialog(
            "Delete this task?",
            isPresented: $isConfirmingDelete,
            titleVisibility: .visible
        ) {
            Button("Delete Task", role: .destructive) {
                let doomed = original
                dismiss()
                Task { await store.delete(doomed) }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text(TaskListView.deleteWarning(for: original))
        }
        .navigationTitle(isNew ? "New Task" : "Task")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Cancel") { dismiss() }
            }
            // Only on a saved task: sharing something not yet written invites
            // confusion about what was actually sent. Left of Save, which stays
            // the rightmost as the primary action.
            if !isNew {
                ToolbarItem(placement: .topBarTrailing) {
                    ShareLink(
                        item: TaskShareExport.text(for: draft),
                        subject: Text(draft.subject),
                        message: Text("")
                    ) {
                        Image(systemName: "square.and.arrow.up")
                    }
                    .accessibilityLabel("Share task")
                }
            }
            ToolbarItem(placement: .confirmationAction) {
                Button(isNew ? "Add" : "Save") {
                    let task = normalized
                    dismiss()
                    Task {
                        if isNew { await store.create(task) } else { await store.save(task) }
                    }
                }
                .disabled(isNew ? subjectIsEmpty : !hasChanges)
                .fontWeight(.semibold)
            }
        }
    }

    // MARK: Sections

    /// Names the control when there's no override, shows the delta when there
    /// is. B and I are self-evident; a bare stepper isn't.
    private var sizeLabel: String {
        guard let delta = draft.emphasis.sizeDelta else { return "Font size" }
        return delta > 0 ? "+\(delta)" : "\(delta)"
    }

    private func stepSize(_ step: Int) {
        var e = draft.emphasis
        if let current = e.sizeDelta {
            let next = current + step
            // Below the floor, fall back to the category rather than clamping —
            // it gives the stepper a way back to the third state.
            e.sizeDelta = next < CategoryTextStyle.sizeRange.lowerBound
                ? nil
                : min(next, CategoryTextStyle.sizeRange.upperBound)
        } else {
            // First press adopts the category's own size, so stepping from
            // "Category" moves one notch rather than jumping to zero.
            e.sizeDelta = effectiveStyle.sizeDelta + step
        }
        draft.setMileage(emphasis: e)
    }

    /// The style the task would render with, before any override.
    ///
    /// `textStyle(forAny:)` already implements the first-category-with-a-style
    /// rule the rows use, so this doesn't reimplement it — and `textStyle(for:)`
    /// returns an optional, which is the wrong shape here.
    private var effectiveStyle: CategoryTextStyle {
        store.settings.textStyle(forAny: draft.categories)
    }

    /// Unset → on → off → unset. Three states need three stops; a plain toggle
    /// can only say two and couldn't express "follow the category".
    private func cycle(_ value: Bool?) -> Bool? {
        switch value {
        case nil:    return true
        case true:   return false
        case false:  return nil
        case .some:  return nil
        }
    }

    /// Filled when forced on, struck when forced off, plain when following the
    /// category — so the third state is visible rather than implied.
    private func emphasisButton(
        _ label: String,
        systemImage: String,
        value: Bool?,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.system(size: 14, weight: .semibold))
                .frame(width: 40, height: 30)
                .background(
                    RoundedRectangle(cornerRadius: 8)
                        .fill(value == true ? Theme.Palette.ink : Color.clear)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .strokeBorder(Theme.Palette.hairline)
                )
                .foregroundStyle(value == true ? Theme.Palette.paper
                                 : (value == false ? Theme.Palette.slate : Theme.Palette.ink))
                .opacity(value == false ? 0.45 : 1)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
        .accessibilityValue(value == true ? "On" : value == false ? "Off" : "Category style")
    }

    private var emphasisSection: some View {
        Section {
            // Below Categories, not above: the order teaches the relationship
            // — pick a category, then adjust its style. Three states each: on,
            // off, or unset. Unset follows the category, which is what lets a
            // task in a bold category be set explicitly regular.
            HStack(spacing: 10) {
                emphasisButton("Bold", systemImage: "bold", value: draft.emphasis.bold) {
                    var e = draft.emphasis
                    e.bold = cycle(e.bold)
                    draft.setMileage(emphasis: e)
                }
                emphasisButton("Italic", systemImage: "italic", value: draft.emphasis.italic) {
                    var e = draft.emphasis
                    e.italic = cycle(e.italic)
                    draft.setMileage(emphasis: e)
                }
                // A stepper, not a cycling button: size carries a value rather
                // than being on or off. Stepping below the floor returns it to
                // "follow the category" — the third state the other two get
                // from their off position.
                HStack(spacing: 2) {
                    Button {
                        stepSize(-1)
                    } label: { Image(systemName: "minus") }
                        .buttonStyle(.plain)
                        .frame(width: 28, height: 30)
                    Text(sizeLabel)
                        .font(.system(size: 12))
                        .foregroundStyle(Theme.Palette.slate)
                        .frame(minWidth: 64)
                    Button {
                        stepSize(1)
                    } label: { Image(systemName: "plus") }
                        .buttonStyle(.plain)
                        .frame(width: 28, height: 30)
                }
                .overlay(RoundedRectangle(cornerRadius: 8)
                    .strokeBorder(Theme.Palette.hairline))

                Spacer()
            }

            if !draft.emphasis.isEmpty {
                Button("Reset to Category Style") {
                    // Clears all three. Re-setting whichever you wanted is
                    // simpler than three separate resets for something done
                    // rarely.
                    draft.setMileage(emphasis: TPTask.Emphasis())
                }
                .font(.system(size: 13))
                .foregroundStyle(Theme.Palette.slate)
                // Trailing, so it sits under the controls it resets rather than
                // floating in the middle of the row.
                .frame(maxWidth: .infinity, alignment: .trailing)
            }

            // One row instead of a list. The list grows with every category
            // added, so an inline picker either caps and hides some, or takes
            // over the sheet. Tapping opens the full list; the chips show what
            // is chosen.
            Button {
                showsAllCategories = true
            } label: {
                HStack(alignment: .top) {
                    Text("Categories")
                        .foregroundStyle(Theme.Palette.ink)
                    Spacer(minLength: 12)
                    if draft.categories.isEmpty {
                        Text("None").foregroundStyle(Theme.Palette.slate)
                    } else {
                        categoryChips
                    }
                    Image(systemName: "chevron.right")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(Theme.Palette.slate)
                }
            }
        } header: {
            // The note used to print below the Categories row at the foot of
            // this section, where it read as a comment on categories rather than
            // on emphasis. Above the controls it describes instead.
            VStack(alignment: .leading, spacing: 6) {
                Text("Font Emphasis")
                Text("For the occasional task that needs to stand out from others in its category. Everything else follows the category's own styling.")
                    .textCase(nil)
                    .font(.footnote)
                    .foregroundStyle(Theme.Palette.slate)
            }
        }
    }

    private var subjectSection: some View {
        Section {
            // `axis: .vertical` is what makes it wrap and grow rather than
            // scrolling sideways with the end of a long subject unreadable.
            TextField("Subject", text: $draft.subject, axis: .vertical)
                .font(.body)
                .lineLimit(1...6)
                // A subject is one line of text that happens to wrap; a return
                // in it would be stored and then rendered as a space anyway.
                .onChange(of: draft.subject) { _, new in
                    if new.contains("\n") {
                        draft.subject = new.replacingOccurrences(of: "\n", with: " ")
                    }
                }
            Picker("Importance", selection: $draft.importance) {
                Text("Low").tag(TPImportance.low)
                Text("Normal").tag(TPImportance.normal)
                Text("High").tag(TPImportance.high)
            }
        }
    }

    private var scheduleSection: some View {
        Section("Schedule") {
            DateFieldView(title: "Start", date: $draft.startDate, defaultHour: 9)
            DateFieldView(title: "Due", date: $draft.dueDate)
            DateFieldView(title: "Reminder", date: $draft.reminderDueBy, includesTime: true, defaultHour: 9)

            NavigationLink {
                RecurrenceEditorView(
                    current: draft.recurrence,
                    anchor: draft.dueDate ?? Date()
                ) { updated in
                    draft.recurrence = updated
                }
            } label: {
                HStack {
                    Text("Repeat")
                    Spacer()
                    Text(draft.recurrence?.summary ?? "Never")
                        .foregroundStyle(Theme.Palette.slate)
                        .multilineTextAlignment(.trailing)
                }
            }

            if let recurrence = draft.recurrence,
               let next = RecurrenceEngine.upcoming(
                   from: draft.dueDate ?? Date(), recurrence: recurrence, count: 1
               ).first {
                LabeledContent("Next after this") {
                    Text(next.formatted(date: .abbreviated, time: .omitted))
                        .font(Theme.numeric(15))
                }
                .foregroundStyle(Theme.Palette.slate)
            }
        }
    }

    private var progressSection: some View {
        Section("Progress") {
            Picker("Status", selection: statusBinding) {
                ForEach(TPTaskStatus.allCases, id: \.self) { status in
                    Text(status.displayName).tag(status)
                }
            }

            if store.capabilities.supportsPercentComplete {
                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Text("% Complete")
                        Spacer()
                        Text("\(Int(draft.percentComplete))%")
                            .font(Theme.numeric(15, weight: .medium))
                            .foregroundStyle(Theme.Palette.slate)
                    }
                    Slider(
                        value: Binding(
                            get: { draft.percentComplete },
                            set: { draft.setPercentComplete(($0 / 5).rounded() * 5) }
                        ),
                        in: 0...100
                    )
                    .tint(Theme.Palette.ink)
                }
            }

            if let completed = draft.completeDate {
                LabeledContent("Completed", value: completed.formatted(date: .abbreviated, time: .omitted))
                    .foregroundStyle(Theme.Palette.slate)
            }
        }
    }

    private var effortSection: some View {
        Section("Effort") {
            LabeledContent("Total work") {
                TextField("minutes", value: $draft.totalWork, format: .number)
                    .keyboardType(.numberPad)
                    .multilineTextAlignment(.trailing)
                    .font(Theme.numeric(17))
            }
            LabeledContent("Actual work") {
                TextField("minutes", value: $draft.actualWork, format: .number)
                    .keyboardType(.numberPad)
                    .multilineTextAlignment(.trailing)
                    .font(Theme.numeric(17))
            }
            if let hours = draft.estimatedHours, hours > 0 {
                LabeledContent("Estimated", value: String(format: "%.1f hours", hours))
                    .foregroundStyle(Theme.Palette.slate)
            }
        }
    }

    private var adminSection: some View {
        Section {
            // No Mileage row. The field is the app's storage for the per-task
            // emphasis marker, and an editable control over it invites someone
            // to type into a field they don't know is spoken for.
            //
            // Nothing is lost: `setMileage` preserves any text it doesn't own,
            // so mileage typed in Outlook survives even though the app never
            // shows it. Outlook remains the place to read or clear it.
            LabeledContent("Billing") {
                TextField("None", text: Binding(
                    get: { draft.billingInformation ?? "" },
                    set: { draft.billingInformation = $0.isEmpty ? nil : $0 }
                ))
                .multilineTextAlignment(.trailing)
            }
            // Read-only: Exchange sets Owner to the mailbox owner and rejects a
            // write to it. It only names someone else on a formally assigned
            // task, which is why it can't carry "who's responsible".
            LabeledContent("Owner", value: draft.owner ?? "—")
                .foregroundStyle(Theme.Palette.slate)

            if store.capabilities.supportsCompanies {
                LabeledContent("Assigned To") {
                    TextField("None", text: Binding(
                        get: { draft.companies.joined(separator: ", ") },
                        // Companies is an array in EWS, so the text is split
                        // rather than stored whole.
                        set: { text in
                            draft.companies = text
                                .split(separator: ",")
                                .map { $0.trimmingCharacters(in: .whitespaces) }
                                .filter { !$0.isEmpty }
                        }
                    ))
                    .multilineTextAlignment(.trailing)
                }
            }
        } header: {
            Text("Tracking")
        } footer: {
            Text("Owner is set by Exchange and can't be changed. **Assigned To** is stored in the task's Companies field — that's the label it appears under in Outlook, on the Details tab. Separate several names with commas.")
        }
    }

    /// Deliberately lighter than the delete bar below it.
    ///
    /// Two full-width bars of equal weight in the same place are easy to hit
    /// wrongly, and spacing alone is a thin defence on a phone — so this reads
    /// as a normal row and only the destructive one is heavy and red.
    ///
    /// Flips to Reopen on a completed task: same place, obvious opposite.
    private var completeSection: some View {
        Section {
            Button {
                // Reopening is never gated; completing follows the same
                // preference the checkbox in the list uses, so there's one rule
                // rather than two implementations of it.
                if store.settings.confirmsCompletion && !draft.isComplete {
                    isConfirmingComplete = true
                } else {
                    toggleCompletion()
                }
            } label: {
                HStack {
                    Spacer()
                    Text(draft.isComplete ? "Reopen Task" : "Complete Task")
                        .foregroundStyle(Theme.Palette.ink)
                    Spacer()
                }
            }
        }
    }

    private var deleteSection: some View {
        Section {
            Button(role: .destructive) {
                isConfirmingDelete = true
            } label: {
                HStack {
                    Spacer()
                    Text("Delete Task")
                    Spacer()
                }
            }
        }
    }

    private func toggleCompletion() {
        let target = original
        dismiss()
        Task { await store.toggleComplete(target) }
    }

    private var notesSection: some View {
        Section {
            Toggle(isOn: Binding(
                get: { draft.body.isHTML },
                set: { wantsHTML in
                    if wantsHTML {
                        // Safe direction: nothing is lost turning plain into HTML.
                        draft.body = draft.body.convertedToHTML()
                    } else {
                        // Lossy — a plain body cannot hold bullets or color, so
                        // this discards them rather than hiding them.
                        isConfirmingPlainText = true
                    }
                }
            )) {
                HStack(spacing: 6) {
                    Text("Text Formatting")
                    Text("(Default is Plain Text)")
                        .font(.caption)
                        .foregroundStyle(Theme.Palette.slate)
                }
            }

            if draft.body.isHTML {
                // The controls appear with the toggle rather than sitting inert
                // above a plain note: a row of nine dimmed buttons is more
                // confusing than no buttons at all.
                RichNotesEditor(body: $draft.body)
                    .frame(minHeight: 160)
                    .listRowInsets(EdgeInsets())
            } else {
                TextField("Add notes", text: $draft.body.content, axis: .vertical)
                    .lineLimit(4...12)
            }
        } header: {
            Text("Notes")
        } footer: {
            // The warning appears in both states: before you turn it on, so the
            // cost is known up front; and while it's on, when it's about to bite.
            VStack(alignment: .leading, spacing: 4) {
                if draft.body.isHTML {
                    Text("Formatting travels to Outlook. Editing the note there and syncing back may not preserve colors and sizes exactly — bullets and bold usually survive.")
                    Text("Switching this note back to Plain Text will lose all formatting within it. The words are kept.")
                        .foregroundStyle(Theme.Palette.overdue)
                } else {
                    Text("Plain text. Turn on Text Formatting for colors, fonts, bullets and numbering.")
                    Text("If a formatted note is switched back to Plain Text, all formatting within that note is lost.")
                }
            }
        }
        .confirmationDialog("Switch to plain text?",
                            isPresented: $isConfirmingPlainText, titleVisibility: .visible) {
            Button("Remove Formatting", role: .destructive) {
                draft.body = draft.body.convertedToPlainText()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Formatting in this note — colors, fonts, bullets and numbering — will be removed. The words are kept.")
        }
    }

    // MARK: Helpers

    private var statusBinding: Binding<TPTaskStatus> {
        Binding(
            get: { draft.status },
            set: { draft.setStatus($0) }
        )
    }

    /// Wraps rather than scrolling: a task with several categories should show
    /// them all, and the row is free to grow.
    private var categoryChips: some View {
        FlowLayout(spacing: 6) {
            ForEach(draft.categories, id: \.self) { name in
                let known = store.categories.first { $0.name == name }
                HStack(spacing: 5) {
                    Circle()
                        .fill(known.map { OutlookCategoryPalette.color(for: $0.colorIndex) }
                              ?? Color.clear)
                        .overlay(Circle().strokeBorder(
                            known == nil ? Theme.Palette.hairline : .clear, lineWidth: 1))
                        .frame(width: 8, height: 8)
                    Text(name)
                    if known == nil {
                        Text("not in list")
                            .font(.caption2)
                            .foregroundStyle(Theme.Palette.slate)
                    }
                }
                .font(.system(size: 13,
                              // The first decides where the task files under
                              // category grouping, so it shouldn't look
                              // interchangeable with the rest.
                              weight: name == draft.categories.first ? .semibold : .regular))
                .foregroundStyle(Theme.Palette.ink)
                .padding(.horizontal, 9)
                .padding(.vertical, 3)
                .background(Theme.Palette.canvas, in: Capsule())
                .opacity(known == nil ? 0.75 : 1)
            }
        }
    }

    /// `reminderIsSet` is derived, never edited directly — a reminder exists
    /// exactly when it has a date. Keeping the flag as separate state was how the
    /// two could drift apart.
    private var normalized: TPTask {
        var task = draft
        task.reminderIsSet = task.reminderDueBy != nil
        return task
    }

    private var hasChanges: Bool { normalized != original }

    private var subjectIsEmpty: Bool {
        draft.subject.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
}

#Preview {
    let store = TaskStore(backend: MockBackend(latency: .zero))
    return NavigationStack {
        TaskDetailView(task: MockFixtures.tasks[2])
    }
    .environment(store)
    .task { await store.load() }
}
