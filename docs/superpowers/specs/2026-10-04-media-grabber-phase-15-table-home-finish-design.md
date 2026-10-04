# Phase 15 — Table & Home finish

**Status:** ready for plan.

**Owner phase:** Phase 15 (Table & Home finish).  
**Parent:** `docs/superpowers/specs/2026-08-28-youtube-downloader-mac-design.md`
§5.3–5.4, §12.1 Phase 15; `apps/media-grabber/docs/state-flow.md` §4.  
**Leaf backlog:** `apps/media-grabber/ticket-backlog.md` Phase 15.  
**Scope locked:** 2026-10-04 (view-order drag + deferred visual picks; banner→footer closed as already shipped).

---

## Intent

Finish the table and Home surfaces parked out of Phases 12–13: let users
rearrange Downloads rows as a **session view order** (not engine priority),
swap Aurora’s body face off Inter after a visual pick, and do the creative
first-run Home pass the parent still points at Phase 15 for.

Working name stays `MediaGrabber`. Branding remains Phase 17.

**Build order (locked):** ship row drag-reorder first; then present body-face
and first-run variants; then implement Theme / Home from the picks.

---

## Not this phase

| Item | Destination |
|---|---|
| Home banner → footer | **Already shipped** (bottom-docked `WarningBanner` in `MainWindow`) — not Phase 15 work |
| Engine queue reorder / “who downloads next” via drag | **Out** — not a product goal; do not add an engine `reorder` intent |
| Persist manual row order across relaunch | **Out** — session only; revisit only if a later phase owns it |
| Filter-chip clear prompts on drag | **Out** — sort conflict only |
| POT / shield rotation; always-on-cookies; remote `player_client` JSON; per-site helpers | Phase 16 |
| Optional UX extras (subtitles, menu bar, …) | Phase 16 (evaluate at that plan) |
| Product name + app icon; Sparkle / notarization / bundled deps | Phase 17 |

---

## Locked decisions (2026-10-04)

| Topic | Decision |
|---|---|
| Scope rule | pick = ship end-to-end; every IN item has a clear done line |
| Row drag meaning | **View order only** — `RowStore` session list; engine schedule / job list order unchanged |
| Sort conflict | Active column sort + drag → confirm (“sorting will be overwritten”); Proceed clears sort and applies reorder; Cancel = no-op |
| Filters | No extra prompt; filters stay; drag reshuffles within the current visible set’s participation in manual order |
| Manual order lifetime | **Session only** — cleared on quit; cleared when user sets a new column sort (after confirm path or normal sort UI) |
| Playlist groups | Group **headers** not draggable; children may move in the visible list; no engine group-order API |
| Banner → footer | **Closed** — already bottom-docked; remove from Phase 15 IN in parent / backlog / state-flow |
| Body face | **TBD visually** after reorder ships — 2–3 candidates vs current Inter; Sora display + JetBrains Mono stay |
| First-run Home | **TBD visually** after reorder — same §5.3 gates (no table/runway until first Grab; step cards first-run-only; emptied-table does not resurrect steps); composition/copy variants only |
| Branding | Still Phase 17 |

---

## Architecture

### View-order row drag

**Today**

- AppKit Downloads grid supports column header reorder; **rows** are not
  draggable.
- Display order comes from `RowStore` sort / filter / group collapse over
  engine `JobSnapshot`s.
- Engine `jobs` array order is schedule truth; Phase 2 mentioned a future
  `reorder` intent that this phase **explicitly does not ship**.

**Target**

```text
user drags row in AppKit grid
  → (if column sort active) AppModel.confirm(sortOverwrite)
        → Cancel: abort
        → Proceed: clear ColumnConfig sort, then apply
  → RowStore.applyManualOrder(from:to:) / setManualOrder(_:)
  → recomputeVisible() uses manual order when sort is nil
```

- Store something like `manualOrder: [UUID]?` (or non-empty list) on
  `RowStore` — session only, not `columns.json`, not `queue.json`.
- When `manualOrder` is set and sort is off, ordered blocks / children follow
  that permutation for IDs present; new jobs append by existing natural rules
  (plan picks: end of list vs Added-at among unordered).
- Starting a column sort through the normal header UI clears `manualOrder`
  (sort wins). Drag-with-sort uses the confirm path above.
- Selection / batch bar / playlist collapse keep current contracts; prune
  rules unchanged.

**Confirmation copy** — one `ConfirmationRequest` (non-destructive): title +
one sentence that active sorting will be cleared; Confirm / Cancel. No
suppression key required unless plan finds an existing pattern that fits.

### Aurora body-face swap

**Today**

- Theme Aurora body resolves `Inter` (bundled or system fallback per Phase 13).
- Display = Sora; mono = JetBrains Mono.

**Target**

After reorder DoD:

1. Present 2–3 body candidates (+ Inter as control) for a visual pick.
2. Vendor OFL files for the chosen face; remove Inter from Aurora body path
   (Inter may remain on disk only if another theme still needs it — Tape Deck
   does not use Inter; prefer delete unused Inter resources if nothing
   references them).
3. `Theme` Aurora body resolver points at the chosen PostScript/family name;
   smoke test `NSFont(name:size:)` non-nil.

Spec does **not** invent the final face name — the plan’s visual task records
the pick, then implementation tasks wire it.

### First-run Home redesign

**Today**

- Parent §5.3 structure is live: hero + paste + three step cards; table appears
  after first Grab; emptied table keeps chrome with empty line.

**Target**

After reorder (and optionally after or alongside body-face pick):

1. Present 2–3 composition/copy variants under the same behavioral gates.
2. Implement the chosen variant in App Home / empty-state views only.
3. No change to probe, runway arming, playlist picker, or engine submit.

---

## File / seam map (indicative)

| Area | Likely touch |
|---|---|
| Manual order | `RowStore.swift`, `RowStore+Groups.swift`, visible-item ordering |
| Drag UI | `DownloadsGridController*` / table data source (AppKit row drag) |
| Sort clear + confirm | `ColumnConfig` / column header sort cycle; `AppModel` confirm helper |
| Body face | `Theme.swift`, font Resources, Info.plist `ATSApplicationFontsPath` |
| First-run | `HomeView.swift`, empty-state helpers, copy strings |
| Docs | parent §12.1, leaf backlog, CLAUDE, `state-flow.md` §4, design-system if face name lands |

Exact types and method names land in the implementation plan.

---

## Testing & DoD

**Reorder**

- Unit: manual order changes visible sequence; sort confirm clear path; cancel
  leaves sort + order untouched; quit/session reset documented (no persist
  file).
- Manual / UI smoke: drag on grid; group header refuses drag; sort+drag shows
  dialog.

**Body face**

- Chosen face resolves; Sora / JetBrains still resolve; no Theme API break for
  Tape Deck.

**First-run**

- First-run → first Grab → table; emptied table does not bring step cards back;
  runway still hidden until resolve.

**Suite**

- Full `GrabberKitTests` + `AppUnitTests` + lint green before Phase 15
  *(shipped)*.

---

## Parent / leaf doc updates (this phase’s design pass)

- Phase 15 stub: IN = view-order row drag + body-face + first-run; note banner
  already footer.
- `state-flow.md` §4: remove or rewrite the “banner → footer” parked row;
  retarget row-drag row to **view order (session)** not “engine order + UI”.
- Archived Phase 13/14 “Out → Phase 15” banner lines may stay historical; living
  stubs must not list banner as open Phase 15 work.

---

## Open picks (blocked only on visual tasks, not on writing the plan)

1. Aurora body face family (after candidate review).
2. First-run Home composition variant (after mockup review).

The implementation plan may sequence: Tasks 1…N reorder → Task “visual gate”
(no code until picks) → font + Home tasks. Plan must not leave either pick as
an unowned TBD past ship.

---

## Sibling phases (unchanged ownership)

- **Phase 16 — Site / identity maturity.** POT/shield rotation; always-on-cookies;
  remote `player_client` JSON; per-site helpers; optional UX extras.
- **Phase 17 — Branding & release gate.** Product name + icon; Sparkle /
  notarization / bundled deps if Developer ID exists.
