# Task Perfect — Foundation + UI

A running SwiftUI app on top of the mock backend. No network, no credentials, no dependencies.

```
TaskPerfect/
├── START-HERE.md                     ★ Read first — reading order, and the fact
│                                     that none of this has ever been compiled
├── PROJECT-SETUP.md                  ★ Xcode target settings, Info.plist, signing
├── BEFORE-EWS.md                     ★ What's been established against the mailbox
├── BACKEND-CONTRACT.md               ★ The TaskBackend seam: every method, its
│                                     callers, and what breaks if it's wrong
├── PARITY.md                         Prototype vs Swift — where they may have drifted
├── App/TaskPerfectApp.swift          Entry point + Session (auth state)
├── Domain/
│   ├── Models/                       TPTask, TPCategory, TPTaskList,
│   │                                 TPRecurrence, SyncToken, SearchField,
│   │                                 CategoryTextStyle
│   ├── Protocols/TaskBackend.swift   ★ The seam. Capabilities + errors.
│   └── UseCases/                     RecurrenceEngine, TaskSorting
├── Backend/Mock/MockBackend.swift    Delta tracking, tombstones, paging
├── Persistence/
│   ├── Entities/                     SwiftData: CachedTask, CachedCategory,
│   │                                 CachedSyncState, PendingChange
│   │                                 (+ QueuedChange, its Sendable snapshot)
│   ├── LocalStore.swift              @ModelActor
│   └── TaskStore.swift               @Observable source of truth
├── Features/
│   ├── SignIn/                       SignInView, LockedView
│   ├── TaskList/                     TaskListView, TaskRowView,
│   │                                 CategoryFilterView, DueRemindersView
│   ├── TaskDetail/                   TaskDetailView, DateFieldView,
│   │                                 RecurrenceEditorView, RichNotesEditor,
│   │                                 RichTextFormatter, TaskCategoryPicker,
│   │                                 ShareSheet, TaskShareExport
│   ├── Categories/                   CategoryManagerView, CategoryEditorView,
│   │                                 CategorySpine
│   └── Settings/                     SettingsView, BadgeSettingsView,
│                                     CategorySortView, SearchFieldsView,
│                                     TaskDetailsView
├── DesignSystem/                     Theme, OutlookCategoryPalette, AppMark,
│                                     FlowLayout
├── Support/                          AppSettings, AppLock, AppBadge,
│                                     CredentialStore, UndoCoordinator,
│                                     Reachability, ServerConfig
├── Tests/                            RecurrenceEngine + TaskSorting unit tests
└── VerifyEWS/                        Connectivity probe — see BEFORE-EWS.md
```

## Run it

**`PROJECT-SETUP.md` is the authoritative version of this** — full target settings, the required `Info.plist` keys, and the signing decision. Short form:

1. Xcode → New Project → iOS → App → SwiftUI, Swift 6 language mode, minimum iOS 17.
2. Delete the generated `ContentView.swift` and `<Name>App.swift`.
3. Drag all folders in — **Copy items if needed**, **Create groups**.
4. Add `NSFaceIDUsageDescription` to `Info.plist`. Without it iOS *terminates the app* the first time biometric unlock is used.
5. Build and run. Tap **Explore with sample data**.

Every `#Preview` works standalone too, so you can iterate on a single screen without launching the app.

## Design direction

The mailbox already carries 25 user-assigned category colors. Layering a brand palette on top of that fights the data, so the chrome is near-monochrome — ink, slate, paper — and **category color is the only saturated color in the app**.

**The signature element is the category spine**: thin vertical color bars on the leading edge of each row, one segment per category. Chips wrap badly on a phone and push the subject line around; a spine shows three categories in four points and keeps every row's text aligned on the same axis. Uncolored categories render as a hairline rather than a gap, so a row still reads as categorised.

Everything else stays disciplined: one accent for overdue (used nowhere else, so it always means one thing), monospaced digits on dates and percentages so numbers don't jitter as rows update mid-sync, and no animation beyond the checkbox symbol transition.

## What works right now

- Tasks grouped as Overdue / Today / Tomorrow / **one section per calendar day** / No Due Date / Completed
- Tap the circle or swipe right to complete — confirmed by default, optimistic, with rollback on failure
- Swipe left to delete — staged, then confirmed in an action sheet
- Delete Task at the bottom of the detail screen, also confirmed
- Search across subject and notes
- Filter by category (only categories actually in use are listed)
- Add, rename, recolor and delete categories — with rename cascading onto tagged tasks
- Undated tasks at top, at bottom, or hidden — set in Display settings
- Full detail editor: status, % complete, dates, reminder, categories, effort, mileage, billing, notes
- Pull to refresh
- Empty states that differ by cause — no matches, filtered out, or genuinely all clear

## Things already handled that are easy to get wrong

**Status and % complete stay coupled**, matching Exchange's server-side behavior. Dragging the slider to 100 flips status to Completed and stamps the completion date; reopening clears it. That's why those properties are `private(set)`.

**Optimistic updates roll back.** Toggle a task and the row changes instantly. If the push fails, the row reverts and the error surfaces. Test it:

```swift
await backend.setFailureMode(.networkUnavailable)
```

**Conflicts trigger a refresh, not a crash.** `MockBackend.update` rejects a stale `changeKey` exactly as Exchange does. The store catches it and reloads.

**Orphan categories render.** A task can carry a category name that is not in the master list — it happens when a category is deleted while tasks still reference it. `TPCategoryResolver` returns those uncolored rather than failing, and the detail screen marks them "Not in your list." No fixture ships in this state; add a name to a task's `categories` that is not in `MockFixtures.categories` to see it.

**Local edits aren't stomped.** `apply(_:)` skips any row still flagged `isDirty`, so a sync landing mid-edit won't overwrite unpushed work.

**Capability-bound fields.** Effort, mileage and billing render because `capabilities` says EWS supports them. Change one constant to `.microsoftGraphToDo` and they disappear rather than silently dropping data.

## Before you go further

Read **`BEFORE-EWS.md`**. It records what has been established against the real mailbox rather than assumed from documentation — EWS is confirmed enabled, authentication works on the bare e-mail address, and reading the master category list works. It also names the one operation that has never been attempted: **writing** the `CategoryList` item, which every category color, rename and delete depends on. Test that early rather than last.

`VerifyEWS/verify.sh` is kept as a quick connectivity probe, not as a gate — the question it was written to answer has since been answered three better ways. `BEFORE-EWS.md` explains why.

## Categories

Settings → **Categories**. Add, rename, recolor, delete, and adopt orphan names into the list.

Files: `Features/Categories/CategoryManagerView.swift`, `CategoryEditorView.swift`, plus `TaskStore`'s category methods and `TaskBackend.saveMasterCategories`.

### Ordering

Categories keep a chosen order that persists until you change it again. It applies **everywhere categories are listed** — the hamburger filter menu, the category manager, and the picker in a task's detail — so one reorder moves all three together.

**Reset to alphabetical order** stores the A–Z order explicitly rather than clearing it. Clearing would fall back to whatever order the mailbox returned, which isn't alphabetical and isn't what the button says.

Names not in the stored order — newly created, or renamed since — fall to the bottom A–Z rather than disappearing. Renaming carries a category's position with it; deleting removes it from the order.

**The order is a device preference**, kept in `UserDefaults` alongside the per-category text styles. The CategoryList blob does carry an order, but desktop Outlook sorts its own dialog alphabetically regardless, so writing it back would be a write nothing reads.

**Category filtering is capped at five in the menu.** At thirty or forty categories the hamburger becomes a scroll, and a filter you have to scroll to find is barely faster than opening Settings. The menu shows five with a **Click here for more categories** row opening the full list; `CategoryFilterView` in Swift, the `filters` panel in the prototype.

**Active filters are promoted to the top of those five.** The common case is clearing a filter you just set — that should stay one tap however far down the list its category sits. Verified: filtering a category that sits last still puts it first in the menu.

**Orphan categories come along.** Categories present on tasks but absent from the master list render on the filter screen marked *"not in list"*. They only appear with certain data, which makes them easy to forget when moving this UI.

**The hamburger is filter-only.** Categories, Show completed, and a **Task Perfect settings…** link. Renamed from "Display settings" because that screen long ago grew past display preferences into sync, unlocking, confirmations, undo and seven sorting screens.

The undated-placement control was removed from it too — in the prototype it was a passive status readout among controls, telling you a value you couldn't act on; in Swift it was a submenu doing a different job in a menu meant for filtering. Both live in Settings, where the same value appears as a real control. The tappable "*3 tasks with no due date hidden*" banner already surfaces the setting exactly when it matters.

**Reordering lives in the Categories screen only.** The hamburger was doing two unrelated jobs: filtering by category is constant, reordering is set-once — and every filter row carried a pair of ▲▼ buttons, 16 of them in an 8-row menu, cluttering the frequent action with controls for the rare one. The menu is now purely a filter: categories, Show completed, Display settings. No shortcut into the Categories screen either — a second doorway means someone who finds ordering that way never discovers the rename, recolor and font controls sitting beside it.

The two implementations still differ in mechanism: Swift uses native drag handles, the prototype uses ▲▼ buttons, because HTML drag is unreliable on touch. But both now live in the same place.

### Rename cascades — this is the whole problem

Exchange stores category **names** on task items, not references. Rename the master-list entry alone and every task tagged with it silently becomes an orphan pointing at a name that no longer exists.

So `TaskStore.rename` does three things: updates the list, rewrites the name on every tagged task, and repoints any active filter. The editor shows the count before you commit — *"2 tasks will be updated to the new name."*

### Delete leaves the label

Deleting a category removes it from the master list; tasks keep the name and render uncolored. That matches desktop Outlook, and `TPCategoryResolver` already handles orphans. Stripping the name off tasks would be silent data loss, so it's a separate, explicitly labeled option in the confirmation: *"Delete and Remove from 3 Tasks."*

### Overdue outranks everything

An overdue task's subject turns **bold red**, and the **Overdue** section heading is bold red too — the only heading that isn't black.

Precedence on a subject line, strongest first: **completed → overdue → category style.** State beats decoration; a row should read as finished, or as late, before it reads as belonging to something.

Overdue forces weight and color but deliberately keeps the category's **size and design**. A row shouldn't change shape as it crosses its due date — only its weight and color — or the list reflows overnight and nothing sits where you left it.

### Four colors beyond Outlook's presets

Palette indices 25–47 — twenty-three colors beyond Outlook's presets:

| | | | |
|---|---|---|---|
| Navy `#14396E` | Sky Blue `#1E90FF` | Bright Orange `#FF7A00` | Amber `#D97706` |
| Vivid Green `#00D45E` | Forest `#00693C` | Deep Gold `#D4A800` | Silver `#7D8FA8` |
| Graphite `#3F4A5A` | Vivid Pink `#E8197B` | Pine `#00706A` | Burnt Orange `#E03E00` |
| Burgundy `#7A0038` | Cobalt `#1550E0` | Crimson `#B3000F` | Scarlet `#E01020` |
| Deep Olive `#5E6B00` | Rosewood `#C41E4E` | Cherry `#FF2D2D` | Umber `#8A5320` |
| Mist `#9BB2E2` | Bronze `#B08C4A` | Mustard `#9B7A00` | |

**They're deliberately more saturated than their Outlook counterparts.** That extra chroma is what makes them read as different rather than as a slightly-off duplicate of a preset sitting a few swatches away — the failure mode when adding colors to an already-full palette.

Three sit in bands Outlook already crowds: Deep Gold near Dark Yellow, Silver near Dark Steel, Pine near Dark Teal. Each is still visibly brighter, but those are the three where the difference is smallest.

**Every addition is checked against the whole palette before it goes in.** The test is RGB distance ≥ 40 from every existing color and from every other new one; below that, a swatch reads as a mistake rather than a choice. Several candidates were moved as a result — Mustard shifted darker to clear Dark Yellow, Mist lighter to clear Gray, Rosewood pinkward to clear Dark Red. The red and yellow bands are the tight ones.

In the category editor they sit under their own heading, **Not Outlook Compatible**, below the 25 presets. Pick one and a warning names exactly what desktop Outlook will show instead:

| Extended color | Outlook falls back to |
|---|---|
| Navy | Dark Blue |
| Sky Blue | Blue |
| Bright Orange | Orange |
| Amber | Dark Orange |

**The two pickers still differ, and that isn't arbitrary.** Exchange stores a category's color as a preset index in the CategoryList blob, and the blob only understands 0–24. So:

- **Font color** offers all 29. Subject styling is a device preference that never leaves the phone, so there's nothing to round-trip.
- **Category color** offers presets first, then the extended four under a heading that says plainly they won't round-trip. Task Perfect renders the color you picked; Outlook shows the nearest preset. The choice is yours to make with the tradeoff stated, rather than the option being hidden.

`ewsPresetIndex(for:)` maps an extended color to its nearest preset by RGB distance, so the write path degrades to something close rather than failing.

### The No Due Date heading is dark blue

`Theme.Palette.undated` (`#14396E`). Undated work is neither urgent nor scheduled, so it gets its own color rather than borrowing the black used by dated sections. Section headings now run three ways: red for Overdue, dark blue for No Due Date, black for everything else.

### Category names carry their color

On a task row each category name prints in its own color, separated by a neutral dot so two adjacent names don't read as one phrase. Orphan names — on a task but absent from the master list — stay gray.

**The palette needed a text variant.** Those 25 colors are designed for filled chips, where a pale swatch reads fine against dark text. As 12pt colored text on white, Peach (#F8CBAD) and Gray (#BDC3C7) are close to invisible. `OutlookCategoryPalette.textColor(for:)` darkens anything above a luminance ceiling until it clears it, preserving hue — Peach becomes #876F5E, Gray becomes #707376, while Red and Dark Blue pass through untouched. Chips and the color spine still use the true palette value; only text is adjusted.

### Per-category subject styling

Each category can paint the subject line of its tasks: **font color** (the 25 Outlook colors plus a Default that is true black), **font design** (System / Rounded / Serif / Mono), **size** (−3 to +4 from system default), **bold**, **italic**, and a **Reset to system default** button.

`Domain/Models/CategoryTextStyle.swift` + the Subject text section of `CategoryEditorView`.

Three decisions worth knowing:

**Multiple categories need a tiebreak.** A task can carry several. The rule: *the first category on the task that has a custom style wins*, in the order the task stores them — the same order the color spine paints. What you see leftmost is what styles the text.

**This is a device preference, not mailbox data.** Exchange has nowhere to store it and desktop Outlook won't render it, so it lives in `UserDefaults` rather than pretending to sync. Styles are keyed by category name, which means rename has to migrate the key (`AppSettings.migrateTextStyle`) or a renamed category silently reverts to default.

**Completion outranks styling.** A finished task stays muted gray with a strikethrough regardless of its category's color — it should read as finished before it reads as belonging to something.

Palette index 14 ("Black") was a dark gray; it's true black now, since it has to serve as a real font color rather than just a chip tint.

### Whole-list writes

`saveMasterCategories` takes the entire array rather than single-item add/update/delete. That's not an API preference — EWS keeps the categories as one XML blob in a single hidden folder-associated item, so every change is a read-modify-write of the whole thing. Modeling it per-item would hide a clobber risk the caller needs to see. Implementations must preserve each category's `guid`; desktop Outlook treats a changed GUID as a different category.

## Completing

Tapping the circle (or swiping right) asks for confirmation first. **Confirm before completing** in Display settings turns it off — on by default.

Only *completing* is gated. **Reopening a completed task never asks**, whatever the setting. Undo should stay cheap; make it expensive and people get wary of the checkbox itself.

The confirmation carries real information for recurring tasks — it names the date the next occurrence will land on, or says the series is ending. That's what makes it worth a tap rather than friction for its own sake.

## Adding a task

The **+** button opens the same editor used for an existing task, in "new" mode — so subject, dates, reminder, repeat, categories, effort and notes are all available at creation rather than forcing a save-then-edit round trip. The Delete row is hidden (nothing exists to delete yet; Cancel discards), the action button reads **Add**, and it's disabled until the subject has something in it.

Two touches:

- **A new task is due today**, at 5pm. Most tasks people add are things they mean to deal with now, so a date is the common case and None is the exception. It's also the safer default: an undated task can only be found in All Tasks and No Due Date, which is a quiet way to lose one. Clearing it is one tap — the date field still offers None.
- **Two tabs override that.** No Due Date seeds no date, because undated is the entire point of the tab; Completed does the same, since a new task isn't finished and a dated one would vanish on save either way. Everywhere else, including Overdue, the default stands: adding from Overdue means "deal with this now", not "make it late".
- **The draft is otherwise seeded from the tab you're standing in.** Adding from a category tab arrives already tagged. No Category deliberately seeds nothing, since untagged is the trait.
- **A new task always lands somewhere visible.** Add an undated task while standing in Overdue and it would vanish the moment you saved — so the view switches to All Tasks and says so. This matters less now that dates are the default, but it still covers the tabs that seed None and anyone who clears the date by hand.
- **5pm, not midnight.** A task created at 9am with a midnight due time is already overdue before you've put the phone down. 5pm also matches where the date picker lands elsewhere.

## Undo

Deleting a task or a category removes it immediately and shows an Undo bar. `Support/UndoCoordinator.swift`.

**Two independent coordinators, not one.** `taskUndo` and `categoryUndo` each hold their own pending entry and their own window, so deleting a task never cuts short a pending category delete. Both can be up at once, in which case the bars stack.

**Undo can be switched off entirely, separately for tasks and categories.** Off means the delete is sent immediately — no bar, no way back from within the app. The window picker hides when its toggle is off, since it would be configuring something that doesn't happen.

**Turning undo off doesn't switch the confirmation on.** Silently changing a second setting on the user's behalf is worse than telling them: if undo *and* confirmation are both off for the same operation, the footer warns that a swipe will delete with nothing in between. Their choice to make, stated plainly.

**Separate windows, set independently** — 5 / 10 / 15 / 30 / 45 / 60 seconds, the same choices for both, defaulting to 5 for tasks and 10 for categories since a category delete is the more consequential one.

**The bar tracks your finger as you drag it** — moving with you and fading as it goes, springing back if you release short of the 44pt threshold. A gesture with no visual response is indistinguishable from a broken one, which is exactly how the first version felt: the logic fired correctly but nothing moved, so there was no way to tell it was working.

The axis is decided once, on the first few points of movement, then committed to — otherwise a slightly diagonal drag flickers between vertical and horizontal. In the prototype the bar also needs `touch-action: none`, or the browser claims the vertical drag for scrolling before the handler ever sees it.

`UndoBar` is its own SwiftUI view rather than a helper method, because two bars can be on screen at once and each needs its own drag offset.

**Slide the bar down to dismiss, which commits.** Hiding the bar while the delete stayed secretly cancellable would be a strange in-between state — dismissing means "yes, I meant it", and the change reaches the queue immediately rather than waiting out the window. Downward only, and past a 40pt threshold: an accidental sideways swipe shouldn't end the window. VoiceOver gets a named "Dismiss" action, since a swipe isn't reachable that way.

**Tasks batch, categories don't.** Deleting three tasks in a row gives one bar reading *"3 tasks deleted"*, and one Undo restores all three; each new delete restarts the clock. Restores run newest-first so entries touching the same records unwind in the order they were applied. Categories stay single — two staged category deletions can touch overlapping task lists, and untangling which restore owns which tag isn't worth it for something that rare.

**Category undo has to restore more than the list entry.** Styling and ordering are keyed by name and get cleared on the way out, so both are snapshotted. If the delete also stripped the label from tasks, the affected task IDs are captured *before* the strip — afterwards there's nothing left to identify them by.

**It delays the send rather than reversing it.** Nothing reaches the change queue until the window closes, so undo has nothing to undo — it just cancels. A true reversal would need Exchange to hand the item back from Deleted Items: EWS can do that, but retention varies by server, a hard delete leaves nothing, and the restored item returns with a new `ItemId` that no longer matches the local record.

Three cases that would otherwise be silent bugs, all verified:

- **Backgrounding with anything staged** commits both slots. Otherwise the task would look deleted, not be, and offer no way back — the worst of both.
- **A second delete before the first commits** flushes the first rather than dropping it, or the earlier task would never reach the server.
- **Undo after the window closes** does nothing rather than resurrecting a task that's already gone.

### Confirmations are now three independent toggles

Settings → **Confirmations**: completing (on), deleting a task (**off**), deleting a category (on).

**Task deletion defaults to off because undo covers it better** — a confirmation costs a tap every time to guard against a mistake undo fixes after the fact.

**Category deletion keeps its prompt**, and that's not just caution. The dialog is where you choose between *"Delete Category"* and *"Delete and Remove from 8 Tasks"* — two different outcomes that undo can't express. Switch it off and the label silently stays on tasks, which the settings footer warns about.

## Deleting

Two routes, both confirmed:

1. **Swipe left on a row** → reveals Delete → action sheet
2. **Delete Task** at the bottom of the detail screen → same action sheet

The swipe action stages the deletion rather than performing it; the confirmation is what actually calls `store.delete`. Nothing leaves the mailbox on a stray swipe.

The confirmation names the task rather than saying "this item", and adds a second line for recurring tasks — *"Future occurrences will stop."* Deleting a recurring task takes its whole schedule down, which isn't obvious from the word Delete.

## Date fields

`Features/TaskDetail/DateFieldView.swift` — used for Start, Due and Reminder.

**None is a choice, not the absence of one.** Tap a date row and it expands to show *None · Today · Tomorrow · Next week* as equal options, with a calendar below when a date is set. Picking None clears the field and collapses the picker.

This replaces a toggle-plus-picker pattern where "no date" was a side effect of flipping a switch — you couldn't see it as an option, only infer it. The collapsed row now reads back "None" in muted text, so the state is legible without opening anything.

Two things that fell out of the change:

- **`reminderIsSet` is derived, never edited.** A reminder exists exactly when it has a date. Holding the flag as separate state was how the two could drift apart.
- **Start and Due seed different hours** — 9am and 5pm. A task that starts in the morning and is due end of day is the common case, and quick options should land there without a second edit.

## Date range

Settings → **Date range**: how far **Back** (8 days, 1 / 3 / 6 months, 1 year, All) and how far **Ahead** (8 days, 1 / 3 / 6 months, 1 year, 18 months, 27 months, All) the app lists tasks. **All** sits last in both lists — the options are an increasing scale and "no limit" is the end of it, not the start. Both default to **All**: a window that hides tasks the user never asked to hide is the wrong first-launch behavior.

Three decisions:

**The limit carries days or months, not one unit.** Eight days can't be expressed in months, and "1 month" has to stay a calendar month rather than becoming 30 days — otherwise a range set in January would end mid-February.

**Both edges snap to whole days.** An exact timestamp on the far edge makes the window lopsided: a task due at 5pm on the eighth day would be hidden while its counterpart eight days back was shown. Verified symmetric — ±8 in range, ±9 out.

**It's anchored on the completion date when there is one**, otherwise the due date. A task finished yesterday shouldn't disappear because it was *due* two years ago.

**Undated tasks always pass.** They have no anchor to compare, and the No Due Date placement setting already governs them.

**It filters in `matchesFilters`**, so the window applies to every tab at once rather than being re-implemented per tab — including the category pills.

The settings footer shows a live count of what the range is currently hiding, in red, for the same reason the No Due Date "Don't show" option does: a setting that removes tasks has to say how many.

## Language

**American English throughout** — user-facing strings, code comments and this document. "Color", not "colour". Worth keeping in mind when adding anything new.

## Offline

The app opens to a full task list with no connection, edits work normally, and changes sync when the network returns.

| File | Role |
|---|---|
| `Persistence/Entities/CachedTask.swift` | SwiftData rows for tasks, categories, sync state |
| `Persistence/Entities/PendingChange.swift` | One queued outbound change, with backoff |
| `Persistence/LocalStore.swift` | `@ModelActor` wrapping the store |
| `Support/Reachability.swift` | `NWPathMonitor`, fires on reconnect |

### Disk first, then network

`TaskListView.task` calls `loadFromDisk()` before any network call, so the list is on screen before a request is attempted. Deltas write through to disk as they arrive, and the sync cursor is persisted per folder — a relaunch resumes the delta stream instead of re-pulling the mailbox.

### The queue is durable and coalesced

Every mutation enqueues rather than pushing directly. An edit made on a plane survives the app being killed.

**Coalescing matters more than it looks.** Without it the queue grows without bound — checking a task off and on ten times would send twenty requests describing one final state. The rules:

- A second update collapses into the first; only the latest state matters.
- An update after a queued create is absorbed — the payload is read **fresh from disk at send time**, so later edits ride along rather than needing their own entry.
- A delete drops everything queued for that task.
- **Create-then-delete cancels out entirely.** A task created and deleted before either reached the server never existed as far as Exchange is concerned; sending both would ask the server to delete an item it would first have to invent.

Verified: 25 operations collapse to 3 queued changes.

### Failure handling

Failures back off exponentially, capped at 5 minutes with jitter — the cap stops a long outage pushing the next attempt hours out, and the jitter keeps a queue from retrying in lockstep and arriving as one burst. After 10 attempts a change is dropped, but the task keeps its dirty flag so the work stays visible.

A conflict is **not** retried. The server copy wins, the change is dropped, and the next pull brings theirs in — retrying would fail again on the same stale `changeKey`.

**Being offline is not an error.** `syncChanges()` returns early rather than recording a failure; the queue is already holding the work.

### Telling the difference

The header subtitle ranks connectivity above everything: *"⚠ Offline · 2 waiting"*, then *"2 changes to sync"*, then *"3 due today"*, then the last-synced time. "3 due today" while silently offline is a worse lie than a missing count. The ↻ button dims when offline but stays tappable — an attempt that fails fast and says why beats a dead-looking button.

## Settings structure

Five groups, each introduced by a tinted band with a title and one line of description:

| Group | Contains |
|---|---|
| **Appearance** | Row shading, subject lines, undated placement, completed grouping, date range |
| **Organization** | Sorting Options ›, Tab Bar ›, Categories Management › |
| **Behavior** | Confirmations and undo |
| **Sync & Notifications** | Sync triggers, app icon badge |
| **Account** | How the app opens, server, domain, reset cache, sign out |

**The order was accumulated, not designed** — each section arrived as it was built, leaving display preferences at positions 1, 3, 8 and 9 with unrelated things between them, and Account last when it's what people open Settings to find.

**All three sub-pages now sit together under Organization.** Mixing navigation rows among inline toggles meant scanning every row to know which led somewhere.

**Nothing was merged, only moved.** Every section kept its heading, every control its binding, every stored value its key — so the grouping is presentation and can be undone by moving blocks back. `/tmp/prototype-before-settings-restructure.html` holds the previous version.

**The Tab Badge & Visibility row gained a heading.** It had been sitting headingless at the tail of Row Shading, which is how it ended up between two unrelated things.

## Account

Settings → **Account**: Signed in as, Server, Domain, Sign out.

**Reset cache** clears the sync token and local store, then pulls the mailbox again. The escape hatch for "sync looks wrong and I can't tell why" — a stale token, a half-applied delta, anything that leaves the local copy out of step.

**An action, not a mode.** A "full sync" toggle would let someone permanently degrade their own sync, and with *sync after every change* on it would re-pull the whole mailbox on every completion. This self-corrects once and resumes delta syncing. Pending changes are pushed **before** the store is cleared — otherwise it would silently discard edits that never reached Exchange.

**Domain is optional.** Evidence from a working third-party client on the same mailbox: its Domain field is empty and marked Optional, authenticating on the full e-mail address alone. `qualifiedUsername` sends the bare username when the domain is blank rather than a leading backslash, which Exchange rejects. The default is still prefilled; it just isn't required.

**No password field, deliberately.** Three reasons, and the first is the one that settles it:

- Under biometric lock the password is stored with `.biometryCurrentSet`, so **reading it is the Face ID prompt**. Displaying it would demand authentication every time this screen opened, for a field nobody came to look at.
- Under "Password every time" nothing is stored, so the field would be permanently blank — which reads as broken.
- A retrievable password on screen is a password over someone's shoulder.

**Sign out covers what a password field would have been for.** Changing your Exchange password means giving the app the new one, and signing out and back in does that — while also being how you'd switch accounts. It's confirmed first, and the message notes that local tasks survive and pending changes are sent on the next sign-in.

## Server and domain

Defaults are baked in — `east.exch092.serverdata.net` / `EXCH092` — because asking every colleague to type a server address is a way to collect typos. But they're **editable in two places**, and both are necessary:

- **On the sign-in screen**, behind a "Change server" disclosure that opens automatically if the values have been customized.
- **In Settings → Account**, for changing them later.

**Settings alone would have been useless.** It sits behind the sign-in screen, so a first-time user whose mailbox is on a different host could never reach the field that fixes it. The sign-in disclosure is what makes this work at all; the Settings copy is the convenience.

**Values are normalized on the way in.** Pasting `https://host/EWS/Exchange.asmx` — the common mistake — is stored as `host`. A full URL in that field would otherwise fail with a confusing error rather than an obviously wrong address.

**Blank falls back to the shipped default** rather than saving an empty string the app can't use. A "Reset to defaults" button appears only once something has been changed.

**Sign-in persists the fields before attempting the connection**, so a failed sign-in doesn't discard the correction just typed.

The username field is labelled **Username / e-mail**: `qualifiedUsername` already passes through anything containing `@` or `\` untouched, so both forms work.

## Unlocking

Settings → **How the app opens**, positioned next to Server and Domain since it's all sign-in — one picker, three states:

| Option | Behavior | What's stored |
|---|---|---|
| **Password every time** *(default)* | Sign-in screen on every launch | Nothing |
| **Face ID / Touch ID** | Locked screen, biometric prompt, then the list | Password in Keychain, released only after biometrics |
| **Stay signed in** | Opens straight to the task list | Password in Keychain, released when the device is unlocked |

**A picker, not two toggles.** "Stay signed in" and "require Face ID" are contradictory instructions. Separate switches would need coordination logic to stop them fighting; an enum makes the conflict impossible to express rather than merely handled.

### The setting changes what's on disk, not just a label

`CredentialStore` sets the Keychain accessibility class from the mode, and that's what actually enforces it:

- **Password mode** stores nothing at all — that's what "not remembered" has to mean.
- **Biometric** uses `kSecAttrAccessibleWhenPasscodeSetThisDeviceOnly` with `.biometryCurrentSet`. The Keychain itself refuses to release the password without a successful biometric check, so reading it *is* the gate. `.biometryCurrentSet` also invalidates the item if a face or finger is added or removed — otherwise enrolling a new face would silently grant access.
- **Stay signed in** uses `kSecAttrAccessibleWhenUnlockedThisDeviceOnly` — no prompt, but never synced to iCloud and never restored onto a different phone.

Changing the setting rewrites the stored item, because Keychain access control is fixed at write time. Storing the password and merely *asking* for Face ID in the UI would be theatre — anyone with the device unlocked could read the item directly.

### Never lock the user out of their own mailbox

- The biometric prompt uses `.deviceOwnerAuthentication`, not `...WithBiometrics`, so iOS offers the device passcode when a face isn't recognized. Without that, someone in sunglasses has no way forward.
- Enrollment changes, biometric lockout, or tapping "Use Password" all fall back to the sign-in screen with the reason shown.
- If Face ID isn't set up on the device, that option isn't listed at all — `AppLock.availableModes` filters it out.
- `AppLock.biometryName` returns "Face ID", "Touch ID" or "Optic ID" as appropriate. Hardcoding "Face ID" would give an iPhone SE user a wrong instruction.

The locked state is its own screen rather than a sheet over the task list — a sheet would leave the list readable underneath, defeating the point.

## Sync

Settings → **Sync** has three toggles: **After every change** (default on), **When opening the app** (default on), **When closing the app** (default off). The ↻ button on the task list works regardless.

### After every change

Fires on anything that reaches the mailbox: a task added, edited, completed, reopened, skipped or deleted, and any category added, renamed, recolored or removed.

**Display settings are deliberately excluded.** They live in `UserDefaults` on the device and Exchange has nowhere to store them, so there would be nothing to send.

**It coalesces rather than firing immediately.** Checking off five tasks in a row is five changes but should be one round trip. Each change cancels the pending sync and restarts a two-second timer, so the sync lands shortly after you stop. Firing on every change would leave the app in a permanent sync spin and, on a slow connection, queue syncs faster than they complete. `syncAfterChangeNow()` skips the delay when something needs to go immediately.

Verified against the mock: five completions in quick succession produce one sync carrying all six pending changes; with the toggle off, edits stay pending until you press ↻.

**`TaskStore.syncChanges()` is the changes-only command.** It's what the ↻ button, pull-to-refresh and the automatic triggers all call. `refresh()` still exists for a full reload, but it's only used on first run and when the server rejects our sync state.

Three things it does that a plain reload doesn't:

1. **Pushes pending local edits first.** Pulling before pushing lets the server's older copy overwrite work that never left the device. Anything that fails keeps its dirty flag and is retried next time rather than being dropped.
2. **Drains every page.** EWS returns changes in batches. One call can leave changes behind, and the next sync would start from a token claiming they'd already been seen.
3. **Skips folders and categories.** Those rarely change and cost a round trip each; they're only re-read when the server forces a full resync.

### The sync token has to carry a cursor, not just a version

`MockBackend` now tracks real per-item versions and deletion tombstones, so incremental sync can be tested rather than assumed. Building that surfaced a genuine bug worth recording:

A token holding only "the version I've synced to" **cannot page**. Every item written in one batch shares a version, so the cursor can never advance past them — the first sync delivered one page of 25 and then declared itself finished, silently losing 31 tasks. The token now carries `(version, offset)`, and only commits to the new version once the whole change set has been read, so an interrupted sync resumes instead of skipping.

Real EWS hides these same two pieces of state inside its opaque `SyncState` string. When you write `EWSBackend`, treat that string as opaque and store it verbatim — the bug above is what happens when you try to be clever about what's inside it.

**Tombstones ride with the final page.** A delete applied before its matching edits arrive would resurrect the item on the next page.

Verified against the mock: a first sync pulls 56 tasks across 3 pages; an immediate second sync makes one call and returns nothing; 3 remote edits return exactly 3 items; a remote delete returns exactly 1 tombstone; a stale token triggers a clean full resync.



Settings → **Sync**: *When opening the app* (default on) and *When closing the app* (default off). A **↻** button sits beside the hamburger on the task list for syncing on demand.

**Two independent toggles rather than one three-way picker.** Wanting both triggers is a reasonable setup, and a picker would force a choice between them. With both off, syncing is manual only — the footer says so, and the button is always there regardless.

Automatic syncs hang off `scenePhase`: foreground from background triggers the open sync, moving to background triggers the close one. First launch always loads whatever the settings say — there'd be nothing to show otherwise.

In the prototype, syncing is simulated (a short delay, then the header timestamp updates) and `visibilitychange` stands in for the scene phase, since backgrounding a browser tab is the closest analogue to closing an app.

## Completed sorting

Settings → **Sorting Options → Completed**. Completion Date, Due Date, or Ungrouped.

| Grouping | Levels offered |
|---|---|
| Completion Date | Due Date soonest / furthest, Category A–Z / Z–A, Alphabetically A–Z / Z–A, Recurring |
| Due Date | Completion Date most recent / oldest, Category A–Z / Z–A, Alphabetically A–Z / Z–A, Recurring |
| Ungrouped | both date families, plus the rest |

**Completion dates are labelled "most recent / oldest"**, not "soonest / furthest". Completion dates are all in the past, so the future-facing wording used for due dates would read backwards.

**No High Priority level here** — priority stops mattering once something is done. **No Category per Tab Order** either.

**Each grouping omits its own date family**, since a section grouped by completion date is already one completion date. The same rule as everywhere else.

**Tasks with no completion date get their own section at the bottom.** Exchange doesn't always populate `completeDate` — a task marked done by an older client can arrive without it. They'd otherwise be dropped from a completion-date grouping or silently bucketed under today.

**The default is Ungrouped, most recent first** — exactly what the tab already did, so switching this on changes nothing until you change it.

**The tab never disappears**, empty or not, and its badge can be switched off like any other.

## No Category sorting

Settings → **Sorting Options → No Category**. Due Date or Ungrouped.

| Grouping | Levels offered |
|---|---|
| Due Date | None, Alphabetically A–Z / Z–A, High Priority, Recurring |
| Ungrouped | those plus Due Date soonest / furthest |

**No category levels in either** — nothing here carries a category to order by.

**And no date levels under due-date grouping**, where each section is already a single date and they'd have nothing to separate. They appear under Ungrouped, where the whole list is one section and date order is the main thing you'd want. Same reasoning as the main tabs.

Overdue and No Due Date stay pinned in both groupings, as they do in the main tabs.

The pill disappears when nothing is untagged, and its badge can be switched off — verified that with the badge off, the count never runs.

## No Due Date sorting

Settings → **Sorting Options → No Due Date**. Two groupings only — Category or Ungrouped.

**No due-date grouping, and no date sort levels.** Nothing in this tab has a date, so grouping by one would yield a single section and sorting by one would decide nothing.

| Grouping | Levels offered |
|---|---|
| Category | None, Alphabetically A–Z / Z–A, High Priority, Recurring |
| Ungrouped | those plus Category A–Z / Z–A / per Tab Order |

The category levels appear only when ungrouped, where the list mixes categories. Inside a category group every task shares one, so they'd decide nothing there either.

**This tab ignores the "Don't show undated tasks" placement setting** — a tab whose job is showing undated tasks can't honour a preference to hide them. So it can show tasks hidden everywhere else. Existing behavior, unchanged by these settings.

The pill disappears when nothing undated is outstanding, and its badge can be switched off like any other — verified that with the badge off, `tabCount("nodue")` is never called.

## Overdue sorting

Settings → **Sorting Options → Overdue**. Its own setting, with all three groupings and the same three menus as the main tabs.

**No pinned overdue section here.** Everywhere else, overdue tasks are lifted into their own section at the top and exempted from the configured sort. In this tab every task is overdue, so that rule would make the whole thing one exempt section and leave the settings inert. Dropping it is what makes the tab configurable at all.

No undated section either — an undated task is never overdue — and no completed banner, since a completed task isn't overdue.

**Due-date grouping tends toward many small sections**, because overdue tasks spread across whatever dates they missed. Ungrouped often reads better here than elsewhere. The footer says so.

**The tab still disappears when nothing is overdue**, and its badge can be switched off in Tab counts like any other — verified that with the badge off, `tabCount("overdue")` is never called.

One thing that can't be skipped: the pill still has to know *whether* any overdue tasks exist, or it can't decide whether to appear. That check stops at the first match rather than counting everything, so it's much cheaper than the badge — but it means the tab is never entirely free.

## All Tasks and Today sorting

Settings → **Sorting Options → All Tasks Tab** and **Today Tab**. Separate settings, identical options.

**Grouping:** Due Date, Category, or Ungrouped.

**The sort menu changes with the grouping**, because the useful levels differ:

| Grouping | Levels offered |
|---|---|
| Due Date | Category A–Z / Z–A / per Tab Order, Alphabetically A–Z / Z–A, High Priority, Recurring |
| Category | Due Date soonest / furthest, Alphabetically A–Z / Z–A, High Priority, Recurring |
| Ungrouped | all ten — dates first, then the rest |

**Ungrouped offers the date levels; due-date grouping doesn't.** That looks inconsistent but isn't: under due-date grouping each section is already a single day, so a date sort would only distinguish time of day. Ungrouped is one long list, where the date order is the main thing you'd want.

Category levels decide nothing inside a category group — every task there already shares a category.

**The category levels are offered on the main tabs only.** A category *tab* never lists them, whatever its grouping: its tasks are already filtered to one category, so sorting by "first tag" would order by something that isn't the tab you're looking at. So Category Tabs keeps its seven options, and only All Tasks & Today grouped by due date gets the extra three.

Switching grouping prunes any level the new menu doesn't offer, or the picker would show a blank row and sort by something invisible.

### Group by Category is a partition

**A task with two categories appears once, under its first tag.** Groups must partition or the section counts exceed the task total — verified: 55 rows against a badge of 55, with both dual-category fixtures appearing exactly once.

**This differs from a category tab on purpose.** A `[Special, Friends]` task appears in *both* pills, because a tab is a filtered view. It appears in *one* group, because a group is a partition. Same task, two behaviors, both correct.

**"First" means first tag, not highest-ranked.** A task tagged `[Friends, Special]` files under Friends even if Special sits earlier in the manual pill order. The order comes from Exchange, normally the order the tags were applied in Outlook, and isn't visible in the app.

Category sections follow the manual pill order, then unknown categories A–Z, then No Category last. Untagged tasks sink in every category sort direction — there's no category to order them by, so putting them first would be arbitrary.

### Today offers neither due-date grouping nor date sort levels

**Grouping:** Category or Ungrouped only. Grouping Today by due date yields Overdue and Today — exactly what the tab already shows without any setting, so it isn't offered.

**Levels:** no date options in either grouping. Overdue is a pinned section with its own ordering, and everything else in the tab is due today — so a date sort would only separate tasks due at different times of the same day. Same rule as everywhere else: date levels appear only where a section can hold more than one date.

The default is **Ungrouped, A–Z**, matching what the tab already showed.

### Why the tabs have separate settings

The same grouping means something quite different in each tab, so a shared value forced a compromise on both — and Today ends up offering a genuinely smaller menu than All Tasks.

**These tabs never disappear**, unlike category pills, regardless of emptiness.

## Sharing a task

A **share button** in the task detail toolbar, left of Save. Only on saved tasks — sharing something not yet written invites confusion about what was actually sent.

**Two representations go together.** Readable text as the message body, and an **`.ics` file** (`VTODO`) attached. The text is what a recipient reads and what the system printer lays out; the `.ics` imports into Outlook, Reminders or most task apps as a task of their own.

**Print and PDF come free.** The system share sheet includes Print, and Print's preview becomes a PDF if you pinch outward on the page thumbnail. No separate print control, no custom layout.

**The `.ics` is a snapshot, not a subscription.** Nothing links back, no status returns, ownership doesn't change — deliberately unlike Exchange task assignment, which creates an obligation and takes the task away from you.

**`ShareLink` couldn't do it.** It takes a homogeneous collection, so it can't carry text and a file together; `ShareSheet` wraps `UIActivityViewController`, which takes `[Any]`.

Rich-text notes flatten to plain text — bullets survive as "• ", colors and fonts don't. Categories go into the `.ics` but without their colors, since iCalendar has no equivalent of Outlook's palette.

## Assigned To

**Exchange's `Owner` field is read-only** — the server sets it to the mailbox owner, and it only names someone else on a formally assigned task. So it can't carry "who's responsible". It's displayed but not editable.

**Assigned To is stored in `Companies`**, an editable string array EWS exposes and Outlook shows on the Details tab. The app labels it Assigned To; only Outlook reveals the underlying name. Several names separate with commas.

**Grouping and sorting, in all seven tabs.** `Assigned To A–Z` and `Assigned To Z–A` appear last in every grouping menu and every sort-level menu — last because it's the newest and least populated option, and shouldn't displace what people reach for first.

**No pinned Overdue or No Due Date sections under assignee grouping.** Every other grouping pulls those out into their own sections so a late task can't hide. Grouping by assignee answers "what does this person owe me" — and their *overdue* task is the thing you most need to see under their name, so pinning it away defeats the purpose. Overdue tasks keep their red date and warning icon inside the person's section.

Swift got this right for free: `switch options.grouping` makes the cases mutually exclusive. The prototype's if-chain tested overdue and undated *before* consulting the grouping, so four of eight assigned tasks landed in the pinned sections instead of under a name.

**On the list, the name sits on its own line with the completion stamp** — assignee left, "Completed [date]" right, growing toward each other rather than into each other. Not on the meta line: that already runs to ~50 characters on a third of rows, so a name there would have made wrapping the normal case.

Slate, with a small person glyph, so a name doesn't read as another category — the two sit inches apart and would otherwise look alike. Several names show as "Jill +1", with the full list in the tooltip. The line only renders when there's something to put on it, so unassigned active rows are unchanged.

**A task files under its first assignee**, matching the first-category rule: it appears once, not once per name. **Unassigned sinks to the bottom** in both directions, like undated tasks.

**Assigned levels drop out under assigned grouping** — each section is already one person, so they'd have nothing to separate. Same rule as category levels vanishing inside category grouping.

**Unlike categories, names have no defined order.** There's no equivalent of "Category per Tab Order", so alphabetical is the only arrangement.

## Reminders on open

Settings → **Sync & Notifications → Reminders → Show reminders when the app opens**, default **on**.

A banner on the task list reads *"3 reminders due"* and opens a list of reminders that came due while you were away: set, in the past, not yet done. Oldest first — the one most likely to have been missed leads.

**Why this exists when notifications are the obvious answer.** iOS caps an app at 64 pending notifications and silently drops the rest, so the plan in `BEFORE-EWS.md` is to schedule the nearest ones and top up on open. That plan has a hole: a reminder outside the window never fires at all. This path reads the task list rather than a capped queue, so it has no ceiling. It also needs no permission — notifications can be declined at the prompt or revoked later in iOS Settings, which kills the feature silently, and this still works.

The two mechanisms cover each other: notifications reach you with the app closed, the sweep catches what notifications couldn't hold.

**A toggle, not fixed behavior.** A banner on every launch becomes noise you learn to dismiss unread, at which point it's worse than absent — it has trained you to ignore it. Somebody who works that way needs a way out that isn't "stop setting reminders."

**Default on**, unlike the No Due Date memory. That one defaults off because remembering a collapse can hide work; this surfaces work you asked to be reminded about, so the safe default and the useful default agree.

**A banner, not a modal.** A dialog on every launch is the same few reminders most mornings and blocks the app to say so. The banner matches the hidden-undated one already there, and waits to be tapped.

**Above the undated banner, and on every tab.** It's a prompt to act rather than a note about a filter, and a missed reminder isn't a property of the tab you happen to be standing in.

### Dismissal is local to the launch

Exchange stores **one** reminder per task, and Outlook keeps its own dismissal state. Writing `reminderIsSet = false` from the phone would clear the reminder on every client — not what tapping *Dismiss* means. So dismissal lives in `dismissedReminderIDs`, in memory, gone on the next launch.

The cost is real: the same reminder can greet you on two devices. It's the right trade, since the alternative silently destroys data. Clearing a reminder for good stays the task editor's job, and a row opens straight into it.

**`remindersBannerHandled`** is what stops the banner returning on every redraw once you've dealt with it. Also per launch.

### Where the toggle sits

*Sync & Notifications* already existed as a group heading with Sync and App icon badge under it. This adds a **Reminders** group between them — the shelf the rest of the reminder work will sit on. Permission state, lead time and the 64-notification top-up all belong there when they're built, so nothing has to move.

### Fixtures

Five, identical in `MockFixtures.swift` and the prototype. Three qualify for the banner: a broker call reminded three hours ago, a delivery window from yesterday morning, and an **undated task carrying a reminder** — the combination that catches an implementation keying reminders off the due date.

Two deliberately don't: a reminder set for next week, and a past reminder on a completed task. They're there so the count can be *checked* rather than assumed — 84 tasks, 6 carrying reminders, 3 due.

The three-hours-ago one is built relative to now rather than to a clock hour, so it stays three hours ago whenever the app is opened.

## The sheet behind the list

Opening a task showed the editor *behind* the task list — every row painting over it, on every tab. A regression from the iOS height fix, not from the panel work.

Task rows carry `z-index: 1` for the swipe track. The task sheet carried none, relying on document order. Those two coexisted only because `-webkit-overflow-scrolling: touch` promoted the list to its own layer in WebKit, and that layer *contained* the rows' stacking order. Removing the flag — necessary, it was breaking the list's height — let the rows' z-index escape into the page, where a positive number beats the sheet's `auto` regardless of where either sits in the markup.

Fixed twice over, deliberately:

**`isolation: isolate` on the list**, which contains the rows' stacking order on purpose rather than by side effect. This is the root cause fix and the comment says the property is load-bearing, because it looks removable.

**An explicit scale for the overlays**, so nothing depends on document order: popscrim 4 · pop 5 · task scrim and sheet 6 · pushed panels 7–11 · undo 10 · dialogs 20+. The sheet has to sit above the list and below the panels it pushes, and now says so.

**The lesson worth keeping**: the flag removal was correct and the bug it exposed was already latent. A fix that removes a compositing hint can silently change what a whole screen paints over, and neither the height test nor the search test would ever have caught it — it takes opening a task.

## The category filter panel

Reported as confusing: the panel ended with *Task Perfect settings…* and then task rows immediately below it, so it read as one continuous surface where the tasks looked selectable.

**A scrim behind it.** The single biggest cause. With nothing dimming the list, the panel's bottom edge sat flush against live rows and the whole thing read as one menu — chips, a settings line, then apparently-tappable tasks. The dim says the panel is temporary and the list is waiting underneath. The Swift version had this already; native menus dim for free.

**Settings sits on a tinted strip.** Everything above it filters the list; it leaves. Same weight and background made it read as one more category.

**Clear filter moved to the top**, above the categories, and only appears with a filter set — carrying the count, so the panel says how many are ticked without being counted. It used to sit *below* Settings, which is the last place anyone looks, for the action people most often reopen the menu to perform.

**Heading is now "Filter By Category"** — an instruction rather than a noun phrase, matching the direction the other screens moved.

**"Click Here For More Categories" stays** as it is.

### Clearing a filter from the list

A banner sits **directly under the reminders banner**, above the hidden-undated one: *"Filtered: Personal · Clear"*. The completed toggle keeps its own place above, untouched.

**Stacked, not merged.** Sharing a row with the reminders banner would save a line, but the two say different kinds of thing — one is *something needs your attention*, the other is *this list is not everything* — and combining unrelated statements makes both harder to read. Reminders lead: a due reminder outranks a filter you set a minute ago and already know about.

**Names up to two categories, counts beyond.** *"Filtered: Personal"*, *"Filtered: Personal, Work"*, then *"Filtered: 3 categories"*. Keeps the line from wrapping and doubling its height however many are ticked.

**The whole row clears it.** A filter banner exists to be dismissed, so a small "Clear" target beside a large inert row would be the wrong way round.

This doesn't replace *Clear filter* in the menu — the banner is for when you're looking at a filtered list and want out, the menu entry for when you're already in there adjusting things.

**One helper opens and closes the panel** rather than paired `classList` calls at five call sites. The scrim and the panel must never disagree, and they will if each site does it by hand.

Every stamped build is self-contained, so reverting is opening an earlier file — nothing here touches stored data or settings.

## Pinned sections and the configured sort

Reported as "Alphabetically Z–A doesn't work properly." Z–A was fine everywhere it applied — the fault was that **No Due Date ignored the sort entirely**, always ordering A–Z. Choose Z–A and every section obeys except that one, which reads exactly like a broken sort.

The exemption was inherited from Overdue, where it earns its place: how late something is *is* the organizing idea there, and no sort level can express it under due-date grouping, where the date levels aren't offered. None of that applies to No Due Date — those tasks have no date to order by, so there was nothing for the exemption to protect.

**Now: Overdue keeps oldest-first; every other section, No Due Date included, follows the configured levels.** Fixed in four places in Swift and three in the prototype, since each tab's builder had its own copy of the rule.

Worth noting how it hid: the reported symptom pointed at the comparator, and the comparator was correct. Testing Z–A across All Tasks, a category tab, and both groupings showed correct ordering in every section that used it — which is what made the one section that didn't stand out.

## Grouping: Today, Tomorrow, Weeks, Months

Sorting Options → All Tasks → Grouping, directly beneath **Due Date**. Sections run: **Overdue · Today · Tomorrow · Rest of This Week · four weekly sections · Rest of [month] · then whole months**, with No Due Date wherever the placement setting puts it.

**The point is a bounded list.** Due-date grouping produces one heading per distinct date — thirty scattered tasks make thirty headings. This holds at roughly a dozen however far out the tasks run, because resolution coarsens with distance: detail close in, less of it further out.

**Same key, different resolution**, so it sits under Due Date rather than elsewhere in the list. Both group by the due date. Neither renames the other: `dueDate` stays exactly as it was.

**The first three sections are decided by identical logic**, so Overdue, Today and Tomorrow behave the same under both groupings, and No Due Date needs no special case — it's a pinned section built from `noDueDatePlacement` regardless of grouping, so Top, Bottom and Don't show all work untouched.

### The calendar edges, and how each resolves

Verified by walking 160 consecutive due dates against four different "today"s:

**Tomorrow can fall in next week.** On a Saturday it does. The Tomorrow carve-out happens *before* the week test, so Sunday's tasks don't land in both. The consequence is visible: standing on Saturday Aug 22, the section labeled *Aug 23–29* holds Aug 24–29, because Aug 23 is Tomorrow. The label overstates by one day at the boundary — the alternative, relabeling the week, would be worse.

**Rest of This Week legitimately empties.** On Saturday always, on Friday when nothing is due Saturday. Empty sections are never built, so the heading simply isn't there. Confirmed absent on both Friday and Saturday.

**Weeks start after the current one**, not four weeks from today — stable Sunday–Saturday blocks rather than a sliding window that renames itself every morning.

**The first month is partial**, since four weeks out lands mid-month. Labeled *Rest of September 2026*; calling it *September* would be a lie when three of its weeks are in the sections above.

**Week headings read "Aug 23–29"**, or *"Aug 30 – Sep 5"* when a week straddles two months. Compact enough for the small uppercase heading style; *"Week of Aug 23"* is friendlier but noticeably wider.

**Sections migrate as time passes** — a task in *Aug 23–29* moves to *Rest of This Week* when that week arrives. Day sections already do this; it's just more visible when a whole section's worth moves at once.

### The branch that swallowed it

Shipped broken the first time: selecting the grouping produced one flat list with no headings at all. The prototype's section builder has a chain of `else if`s, and one of them reads *"main tab, and grouping isn't dueDate"* — it handles category and assignee, then sends anything it doesn't recognize to a single "Tasks" body section. Horizon matched that condition, fell to its `else`, and the branch written to handle it sat lower in the chain, unreachable.

Fixed by excluding horizon from that condition rather than by moving code, so the two branches can't fight over the same tasks. Verified by driving the prototype's own handlers headlessly — opening the sort screen, changing the grouping, re-rendering — which returns: Overdue, Today, Tomorrow, Rest of This Week, Aug 23–29, Aug 30 – Sep 5, Sep 6–12, Sep 13–19, October 2026, No Due Date.

Worth noting the shape of the miss: the classifier was right and unit-tested across 160 dates and four weekdays, and none of that touched whether the classifier was ever *called*. Testing the piece isn't testing the wiring.

### Sort levels

`forHorizonGrouping` includes the **due-date levels**, which `forDueDateGrouping` deliberately omits. Under due-date grouping every section is a single date, so ordering by date decides nothing; a weekly or monthly section holds tasks due on different days, so it decides quite a lot.

### Scope

**All Tasks and the category pills.** A pill suits it even better: a category holds fewer tasks over the same span of time, which is exactly when one heading per day reads worst — fifteen tasks making fourteen headings that hold one row each.

**It lands on every pill at once.** Category tabs share a single sort configuration, so choosing this grouping applies to all of them, not the one being looked at. True of Due Date and Category grouping too, but easy to meet by surprise, so the explanation on that screen says so outright.

**The level list differs by one pair.** Category tabs drop the *Category A–Z / Z–A* levels — every task in the tab already shares a category, so they'd order by something that isn't the tab. The date levels stay, since weekly and monthly sections span several days. Same rule Due Date already follows there; `forHorizonCategoryTab` is `forHorizonGrouping` minus those two.

**Empty sections vanish here more often.** Verified on the Personal pill: Today, Tomorrow, Rest of This Week, Aug 23–29, Sep 6–12, Sep 13–19 — *Aug 30 – Sep 5* simply isn't there, because nothing is due that week. Correct, and it reads oddly the first time: a section you know exists is absent. Left as is. Rendering empty weeks would trade a small surprise for permanent clutter on exactly the sparse lists this grouping is meant to help.

**Not the other tabs.** Not Today (already just today plus overdue), not Overdue (its own per-day breakdown), not No Due Date (nothing to group by). Completed is arguable and left out: completion dates run backwards, so a horizon inverts awkwardly.

## Search Bar Fields

Settings → Appearance → **Search Bar Fields**. Six switches deciding where the search bar looks. Global — the same scope applies in every tab, and it persists until changed here.

| Field | Default | Finds |
| --- | --- | --- |
| Task subject line | on | The title |
| Task notes | on | The words in the notes, formatting stripped |
| Categories | off | Category names, orphans included |
| Assigned To | off | The Companies field |
| Status | off | Not Started, In Progress, Waiting on Someone Else, Deferred, Completed |
| High priority tasks | off | Tasks marked High |

**"Search Bar Fields", not "Search fields".** The shorter name was ambiguous in a way that matters on a settings screen: "fields" reads as things you type into as easily as things being searched. Naming the search bar removes the doubt, and the screen's own title matches the row so arriving somewhere confirms you meant to. The row summary dropped its "Searching" prefix at the same time — with the label above it, the word appeared three times in two lines.

**Subject and notes are separate rows, not one built-in default.** Notes off is the genuinely useful case: a long note throws hits you didn't want, and subject-only search is precise. Subject off is odd but allowed — see below.

The note reads: *"Select the fields you want the Search Bar to search in each tab. At least one field stays selected."* It leads with the instruction rather than describing the mechanism, which is what the earlier wording did — "Search looks for your text in the fields ticked here" explains how the screen works to someone already looking at it.

**The last field on can't be switched off.** Its row disables while it's alone and unlocks the moment another is ticked, so no particular field is ever stuck; you simply can't reach zero. The alternative — allowing zero and letting search quietly match nothing — fails at a distance from its cause: you'd hit it later, in a tab, with nothing to connect it to a setting. A disabled switch explains itself while the screen is still in front of you, and it's the same pattern as the greyed pill rows and the collapse child toggle. `AppSettings` enforces it a second time, since a stored value could arrive empty from a future migration.

**Notes always search `plainText`.** Searching raw HTML for "li" would match every bulleted note. The stripped copy is derived per keystroke and discarded — the stored body keeps its formatting, and nothing is written back.

### The vanishing search results — a prototype-only fault

Searching returned the right count but drew only the first section. Leaving the tab
and returning showed everything.

**The cause was a stale flex-child height.** An on-screen readout of the frame's own
geometry settled it: `rows:15 heads:10 list:302/1716 kbd:0px dev:752`. Every row was
in the DOM, the keyboard allowance was correctly zero, the frame was back to full
height — and the list was still 302px tall, the height it had while the keyboard was
up, holding 1716px of results. Nothing was hidden or unpainted. The list was simply
the wrong size, so everything past the first section sat below its bottom edge, and
switching tabs forced the relayout that fixed it.

Changing the frame's height doesn't reliably make Edge or Safari on iOS re-measure a
flex child inside it. Four earlier diagnoses each fixed something that wasn't broken.
The lesson worth keeping: when a symptom survives three fixes, stop theorizing and
print the machine's own numbers on the screen.

**What exists in the code because of it:**

- **`syncFrame()` is the one measurement, with one home.** Called by the viewport
  listeners *and* by `reopenApp()`, which has no viewport event of its own. Three
  symptoms turned out to be this same stale height: vanishing search results, a list
  stuck at 302px, and *Explore with sample data* hiding under the browser toolbar
  after a simulated relaunch. A real launch has nothing focused and no keyboard, so
  the simulation blurs the active element, zeroes the keyboard allowance and
  re-measures.
- **The list relayouts on every viewport change**, not only when redrawn — the
  crucial difference, because the keyboard closing redraws nothing. A `ResizeObserver`
  on the frame covers resizes the visual viewport doesn't report.
- **`--kbd` is non-zero only while an input is genuinely focused**, recomputed on
  `focusin`, `focusout` and orientation change. iOS never tells a page the keyboard is
  open, and doesn't reliably report it closing either — blur is the event that
  actually marks the end of typing.
- **`renderList` ends with `repaint()`**: display removed, a geometry property read to
  force a synchronous reflow, display restored, and a second read scheduled on the next
  frame for when the viewport is still settling. The search input schedules one more on
  a zero timeout — typing is the only path with the keyboard up and the frame moving
  underneath the render. Ugly, and cheap at this size.
- **`-webkit-overflow-scrolling: touch` is gone** from all four scrollers. Redundant
  since iOS 13, when momentum scrolling became the default. Removing it fixed nothing,
  but it was obsolete and every scroller had the same exposure.
- **A shadowed variable was silently throwing.** A local named `el` shadowed the `el()`
  helper, so `repaint(el("list"))` called an element as a function. Renamed to
  `focused`. This was also why the prototype stalled at startup in sandboxed in-app
  viewers — not viewer strictness, as first assumed.
- **The demo link sits in flow, not pinned** to the bottom of the sign-in screen.
  Pinned, it fell below the fold in any short viewport with nothing to indicate it was
  there.

**Sandboxed viewers get an opaque origin**, which shapes three things. *Reading*
`window.localStorage` throws before any method is called — a `try` around `getItem`
doesn't help when the property access itself is the fault — so storage is resolved once
through a guarded probe and every later use is a null check. Keyboard tracking and the
`ResizeObserver` are wrapped too; neither is load-bearing, and an embedded viewer
refusing them shouldn't stop the script. And such a viewer strips exception detail:
every fault arrives as a bare `Script error.` with no file or line, so the whole script
is wrapped and startup failures print into a bar at the top of the frame with their real
message. Silent in a normal browser.

**No equivalent risk in Swift.** SwiftUI has no analogue — `List` doesn't hand
rendering to a CSS compositor layer, and there is no keyboard inset to subtract from a
frame height by hand. This was a prototype fidelity problem, not a design one, and none
of the machinery above has a counterpart to port.

**Collapse is suspended while a search is running.** Found in use: searching returned results under headings that were already collapsed, so the matches were counted but not shown. Every section that survives a search now renders expanded, on every tab and whichever fields are being searched, and the chevron disappears rather than offering a control that would do nothing.

The state is suspended, not cleared — clearing the search restores exactly the arrangement you had, including the remembered No Due Date collapse. That one was the worst case: it can sit collapsed for days, so a search matching an undated task would have found it and hidden it.

**Search never reorders.** Matching rows stay in the tab's grouping and sort; sections with no matches disappear. There's no relevance ranking anywhere — a task whose subject *is* the search term sorts no higher than one mentioning it once in a note. A list that reshuffled itself as you typed would make it impossible to tell whether a task moved or you'd lost sight of it.

**High only, and the label says so.** The field started as *Importance*, matching all three values, on the argument that a field matching one of three reads as broken when you type "low" and get nothing. That argument turned on the label: *Importance* promises all three, *High priority tasks* promises one. With the honest label the narrow behavior is the better one — Normal is the default nobody sets deliberately, so matching it returned most of the list, and Low is not something anyone searches for.

The word "High" is appended to the haystack only when the task carries it, so typing "high" matches and "low" finds nothing, exactly as the row states.

Sorting Options still has *High Priority First*, which gathers High tasks in every tab with nothing typed and nothing to switch back. This field is for High *within* a search, not a substitute for that sort.

**Excluded, with reasons**, recorded in `SearchField` so they don't get added later by accident: dates (nobody types a date the way it's stored), recurrence ("every 2 weeks" is generated text, and *Recurring Tasks* is a sort level), percent complete and effort (typing "50" would collide with every note containing 50).

**The Settings row instructs, then reports** — *"Select the fields you want the Search Bar to search in each tab — currently Task subject line, Task notes."* — so the common question is answerable without opening the screen. Worth having because the scope is sticky: a narrow configuration follows you into every tab and every session until changed.

## Task details in lists

Settings → Appearance → **Task details in lists**, a screen with one switch per tab. Default off everywhere: rows show everything they show today, and turning a tab **on** is what hides its detail.

With details hidden a row keeps the **subject, its category colors, and the due date**. The bell, the repeat summary, "Waiting", the assignee, the completion stamp and the progress bar all move into the task itself.

**The progress bar goes too.** It was left in at first on the grounds that geometry doesn't crowd a row the way a second line of text does — but a row that still carries a bar isn't the plain subject line the setting promises, and the percentage is a detail like any other.

**The due date stays.** It's the field people navigate by and the only one that turns red when late. Under due-date grouping the section heading already says the day, so the row is arguably redundant there — but ungrouped, in a category tab, and in Overdue it's doing real work, and a rule that varies by grouping would be harder to predict than one that doesn't.

**Per tab, not global.** Density is a per-list preference: a category pill scanned for what's next wants subjects only, while All Tasks may want the full picture. That's the same reasoning as the sorting settings, and unlike those it fits on one screen.

**Completed isn't offered.** Hiding detail there removes the completion date, which is often the only thing telling one finished row from another — the tab would become a column of subjects. The note says so in half a sentence, rather than leaving the gap to be read as an oversight.

**The note sits above the rows, not below them.** It describes what the whole screen does, and the list grows with every category — a footer under a dozen tabs is below the fold, read only after the screen has already been used. Headers explain, footers qualify.

**Two bulk buttons, not one that flips.** *Hide in all tabs* and *Show in all tabs*. Once a few tabs differ — the normal state — a single button has to decide what to call itself, and whichever it picks is wrong for half the screen.

**Stored as the set that differs from the default**, like `hiddenBadgeTabs`. A new category needs no migration and a deleted one leaves nothing orphaned.

**The category rows come from `orderedCategories`**, so they follow the manual order from Categories management, a rename carries the row with it, and a new category appears on its own. Every configurable tab is listed whether or not it currently earns a pill — a settings screen that dropped rows as categories emptied would look like it had lost them.

**Placed under *Subject lines viewable in task lists*.** Both decide how much a row shows. Organization governs what appears and in what order, which is a different question.

## Collapsible sections

Tap any section heading to collapse it. The heading stays, with its **full count** — a collapsed section should still say how much is inside — and the chevron rotates rather than swapping glyphs, so the header doesn't reflow when it turns.

**Session-only, keyed by tab + section title.** The same category collapsed in one tab doesn't vanish in another. Not persisted: date sections like "Wed, August 19" stop existing, so stored keys would accumulate forever.

**Cleared when a tab's grouping changes**, since the sections themselves are replaced and the keys would point at nothing.

**A Settings toggle governs it**, defaulting on — a heading with a chevron teaches itself, and there's no cost to a feature you don't use. Switching it off expands everything, or sections would stay hidden with no control left to reveal them.

**Overdue can be collapsed too.** It's pinned to the top so late work can't hide, and letting it collapse partly undoes that — but treating people as capable won out.

### One section remembers: No Due Date in All Tasks

Settings → Collapsible sections → **Keep No Due Date as you left it in the All Tasks tab**, default **off**. With it on, collapsing that one heading in All Tasks survives a launch. Everything else still reopens.

**Why this section and no other.** The reason collapse isn't persisted is that date sections stop existing, so stored keys accumulate pointing at nothing. No Due Date is different in kind: it's a *pinned* section, built separately by `TaskStore` from `noDueDatePlacement` in every grouping — due date, category, ungrouped alike. It survives a regroup, which is exactly why it's exempt from the clear-on-regroup rule that governs the session set. And it's one Boolean, not an unbounded set.

**Scoped to All Tasks, not every tab.** The category pills qualify on the same reasoning, but per-tab memory means keys that orphan when a category is deleted and drift when one is renamed — housekeeping the session version never needed. One tab, one flag, no pruning.

**The No Due Date tab is deliberately excluded** and stays session-only. Everywhere else the section is a slice of the list; in that tab it *is* the list, so a remembered collapse would open onto a single header and empty space.

**A child of the collapse toggle above it.** `collapsibleSections` is global, so with it off there are no chevrons anywhere and this governs nothing. The row is disabled rather than hidden — hiding it leaves people hunting for a setting they saw once — and the stored value is kept, so turning the parent back on restores the preference.

**Default off because that's the safer behavior**, not because it's the lesser feature. A section that reopens can't hide work from you indefinitely; folding the undated list away is a deliberate choice, which is what a default-off toggle is for.

**The label says what you get, not what the code does.** *As you left it* rather than *Keep collapsed*: the toggle collapses nothing by itself, and the natural-sounding label would imply it does — with this on and the heading expanded, nothing happens. It also covers both directions, which is the honest description.

Rejected along the way: *Collapse State* (developer vocabulary), *Remember…* (accurate but vague about what's remembered), and the negative framing *Don't reopen No Due Date* — precise, but a switch whose "on" means "don't" makes people stop and parse it. Also rejected inverting the whole setting (*Reopen all headings on launch*, default on) for the same reason the other toggles read as they do: on means more behavior.

**"The All Tasks tab", not "All Tasks".** The bare name reads as a description of tasks rather than a place.

**State is handed across when the toggle flips**, in both directions: switch it on with the section collapsed and it stays collapsed; switch it off and the session set adopts the current state. Nothing jumps open or shut underneath you as a side effect of changing a preference about *persistence*.

**With placement set to Don't show** there's no section to collapse. The flag is kept and ignored, so it comes back with the section.

**The prototype had to grow storage for this.** Nothing else in it persists — every setting is in memory for the session — so `localStorage` appears exactly once, holding these two values under `taskperfect.undatedCollapse`, wrapped in `try`/`catch`. Some browsers refuse it on `file://` or in a sandboxed frame, and a settings toggle isn't worth a thrown exception; where it's refused the values are session-only and everything else behaves identically. In Swift both are ordinary `UserDefaults` keys alongside the rest.

**And it exposed a bug in *Simulate reopening the app*.** A real launch builds a fresh `TaskStore` and a fresh `TaskListView`, so everything in memory is gone. The prototype's JavaScript never restarts, so `reopenApp()` was returning to a screen that had quietly kept its collapsed sections, its selected tab and its search text — reporting that state survives a launch when it doesn't. It now discards the three things a launch would take: `collapsed`, `activeTab` back to All Tasks, and the search field. `persisted` is deliberately left alone, since standing in for `UserDefaults` is its entire job.

This only mattered once something was *meant* to survive. Before that, everything surviving looked plausible.

## Complete Task in the editor

A **Complete Task** row at the foot of the task sheet, above Delete with clear space between them. It flips to **Reopen Task** on a completed task — same place, obvious opposite.

**Deliberately lighter than the delete bar.** Two full-width bars of equal weight in the same place are easy to hit wrongly, and spacing alone is a thin defence on a phone. So this reads as a normal row in ink, and only the destructive one is heavy and red.

**It routes through the same completion path as the checkbox**, so the *Confirm before completing task* preference governs it without a second implementation of the rule. Reopening is never gated, matching the list.

**No undo window.** Completing is instantly reversible by reopening, so an undo bar would be a third setting for something the app already lets you take back.

## Categories on a task

**One row under Importance**, showing the chosen categories as colored chips. Tapping it opens the full list. The list grows with every category added, so an inline picker either caps and hides some — which then needs promotion rules so a ticked one stays reachable — or takes over the sheet.

**The first chip is bold.** It decides where the task files under category grouping, so it shouldn't look interchangeable with the rest. Selecting appends rather than inserts, for the same reason.

**Orphans appear as chips marked "not in list"** — on the task but absent from the master list, the case being someone deleting a category in desktop Outlook while tasks still carry it.

**Chips wrap rather than scroll.** `FlowLayout` exists because SwiftUI has no wrapping stack: `HStack` pushes overflow off the edge, and `LazyVGrid` forces equal widths onto chips whose natural sizes differ.

**Nothing downstream changed.** Categories are still an array on the task, so grouping, the pill bar, sorting, filtering, the color spine and the No Category tab all read the same data — only the editor moved.

**Selecting appends rather than inserts.** The first category decides where a task files under category grouping, so reordering silently would move it to a different section.

## Default text sizes

Both size controls start one step below where they began.

**Category subject styling:** base is 16pt in Swift, 15px in the prototype. The ±range is untouched, so Default now sits where −1 used to, with three steps down and four up still reachable. The row's own CSS matches the base — a completed row renders with no inline style, so if the two disagree the struck-through rows sit at a different size.

**Notes:** `.callout` rather than `.body` — exactly one step below on the iOS type scale, and it still scales with Dynamic Type. A hardcoded point size would go smaller but stop responding to it. The size menu is labelled around the new default rather than by absolute size, with one step below and three above.

## Per-task bold and italic

A task can override its category's bold and italic — **only** those two. Colors, fonts and sizes stay with the category, because emphasis sits *within* a style while a different color would make a task look like it belongs somewhere else, which is the one thing category styling exists to communicate.

**Its own section, below Categories**, headed *Font Emphasis* with a note: *"For the occasional task that needs to stand out from others in its category. Everything else follows the category's own styling."*

The placement is the point. These controls override a category's styling, so meeting them *before* picking a category invites using them as general formatting. Below it, the order teaches the relationship — pick a category, then adjust its style. Disabling them until a category exists was considered and rejected: an uncategorized task should still be able to stand out.

**Size is a third override**, alongside bold and italic — a stepper rather than a cycling button, because it carries a value rather than being on or off. Stepping below the floor returns it to "follow the category", which is the third state the other two get from their off position. The first press adopts the category's own size, so stepping from *Category* moves one notch rather than jumping to zero.

**"Use category style" clears all three.** Re-setting whichever you wanted is simpler than three separate resets for something done rarely.

**The Outlook mirroring doesn't extend to size.** Conditional formatting rules can test for a substring but can't set a *variable* font size, so `size+2` in the marker is read by Task Perfect only. Bold and italic still mirror.

**Three states, not two.** Unset follows the category; on and off force the value. A plain `Bool` couldn't express "unset" — it would default to `false` and quietly un-bold every task in a bold category. So the model is `Bool?`, and the control cycles unset → on → off rather than toggling.

**Stored in the task's `Mileage` field** as `TP:bold`, `TP:italic`, `TP:bold,italic`, or `TP:nobold` for an explicit off. That's so Outlook's **conditional formatting** can mirror it: two rules testing whether Mileage *contains* "bold" and "italic". Contains, not equals — with equals, `TP:bold,italic` would match neither.

**The Mileage row isn't shown in the app.** The field is the app's storage for the marker, and an editable control over it invites someone to type into a field they don't know is spoken for.

Nothing is lost by hiding it: `setMileage` preserves any text it doesn't own, so mileage typed in Outlook survives even though Task Perfect never displays it. Outlook remains the place to read or clear it.

**Neither the app nor Outlook owns the whole field.** Mileage is editable in Outlook, so the app reads and writes only its own marker and preserves anything else: `Round trip to Dayton; TP:bold` keeps both. The Mileage row in the editor shows and edits the text part alone.

**And Outlook can still break it.** Clearing Mileage there removes the marker and the task reverts to its category style — silently, since a missing marker is indistinguishable from an intentional clear. That's inherent: the flag has to live somewhere Outlook can read for the conditional formatting to work, which is the same thing that lets Outlook overwrite it.

**Overdue still forces bold**, and italic still honours the override, so a late task changes weight and color without changing shape.

## Subject fonts

Eight, in picker order: **System, Arial, Bodoni MT, Calibri, Mono, Rounded, Serif, Times New Roman**. Each option previews its own family, so the list reads as a font list rather than a list of words.

**Two kinds sit in one list.** System, Rounded, Serif and Mono resolve through `Font.system(design:)` and adapt to Dynamic Type and whatever system face the user has chosen. Arial, Bodoni, Calibri and Times resolve through `Font.custom` and are fixed faces. They belong together because Outlook users expect Arial and Times *by name*, not by category.

**Named families need their bold face requested by name.** Unlike `Font.system`, `Font.custom` won't synthesize weight from a `.bold` argument — asking for Arial and bold gives you regular Arial. `Design.customFontNameBold` supplies `Arial-BoldMT` and friends. `relativeTo: .body` keeps Dynamic Type working, which a fixed-size custom font would otherwise break.

A name absent from the device falls back to the system font silently. That's the right failure: a missing face shouldn't make a task unreadable.

**The overdue rule still holds.** An overdue row forces bold while keeping the category's family, size and italic, so a row changes weight and color as it crosses its due date but not its shape. `font(forcingBold:)` is the single place that's decided.

## Category tab sorting

Settings → **Sorting Options → Category Tabs**. Applies to category pills only — the fixed tabs each answer a specific question and shouldn't be reconfigurable into answering a different one.

**Grouping Options:** Due Date (a section per day, as All Tasks does) or Ungrouped.

**"Ungrouped" isn't one section.** Overdue stays pinned at the top and No Due Date keeps the placement set in Display settings, so it yields up to three. Named "Ungrouped" rather than "None" because none would promise something it can't deliver.

**Sorting Within Group:** four levels, each offering Due Date (soonest / furthest), Alphabetically (A–Z / Z–A), High Priority Tasks, Recurring Tasks, or None.

A level only decides when every level above it ties. With Alphabetically first, a tie needs identical subjects — so levels 2–4 will appear inert. That's correct, not a fault. The chain earns its keep with splits at the top: **High Priority → Recurring → Due Date → A–Z** puts two piles in order, then dates them, then names them.

High Priority and Recurring aren't orderings at all — they're yes/no splits, putting one pile ahead of the other and leaving ordering within each to the next level. Useful first, nearly useless third.

**Overdue and No Due Date sections keep their own ordering** even inside a category tab. They're pinned sections, not part of the configured sort.

### The completed banner

All Tasks, Today and every category tab carry a banner reading *"Show 7 completed tasks"* / *"Hide 7 completed tasks"*, appearing only when that tab actually holds completed tasks.

**The main-tab banner drives the existing global `showsCompleted`** — the same value as the hamburger's "Show completed" and the Settings toggle. Four views of one setting, not four settings. Category tabs use their own `categorySort.includesCompleted`, because "is this category finished?" is a different question from "do I want done items in my main list?".

**The counts differ per tab, correctly.** All Tasks reports every completed task in range; Today reports only what was completed today, so its banner is usually absent — verified at 7 versus 1 against the same fixtures.

### Pill visibility

A category pill shows when it has active tasks, or has completed tasks and the category-tab "Show completed" is on.

**A pill you're standing in gets a reprieve.** Complete the last task in a category and the tab stays put rather than vanishing under you; it goes when you next select a different tab. Sheets and Settings don't count as leaving — the reprieve ends exactly when you'd expect.

**Each category tab answers only for itself.** `categoriesShowingCompleted` is a set of category names, not one flag — a single shared value meant revealing completed tasks in Personal also revealed them in LMC Projects, which is what the banner in each tab implies it isn't doing.

Stores the categories that **do** show them, so one created later defaults to hiding completed work with nothing written for it — the same inversion as the badge and visibility sets. The flag is keyed by name, so it follows a rename, clears on delete, and is restored by undo alongside the style and ordering.

**The Category Tabs sort screen has no completed toggle.** With per-category state there's no single value it could show. The banner is the control, and it sits in the tab it affects. The main-tab screen keeps its toggle, because that one genuinely is a single global value with several views.

**Badges take the tab as a parameter and never read `activeTab`.** This is the trap that per-tab settings create: badges compute every tab at once, so a filter consulting the tab you're standing in hands every other tab that tab's answer. Symptom was turning completed on in All Tasks pushing the No Category badge up, then watching it fall when you navigated away.

`visibleTasks(for:)` is the fix — `allTabCount` asks for `.all`, `uncategorizedTasks` for `.noCategory`, and only the list rendering passes the active tab.

**Three numbers, two meanings.**

| Shown | Counts | Completed included? |
|---|---|---|
| Today tab badge | what the tab lists | yes, when that tab's banner is on |
| Line under the logo | overdue + due today | never |
| App icon badge | overdue + due today | never |

The badge answers "what's in here"; the other two answer "what still needs doing". They agree until you reveal completed tasks in Today, at which point the badge rises and the other two hold — because **finishing work shouldn't make the app look busier**, and an icon badge climbing after you tick something off reads as broken.

**The Today badge and the "due today" count are different numbers.** The badge counts what the tab lists, completed included when that tab asks; `todayOutstanding` counts what's still to do and drives the header line and the app icon. A finished task isn't outstanding, so the app icon shouldn't move when you reveal completed work. Previously the badge hardcoded `!isComplete`, which is why it never moved at all.

**Every tab that can show completed tasks answers only for itself.** `tabsShowingCompleted` is a set of tab IDs — All Tasks, Today, No Due Date, No Category. A single shared value meant the banner in All Tasks also revealed completed tasks in Today, which is exactly what a banner sitting inside a tab implies it isn't doing.

**Overdue and Completed carry no banner.** Overdue excludes completed tasks by definition, and the Completed tab shows nothing else, so a toggle in either would be meaningless.

**No Due Date needed its filter changed before it could have a banner.** `undatedTasks` excluded completed tasks outright, so there was nothing to reveal. It now includes them when that tab asks.

**No completed toggle in Settings or on any sort screen.** The banner in each tab is the only control.

Those two were leftovers from when `showsCompleted` was a single global value that four controls all pointed at. Once it went per-tab they had nothing honest to show: a switch reading "off" while a tab visibly displayed completed tasks was reporting "all four are on", not a state. The sort-screen one was doubly wrong — showing completed tasks is a filtering decision, not a sorting one, and it sat inside the *All Tasks* screen while acting on four tabs.

Nothing was lost with them. Each banner still toggles its own tab and only its own, and the bulk helpers they used were deleted rather than left dead.

The hamburger toggle went for the same reason.

**Watch the tab IDs.** `TaskTab.noCategory.id` is `"nocat"`, not `"noCategory"` — a plausible-looking wrong string here fails silently, leaving one tab permanently hiding completed work.

**The completed toggle sits in the tab, not just Settings.** It appears above the list when the category holds completed tasks, so you can flip it while looking at what it affects.

Its label says what tapping does, so it flips between *"Show 2 completed tasks"* and *"Hide 2 completed tasks"*. The count doesn't change — it's the number of completed tasks either way, whether they're on screen or not.

### Dual-category tasks appear in both pills

A task tagged both LMC Projects and Special shows in both, because that's what the tag means — hiding it from the second would diverge from Outlook, where opening the task shows both categories listed.

## Tab badge & visibility controls

Settings → **Tab Badge & Visibility Controls**. One screen, two columns: whether each tab shows a count, and whether it stays in the bar when empty.

**Both on one screen because both are per-tab visibility settings.** Splitting them would mean listing every tab twice. Column headers carry the meaning — a bare pair of switches wouldn't say which is which — and each column has its own All on / All off.

**The column is labeled "Badge count", not "Count"**, matching the wording of the note and of the setting elsewhere in the app. A bare "Count" reads as though it might mean a total rather than a control.

**Categories Development & Controls got the rule applied per section, not per screen.** It has three: your categories, the reset action, and the orphans list. Hoisting all three notes to the top would have buried the first category under a wall of text and separated each note from what it describes — so each note moved to the top of *its own* section instead. *Reset to alphabetical order* stays at the **bottom only**, carrying one line of its own: **"This reorders the category tabs too."**

**Bulk toggles get mirrored to the top; destructive resets don't.** That's the rule, and it's why this button is the exception to the pattern on the other screens. *All on / All off* and *Clear filter* are cheap and reversible — reachability is a virtue. Reset discards a hand-built order with no undo, and a top copy would sit in the path of a thumb reaching for the list rather than somewhere you arrive deliberately. The few seconds of scrolling are a feature. Removing it also bought back three lines at the top of the busiest header in the app.

That line earns its place because the consequence is invisible from the screen you're on. The pills are built from `orderedCategories`, so a reset moves the tab bar — but the tab bar isn't on screen while you're tapping the button, and someone who spent time arranging their pills would be surprised to come back and find them alphabetical. Putting it on the button rather than only in the note above means it's read at the moment of the decision.

**The orphans section couldn't be fixed by mirroring.** Its position is meaningful — a secondary list shouldn't outrank your real categories — but below thirty rows it's invisible. The main header now carries a count (*Your categories · 3 unlisted*), which says the section exists without moving it or adding another control to the top of the screen. Absent entirely when there are no orphans.

The **+** button was left alone in the app: it's in the nav bar, always visible, no scrolling involved.

**The prototype had no equivalent**, and that was a real divergence rather than a cosmetic one. Its Add Category was a row at the foot of the list, below even the orphans — as buried as the controls we'd just mirrored, and giving a worse impression of the screen than the app will give. The prototype's category sheet now carries a **+** in its header beside Done, and the bottom row is gone. Same behavior as the app, and the prototype predicts it rather than contradicting it.

**The task editor's category notes moved up too.** The picker's note now sits above the category list, same reasoning as everywhere else — that list is as long as the category list. It gained a line: *"Use up to two, and only when needed."*

That line is **guidance, not a limit**. Nothing in the code caps the count, and Exchange doesn't either; a task with five categories still syncs and still files under the first. Written as advice because the cost of many categories is a crowded row and a diluted grouping, not a failure — and a rule the app doesn't enforce shouldn't be phrased as one it does. If it should be enforced, that's a different change: a cap needs a disabled state on the picker rows and a decision about what happens to tasks arriving from Outlook already carrying three.

**The Font Emphasis note moved above its controls.** It used to print at the foot of that section, directly beneath the Categories row, where it read as a comment on categories rather than on emphasis.

**The filter list uses the pill rule.** Found in use: completing the last four tasks in a category dropped its pill but left it in Categories Filtering, because the two used different definitions of "in use" — the pill wanted an *active* task, the filter list accepted any task carrying the name, completed included. Both were defensible alone; together they contradicted each other on screen.

`categoriesInUse` now calls `categoryEarnsPill`, so a category leaves the tab bar and the filter list at the same moment, and "gone from the tabs" reliably means "gone from the filters". Orphans are held to the same test.

Filtering to a category holding only completed work is what the Completed tab is for. Switching on completed tasks for that category brings back both its pill and its filter row, so nothing is unreachable. A category pinned with **Always show** keeps its pill and therefore its filter row too — consistent by construction, since the rule is now one test rather than two.

Categories Filtering follows the same rule — its note moved above the rows too, and its **Clear filter** button is mirrored to the top for the same reachability reason as the bulk controls elsewhere. It appears only while a filter is active, so the common path is unchanged. In the prototype both copies are keyed by data attribute, not `id`. Any screen whose list grows with the category list gets its explanation at the top; that now covers Categories Filtering, Tab Badge & Visibility Controls, and Task details in lists.

**The note leads with what the Badge count switch does**, not with why hiding one is cheap. The performance argument — a hidden count isn't calculated at all, which is the whole saving — no longer opens the note, but it isn't lost: it's a clause at the end of the first line ("this can reduce processing time"), where it reads as a reason to use the switch rather than as the explanation of what the switch is. The note now runs: what Count does, what Always show does, then the defaults and the press-and-hold shortcut.

**The All on / All off pairs appear twice** — under the column headers and again below the last row. The list grows with every category, so a single copy is out of reach from the other end. The top copy sits directly beneath the headers, which is what tells you which column each pair applies to; no labels repeat the column names.

Duplicating them exposed one genuine trap, in the prototype rather than the design: the buttons were keyed by `id`, and two elements sharing an id is invalid HTML with the handler matching whichever the browser returned first. Both screens now key their bulk buttons by data attribute. In Swift the same `bulkRow` view is simply emitted twice, calling the same methods — no state to keep in sync, since neither copy holds any.

**The explanatory note sits above the rows.** Same reasoning as the task-details screen: this list grows with every category, so a footer ends up below the fold and is read only after the screen has already been used. Anything explaining what a screen *does* goes at the top; footers are for qualifying a control you can see.

**Three toggles are shown but disabled.** All Tasks, Today and Completed never disappear regardless. Disabled rather than absent: a missing control raises "where did it go", a greyed one answers itself.

**The setting stores which tabs are *pinned*, not which disappear.** Same inversion as the badge setting, for the same reason — a category created next year inherits the default without anything written for it. Verified: a freshly added category is not pinned.

## Tab counts

Each pill's badge can be switched off individually — Settings → **Tab counts** (its own screen), or press and hold the pill itself.

**It's a sub-screen, not an inline section.** Two reasons, and the second is the stronger one:

1. It's the only part of Settings that grows with the user's data — one row per category, unbounded.
2. The counts shown beside each toggle cost a scan per tab. Inline, that scan ran **every time Settings opened**, whether or not the user came to adjust badges. For a feature whose whole purpose is avoiding scans, that was self-defeating. Measured at 3,000 tasks: opening Settings went from **52 ms to 1 ms**, with the 38 ms of counting now paid only by someone who actually opens the screen.

**The collapsed row shows no summary.** A status line like "12 of 14 showing" would have to compute something to tell the user a thing they aren't looking for — this is a set-once preference. A plain navigation row costs nothing.

The pill's long-press menu deep-links straight to this screen rather than to Settings; landing on Settings and hunting for the row would make the shortcut worse than no shortcut.

**A hidden count is never calculated**, which is the point. Hiding a number you already computed saves nothing; the scan is the entire cost. `pill(for:)` computes `count` only when `showsBadge` is true.

Measured at 3,000 tasks across 14 tabs:

| | Tab bar render | Full list render |
|---|---|---|
| All badges on | 73 ms | 385 ms |
| Four kept on | 39 ms | 252 ms |
| All off | 0.1 ms | — |

**The setting stores which badges are *off*, not which are on.** That way a category added next year defaults to showing its badge without anything having to be written first — the alternative silently hides every new tab.

**Long press rather than a second tap target.** A pill is small and its tap already means "switch to this tab". iOS gets a proper context menu with Hide/Show count plus a link into settings; the prototype uses the same gesture and swallows the click that follows so the tab doesn't switch underneath you.

## Row shading

Overdue rows carry a faint red wash (`#FDF5F4`), undated rows a faint blue one (`#E8EDF7`) keyed to the navy No Due Date heading. Settings → **Row shading** turns each off independently; both default on.

**Two toggles rather than one.** The washes answer different questions — one is a warning, the other a classification — and wanting the late warning without the undated one is a reasonable preference.

**Completed tasks are never shaded**, even undated ones. A finished task isn't waiting on anything, so tinting it would signal something untrue. Where a row could qualify for both, overdue wins; that can't happen under the current rules, but the precedence is written explicitly rather than left to chance.

In the prototype the wash is applied to both the swipe wrapper and the row itself — the row slides over the delete track, so tinting only one leaves a mismatched sliver mid-animation.

## Display settings

`Support/AppSettings.swift` + `Features/Settings/SettingsView.swift`. Persisted to `UserDefaults` — deliberately *not* synced to Exchange, since someone who wants undated tasks hidden on their phone may still want them visible in desktop Outlook.

**Tasks with no due date** — three options, reachable from the filter menu (☰) or Display settings:

| Option | Behavior |
|---|---|
| **Top of list** | Section appears above Overdue |
| **Bottom of list** | Below every dated section, above Completed *(default)* |
| **Don't show** | Not listed. Still in the mailbox, still syncing |

The section heading reads **No Due Date** in both placements.

### Hidden never means lost

"Don't show" is the option most likely to cause quiet data loss — tasks vanish and nobody remembers they exist. Three places guard against that:

1. A tappable banner on every tab the setting actually applies to — All Tasks and each category tab — reading *"3 tasks with no due date hidden"* and opening Display settings when tapped. Category tabs show **their own** count, not the global one; a banner pointing at tasks that aren't in the tab would be worse than none. Today, Overdue, No Due Date and Completed get no banner: the first two exclude undated tasks by definition, No Due Date deliberately ignores the setting, and Completed isn't affected — a banner there would explain a rule that isn't in force.
2. The settings screen shows the live count in red under the option
3. The empty state names the count instead of claiming "All clear"

The implementation detail that makes placement work: `DueGroup.sortKey(undatedFirst:)` starts its ranks at 1, leaving 0 free for No Due Date to occupy when lifted to the top.

## Panel navigation (prototype)

The prototype's overlays — Settings, Categories, Category editor, Recurrence — are absolutely positioned siblings that slide in over each other. Closing one used to leave anything stacked above it open, which is how the Categories page ended up covering the task list.

Two rules now, applied everywhere:

- **Back** — up one level. Closes this panel *and everything above it*, revealing the panel beneath.
- **Done** — all the way out. `closeAllPanels()` clears the whole stack and returns to the list.

`closeAllPanels` is the safety net: whatever the route in, that's the route out, so no panel can be stranded on top of the list. Closing the task detail sheet also closes the recurrence editor above it.

The Swift app doesn't need this — `NavigationStack` and `.sheet` manage their own dismissal — so the fix is prototype-only.

## Tabs

Two pills sit directly under the search bar, above the scroll area so they stay put:

| Pill | Shows | Badge counts |
|---|---|---|
| **All Tasks** | Everything, grouped by day | Every task currently listed |
| **Today** | Overdue section, then Today | Active tasks due **today only** |
| **Overdue** | Every past-due task, one section per due date | All overdue tasks |
| **No Due Date** | One section, A–Z | All undated active tasks |
| **Completed** | One section, newest completion first | All completed tasks |
| **<category>** | That category's tasks, grouped by day like All Tasks | Tasks in the category |

**One pill per category**, following the order set in the category manager, each filled with its own color.

Category pills are keyed by name (`TaskTab.category(String)`) rather than by index, so a rename carries the tab with it and a delete takes it away — there's no separate tab identity to keep in sync.

**Selection reads as a ring, not a fill.** Every other pill turns dark ink when selected; a category pill can't, because the fill is already carrying the category color. Selected category pills get an ink ring instead. Label and badge color flip between black and white per swatch luminance, so pale categories stay legible.

**A category tab is a view of the list, not a different kind of list** — it applies the same rules as All Tasks (completed hidden unless asked for, undated placement honored) narrowed to one category. Adding a task from a category tab arrives already tagged with it.

Each completed row prints **"Completed <date>"** at its lower right, in the same abbreviated-weekday format as everywhere else. It renders for any completed task carrying a stamp — not only inside this tab — so a row in the All Tasks completed section answers the same question without a tab-specific special case. Tasks closed elsewhere without a completion stamp simply omit the line.

**Completed sorts by completion date, not due date.** The useful order for an archive is "what did I just do", not "what was due when". Tasks closed elsewhere without a stamped completion date sort to the bottom rather than pretending to be ancient. Like No Due Date, this tab ignores the display preference that would hide its contents — "Show completed" governs All Tasks.

Completed is always visible, unlike Overdue and No Due Date. It can be made conditional the same way if you'd rather it disappear on an empty archive.

**No Due Date ignores the "Don't show" display preference.** That setting governs All Tasks, where undated work is a matter of taste. A tab whose entire job is showing undated tasks can't honor a preference to hide them — so the pill stays, and the tasks are always listed there. Undated tasks have nothing but a name to rank them, hence straight A–Z.

**Overdue and No Due Date only appear when they'd have something in them.** All Tasks and Today are always meaningful, so they always show. Two details make the conditional pills safe:

- **Visibility ignores search and category filters.** It keys off `hasOverdueTasks` / `hasUndatedTasks` (both unfiltered), so a pill doesn't vanish mid-keystroke when a search happens to exclude its contents. It stays put, its badge reads 0, and the empty state explains why.
- **`activeTab` falls back to All Tasks.** `selectedTab` is what the user last tapped; `activeTab` is what survives. Finish the last overdue task — or give the last undated task a date — while standing in that tab and the pill disappears underneath you. Without the fallback you'd be stranded on a tab that no longer exists. It's computed rather than assigned, so nothing mutates state during a view update.

**Sorting is uniform across every group and every tab:** due date first, then A–Z.

Inside a dated section that still ranks by time of day, so a 9am task precedes a 5pm one; equal times fall through to alphabetical, and undated tasks go straight there. Importance no longer ranks anything — the row already flags it with the marker in the trailing gutter, and letting it jump tasks around made a scanned list unpredictable.

**The Overdue tab regroups by date.** Elsewhere everything late collapses into a single Overdue bucket, because *which* day something slipped is noise when you're scanning the week. Inside this tab it's the entire organizing idea, so it breaks back apart into one section per due date, oldest first. Within a section everything shares a due date and nothing else ranks them, so tasks sort **A–Z**. Those dated headings carry the overdue red, since they all describe late work.

**The Today badge excludes overdue on purpose.** Overdue tasks appear in the tab — in their own section at the top, keeping the bold red treatment — but folding them into the number would make it mean two things at once. The badge answers "what's on my plate today"; the red section answers "what did I miss".

**The All Tasks badge matches what's on screen**, so it moves with filters, search, and the show-completed and undated-placement settings. A badge that disagrees with the list below it is worse than no badge.

**Today ignores the display preferences.** No completed tasks, no undated tasks, regardless of settings. Those preferences govern All Tasks, where they're a matter of taste; here they'd contradict what the tab means.

## Dates on rows

Rows print the full date — abbreviated weekday, full month, day, year: **"Thu, August 20, 2026"**. Never "Today" or "Tomorrow": the section heading already names the day, so a relative label on the row wastes the line, and in the Overdue tab it would be actively unhelpful.

Same `setLocalizedDateFormatFromTemplate` approach as the section headings, so field order follows the device locale.

### Scrolling the pill strip

The strip scrolls horizontally, and selecting a pill centers it. That centering sets `scrollLeft` on the strip itself rather than calling `scrollIntoView` on the pill — `scrollIntoView` walks up and scrolls *every* scrollable ancestor, which dragged the whole screen sideways and pushed the list off its left margin when the rightmost pill was tapped. Setting `scrollLeft` can only ever move the strip.

`.screen` and `.list` also carry `overflow-x:hidden` so nothing below the strip can scroll sideways at all.

The Swift version uses `ScrollViewReader.scrollTo`, which is already scoped to its own `ScrollView`.

## List grouping

Sections run: **Overdue → Today → Tomorrow → one section per calendar day → No Due Date → Completed.**

Dated headers show abbreviated weekday, full month, day and year — "Thu, August 13, 2026". Built with `setLocalizedDateFormatFromTemplate` rather than a literal format string, so field *order* follows the device locale: the same code renders "Thu, 13 August 2026" on a UK phone.

Two decisions worth knowing:

**Overdue stays one group** rather than splitting by past day. Anything late needs attention now, and which day it slipped is detail the row already carries. Splitting it would push today's work below a stack of headers.

**Sections are built from the data, not a fixed list.** `DueGroup.day(Date)` carries a midnight-normalized date, and sections sort by `(rank, date)`. Days with nothing due simply don't appear — no empty headers.

## Recurrence

Full support for daily, weekly, monthly and yearly patterns, plus Outlook's regenerating mode.

| File | Role |
|---|---|
| `Domain/Models/TPRecurrence.swift` | Pattern + range types, `summary`, `shortSummary` |
| `Domain/UseCases/RecurrenceEngine.swift` | All date math. Pure, calendar-injected, testable |
| `Features/TaskDetail/RecurrenceEditorView.swift` | The editor, with live preview |

**Patterns:** every N days · every N weeks on chosen weekdays · day N of every N months · the [first–last] [weekday] of every N months · a fixed month/day each year · the [first–last] [weekday] of a given month each year · regenerating (N units after completion).

**Ranges:** never ends · after N occurrences · until a date.

**On rows**, recurrence shows what it repeats rather than a bare icon — "Weekly · Mon Thu", "Monthly · day 5", "1mo after done". Same row space, answers the actual question.

**Completing a recurring task** closes the current occurrence and opens the next, matching Outlook: the finished one stays as a completed record with its recurrence stripped, and a new task appears for the next date. Stripping it matters — otherwise reopening the completed copy would spawn duplicates. When the series runs out, only the record remains.

**Swipe right on a recurring task** for Skip, which advances the due date without recording a completion.

### Three details that are easy to get wrong

**Regenerating counts from completion, not the due date.** A monthly regenerating task finished two weeks late is next due a month from *then*. Fixed schedules don't move. This is why `RecurrenceEngine.complete` picks its reference date based on `isRegenerating`.

**Day-of-month clamps.** "Day 31 of every month" lands on Feb 28 — or 29 in a leap year — not March 3. `setDayClamped` handles it, and the editor warns when you pick past 28.

**Time of day is preserved.** Without `preserveTime`, a task due at 5pm silently drifts to midnight on its second occurrence.

The editor's live preview exists because recurrence rules are hard to read. "The last Friday of every 3 months" means nothing until you see three real dates — everything above the preview is inputs, the preview is the answer.

## Next

Items 2 and 3 of the original list are done — `Persistence/` is SwiftData and offline edits queue durably in `PendingChange` with capped backoff. What remains:

1. `Backend/EWS/SOAP/` — the SOAP client, negotiating auth over `URLSession`
2. `GetFolder` / `SyncFolderItems` — prove the delta stream
3. **The `CategoryList` write** — the one unproven operation, tested early
4. `EWSMapper` — XML to `TPTask` and back
5. Error mapping to `TaskBackendError`
6. Local notifications for reminders (the model is complete; nothing is scheduled yet — mind the 64-pending limit)

`BEFORE-EWS.md` carries the same order with the reasoning, plus the findings that shape steps 1 and 3.

`Session.signIn` has the swap point marked. When `EWSBackend` exists, replace one line — nothing in `Features/` changes.

## Rule worth enforcing

Nothing in `Domain/`, `Features/` or `Persistence/` may reference a type from `Backend/EWS/`. If a view file ever mentions a SOAP envelope, the abstraction has leaked. Treat it as a build-breaking bug.
