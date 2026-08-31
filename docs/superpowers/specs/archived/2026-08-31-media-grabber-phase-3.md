# Preferences screen (Phase 3)

**Status:** design complete. Plan: not yet written. Parent spec:
`docs/superpowers/specs/2026-08-28-youtube-downloader-mac-design.md` §12.1.
Phase 2 (shipped): `docs/superpowers/specs/queue-foundation.md`.
Visual reference: `../assets/2026-08-31-media-grabber-phase-3/` (frozen design
explorations — `prefs-full-v2.html` the pane layout, `skinned-picker-v2.html`
the picker interaction fork, `appearance-swatch-final.html` the swatch fork,
`concurrency-note-v3.html` the note fork). The maintained mockup is
`apps/media-grabber/docs/mockups/screens.html`.

Phases 1–2 gave the runway hard-coded default reads from the `Preferences`
model (`theme` / `palette` / `defaultKind` / video height / download folder)
with no editor. Phase 3 builds the in-app Preferences page — the 7-pane
`PreferencesView` over that model — and, in the same pass, the two reusable
skinned form controls the page needs (`SkinnedSegment`, `SkinnedPicker`), which
also replace the native `Menu` dropdowns on the Home runway. Phase 3 also does
the pre-release vocabulary cleanup (§11): the `Skin` type family becomes
`Theme`, and the `Preferences` fields the UI is about to expose get their final
names.

Everything built here is built to its final-app form. Panes a later phase fills
(Sign-in & cookies, Updates) ship as complete headers; the `Preferences`
fields, `YtDlpArguments` wiring, and controls introduced here are final. No
shape a later phase must replace (parent §12 scoping rule).

---

## 1. Scope

**In this phase:**

- The 7-pane `PreferencesView`: grouped left rail, right pane of two-column
  rows (`label + helper` left, control right). Fixed window height. The left
  rail never scrolls (the window is tall enough for all rail items); the right
  pane scrolls independently.
- **Filled panes:** Downloads, Appearance, Network, Logs & privacy, Advanced.
- **Stepless panes:** Sign-in & cookies, Updates. Present in the rail; render a
  title, a one-line sub, and one plain-language "coming in a later update"
  sentence. No phase number in the shipped copy.
- **`SkinnedSegment`** — skinned 2–3-option segmented control, all options
  visible, one tap. Equal-width segments; the control hugs its content and
  sits flush to the row's right edge.
- **`SkinnedPicker<T>`** — skinned trigger button + **popover** list (caption
  header, checkmark on selected, hover highlight, optional per-row subtitle, no
  row icons). Not a modal. Keyboard + VoiceOver. No scroll cap this phase.
- Both controls replace the native `Menu` dropdowns on the Home runway.
- New `Preferences` fields (§3) and their persistence.
- The pre-release rename sweep (§11): `Skin` → `Theme` end to end, and the
  `Preferences` field renames.
- `GlobalDownloadOptions` in `GrabberKit` + `YtDlpArguments` wiring for the
  Network flags.
- The "concurrency lowered below running count" inline note.
- `AppModel.Page.preferences` carries a target `PreferencesPane` (deep-link
  seam for later phases).
- Doc updates: `design-system.md` and `screens.html` (§8).

**Deferred (hints land in the owning phase's stub):**

- Runway per-download quality picker showing only probe-reported available
  heights — Phase 7 (needs format-list parsing on `MetadataProbe`). The hint on
  the Phase 7 stub also carries the seed-clamp order (§3.1).
- In-app rendered `PRIVACY.md` sheet — this phase opens the file externally.
- Diagnostics page — Phase 10; its nav placeholder is untouched here.
- `maxAutoRetries` control ("Automatic retries") — the row is laid out this
  phase and the field persists; the retry engine that consumes it is Phase 4.
- `screens.html` for the playlist, Diagnostics, and cookie-filled screens —
  hints on the Phase 5 / 8 / 10 stubs.

**Not in scope:** Diagnostics content, cookies UI, Updates UI, toasts,
multi-select, column drag-reorder.

---

## 2. Architecture

`PreferencesView` is a plain SwiftUI page in the App target, selected by
`AppModel.page`. It reads and writes the `@Observable Preferences` model
directly — every consumer (runway, engine `cap`, `Theme` / `Palette`
resolution) already binds that model live, so an edit re-themes and re-defaults
the app with no extra plumbing.

```
Sources/App/Preferences/
  PreferencesView.swift     — the page: rail + selected-pane switch
  PreferencesPane.swift     — enum: cases, titles, subs, rail group; deep-link target
  PrefRow.swift             — the shared label+helper / control row + pane header
  FileNamingPreset.swift    — preset ↔ filenameTemplate string mapping
  ConcurrencyNote.swift     — shouldShowConcurrencyNote(...) predicate + the note view
  Panes/
    DownloadsPane.swift
    AppearancePane.swift
    NetworkPane.swift
    SignInCookiesPane.swift  — stepless
    UpdatesPane.swift        — stepless
    LogsPrivacyPane.swift
    AdvancedPane.swift

Sources/App/Controls/
  SkinnedSegment.swift
  SkinnedPicker.swift

Sources/App/Home/
  RunwaySeed.swift          — runwaySeed(from:) pure resolver (§3.1)

Sources/GrabberKit/Download/
  GlobalDownloadOptions.swift   — beside YtDlpArguments.swift
```

One file per pane so later phases each edit one small focused file. `PrefRow`
is the field primitive; panes stay declarative lists of rows.

`SkinnedSegment` / `SkinnedPicker` `import SwiftUI` only — generic over the
option type, no `GrabberKit`. Call sites pass the concrete type (`AudioFormat`,
an `Int` height, a `FileNamingPreset`, a folder identifier).

### 2.1 Navigation / deep-link

`AppModel.Page.preferences` gains an associated value:

```swift
enum Page: Equatable {
    case home
    case preferences(PreferencesPane = .downloads)
    case diagnostics
}
```

`Page` gains an `Equatable` conformance (it has none today); `PreferencesPane`
is `Hashable`, so the associated-value synthesis works. `PreferencesView` holds
`@State selectedPane`, seeded from the associated value, thereafter driven by
the rail. **Not persisted** — Preferences always opens to Downloads unless a
caller deep-links a specific pane. Later phases route errors here
(`.preferences(.network)`, `.preferences(.cookies)`).

The `MainWindow` nav button targets `.preferences()` (defaulted). Any
`.preferences(_)` value marks the nav button active. The `.diagnostics` case
and its placeholder are unchanged.

---

## 3. `Preferences` — new fields

All `UserDefaults`-backed, same pattern as the existing model. Field names here
are already the §11 post-rename names.

| Field | Type | Default | Notes |
|---|---|---|---|
| `detectClipboardLinks` | `Bool` | `true` | Persists only; the clipboard watch itself is Phase 9. |
| `proxyURL` | `String?` | `nil` | Trimmed on set; empty string stored as `nil`. |
| `forceIPv4` | `Bool` | `false` | |
| `speedLimitKBps` | `Int` | `0` | `0` = no limit. Clamped to `0…100000` on set. Per download. |
| `lastVideoHeight` | `Int?` | `nil` | Written on Grab. `Int.max` is a valid value ("Best available"). |
| `lastMediaType` | `MediaType?` | `nil` | `.video` / `.audio`. Written on Grab. |
| `lastAudioFormat` | `AudioFormat?` | `nil` | Written on Grab. |

`MediaType` (was the `private` `KindSelector` inside `Preferences`) is promoted
to a top-level `public enum MediaType: String, Codable, Sendable, CaseIterable`
in `GrabberKit` — `{ case video, audio }` — so `lastMediaType` /
`defaultMediaType` can be typed and the runway can read them.

**"Best available" storage.** The Preferences "Video quality" picker and the
runway quality picker both offer `2160 / 1440 / 1080 / 720 / 480 / Best
available`. "Best available" is stored as `Int.max` in `defaultVideoHeight` /
`lastVideoHeight`. `YtDlpArguments` needs no special case —
`bv*[height<=9223372036854775807]` is always satisfied, so yt-dlp picks the
best. `defaultVideoHeight`'s default stays `1080`.

### 3.1 Runway seeding

`runwaySeed(from: Preferences) -> RunwaySeed` is a pure function in
`Sources/App/Home/RunwaySeed.swift`, unit-testable without a view.
`HomeView.seedFromPrefs` calls it once (guarded by its existing `seeded` flag).

```swift
struct RunwaySeed: Equatable {
    var mediaType: MediaType
    var videoHeight: Int
    var audioFormat: AudioFormat
    var downloadFolder: URL
}
```

- `mediaType   = prefs.lastMediaType   ?? prefs.defaultMediaType`
- `videoHeight = prefs.lastVideoHeight ?? prefs.defaultVideoHeight`
- `audioFormat = prefs.lastAudioFormat ?? prefs.defaultAudioFormat`
- `downloadFolder = prefs.lastUsedDownloadFolder` if set and distinct from
  `prefs.defaultDownloadFolder`, else `prefs.defaultDownloadFolder`

The runway's "Save to" step is therefore **always seeded** — it never renders
in an unfilled / "wait" state.

On Grab, the grab path (`AppModel.grab(overrides:)`) writes `lastMediaType` /
`lastVideoHeight` / `lastAudioFormat` from `overrides.kind`, and
`lastUsedDownloadFolder` from `overrides.destFolder` (as today).

**Deferred to Phase 7** (hint on its stub): when the runway quality picker is
restricted to probe-reported available heights, the seed resolves `lastVideoHeight`
→ if available use it → else `defaultVideoHeight` if available → else the best
available height.

---

## 4. Controls

### 4.1 `SkinnedSegment`

A skinned segmented control. Full design-system entry in `design-system.md`
§4.9 (new).

```swift
struct SkinnedSegment<Option: Hashable>: View {
    init(_ options: [Option], selection: Binding<Option>, label: @escaping (Option) -> String)
}
```

- 2–3 options, all rendered as segments in a `--panel` track with a `--stroke`
  border; the selected segment gets a `--panel-solid` fill.
- **Equal-width segments** within one control (each segment sized to the widest
  label). The control as a whole **hugs its content** — it is only as wide as
  its segments need — and sits flush to the row's right edge. Different controls
  in one pane may have different total widths; all are right-aligned.
- One tap selects. No popover.
- Keyboard: Left / Right moves selection when focused; VoiceOver exposes it as a
  radio group / segmented control with the option labels.
- Palette-matched: track, border, and selected-fill are theme tokens; radius is
  the theme's `chipRadius`.

**Used by:** Theme (Appearance), Media type (Downloads + runway), Audio format
(Downloads + runway).

### 4.2 `SkinnedPicker<T>`

A skinned dropdown. Full entry in `design-system.md` §4.10 (new). See the frozen
`../assets/2026-08-31-media-grabber-phase-3/skinned-picker-v2.html` (option A, the
chosen model).

**It is a popover, not a modal.** Picking one value from a short list is a
lightweight, anchored interaction — a `Menu` / pop-up button, skinned. The only
app modals are the confirmation dialog (§4.8 design-system) and the playlist
picker (Phase 8).

```swift
struct SkinnedPickerRow<Option: Hashable>: Identifiable {
    let id: Option
    let title: String
    let subtitle: String?   // nil -> single-line row
}

struct SkinnedPicker<Option: Hashable>: View {
    init(caption: String,
         rows: [SkinnedPickerRow<Option>],
         selection: Binding<Option>,
         triggerLabel: String? = nil)   // defaults to the selected row's title
}
```

- **Trigger** — a button showing the current selection's label + a chevron,
  `--panel` fill, `--stroke` border, theme `controlRadius`. The trigger is only
  as wide as its own label.
- **Popover** — opens below the trigger (flips above if no room). `--panel-solid`
  fill, theme border + `cardRadius` + elevation (glow on Aurora, hard shadow on
  Tape Deck), matching the confirmation-dialog card treatment.
  - **Width** — sized to the picker's widest row (caption / label / subtitle),
    clamped to `[trigger width … 340pt]`. A picker with short rows (the quality
    ladder) gets a narrow popover; one with long subtitles (file naming) gets a
    wide one. There is no single global popover width.
  - **Caption header** — a `--faint` uppercase label naming what is being chosen
    (e.g. "Resolution", "File naming"), with a hairline rule under it.
  - **Rows** — label; optional second-line **subtitle** in `--dim` (`nil` →
    single-line row); a checkmark (`--accent`) on the selected row; hover /
    arrow-key highlight uses a translucent accent wash.
  - **No row icons.**
- Keyboard: Return / Space opens; Up / Down moves the highlight; Return selects;
  Esc closes without changing. VoiceOver: a menu / pop-up button; the popover
  traps focus; the selected row is announced.
- No `maxVisibleRows` / scroll cap this phase — every list is ≤ 6 rows. Phase 5
  (Firefox profile list) adds a cap + scroll; additive, no layout change.

**Used by:** Video quality (Downloads + runway), Filename format (Downloads),
Save to (runway). Phase 5 adds the cookie-browser and Firefox-profile pickers;
Phase 8 the playlist filters as applicable.

**Subtitle call sites this phase:** the runway Save-to picker (folder path under
a possibly duplicate folder name) and Filename format (example filename).
Quality passes `nil` on every row.

---

## 5. Panes

Two-column rows: `label` (13, `--text`, semibold) + optional `helper` (11.5,
`--dim`) stacked on the left; control right-aligned; a `--hair` divider between
rows. A row with no helper renders label-only. Pane title 20 / heavy in
`--headline` with a rule under it, a one-line `--dim` sub above the rule.

Rail: three group captions —
**General** (Downloads · Appearance · Network),
**YouTube** (Sign-in & cookies),
**System** (Updates · Logs & privacy · Advanced).

Copy convention: labels are scannable noun phrases, not sentence fragments the
control completes. Helpers are ≤ 8 words and only present when the label is not
self-evident. No phase / ticket references in any shipped string.

### 5.1 Downloads

Pane sub: *Defaults for new downloads. Change any of these per download on the
Home screen.*

| Label | Helper | Control | Backs |
|---|---|---|---|
| Downloads folder | — | folder button showing `~/Downloads` (tilde-abbreviated path, **no chevron**) → `NSOpenPanel`, directories only. No list. | `defaultDownloadFolder` |
| Simultaneous downloads | Automatically reduced if a site rate-limits you. | stepper 1–6 | `maxConcurrentDownloads` |
| Automatic retries | Attempts before the app asks you what to do. | stepper 1–5 | `maxAutoRetries` |
| Media type | — | `SkinnedSegment` — Video / Audio | `defaultMediaType` |
| Video quality | Highest available if the exact height isn't offered. | `SkinnedPicker` — 2160p / 1440p / 1080p / 720p / 480p / Best available | `defaultVideoHeight` (`Int.max` for Best) |
| Audio format | — | `SkinnedSegment` — M4A / MP3 | `defaultAudioFormat` |
| Filename format | — | `SkinnedPicker` — Title / Title – channel / Date – title / Custom… (§5.1.1) | `filenameTemplate` |
| Clipboard detection | Offer to grab links you copy. | toggle | `detectClipboardLinks` |

**Concurrency note** (§6) renders in the "Simultaneous downloads" row's right
column, under the stepper, when the new value is below the live running count.
This is the one row whose height grows.

The **Preferences "Downloads folder"** control differs from the **runway "Save
to"** (§5.1.2): the Preferences one edits a single default folder and needs no
list, so it has the trigger chrome of a `SkinnedPicker` (same `--panel` fill,
`--stroke` border, `controlRadius`) **without the chevron** — a chevron implies
a list. Clicking it opens `NSOpenPanel`.

#### 5.1.1 Filename format

`FileNamingPreset` (App target, not persisted):

| Row label | Template | Example subtitle |
|---|---|---|
| Title | `%(title)s.%(ext)s` | `Never Gonna Give You Up.mp4` |
| Title – channel | `%(title)s - %(uploader)s.%(ext)s` | `Never Gonna Give You Up - Rick Astley.mp4` |
| Date – title | `%(upload_date>%Y-%m-%d)s - %(title)s.%(ext)s` | `2009-10-25 - Never Gonna Give You Up.mp4` |
| Custom… | — | reveals a monospace text field below the picker |

- The picker maps a preset row → its template string on select.
- On load / open, the selected row is **derived** from the stored
  `filenameTemplate`: if it string-matches a preset template, that row is
  selected; otherwise "Custom…" is selected and the text field shows the stored
  string.
- Custom text field: monospace, pre-filled with the current template. Empty on
  blur → revert to the previously stored value. No syntax validation beyond
  non-empty.
- Backing is `filenameTemplate: String` only. No new field — the preset is
  state derived from the string.

#### 5.1.2 Runway "Save to" (Home)

The runway's "Save to" slot is a `SkinnedPicker`:

- Row 1 — `defaultDownloadFolder`. Label = folder name; subtitle = full path.
- Row 2 — `lastUsedDownloadFolder`, **only if it differs from
  `defaultDownloadFolder`**. Label = folder name; subtitle = full path.
- Row 3 — "Choose…" → `NSOpenPanel`. On pick: sets the per-download dest and
  writes `lastUsedDownloadFolder`.
- Trigger label = the selected folder's name only. When two rows share a
  basename, the popover subtitles (full paths) disambiguate.
- Default selection: `lastUsedDownloadFolder` if set and valid, else
  `defaultDownloadFolder`.

#### 5.1.3 Runway Media type / Quality / Format

- Media-type slot → `SkinnedSegment` (Video / Audio).
- Format slot → `SkinnedSegment` for the audio format when Media type = Audio;
  `SkinnedPicker` for the quality ladder when Media type = Video. (Two distinct
  controls: a two-value pair vs a six-value ladder.)
- Ladder: `2160 / 1440 / 1080 / 720 / 480 / Best available` — **drop `360`**
  (currently in `RunwayView.heights`), **add "Best available"** (`Int.max`).
- On Grab the runway writes `lastMediaType` / `lastVideoHeight` /
  `lastAudioFormat`.

### 5.2 Appearance

Pane sub: *Pick a look. Theme sets the personality; palette sets the colours.*

| Label | Helper | Control | Backs |
|---|---|---|---|
| Theme | Aurora is dark and luminous. Tape Deck is warm and light. | `SkinnedSegment` — Aurora / Tape Deck | `theme` |
| Palette | — | 3 swatches for the selected theme | `palette` |

- **Swatch** — a rounded tile ~38 pt tall: a split fill of that palette's
  `--accent` (left half) and `--accent-2` (right half), the palette name in
  `--text` underneath. Selected swatch gets a 2 pt `--accent` outline at a 2 pt
  offset.
- Only the 3 palettes of the currently-selected theme are shown; the set swaps
  when Theme changes.
- Changing Theme resets `palette` to that theme's default (`.auroraMintIris` /
  `.tapeDeckA`) — matches the model's existing fallback.
- Both controls apply live (the whole app re-themes on click).

Note: `Sources/App/Theme/Palette.swift`'s `palette(for:)` currently returns the
Aurora Mint & Iris tokens for every kind (Phase 9 fills the real palette
values). Until then the three swatches render identical colours — expected, not
a bug, and not fixed in this phase.

### 5.3 Network

Pane sub: *Applied to new downloads.*

| Label | Helper | Control | Backs |
|---|---|---|---|
| Proxy server | `http://host:port` — blank for none. | text field | `proxyURL` |
| Force IPv4 | Can help when connections stall. | toggle | `forceIPv4` |
| Speed limit | Applies to each download separately. | stepper in KB/s with an "Off" position at `0` | `speedLimitKBps` |

Flags are passed to `yt-dlp` via `GlobalDownloadOptions` (§7). They affect
**new** downloads only — a running child process is not restarted. No inline
note (unlike concurrency, this is the obvious behaviour of a per-launch flag).

Speed-limit stepper: the value `0` shows as "Off". Stepping down from the
minimum real value lands on "Off"; stepping up from "Off" lands on the first
real value. Step size 100 KB/s.

### 5.4 Sign-in & cookies — stepless

Pane sub: *Sign in to reach private or age-restricted videos.*
Body: one `--faint` line — *"Cookie sign-in is coming in a later update."*
No rows, no controls. `cookiesFromBrowser` / `firefoxProfile` land in Phase 5.

### 5.5 Updates — stepless

Pane sub: *Check for new versions of the app and the downloader.*
Body: one `--faint` line — *"Update checks are coming in a later update."*
No rows, no controls. `autoCheckUpdates` lands in Phase 10.

### 5.6 Logs & privacy

Pane sub: *What the app records, and where to find it.*

| Label | Helper | Control | Action |
|---|---|---|---|
| Log files | — | button "Show in Finder" | reveal `~/Library/Logs/MediaGrabber` |
| Verbose logging | More detail for troubleshooting. | toggle | `verboseLogging` |
| Privacy details | — | button "Open" | open the bundled `PRIVACY.md` externally |

`PRIVACY.md` is added to the App target's bundle resources in `Project.swift` as
part of this phase if it is not already there. If the bundle lookup returns
`nil`, the button is a no-op (guarded).

### 5.7 Advanced

Pane sub: *Reset options. These don't touch your downloaded files.*

| Label | Helper | Control | Action |
|---|---|---|---|
| App data | — | button "Show in Finder" | reveal `~/Library/Application Support/MediaGrabber` |
| Reset columns | Table layout back to default. | button "Reset" | `appModel.columnConfig = .default` — propagates to `RowStore` + persistence via the existing `didSet` |
| Reset settings | All preferences back to default. Downloads are untouched. | button "Reset…" (`--danger`), `ConfirmationRequest` `isDestructive: true`, `suppressionKey: nil` | `appModel.resetAllSettings()` → `Preferences.resetToDefaults()` |

- `Preferences.resetToDefaults()` removes every `mg.*` key the model owns
  (enumerated explicitly — **not** `removePersistentDomain`, other subsystems
  share the suite). The getters already fall back to the right defaults once a
  key is removed.
- "Reset settings" resets the `Preferences` model **only** — not `columns.json`
  (that has its own button). Theme / palette / defaults snap live; the
  concurrency note shows if the reset cap is below the running count, same as a
  manual change.
- "Reset columns" and "Reset settings" are independent.

---

## 6. Concurrency-lowered inline note

See the frozen `../assets/2026-08-31-media-grabber-phase-3/concurrency-note-v3.html`
(direction D1, chosen).

When the user sets "Simultaneous downloads" to `N` while the live running-job
count is `> N`:

- An inline note appears in the row's right column, under the stepper.
- **Leading glyph** — the design-system warn glyph (§3.4), tinted `--warn`.
- **Text** — `--dim`, one short sentence:
  `"<count> still running — the new limit applies as they finish."`
- The note clears when the running count drops to `≤ N`, or on relaunch.

**No new drain logic.** The Phase 2 scheduler already gates `running < cap` and
reads `cap` live from `preferences.maxConcurrentDownloads` on every
`evaluateSchedule()`. Lowering the cap fires no engine event, so the running
jobs continue and the next natural completion re-evaluates with the new cap —
the queue drains to the new limit on its own. The note only *states* this so
the user isn't surprised that the running downloads didn't stop.

The visibility predicate is a pure function
(`shouldShowConcurrencyNote(newValue:runningCount:) -> Bool`, true iff
`newValue < runningCount`) so it is unit-testable without a view. Running count
comes from `AppModel.rowStore.rows` filtered to `.running` (already
`@Observable`).

---

## 7. `GlobalDownloadOptions` + `YtDlpArguments`

New value type in `GrabberKit`, beside `YtDlpArguments.swift`:

```swift
public struct GlobalDownloadOptions: Sendable, Equatable {
    public var proxyURL: String?
    public var forceIPv4: Bool
    public var speedLimitKBps: Int   // 0 = no limit
    public init(proxyURL: String?, forceIPv4: Bool, speedLimitKBps: Int)
    public static let none = GlobalDownloadOptions(
        proxyURL: nil, forceIPv4: false, speedLimitKBps: 0
    )
}
```

`YtDlpArguments`:

```swift
public static func build(
    for request: DownloadRequest,
    options: GlobalDownloadOptions = .none
) -> [String]

public static func redacted(
    for request: DownloadRequest,
    options: GlobalDownloadOptions = .none
) -> [String]
```

- Appends `--proxy <url>` when `proxyURL` is non-nil and non-empty.
- Appends `-4` when `forceIPv4`.
- Appends `--limit-rate <N>K` when `speedLimitKBps > 0`.
- `redacted` **diverges** from `build`: proxy userinfo (`user:pass@`) is masked
  in the returned proxy URL (`***@`). Identical to `build` in every other
  respect.
- The default `.none` argument keeps every existing call site compiling
  unchanged.

`DownloadEngine` reads the three fields off `preferences` into a
`GlobalDownloadOptions` value **before** the launcher `Task` (as it does for
`request`), then passes it to `build(for:options:)`. `ProcessRunner` stays the
only place `Foundation.Process` is touched; `DownloadEngine` stays the only
spawner (CLAUDE.md). Wiring `redacted` into the `processLaunched` log event is
Phase 4's concern — the seam already exists and is not touched here.

---

## 8. Doc updates

### 8.1 Design-system doc (`apps/media-grabber/docs/design-system.md`)

Living doc — updated as part of this phase, not archived.

1. **Global "Skin" → "Theme" rename.** §2 heading "Skins" → "Themes",
   §2.1 / §2.2 prose, every "skin" occurrence in component and palette
   sections, `data-skin` → `data-theme` wherever the doc references the mockup
   attribute.
2. **§4.6 Preferences** — rewrite to match §5 here: two-column row layout, title
   hierarchy, fixed window height, rail no-scroll, right pane scrolls; per-pane
   row tables with the final labels / helpers / controls; stepless Sign-in /
   Updates; Advanced buttons; the concurrency note. Fix the concurrency stepper
   range to **1–6**. Update the "new `Preferences` fields this section
   introduces" line to the §3 set (post-rename names).
3. **§4.9 `SkinnedSegment`** (new) — §4.1 here, including the equal-width /
   hug-content / flush-right sizing.
4. **§4.10 `SkinnedPicker`** (new) — §4.2 here, including "popover, not a
   modal" and the content-sized-clamped popover width.
5. **§4.2.2** — note the runway's Media-type / Format / Save-to slots now use
   `SkinnedSegment` / `SkinnedPicker`, not native `Menu`.
6. **§5.2 Tape Deck palettes** — darken `--warn` for legibility as text / glyph
   on the cream `--panel-solid`. Current values (`#E4A11B` / `#E8B24A` /
   `#F2B12E`) are low-contrast; replace with darker ambers (≈ `#9C5A00` /
   `#9A6410` / `#8E6318` — final values chosen against a WCAG AA check for
   normal text on each palette's `--panel-solid`). Leave the `--go` rows
   (which currently share the `--warn` hex) unchanged. Aurora `--warn`
   unchanged. This is a plain change this phase makes to completed-phase
   palette tokens (parent §12 scoping rule 3); it also affects future
   `--warn`-as-text uses (Phase 6 cooldown copy).
7. **§3.4** — confirm the warn glyph the confirmation dialog already references
   is reused for the concurrency note; no new glyph.

### 8.2 Screen mockups (`apps/media-grabber/docs/mockups/screens.html`)

The maintained mockup and the dev-facing source of truth for how every screen
looks once the decisions made to date (Phases 1–3) are implemented. It is a
**snapshot**, not a changelog — it shows the target state, not what changed.
This file uses phase references only where a caption genuinely helps a dev
(a screen a later phase re-details); it is a meta file, not shipped UI, so the
no-phase-reference rule does not apply to it.

Rebuild scope:

- **Structure** — a table of contents at the top with jump links; sectioned
  dotted numbering; the skin/palette switcher retained and verified to write
  the correct token values for every palette.
- **Fidelity** — every `.app` block is a fixed **980 × 720** (the app's
  `.defaultSize`), 1 CSS px = 1 pt so a dev can measure directly. Key
  structural dimensions annotated (window size, rail width, pane padding, row
  divider, control heights, confirmation card `max-width` 420). Not a full
  redline — the spacing scale and token values live in `design-system.md`.
- `data-theme`, not `data-skin`.

Sections:

- **§1 Home** — 1.1 first run · 1.2 link resolved (runway + table) · 1.3 column
  filter menu open. The runway Media-type / Format / Save-to slots render as
  `SkinnedSegment` / `SkinnedPicker` (§5.1.2–5.1.3); quality ladder drops 360,
  adds "Best available"; Save-to picker shows default + last-used (if distinct)
  + "Choose…", always seeded. Future-phase chrome already drawn on 1.2
  (cooldown chip, cooldown banner, success toast) is kept with a minimal phase
  tag in the caption.
- **§2 Onboarding** — 2.1 first-run setup. Unchanged this phase apart from the
  `--theme` attribute rename.
- **§3 Preferences** — one `.app` block per pane: 3.1 Downloads · 3.2
  Appearance · 3.3 Network · 3.4 Sign-in & cookies (stepless) · 3.5 Updates
  (stepless) · 3.6 Logs & privacy · 3.7 Advanced. Single render each; the
  switcher covers both themes. Rail shown not-scrolling; the Downloads pane
  shown mid-scroll to demonstrate the fixed height + independent scroll.
  **3.8 Control details** — isolated pane-region fragments (not full windows),
  clubbed in one block: the concurrency note expanded under the stepper; the
  Filename-format row with "Custom…" selected and the monospace field revealed;
  the Filename-format `SkinnedPicker` with its popover open (caption header,
  checkmark, hover wash, ~320 pt width).
- **§4 Dialogs** — 4.1 confirmation, destructive variant (warn glyph, `--danger`
  confirm, over a dimmed Advanced pane) · 4.2 confirmation, notice variant
  (single button, no glyph). design-system §4.8.
- **§5 Playlist** — 5.1 picker modal · 5.2 group in table. Carried from the
  current file; caption notes the depiction updates when Phase 8 is detailed.
- **§6 Diagnostics** — 6.1 report card. Carried; caption notes Phase 10.

---

## 9. Testing (TDD — test before implementation for every unit)

**`GrabberKitTests`:**

- `YtDlpArguments` — `options: .none` emits no `--proxy` / `-4` / `--limit-rate`;
  each field set emits its flag with the right formatting; `--limit-rate`
  omitted when `speedLimitKBps` is `0`; `redacted` masks `user:pass@` in the
  proxy URL and is otherwise identical to `build`.
- `Preferences` new fields — defaults; `speedLimitKBps` clamp bounds (`0` and
  `100000`); `proxyURL` empty-string → `nil`; `lastVideoHeight` /
  `lastMediaType` / `lastAudioFormat` round-trip through `UserDefaults`
  including `Int.max`.
- `Preferences.resetToDefaults()` — restores every field to its default; the
  owned-key list is exhaustive (cross-checked against every `forKey:` literal
  in the file).
- Renamed fields — a set of the old-name values does not resolve under the new
  getters (proves the key strings changed), and the new getters return correct
  defaults on a fresh suite.
- `GlobalDownloadOptions` — `.none` is all-empty; `Equatable` holds.

**`AppUnitTests`:**

- `PreferencesPane` — every rail group's `panes` union equals
  `PreferencesPane.allCases` with no duplicates; group order matches §5;
  `AppModel.Page.preferences()` equals `.preferences(.downloads)`.
- `shouldShowConcurrencyNote(newValue:runningCount:)` — true iff
  `newValue < runningCount`; boundary at equality; `runningCount == 0` is false.
- `FileNamingPreset` — each preset row → its exact template; an unrecognised
  string → `.custom`; `.matching(_:)` recognises every preset template.
- `runwaySeed(from:)` — falls back to defaults when no `last*` is set; prefers
  `last*` when present, including `Int.max` for height.
- `AppModel.grab(overrides:)` writes `lastMediaType` / `lastVideoHeight` /
  `lastAudioFormat` from `overrides.kind`.
- Reset mutations — `columnConfig = .default` restores the default column set /
  order; `resetAllSettings()` writes every `Preferences` field to its default
  (assert on the model, not the view).

**Not tested:** SwiftUI view rendering, `NSOpenPanel` / `NSWorkspace` calls,
live re-theme (visual), the popover's flip-above geometry.

**Manual smoke** (leaf checklist, added by the plan): open each pane; change
Theme + palette and see the app re-theme; lower the concurrency cap below a
running download and see the note, then see it clear as downloads finish; set a
proxy / Force IPv4 / speed limit and confirm the next download's `yt-dlp` argv
carries the flags; "Reset settings" restores defaults; "Reset columns" is
independent; runway Media-type / Quality / Save-to pickers open, select, and
persist to the next paste; Filename format "Custom…" reveals the field, persists,
and re-derives to the right row on reopen.

---

## 10. Definition of done

- All of §1 "in this phase" built to final-app form, including the §11 rename
  sweep.
- `tuist test` green; `swiftformat --lint` + `swiftlint --strict` clean.
- Manual smoke checklist passes on a real machine.
- `design-system.md` updated per §8.1; `screens.html` rebuilt per §8.2.
- Parent spec §12.1 Phase 3 stub + §12.2 `PreferencesView` row updated to
  reflect what shipped. Deferred hints on the Phase 5 / 7 / 8 / 10 stubs
  (already added: 5 / 8 / 10 mockup hints; add the Phase 7 seed-clamp hint).
- Commit tagged `phase-3`.

---

## 11. Pre-release vocabulary sweep

The app is unreleased; no `UserDefaults` data is worth preserving. These renames
are done in Phase 3 because it is the moment the Preferences UI first exposes
these names to a user, and because the `Theme` / `Skin` split becomes load-
bearing here. Presented as a plain change this phase makes to completed-phase
code (parent §12 scoping rule 3) — not a fix of a past mistake.

### 11.1 `Skin` → `Theme`

| Old | New | Target |
|---|---|---|
| `enum SkinKind` | `enum ThemeKind` | GrabberKit (`Preferences.swift` neighbourhood) |
| `enum Skin` | `enum Theme` | App (`Sources/App/Theme/`) |
| `Skin.swift` | `Theme.swift` | file rename |
| `SkinEnvironment.swift` | `ThemeEnvironment.swift` | file rename |
| `struct ResolvedTheme` | collapsed — the environment value is `Theme`, which carries the palette, typography accessors, and radii directly (no wrapper) | App |
| `Preferences.skin` | `Preferences.theme` (key `mg.skin` → `mg.theme`) | GrabberKit |
| `theme.skin.bodyFont(…)` etc. | `theme.bodyFont(…)` | all call sites |
| `data-skin`, `:root[data-skin="…"]` | `data-theme`, `:root[data-theme="…"]` | mockup + design-system |
| `ThemeKind.aurora` / `.tapeDeck` | unchanged raw values (`"aurora"` / `"tapeDeck"`) | |

`ThemeKind` stays a `String`-raw identity type in `GrabberKit` (no SwiftUI); the
`Color` / `Font`-bearing `Theme` stays in the App target. The
`@Entry var theme` environment value's type changes from `ResolvedTheme` to
`Theme`.

### 11.2 `Preferences` field renames

| Old field | New field | Old key | New key |
|---|---|---|---|
| `defaultDestFolder` | `defaultDownloadFolder` | `mg.defaultDestFolder` | `mg.defaultDownloadFolder` |
| `lastUsedDestFolder` | `lastUsedDownloadFolder` | `mg.lastUsedDestFolder` | `mg.lastUsedDownloadFolder` |
| `defaultMaxHeight` | `defaultVideoHeight` | `mg.defaultMaxHeight` | `mg.defaultVideoHeight` |
| `defaultAudioCodec` | `defaultAudioFormat` | `mg.defaultAudioCodec` | `mg.defaultAudioFormat` |
| `outputTemplate` | `filenameTemplate` | `mg.outputTemplate` | `mg.filenameTemplate` |
| `maxAutoAttempts` | `maxAutoRetries` | `mg.maxAutoAttempts` | `mg.maxAutoRetries` |
| `defaultAudioOrVideo` (private) | `defaultMediaType` (public) | `mg.defaultKindSelector` | `mg.defaultMediaType` |
| `skin` | `theme` | `mg.skin` | `mg.theme` |

Kept as-is (not 1:1 with a single user-facing setting, or already fine):
`defaultKind` (computed), `maxConcurrentDownloads`, `verboseLogging`, `palette`.

### 11.3 Type renames

| Old | New | Target | Notes |
|---|---|---|---|
| `AudioCodec` | `AudioFormat` | GrabberKit | 1:1 with the "Audio format" setting. Live in `DownloadRequest.swift`, `DownloadKind`, `YtDlpArguments`, tests. Raw values `m4a` / `mp3` unchanged. |
| `KindSelector` (private in `Preferences`) | `MediaType` (public) | GrabberKit | `{ case video, audio }`. `RunwayView.KindSelector` (the nested App-target copy) is deleted; call sites use `MediaType`. |
| `DownloadKind` | *keep* | | Not 1:1 with a user setting — it is the request payload union (`.video(maxHeight:)` / `.audio(format:)`). Its `.audio` associated label changes `codec:` → `format:` with the `AudioFormat` rename. |

### 11.4 Call-site fallout (non-exhaustive)

`RequestBuilder.swift` (`RunwayOverrides`, `container(for:)`), `HomeView.swift`
(`@State` types, `seedFromPrefs`, `selectedKind`), `RunwayView.swift` (deletes
the nested enum, all four bindings), `AppModel.swift` (`grab`, the `Page`
enum), `MainWindow.swift` (nav target + active check), every file under
`Sources/App/Theme/`, `Sources/App/Table/` and `Sources/App/Chrome/` that reads
`theme.skin.*`, and the corresponding test files
(`PreferencesTests`, `RequestBuilderTests`, `ThemeTests`, `YtDlpArgumentsTests`,
`ValueTypesTests`, `AppModelTests`). `tuist generate --no-open` after the file
renames.
