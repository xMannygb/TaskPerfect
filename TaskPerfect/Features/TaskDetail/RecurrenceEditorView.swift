import SwiftUI

/// Recurrence editor: daily, weekly, monthly, yearly, plus Outlook's
/// regenerating mode and all three range types.
///
/// The live preview at the bottom is the point of the screen. Recurrence rules are
/// easy to misread — "the last Friday of every 3 months" means nothing until you
/// see three real dates. Everything above the preview is inputs; the preview is
/// the answer.
public struct RecurrenceEditorView: View {

    @Environment(\.dismiss) private var dismiss

    /// Anchor for the pattern — the task's due date, or today if it has none.
    private let anchor: Date
    private let onSave: (TPRecurrence?) -> Void

    @State private var isOn: Bool
    @State private var frequency: TPRecurrence.Frequency
    @State private var interval: Int
    @State private var weekdays: Set<TPRecurrence.Weekday>
    @State private var monthlyMode: MonthlyMode
    @State private var dayOfMonth: Int
    @State private var ordinal: TPRecurrence.Ordinal
    @State private var relativeWeekday: TPRecurrence.Weekday
    @State private var yearMonth: Int
    @State private var regenerates: Bool
    @State private var endMode: EndMode
    @State private var occurrences: Int
    @State private var endDate: Date

    private enum MonthlyMode: String, CaseIterable { case onDay = "On a day", onWeekday = "On a weekday" }
    private enum EndMode: String, CaseIterable { case never = "Never", after = "After", on = "On date" }

    public init(current: TPRecurrence?, anchor: Date, onSave: @escaping (TPRecurrence?) -> Void) {
        self.anchor = anchor
        self.onSave = onSave

        let cal = Calendar.current
        let comps = cal.dateComponents([.day, .month, .weekday], from: anchor)

        _isOn = State(initialValue: current != nil)
        _frequency = State(initialValue: current?.frequency ?? .weekly)
        _interval = State(initialValue: current?.interval ?? 1)
        _regenerates = State(initialValue: current?.isRegenerating ?? false)

        var days: Set<TPRecurrence.Weekday> = [.from(calendarIndex: comps.weekday ?? 1)]
        var mode: MonthlyMode = .onDay
        var dom = comps.day ?? 1
        var ord: TPRecurrence.Ordinal = .first
        var relDay: TPRecurrence.Weekday = .from(calendarIndex: comps.weekday ?? 1)
        var month = comps.month ?? 1

        switch current?.pattern {
        case .weekly(_, let d): days = d
        case .monthlyAbsolute(let day, _): mode = .onDay; dom = day
        case .monthlyRelative(let o, let w, _): mode = .onWeekday; ord = o; relDay = w
        case .yearlyAbsolute(let m, let day): month = m; dom = day; mode = .onDay
        case .yearlyRelative(let o, let w, let m): month = m; ord = o; relDay = w; mode = .onWeekday
        default: break
        }

        _weekdays = State(initialValue: days)
        _monthlyMode = State(initialValue: mode)
        _dayOfMonth = State(initialValue: dom)
        _ordinal = State(initialValue: ord)
        _relativeWeekday = State(initialValue: relDay)
        _yearMonth = State(initialValue: month)

        switch current?.range {
        case .numbered(_, let n):
            _endMode = State(initialValue: .after)
            _occurrences = State(initialValue: n)
            _endDate = State(initialValue: cal.date(byAdding: .year, value: 1, to: anchor) ?? anchor)
        case .endDate(_, let e):
            _endMode = State(initialValue: .on)
            _occurrences = State(initialValue: 10)
            _endDate = State(initialValue: e)
        default:
            _endMode = State(initialValue: .never)
            _occurrences = State(initialValue: 10)
            _endDate = State(initialValue: cal.date(byAdding: .year, value: 1, to: anchor) ?? anchor)
        }
    }

    public var body: some View {
        Form {
            Section {
                Toggle("Repeat this task", isOn: $isOn.animation())
            }

            if isOn {
                frequencySection
                detailSection
                regenerateSection
                endSection
                previewSection
            }
        }
        .navigationTitle("Repeat")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("Done") {
                    onSave(isOn ? built : nil)
                    dismiss()
                }
                .fontWeight(.semibold)
            }
        }
    }

    // MARK: Sections

    private var frequencySection: some View {
        Section {
            Picker("Frequency", selection: $frequency.animation()) {
                ForEach(TPRecurrence.Frequency.allCases, id: \.self) { f in
                    Text(f.rawValue).tag(f)
                }
            }
            .pickerStyle(.segmented)
            .listRowInsets(EdgeInsets(top: 10, leading: 12, bottom: 10, trailing: 12))

            if frequency != .yearly {
                Stepper(value: $interval, in: 1...99) {
                    HStack {
                        Text("Every")
                        Spacer()
                        Text(interval == 1
                             ? frequency.unitNoun
                             : "\(interval) \(frequency.unitNoun)s")
                            .font(Theme.numeric(16, weight: .medium))
                            .foregroundStyle(Theme.Palette.slate)
                    }
                }
            }
        }
    }

    @ViewBuilder
    private var detailSection: some View {
        switch frequency {
        case .daily:
            EmptyView()

        case .weekly:
            Section("On these days") {
                HStack(spacing: 6) {
                    ForEach(TPRecurrence.Weekday.allCases, id: \.self) { day in
                        Button {
                            toggle(day)
                        } label: {
                            Text(day.initial)
                                .font(.system(size: 14, weight: .semibold))
                                .frame(maxWidth: .infinity, minHeight: 38)
                                .background(
                                    Circle().fill(weekdays.contains(day)
                                                  ? Theme.Palette.ink : Theme.Palette.canvas)
                                )
                                .foregroundStyle(weekdays.contains(day) ? .white : Theme.Palette.slate)
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel(day.rawValue)
                        .accessibilityAddTraits(weekdays.contains(day) ? .isSelected : [])
                    }
                }
                .padding(.vertical, 4)

                if weekdays.isEmpty {
                    Text("Pick at least one day, or this repeats weekly on the due date.")
                        .font(.caption)
                        .foregroundStyle(Theme.Palette.slate)
                }
            }

        case .monthly:
            Section {
                Picker("Mode", selection: $monthlyMode.animation()) {
                    ForEach(MonthlyMode.allCases, id: \.self) { Text($0.rawValue).tag($0) }
                }
                .pickerStyle(.segmented)
                .listRowInsets(EdgeInsets(top: 10, leading: 12, bottom: 10, trailing: 12))

                if monthlyMode == .onDay {
                    Stepper(value: $dayOfMonth, in: 1...31) {
                        HStack {
                            Text("Day of month")
                            Spacer()
                            Text("\(dayOfMonth)")
                                .font(Theme.numeric(16, weight: .medium))
                                .foregroundStyle(Theme.Palette.slate)
                        }
                    }
                    if dayOfMonth > 28 {
                        Text("Short months use their last day.")
                            .font(.caption)
                            .foregroundStyle(Theme.Palette.slate)
                    }
                } else {
                    ordinalPickers
                }
            }

        case .yearly:
            Section {
                Picker("Month", selection: $yearMonth) {
                    ForEach(1...12, id: \.self) { m in
                        Text(TPRecurrence.monthName(m)).tag(m)
                    }
                }
                Picker("Mode", selection: $monthlyMode.animation()) {
                    ForEach(MonthlyMode.allCases, id: \.self) { Text($0.rawValue).tag($0) }
                }
                .pickerStyle(.segmented)
                .listRowInsets(EdgeInsets(top: 10, leading: 12, bottom: 10, trailing: 12))

                if monthlyMode == .onDay {
                    Stepper(value: $dayOfMonth, in: 1...31) {
                        HStack {
                            Text("Day")
                            Spacer()
                            Text("\(dayOfMonth)")
                                .font(Theme.numeric(16, weight: .medium))
                                .foregroundStyle(Theme.Palette.slate)
                        }
                    }
                } else {
                    ordinalPickers
                }
            }
        }
    }

    private var ordinalPickers: some View {
        Group {
            Picker("Which", selection: $ordinal) {
                ForEach(TPRecurrence.Ordinal.allCases, id: \.self) { Text($0.rawValue).tag($0) }
            }
            Picker("Day", selection: $relativeWeekday) {
                ForEach(TPRecurrence.Weekday.allCases, id: \.self) { Text($0.rawValue).tag($0) }
            }
        }
    }

    private var regenerateSection: some View {
        Section {
            Toggle("Count from completion", isOn: $regenerates.animation())
        } footer: {
            Text(regenerates
                 ? "The next task appears \(interval) \(frequency.unitNoun)\(interval == 1 ? "" : "s") after you finish this one — useful when falling behind shouldn't stack up overdue copies."
                 : "The schedule is fixed. Finishing late doesn't move the next due date.")
        }
    }

    private var endSection: some View {
        Section("Ends") {
            Picker("Ends", selection: $endMode.animation()) {
                ForEach(EndMode.allCases, id: \.self) { Text($0.rawValue).tag($0) }
            }
            .pickerStyle(.segmented)
            .listRowInsets(EdgeInsets(top: 10, leading: 12, bottom: 10, trailing: 12))

            switch endMode {
            case .never:
                EmptyView()
            case .after:
                Stepper(value: $occurrences, in: 2...365) {
                    HStack {
                        Text("Occurrences")
                        Spacer()
                        Text("\(occurrences)")
                            .font(Theme.numeric(16, weight: .medium))
                            .foregroundStyle(Theme.Palette.slate)
                    }
                }
            case .on:
                DatePicker("Last date", selection: $endDate, displayedComponents: .date)
            }
        }
    }

    private var previewSection: some View {
        Section("Next occurrences") {
            let dates = RecurrenceEngine.upcoming(from: anchor, recurrence: built, count: 4)
            if dates.isEmpty {
                Text("This pattern produces no further dates.")
                    .font(.subheadline)
                    .foregroundStyle(Theme.Palette.overdue)
            } else {
                ForEach(Array(dates.enumerated()), id: \.offset) { index, date in
                    HStack {
                        Text(date.formatted(.dateTime.weekday(.wide).month().day().year()))
                            .font(Theme.numeric(15))
                            .foregroundStyle(index == 0 ? Theme.Palette.ink : Theme.Palette.slate)
                        Spacer()
                        if index == 0 {
                            Text("next").font(.caption).foregroundStyle(Theme.Palette.slate)
                        }
                    }
                }
                if regenerates {
                    Text("Estimated — regenerating tasks depend on when each one is completed.")
                        .font(.caption)
                        .foregroundStyle(Theme.Palette.slate)
                }
            }
        }
    }

    // MARK: Build

    private func toggle(_ day: TPRecurrence.Weekday) {
        if weekdays.contains(day) { weekdays.remove(day) } else { weekdays.insert(day) }
    }

    private var built: TPRecurrence {
        let pattern: TPRecurrence.Pattern

        if regenerates {
            pattern = .regenerating(unit: frequency, interval: interval)
        } else {
            switch frequency {
            case .daily:
                pattern = .daily(interval: interval)
            case .weekly:
                pattern = .weekly(interval: interval, daysOfWeek: weekdays)
            case .monthly:
                pattern = monthlyMode == .onDay
                    ? .monthlyAbsolute(dayOfMonth: dayOfMonth, interval: interval)
                    : .monthlyRelative(ordinal: ordinal, weekday: relativeWeekday, interval: interval)
            case .yearly:
                pattern = monthlyMode == .onDay
                    ? .yearlyAbsolute(month: yearMonth, dayOfMonth: dayOfMonth)
                    : .yearlyRelative(ordinal: ordinal, weekday: relativeWeekday, month: yearMonth)
            }
        }

        let range: TPRecurrence.Range
        switch endMode {
        case .never:  range = .noEnd(start: anchor)
        case .after:  range = .numbered(start: anchor, occurrences: occurrences)
        case .on:     range = .endDate(start: anchor, end: endDate)
        }

        return TPRecurrence(pattern: pattern, range: range)
    }
}

#Preview {
    NavigationStack {
        RecurrenceEditorView(current: nil, anchor: Date()) { _ in }
    }
}
