# Phase 13 — Polish

**Status:** ready for plan.

**Owner phase:** Phase 13 (Polish).  
**Parent:** `docs/superpowers/specs/2026-08-28-youtube-downloader-mac-design.md`
§5.2–5.3, §5.11, §4.4 (design-system), §12.1 Phase 13, §14.  
**Visual / copy contracts:** `apps/media-grabber/docs/design-system.md` §4.4
Toast; parent §5.3 empty states.  
**Leaf backlog:** `apps/media-grabber/ticket-backlog.md` Phase 13.  
**Scope locked:** 2026-09-23 (pick = ship end-to-end).

---

## Intent

Close the polish gap so everyday use feels finished: wire feedback the design
system already describes (toasts, background failure notifications), finish
first-run → table and emptied-table transitions, ship Phase 12 leftovers (live
column-width readout), bundle Aurora typefaces without a typography redesign,
close Debug menu + Share Extension first-enable as decide-and-ship, then run a
full accessibility pass **last**.

Working name stays `MediaGrabber`. Product name and app icon are **not** this
phase — they open Phase 14 as Step 0.

---

## Not this phase

| Item | Destination |
|---|---|
| Product name (§14) + find-and-replace | Phase 14 Step 0 |
| App icon | Phase 14 Step 0 |
| Aurora body-face swap (drop Inter) | Phase 14 |
| First-run Home copy / composition redesign | Phase 14 |
| Home banner → footer | Phase 14 |
| Per-host adaptive concurrency | Phase 14 (engine) |
| Queue-row drag-reorder | Phase 14 (parked from Phase 12) |

---

## Locked decisions (2026-09-23)

| Topic | Decision |
|---|---|
| Scope rule | pick = ship end-to-end; every IN item has a clear done line |
| Toasts | Success (`<title> saved` + Reveal) + chip-refresh failure; **no** per-job failure toasts |
| Notifications | Native macOS notifications for **job failures only while backgrounded**; never double-fire with toasts |
| Empty states | Finish gaps vs parent §5.3 only; no creative first-run redesign |
| Fonts | Bundle Sora / Inter / JetBrains Mono + `ATSApplicationFontsPath`; Theme uses them; **no** body-face swap |
| Width readout | Live integer **pt** while dragging a column divider; hide on mouse-up |
| Debug menu | **Ship** always-present menu exposing existing `DebugFlags` (Force Onboarding, Reset State, Concurrency Cap); argv parsing stays |
| Share Extension tip | **Ship** one-shot dismissible tip on Home after first Grab (Settings deep-link best-effort); not blocking |
| A11y | Full keyboard / VoiceOver / `prefers-reduced-motion` sweep **last**, after other Phase 13 UI freezes |
| Branding | Name + icon deferred to Phase 14 Step 0 |

---

## Architecture

### Feedback path (toasts + notifications)

```text
QueueEvent / chip refresh result
  → AppModel
      → ToastCenter   (app active + success | chip-refresh failure)
      → NotificationRouter (app backgrounded + job failure only)
  → ToastHost (MainWindow overlay) / UNUserNotificationCenter
```

**ToastCenter** — small `@MainActor` queue of transient items (one line +
optional action). Auto-dismiss ≈ 4s. Stacked bottom-right per design-system
§4.4.

**ToastHost** — SwiftUI overlay on `MainWindow`, peer to the existing
confirmation-dialog overlay. Does not replace `WarningBanner` (engine/host
conditions stay banner-only).

**NotificationRouter** — requests notification permission **lazily** on first
need (not at cold launch). Fires only when `!NSApp.isActive` and a job fails.
Permission denied → silent skip; failure still appears in the table / Inactive
rail badge.

**Double-fire rule**

| Event | App active | App backgrounded |
|---|---|---|
| Job `.completed` | Success toast + Reveal | No toast, no notification |
| Job `.failed` | No toast (row + Inactive badge) | Native notification only |
| Chip refresh failure | Error toast | No toast, no notification — chip stays bad |

Chip-refresh failures are not “download failed while away”: toast only when
the refresh Task completes and the app is active.

### Empty states

Existing model stays:

- `hasGrabbedOnce` **or** non-empty `rowStore` → table chrome (`showsTable`).
- Else → first-run layout (hero + paste + step cards; no table, no rail, no
  Columns).
- After first Grab, step cards never return.
- Emptied queue: table chrome stays; centred
  `TablePresentation.emptyQueueMessage` ("No downloads — paste a link above.").
- Filtered empty keeps `TablePresentation.filteredEmptyMessage`.

This phase **audits and closes gaps** (rail / Columns visibility, first Grab
flipping `hasGrabbedOnce`, emptied vs filtered empty in the AppKit grid). No
new copy, no layout redesign.

### Live column-width readout

During AppKit header resize drag, show a small readout near the active divider
with the live column width in **integer pt**. Hide on mouse-up. Widths continue
to persist via existing `ColumnConfig` / `columns.json`. Implementation lives
in the Downloads grid island (`DownloadsGridHeaderView` / controller) — not a
SwiftUI-only overlay that fights header hit-testing.

### Aurora fonts

- Vendor OFL-compatible Sora / Inter / JetBrains Mono files under app Resources
  (e.g. `Resources/Fonts/`).
- Set `ATSApplicationFontsPath` in the app Info.plist so families resolve at
  launch.
- `Theme.resolvedFont` already looks up by family name; bundling should stop
  silent system fallback for Aurora faces.
- AppKit grid cells that use custom/`NSFont` must resolve the same family names
  after registration.
- Document license + path in leaf README / CLAUDE Known gaps (close the
  “not bundled” gap).
- **No** Theme API change for body-face swap.

### Debug menu

Add an application **Debug** menu that toggles / applies the existing
`DebugFlags` surface:

- Force Onboarding (`-MGForceOnboarding`)
- Reset State (`-MGResetState`)
- Concurrency Cap (`-MGConcurrencyCap`)

CLI argv parsing remains. Menu is the discoverable path for local QA. Menu is
**always present** in the shipped app (not `#if DEBUG`-only) — items are
harmless for users who never open Debug.

### Share Extension first-enable tip

One-shot dismissible tip on **Home**, after first successful Grab:

- Copy explains enabling MediaGrabber under System Settings → Extensions /
  Sharing.
- Primary: open the relevant Settings pane if a stable URL exists; else “Open
  System Settings”.
- Dismiss forever via `AppStorage` (`mg.shareExtensionTipDismissed`).
- Not blocking; not every launch. Tip copy must stand alone if the deep-link
  fails.

### Build order

1. Bundle Aurora fonts  
2. Toasts + notifications  
3. Empty-state gap close  
4. Live width readout  
5. Debug menu + Share tip  
6. **Full a11y sweep last**

---

## Component map

| Piece | Owns | Touches |
|---|---|---|
| `ToastCenter` + `ToastHost` | Queue, auto-dismiss, Reveal action | `MainWindow` overlay |
| `NotificationRouter` | Permission + background failure notify | Job failure path from `AppModel` / queue events |
| Completion / failure observers | Map `.completed` / `.failed` → toast or notification | `RowStore` / `QueueEvent` |
| Chip refresh failure | Propagate shield / yt-dlp refresh failure → error toast | `MainWindow` HealthStrip handlers + `AppModelDiagnostics` |
| Empty-state audit | Close gaps vs §5.3 | `HomeView`, grid empty presentation, rail / `hasGrabbedOnce` |
| Width readout | Live pt label during resize | Downloads grid header / controller |
| Fonts | Files + plist + smoke | App Resources, `Theme`, AppKit cells |
| Debug menu | Wire `DebugFlags` | `MediaGrabberApp` / `Commands` |
| Share tip | One-shot UI + dismiss | Home (after first Grab) |
| A11y pass | Keyboard, VO, reduced-motion | Every screen after UI above freezes |

---

## Accessibility (last)

Parent §5.11 quality floor, applied as one consolidated pass:

- Full keyboard navigation and visible focus on Home, Preferences, About,
  Onboarding, playlist picker, and the Downloads AppKit island.
- VoiceOver labels on every icon-only control (row actions, chip `↻`, batch
  bar, Columns, etc.).
- `prefers-reduced-motion`: motif stops spinning; chip busy spin disabled
  (HealthStrip already has a seam — verify globally).
- Remark / hover-only detail must remain reachable via keyboard focus (parent
  §5.4).
- Budget explicit VO + keyboard smoke on the AppKit grid — heavier than
  SwiftUI screens.

---

## Definition of done

- Success toast + Reveal when a job completes while the app is active.
- Chip-refresh failure toast with reason; chip stays bad on failure.
- Background job failure → one native notification; foreground failure → no
  toast.
- First-run → table and emptied-table match parent §5.3; step cards do not
  return after first Grab.
- Live width readout during column resize; persistence unchanged.
- Aurora faces render when bundled (no silent system fallback for those
  families).
- Debug menu exposes Force Onboarding / Reset State / Concurrency Cap.
- Share tip shows once, dismisses forever; Settings open is best-effort.
- A11y sweep complete per § above.
- Parent §12.1 Phase 13 stub, leaf backlog, and design-system §4.4 stay
  consistent; CLAUDE “Next” advances only when this phase ships.

---

## Risks

| Risk | Mitigation |
|---|---|
| Notification permission denied | Silent skip; table / Inactive badge still show failure |
| Font licensing | Ship OFL-compatible files only; document in README |
| AppKit grid a11y harder than SwiftUI | Explicit VO/keyboard checklist in the plan; do not skip |
| Share tip Settings URL fragile | Tip copy stands alone without deep-link |
| Chip refresh fails while fully inactive | Leave chip bad; no notification (see double-fire rule) |

---

## Testing notes (for plan)

- Unit: `ToastCenter` enqueue / auto-dismiss / stack order; notification
  router active-vs-background gating (inject `isActive`).
- Unit: empty-state predicates (`showsTable` / emptied / filtered).
- UI smoke: success toast Reveal; chip `↻` failure toast; background failure
  notification (manual or launch-arg harness).
- Font smoke: `NSFont(name: "Sora" | "Inter" | "JetBrains Mono", …)` non-nil
  after launch.
- A11y smoke: keyboard traverse Home + grid; VoiceOver labels on Actions;
  reduced-motion stops motif / busy spin.

No live network required for the polish pack except optional manual
notification smoke with a real download failure.
