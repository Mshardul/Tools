# MediaGrabber — Design System

**Status:** draft, tracks §5 of the design spec
**Date:** 2026-08-28
**Working name:** MediaGrabber (final name deferred — spec §14)

This is the source of truth for visual design. Mockups in `mockups/` mirror
these values; if they disagree, this file wins.

---

- [1. Concepts](#1-concepts)
- [2. Themes](#2-themes)
  - [2.1 Tape Deck](#21-tape-deck)
  - [2.2 Aurora](#22-aurora)
- [3. Shared structure (theme-independent)](#3-shared-structure-theme-independent)
  - [3.1 Spacing scale (4pt)](#31-spacing-scale-4pt)
  - [3.2 Type scale](#32-type-scale)
  - [3.3 Motion](#33-motion)
  - [3.4 Iconography](#34-iconography)
- [4. Components](#4-components)
  - [4.1 App chrome](#41-app-chrome)
  - [4.2 Home](#42-home)
    - [4.2.1 States](#421-states)
    - [4.2.2 Paste field + runway](#422-paste-field--runway--the-hero)
    - [4.2.3 Downloads table](#423-downloads-table)
    - [4.2.4 Playlist group in the table](#424-playlist-group-in-the-table)
  - [4.3 Playlist picker (modal)](#43-playlist-picker-modal)
  - [4.4 Toast](#44-toast)
  - [4.5 Onboarding](#45-onboarding)
  - [4.6 Preferences](#46-preferences)
  - [4.7 Diagnostics](#47-diagnostics)
  - [4.8 Confirmation dialog](#48-confirmation-dialog)
  - [4.9 SkinnedSegment](#49-skinnedsegment)
  - [4.10 SkinnedPicker](#410-skinnedpicker)
- [5. Palette token sets](#5-palette-token-sets)
  - [5.1 Token list](#51-token-list)
  - [5.2 Tape Deck palettes (light)](#52-tape-deck-palettes-light)
  - [5.3 Aurora palettes (dark)](#53-aurora-palettes-dark)
- [6. Implementation notes](#6-implementation-notes)


---

## 1. Concepts

| Term | Meaning |
|---|---|
| **Theme** | Visual identity: **Tape Deck** or **Aurora**. Sets type, shape language, elevation style, and the signature motif. |
| **Palette** | A colour variant *within* a theme. Three per theme. Swaps colour tokens only — type, radii, spacing, motif are unchanged by palette. |

User picks a theme, then a palette. Default: **Aurora / Mint & Iris**.

Light/dark orientation is fixed per theme: **Tape Deck is light**, **Aurora is dark**.
Every palette declares a complete token set on `:root[data-theme=…][data-palette=…]`.

---

## 2. Themes

### 2.1 Tape Deck

Warm, tactile, nostalgic hi-fi. Light-first.

| Axis | Value |
|---|---|
| Display face | **Bricolage Grotesque** 700 / 800 — headlines, wordmark, Go button, banner heading |
| Body face | **DM Sans** 400 / 500 / 700 — UI text, table cells, field labels |
| Utility face | **DM Mono** 400 / 500 — chips, status pills, table headers, data, kicker |
| Border | 2px solid `--ink` on structural edges; 1.5px on chips / pills / small controls |
| Radius | window 14 · card 12 · control 8 · pill 20 · chip 6 (px) |
| Elevation | **hard offset shadow** — `8px 8px 0 rgba(0,0,0,.35)` on the window; controls get none |
| Motif | **spinning tape reel** — in the wordmark, and on any actively-downloading row (14px reel, 2s linear spin) |
| Header ground | `--brand` (the palette's deep hue), text in `--surface` |

### 2.2 Aurora

Luminous, calm, premium. Dark-first.

| Axis | Value |
|---|---|
| Display face | **Sora** 600 / 700 — headlines, wordmark, Go button, section headings |
| Body face | **Inter** 400 / 500 / 600 — UI text, table cells |
| Utility face | **JetBrains Mono** 400 / 500 — chips, status pills, table headers, data, kicker |
| Border | hairline — `1px solid --stroke` (a low-alpha white) on structural edges; `--hair` for table row rules |
| Radius | window 18 · card 14 · control 9 · pill 20 · chip 7 (px) |
| Elevation | **glow** — `0 0 0 1px --glow-a, 0 0 32px --glow-b` on the paste console; window uses a deep soft shadow `0 24px 60px rgba(0,0,0,.6)` |
| Motif | **conic-gradient orb** — 20px in the wordmark (6s spin), 14px on actively-downloading rows (2s spin) |
| Header ground | transparent (same as body); divider only |

---

## 3. Shared structure (theme-independent)

Layout, spacing, iconography, copy voice, and component anatomy do **not**
change between themes — only their surface styling does.

### 3.1 Spacing scale (4pt)

`4 · 8 · 12 · 16 · 22 · 30 · 44` px — tokens `--sp-1 … --sp-8`.

### 3.2 Type scale

| Role | Size / line-height | Notes |
|---|---|---|
| Hero headline | 32 / 1.04, letter-spacing −.03em | display face, max ~18ch |
| Section heading (Preferences, Diagnostics) | 18 / 1.3 | display face |
| Onboarding headline | 26 / 1.05 | display face |
| Body | 13 / 1.6 | body face |
| Small / helper | 12 / 1.5 | body face, `--dim` |
| Kicker / eyebrow | 11, letter-spacing .16em, uppercase | utility face, `--accent` |
| Table header | 10, letter-spacing .08em, uppercase | utility face, `--dim` |
| Status pill / chip / data | 10–11 | utility face |

### 3.3 Motion

`--ease: cubic-bezier(.2,.7,.2,1)` · `--dur: 160ms` for state transitions.
Spin animations are linear. **All animation is disabled under
`prefers-reduced-motion: reduce`.**

### 3.4 Iconography

Icons are **bundled SVGs, one library per theme** — the only axis where the two
themes draw from different sources:

- **Tape Deck → Phosphor Bold** (`@phosphor-icons/core`, MIT). Heavy filled-outline weight; matches the 2px borders.
- **Aurora → Lucide** (`lucide`, ISC). Clean 2px stroke; matches the hairline borders.

Within a theme every glyph comes from that one library — never mixed. Only the
~26 glyphs actually used are bundled (≈ 48 SVGs total across both themes), as an
asset catalog. A `NOTICE` file credits both libraries.

**Rendering.** Each glyph is a template image tinted with the current context
colour (`--text`, `--dim`, `--accent`, `--danger`, …). An `Icon` SwiftUI view
takes a semantic case (`Icon(.pause)`), reads the active theme from
`ThemeEnvironment`, and resolves the right asset. Nominal size 16px in dense
spots (row actions, table headers, chips), 15px in nav, up to 20–22px in the
banner and onboarding.

**Glyph set** (semantic name → Phosphor Bold / Lucide):

| Semantic | Phosphor Bold | Lucide |
|---|---|---|
| pause | `pause` | `pause` |
| resume | `play` | `play` |
| cancel | `x` | `x` |
| force-start | `arrow-line-up` | `arrow-up-to-line` |
| retry | `arrow-clockwise` | `rotate-cw` |
| retry-with-cookies | `key` | `key-round` |
| reveal-in-Finder | `folder-open` | `folder-open` |
| open-in-browser | `globe` | `globe` |
| remove | `trash` | `trash-2` |
| show-log | `file-text` | `file-text` |
| sort-neutral | `caret-up-down` | `chevrons-up-down` |
| sort-asc | `caret-up` | `chevron-up` |
| sort-desc | `caret-down` | `chevron-down` |
| filter | `funnel` | `funnel` |
| chip-refresh | `arrows-clockwise` | `refresh-cw` |
| columns-menu | `columns-plus-right` | `columns-3` |
| disclosure-collapsed | `caret-right` | `chevron-right` |
| disclosure-expanded | `caret-down` | `chevron-down` |
| copy | `copy` | `copy` |
| open-terminal | `terminal-window` | `square-terminal` |
| step-done | `check` | `check` |
| shield | `shield-check` | `shield-check` |
| warning | `warning` | `triangle-alert` |
| nav-home | `house` | `house` |
| nav-preferences | `gear` | `settings` |
| nav-diagnostics | `stethoscope` | `stethoscope` |

The signature motif (reel / orb) is **not** in this set — it is `MotifView`, a
drawn SwiftUI shape, not a bundled icon.

The `warning` glyph is reused for the Preferences concurrency note (§4.6) — no
new glyph is introduced for it.

---

## 4. Components

### 4.1 App chrome

- **Brand row** — wordmark (motif + name) left; nav right (`Home · Preferences · Diagnostics`) as in-app page links. Active page gets a filled `--panel` background.
- **Health strip** — below the brand row. Small utility-face chips carrying ambient state: `bot-check shield`, `engine` (yt-dlp freshness), `online`, and a `<host> · cooldown m:ss` chip that appears only during a cooldown. Green dot = ok, amber dot = attention.
  - **When a chip is in a bad state, a refresh icon `↻` appears at its right edge.** Clicking it puts the chip in a `checking…` state and runs that chip's fix routine in the background:
    | chip bad state | `↻` runs |
    |---|---|
    | `shield · offline` | restart the POT provider process, re-run its health check |
    | `engine · stale` | `brew upgrade yt-dlp` (or `yt-dlp -U`), re-read the version |
    | `offline` | re-poll `NWPathMonitor` |
    | `engine · missing` (dependency gone) | *not a refresh* — routes back to Onboarding; hard block |
  - On success the chip flips green and the icon disappears. On failure an **error toast** shows the reason and the chip stays in its bad state (icon remains).
  - The `cooldown m:ss` chip is not an error — no refresh icon. Clicking it opens a small popover: why the cooldown happened, when it clears, and a **Retry now** button.
- **Warning banner** — docked to the **bottom** of the window, floating over the table, `left/right: 16`, `bottom: 16`. The table gets bottom padding (≈ 78–82px) so its last row never sits under the banner. Reserved for **engine / host-level** conditions only: cooldown explainer, circuit-breaker open, dependency missing, POT provider down. One sentence + one action button. The theme styles it as a solid warm fill (Tape Deck: `--accent` on `--ink` border; Aurora: `--banner-fill` gradient).

### 4.2 Home

Behavioural contract in spec §5.3. Home is one screen with three states and
four parts (hero field + runway, the Downloads table, the playlist group, the
first-run cards).

#### 4.2.1 States

- **First run, no download ever made:** header + paste field + the **three step
  cards** ("Paste a link · Pick a format · Press Grab") fill the body. **No
  Downloads table is rendered** — no headers, filter chips, or Columns button.
  The runway is not shown either (no link yet).
- **After the first Grab:** the step cards are gone permanently. The Downloads
  table (with its toolbar) is rendered from now on. The field sits above it; the
  runway appears when a pasted link resolves and is hidden otherwise.
- **Table emptied later** (user removed every row): the table stays, showing a
  single centered line "No downloads — paste a link above." The step cards do
  **not** return; they are first-run-only.

#### 4.2.2 Paste field + runway  *(the hero)*

The "resolve link & arm Grab" pattern.

- **Field** — full-width card (`--panel`). Rounded on all corners. Holds the
  pasted URL. After a successful probe, an inline status appears at the right
  end: `✓ <title>` (or `✓ "<playlist>" · N items`). On probe failure:
  `--danger` text with the reason, inside the same card below the input.
- **Runway** — **hidden until a pasted link resolves.** When shown, it is a
  **separate full-width card** (`--panel-hi`) below the field, with
  `--sp-3` gap between the two — not a shared border. Rounded on all corners.
  A row of labelled slots:
  - `Link` — filled when the probe resolves to a downloadable item
  - `Type` — `SkinnedSegment` (§4.9) — Video / Audio; seeded from Preferences
  - `Format` — contextual: `SkinnedPicker` (§4.10) quality ladder for video, or
    `SkinnedSegment` `M4A` / `MP3` for audio; seeded from Preferences
  - `Save to` — `SkinnedPicker`: default folder, last-used (if distinct),
    "Choose…" for a new folder. Always seeded — never renders unfilled.
  - *(playlist only)* no extra slot — item selection happens in the picker modal (§4.3)
  - Each slot: hollow dot `○` (`--faint`) when unset, filled dot `●` (`--accent`) when set.
  - The slots use `SkinnedSegment` / `SkinnedPicker`, not the native `Menu`.
- **Grab button** — at the end of the runway, past a divider. **Disabled** (opacity .3, grayscale) until **every** slot is filled: link resolved *and* downloadable, Type, Format, and Save-to all set. Label: `Grab` (single item) / `Grab all N` / `Add N` (after picker). Theme fill: Tape Deck `--go` solid; Aurora `--go-fill` gradient.

#### 4.2.3 Downloads table

One table, newest at top. One **row per video** (a playlist contributes N rows, grouped — §4.2.4).

**Above the table:**
- **Filter chips** — `All · Downloading · Done · Needs attention`. "Needs attention" shows a count badge when > 0.
- **`⊞ Columns` button** (right-aligned) — opens a dropdown of checkboxes to show/hide columns.

**Columns:** 16, one active sort at a time (`↕` cycles asc → desc → off).

| Column | Default | Hideable | Reorderable | Sort | Filter |
|---|---|---|---|---|---|
| Title | ✓ visible | no | yes | yes | yes (text) |
| Status | ✓ visible | yes | yes | yes | yes (checklist) |
| Progress | ✓ visible | yes | yes | yes | — |
| Speed | ✓ visible | yes | yes | yes | — |
| ETA | ✓ visible | yes | yes | yes | — |
| Type | ✓ visible | yes | yes | yes | yes (checklist — Audio / Video) |
| Quality | ✓ visible | yes | yes | yes | yes (checklist — 1080p / 720p / … / m4a / mp3) |
| Size | ✓ visible | yes | yes | yes | — |
| Site | hidden | yes | yes | yes | yes (checklist) |
| Added at | hidden | yes | yes | yes | — |
| Finished at | hidden | yes | yes | yes | — |
| Duration | hidden | yes | yes | yes | — |
| Destination | hidden | yes | yes | yes | yes (checklist) |
| Attempt | hidden | yes | yes | yes | — |
| Client used | hidden | yes | yes | yes | yes (checklist) |
| **Actions** | ✓ visible | **no** | **no (pinned last)** | — | — |

- **Column headers are draggable** to reorder (except Actions, pinned last).
- Column order, visibility, the active sort column + direction, and active filters **persist** as a `ColumnConfig` in `columns.json` (separate from `Preferences`; see spec §4).
- A column whose data source is not yet populated (`Attempt`, `Client used`) shows an em-dash and still sorts; a checklist filter with only a "(none)" option is allowed.
- Nil values always sort **last**, regardless of direction.
- There is **no "Playlist" column** — a playlist's membership is shown by the group header + indented child rows + spine (§4.2.4), not a column.
- No per-row expansion. No detail view. No row selection. Ever — the Actions column is the entire per-row interaction model.

**Cell treatments:**
- *Title* — motif spinner prefix on an actively-downloading row; playlist children indented with the spine connector (§4.2.4).
- *Status* — utility-face pill with a leading state dot: `queued` (`--accent-2`; shows `queued · #N` position), `probing`, `downloading` (`--accent`, glowing dot), `paused`, `waiting for network`, `cooling down` (`--warn`), `saved` (`--dim`), `couldn't verify you` / other failures (`--danger`), `cancelled`. Failure text is the plain-English reason, not an error code.
- *Progress* — thin bar (`--bar-fill`), only on active rows; blank otherwise.
- *Speed*, *ETA* — utility face, `--dim`; blank on non-running rows.
- *Type* — `Audio` / `Video`. *Quality* — the selector (`1080p` … or `m4a` / `mp3`). Both `--dim`.
- *Size* — known total; `--dim`; em-dash until known.
- *Site* — utility face, `--dim`.
- *Actions* — contextual icon buttons (glyphs per §3.4): pause/resume, cancel, force-start, retry, retry-with-cookies, reveal-in-Finder, open-in-browser, remove, show-log (opens the raw log file in the default text editor — no in-app log view). Every button is laid out; one whose action does not apply to the row's state renders disabled.

#### 4.2.4 Playlist group in the table

- **Group header row** — spans the table above the playlist's videos. Contains: a disclosure caret (collapses/expands the whole group), the playlist name, a rollup (`N items · M done` + a mini progress bar), and group actions (Pause all · Retry failed · Cancel all). Background `--accent-2` at low alpha.
- **Child rows** — the playlist's videos, indented. A single **continuous vertical spine** runs down the left at the indent position. Each child has a short horizontal connector from the spine to its content.
- **Row divider lines between children start *after* the spine** (indented to align with content) — they never cross it, so the spine reads as one unbroken line.
- **Collapsed** — children hidden; the header row remains, showing the rollup only.
- This is a grouping row, not a detail view. Nothing expands per video.

### 4.3 Playlist picker (modal)

Opens automatically when a resolved link is a playlist, **before** any rows are added.

- **Header** — "Choose videos to download" + `<playlist> · <site> · by <uploader> · N items`.
- **Tools row** — `Select all` / `Select none` links; a filter-in-playlist text field (right).
- **List** — scrollable, one row per video: checkbox · thumbnail · title (truncates) · duration. Whole row toggles.
- **Footer** — live `M of N selected · ≈ <size>` · `Cancel` · `Add M` (primary; disabled at 0).
- Only checked videos become table rows (as the group in §4.2.4). Unchecked are not added and not remembered.

### 4.4 Toast

- **Bottom-right**, stacked, transient (≈ 4s, auto-dismiss), one line + optional action.
- Fires for: **download successes** (`<title> saved` + `Reveal`) and **health-chip refresh failures** (the reason a `↻` fix did not work).
- **Per-job download failures do not toast.** They surface via the row Status cell + the "Needs attention" filter-chip badge.
- While the app is **backgrounded**, a failure fires a **native macOS notification** (not a toast).
- Engine/host conditions use the bottom banner (§4.1), never a toast.

### 4.5 Onboarding

- Full-window takeover on first run, or whenever `EnvironmentProbe` finds a required dependency missing.
- **Blocks Home** until `yt-dlp` + `ffmpeg` are present.
- Steps as a vertical checklist, each with a state icon (`✓` done / number pending / spinner running):
  1. **Homebrew** — if missing: show the official install command with a `Copy` button and an `Open Terminal` action; re-check on return.
  2. **Downloader + media tools** — `brew install yt-dlp ffmpeg`, run in-app with streamed progress. Required.
  3. **Bot-check shield** — `pipx install bgutil-ytdlp-pot-provider` (+ the yt-dlp POT plugin). Recommended, not blocking.
  4. **Test run** — canary probe of a known-stable video; green-lights Home.
- Plain language: "downloader + media tools", "bot-check shield" — not "yt-dlp", "POT provider" (the exact names still appear in the command shown).

### 4.6 Preferences

- In-app page (nav item). Not a separate macOS Settings window.
- **Fixed window height.** The left rail never scrolls (the window is tall
  enough for every rail item). The right pane scrolls independently.
- **Left rail** — three group captions, each item highlighted when selected:
  - **General:** Downloads · Appearance · Network
  - **YouTube:** Sign-in & cookies
  - **System:** Updates · Logs & privacy · Advanced
- **Right pane** — the selected pane. Two-column rows: `label` (13, `--text`,
  semibold) + optional `helper` (11.5, `--dim`) stacked on the left; control
  right-aligned; a `--hair` divider between rows. A row with no helper renders
  label-only. Pane title 20 / heavy in `--headline` with a rule under it, a
  one-line `--dim` sub above the rule.
- **Stepless panes** (Sign-in & cookies, Updates) render title + sub + one
  plain-language "coming in a later update" line — no rows, no controls.

Rows per pane (control → backing field on `Preferences`, unless noted):

**Downloads** — sub *"Defaults for new downloads. Change any of these per
download on the Home screen."*
| Label | Helper | Control | Backs |
|---|---|---|---|
| Downloads folder | — | folder button `~/Downloads`, no chevron → `NSOpenPanel` | `defaultDownloadFolder` |
| Simultaneous downloads | Automatically reduced if a site rate-limits you. | stepper 1–6 | `maxConcurrentDownloads` |
| Automatic retries | Attempts before the app asks you what to do. | stepper 1–5 | `maxAutoRetries` |
| Media type | — | `SkinnedSegment` — Video / Audio | `defaultMediaType` |
| Video quality | Highest available if the exact height isn't offered. | `SkinnedPicker` — 2160p / 1440p / 1080p / 720p / 480p / Best available | `defaultVideoHeight` (`Int.max` = Best) |
| Audio format | — | `SkinnedSegment` — M4A / MP3 | `defaultAudioFormat` |
| Filename format | — | `SkinnedPicker` — Title / Title – channel / Date – title / Custom… | `filenameTemplate` |
| Clipboard detection | Offer to grab links you copy. | toggle | `detectClipboardLinks` |

The **concurrency note** renders in the "Simultaneous downloads" row's right
column, under the stepper, when the new value is below the live running count:
the warn glyph (§3.4) tinted `--warn` + a `--dim` line
`"<count> still running — the new limit applies as they finish."` It clears when
the running count drops to `≤` the new value, or on relaunch.

**Appearance** — sub *"Pick a look. Theme sets the personality; palette sets the
colours."*
| Label | Helper | Control | Backs |
|---|---|---|---|
| Theme | Aurora is dark and luminous. Tape Deck is warm and light. | `SkinnedSegment` — Aurora / Tape Deck | `theme` |
| Palette | — | 3 split-fill swatches (~38pt, name below; selected has a 2pt `--accent` outline at 2pt offset) for the selected theme | `palette` |

Changing Theme resets `palette` to that theme's default. Both controls apply
live.

**Network** — sub *"Applied to new downloads."*
| Label | Helper | Control | Backs |
|---|---|---|---|
| Proxy server | `http://host:port` — blank for none. | text field | `proxyURL` |
| Force IPv4 | Can help when connections stall. | toggle | `forceIPv4` |
| Speed limit | Applies to each download separately. | stepper KB/s, "Off" at 0 | `speedLimitKBps` |

**Sign-in & cookies** — stepless. Sub *"Sign in to reach private or
age-restricted videos."* Body: *"Cookie sign-in is coming in a later update."*

**Updates** — stepless. Sub *"Check for new versions of the app and the
downloader."* Body: *"Update checks are coming in a later update."*

**Logs & privacy** — sub *"What the app records, and where to find it."*
| Label | Helper | Control | Action |
|---|---|---|---|
| Log files | — | button "Show in Finder" | reveal `~/Library/Logs/MediaGrabber` |
| Verbose logging | More detail for troubleshooting. | toggle | `verboseLogging` |
| Privacy details | — | button "Open" | open the bundled `PRIVACY.md` externally |

**Advanced** — sub *"Reset options. These don't touch your downloaded files."*
| Label | Helper | Control | Action |
|---|---|---|---|
| App data | — | button "Show in Finder" | reveal `~/Library/Application Support/MediaGrabber` |
| Reset columns | Table layout back to default. | button "Reset" | `columnConfig = .default` |
| Reset settings | All preferences back to default. Downloads are untouched. | button "Reset…" (`--danger`), confirmation dialog | `Preferences.resetToDefaults()` |

New `Preferences` fields this section introduces: `detectClipboardLinks: Bool`
(default true), `proxyURL: String?`, `forceIPv4: Bool` (default false),
`speedLimitKBps: Int` (default 0, clamped 0…100000), `lastVideoHeight: Int?`,
`lastMediaType: MediaType?`, `lastAudioFormat: AudioFormat?`.

### 4.7 Diagnostics

- In-app page. One primary button: **Run check**.
- Runs a canary probe, then shows a **report card** — rows of `key : value`, values coloured by verdict (`--accent` ok, `--warn` attention, `--danger` bad): canary result + time, yt-dlp version + freshness, ffmpeg version, bot-check shield health + port, cookie source + readability, detected client, **player_client rotation order** (read-only), active cooldown, network + VPN status.
- **Copy report** — puts a redacted plain-text block on the clipboard (redaction per spec §8.5).
- **Copy diagnostic bundle** — the `DiagnosticBundle` zip (app-log tail + job log + this report). This is the only place it lives (not in Preferences).

---

### 4.8 Confirmation dialog

A reusable modal the app raises a handful of times across its life (duplicate submit, graceful quit, reveal-target-missing, persistence write failure). One host, driven by `AppModel.pendingConfirmation`.

- **Scrim** — the whole window dims behind a `--ground` fill at ~60% alpha; clicks on the scrim do nothing (the choice is explicit).
- **Card** — centered, `max-width` ~420 px, theme card treatment: `--panel-solid` fill, theme border + `cardRadius` + elevation shadow. Padding `s5` all round, `s4` between rows.
- **Layout**, top to bottom:
  - Optional **warning glyph** (§3.4) — shown only when `isDestructive`, tinted `--danger`.
  - **Title** — `displayFont` 15 semibold, `--headline`.
  - **Message** — `bodyFont` 13, `--dim`, wraps freely.
  - Optional **"Don't ask again"** checkbox row — present only when `suppressionKey != nil`; ticking it and confirming persists suppression to `AppStorage` under that key.
  - **Buttons**, right-aligned, `s2` gap:
    - **Cancel** — plain / `--panel`, `controlRadius`. Omitted entirely in notice mode (`cancelTitle == nil`).
    - **Confirm** — filled: `--danger` when `isDestructive`, else `--accent` (theme `--go` gradient on Aurora). `--onAccent` label.
- **Motion** — card scales/fades in over `--dur` / `--ease`; disabled under reduce-motion (appears instantly).
- **Keyboard** — Return confirms; Esc cancels (or dismisses a notice). Initial focus is on **Cancel** for a destructive action, **Confirm** otherwise.
- **VoiceOver** — the card is a modal alert (`.isModal`), focus is trapped inside it, and the message text is read on present.

---

### 4.9 SkinnedSegment

A skinned segmented control, `import SwiftUI` only, generic over the option type.

```swift
struct SkinnedSegment<Option: Hashable>: View {
    init(_ options: [Option], selection: Binding<Option>, label: @escaping (Option) -> String)
}
```

- 2–3 options, all rendered as segments in a `--panel` track with a `--stroke`
  border; the selected segment gets a `--panel-solid` fill. Radius is the
  theme's `chipRadius`.
- **Equal-width segments** within one control (each sized to the widest label).
  The control as a whole **hugs its content** and sits flush to the row's right
  edge. Different controls in one pane may have different total widths; all are
  right-aligned.
- One tap selects. No popover. Left / Right arrow moves selection when focused;
  VoiceOver exposes it as a segmented control with the option labels, the
  selected segment carrying `.isSelected`.

**Used by:** Theme (Appearance), Media type (Downloads + runway), Audio format
(Downloads + runway).

### 4.10 SkinnedPicker

A skinned dropdown. **It is a popover, not a modal** — picking one value from a
short list is a lightweight, anchored interaction.

```swift
struct SkinnedPickerRow<Option: Hashable>: Identifiable {
    var id: Option
    var title: String
    var subtitle: String?   // nil -> single-line row
}

struct SkinnedPicker<Option: Hashable>: View {
    init(caption: String,
         rows: [SkinnedPickerRow<Option>],
         selection: Binding<Option>,
         triggerLabel: String? = nil)   // defaults to the selected row's title
}
```

- **Trigger** — a button showing the current selection's label + a chevron,
  `--panel` fill, `--stroke` border, theme `controlRadius`. Only as wide as its
  own label.
- **Popover** — opens below the trigger (flips above if no room). `--panel-solid`
  fill, theme border + `cardRadius` + elevation matching the confirmation-dialog
  card (glow on Aurora, hard offset shadow on Tape Deck).
  - **Width** — sized to the picker's widest row (caption / label / subtitle),
    clamped `[trigger width … 340pt]`. No single global width.
  - **Caption header** — a `--faint` uppercase label naming what is being
    chosen, with a hairline `--hair` rule under it.
  - **Rows** — label; optional second-line **subtitle** in `--dim` (`nil` →
    single-line row); a checkmark (`--accent`) on the selected row; hover /
    arrow-key highlight uses a translucent accent wash. **No row icons.**
- Keyboard: Return / Space opens; Up / Down move the highlight; Return selects;
  Esc closes without changing. VoiceOver: a pop-up button; the selected row is
  announced.

**Used by:** Video quality (Downloads + runway), Filename format (Downloads),
Save to (runway).

---

## 5. Palette token sets

Every palette defines the full set. Names are stable across palettes; only
values change. `--on-accent` is the text colour that sits on a solid `--accent`
or `--go` fill.

### 5.1 Token list

```
--ground        app window backdrop (behind the card)
--panel-solid   main body / card fill
--panel         raised small surfaces (chips, selects, inputs) — may be translucent
--panel-hi      slightly stronger raised surface
--stroke        structural border
--hair          table row rule / faint divider
--text          primary text
--dim           secondary text
--faint         tertiary / placeholder
--headline      headline text (often = --text or a touch brighter)
--on-accent     text on a solid accent fill
--accent        primary accent / "downloading" / kicker
--accent-2      secondary accent / "queued" / links / playlist group
--warn          cooldown / attention
--danger        failure / error
--go            Go button fill (Tape Deck: solid; Aurora: use --go-fill)
--go-fill       Go button gradient (Aurora)
--orb           conic-gradient motif (Aurora)
--bar-fill      progress bar fill
--banner-fill   warning banner fill
--glow-a        glow inner colour (Aurora elevation)
--glow-b        glow outer colour (Aurora elevation)
```

### 5.2 Tape Deck palettes (light)

Shared: `--ground` is a warm off-white a shade darker than `--surface`
(`--panel-solid`). `--on-accent` = `--ink`. Elevation = hard shadow, no glow
tokens used.

`--warn` is a dark amber (`#9C5A00` / `#9A6410` / `#8E6318`) chosen to hit WCAG
AA for normal text on each palette's `--panel-solid` — it is used as text and as
the glyph tint (concurrency note §4.6, cooldown copy). `--go` keeps its lighter
amber (it is only ever a fill behind `--on-accent`). Aurora `--warn` is
unchanged.

**Tape Deck / Teal & Rust**  *(default for this theme)*
| token | value |
|---|---|
| --ground | `#F3E9D8` |
| --panel-solid (surface) | `#FBF4E6` |
| --panel | `#F3E9D8` |
| --stroke / --ink | `#2B2118` |
| --hair | `rgba(43,33,24,.18)` |
| --text | `#2B2118` |
| --dim | `#8A7A60` |
| --brand (header) | `#0E5C57` |
| --accent | `#D2601A` |
| --accent-2 | `#0E5C57` |
| --warn | `#9C5A00` |
| --danger | `#B4472A` |
| --go | `#E4A11B` |
| --bar-fill | `#D2601A` |
| --banner-fill | `#D2601A` |
| status: downloading / saved / fail / cooldown / queued | `#CFE3E1` / `#D9E8C8` / `#F3D2C3` / `#F6E2B8` / `#FBF4E6` |

**Tape Deck / Plum & Blush**
| token | value |
|---|---|
| --ground | `#EFE9E9` |
| --panel-solid (surface) | `#FBF5F5` |
| --panel | `#EFE9E9` |
| --stroke / --ink | `#281E26` |
| --hair | `rgba(40,30,38,.18)` |
| --text | `#281E26` |
| --dim | `#8B8088` |
| --brand (header) | `#5A2E52` |
| --accent | `#E98C89` |
| --accent-2 | `#5A2E52` |
| --warn | `#9A6410` |
| --danger | `#C25B57` |
| --go | `#E8B24A` |
| --bar-fill | `#E98C89` |
| --banner-fill | `#E98C89` |
| status: downloading / saved / fail / cooldown / queued | `#E1DCEC` / `#D8E6D0` / `#F4D6D6` / `#F3E3C0` / `#FBF5F5` |

*Note: with Blush as `--accent`, warning/cooldown reads softer. Confirmed acceptable in review.*

**Tape Deck / Navy & Aqua**
| token | value |
|---|---|
| --ground | `#E7E9E7` |
| --panel-solid (surface) | `#F5F6F3` |
| --panel | `#E7E9E7` |
| --stroke / --ink | `#1B222A` |
| --hair | `rgba(27,34,42,.18)` |
| --text | `#1B222A` |
| --dim | `#7C838A` |
| --brand (header) | `#1F3350` |
| --accent | `#2FA69A` |
| --accent-2 | `#1F3350` |
| --warn | `#8E6318` |
| --danger | `#D9694C` |
| --go | `#F2B12E` |
| --bar-fill | `#2FA69A` |
| --banner-fill | `#2FA69A` |
| status: downloading / saved / fail / cooldown / queued | `#D6E6E3` / `#D8E6D0` / `#F3D8CC` / `#F6E6B6` / `#F5F6F3` |

### 5.3 Aurora palettes (dark)

Shared: `--panel` = `rgba(255,255,255,.05)`, `--panel-hi` =
`rgba(255,255,255,.08)`, `--hair` = `rgba(255,255,255,.06)`, `--on-accent` =
`#07080B`. Elevation = glow.

**Aurora / Mint & Iris**  *(app default)*
| token | value |
|---|---|
| --ground | `#0C1013` |
| --panel-solid | `#0E1117` |
| --stroke | `rgba(255,255,255,.12)` |
| --text | `#EDF0F5` |
| --dim | `#9AA3B2` |
| --faint | `#6B7480` |
| --headline | `#F4F6FA` |
| --accent | `#5EF2C8` |
| --accent-2 | `#8B7BFF` |
| --warn | `#FFC24B` |
| --danger | `#FF7A6B` |
| --go-fill | `linear-gradient(135deg,#5EF2C8,#8B7BFF)` |
| --orb | `conic-gradient(from 0deg,#5EF2C8,#8B7BFF,#FF7A6B,#5EF2C8)` |
| --bar-fill | `linear-gradient(90deg,#5EF2C8,#8B7BFF)` |
| --banner-fill | `linear-gradient(90deg,#FF7A6B,#FFC24B)` |
| --glow-a / --glow-b | `rgba(94,242,200,.14)` / `rgba(139,123,255,.16)` |

**Aurora / Lime & Forest**
| token | value |
|---|---|
| --ground | `#0A0F0C` |
| --panel-solid | `#0C1210` |
| --stroke | `rgba(190,255,210,.13)` |
| --text | `#E9F2EC` |
| --dim | `#93A99C` |
| --faint | `#5F7268` |
| --headline | `#F2F8F3` |
| --accent | `#B6F04A` |
| --accent-2 | `#4ED6A0` |
| --warn | `#F2C14E` |
| --danger | `#FF6F6F` |
| --go-fill | `linear-gradient(135deg,#B6F04A,#4ED6A0)` |
| --orb | `conic-gradient(from 0deg,#B6F04A,#4ED6A0,#F2C14E,#B6F04A)` |
| --bar-fill | `linear-gradient(90deg,#B6F04A,#4ED6A0)` |
| --banner-fill | `linear-gradient(90deg,#FF6F6F,#F2C14E)` |
| --glow-a / --glow-b | `rgba(182,240,74,.16)` / `rgba(78,214,160,.14)` |

**Aurora / Magenta & Violet**
| token | value |
|---|---|
| --ground | `#100C14` |
| --panel-solid | `#120E16` |
| --stroke | `rgba(230,190,255,.14)` |
| --text | `#F1EAF5` |
| --dim | `#A996B5` |
| --faint | `#7A6B85` |
| --headline | `#F7F2FA` |
| --accent | `#F25C9E` |
| --accent-2 | `#9B6BFF` |
| --warn | `#FFC24B` |
| --danger | `#FF6B6B` |
| --go-fill | `linear-gradient(135deg,#F25C9E,#9B6BFF)` |
| --orb | `conic-gradient(from 0deg,#F25C9E,#9B6BFF,#5ED6E8,#F25C9E)` |
| --bar-fill | `linear-gradient(90deg,#F25C9E,#9B6BFF)` |
| --banner-fill | `linear-gradient(90deg,#FF6B6B,#FFC24B)` |
| --glow-a / --glow-b | `rgba(242,92,158,.16)` / `rgba(155,107,255,.16)` |

---

## 6. Implementation notes

- SwiftUI: express palettes as a `Palette` struct of `Color`s selected by
  `@AppStorage` theme + palette keys; themes differ in more than colour
  (fonts, corner radii, elevation modifier) so model a `Theme` protocol/enum
  with those as properties, not just a colour set.
- The signature motif (reel / orb) is one small reusable view driven by an
  `isActive` flag; honour `accessibilityReduceMotion`.
- Quality floor: full keyboard navigation, visible focus rings, VoiceOver
  labels on every icon button, `prefers-reduced-motion` respected, window
  usable down to a narrow width (table scrolls horizontally inside its own
  container; the page never scrolls sideways).
- Column state (order, visibility, sort, filters) persists as `ColumnConfig`
  in `columns.json` via `Persistence` (the same mechanism as queue/history),
  keyed independently of both `Preferences` and window state.
