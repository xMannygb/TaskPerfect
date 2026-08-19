# Parity: the prototype vs the Swift

Two implementations of the same app. Every change was made in both — but they were
**verified very differently**, and that asymmetry is the thing to understand before
you trust either one.

| | `task-perfect-prototype.html` | `TaskPerfect/*.swift` |
|---|---|---|
| Lines | ~5,300 | ~12,300 across 49 files |
| Ever executed | **Yes** — opened in a browser, exercised, bugs found and fixed | **No.** Never compiled, let alone run |
| Verified by | Behavior | Reading |

So where the two disagree about what *should* happen, **the prototype is the better
evidence.** It has been through a real render loop; the Swift has been through a
careful read. A careful read is not nothing, but it does not catch an off-by-one in
a bucket boundary or a list that was updated in one file and not the other.

**This is not a list of known bugs.** Nothing below has been confirmed broken. It
is a list of the places where a divergence is most likely and least visible, in
rough order of how much it would cost to discover late.

---

## How to use this

Do these comparisons **after** the app compiles and runs against the mock, and
**before** you write any EWS code. Open the prototype in Safari on the same phone,
side by side with the running app, and walk each row.

Where they differ, the question is which is right — not which to change. Both were
written from the same decisions, and those decisions are in `README.md`. Fix the one
that drifted, and if you cannot tell which drifted, `README.md` is the tiebreaker.

---

## 1. Sort level lists — highest risk

`CategorySortOptions.SortLevel` carries **eleven** static arrays naming which levels
each grouping offers: `forHorizonGrouping`, `forHorizonCategoryTab`,
`forDueDateGrouping`, `forCategoryGrouping`, `forUngrouped`,
`forCompletedByCompletion`, `forCompletedByDue`, `forCompletedUngrouped`,
`forNoCategoryByDate`, `forUndatedByCategory`, `forUndatedUngrouped`.

Each has an equivalent in the prototype. Eleven hand-maintained lists in two
languages is the highest-drift construct in the project: adding a level means
editing up to twenty-two places, and omitting one produces a menu that is quietly
missing an option rather than an error.

**Check:** for each of the seven sorting screens, open the level picker in both and
compare the options offered, in order. `Tests/TaskSortingTests.swift` covers the
Swift side of this once it runs.

## 2. Horizon grouping buckets

"Today, Tomorrow, Weeks, Months" coarsens with distance: today, tomorrow, the rest
of this week, four whole weeks, then whole months. The **boundaries** are the risk —
where "rest of this week" ends and "next week" begins, whether the fourth week
rolls into months, what happens to a task due 400 days out.

**Check:** the same fixture set in both, with tasks placed deliberately on each
boundary. Compare section headings and counts, not just the ordering within.

## 3. Tab badge and visibility rules

Three independent per-tab switches — badge count on/off, hide when empty, show
completed — across eight-plus tabs. The README records that two controls were
removed here once `showsCompleted` went per-tab, and that
`TaskTab.noCategory.id` is `"nocat"` rather than `"noCategory"`. A plausible-looking
wrong string in either implementation fails silently, leaving exactly one tab
misbehaving.

**Check:** toggle each of the three switches on each tab in both, and confirm the
tab bar responds identically. Pay particular attention to No Category and No Due
Date.

## 4. The "earns a pill" rule

A category leaves the tab bar and the filter list at the same moment. The prototype
had a real bug here — the pill wanted an active task, the filter list accepted any
task carrying the name, completed included — and the fix routed both through one
predicate (`categoryEarnsPill`).

**Check:** complete the last active task in a category. Its pill and its filter row
must disappear together, in both. Then switch on completed tasks for that category
and confirm both come back.

## 5. Search field set

Six switches choosing where search looks, with at least one always selected.

**Check:** the six labels match, the defaults match (subject and notes on), and the
"can't turn the last one off" guard behaves the same way in both.

## 6. Collapse behavior

Session-only, with one opt-in exception: No Due Date in All Tasks can persist
collapsed across launches. Collapse is also suspended while a search is running —
every section that survives a search renders expanded and loses its chevron.

**Check:** collapse a section, search, confirm results show expanded, clear the
search, confirm the collapse state returns. Then relaunch and confirm nothing
persists except the one opt-in case.

## 7. Recurrence preview

The editor shows the next three dates live. Both implementations compute this
independently — the Swift through `RecurrenceEngine.upcoming`, the prototype
through its own arithmetic.

**Check:** the awkward patterns, since the simple ones will agree. Day 31 monthly
across February. "Last Monday" in a five-Monday month. A regenerating task completed
two weeks late. Feb 29 yearly in a non-leap year. `Tests/RecurrenceEngineTests.swift`
pins the Swift side of exactly these once it runs.

## 8. Per-category subject styling

Color, eight fonts, size, bold, italic. The font lists must match, and the Swift
side resolves two different ways — four system designs through `Font.system`, named
families through `Font.custom`.

**Check:** the eight font names, and that each renders as a visibly different face
in both. A `Font.custom` name that doesn't resolve on iOS falls back silently to the
system face, which looks like the styling simply not working.

---

## Two things that cannot drift, and one that will

**Cannot drift:** the category color palette (48 entries, indices matched to EWS)
and the Outlook status/importance/sensitivity raw strings. Both are wire formats.
If they differ, one is simply wrong, and the mailbox is the arbiter.

**Will drift, and that's fine:** anything below the interaction layer. The
prototype uses `localStorage` behind a guarded probe; the Swift uses SwiftData and
the Keychain. The prototype simulates sync with timers; the Swift has a real change
queue with capped backoff. Nobody should try to reconcile those — they are the same
decisions expressed in two very different runtimes.

---

## Keeping it true

The rule until now has been that a change goes into both. That was right while one
person held the whole thing in their head, and it stops being right the moment a
build team is working in Xcode daily.

**Suggestion, for the team to decide rather than inherit:** once the Swift app
compiles and runs on a device, promote it to the source of truth and let the
prototype freeze as a reference snapshot of intended behavior. Keeping two
implementations in step by hand has a real cost, and the reason the prototype
existed — seeing the app without a Mac and without a build — stops applying the day
the real one runs. Whatever you decide, write it down in `README.md`; the worst
outcome is a prototype that is *sometimes* maintained, because then nobody knows
whether a difference is a bug or an intentional lag.
