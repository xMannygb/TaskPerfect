# The TaskBackend contract

What `EWSBackend` has to satisfy, and what breaks if each piece is wrong.

`Domain/Protocols/TaskBackend.swift` is the only place the app meets a server.
Everything above it — `TaskStore`, every view, the offline cache, the change queue
— is written against this protocol and has no idea what a SOAP envelope is.
`MockBackend` implements it today. Swapping in `EWSBackend` is one line in
`Session.makeStore()`.

This file exists so you can write that implementation without reading 12,000 lines
to work out what the callers actually expect. It was compiled from the call sites,
not from intentions.

**Every caller of every method is in `Persistence/TaskStore.swift`.** Nothing else
in the project touches the backend. That is by design and worth preserving: it
means the blast radius of a protocol change is one file.

---

## 1. The eleven methods

### `var accountID: UUID`

| | |
|---|---|
| **Called by** | Nothing, currently |
| **Expected** | Stable for the lifetime of the account |
| **If wrong** | Nothing today. It exists for a future multi-account build; return a value derived from the mailbox address rather than a fresh `UUID()` each launch, or that future gets harder. |

### `var capabilities: BackendCapabilities`

| | |
|---|---|
| **Called by** | `TaskStore.capabilities` (line 161), which five views read — see §2 |
| **Expected** | `.exchangeEWS` for this backend. Constant; read on every view render, so it must be cheap and must not vary between calls. |
| **If wrong** | Fields silently disappear from the task editor, or appear and then drop data on save. |

### `func verifyConnection() async throws`

| | |
|---|---|
| **Called by** | **Nothing yet** — the sign-in flow doesn't call it |
| **Expected** | A cheap round trip proving credentials and reachability. Fail fast; a long timeout here strands someone on a spinner. |
| **If wrong** | Nothing breaks today, but wiring this into `SignInView` is worth doing while you build the SOAP layer — right now a bad password isn't discovered until the first sync. |
| **Suggested shape** | `GetFolder` on the distinguished `tasks` folder. Same request `VerifyEWS/getfolder.xml` sends. |

### `func taskFolders() async throws -> [TPTaskList]`

| | |
|---|---|
| **Called by** | `load()` (line 198), concurrently with `masterCategories()` |
| **Expected** | Every task folder in the mailbox. `isDefault` **must** be true for exactly one — `load()` picks the active folder by `first(where: \.isDefault)`, falling back to `first`. |
| **If wrong** | No folder marked default means the app silently syncs whichever folder came back first. On a mailbox with several task folders, the user sees someone's idea of a task list but not necessarily their own. |
| **EWS** | `GetFolder` with `DistinguishedFolderId Id="tasks"`, plus `FindFolder` for the rest. `totalCount` and `unreadCount` are read from the folder shape; nothing depends on them yet. |

### `func changes(in:since:) async throws -> TaskDelta`

The most important method in the protocol. Called from `load()` (line 209) and
`syncChanges()` (line 280).

| | |
|---|---|
| **Expected** | An incremental delta against `token`. `nil` token means "give me everything." |
| **`nextToken`** | **Store verbatim, never parse.** The paging bug found in `MockBackend` came from treating the token as structured data. It carries a cursor; the client's only job is to hand it back unchanged. |
| **`includesLastItemInRange`** | `false` means more pages. `syncChanges()` loops calling again with `nextToken` until it's `true`, capped at 50 iterations. **Return `false` when EWS says `IncludesLastItemInRange=false` or changes are silently dropped** — the next sync starts from a token claiming they were already seen, so they never arrive at all. |
| **`isFullResync`** | `true` makes `TaskStore` clear the local store for the folder *and* re-read `masterCategories()`. Use it when the server hands back a fresh sync state rather than a delta. |
| **Deletions** | `deletedItemIDs` carries EWS `ItemId` values, not `localID`s. `LocalStore.deleteTasks(itemIDs:)` matches on `itemID`. |
| **`syncStateInvalid`** | Throw this — don't return an empty delta — when the server rejects the token. `syncChanges()` catches it, clears the token and falls back to `load()`. Treated as a normal path, not an error, and it is never shown to the user. |
| **If wrong** | Wrong paging loses changes invisibly. A parsed-and-rebuilt token can appear to work for weeks and then fail on an edge the parser didn't anticipate. |

### `func create(_:in:) async throws -> TPTask`

| | |
|---|---|
| **Called by** | The queue drain (line 338) and the immediate-push path (line 379) |
| **Expected** | The stored task **with `itemID` and `changeKey` populated** by the server |
| **If wrong** | The return value is written straight back into the local store and the in-memory array. Return the input unchanged and the task looks created but has no server identity — every later update fails, and the queue retries forever until it exhausts at 10 attempts and silently drops the change. |
| **Note** | `localID` must survive the round trip. `TaskStore` matches the response to the local row by `localID`; a fresh one orphans the local copy and produces a duplicate. |

### `func update(_:) async throws -> TPTask`

| | |
|---|---|
| **Called by** | Queue drain (339), immediate push (378), `pushTask(at:)` (789) |
| **Expected** | The updated task with a **new** `changeKey` |
| **`conflict`** | Throw `TaskBackendError.conflict(itemID:)` when the `changeKey` is stale. `TaskStore` drops the queued change and lets the next pull bring the server's copy in — the server wins. Retrying blindly would fail forever on the same stale key. |
| **If wrong** | Returning the old `changeKey` makes the *next* update conflict. The user sees an edit revert for no visible reason. |

### `func delete(itemID:changeKey:) async throws`

| | |
|---|---|
| **Called by** | Queue drain only (line 328) |
| **Expected** | Hard delete, or move to Deleted Items — your call, but decide and write it down |
| **`itemNotFound`** | Throw it when the item is already gone. `TaskStore` treats that as success and removes the queued change. Anything else leaves the queue retrying a delete that can never succeed. |

### `func masterCategories() async throws -> [TPCategory]`

| | |
|---|---|
| **Called by** | `load()` (199) and `syncChanges()` on full resync (285) |
| **Expected** | The mailbox master category list with colors. `colorIndex` is 0–24; `-1` means no color. |
| **`guid`** | Round-trip it. Desktop Outlook treats a changed GUID as a different category. |
| **EWS** | `GetUserConfiguration` for `CategoryList` in the **Calendar** folder — not Tasks. **This is proven working against the real mailbox.** |
| **If wrong** | Colors fall back to uncolored, which the app renders as a hairline rather than failing. Degrades rather than breaks. |

### `func saveMasterCategories(_:) async throws`

**The one unproven operation. Build and test this third, not last.** See
`BEFORE-EWS.md`.

| | |
|---|---|
| **Called by** | `pushCategories(rollingBackTo:)` (line 776), which every category add / rename / recolor / delete funnels through |
| **Expected** | Replace the list wholesale. Whole-list rather than per-item on purpose: EWS stores the categories as one XML blob in a single hidden folder-associated item, so every change is a read-modify-write of the entire thing. Modeling it as "add one category" would hide a clobber risk the caller needs to see. |
| **Failure is handled** | `TaskStore` rolls the in-memory list back to a snapshot and surfaces the error. So a server refusal degrades rather than corrupting — but every category feature stops working. |
| **If it turns out the server refuses the write** | The fallback is real but modest: names still sync (they live on the task items), colors become device-local, and Outlook shows uncolored names. Worth discovering before the category screens are wired to a live backend rather than after. Set `supportsCategoryManagement: false` and the management UI hides itself — see §2. |
| **Rename cascade** | The caller marks every tagged task dirty and queues an update *after* this call succeeds. Renaming is therefore N+1 round trips, not one. |

---

## 2. The eleven capability flags

`BackendCapabilities` is not decoration. Five view sites read it, and its purpose
is to stop a future backend silently discarding data the user typed.

| Flag | Read at | Effect when false |
|---|---|---|
| `supportsEffortTracking` | `TaskDetailView:38` | Effort section hidden |
| `supportsMileageAndBilling` | `TaskDetailView:39` | Mileage and billing hidden |
| `supportsPercentComplete` | `TaskDetailView:351` | % complete slider hidden |
| `supportsCompanies` | `TaskDetailView:421` | **Assigned To hidden** |
| `supportsCategoryManagement` | `SettingsView:179` | Categories screen hidden entirely |
| `supportsRichTextBody` | *not yet read* | — |
| `supportsRecurrence` | *not yet read* | — |
| `supportsRegeneratingRecurrence` | *not yet read* | — |
| `supportsSensitivity` | *not yet read* | — |
| `supportsMultipleFolders` | *not yet read* | — |
| `supportsServerSideSearch` | *not yet read* | — |

Six flags exist but nothing consults them. That is a gap worth closing while you
are in this code: they are the mechanism that makes a Microsoft 365 migration cost
nothing later, and a flag nobody reads provides no protection. `.microsoftGraphToDo`
is already defined as the contrasting set.

**`supportsCategoryManagement` has a second use**: if the `CategoryList` write turns
out to be refused by the server, setting it false is the honest, one-line response —
the management UI disappears instead of offering controls that silently fail.

---

## 3. Errors, and which ones retry

`TaskBackendError.isRetryable` decides whether the change queue backs off and tries
again or surfaces to the user. Map SOAP faults deliberately; the default is not to
retry.

| Retryable — queue backs off and retries | Not retryable — surfaced to the user |
|---|---|
| `networkUnavailable` | `authenticationFailed` |
| `serverUnreachable(host:)` | `ewsDisabledForMailbox` |
| `conflict(itemID:)` | `itemNotFound(itemID:)` |
| `syncStateInvalid` | `malformedResponse(detail:)` |
| | `soapFault(code:message:)` |
| | `unsupportedByBackend(feature:)` |
| | `duplicateCategory(name:)` |
| | `notConfigured` |

Backoff is capped exponential with jitter, and a change is dropped after 10
attempts — the task keeps its dirty flag, so the work stays visible to the user
even though the queue gave up.

Two mappings worth getting right rather than guessing:

- **403 or a SOAP fault indicating EWS is off for the plan** → `ewsDisabledForMailbox`,
  not `soapFault`. It has its own user-facing message pointing at the provider.
- **A stale `changeKey`** → `conflict(itemID:)`, not `soapFault`. The store has real
  recovery behavior for it.

---

## 4. What the seam guarantees, and the rule that keeps it

Nothing in `Domain/`, `Features/` or `Persistence/` may reference a type from
`Backend/EWS/`. If a view file ever mentions a SOAP envelope, the abstraction has
leaked — treat it as a build-breaking bug.

That rule is why the swap is one line, and it is the only rule in the project worth
being rigid about. The practical version while you work: if you find yourself
wanting to add a parameter to a `TaskBackend` method so a view can pass something
EWS-shaped, the answer is almost always that the mapping belongs inside
`EWSBackend`.

---

## 5. What is already exercised, so you inherit it working

`MockBackend` is not a stub. It simulates tombstones, paging, `changeKey` conflicts
and full-resync signalling, and it has a `setFailureMode(_:)` hook. So the machinery
around your new layer — the queue, the rollback, the conflict path, the page loop —
has been driven through those states already.

Two consequences:

1. **Build `EWSBackend` against `MockBackend`'s behavior as the specification.**
   Where the two disagree, one of them is wrong about Exchange, and it is worth
   finding out which before shipping rather than after.
2. **Keep `MockBackend` working.** It is what makes demo mode, the SwiftUI previews
   and any future test suite run without a mailbox. Do not delete it once
   `EWSBackend` exists.

Finally, from `BEFORE-EWS.md` and worth repeating here: **capture real XML from this
mailbox as you go.** Hosted Exchange deployments differ from Microsoft's
documentation in small ways that only show up at runtime, and a saved response from
this server beats the spec every time.
