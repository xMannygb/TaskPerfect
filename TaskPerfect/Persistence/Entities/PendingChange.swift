import Foundation
import SwiftData

/// One outbound change waiting for the server.
///
/// Persisted, which is the whole point: an edit made on a plane has to survive
/// the app being killed before it ever reaches Exchange.
@Model
public final class PendingChange {

    public enum Operation: String, Codable, Sendable {
        case create, update, delete
    }

    @Attribute(.unique) public var id: UUID
    /// Which task this concerns. The payload is read fresh from `CachedTask` at
    /// send time rather than snapshotted here, so a later edit rides along on an
    /// already-queued change instead of needing its own entry.
    public var taskLocalID: UUID
    public var operationRaw: String
    public var queuedAt: Date

    /// Delete needs these because the row is gone from the store by then.
    public var itemID: String
    public var changeKey: String

    public var attemptCount: Int
    /// Don't try again before this. Exponential backoff, so a server that's down
    /// isn't hammered every few seconds.
    public var nextAttemptAt: Date
    public var lastError: String?

    public var operation: Operation {
        Operation(rawValue: operationRaw) ?? .update
    }

    public init(
        operation: Operation,
        taskLocalID: UUID,
        itemID: String = "",
        changeKey: String = ""
    ) {
        self.id = UUID()
        self.taskLocalID = taskLocalID
        self.operationRaw = operation.rawValue
        self.queuedAt = Date()
        self.itemID = itemID
        self.changeKey = changeKey
        self.attemptCount = 0
        self.nextAttemptAt = .distantPast
        self.lastError = nil
    }

    public var isReady: Bool { nextAttemptAt <= Date() }

    /// Capped exponential backoff with jitter.
    ///
    /// The cap stops a long outage pushing the next attempt hours out — when the
    /// network returns, five minutes is long enough to be polite and short
    /// enough that the user doesn't notice. Jitter keeps a queue of changes from
    /// retrying in lockstep and arriving as one burst.
    public func recordFailure(_ message: String) {
        attemptCount += 1
        lastError = message
        let base = min(pow(2.0, Double(attemptCount)), 300)
        let jitter = Double.random(in: 0.85...1.15)
        nextAttemptAt = Date().addingTimeInterval(base * jitter)
    }

    /// Give up after enough tries that the problem is clearly not transient.
    /// The task keeps its dirty flag, so the work is still visible to the user.
    public var isExhausted: Bool { attemptCount >= 10 }

    /// A value copy safe to hand outside `LocalStore`.
    public var snapshot: QueuedChange {
        QueuedChange(
            id: id,
            operation: operation,
            taskLocalID: taskLocalID,
            itemID: itemID,
            changeKey: changeKey,
            nextAttemptAt: nextAttemptAt
        )
    }
}

// MARK: - Snapshot

/// An immutable copy of one queued change, for callers outside `LocalStore`.
///
/// `PendingChange` is a SwiftData `@Model`, so it is a reference tied to the
/// `ModelContext` that fetched it — not `Sendable`, and not safe to read from
/// another actor. `TaskStore` runs on the main actor and only ever needs these
/// six values, so it gets copies instead of the live objects. Mutations still go
/// back through `LocalStore` by `id`, which keeps the context the single owner.
public struct QueuedChange: Sendable, Identifiable, Hashable {

    public let id: UUID
    public let operation: PendingChange.Operation
    public let taskLocalID: UUID
    public let itemID: String
    public let changeKey: String
    public let nextAttemptAt: Date

    public init(
        id: UUID,
        operation: PendingChange.Operation,
        taskLocalID: UUID,
        itemID: String,
        changeKey: String,
        nextAttemptAt: Date
    ) {
        self.id = id
        self.operation = operation
        self.taskLocalID = taskLocalID
        self.itemID = itemID
        self.changeKey = changeKey
        self.nextAttemptAt = nextAttemptAt
    }

    /// Still inside its backoff window, so leave it alone this pass.
    public var isReady: Bool { nextAttemptAt <= Date() }
}
