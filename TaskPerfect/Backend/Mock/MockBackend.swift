import Foundation

/// In-memory backend with realistic fixtures. No network, no credentials.
///
/// This is not throwaway scaffolding — it earns its place three times over:
///
///  1. **Build the whole UI before writing any SOAP.** The EWS layer is the slowest,
///     fiddliest part of this project. Don't let it gate the part you want to look at.
///  2. **It keeps the abstraction honest.** If the UI compiles against this, no EWS
///     type has leaked upward.
///  3. **It is your App Review demo mode.** Reviewers can't reach your Exchange server,
///     and an app that shows a login wall they can't pass gets rejected under
///     Guideline 2.1. Wire a "Try the demo" button on the sign-in screen to this and
///     that problem disappears permanently.
public actor MockBackend: TaskBackend {

    public nonisolated let accountID: UUID
    public nonisolated let capabilities: BackendCapabilities = .exchangeEWS

    private var tasks: [String: TPTask] = [:]
    private var folders: [TPTaskList]
    private var categories: [TPCategory]
    private var version: Int = 0

    /// Which server version each item was last touched at, and a tombstone log
    /// for deletions. Real EWS keeps this behind an opaque SyncState string; the
    /// mock keeps it in the open so incremental sync can actually be tested
    /// rather than assumed.
    private var itemVersions: [String: Int] = [:]
    private var tombstones: [(itemID: String, version: Int)] = []

    /// EWS returns changes in pages. Keeping this small forces the sync loop to
    /// drain more than one page on a first run, which is where paging bugs hide.
    private let pageSize = 25

    /// Artificial latency so the UI's loading states get exercised. Set to 0 in tests.
    private let latency: Duration

    /// Fails every request. Use it to exercise your error paths in the simulator.
    private var failureMode: TaskBackendError?

    public init(
        accountID: UUID = UUID(),
        latency: Duration = .milliseconds(350),
        seeded: Bool = true
    ) {
        self.accountID = accountID
        self.latency = latency
        self.folders = [
            TPTaskList(folderID: "mock-tasks", displayName: "Tasks", isDefault: true),
            TPTaskList(folderID: "mock-projects", displayName: "Projects")
        ]
        self.categories = MockFixtures.categories
        if seeded {
            for task in MockFixtures.tasks {
                self.tasks[task.itemID] = task
                self.itemVersions[task.itemID] = 0
            }
        }
    }

    // MARK: Test controls

    public func setFailureMode(_ error: TaskBackendError?) {
        failureMode = error
    }

    public func reset() {
        tasks = Dictionary(uniqueKeysWithValues: MockFixtures.tasks.map { ($0.itemID, $0) })
        itemVersions = tasks.mapValues { _ in 0 }
        tombstones = []
        version = 0
        failureMode = nil
    }

    /// Simulate somebody editing a task in desktop Outlook, so a delta sync has
    /// something to find.
    public func simulateRemoteEdit(count: Int = 1) {
        for task in tasks.values.prefix(count) {
            version += 1
            var edited = task
            edited.changeKey = "ck-\(version)"
            edited.subject += " (edited elsewhere)"
            tasks[task.itemID] = edited
            itemVersions[task.itemID] = version
        }
    }

    // MARK: TaskBackend

    public func verifyConnection() async throws {
        try await pause()
    }

    public func taskFolders() async throws -> [TPTaskList] {
        try await pause()
        return folders.map { folder in
            var f = folder
            f.totalCount = tasks.values.filter { $0.folderID == folder.folderID }.count
            return f
        }
    }

    public func changes(in folderID: String, since token: SyncToken?) async throws -> TaskDelta {
        try await pause()

        let cursor = Cursor(token)
        let isFullResync = cursor.since == nil || cursor.since! > version

        let candidates: [TPTask]
        let deleted: [String]
        if isFullResync {
            candidates = tasks.values.filter { $0.folderID == folderID }
            deleted = []
        } else {
            let since = cursor.since!
            candidates = tasks.values.filter {
                $0.folderID == folderID && (itemVersions[$0.itemID] ?? 0) > since
            }
            deleted = tombstones.filter { $0.version > since }.map(\.itemID)
        }

        let ordered = candidates.sorted { (itemVersions[$0.itemID] ?? 0) < (itemVersions[$1.itemID] ?? 0) }
        let start = min(cursor.offset, ordered.count)
        let slice = Array(ordered[start..<min(start + pageSize, ordered.count)])
        let isLast = start + slice.count >= ordered.count

        return TaskDelta(
            upserted: slice,
            // Tombstones ride with the final page: a delete applied before its
            // matching edits arrive would resurrect the item on the next page.
            deletedItemIDs: isLast ? deleted : [],
            // Only commit to the new version once the whole set has been read,
            // otherwise an interrupted sync loses whatever it hadn't reached.
            nextToken: isLast
                ? Cursor(since: version, offset: 0).token
                : Cursor(since: cursor.since ?? -1, offset: start + slice.count).token,
            isFullResync: isFullResync,
            includesLastItemInRange: isLast
        )
    }

    /// Sync position: the version synced up to, plus how far into the current
    /// change set we've read.
    ///
    /// A version alone cannot page. Every item written in one batch shares a
    /// version, so a version-only cursor can never advance past them — the first
    /// sync would deliver one page and then declare itself finished. Real EWS
    /// hides the same two pieces of state inside its opaque SyncState string.
    private struct Cursor {
        var since: Int?
        var offset: Int

        init(since: Int?, offset: Int) {
            self.since = since
            self.offset = offset
        }

        init(_ token: SyncToken?) {
            guard let raw = token?.rawValue,
                  raw.hasPrefix("v"),
                  let dot = raw.firstIndex(of: "."),
                  let since = Int(raw[raw.index(after: raw.startIndex)..<dot]),
                  let offset = Int(raw[raw.index(dot, offsetBy: 2)...])
            else {
                self.since = nil
                self.offset = 0
                return
            }
            self.since = since
            self.offset = offset
        }

        var token: SyncToken { SyncToken(rawValue: "v\(since ?? -1).o\(offset)") }
    }

    public func create(_ task: TPTask, in folderID: String) async throws -> TPTask {
        try await pause()
        var stored = task
        version += 1
        stored.itemID = "mock-item-\(UUID().uuidString.prefix(8))"
        stored.changeKey = "ck-\(version)"
        itemVersions[stored.itemID] = version
        stored.folderID = folderID
        stored.lastModified = Date()
        stored.isDirty = false
        tasks[stored.itemID] = stored
        return stored
    }

    public func update(_ task: TPTask) async throws -> TPTask {
        try await pause()
        guard var existing = tasks[task.itemID] else {
            throw TaskBackendError.itemNotFound(itemID: task.itemID)
        }
        // Mirrors real optimistic concurrency: a stale ChangeKey is a conflict.
        guard existing.changeKey == task.changeKey else {
            throw TaskBackendError.conflict(itemID: task.itemID)
        }
        version += 1
        existing = task
        existing.changeKey = "ck-\(version)"
        itemVersions[task.itemID] = version
        existing.lastModified = Date()
        existing.isDirty = false
        tasks[task.itemID] = existing
        return existing
    }

    public func delete(itemID: String, changeKey: String) async throws {
        try await pause()
        guard tasks[itemID] != nil else {
            throw TaskBackendError.itemNotFound(itemID: itemID)
        }
        version += 1
        tombstones.append((itemID: itemID, version: version))
        itemVersions[itemID] = nil
        tasks[itemID] = nil
    }

    public func masterCategories() async throws -> [TPCategory] {
        try await pause()
        return categories
    }

    public func saveMasterCategories(_ updated: [TPCategory]) async throws {
        try await pause()
        categories = updated
    }

    // MARK: Helpers

    private func pause() async throws {
        if latency > .zero {
            try? await Task.sleep(for: latency)
        }
        if let failureMode { throw failureMode }
    }
}

// MARK: - Fixtures

public enum MockFixtures {

    public static let categories: [TPCategory] = [
        TPCategory(name: "Special",            colorIndex: 8),
        TPCategory(name: "Personal",           colorIndex: 1),
        TPCategory(name: "LMC Projects",       colorIndex: 4),
        TPCategory(name: "LMC Administration", colorIndex: 7),
        TPCategory(name: "LMC Misc",           colorIndex: 8),
        TPCategory(name: "LMC Lawsuit",        colorIndex: 10),
        TPCategory(name: "Friends",            colorIndex: 15),
        TPCategory(name: "Investors",          colorIndex: 5)
    ]

    /// An absolute date, for fixtures that should sit on a specific calendar day
    /// rather than drift with today.
    static func fixedDate(year: Int, month: Int, day: Int, hour: Int = 17) -> Date {
        var components = DateComponents()
        components.year = year
        components.month = month
        components.day = day
        components.hour = hour
        return Calendar.current.date(from: components) ?? Date()
    }

    /// Relative to now rather than to a clock hour — a reminder "3 hours ago"
    /// stays 3 hours ago whenever the app is opened, which a fixed hour doesn't.
    private static func hoursAgo(_ hours: Int) -> Date {
        Calendar.current.date(byAdding: .hour, value: -hours, to: Date()) ?? Date()
    }

    private static func date(_ dayOffset: Int, hour: Int = 17) -> Date {
        let cal = Calendar.current
        let base = cal.date(byAdding: .day, value: dayOffset, to: Date()) ?? Date()
        return cal.date(bySettingHour: hour, minute: 0, second: 0, of: base) ?? base
    }

    public static var tasks: [TPTask] {
        var result: [TPTask] = []

        var overdue = TPTask(
            itemID: "mock-item-0001",
            changeKey: "ck-1",
            folderID: "mock-tasks",
            subject: "Renew SSL certificate for the intranet",
            body: TPBody(content: "Expires end of month. Ticket #4471 with IT."),
            categories: ["Special", "Friends"],
            importance: .high,
            dueDate: date(-3),
            reminderDueBy: date(-4, hour: 9),
            reminderIsSet: true
        )
        overdue.setPercentComplete(25)
        overdue.isDirty = false
        result.append(overdue)

        result.append(TPTask(
            itemID: "mock-item-0002",
            changeKey: "ck-1",
            folderID: "mock-tasks",
            subject: "Submit Q3 expense report",
            categories: ["Personal"],
            importance: .normal,
            dueDate: date(0),
            totalWork: 45
        ))

        var inProgress = TPTask(
            itemID: "mock-item-0003",
            changeKey: "ck-1",
            folderID: "mock-tasks",
            subject: "Draft the vendor renewal summary",
            body: TPBody(content: "Compare current pricing against last year's contract."),
            categories: ["LMC Administration"],
            dueDate: date(2),
            totalWork: 180,
            actualWork: 60,
            companies: ["Intermedia"]
        )
        inProgress.setStatus(.inProgress)
        inProgress.setPercentComplete(40)
        inProgress.isDirty = false
        result.append(inProgress)

        let approval = TPTask(
            itemID: "mock-item-0004",
            changeKey: "ck-1",
            folderID: "mock-tasks",
            subject: "Approval on the new phone policy",
            categories: ["LMC Lawsuit", "LMC Misc"],
            dueDate: date(5),
            owner: "Operations"
        )
        result.append(approval)

        result.append(TPTask(
            itemID: "mock-item-0005",
            changeKey: "ck-1",
            folderID: "mock-tasks",
            subject: "Weekly backup verification",
            categories: ["LMC Projects"],
            startDate: date(1, hour: 8),
            dueDate: date(1),
            recurrence: TPRecurrence(
                pattern: .weekly(interval: 1, daysOfWeek: [.monday, .thursday]),
                range: .noEnd(start: date(-30))
            )
        ))

        // One fixture per frequency, so every branch of the editor and every
        // shortSummary variant is visible in the list without typing anything.
        result.append(TPTask(
            itemID: "mock-item-0010",
            changeKey: "ck-1",
            folderID: "mock-tasks",
            subject: "Check the server room temperature log",
            categories: ["LMC Administration"],
            dueDate: date(0, hour: 9),
            recurrence: TPRecurrence(
                pattern: .daily(interval: 1),
                range: .noEnd(start: date(-60))
            )
        ))

        result.append(TPTask(
            itemID: "mock-item-0011",
            changeKey: "ck-1",
            folderID: "mock-tasks",
            subject: "Reconcile the corporate card statement",
            categories: ["Personal"],
            importance: .high,
            dueDate: date(4),
            recurrence: TPRecurrence(
                pattern: .monthlyAbsolute(dayOfMonth: 5, interval: 1),
                range: .noEnd(start: date(-120))
            )
        ))

        result.append(TPTask(
            itemID: "mock-item-0012",
            changeKey: "ck-1",
            folderID: "mock-tasks",
            subject: "Run the quarterly access review",
            categories: ["Friends"],
            dueDate: date(11),
            recurrence: TPRecurrence(
                pattern: .monthlyRelative(ordinal: .first, weekday: .monday, interval: 3),
                range: .numbered(start: date(-90), occurrences: 8)
            )
        ))

        result.append(TPTask(
            itemID: "mock-item-0013",
            changeKey: "ck-1",
            folderID: "mock-tasks",
            subject: "Renew the business insurance policy",
            categories: ["Special"],
            importance: .high,
            dueDate: date(21),
            recurrence: TPRecurrence(
                pattern: .yearlyAbsolute(month: 9, dayOfMonth: 1),
                range: .noEnd(start: date(-340))
            )
        ))

        // Regenerating: the next one appears 30 days after this is completed,
        // not 30 days after it was due. Falling behind doesn't stack up copies.
        result.append(TPTask(
            itemID: "mock-item-0014",
            changeKey: "ck-1",
            folderID: "mock-tasks",
            subject: "Deep clean the break room fridge",
            categories: ["LMC Projects"],
            importance: .low,
            dueDate: date(6),
            recurrence: TPRecurrence(
                pattern: .regenerating(unit: .monthly, interval: 1),
                range: .noEnd(start: date(-30))
            )
        ))

        // Finished work at different times, so the Completed tab has an order
        // to show rather than a pile of identical timestamps.
        var done = TPTask(
            itemID: "mock-item-0006",
            changeKey: "ck-1",
            folderID: "mock-tasks",
            subject: "Order replacement laptop batteries",
            categories: ["LMC Projects"],
            dueDate: date(-1),
            billingInformation: "PO-88213"
        )
        done.setStatus(.completed, now: date(-1, hour: 11))
        done.isDirty = false
        result.append(done)

        var signedW9 = TPTask(
            itemID: "mock-item-0022", changeKey: "ck-1", folderID: "mock-tasks",
            subject: "Send the vendor the signed W-9",
            categories: ["Personal"], dueDate: date(-2)
        )
        signedW9.setStatus(.completed, now: date(0, hour: 10))
        signedW9.isDirty = false
        result.append(signedW9)

        var holiday = TPTask(
            itemID: "mock-item-0023", changeKey: "ck-1", folderID: "mock-tasks",
            subject: "Post the holiday schedule to the break room",
            categories: ["LMC Administration"],
            importance: .low, dueDate: date(-5)
        )
        holiday.setStatus(.completed, now: date(-4, hour: 15))
        holiday.isDirty = false
        result.append(holiday)

        var inspection = TPTask(
            itemID: "mock-item-0024", changeKey: "ck-1", folderID: "mock-tasks",
            subject: "Confirm the fire inspection appointment",
            categories: ["Friends"], importance: .high, dueDate: date(-6)
        )
        inspection.setStatus(.completed, now: date(-6, hour: 9))
        inspection.isDirty = false
        result.append(inspection)

        result.append(TPTask(
            itemID: "mock-item-0007",
            changeKey: "ck-1",
            folderID: "mock-tasks",
            subject: "Book conference room for the all-hands, confirm AV setup with facilities, and send the calendar invite to everyone on the distribution list",
            categories: ["LMC Administration"],
            importance: .low,
            dueDate: date(9)
        ))

        result.append(TPTask(
            itemID: "mock-item-0008",
            changeKey: "ck-1",
            folderID: "mock-tasks",
            subject: "Archive the 2024 project files",
            categories: ["LMC Projects"],
            dueDate: date(14)
        ))

        result.append(TPTask(
            itemID: "mock-item-0009",
            changeKey: "ck-1",
            folderID: "mock-projects",
            subject: "Task Perfect — verify EWS is enabled on our plan",
            body: TPBody(content: "Send one GetFolder request before building further."),
            categories: ["Special"],
            importance: .high,
            dueDate: date(1)
        ))

        // A few more past-due items so the Overdue tab shows real grouping
        // and sorting rather than a single lonely row.
        result.append(TPTask(
            itemID: "mock-item-0015", changeKey: "ck-1", folderID: "mock-tasks",
            subject: "Update the emergency contact sheet",
            categories: ["Friends"], dueDate: date(13)
        ))
        result.append(TPTask(
            itemID: "mock-item-0016", changeKey: "ck-1", folderID: "mock-tasks",
            subject: "Approve the printer maintenance quote",
            categories: ["Personal"], importance: .high, dueDate: date(4)
        ))
        result.append(TPTask(
            itemID: "mock-item-0017", changeKey: "ck-1", folderID: "mock-tasks",
            subject: "Chase the missing packing slip",
            categories: ["LMC Misc"],
            dueDate: date(2)
        ))
        var backup = TPTask(
            itemID: "mock-item-0018", changeKey: "ck-1", folderID: "mock-tasks",
            subject: "Back up the shared drive archive",
            categories: ["LMC Administration"], dueDate: date(-14)
        )
        backup.setPercentComplete(60)
        backup.isDirty = false
        result.append(backup)

        // Undated work — the "someday" pile the No Due Date tab exists for.
        result.append(TPTask(
            itemID: "mock-item-0019", changeKey: "ck-1", folderID: "mock-tasks",
            subject: "Research a replacement for the label printer",
            categories: ["LMC Administration"], importance: .low
        ))
        result.append(TPTask(
            itemID: "mock-item-0020", changeKey: "ck-1", folderID: "mock-tasks",
            subject: "Ask about bulk pricing on toner",
            categories: ["LMC Administration"]
        ))
        result.append(TPTask(
            itemID: "mock-item-0021", changeKey: "ck-1", folderID: "mock-tasks",
            subject: "Write up the new-hire onboarding checklist",
            categories: ["Friends"]
        ))

        let t30 = TPTask(
            itemID: "mock-item-0030",
            changeKey: "ck-1",
            folderID: "mock-tasks",
            subject: "Review the board packet before Thursday",
            categories: ["Special"],
            importance: .high,
            dueDate: date(2, hour: 17)
        )
        result.append(t30)

        let t31 = TPTask(
            itemID: "mock-item-0031",
            changeKey: "ck-1",
            folderID: "mock-tasks",
            subject: "Approve the updated org chart",
            categories: ["Special"],
            dueDate: date(7, hour: 17)
        )
        result.append(t31)

        let t32 = TPTask(
            itemID: "mock-item-0032",
            changeKey: "ck-1",
            folderID: "mock-tasks",
            subject: "Draft talking points for the annual meeting",
            categories: ["Special"],
            dueDate: date(9, hour: 17),
            totalWork: 120
        )
        result.append(t32)

        let t33 = TPTask(
            itemID: "mock-item-0033",
            changeKey: "ck-1",
            folderID: "mock-tasks",
            subject: "Renew the notary commission",
            categories: ["Special"],
            importance: .low,
            dueDate: date(45, hour: 17),
            recurrence: TPRecurrence(pattern: .yearlyAbsolute(month: 6, dayOfMonth: 1), range: .noEnd(start: date(-60)))
        )
        result.append(t33)

        let t34 = TPTask(
            itemID: "mock-item-0034",
            changeKey: "ck-1",
            folderID: "mock-tasks",
            subject: "Schedule the annual physical",
            categories: ["Personal"],
            dueDate: date(12, hour: 9)
        )
        result.append(t34)

        let t35 = TPTask(
            itemID: "mock-item-0035",
            changeKey: "ck-1",
            folderID: "mock-tasks",
            subject: "Renew vehicle registration",
            categories: ["Personal"],
            importance: .high,
            dueDate: date(21, hour: 17),
            recurrence: TPRecurrence(pattern: .yearlyAbsolute(month: 6, dayOfMonth: 1), range: .noEnd(start: date(-60)))
        )
        result.append(t35)

        let t36 = TPTask(
            itemID: "mock-item-0036",
            changeKey: "ck-1",
            folderID: "mock-tasks",
            subject: "Pick up dry cleaning",
            categories: ["Personal"],
            importance: .low,
            dueDate: date(0, hour: 17)
        )
        result.append(t36)

        let t37 = TPTask(
            itemID: "mock-item-0037",
            changeKey: "ck-1",
            folderID: "mock-tasks",
            subject: "Book flights for the reunion",
            categories: ["Personal"],
            dueDate: date(26)
        )
        result.append(t37)

        let t38 = TPTask(
            itemID: "mock-item-0038",
            changeKey: "ck-1",
            folderID: "mock-tasks",
            subject: "Replace the furnace filter",
            categories: ["Personal"],
            importance: .low,
            dueDate: date(30, hour: 17),
            recurrence: TPRecurrence(pattern: .regenerating(unit: .monthly, interval: 1), range: .noEnd(start: date(-60)))
        )
        result.append(t38)

        var t39 = TPTask(
            itemID: "mock-item-0039",
            changeKey: "ck-1",
            folderID: "mock-tasks",
            subject: "Finalize the warehouse layout drawings",
            categories: ["LMC Projects"],
            importance: .high,
            dueDate: date(3, hour: 17)
        )
        t39.setPercentComplete(25)
        t39.isDirty = false
        result.append(t39)

        let t40 = TPTask(
            itemID: "mock-item-0040",
            changeKey: "ck-1",
            folderID: "mock-tasks",
            subject: "Collect bids for the roof replacement",
            categories: ["LMC Projects"],
            dueDate: date(7, hour: 17)
        )
        result.append(t40)

        let t41 = TPTask(
            itemID: "mock-item-0041",
            changeKey: "ck-1",
            folderID: "mock-tasks",
            subject: "Update the project milestone tracker",
            categories: ["LMC Projects"],
            dueDate: date(3, hour: 17),
            recurrence: TPRecurrence(pattern: .weekly(interval: 1, daysOfWeek: [.monday]), range: .noEnd(start: date(-60)))
        )
        result.append(t41)

        let t42 = TPTask(
            itemID: "mock-item-0042",
            changeKey: "ck-1",
            folderID: "mock-tasks",
            subject: "Close out the Phase 1 punch list",
            categories: ["LMC Projects"],
            dueDate: date(14, hour: 17),
            totalWork: 240
        )
        result.append(t42)

        var t43 = TPTask(
            itemID: "mock-item-0043",
            changeKey: "ck-1",
            folderID: "mock-tasks",
            subject: "Archive completed project photos",
            categories: ["LMC Projects"],
            importance: .low,
            dueDate: date(-9, hour: 17)
        )
        t43.setStatus(.completed, now: date(-3, hour: 14))
        t43.isDirty = false
        result.append(t43)

        let t44 = TPTask(
            itemID: "mock-item-0044",
            changeKey: "ck-1",
            folderID: "mock-tasks",
            subject: "File the quarterly payroll return",
            categories: ["LMC Administration"],
            importance: .high,
            dueDate: date(5, hour: 17)
        )
        result.append(t44)

        let t45 = TPTask(
            itemID: "mock-item-0045",
            changeKey: "ck-1",
            folderID: "mock-tasks",
            subject: "Update the employee handbook",
            categories: ["LMC Administration"],
            dueDate: date(15)
        )
        result.append(t45)

        let t46 = TPTask(
            itemID: "mock-item-0046",
            changeKey: "ck-1",
            folderID: "mock-tasks",
            subject: "Reconcile the petty cash box",
            categories: ["LMC Administration"],
            importance: .low,
            dueDate: date(1, hour: 17),
            recurrence: TPRecurrence(pattern: .monthlyAbsolute(dayOfMonth: 1, interval: 1), range: .noEnd(start: date(-60)))
        )
        result.append(t46)

        let t47 = TPTask(
            itemID: "mock-item-0047",
            changeKey: "ck-1",
            folderID: "mock-tasks",
            subject: "Renew the business license",
            categories: ["LMC Administration"],
            importance: .high,
            dueDate: date(10, hour: 17)
        )
        result.append(t47)

        var t48 = TPTask(
            itemID: "mock-item-0048",
            changeKey: "ck-1",
            folderID: "mock-tasks",
            subject: "Order office supplies",
            categories: ["LMC Administration"],
            dueDate: date(-4, hour: 17)
        )
        t48.setStatus(.completed, now: date(-2, hour: 14))
        t48.isDirty = false
        result.append(t48)

        let t49 = TPTask(
            itemID: "mock-item-0049",
            changeKey: "ck-1",
            folderID: "mock-tasks",
            subject: "Sort the storage room shelves",
            categories: ["LMC Misc"],
            importance: .low,
            dueDate: date(9)
        )
        result.append(t49)

        let t50 = TPTask(
            itemID: "mock-item-0050",
            changeKey: "ck-1",
            folderID: "mock-tasks",
            subject: "Return the leased projector",
            categories: ["LMC Misc"],
            dueDate: date(4, hour: 17)
        )
        result.append(t50)

        let t51 = TPTask(
            itemID: "mock-item-0051",
            changeKey: "ck-1",
            folderID: "mock-tasks",
            subject: "Update the emergency phone list",
            categories: ["LMC Misc"],
            dueDate: date(8, hour: 17)
        )
        result.append(t51)

        let t52 = TPTask(
            itemID: "mock-item-0052",
            changeKey: "ck-1",
            folderID: "mock-tasks",
            subject: "Test the backup generator",
            categories: ["LMC Misc"],
            dueDate: date(18, hour: 9),
            recurrence: TPRecurrence(pattern: .monthlyAbsolute(dayOfMonth: 1, interval: 3), range: .noEnd(start: date(-60)))
        )
        result.append(t52)

        let t53 = TPTask(
            itemID: "mock-item-0053",
            changeKey: "ck-1",
            folderID: "mock-tasks",
            subject: "Send documents to counsel",
            categories: ["LMC Lawsuit"],
            importance: .high,
            dueDate: date(1, hour: 17)
        )
        result.append(t53)

        var t54 = TPTask(
            itemID: "mock-item-0054",
            changeKey: "ck-1",
            folderID: "mock-tasks",
            subject: "Review the deposition transcript",
            categories: ["LMC Lawsuit"],
            importance: .high,
            dueDate: date(6, hour: 17),
            totalWork: 180
        )
        t54.setPercentComplete(40)
        t54.isDirty = false
        result.append(t54)

        let t55 = TPTask(
            itemID: "mock-item-0055",
            changeKey: "ck-1",
            folderID: "mock-tasks",
            subject: "Compile the exhibit list",
            categories: ["LMC Lawsuit"],
            importance: .high,
            dueDate: date(6, hour: 17)
        )
        result.append(t55)

        let t56 = TPTask(
            itemID: "mock-item-0056",
            changeKey: "ck-1",
            folderID: "mock-tasks",
            subject: "Calendar the mediation date",
            categories: ["LMC Lawsuit"],
            dueDate: date(25, hour: 17)
        )
        result.append(t56)

        var t57 = TPTask(
            itemID: "mock-item-0057",
            changeKey: "ck-1",
            folderID: "mock-tasks",
            subject: "Log this month's legal invoices",
            categories: ["LMC Lawsuit"],
            dueDate: date(-7, hour: 17)
        )
        t57.setStatus(.completed, now: date(-5, hour: 14))
        t57.isDirty = false
        result.append(t57)

        let t58 = TPTask(
            itemID: "mock-item-0058",
            changeKey: "ck-1",
            folderID: "mock-tasks",
            subject: "Send Marcus a birthday card",
            categories: ["Friends"],
            dueDate: date(8, hour: 17)
        )
        result.append(t58)

        let t59 = TPTask(
            itemID: "mock-item-0059",
            changeKey: "ck-1",
            folderID: "mock-tasks",
            subject: "Plan the summer cookout",
            categories: ["Friends"],
            importance: .low,
            dueDate: date(16, hour: 17)
        )
        result.append(t59)

        let t60 = TPTask(
            itemID: "mock-item-0060",
            changeKey: "ck-1",
            folderID: "mock-tasks",
            subject: "Return Dana's ladder",
            categories: ["Friends"],
            importance: .low,
            dueDate: date(5, hour: 17)
        )
        result.append(t60)

        let t61 = TPTask(
            itemID: "mock-item-0061",
            changeKey: "ck-1",
            folderID: "mock-tasks",
            subject: "Confirm the fishing trip dates",
            categories: ["Friends"],
            dueDate: date(31)
        )
        result.append(t61)

        // No category — these drive the No Category pill
        result.append(TPTask(
            itemID: "mock-item-0074", changeKey: "ck-1", folderID: "mock-tasks",
            subject: "Replace the lobby entry mat",
            dueDate: MockFixtures.fixedDate(year: 2026, month: 9, day: 4)
        ))
        result.append(TPTask(
            itemID: "mock-item-0075", changeKey: "ck-1", folderID: "mock-tasks",
            subject: "Get a quote for repaving the side lot",
            dueDate: MockFixtures.fixedDate(year: 2026, month: 9, day: 17),
            totalWork: 60
        ))

        // Investors
        var investorUpdate = TPTask(
            itemID: "mock-item-0070", changeKey: "ck-1", folderID: "mock-tasks",
            subject: "Prepare the quarterly investor update",
            categories: ["Investors"], importance: .high,
            dueDate: date(6), totalWork: 240
        )
        investorUpdate.setPercentComplete(30)
        investorUpdate.isDirty = false
        result.append(investorUpdate)

        result.append(TPTask(
            itemID: "mock-item-0071", changeKey: "ck-1", folderID: "mock-tasks",
            subject: "Circulate the refreshed cap table",
            categories: ["Investors"], dueDate: date(12)
        ))
        result.append(TPTask(
            itemID: "mock-item-0072", changeKey: "ck-1", folderID: "mock-tasks",
            subject: "Schedule calls with the Q4 prospects",
            categories: ["Investors"], dueDate: date(19)
        ))
        result.append(TPTask(
            itemID: "mock-item-0073", changeKey: "ck-1", folderID: "mock-tasks",
            subject: "Draft the annual letter to shareholders",
            categories: ["Investors"], importance: .low,
            dueDate: date(33), totalWork: 180
        ))

        // ── Reminder fixtures ────────────────────────────────────────────────
        // Enough to exercise the on-open banner in both states. Three qualify
        // (set, past, not done); the last two deliberately don't, so the count
        // can be checked rather than assumed.
        var reminderSoon = TPTask(
            itemID: "mock-item-0080", changeKey: "ck-1", folderID: "mock-tasks",
            subject: "Call the insurance broker back",
            body: TPBody(content: "He needs the vehicle list before the renewal quote."),
            categories: ["LMC Administration"], importance: .high,
            dueDate: date(0), reminderDueBy: hoursAgo(3), reminderIsSet: true
        )
        reminderSoon.isDirty = false
        result.append(reminderSoon)

        var reminderYesterday = TPTask(
            itemID: "mock-item-0081", changeKey: "ck-1", folderID: "mock-tasks",
            subject: "Confirm Thursday's delivery window",
            categories: ["Personal"],
            dueDate: date(1), reminderDueBy: date(-1, hour: 8), reminderIsSet: true
        )
        reminderYesterday.isDirty = false
        result.append(reminderYesterday)

        // No due date, but a reminder — the combination that catches naive
        // implementations keying reminders off the due date.
        var reminderUndated = TPTask(
            itemID: "mock-item-0082", changeKey: "ck-1", folderID: "mock-tasks",
            subject: "Ask Ivelisse about the storage unit lease",
            categories: ["Special"],
            reminderDueBy: date(-2, hour: 16), reminderIsSet: true
        )
        reminderUndated.isDirty = false
        result.append(reminderUndated)

        // Future: set, but not due — must not appear.
        var reminderFuture = TPTask(
            itemID: "mock-item-0083", changeKey: "ck-1", folderID: "mock-tasks",
            subject: "Renew the domain registration",
            categories: ["LMC Administration"],
            dueDate: date(9), reminderDueBy: date(7, hour: 9), reminderIsSet: true
        )
        reminderFuture.isDirty = false
        result.append(reminderFuture)

        // Past reminder on a finished task — must not appear either.
        var reminderDone = TPTask(
            itemID: "mock-item-0084", changeKey: "ck-1", folderID: "mock-tasks",
            subject: "File the completed safety inspection form",
            categories: ["Personal"],
            dueDate: date(-2), reminderDueBy: date(-2, hour: 9), reminderIsSet: true
        )
        reminderDone.setStatus(.completed, now: date(-2, hour: 11))
        reminderDone.isDirty = false
        result.append(reminderDone)

        return result
    }
}
