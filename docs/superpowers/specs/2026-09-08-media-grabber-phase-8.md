# Playlist (Phase 8)

**Status:** design complete. Plan:
`docs/superpowers/plans/2026-09-08-media-grabber-phase-8.md`. Parent spec:
`docs/superpowers/specs/2026-08-28-youtube-downloader-mac-design.md` §5.3–5.5,
§7.4 token bucket, §12.1. Phase 2 shells: `docs/superpowers/specs/queue-foundation.md`
(`PlaylistGroup`, `playlistGroupID`, per-request probe cancel deferred here).
Phase 7 (YouTube hardening) is the previous increment:
`docs/superpowers/specs/2026-09-07-media-grabber-phase-7.md`.

Phases 1–7 built the download pipeline, queue, retry, cookies, rate limits,
and YouTube identity on paste/Grab. Phase 8 is playlist: one `--flat-playlist`
dump, a picker before any rows, then **one independent job per checked video**
with a shared group id. Group header, spine, and actions are a `RowStore`
aggregate. The engine never runs yt-dlp over a playlist with `--playlist-items`.

YouTube e2e this phase is **watch = one video** and **`PL` playlist page =
picker → group**. Mix, Radio, Watch Later, Liked, uploads (`UU`), and channel
`/videos` do not open the picker. Picker, batch enqueue, groups, token bucket,
and probe cancel are extractor-agnostic; this phase does **not** call
`--flat-playlist` for non-YouTube URLs (no surprise expansion of archive.org
collections). SoundCloud sets and similar wait for a later classifier arm.

UI copy stays plain language. Never "POT", "yt-dlp", or `player_client` in a
user-visible string (onboarding's existing "yt-dlp is missing" probe sentence
is unchanged).

---

## 1. Scope

**In this phase:**

- **`PlaylistLink`** — classify a paste before any probe. YouTube watch (even
  with `&list=`) → existing `engine.preview` (`-J --no-playlist`). YouTube
  `/playlist?list=PL…` → one `engine.previewPlaylist` (`-J --flat-playlist`).
  YouTube Mix / Radio / WL / LL / UU / channel `/videos` → runway error, **no
  probe**.
- **`PlaylistDump` / `PlaylistEntry`** — parsed from the flat JSON: playlist
  title, uploader, extractor, `webpage_url`, entries (watch URL, title,
  duration, thumbnail URL, extractor/`ie_key`, playlist index). Not stuffed
  into `MediaMetadata`.
- **`PlaylistPickerView`** — auto-opens on a successful playlist dump, before
  any rows. Checkbox · thumbnail · title · duration; Select all/none (filtered
  rows only); title filter; duplicate banner + per-row warnings; footer
  `M of N selected · K already in queue · ≈ H:MM:SS`. Virtualized list; no
  item cap; thumbnails from dump URLs, visible rows only.
- **Add M** — one `DownloadRequest` per checked row. Inherit runway type,
  quality cap, language, folder. Prefetch title / duration / extractor so
  `Scheduler.needsMetadata` skips `-J` when all three are present. Join an
  existing group when `sourceURL` matches a live group; else new id. Batch
  enqueue, one snapshot.
- **`playlistGroupID` + `playlistIndex`** on `DownloadJob` / `JobSnapshot` /
  `PersistedJob`. Today's snapshot hardcodes `playlistGroupID: nil` — fill it.
  **No** `playlist` / `PlaylistSelection` field on `DownloadRequest`.
- **`MetadataTokenBucket`** — always-on cap on **probes only** (~3 per rolling
  60 s). Counts Home `-J`, playlist `--flat-playlist` (one token), leftover
  per-item `-J`. Downloads unchanged. Waiting for a token is cancellable.
- **Per-request probe cancel** — cancel/remove of a `.probing` job cancels
  that probe (SIGTERM if yt-dlp is up). A request still waiting on the probe
  tail or the bucket is dropped and does not launch. Today's cancel-while-
  probing only kills `childTasks`; probes use `probeTask` — fix that.
- **Table** — fill `PlaylistGroup`. Header + spine + collapse (persisted).
  Children playlist-index order. Block position by max child `addedAt` on
  default Added-at ↓. Chip/column filters: header if any child matches;
  rollup is the whole group. Per-column aggregates (parent hint, 10% progress
  buckets). Group actions: Pause all / Retry failed / Cancel all (confirm +
  `suppressionKey`).
- **Persistence** — `queue.json` `groups: [{ id, title, sourceURL, isCollapsed }]`.
  `playlistIndex` on jobs. Schema version stays **1** (additive). Persistence
  merges jobs + groups so neither write wipes the other. Groups remain in
  `queue.json` while any restored job (queue or history) still has that id.
- **`screens.html` §5** — picker + group table, five-slot skinned runway,
  duration footer, duplicate warnings. design-system §4.3 footer matches.
- **`EngineTuning`** — `metadataProbeLimit` (default 3,
  `MG_METADATA_PROBE_LIMIT`) and `metadataProbeWindowSeconds` (default 60,
  `MG_METADATA_PROBE_WINDOW_SECONDS`).

**Implementation notes.** Comments are single-line why only — no `///`.
`DownloadEngineProtocol` grows `previewPlaylist` and `submitPlaylistItems`.
Fakes: `Tests/AppUnitTests/Support/AppFakes.swift` `FakeEngine` and the private
`FakeEngine` in `QuitCoordinatorTests.swift`. `previewPlaylist` default
`.failure(.malformedOutput)`; `submitPlaylistItems` default `[]`.
`QueuePersisting` / `NoopPersisting` grow groups load/save. `JobSnapshot` /
`PersistedJob` gain `playlistIndex: Int? = nil` (fixtures keep compiling).
Extend exhaustive `LogEvent` `key` / `category` / `fields` switches.

**Deferred (hints in their phase):**

- Other extractors' playlist pages (SoundCloud sets, archive.org collections)
  — a later phase adds a classifier arm; the picker/group APIs stay as they
  are. Not Phase 9 (add flows).
- Mix / Radio / channel `/videos` / Watch Later / Liked — not a phase yet;
  parent §12.1 Phase 8 stays "YouTube watch + `PL` playlist page".
- Queue-row drag-reorder — parent §5.4; no phase yet.
- Chip-refresh toast — Phase 11.
- Diagnostics report-card playlist rows — Phase 10 if warranted (no new
  report-card fields required here).

**Not touched:** Phase 6 rate limiter / circuit / network monitor (bucket is
an extra probe gate, not a replacement). Cookie subsystem. Onboarding.
Preferences panes. Shield. Runway slot layout (still five slots; playlist
dump has no format list, so Format/Language seed from prefs / last-used as
when availability is unknown).

---

## 2. Classify, then one probe

### 2.1 `PlaylistLink`

`GrabberKit/Download/PlaylistLink.swift`. Pure URL parse; no yt-dlp.

```swift
public enum PlaylistLinkKind: Sendable, Equatable {
    case singleVideo
    case youtubePlaylist
    case youtubeUnsupported
}

public enum PlaylistLink {
    public static func classify(_ urlString: String) -> PlaylistLinkKind
}
```

`RateHost(urlString:).canonical == "youtube"` means a YouTube family host
(`youtube.com`, `youtu.be`, `m.` / `music.` / `gaming.` / `youtube-nocookie.com`).

**`.singleVideo`** when YouTube and the path is a watch-like URL: `/watch`,
`/shorts/`, `/live/`, `/embed/`, or `youtu.be/<id>`. **`&list=` is ignored.**
Home keeps today's `-J --no-playlist`.

**`.youtubePlaylist`** when YouTube, path contains `/playlist`, and the `list`
query value starts with **`PL`** (unescaped). `music.youtube.com/playlist?list=PL…`
counts. Only this kind calls `--flat-playlist`.

**`.youtubeUnsupported`** when YouTube and any of:

- `list` starts with `RD` (Mix / Radio), `WL` (Watch Later), `LL` (Liked),
  `UU` (uploads), `OL` (YouTube Music album/library), or other non-`PL`
  playlist ids on a `/playlist` path
- path looks like a channel tab: `/videos`, `/@…/videos`, `/channel/…/videos`,
  `/c/…/videos`, `/user/…/videos`

No probe. Runway error: **This link isn't a video or a playlist.**

**Non-YouTube** → `.singleVideo` (existing preview). This phase never opens
the picker for them.

Trim whitespace before classify. Empty string does not classify (Home already
no-ops).

### 2.2 Preview split

`engine.preview` unchanged (single video).

```swift
func previewPlaylist(_ url: String) async -> Result<PlaylistDump, MetadataError>
```

Same gates as `preview`: shield status refresh, `.networkDown` → `.network`,
`blockedProbeHostIDs` / host cooldown → `.hostBlocked`. Same
`makeContext(url:attempt:0, forceCookies:false)` as preview.

Argv: `["-J", "--flat-playlist", "--no-warnings", "--no-update"] +
extractorFlags(context:) + [url]`. **Not** `--no-playlist`. One process.
Counts as **one** token bucket acquire.

`AppModel.resolvePasted`:

1. Classify.
2. `.youtubeUnsupported` → `resolved = nil`, probe error copy above, no
   engine call.
3. `.youtubePlaylist` → `previewPlaylist`. Success → store the dump, runway
   `✓ "<title>" · N items`, **auto-open the picker**. Failure → same
   `probeErrorMessage` family as today (`Couldn't read the video details.`
   for malformed dumps).
4. `.singleVideo` → today's `preview`.

Grab on a stored playlist dump **does not enqueue**. It reopens the picker.
Cancel in the picker: no rows; runway stays. Checks are **not** remembered
(next open uses §3 defaults). Changing the paste field clears the dump
(`clearResolved`).

Runway Type / Format / Language / Save to stay. Flat dump has no format list
and no audio tracks: Format uses the unknown-availability ladder (prefs /
last-used heights); Language uses the Downloads policy (`YouTube default` /
`Original`) as when `audioTracks` is empty. Grab stays enabled once the dump
succeeds (picker is the commit).

---

## 3. Playlist dump

```swift
public struct PlaylistDump: Sendable, Equatable {
    public var title: String
    public var uploader: String?
    public var extractor: String?
    public var sourceURL: String
    public var entries: [PlaylistEntry]
}

public struct PlaylistEntry: Sendable, Equatable {
    public var watchURL: String
    public var title: String
    public var durationSeconds: Int?
    public var thumbnailURL: String?
    public var extractor: String?
    public var playlistIndex: Int
}
```

Parse the top-level JSON object (`_type` is typically `playlist`). Title from
`title`. Uploader from `uploader` or `channel`. Extractor from `extractor` or
`extractor_key`. `sourceURL` = `webpage_url` if present else the paste URL
(trimmed). `entries` from the `entries` array, skipping objects with `_type`
`playlist` (nested playlists are not expanded).

Per entry:

- **watchURL** — if `url` / `webpage_url` is an `http` URL, use it. Else if
  `id` is present and the dump is YouTube, `https://www.youtube.com/watch?v=<id>`.
  Else skip the entry.
- **title** — `title` or `id`; skip if both missing.
- **durationSeconds** — same numeric coercion as `MediaMetadata` (`duration`).
- **thumbnailURL** — `thumbnail` string, or the first `thumbnails[].url`.
- **extractor** — entry `ie_key` or `extractor` or the playlist extractor
  (so YouTube flats can skip per-item `-J`).
- **playlistIndex** — `playlist_index` if present, else 1-based enumeration
  order of kept entries.

Empty `entries` after filtering → `.malformedOutput`.

Prefetch `MediaMetadata` for an entry (submit): `title`, `durationSeconds`,
`extractor`, `sourceURL: watchURL`, `isPlaylist: false`. Format fields stay
defaults (unknown / empty). Missing duration still trips `needsMetadata`
(title + extractor + duration must all be non-nil).

---

## 4. Picker

`Sources/App/Home/PlaylistPickerView.swift`. Skinned modal (design-system
§4.3 + this spec). Opens automatically on dump success; Grab reopens it.

**Header** — "Choose videos to download". Subtitle:
`<playlist> · <site> · by <uploader> · N items`. Omit `by <uploader>` when
uploader is nil. Site is the dump host (e.g. `youtube.com`), not "youtube"
canonical.

**Banner** (below header, only when this dump's `sourceURL` equals a live
group's `sourceURL`): **This playlist is already in your queue.** Exact
trimmed-string match. A group is live if any job in the engine still has that
`playlistGroupID`.

**Tools** — Select all / Select none apply to **currently filtered** rows
only. Filter field matches **title**, case-insensitive. Placeholder `filter…`.

**List** — `LazyVStack` (or equivalent); no item cap. Row: checkbox ·
thumbnail (52×30) · title (truncate) · duration (`M:SS` or `H:MM:SS`) ·
optional warning. Whole row toggles the checkbox. Thumbnail: async load from
`thumbnailURL`; placeholder on nil/fail. Load **visible rows only** (no
prefetch of the whole dump).

**Row warning** if that entry's `watchURL` equals any job's `request.url`
still in the engine (queue + in-memory history):

- job state `.completed` → **Already saved**
- any other state → **In queue**

Video identity is the watch URL, not full `DownloadRequest` equality (a
1080p job still warns a 720p re-add). Removed jobs do not warn (no disk
scan).

**Defaults** — every row starts checked **except** warned rows (those start
unchecked). Select all may check warned rows. Reopening the picker resets to
these defaults; previous checks are discarded.

**Footer** — `M of N selected · K already in queue · ≈ H:MM:SS`.

- `N` is the dump entry count (not the filtered subset).
- `M` is checked count (all entries, including those hidden by the filter).
- `K` is checked rows that carry a warning.
- Duration is the sum of **known** `durationSeconds` among **checked** rows.
  Unknown durations are omitted, not guessed. Format `H:MM:SS` when the sum
  is ≥ 3600, else `M:SS`. No invented MB/GB. If a dump actually includes
  bytes, still do not show them this phase.
- Omit `· K already in queue` when `K == 0`.
- **Add M** disabled at `M == 0`. Label uses the count (`Add 12`).
- Cancel: dismiss, no rows.

---

## 5. Add M and enqueue

`RequestBuilder` gains a per-entry helper that reuses the existing single-item
builder: watch URL + current runway overrides + prefs. Same `DownloadKind`,
`audioLanguage`, `destFolder`, container, filename template as a single Grab
at that moment. The picker does not re-ask quality or language.

```swift
public struct PlaylistSubmitItem: Sendable {
    public var request: DownloadRequest
    public var force: Bool
    public var prefetched: MediaMetadata?
    public var playlistGroupID: UUID
    public var playlistIndex: Int
}

func submitPlaylistItems(_ items: [PlaylistSubmitItem]) async -> [UUID]
```

**Group id.** If a live group has the same `sourceURL`, reuse its id (later
Add M **joins** that header). Else `UUID()` and AppModel inserts
`{ id, title, sourceURL, isCollapsed: false }` into the registry.

**Force.** `force == true` iff that row was warned **and** left checked
(download again). Unchecked warned rows are not submitted. New URLs use
`force == false`; if a race still hits `.duplicateExists`, skip that item
(do not halt the batch, no per-item dialog).

**Batch.** Append every job, set `playlistGroupID` / `playlistIndex` /
prefetched fields, **one** `bump` + **one** `.snapshot` + one
`evaluateSchedule`. Log `playlistEnqueued(groupID:count:)` and the existing
per-job `jobEnqueued` for each item.

`submit(_:force:prefetchedMetadata:)` stays for single Grab. Group id and
index are set only by `submitPlaylistItems`. Do not add `playlist` to
`DownloadRequest`.

Prefetch skip-`-J`: copy title, extractor, duration onto the job the same way
today's `prefetchedMetadata` path does. Fill extractor from the entry as in
§3.

---

## 6. Token bucket and probe cancel

### 6.1 `MetadataTokenBucket`

`GrabberKit/Download/MetadataTokenBucket.swift`. Rolling window: at most
`tuning.metadataProbeLimit` acquires in the last
`tuning.metadataProbeWindowSeconds`. `acquire()` waits until a slot exists or
the `Task` is cancelled. Tests inject a fake clock.

Owned by `MetadataProbe` (every `-J` and `--flat-playlist` goes through it).
`MetadataProbe` init takes `bucket: any MetadataTokenBucketing =
UnlimitedMetadataTokenBucket()` so existing unit tests stay unpaced.
`EngineDependencies.live` injects the real rolling bucket — the app factory
is the only production construction, so a missed inject cannot burst.

Downloads, retries, and fragment pacing are unchanged. yt-dlp
`--sleep-requests` stays; the bucket does not replace it.

### 6.2 Probe cancel

`MetadataProbe`'s tail chain is additive: a cancelled waiter must **not**
run yt-dlp, and must still complete the tail so the next probe is not stuck.
If this request's process is in-flight, cancelling the Swift `Task` already
SIGTERMs via `ProcessRunner`; check `Task.isCancelled` after waiting on the
predecessor and after `acquire()`, and treat `ProcessResult.wasCancelled` as
a dropped probe (not `.unknown`).

Engine:

- `launchProbe` keeps `probeTask`. `cancel` / `remove` of a `.probing` job
  cancels **`probeTask`**, not only `childTasks[id]`.
- `cancel` of `.queued` stays `markCancelled` (never started a probe).
- `recordProbeResult`: if the job is missing or `state != .probing`, clear
  `probeInFlight` / `probeTask` and `evaluateSchedule()` — do **not** overwrite
  `.cancelled` / a new state with probe success or failure.
- Group Cancel all: existing confirm, then `cancel` each child whose state is
  cancellable (queued / paused / probing / running). Probe cancel follows
  per id.

Confirm copy:

- title: **Cancel this playlist?**
- message: **Videos still waiting or downloading will stop. Files already saved stay.**
- confirm: **Cancel All** (destructive)
- cancel: **Keep**
- `suppressionKey`: `playlist-cancel-all` (Don't ask again).

Pause all: `pause` every child in `.running`. Retry failed: existing `retry`
on `.failed` children (cooldown rows keep the per-row retry rules). Disable
Pause all when no child is running; Retry failed when none are `.failed`;
Cancel all when no child is cancellable.

Removing the last job that still has a `playlistGroupID` **drops** that
registry row (header gone). Cancelled children can remain; the header stays
on All.

---

## 7. Table groups

Fill `Sources/App/Rows/RowStore.swift` `PlaylistGroup` and
`Sources/App/Table/DownloadsTable.swift`. Header is not a `JobSnapshot`.
`visibleRows` becomes a mixed list (header | child). `chipCounts` stay **per
job**; headers do not increment All.

### 7.1 `PlaylistGroup`

Keep the existing fields and add what the header cells need (or a nested
aggregates struct — one type, not a parallel model). Required:

- `id`, `title`, `isCollapsed`
- `totalCount`, `completedCount`, `failedCount`
- `rollupFraction`
- speed (Σ active `speedBytesPerSec`), eta (max active `etaSeconds`)
- size / duration (Σ known; nil if none known)
- `addedAt` displayed = **min** child `addedAt`
- `finishedAt` = max child `finishedAt` once **every** child is `.completed`,
  else nil
- Site / Type / Quality / Destination / Client used: the common label, or
  `mixed`
- Attempt: max

`sourceURL` lives on the AppModel registry, not necessarily on the view
model.

### 7.2 Order

Children **always** sort by `playlistIndex` ascending inside the block.
Column sort never reorders children.

Default `ColumnConfig` is Added at **descending**. A group's **block
position** uses **max(child `addedAt`)** so a later Add M bumps the whole
group. Ungrouped jobs use the active column as today. Groups and singles
interleave by that key. When `sortColumn == nil`, keep grouping (engine
order for ungrouped jobs; groups still blocks).

Other sort columns: the group's sort key is the header aggregate for that
column (progress = `rollupFraction`, title = playlist title, …). Nil
aggregates sort last, same as jobs.

### 7.3 Chips and column filters

Header is visible if **any** child passes the active chip **and** column
filters. Non-matching children hide. Collapse hides **all** children; the
header remains if it passed the previous sentence. Rollup numbers are the
**whole group**, not the visible slice.

### 7.4 Progress recompute

Contribution: `.completed` → `1.0`; else `progress.fraction` quantized to
the nearest 0.1; else `0.0`. `rollupFraction` = Σ contribution / `totalCount`
(0 if total is 0). Recompute a group only when a child **crosses a 10%
bucket** or a **state boundary**. Track last-bucket per active child on the
store. Ignore `.progress` ticks that stay in the same bucket. Status column:
`M done · K failed · rest queued` where `rest` is everyone who is not
completed and not failed (queued, probing, running, paused, waiting,
cooldown, cancelled). Title-side rollup stays `N items · M done` plus the
mini bar (design-system §4.2.4).

### 7.5 Chrome

Header: disclosure caret, playlist name, rollup + mini bar, Pause all ·
Retry failed · Cancel all. Background `--accent-2` at low alpha. Children
indented; one continuous vertical spine; dividers start after the spine.
Collapse persists on the registry (`isCollapsed`).

---

## 8. Persistence and restore

`QueueFile`:

```swift
public struct QueueFile: Codable, Sendable {
    public var schemaVersion: Int
    public var jobs: [PersistedJob]
    public var groups: [PersistedPlaylistGroup]
}

public struct PersistedPlaylistGroup: Codable, Sendable, Equatable {
    public var id: UUID
    public var title: String
    public var sourceURL: String
    public var isCollapsed: Bool
}
```

`groups` `decodeIfPresent` → `[]`. `schemaVersion` stays **1**.
`PersistedJob.playlistIndex: Int?` `decodeIfPresent` → `nil`.
`playlistGroupID` already exists; `DownloadEngine.persistedJob(from:)` and
`snapshot` must write the real values (today both force `nil`).

`QueuePersisting`:

- `saveQueue(_ jobs:)` unchanged from the engine's point of view.
- `savePlaylistGroups(_ groups:)` from AppModel on registry change.
- `loadPlaylistGroups() -> [PersistedPlaylistGroup]`.
- `writePending` builds one `QueueFile` by merging pending jobs and pending
  groups with the last-written values so a jobs-only debounce cannot wipe
  groups and a groups-only save cannot wipe jobs.

Terminal jobs still go to `history.json` (jobs only; no groups there). A
group whose members are all completed remains in **`queue.json`** (possibly
`jobs: []`) until every member is **removed**. On load, drop registry rows
with no matching job in queue ∪ history. Jobs with a group id but no
registry row still group; title falls back to **Playlist**.

Restore: engine `restore` as today (probing clamps to queued). Skip `-J` when
title, extractor, and duration are all present. `playlistIndex` / group id
round-trip. AppModel loads groups, hands titles/collapse to `RowStore`.

Not persisted: thumbnails, picker checks, the dump JSON.

`hasGrabbedOnce` is already true if restore produced jobs; adding a playlist
is a Grab and must set it the same as a single add.

---

## 9. AppModel wiring

Hold `resolvedVideo: MediaMetadata?` **or** `resolvedPlaylist: PlaylistDump?`
(one enum). `isPlaylistPickerPresented`. Group registry
`[UUID: PersistedPlaylistGroup]` (or an array) updated on Add M, collapse,
and last-member remove.

`grab()`: if playlist dump is set, present picker; else today's single submit
+ duplicate dialog.

Duplicate dialog remains for **single** Grab only.

Log: `probeCompleted` for dump success/fail; `playlistEnqueued`; probe cancel
does not log a user-facing error.

---

## 10. Copy

| Situation | Copy |
|---|---|
| Classify `.youtubeUnsupported` | This link isn't a video or a playlist. |
| Playlist banner | This playlist is already in your queue. |
| Row, still active | In queue |
| Row, completed | Already saved |
| Footer overlap | ` · K already in queue` |
| Cancel all | §6.2 |
| Malformed dump | Couldn't read the video details. |

---

## 11. Tests and done

| Suite | Assert |
|---|---|
| `PlaylistLinkTests` | watch + `list=PL` → single; `/playlist?list=PL` → playlist; `RD` / `WL` / `LL` / `UU` / `/videos` → unsupported; archive.org → single |
| `PlaylistDumpTests` | fixture `-J --flat-playlist` JSON → entries, watch URL from id, skip nested playlist, empty entries → malformed |
| `MetadataTokenBucketTests` | 4th acquire in the window waits; cancel during wait does not consume a token; fake clock |
| `MetadataProbeCancelTests` | cancelled waiter does not launch; in-flight cancel → `wasCancelled`, tail continues |
| `EnginePlaylistSubmitTests` | batch: one snapshot, group id + index set, prefetch skips probing, force on warned URL, join same `sourceURL` |
| `EngineProbeCancelTests` | cancel while `.probing` cancels `probeTask`; `recordProbeResult` ignores non-probing |
| `RowStoreGroupTests` | block order by max `addedAt`; children by index; chip hides children keeps rollup; 10% bucket; collapse; last remove drops group |
| `PersistenceGroupTests` | `QueueFile` round-trip groups; old file without `groups` → `[]`; jobs-only save does not wipe groups |
| `PlaylistPicker` / `AppModel` tests | defaults (warned unchecked); filter Select all; Add M inherit runway; Grab reopens picker; unsupported copy |
| Fakes | `FakeEngine.previewPlaylist`, `submitPlaylistItems`; `NoopPersisting` groups |

Lint: `mise exec -- swiftformat --lint .` and `swiftlint lint --strict`.
Full suite: `MediaGrabber-Workspace`. Comments: single-line why only, no `///`.

### 11.1 Manual smoke

- Paste a real YouTube **`PL` playlist** → picker auto-opens, all checked,
  durations in the footer; Add M → group header + spine; inherit Type /
  Language; rows skip probing when the dump had title/duration.
- Paste a **watch URL with `&list=`** → one video, no picker.
- Paste a Mix / channel `/videos` → "isn't a video or a playlist", no probe.
- Re-paste the same playlist → banner; overlapping rows warned and unchecked;
  Add remaining → **same** header; collapse survives quit/relaunch.
- Cancel all → confirm; Don't ask again sticks; in-flight `-J` (if any) dies.
- Filter chip Done → header remains if any child is saved; rollup still N/M.

---

## 12. Parent, design-system, backlog deltas

Living docs must match this spec (no changelog framing).

**Parent `2026-08-28-…-design.md`** — §5.3 playlist picker (duration, not
size; no range syntax in the engine); §5.5 already matches the header;
§4 `DownloadRequest` drops `playlist: PlaylistSelection`; §6 step 2–3
playlist dump + N jobs; §12.1 Phase 8 points here; §12.2 JobSnapshot
`playlistGroupID` filled this phase; ConfirmationRequest suppression used
for cancel all.

**design-system.md §4.3** — footer duration + `K already in queue`; banner
and per-row warnings; warned rows start unchecked.

**`apps/media-grabber/ticket-backlog.md`** — Phase 8 blurb matches (no
`playlistProgress`, no "size" as the primary footer).

**`screens.html` §5.1 / §5.2** — drop "refined later"; five-slot skinned
runway; Grab not "Add 12" on the runway; footer duration; one warned row;
group block + spine; real column set.

Queue-foundation deferred sentences (empty `groups`, per-request probe
cancel) are satisfied here; do not rewrite the archived-style Phase 2 spec
except to leave it as history. This phase's spec is the source of truth.

Phase 7 remains unarchived until it ships.

---

## 13. Out of scope

Mix / Radio / WL / LL / UU / channel pages; `--flat-playlist` for
non-YouTube; one yt-dlp `--playlist-items` process; range-syntax field;
`DownloadRequest.playlist`; disk-file duplicate check; remembering picker
checks; invented byte sizes; row drag-reorder; Phase 9 add flows; a second
probe after the dump on happy-path items that already have title, duration,
and extractor.
