# Preferences screen (Phase 3)

**Status:** design complete. Plan: not yet written. Parent spec:
`docs/superpowers/specs/2026-08-28-youtube-downloader-mac-design.md` §12.1.
Phase 2 (shipped): `docs/superpowers/specs/queue-foundation.md`.
Visual reference: `assets/2026-08-31-media-grabber-phase-3/` (mockups —
`prefs-full-v2.html` is the pane layout, `skinned-picker-v2.html` the picker,
`appearance-swatch-final.html` the palette swatch, `concurrency-note-v3.html`
the inline note).

Phases 1–2 gave the runway hard-coded default reads from the `Preferences`
model (`skin` / `palette` / `defaultKind` / `defaultMaxHeight` / dest folder)
with no editor. Phase 3 builds the in-app Preferences page — the 7-pane
`PreferencesView` over that model — and, in the same pass, the two reusable
skinned form controls the page needs (`SkinnedSegment`, `SkinnedPicker`), which
also replace the native `Menu` dropdowns on the Home runway.

Everything built here is built to its final-app form. Panes a later phase fills
(Sign-in & cookies → Phase 5, Updates → Phase 10) ship as complete headers; the
`Preferences` fields, `YtDlpArguments` wiring, and controls introduced here are
final. No shape a later phase must replace (parent §12 scoping rule).

---

## 1. Scope

**In this phase:**

- The 7-pane `PreferencesView`: grouped left rail, right pane of two-column
  rows (`label + helper` left, control right), fixed window height with the
  right pane scrolling independently.
- **Filled panes:** Downloads, Appearance, Network, Logs & privacy, Advanced.
- **Header-only panes:** Sign-in & cookies (Phase 5 fills), Updates (Phase 10
  fills). Present in the rail, render a title + sub + one "filled in Phase N"
  line.
- **`SkinnedSegment`** — skinned 2–3-option segmented control, all options
  visible, one tap.
- **`SkinnedPicker<T>`** — skinned trigger button + popover list (caption
  header, checkmark on selected, hover highlight, optional per-row subtitle, no
  row icons). Keyboard + VoiceOver. No scroll cap this phase.
- Both controls replace the native `Menu` dropdowns on the Home runway.
- New `Preferences` fields (§3) and their persistence.
- `GlobalDownloadOptions` in `GrabberKit` + `YtDlpArguments` wiring for the
  Network flags.
- The "concurrency lowered below running count" inline note.
- `AppModel.Page.preferences` carries a target `PreferencesPane` (deep-link
  seam for later phases).
- Doc updates: `design-system.md` and `screens.html` (§8).

**Deferred (hints land in the owning phase's stub):**

- Runway per-download quality picker showing only probe-reported available
  heights — **Phase 7** (needs format-list parsing on `MetadataProbe`).
- In-app rendered `PRIVACY.md` sheet — this phase opens the file externally.
- Diagnostics page — **Phase 10**; its nav placeholder is untouched here.
- `maxAutoAttempts` control ("If a download fails, try") — row is laid out this
  phase but the field already exists and the retry engine is **Phase 4**; the
  stepper is shown and persists.

**Not in scope:** Diagnostics content, cookies UI, Updates UI, toasts,
multi-select, column drag-reorder.

---

## 2. Architecture

`PreferencesView` is a plain SwiftUI page in the App target, selected by
`AppModel.page`. It reads and writes the `@Observable Preferences` model
directly — every consumer (runway, engine `cap`, `Skin`/`Palette` resolution)
already binds that model live, so an edit re-themes and re-defaults the app with
no extra plumbing.

```
Sources/App/Preferences/
  PreferencesView.swift     — the page: rail + selected-pane switch
  PreferencesPane.swift     — enum: cases, titles, rail group; deep-link target
  PrefRow.swift             — the shared label+helper / control row
  Panes/
    DownloadsPane.swift
    AppearancePane.swift
    NetworkPane.swift
    SignInCookiesPane.swift  — header-only
    UpdatesPane.swift        — header-only
    LogsPrivacyPane.swift
    AdvancedPane.swift

Sources/App/Controls/
  SkinnedSegment.swift
  SkinnedPicker.swift

Sources/GrabberKit/Download/
  GlobalDownloadOptions.swift   — beside YtDlpArguments.swift
```

One file per pane so later phases (4/5/6/10) each edit one small focused file.
`PrefRow` is the field primitive; panes stay declarative lists of rows.

`SkinnedSegment` / `SkinnedPicker` `import SwiftUI` only — generic over the
option type, no `GrabberKit`. Call sites pass the concrete type (`AudioCodec`,
an Int height, a `FileNamingPreset`, a folder `URL`).

### 2.1 Navigation / deep-link

`AppModel.Page.preferences` gains an associated value:

```swift
enum Page: Equatable {
    case home
    case preferences(PreferencesPane = .downloads)
    case diagnostics
}
```

`PreferencesView` holds `@State selectedPane`, seeded from the associated value,
thereafter driven by the rail. **Not persisted** — Preferences always opens to
Downloads unless a caller deep-links a specific pane. Later phases route errors
here (`.preferences(.network)`, `.preferences(.cookies)`).

The `MainWindow` nav button targets `.preferences()` (defaulted). The
`.diagnostics` case and its placeholder are unchanged.

---

## 3. `Preferences` — new fields

All `UserDefaults`-backed, same pattern as the existing model.

| Field | Type | Default | Notes |
|---|---|---|---|
| `clipboardAutoDetect` | `Bool` | `true` | "Watch the clipboard". Persists only; the clipboard watch itself is Phase 9. |
| `proxyURL` | `String?` | `nil` | Trimmed; empty string stored as `nil`. |
| `forceIPv4` | `Bool` | `false` | |
| `selfRateLimitKBps` | `Int?` | `nil` | `nil` = "Off". Clamped to `1…100000` when set. |
| `lastSelectedMaxHeight` | `Int?` | `nil` | Written on Grab. `Int.max` is a valid value ("Best available"). |
| `lastSelectedKind` | `KindSelector?` | `nil` | `.video` / `.audio`. Written on Grab. |
| `lastSelectedAudioCodec` | `AudioCodec?` | `nil` | Written on Grab. |

`KindSelector` is today `private` inside `Preferences`; promote it to an
`public enum KindSelector: String, Codable, Sendable, CaseIterable` so
`lastSelectedKind` can be typed and the runway can read it.

**"Best available" storage.** The Preferences "Default video quality" picker and
the runway quality picker both offer `2160 / 1440 / 1080 / 720 / 480 / Best
available`. "Best available" is stored as `Int.max` in `defaultMaxHeight` /
`lastSelectedMaxHeight`. `YtDlpArguments` needs no special case —
`bv*[height<=9223372036854775807]` is always satisfied, so yt-dlp picks the
best. Existing default stays `1080`.

### 3.1 Runway seeding

`HomeView.seedFromPrefs` (today reads `prefs.defaultKind` once) changes to:

- kind = `lastSelectedKind ?? default(from defaultAudioOrVideo)`
- maxHeight = `lastSelectedMaxHeight ?? defaultMaxHeight`
- audioCodec = `lastSelectedAudioCodec ?? defaultAudioCodec`
- destFolder = `lastUsedDestFolder` if set & distinct, else `defaultDestFolder`
  (unchanged from today apart from the picker offering both — §5.1)

On Grab, `RequestBuilder` / the grab path writes `lastSelected*` and
`lastUsedDestFolder` from the runway's current selection.

**Deferred to Phase 7** (hint added to its stub): when the runway quality picker
is restricted to probe-reported available heights, the seed resolves
`lastSelected` → if available use it → else `defaultMaxHeight` if available →
else the best available height.

---

## 4. Controls

### 4.1 `SkinnedSegment`

A skinned segmented control. Full design-system entry in `design-system.md`
§4.9 (new).

- 2–3 options, all rendered as segments in a `--panel` track with a
  `--stroke` border; the selected segment gets a `--panel-solid` fill.
- One tap selects. No popover.
- Keyboard: Left/Right moves selection when focused; VoiceOver exposes it as a
  radio group / segmented control with the option labels.
- Palette-matched: track, border, and selected-fill are skin tokens; radius is
  the skin's `chipRadius`.

**Used by:** Skin (Appearance), Default type (Downloads + runway), Default audio
format (Downloads + runway).

### 4.2 `SkinnedPicker<T>`

A skinned dropdown. Full entry in `design-system.md` §4.10 (new). See
`assets/2026-08-31-media-grabber-phase-3/skinned-picker-v2.html`.

- **Trigger** — a button showing the current selection's label + a chevron,
  `--panel` fill, `--stroke` border, skin `controlRadius`.
- **Popover** — opens below the trigger (flips above if no room). `--panel-solid`
  fill, skin border + `cardRadius` + elevation (glow on Aurora, hard shadow on
  Tape Deck), matching the confirmation-dialog card treatment.
  - **Caption header** — a `--faint` uppercase label naming what is being
    chosen (e.g. "Resolution", "Browser"), with a hairline rule under it.
  - **Rows** — label; optional second-line **subtitle** in `--dim` (`nil` →
    single-line row); a checkmark (`--accent`) on the selected row; hover /
    arrow-key highlight uses a translucent accent wash.
  - **No row icons.**
- Keyboard: Return/Space opens; Up/Down moves the highlight; Return selects;
  Esc closes without changing. VoiceOver: a menu/pop-up button; the popover
  traps focus; the selected row is announced.
- No `maxVisibleRows` / scroll cap this phase — every list is ≤ 6 rows. Phase 5
  (Firefox profile list) adds a cap + scroll; additive, no layout change.

**Used by:** Default video quality (Downloads + runway), File naming
(Downloads), Save to (runway). Phase 5 adds the cookie-browser and Firefox-
profile pickers; Phase 8 the playlist filters as applicable.

**Subtitle call sites this phase:** Save-to (folder path under a possibly
duplicate folder name). Quality and File-naming pass `nil` on every row.

---

## 5. Panes

Two-column rows: `label` (13, `--text`, semibold) + `helper` (11.5, `--dim`)
stacked on the left; control right-aligned; a `--hair` divider between rows. Page
title 20/heavy in `--headline` with a rule under it, a one-line `--dim` sub
above the rule. Rail: three group captions — **General** (Downloads ·
Appearance · Network), **YouTube** (Sign-in & cookies), **System** (Updates ·
Logs & privacy · Advanced).

### 5.1 Downloads

| Row | Control | Backs |
|---|---|---|
| Save to | `SkinnedPicker` — but for the *Preferences* default this is a single folder: the trigger shows the current folder, opening it presents `NSOpenPanel` (directories only). No list. | `defaultDestFolder` |
| At the same time | stepper 1–6 · "The app lowers this on its own if a site starts throttling." | `maxConcurrentDownloads` |
| If a download fails, try | stepper 1–5 · "How many times to retry automatically before asking you." · *(retry engine is Phase 4; the stepper persists now)* | `maxAutoAttempts` |
| Default type | `SkinnedSegment` — Video / Audio | `defaultAudioOrVideo` |
| Default video quality | `SkinnedPicker` — 2160p / 1440p / 1080p / 720p / 480p / Best available | `defaultMaxHeight` (`Int.max` for Best) |
| Default audio format | `SkinnedSegment` — m4a / mp3 | `defaultAudioCodec` |
| File naming | `SkinnedPicker` — Title / Title and channel / Date and title / Custom… (§5.1.1) | `outputTemplate` |
| Watch the clipboard | toggle · "Offer to grab a link when you copy one." · *(acts in Phase 9)* | `clipboardAutoDetect` |

**Concurrency note** (§6) renders in the "At the same time" row's right column,
under the stepper, when the new value is below the live running count.

The **Preferences "Save to"** control differs from the **runway "Save to"**
(§5.1.2) — the Preferences one edits a single default folder and needs no list.

#### 5.1.1 File naming

`FileNamingPreset` (App target, not persisted):

| Row label | Template | Example subtitle |
|---|---|---|
| Title | `%(title)s.%(ext)s` | `Never Gonna Give You Up.mp4` |
| Title and channel | `%(title)s - %(uploader)s.%(ext)s` | `Never Gonna Give You Up - Rick Astley.mp4` |
| Date and title | `%(upload_date>%Y-%m-%d)s - %(title)s.%(ext)s` | `2009-10-25 - Never Gonna Give You Up.mp4` |
| Custom… | — | reveals a monospace text field below the picker |

- The picker maps a preset row → its template string on select.
- On load / open, the selected row is **derived** from the stored
  `outputTemplate`: if it string-matches a preset template, that row is
  selected; otherwise "Custom…" is selected and the text field shows the stored
  string.
- Custom text field: monospace, pre-filled with the current template. Empty on
  blur → revert to the previously stored value. No syntax validation beyond
  non-empty.
- Backing is `outputTemplate: String` only. No new field — the preset is state
  derived from the string.

#### 5.1.2 Runway "Save to" (Home)

The runway's "Save to" slot becomes a `SkinnedPicker`:

- Row 1 — `defaultDestFolder`. Label = folder name; subtitle = full path.
- Row 2 — `lastUsedDestFolder`, **only if it differs from `defaultDestFolder`**.
  Label = folder name; subtitle = full path.
- Row 3 — "Choose…" → `NSOpenPanel`. On pick: sets the per-download dest and
  writes `lastUsedDestFolder`.
- Default selection: `lastUsedDestFolder` if set & valid, else
  `defaultDestFolder`.

#### 5.1.3 Runway Type / Quality / Format

- Type slot → `SkinnedSegment` (Video / Audio).
- Format slot → `SkinnedSegment` for the audio codec when Type = Audio;
  `SkinnedPicker` for the quality ladder when Type = Video. (Matches the two
  distinct controls the runway needs — a codec pair vs a 6-value ladder.)
- Ladder: `2160 / 1440 / 1080 / 720 / 480 / Best available` — **drop `360`**
  (currently in `RunwayView.heights`), **add "Best available"** (`Int.max`).
- On Grab the runway writes `lastSelectedKind` / `lastSelectedMaxHeight` /
  `lastSelectedAudioCodec`.

### 5.2 Appearance

See `assets/2026-08-31-media-grabber-phase-3/appearance-swatch-final.html`.

| Row | Control | Backs |
|---|---|---|
| Skin | `SkinnedSegment` — Aurora / Tape Deck · "Aurora is dark and luminous. Tape Deck is warm and light." | `skin` |
| Palette | 3 swatches for the selected skin | `palette` |

- **Swatch** — a rounded tile: a split fill of `--accent` (left half) and
  `--accent-2` (right half) over ~38 px, the palette name in `--text`
  underneath. Selected swatch gets a 2 px `--accent` outline with a 2 px offset.
- Only the 3 palettes of the currently-selected skin are shown; the set swaps
  when Skin changes.
- Changing Skin resets `palette` to that skin's default (`.auroraMintIris` /
  `.tapeDeckA`) — matches the model's existing fallback.
- Both controls apply live (the whole app re-themes on click).

### 5.3 Network

Flags passed to `yt-dlp` via `GlobalDownloadOptions` (§7 wiring).

| Row | Control | Backs |
|---|---|---|
| Proxy | text field · "e.g. `http://host:port`. Leave blank for none." | `proxyURL` |
| Use IPv4 only | toggle · "Try this if downloads stall on connection errors." | `forceIPv4` |
| Limit download speed | stepper (KB/s) with an "Off" position | `selfRateLimitKBps` |

The three flags affect **new** downloads only — a running child process is not
restarted. (No note needed; unlike concurrency this is the obvious behaviour of
a per-launch flag.)

### 5.4 Sign-in & cookies — header-only

Title + sub + one line: "Filled in Phase 5 — browser picker, Firefox profile,
Full Disk Access, tip text." No `Preferences` fields added this phase
(`cookiesFromBrowser`, `firefoxProfile` land in Phase 5).

### 5.5 Updates — header-only

Title + sub + one line: "Filled in Phase 10 — yt-dlp / ffmpeg / app versions,
check buttons, daily-check toggle." `autoCheckUpdates` lands in Phase 10.

### 5.6 Logs & privacy

| Row | Control | Action |
|---|---|---|
| Open log folder | button | `NSWorkspace.open(~/Library/Logs/MediaGrabber)` |
| Detailed logging | toggle | `verboseLogging` (exists) |
| What's in the logs | button ("View") | `NSWorkspace.open` the bundled `PRIVACY.md` |

### 5.7 Advanced

| Row | Control | Action |
|---|---|---|
| Open app data folder | button | reveal `~/Library/Application Support/MediaGrabber` |
| Reset table columns | button | `appModel.columnConfig = .default` — propagates to `RowStore` + persistence via the existing `didSet` |
| Reset all settings | button (`--danger`), `ConfirmationRequest` `isDestructive: true`, `suppressionKey: nil` | every `Preferences` field → its default |

- "Reset all settings" resets the `Preferences` model **only** — not
  `columns.json` (that has its own button). Skin / palette / defaults snap
  live; the concurrency note shows if the reset cap is below the running count,
  same as a manual change.
- "Reset table columns" and "Reset all settings" are independent.

---

## 6. Concurrency-lowered inline note

See `assets/2026-08-31-media-grabber-phase-3/concurrency-note-v3.html` (D1).

When the user sets "At the same time" to `N` while the live running-job count is
`> N`:

- An inline note appears in the row's right column, under the stepper.
- **Leading glyph** — the design-system warn glyph (§3.4), tinted `--warn`.
- **Text** — `--dim`, one short sentence:
  `"<count> running at the old limit — restart to apply now."`
- The note clears when the running count drops to `≤ N`, or on relaunch.

**No new drain logic.** The Phase 2 scheduler already gates
`running < cap` and reads `cap` live from `preferences.maxConcurrentDownloads`
on every `evaluateSchedule()`. Lowering the cap fires no engine event, so the
running jobs continue and the next natural completion re-evaluates with the new
cap — the queue drains to the new limit on its own. The note only *explains*
this.

The visibility predicate is a pure function
(`shouldShowConcurrencyNote(newValue:runningCount:) -> Bool`) so it is unit-
testable without a view. Running count comes from
`AppModel.rowStore.rows` filtered to `.running` (already `@Observable`).

---

## 7. `GlobalDownloadOptions` + `YtDlpArguments`

New value type in `GrabberKit`, beside `YtDlpArguments.swift`:

```swift
public struct GlobalDownloadOptions: Sendable, Equatable {
    public var proxyURL: String?
    public var forceIPv4: Bool
    public var rateLimitKBps: Int?
    public static let none = GlobalDownloadOptions(
        proxyURL: nil, forceIPv4: false, rateLimitKBps: nil
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

- Appends `--proxy <url>` when `proxyURL` is non-empty.
- Appends `-4` when `forceIPv4`.
- Appends `--limit-rate <N>K` when `rateLimitKBps != nil && > 0`.
- `redacted` now **diverges** from `build`: proxy userinfo (`user:pass@`) is
  masked in the returned URL. (This is the "proxy creds" case the existing
  `redacted` seam comment anticipated.)
- The default `.none` argument keeps every existing call site compiling
  unchanged.

`DownloadEngine` builds a `GlobalDownloadOptions` from `preferences` at spawn
time and passes it to `build(for:options:)`. `ProcessRunner` stays the only
place `Foundation.Process` is touched; `DownloadEngine` stays the only spawner
(CLAUDE.md).

---

## 8. Doc updates

### 8.1 Design-system doc (`apps/media-grabber/docs/design-system.md`)

Living doc — updated as part of this phase, not archived.

1. **§4.6 Preferences** — rewrite to match §5 here: two-column row layout, title
   hierarchy, fixed-height + scrolling right pane; per-pane row tables with the
   locked controls; header-only Sign-in / Updates; Advanced buttons; the
   concurrency note.
2. **§4.9 `SkinnedSegment`** (new) — §4.1 here.
3. **§4.10 `SkinnedPicker`** (new) — §4.2 here.
4. **§4.2.2** — note the runway's Type / Format / Save-to slots now use
   `SkinnedSegment` / `SkinnedPicker`, not native `Menu`.
5. **§5.2 Tape Deck palettes** — darken `--warn` for legibility as text / glyph
   on the cream `--panel-solid`. Current values (`#E4A11B` / `#E8B24A` /
   `#F2B12E`) are low-contrast; replace with darker ambers (≈ `#9C5A00` /
   `#9A6410` / `#8E6318` — final values chosen against a WCAG AA check for
   normal text on each palette's `--panel-solid`). Aurora `--warn` unchanged.
   This is a plain change this phase makes to completed-phase palette tokens
   (parent §12 scoping rule 3); it also affects future `--warn`-as-text uses
   (Phase 6 cooldown copy).
6. **§3.4** — confirm the warn glyph the confirmation dialog already references
   is reused for the concurrency note; no new glyph.

### 8.2 Screen mockups (`apps/media-grabber/docs/mockups/screens.html`)

Single-page, hand-rolled HTML/CSS gallery (its own `<style>` token system —
**do not import the brainstorm mockup CSS**; work within the file's existing
`.field2` / `.fl` / `.fc` / palette classes). Update so it reflects the Phase 3
design:

- **Screen 6 Preferences — Downloads pane:** add the "If a download fails, try"
  row (§5.1); add the concurrency note in the "At the same time" row; render
  the Type / Quality / Audio-format / File-naming controls as the skinned
  segment / skinned-picker style, not native `<select>` / `<input>`.
- **Screen 6 Preferences — Appearance pane:** already close; align helper copy
  and the swatch treatment to §5.2.
- **New Preferences panes** (add as sibling `.app` blocks after Appearance, one
  per pane): Network (§5.3), Sign-in & cookies (header-only, §5.4), Updates
  (header-only, §5.5), Logs & privacy (§5.6), Advanced (§5.7).
- **Screens 0–2 (Home):** show the runway Type / Format / Save-to slots as
  `SkinnedSegment` / `SkinnedPicker` (§5.1.2–5.1.3), replacing the current
  native-dropdown depiction; Save-to picker shows default + last-used (if
  distinct) + "Choose…".
- Both skins where the file already shows both; keep the file's existing screen
  numbering and section-comment style.

This is the first plan task — mechanical, low-risk, within one file.

---

## 9. Testing (TDD — test before implementation for every unit)

**`GrabberKitTests`:**

- `YtDlpArguments` — `options: .none` emits no proxy / `-4` / `--limit-rate`;
  each field set emits its flag with the right formatting; `--limit-rate`
  omitted when `rateLimitKBps` is `0` / negative; `redacted` masks
  `user:pass@` in the proxy URL and is otherwise identical to `build`.
- `Preferences` new fields — defaults; `selfRateLimitKBps` clamp bounds;
  `proxyURL` empty-string → `nil`; `lastSelected*` round-trip through
  `UserDefaults` including `Int.max`.
- `GlobalDownloadOptions` — `.none` is all-empty; `Equatable` holds.

**`AppUnitTests`:**

- `PreferencesPane` — deep-link value resolves to the right rail selection;
  default is `.downloads`.
- `shouldShowConcurrencyNote(newValue:runningCount:)` — true iff
  `newValue < runningCount`; boundary at equality.
- `FileNamingPreset` — template → preset row mapping; an unrecognised string →
  Custom with the string preserved; each preset row → its exact template.
- Reset mutations — `columnConfig = .default` restores default column set /
  order; "reset all" writes every `Preferences` field to its default (assert on
  the model, not the view).

**Not tested:** SwiftUI view rendering, `NSOpenPanel` / `NSWorkspace.open`, live
re-theme (visual), the popover's flip-above geometry.

**Manual smoke** (leaf checklist, added by the plan): open each pane; change
skin + palette and see the app re-theme; lower the concurrency cap below a
running download and see the note; set a proxy / IPv4 / rate limit and confirm
the next download's `yt-dlp` argv (job log) carries the flags; "reset all
settings" restores defaults; runway Type / Quality / Save-to pickers open,
select, and persist to the next paste.

---

## 10. Definition of done

- All of §1 "in this phase" built to final-app form.
- `tuist test` green; `swiftformat --lint` + `swiftlint --strict` clean.
- Manual smoke checklist passes on a real machine.
- `design-system.md` updated per §8.1; `screens.html` updated per §8.2.
- Parent spec §12.1 Phase 3 stub + §12.2 `PreferencesView` row updated to
  reflect what shipped; deferred hint added to the Phase 7 stub (runway quality
  picker restricted to probe-available heights + the seed clamp order).
- Commit tagged `phase-3`.
