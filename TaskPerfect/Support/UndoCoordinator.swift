import Foundation
import Observation

/// Holds deletes for a few seconds so they can be taken back.
///
/// **Delays the send rather than reversing it.** The row disappears immediately,
/// but nothing reaches the change queue until the window expires — so undo has
/// nothing to undo, it just cancels. A true reversal would need Exchange to hand
/// the item back from Deleted Items, which EWS can do but with real caveats:
/// retention varies by server, a hard delete leaves nothing, and the restored
/// item returns with a new `ItemId` that no longer matches the local record.
@MainActor
@Observable
public final class UndoCoordinator {

    /// One staged deletion. Kept as a list so several can share a bar.
    struct Entry {
        let restore: () -> Void
        let commit: () async -> Void
    }

    public struct Pending: Identifiable {
        public let id: UUID
        public let message: String
        public let count: Int
        var entries: [Entry]
    }

    /// Non-nil while the bar is showing.
    public private(set) var pending: Pending?

    public var window: Duration = .seconds(5)

    /// Whether a second deletion joins the first or replaces it.
    ///
    /// Tasks batch: deleting three in a row and changing your mind almost always
    /// means wanting all three back. Categories don't — two staged category
    /// deletions can touch overlapping task lists, and untangling which restore
    /// owns which tag isn't worth it for something this rare.
    public let batches: Bool

    private var timer: Task<Void, Never>?

    public init(window: Duration = .seconds(5), batches: Bool = false) {
        self.window = window
        self.batches = batches
    }

    /// Stage a deletion.
    ///
    /// - Parameter describe: builds the bar's text from the running count, so a
    ///   batch can say "3 tasks deleted" rather than repeating the last subject.
    public func stage(
        describe: (Int) -> String,
        restore: @escaping () -> Void,
        commit: @escaping () async -> Void
    ) {
        let entry = Entry(restore: restore, commit: commit)

        if batches, var current = pending {
            // Join the existing bar and restart its clock. The first item gets a
            // longer reprieve than it would alone, which is the right trade.
            current.entries.append(entry)
            pending = Pending(
                id: current.id,
                message: describe(current.entries.count),
                count: current.entries.count,
                entries: current.entries
            )
        } else {
            // Not batching, or nothing staged: flush whatever was there rather
            // than dropping it, or the earlier delete would never be sent.
            Task { await commitNow() }
            pending = Pending(id: UUID(), message: describe(1), count: 1, entries: [entry])
        }

        startTimer()
    }

    private func startTimer() {
        timer?.cancel()
        timer = Task { [weak self] in
            guard let window = self?.window else { return }
            try? await Task.sleep(for: window)
            guard !Task.isCancelled else { return }
            await self?.commitNow()
        }
    }

    /// Take it all back. Does nothing once the window has closed.
    public func undo() {
        guard let entry = pending else { return }
        timer?.cancel()
        timer = nil
        pending = nil
        // Newest first, so restores that touch the same records unwind in the
        // order they were applied.
        for item in entry.entries.reversed() { item.restore() }
    }

    /// Send it for real. Called when the window expires, when the user dismisses
    /// the bar, and — critically — when the app goes to the background: a pending
    /// delete that survived a quit would look deleted, not be, and have no
    /// visible way back.
    public func commitNow() async {
        guard let entry = pending else { return }
        timer?.cancel()
        timer = nil
        pending = nil
        for item in entry.entries { await item.commit() }
    }

    public var hasPending: Bool { pending != nil }
}
