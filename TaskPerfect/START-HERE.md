# Start here

Task Perfect is an internal iPhone app for this organization's Intermedia Hosted
Exchange 2016 mailbox — Outlook tasks over EWS, including Categories and their
colors. Not a public App Store product.

**State of things:** 49 Swift files plus two test files, a complete SwiftUI app running against a mock
backend, with offline caching and a durable change queue that both work. The EWS
network layer does not exist yet. There is no Xcode project yet either.

---

## Read this before you build

**None of the Swift has ever been compiled.** Not once, by anyone. It was written
in an environment with no Swift toolchain, so every file — including the most
recent edits to `PendingChange.swift`, `LocalStore.swift`, `Reachability.swift`
and the whole of `Tests/` — has been reviewed by eye and never by a compiler.

This is the single biggest risk in the handoff and the first thing you will hit.
Say it out loud now so that nobody reads the first build error as their own setup
mistake and loses an hour before suspecting the code.

What that means in practice:

- **Budget a session for first-build errors.** Expect type mismatches, a missing
  `import`, an exhaustive `switch` that isn't, an access-level problem. Ordinary
  compiler work, not design work.
- **The design has been thought about carefully; the syntax has not been checked.**
  When you hit an error, the fix is usually local. If a fix seems to require
  changing how something *works*, stop — read the relevant section of `README.md`
  first, because the reasoning is probably recorded there and worth not undoing.
- **`Tests/` is unverified twice over** — never compiled, never run, and written by
  reading the implementation rather than executing it. See `Tests/README.md`.
- **The prototype is the opposite case.** `task-perfect-prototype.html` has been
  exercised in a real browser; its behavior is verified where the Swift's is not.
  Where the two disagree about what should happen, the prototype is the better
  evidence — see `PARITY.md`.

---

## Read in this order

| | | |
|---|---|---|
| 1 | **`PROJECT-SETUP.md`** | Make it build. Xcode target settings, the `Info.plist` key that crashes the app if you skip it, the signing decision. Start your day here. |
| 2 | **`BEFORE-EWS.md`** | Before writing any network code. What has been established against the real mailbox by testing, and the one operation still unproven. |
| 3 | **`BACKEND-CONTRACT.md`** | Before writing `EWSBackend`. Every method of the `TaskBackend` protocol with its callers, what they expect back, and what breaks if it's wrong. |
| 4 | `README.md` | Reference, 1,300 lines. Every design decision and the reasoning behind it. Not a start-to-finish read — search it when you wonder why something is the way it is. |
| 5 | `PARITY.md` | When the Swift and the prototype seem to disagree. Where they're most likely to have drifted, and which one to trust. |

`../task-perfect-prototype.html` is the whole app in one browser file, no build
step. Open it in Safari to see intended behavior without waiting on a compile.
It is kept in sync with the Swift code, so a change to one belongs in both.

## The three things most likely to trip you up

1. **`NSFaceIDUsageDescription` must be in `Info.plist`.** Absent it, iOS
   terminates the app the first time biometric unlock is selected — a crash, not
   a failed prompt, and one that no simulator run will surface unless somebody
   touches that setting. `PROJECT-SETUP.md` §3.
2. **The Swift 6 actor boundary is load-bearing.** `LocalStore` is a
   `@ModelActor`; `TaskStore` is `@MainActor`. SwiftData `@Model` objects must not
   cross between them — that is why `pendingChanges()` returns `QueuedChange`
   snapshots. `PROJECT-SETUP.md` §5 has the detail.
3. **The `CategoryList` write is unproven.** Reading the mailbox's master category
   list works. Writing it has never been attempted, and category colors, renames
   and deletes all depend on it. Test it early. `BEFORE-EWS.md`.

## The seam

`Domain/Protocols/TaskBackend.swift` is the only place the app meets a server.
`MockBackend` implements it today; `EWSBackend` will implement it next, and
swapping them is one line in `Session.makeStore()`. **`BACKEND-CONTRACT.md` is the
full specification** — every method, every caller, every failure mode.

Nothing in `Domain/`, `Features/` or `Persistence/` may reference a type from
`Backend/EWS/`. If a view file ever mentions a SOAP envelope, the abstraction has
leaked — treat it as a build-breaking bug. That rule is the reason the swap is one
line, and it is the only rule in the project worth being rigid about.
