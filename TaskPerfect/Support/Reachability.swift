import Foundation
import Network
import Observation

/// Watches the network path so the queue can drain the moment a connection
/// returns, rather than waiting for the user to notice and tap sync.
@MainActor
@Observable
public final class Reachability {

    public private(set) var isOnline = true
    /// Cellular with Low Data Mode, or a constrained hotspot. Worth knowing
    /// before starting a full resync over someone's metered connection.
    public private(set) var isConstrained = false
    public private(set) var isExpensive = false

    /// Fires on a transition from offline to online — the moment to drain.
    public var onReconnect: (() -> Void)?

    /// `nonisolated` so `deinit` can cancel it. `deinit` is never actor-isolated,
    /// so reading a main-actor property from it is an error under Swift 6 — and
    /// `NWPathMonitor` is documented as safe to cancel from any thread, so the
    /// `unsafe` here is a statement about the compiler's knowledge rather than
    /// about the code.
    nonisolated(unsafe) private let monitor = NWPathMonitor()
    /// `DispatchQueue` is already `Sendable`, so this one needs no annotation.
    private let queue = DispatchQueue(label: "reachability")

    public init() {
        monitor.pathUpdateHandler = { [weak self] path in
            Task { @MainActor in
                guard let self else { return }
                let wasOffline = !self.isOnline
                self.isOnline = path.status == .satisfied
                self.isConstrained = path.isConstrained
                self.isExpensive = path.isExpensive
                // Only on the transition. A path update while already online
                // (Wi-Fi to cellular, say) shouldn't restart a sync mid-flight.
                if wasOffline && self.isOnline { self.onReconnect?() }
            }
        }
        monitor.start(queue: queue)
    }

    deinit { monitor.cancel() }
}
