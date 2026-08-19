# Before you write the EWS layer

Findings established by testing against the real mailbox, not assumed from
documentation. They're here because they change what the SOAP layer should do,
and because rediscovering them costs a day each.

---

## EWS is confirmed enabled

Three independent confirmations:

- **Intermedia confirmed it** on the plan directly.
- **The endpoint responds.** `https://east.exch092.serverdata.net/EWS/Exchange.asmx`
  prompts for credentials in Safari — that path is EWS-specific and doesn't exist
  for ActiveSync or Graph.
- **A third-party client uses it.** Task Task on iPhone syncs this mailbox over
  exactly that path.

`VerifyEWS/verify.sh` is now redundant. It was written to answer this question
and the question has better answers.

---

## Authentication works on the e-mail address alone

Task Task's Domain field is **empty** — marked Optional — and it authenticates
as `peter@lastmile.net` with no domain.

So `ServerConfig.qualifiedUsername` sends the bare address untouched, and a blank
domain yields the bare username rather than a leading backslash, which Exchange
rejects. Domain is prefilled with `EXCH092` but is not required.

Task Task exposes no authentication-mode picker, so it is negotiating. **The SOAP
layer should negotiate too** rather than hardcoding NTLM.

---

## Reading the master category list works

A category created in Outlook — name *and* color — appeared in Task Task on the
phone. That's the `CategoryList` FAI item being read successfully over EWS
against this mailbox. It also confirms preset color indices round-trip, which is
what the "Not Outlook Compatible" split in the palette depends on.

## Writing it is the one unproven operation

**Test this first.** Not last.

A category created in Task Task did **not** appear in Outlook's category list.
Making a task with it produced an orphan: Outlook saw the name, with no color.
That's a client that reads the list and never writes it.

Task Task's omission may be a deliberate choice — the blob is fiddly — or it may
be that the server refuses the write. **Nothing we have distinguishes those two
cases**, and our category management depends on the write: colors, renames that
cascade, deletes.

If the write is refused, the fallback is real but modest: names still sync,
colors become device-local, Outlook shows uncolored names. Worth knowing before
the category screens are wired to a live backend rather than after.

Deleting a category in Outlook did not remove it from Task Task, but that's
likely Task Task caching rather than a server behavior. Our design re-reads the
list on full resync.

---

## Sync is delta-only, and should stay that way

Every path calls `syncChanges()`, which uses `backend.changes(in:since:)` with
the stored token. A full `load()` happens in exactly three cases, each a
deliberate fallback:

- first run, no token yet
- the server rejecting the token (`syncStateInvalid`)
- a delta arriving marked `isFullResync`

**Store `SyncState` verbatim and never parse it.** The paging bug found in
`MockBackend` came from treating the token as structured data. It carries a
cursor; the client's job is to hand it back unchanged.

`resetCache()` in Settings → Account is the user-facing escape hatch: it pushes
pending changes, clears the token and store, and pulls again. An action, not a
mode — there's deliberately no "full sync" toggle.

---

## Assigned To is stored in `Companies`

`Owner` is server-set and **read-only**. Exchange sets it to the mailbox owner
and only names someone else on a formally assigned task, so it can't carry "who's
responsible". The app displays it, doesn't write it.

**Assigned To maps to `Companies`** — an editable string array EWS exposes and
Outlook shows on the Details tab. Untested against this mailbox; the round trip
is worth five minutes before anything else depends on it.

---

## Reminders: nothing fires yet

- **The model is complete.** `reminderDueBy`, `reminderIsSet`, and
  `RecurrenceEngine` already carries the reminder to the next occurrence keeping
  its offset from the due date.
- **No notification is ever scheduled.** `UNUserNotificationCenter` appears only
  in `AppBadge`, for the badge permission.
- **iOS allows 64 pending notifications per app**, and silently drops the excess.
  This is the real design constraint: schedule only the nearest ones and top up
  when the app opens.
- **Sound is `.default`**, deliberately — no bundled audio, no picker. A custom
  sound overrides whatever the person chose system-wide.
- Exchange stores **one** reminder per task, so repeat-twice would be device-only.
  Decided against.

---

## Build order

1. `SOAPClient` — negotiate auth over URLSession
2. `GetFolder` / `SyncFolderItems` — prove the delta stream
3. **The `CategoryList` write** — the unproven operation, tested early
4. `EWSMapper` — XML to `TPTask` and back
5. Error mapping to `TaskBackendError`
6. Swap `MockBackend` for `EWSBackend` in `Session.makeStore()` — one line

The seam is already cut. `TaskBackend` is a protocol, everything above it is
written against the protocol, and `MockBackend` simulates real delta behavior
with tombstones and paging — so the machinery around the new layer is already
exercised.

**Capture real XML if you can.** Responses from this mailbox beat Microsoft's
documentation; hosted Exchange deployments differ from the spec in small ways
that only show up at runtime.
