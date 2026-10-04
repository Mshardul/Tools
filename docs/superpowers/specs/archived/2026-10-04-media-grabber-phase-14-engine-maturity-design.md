# Phase 14 — Engine maturity

**Status:** shipped. Plan archived with this spec under
`docs/superpowers/{specs,plans}/archived/`.

**Owner phase:** Phase 14 (Engine maturity).  
**Parent:** `docs/superpowers/specs/2026-08-28-youtube-downloader-mac-design.md`
§12.1 Phase 14, §6–§7 (rate / probe), `apps/media-grabber/docs/state-flow.md` §4.  
**Leaf backlog:** `apps/media-grabber/ticket-backlog.md` Phase 14.  
**Scope locked:** 2026-10-04 (engine-first cut; sibling phases 15–17 own the rest).

---

## Intent

Close the engine gaps that everyday queue behaviour still fakes or papers over:
playlist groups as engine state (not UI-only roll-up), a visible metadata-probe
throttle (the bucket already exists but wait is silent), per-host adaptive
concurrency (today’s cap is global), and an explicit ship-or-drop ruling on
`.shieldDown` / `.userReset` so they stop living as diagram-only.

Working name stays `MediaGrabber`. Branding remains Phase 17.

---

## Not this phase

| Item | Destination |
|---|---|
| Queue-row drag-reorder | Phase 15 |
| Home banner → footer | Phase 15 |
| Aurora body-face swap | Phase 15 |
| First-run Home redesign | Phase 15 |
| POT / shield rotation | Phase 16 |
| Always-on-cookies model | Phase 16 |
| Remote `player_client` order JSON | Phase 16 |
| Per-site helpers beyond YouTube | Phase 16 |
| Optional UX extras (subtitles, menu bar, …) | Phase 16 (evaluate at that plan) |
| Product name + app icon | Phase 17 |
| Sparkle / notarization / bundled deps | Phase 17 |

---

## Locked decisions (2026-10-04)

| Topic | Decision |
|---|---|
| Scope rule | pick = ship end-to-end; every IN item has a clear done line |
| Cut | Engine-first; UI / site / branding are sibling phases 15–17 |
| Playlist groups | Engine owns group registry + aggregate roll-up; UI reads engine truth; persistence keeps writing groups (already real on `Persistence`) |
| Probe throttle | Keep live `MetadataTokenBucket` (already wired in `EngineDependencies.live`); add **wait visibility** on the job while `acquire` blocks — Remark + optional snapshot field; **no new `JobState`** this phase (queued/probing stay; rail mapping unchanged) |
| Per-host adaptive concurrency | Move `adaptiveCap` / `cleanStreak` / `strikeLoweredCap` from global scalars to per-`RateHost`; scheduler accounts running slots per host against that host’s cap; prefs cap remains the global ceiling |
| `.userReset` | **Ship** — circuit reset goes through `RatePolicy.next(..., .userReset)` instead of deleting the dict entry out-of-band |
| `.shieldDown` | **Drop** — dead shield does not halt the queue (matches today’s deliberate design); remove the parked row from `state-flow.md` §4 rather than adding `QueueHaltReason.shieldDown` |
| Branding | Still Phase 17 |

---

## Architecture

### Playlist-group aggregate state

**Today**

- `PersistedPlaylistGroup` + `Persistence.savePlaylistGroups` / `loadPlaylistGroups` are real.
- `AppModel.playlistGroups` is the write path; `RowStore` rebuilds `PlaylistGroup` roll-up from child `JobSnapshot`s + a local collapse map.
- `NoopPersisting` no-ops groups (tests / engine-without-persistence).
- There is no engine-owned group model and no group aggregate on `QueueSnapshot`.

**Target**

```text
submit playlist / collapse / group action
  → DownloadEngine (owns [PlaylistGroupState])
      → persist via QueuePersisting.savePlaylistGroups
      → QueueSnapshot.playlistGroups: [PlaylistGroupSnapshot]
  → AppModel / RowStore render from snapshot (collapse is engine state)
```

`PlaylistGroupState` (engine-internal) and `PlaylistGroupSnapshot` (boundary) carry at least: `id`, `title`, `sourceURL`, `isCollapsed`, and derived counts / roll-up fraction matching what `RowStore` computes today (`totalCount`, `completedCount`, `failedCount`, `runningCount`, `cancellableCount`, `rollupFraction`). Derived fields are computed in the engine when emitting a snapshot — UI does not re-invent eligibility counts for group action enablement.

Collapse toggles and group actions (`pauseAll` / `retryFailed` / `cancelAll`) call into the engine; AppModel stops being the source of truth for the registry. Loading at launch: engine (or AppModel once) feeds persisted groups into the engine before the first snapshot consumers depend on them — plan picks the single boot path so UI and engine never diverge.

### Metadata-probe throttle visibility

**Today**

- `MetadataTokenBucket` is already constructed in `EngineDependencies.live` and injected into `MetadataProbe`.
- `acquire()` sleeps until a token frees; the job has no field or Remark that says it is waiting.
- `UnlimitedMetadataTokenBucket` remains for tests / fixtures that want no throttle.

**Target**

While a job is blocked in `acquire`, surface wait on that job:

- Prefer a `JobSnapshot` field such as `probeWaitUntil: Date?` (nil when not waiting), filled from the bucket’s next-available estimate.
- Remark catalog gains one line when `probeWaitUntil != nil` (e.g. waiting for probe slot) — same Remark channel as backoff / host rate (parent §5.4; not a new Status string).
- Do **not** add `JobState.waitingForProbe` this phase — rail filters already include `.queued` / `.probing` under Downloading.

Bucket API grows a way to observe “next token available at” without turning acquire into a busy poll from the UI. Plan specifies the exact seam (`MetadataTokenBucketing` extension or engine-side wrapper).

### Per-host adaptive concurrency

**Today**

- `RateLimiter.states` is per-host; `adaptiveCap` / `cleanStreak` / `strikeLoweredCap` are global.
- Any host strike drops the **global** cap to 1.
- `effectiveCap = min(rateLimiter.adaptiveCap, prefsCap)` gates all downloads.

**Target**

```text
effectiveSlots(host) = min(host.adaptiveCap, preferencesCap)
running(host) counted only among jobs with that rateHost
Scheduler.nextDownloads respects per-host free slots; global prefsCap still bounds total concurrency
```

- Strike / clean-success adjust **that host’s** trio only.
- `HostRateDisplayState.concurrencyReducedToOne` becomes per-host (already displayed per host; stop using a global flag).
- `SchedulerInput` gains whatever the plan needs for per-host free-slot accounting (either precomputed blocked IDs as today, or an explicit per-host remaining-slots map — pick one shape in the plan, don’t leave both).
- Log events that today say global cap changes become per-host.

### `.userReset` (ship)

**Today:** `RateLimiter.resetCircuit` / `resetAllCircuits` clear dict entries directly; `RatePolicyEvent.userReset` is tested in `RatePolicy` but never fired from the limiter.

**Target:** reset applies `RatePolicy.next(state, .userReset, …)` and stores / clears the result the same way `.cleanSuccess` does (normal → drop entry). Banner / cooldown-chip “Retry now” keep calling the same public reset APIs; behaviour stays “host back to normal,” implementation goes through the policy.

### `.shieldDown` (drop)

Do not add `QueueHaltReason.shieldDown`. A dead POT provider already has chip + banner (`potProviderDown`) without halting the queue; that stays. Delete the parked capability row from `state-flow.md` §4 in this phase’s doc updates so it cannot resurrect as an orphan.

---

## Component map

| Piece | Owns | Touches |
|---|---|---|
| `PlaylistGroupState` / snapshot | Engine registry + roll-up | `DownloadEngine`, `QueueSnapshot`, `Persistence` load/save path, `AppModel` / `RowStore` |
| Probe wait field + Remark | Visibility while bucket blocks | `MetadataTokenBucket` / probe, `JobSnapshot`, Remark catalog / `TablePresentation` |
| Per-host cap trio | Strike / clean / display | `RateLimiter`, scheduler input, rate logs, HealthStrip display state |
| `userReset` wiring | Policy-faithful circuit reset | `RateLimiter.resetCircuit*` |
| Doc parking table | Drop `.shieldDown` row; retarget per-host cap row to Phase 14 done | `state-flow.md` §4, parent §12.1, leaf backlog |

---

## Definition of done

- Playlist groups survive relaunch with engine-owned roll-up; group actions and collapse do not depend on UI-only registry as source of truth.
- A job waiting on the metadata token bucket shows probe-wait in Remark (and snapshot field); unlimited bucket still available for tests.
- Adaptive concurrency is per-`RateHost`; one host’s strike does not serialise unrelated hosts; prefs cap remains the ceiling.
- Circuit reset goes through `.userReset` in `RatePolicy`.
- `.shieldDown` queue halt is explicitly dropped; parking table updated.
- Parent §12.1 Phase 14 stub, leaf backlog, and `state-flow.md` §4 stay consistent; CLAUDE “Next” advances only when this phase ships.

---

## Risks

| Risk | Mitigation |
|---|---|
| Dual source of truth during boot (AppModel groups vs engine) | Single load path into the engine before UI binds; AppModel stops mutating a parallel registry |
| Probe-wait field races with cancel | Cancel must unblock `acquire` (already cancellation-aware); clear `probeWaitUntil` on leave |
| Per-host caps starve global fairness | Keep prefsCap as total concurrent downloads; per-host cap only limits that host’s share |
| Scheduler input shape churn | Plan picks one accounting approach; extend `SchedulerInput` without rewriting the evaluate loop |

---

## Testing notes (for plan)

- Unit: per-host strike lowers only that host’s cap; clean streak raises only that host; prefs clamp still holds.
- Unit: `userReset` transitions cooldown / circuitOpen → normal via `RatePolicy`.
- Unit: playlist group snapshot counts match child job states after complete / fail / cancel.
- Unit: probe wait sets and clears `probeWaitUntil` around a throttled `acquire` (fake clock).
- No live network required; use existing engine fakes / clocks.

---

## Sibling phase stubs (locked with this cut)

Recorded here so parent §12.1 and the leaf backlog can copy them without inventing a second cut:

- **Phase 15 — Table & Home finish.** Queue-row drag-reorder; Home banner → footer; Aurora body-face swap; first-run Home redesign.
- **Phase 16 — Site / identity maturity.** POT/shield rotation; always-on-cookies; remote `player_client` order JSON; per-site helpers beyond YouTube; optional UX extras (evaluate at plan time).
- **Phase 17 — Branding & release gate.** Product name + icon; `BACKLOG.md` revisit; Sparkle / notarization / bundled deps if Developer ID exists.
