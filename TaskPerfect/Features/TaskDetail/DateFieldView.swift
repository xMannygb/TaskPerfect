import SwiftUI

/// A date row where **None** is a first-class choice, not the absence of one.
///
/// The toggle-plus-picker pattern this replaces made "no date" a side effect of
/// flipping a switch — you couldn't see it as an option, only infer it. Here None
/// sits in the same row of choices as Today and Tomorrow, reads back in the
/// collapsed row, and takes one tap from anywhere.
public struct DateFieldView: View {

    let title: String
    @Binding var date: Date?

    /// Reminders need a time; due and start dates don't.
    var includesTime: Bool = false

    /// Hour used when a quick option turns None into a real date.
    var defaultHour: Int = 17

    @State private var isExpanded = false

    public init(
        title: String,
        date: Binding<Date?>,
        includesTime: Bool = false,
        defaultHour: Int = 17
    ) {
        self.title = title
        self._date = date
        self.includesTime = includesTime
        self.defaultHour = defaultHour
    }

    public var body: some View {
        Group {
            Button {
                withAnimation(.snappy(duration: 0.2)) { isExpanded.toggle() }
            } label: {
                HStack {
                    Text(title)
                        .foregroundStyle(Theme.Palette.ink)
                    Spacer()
                    Text(display)
                        .font(Theme.numeric(16))
                        .foregroundStyle(date == nil ? Theme.Palette.slate : Theme.Palette.ink)
                    Image(systemName: "chevron.right")
                        .font(.caption2)
                        .foregroundStyle(Theme.Palette.slate)
                        .rotationEffect(.degrees(isExpanded ? 90 : 0))
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("\(title), \(display)")
            .accessibilityHint("Opens date options")

            if isExpanded {
                quickOptions

                if date != nil {
                    DatePicker(
                        title,
                        selection: Binding(
                            get: { date ?? seed(daysFromNow: 0) },
                            set: { date = $0 }
                        ),
                        displayedComponents: includesTime ? [.date, .hourAndMinute] : [.date]
                    )
                    .datePickerStyle(.graphical)
                    .labelsHidden()
                    .tint(Theme.Palette.ink)
                }
            }
        }
    }

    // MARK: Quick options

    private var quickOptions: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                chip("None", isSelected: date == nil) { date = nil }
                chip("Today", isSelected: isSameDay(0)) { date = seed(daysFromNow: 0) }
                chip("Tomorrow", isSelected: isSameDay(1)) { date = seed(daysFromNow: 1) }
                chip("Next week", isSelected: isSameDay(7)) { date = seed(daysFromNow: 7) }
            }
            .padding(.vertical, 2)
        }
        .scrollClipDisabled()
    }

    private func chip(_ label: String, isSelected: Bool, action: @escaping () -> Void) -> some View {
        Button {
            withAnimation(.snappy(duration: 0.18)) { action() }
        } label: {
            Text(label)
                .font(.subheadline)
                .padding(.horizontal, 14)
                .padding(.vertical, 7)
                .background(
                    Capsule().fill(isSelected ? Theme.Palette.ink : Theme.Palette.canvas)
                )
                .foregroundStyle(isSelected ? .white : Theme.Palette.ink)
        }
        .buttonStyle(.plain)
    }

    // MARK: Helpers

    private var display: String {
        guard let date else { return "None" }
        let calendar = Calendar.current
        let dayPart: String
        if calendar.isDateInToday(date) { dayPart = "Today" }
        else if calendar.isDateInTomorrow(date) { dayPart = "Tomorrow" }
        else if calendar.isDateInYesterday(date) { dayPart = "Yesterday" }
        else { dayPart = date.formatted(.dateTime.weekday(.abbreviated).month().day().year()) }

        guard includesTime else { return dayPart }
        return "\(dayPart), \(date.formatted(date: .omitted, time: .shortened))"
    }

    private func seed(daysFromNow days: Int) -> Date {
        let calendar = Calendar.current
        let base = calendar.date(byAdding: .day, value: days, to: Date()) ?? Date()
        return calendar.date(bySettingHour: defaultHour, minute: 0, second: 0, of: base) ?? base
    }

    private func isSameDay(_ daysFromNow: Int) -> Bool {
        guard let date else { return false }
        return Calendar.current.isDate(date, inSameDayAs: seed(daysFromNow: daysFromNow))
    }
}
