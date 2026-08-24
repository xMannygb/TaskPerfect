import SwiftUI
import SwiftData

@main
struct TaskPerfectApp: App {
    @State private var session = Session()

    /// One container for the app's lifetime. Failing to build it is fatal —
    /// running without persistence would silently drop offline work, which is
    /// worse than not starting.
    // `fileprivate`, not `private`: Session.makeStore() below reads this, and it is
    // a separate type in this file, which `private` does not reach.
    fileprivate static let container: ModelContainer = {
        do {
            return try ModelContainer(
                for: CachedTask.self, CachedCategory.self,
                     CachedSyncState.self, PendingChange.self
            )
        } catch {
            fatalError("Couldn't open the local store: \(error)")
        }
    }()

    var body: some Scene {
        WindowGroup {
            Group {
                switch session.state {
                case .locked:
                    // Credentials are stored but not yet released. Shown while
                    // the biometric prompt is up, and if it's dismissed.
                    LockedView()
                case .signedOut:
                    SignInView { credentials in
                        session.signIn(credentials: credentials)
                    }
                case .signedIn(let store):
                    TaskListView()
                        .environment(store)
                }
            }
            .environment(session)
            .task { await session.restore() }
        }
    }
}

/// App-level authentication state.
@MainActor
@Observable
final class Session {

    enum State {
        case signedOut
        case locked
        case signedIn(TaskStore)
    }

    private(set) var state: State = .signedOut
    private(set) var unlockError: String?

    /// One instance for the app's lifetime, so preferences survive sign-out.
    let settings = AppSettings()

    private var username: String?

    // MARK: Launch

    /// Decide what to show on launch, based on the lock mode and what's stored.
    func restore() async {
        guard case .signedOut = state else { return }
        guard let saved = CredentialStore.rememberedUsername,
              CredentialStore.hasStoredPassword(username: saved)
        else { return }   // nothing remembered — show sign-in

        username = saved

        switch settings.lockMode {
        case .password:
            // Shouldn't happen; a stored password in this mode means the setting
            // changed without cleanup. Remove it rather than trusting it.
            CredentialStore.delete(username: saved)
        case .staySignedIn:
            await openMailbox(username: saved)
        case .biometric:
            state = .locked
            await authenticate()
        }
    }

    /// Run the biometric check and open the mailbox on success.
    func authenticate() async {
        unlockError = nil
        guard let username else { state = .signedOut; return }

        switch await AppLock.unlock() {
        case .success:
            await openMailbox(username: username)
        case .cancelled:
            state = .locked          // stay put; the user can retry
        case .unavailable(let reason):
            // Never strand someone outside their own mailbox — fall back to the
            // password screen rather than leaving them stuck on a failed prompt.
            unlockError = reason
            state = .signedOut
        }
    }

    private func openMailbox(username: String) async {
        // Reading the password is itself the biometric gate under `.biometric`,
        // so it must not run on the main actor.
        let password = await Task.detached(priority: .userInitiated) {
            CredentialStore.password(
                username: username,
                prompt: "Unlock Task Perfect"
            )
        }.value

        guard password != nil else {
            state = .signedOut
            return
        }
        // TODO: hand `password` to EWSBackend once the SOAP layer exists.
        state = .signedIn(makeStore())
    }

    // MARK: Sign in

    func signIn(credentials: (username: String, password: String)?) {
        guard let credentials else {
            // Demo mode — sample data, no network. Useful for showing the app
            // without a mailbox, and the only path App Review would see if this
            // ever went through a review process. Note it is an unauthenticated
            // route into the UI: see PROJECT-SETUP.md before shipping.
            state = .signedIn(makeStore())
            return
        }

        username = credentials.username
        CredentialStore.rememberedUsername = credentials.username
        CredentialStore.save(
            password: credentials.password,
            username: credentials.username,
            mode: settings.lockMode
        )

        // TODO: replace MockBackend with EWSBackend. Build order and the one
        // unproven operation (the CategoryList write) are in BEFORE-EWS.md.
        state = .signedIn(makeStore())
    }

    /// Re-store the password under the protection the new mode requires.
    ///
    /// Called when the setting changes. Switching to `.password` deletes it;
    /// switching between `.biometric` and `.staySignedIn` needs a rewrite,
    /// because the Keychain access control is fixed at write time.
    func applyLockMode(_ mode: AppLockMode) {
        guard let username else { return }

        if mode == .password {
            CredentialStore.delete(username: username)
            return
        }

        // Read under the old protection, write back under the new one.
        Task.detached(priority: .userInitiated) {
            guard let password = CredentialStore.password(
                username: username,
                prompt: "Update how Task Perfect unlocks"
            ) else { return }
            CredentialStore.save(password: password, username: username, mode: mode)
        }
    }

    /// Build a store backed by the on-disk cache, then load from it before any
    /// network call — that's what makes a cold offline launch show the full list.
    private func makeStore() -> TaskStore {
        let store = TaskStore(
            backend: MockBackend(),
            settings: settings,
            local: LocalStore(modelContainer: TaskPerfectApp.container)
        )
        Task { await store.loadFromDisk() }
        return store
    }

    func signOut() {
        if let username { CredentialStore.delete(username: username) }
        CredentialStore.rememberedUsername = nil
        username = nil
        state = .signedOut
    }
}
