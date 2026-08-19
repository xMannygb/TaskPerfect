import Foundation

/// Turns a task into something that can leave the app.
///
/// Two representations, shared together:
///
/// - **Text** for the message body — readable in any mail client, and what the
///   system printer lays out for Print or Save as PDF.
/// - **An `.ics` file** (`VTODO`) attached, so a recipient can import it into
///   Outlook, Reminders or most task apps as a task of their own.
///
/// The `.ics` is a snapshot, not a subscription. Nothing links back, no status
/// flows returning, and ownership doesn't change — deliberately unlike Exchange
/// task assignment, which creates an obligation and takes the task away from
/// you.
enum TaskShareExport {

    // MARK: Readable text

    /// Only lines that have content, so an undated task with no category
    /// doesn't print a column of empty labels.
    static func text(for task: TPTask, categoryNames: [String] = []) -> String {
        var lines: [String] = [task.subject.isEmpty ? "(No subject)" : task.subject, ""]

        func add(_ label: String, _ value: String?) {
            guard let value, !value.isEmpty else { return }
            lines.append("\(label.padding(toLength: 13, withPad: " ", startingAt: 0))\(value)")
        }

        add("Due:", task.dueDate.map { Self.long.string(from: $0) })
        add("Start:", task.startDate.map { Self.long.string(from: $0) })
        if !task.categories.isEmpty {
            add("Category:", task.categories.joined(separator: ", "))
        }
        if !task.assignee.isEmpty {
            add("Assigned to:", task.companies.joined(separator: ", "))
        }
        if task.importance == .high { add("Priority:", "High") }
        if task.recurrence != nil { add("Repeats:", task.recurrence?.summary) }

        if task.isComplete {
            add("Completed:", task.completeDate.map { Self.long.string(from: $0) } ?? "Yes")
        } else {
            // Percent is noise at 0; at 100 the task would be complete.
            // Rounded: percentComplete is a Double, and "40.0%" reads wrong.
            let percent = Int(task.percentComplete.rounded())
            add("Status:", percent > 0 && percent < 100
                ? "\(task.status.displayName) (\(percent)%)"
                : task.status.displayName)
        }

        // Formatting is dropped — bullets survive as "• ", colors and fonts
        // don't. Sharing a formatted note as plain text is the trade for having
        // one path that works in every mail client.
        let notes = task.body.plainText.trimmingCharacters(in: .whitespacesAndNewlines)
        if !notes.isEmpty {
            lines.append("")
            lines.append(notes)
        }

        return lines.joined(separator: "\n")
    }

    // MARK: iCalendar

    /// A `VTODO`, which Outlook and Reminders import as a task.
    ///
    /// Categories are included but won't carry their colors — iCalendar has no
    /// equivalent of Outlook's category palette, so the recipient gets the names
    /// against whatever colors their own list uses.
    static func icsData(for task: TPTask) -> Data? {
        var lines = [
            "BEGIN:VCALENDAR",
            "VERSION:2.0",
            "PRODID:-//Task Perfect//EN",
            "CALSCALE:GREGORIAN",
            "BEGIN:VTODO",
            "UID:\(task.localID.uuidString)",
            "DTSTAMP:\(stamp(Date()))",
            "SUMMARY:\(escape(task.subject))"
        ]

        if let due = task.dueDate { lines.append("DUE:\(stamp(due))") }
        if let start = task.startDate { lines.append("DTSTART:\(stamp(start))") }
        if !task.categories.isEmpty {
            lines.append("CATEGORIES:\(task.categories.map(escape).joined(separator: ","))")
        }

        let notes = task.body.plainText.trimmingCharacters(in: .whitespacesAndNewlines)
        if !notes.isEmpty { lines.append("DESCRIPTION:\(escape(notes))") }

        // iCalendar priority runs 1–9, low numbers being urgent.
        switch task.importance {
        case .high:   lines.append("PRIORITY:1")
        case .low:    lines.append("PRIORITY:9")
        case .normal: break
        }

        lines.append("PERCENT-COMPLETE:\(Int(task.percentComplete.rounded()))")
        lines.append("STATUS:\(task.isComplete ? "COMPLETED" : "NEEDS-ACTION")")
        if task.isComplete, let done = task.completeDate {
            lines.append("COMPLETED:\(stamp(done))")
        }

        lines.append("END:VTODO")
        lines.append("END:VCALENDAR")

        // CRLF, not LF: RFC 5545 requires it, and Outlook is strict about it
        // where Apple's importers are forgiving.
        return lines.joined(separator: "\r\n").data(using: .utf8)
    }

    /// Written to a temp file because the share sheet attaches files by URL, and
    /// the filename is what the recipient sees.
    static func icsFile(for task: TPTask) -> URL? {
        guard let data = icsData(for: task) else { return nil }
        let safe = task.subject
            .components(separatedBy: CharacterSet.alphanumerics.union(.whitespaces).inverted)
            .joined()
            .trimmingCharacters(in: .whitespaces)
        let name = (safe.isEmpty ? "Task" : String(safe.prefix(40))) + ".ics"
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(name)
        do {
            try data.write(to: url, options: .atomic)
            return url
        } catch {
            return nil
        }
    }

    /// Text plus the `.ics`, in that order.
    ///
    /// Order matters: the share sheet previews the first item, so the readable
    /// text is what a recipient sees in the message body, with the file attached
    /// alongside. Reversed, mail apps tend to show a bare attachment and an
    /// empty body.
    static func shareItems(for task: TPTask) -> [Any] {
        var items: [Any] = [text(for: task)]
        if let file = icsFile(for: task) { items.append(file) }
        return items
    }

    // MARK: Formatting

    private static let long: DateFormatter = {
        let f = DateFormatter()
        f.dateStyle = .full
        f.timeStyle = .none
        return f
    }()

    /// UTC, per RFC 5545. A floating local time would shift the due date for a
    /// recipient in another timezone.
    private static func stamp(_ date: Date) -> String {
        let f = DateFormatter()
        f.dateFormat = "yyyyMMdd'T'HHmmss'Z'"
        f.timeZone = TimeZone(identifier: "UTC")
        return f.string(from: date)
    }

    /// Commas, semicolons and backslashes are separators in iCalendar, and a
    /// newline has to be written as a literal `\n`.
    private static func escape(_ raw: String) -> String {
        raw.replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: ";", with: "\\;")
            .replacingOccurrences(of: ",", with: "\\,")
            .replacingOccurrences(of: "\n", with: "\\n")
    }
}
