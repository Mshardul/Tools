# Ticket file

Rules for `tickets.md` in this directory. This file is the source of truth for ids, columns, the predefined value lists, priority, story points, status, and how a row may change.

## Ids

The id is `mg-001`, `mg-002`, and so on. The board is a single board for the whole app, so the id has no vertical segment.

The number is zero-padded to three digits and counts by one from `001`. After `999`, the next id gains a digit. An id is never reused, including when a row is `dropped`.

## Columns

One row per ticket, in this order:

| Column      | Format                              |
| ----------- | ----------------------------------- |
| ID          | `mg-NNN`                            |
| Title       | Up to 10 words.                     |
| Type        | One value from the Types list.      |
| Component   | One value from the Components list. |
| Epic        | One value from the Epics list.      |
| Priority    | `p0` to `p4`.                       |
| Points      | `1`, `2`, `3`, `5`, or `8`.         |
| Status      | One value from Status.              |
| Depends on  | Comma-separated ids, or empty.      |
| Description | Up to 30 words.                     |
| Remarks     | Free text, or empty.                |
| Created     | `dd-mm-yyyy`.                       |
| Updated     | `dd-mm-yyyy`.                       |

Remarks stay empty unless the row cannot be understood without them, or a status move needs a reason.

## Predefined lists

A value in use is never renamed or removed, because finished rows cannot change. A value that is no longer wanted is marked `retired`: no new row uses it. A new value is added by editing this file.

### Types

| Type          | Meaning                                   | State  |
| ------------- | ----------------------------------------- | ------ |
| `bug`         | Something is wrong, missing, or unusable. | active |
| `improvement` | Something works and is made better.       | active |
| `feature`     | Something new a user can do.              | active |
| `chore`       | Maintenance with no user-visible change.  | active |

### Components

A ticket has the one component that holds most of its change.

| Component | Covers | State |
| --- | --- | --- |
| `theme` | Palettes, colour and type tokens, fonts, icons, motion, elevation. `Sources/App/Theme`. | active |
| `controls` | Shared skinned controls: buttons, toggles, steppers, pickers, segments. `Sources/App/Controls`. | active |
| `chrome` | Window shell, brand row, health strip, banner, toasts, dialogs, sheets, menu bar. `MainWindow`, `Chrome`, `Toasts`, `Shield`, `Debug`. | active |
| `home` | Paste field, runway, first-run screen, playlist picker, add flows. `Home`, `Ingress`. | active |
| `table` | Downloads table, header, rows, groups, empty states. `Table`, `Rows`. | active |
| `onboarding` | First-run set-up steps. `Onboarding`. | active |
| `preferences` | Preferences panes, Diagnostics. `Preferences`. | active |
| `about` | About and Developer pages. `About`. | active |
| `engine` | Download engine and everything behind it. `Sources/GrabberKit`. | active |
| `tooling` | Build, CI, release, scripts. | active |

### Epics

| Epic | Meaning | State |
| --- | --- | --- |
| `visual-fidelity` | The app looks and reads as the design system and mockups specify. | active |
| `code-health` | Code, logs and docs say and do what they claim. | active |

## Priority

`p0` is severe. `p4` is a nit. The scale is `p0`, `p1`, `p2`, `p3`, `p4`.

When a row is filed, the agent suggests a priority and the user agrees or overrides it. The agent asks when it needs a clarification.

A row that comes from an audit starts from the audit severity: `severe` → `p0`, `high` → `p1`, `medium` → `p2`, `low` → `p3`, `nit` → `p4`.

## Story points

The value is `1`, `2`, `3`, `5`, or `8`.

When a row is filed, the agent suggests the points and the user agrees or overrides them. The agent asks when it needs a clarification. A row with no points is not offered for implementation until it has some.

## Status

`backlog`, `todo`, `in progress`, `blocked`, `completed`, `dropped`.

A new row is `backlog`. `todo` means the user has picked the row for the next round of implementation.

### Moves

| From | To | When |
| --- | --- | --- |
| `backlog` | `todo` | The user picks the row. Every ticket in Depends on is `completed`, `todo`, or `in progress`, or moves to `todo` in the same step. |
| `todo` | `backlog` | The user un-picks the row. A row that another `todo`, `in progress`, or `blocked` row depends on moves back only in the same step as that row. |
| `todo` | `in progress` | A group containing the row is picked for implementation. |
| `in progress` | `completed` | The user accepts the code. |
| `in progress` | `todo` | The user rejects the session. |
| `todo`, `in progress` | `blocked` | Work cannot proceed. The reason goes in Remarks in the same edit. |
| `blocked` | `todo` | The cause is cleared. |
| `backlog`, `todo`, `in progress`, `blocked` | `dropped` | The user decides. The reason goes in Remarks in the same edit. |

`completed` and `dropped` do not change, Remarks included. A row is never deleted.

### Offered for implementation

A row is offered for implementation when its status is `todo`, it has points, and every ticket in Depends on is `completed`. A row whose Depends on includes a `backlog`, `blocked`, or `dropped` ticket is not offered and stays `todo`; editing its Depends on is how a `dropped` dependency is resolved.

### What may change

- Title, Type, Component, Epic, Priority, Points, Depends on, and Description change only while the row is `backlog` or `todo`.
- Remarks change in any status except `completed` and `dropped`.
- Created is the day the row is added.
- Updated is that same day, and it changes on every later edit these rules allow, Remarks-only edits and status moves included. On a `completed` or `dropped` row it is the day the row reached that status.

## Words in a row

The row describes the work. It does not mention audits, agents, prompts, or reports.
