# Task Perfect — working files

**Snapshot: 2026-08-17**

The three delivered files carry a timestamp in their names
(`task-perfect-project-2026-08-17-1411.zip` and so on) so one download can be
told from another. Filenames *inside* this folder never carry it — the docs refer
to each other by name, and stable paths diff cleanly in Git.

Everything here is plain text. No build step, no dependencies, nothing to install.

## What's in this folder

```
TaskPerfect/            49 Swift files + 2 test files — the real iOS app (needs Xcode on a Mac)
  START-HERE.md         ★ Read this first. Reading order, the three things most
                          likely to trip you up, and the compile warning below.
  PROJECT-SETUP.md      Xcode target settings, Info.plist, signing, first run
  BEFORE-EWS.md         What's established against the real mailbox, and the one
                          operation still unproven
  BACKEND-CONTRACT.md   The TaskBackend seam — what EWSBackend must satisfy
  PARITY.md             Prototype vs Swift: where they may have drifted
  README.md             Every design decision and the reasoning behind it
  Tests/                Unit tests for RecurrenceEngine and TaskSorting
  VerifyEWS/            Connectivity probe — see BEFORE-EWS.md
task-perfect-prototype.html   The whole app in one browser file
HOW-TO-CONTINUE.md      This file
.gitignore              At the repo root, alongside TaskPerfect/
```

## The one thing nobody should discover for themselves

**None of the Swift has ever been compiled.** Not once, by anyone — it was written
without a Swift toolchain available, so all 49 files plus the tests have been
reviewed by eye and never by a compiler. The design has been thought about
carefully; the syntax has not been checked.

That is the single biggest risk in this handoff, and the first thing the build team
will hit. It is stated at the top of `TaskPerfect/START-HERE.md` too, because
someone reading a first build error as their own setup mistake will lose an hour
before suspecting the code.

The prototype is the opposite case: `task-perfect-prototype.html` has been run in a
real browser and its behavior is verified. Where the two disagree, the prototype is
the better evidence — `TaskPerfect/PARITY.md` says where they are most likely to.

## If you are the build team

Go to `TaskPerfect/START-HERE.md` and stop reading this file. It exists for
whoever is carrying the project between conversations, which is a different job.

## The prototype

`task-perfect-prototype.html` — one self-contained file. HTML, CSS and JavaScript
in a single document, no external anything.

- **Run it:** open in any browser. Double-click on a computer; on iPhone, save to
  Files and open with Safari. Tap **Explore with sample data**.
- **Edit it:** any text editor. VS Code, Notepad, TextEdit (*Format → Make Plain
  Text* first). On iPhone: Textastic or Koder.
- **Share it:** email or AirDrop the single file.

The prototype and the Swift app are kept in sync — a change to one belongs in the
other. That is the rule that keeps the prototype worth having: the moment it
drifts, it stops being a reference and becomes a second thing to maintain.

## Where the project stands

Built and working in both the prototype and the Swift code:

- **Seven fixed tabs plus one per category** — All Tasks, Today, Overdue,
  No Due Date, Completed, No Category, then the eight categories in their colors
- **Grouping and sorting configured per tab**, seven independent screens under
  Settings → Sorting Options. Groupings include due date, category, completion
  date and assignee; four priority sort levels within each
- **Full task editor**: dates with a None option, recurrence (daily/weekly/
  monthly/yearly plus regenerating), categories, effort, Assigned To
- **Notes with optional rich text** — colors, fonts, bullets, numbering, indent.
  Plain by default; the toggle is per task and maps to the Exchange body type
- **Add, edit, complete and delete**, each confirmation independently toggleable
- **Undo** on task and category deletion, with independent windows
- **Category management**: add, rename (cascading onto tagged tasks), recolor,
  delete, reorder. 48-color palette, 25 Outlook presets plus 23 extended
- **Per-category subject styling**: color, 8 fonts, size, bold, italic
- **Per-tab control** over badge counts, whether a tab hides when empty, and
  whether completed tasks show
- **Offline**: opens with no connection, edits queue durably and sync on reconnect
- **Unlock** by password, Face ID, or stay signed in
- **Collapsible section headings**, session-only — with one opt-in exception:
  No Due Date in All Tasks can be set to stay collapsed across launches
- **Search fields**: six switches choosing where search looks; subject and
  notes on by default, at least one always selected
- **Task details in lists**: per-tab control over whether rows show reminders,
  repeats, assignees and completion dates. Subject, categories and due date always stay
- **Reminders on open**: a banner listing reminders that came due while you were
  away, with local-only dismissal. Toggle in Settings, default on

Not built yet:

- **The EWS SOAP layer itself** — the seam is cut and everything above it is
  written against the `TaskBackend` protocol. `TaskPerfect/BEFORE-EWS.md` covers what
  is known about the server; `TaskPerfect/BACKEND-CONTRACT.md` covers what the new
  layer has to satisfy.
- **Scheduled local notifications for reminders.** The model is complete and
  `RecurrenceEngine` already carries a reminder to the next occurrence keeping its
  offset; nothing is ever scheduled. The on-open banner covers the same ground
  while the app is running and doesn't depend on them.
- **The Xcode project and the app icon.** Both are deliberately left for a Mac —
  `TaskPerfect/PROJECT-SETUP.md` covers the first, and
  `TaskPerfect/Resources/Assets.xcassets/AppIcon.appiconset/README-ICON.md` the
  second.

## Picking this up in a new conversation

Nothing carries over between conversations except a short note about the project,
so **the files are the record** — they hold every decision.

Attach the zip and say:

> Internal iPhone app for Intermedia Hosted Exchange 2016 over EWS. Swift/SwiftUI
> plus an HTML prototype kept in sync — changes to one mirror to the other.
> `TaskPerfect/START-HERE.md` is the orientation; `BEFORE-EWS.md` covers what's
> been established against the real mailbox; `README.md` has the design decisions.

Then whatever you want to work on.

## Version control, when you're ready

Once a Mac is in the picture, put all of this in a Git repository. It's all text,
so Git tracks it well and gives you a way back from any change that doesn't work.
`.gitignore` is already in place at the repo root.

```
git init
git add .
git commit -m "Task Perfect: prototype plus Swift foundation"
```
