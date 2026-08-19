# Tests

Two files, covering the two pure-function types where a regression is silent and
expensive:

| File | Covers |
|---|---|
| `RecurrenceEngineTests.swift` | Date arithmetic: intervals, the day-of-month clamp, `nth`/`last` weekday, ranges, and what `complete()` produces |
| `TaskSortingTests.swift` | The comparator chain, which levels each grouping offers, and pruning |

## Wiring them up

These files belong to a **test target**, not the app target. See
`../PROJECT-SETUP.md` §7. In short: File → New → Target → Unit Testing Bundle,
name it `TaskPerfectTests`, add these files to that target only, set its Host
Application to `TaskPerfect`.

They use `@testable import TaskPerfect`, so the module name must match the target
name. If you name the app target something else, fix the import.

## ⚠️ They have never been run

There is no Swift toolchain in the environment where they were written — they
were produced by reading the implementation line by line, not by executing
anything. **Expect a handful of assertions to need adjusting on the first run.**

When one fails, the useful question is which side is wrong. Two of these tests
exist specifically because the answer might be "the implementation":

- `testMonthlyRelativeFourthFriday` and `testLastWeekdayIsNotTheFourth` pin down
  that `.last` and `.fourth` differ in a five-Monday month. If they agree, the
  ordinal handling has collapsed.
- `testComparatorIsNeverTrueInBothDirections` checks the comparator is a strict
  weak ordering. `Array.sorted(by:)` is entitled to misbehave if it isn't, and the
  symptom would be an occasional wrong order that nobody can reproduce.

## Why these two files and not others

They are pure, deterministic and calendar-injected, so they test cleanly with no
mocks or hosts. And they are exactly what starts producing wrong answers when a
real `EWSMapper` begins feeding them server data instead of fixtures — dates that
arrive in UTC, recurrence patterns Outlook allows that the editor never
generates, `completeDate` missing on tasks an older client marked done.

Worth adding next, in rough order of value:

1. `TPBody.plainText` — the HTML-to-text path has real edge cases (nested lists,
   entity decoding) and no coverage
2. `LocalStore.enqueue` collapsing — create-then-delete sending nothing, and an
   update riding along on a queued create. It needs an in-memory
   `ModelContainer`, so it is a slightly bigger lift
3. `TPTask.setStatus` / `setPercentComplete` coupling — small, and the rules are
   Exchange's rather than ours, so they must not drift

## Calendar discipline

Every test injects a fixed UTC Gregorian calendar with an explicit first weekday.
Do the same in anything you add. `RecurrenceEngine` defaults to `.current`, which
is correct for the app and useless in a test: results would change with the
machine's time zone, and a suite that passes in one office and fails in another
teaches nobody anything.
