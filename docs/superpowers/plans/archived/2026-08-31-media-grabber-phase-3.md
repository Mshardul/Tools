# Preferences Screen (Phase 3) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build the in-app 7-pane Preferences page over the `Preferences` model, the two reusable skinned form controls (`SkinnedSegment`, `SkinnedPicker`) that also replace the native `Menu` dropdowns on the Home runway, the Network `yt-dlp` flag wiring, and the pre-release vocabulary sweep (`Skin` → `Theme`, `Preferences` field renames).

**Architecture:** `PreferencesView` is a plain SwiftUI page in the App target, selected by `AppModel.page`, reading/writing the `@Observable Preferences` model directly — every consumer (runway, engine `cap`, `Theme` / `Palette` resolution) already binds that model live, so an edit re-themes and re-defaults the app with no extra plumbing. One file per pane. `PrefRow` is the shared field primitive; panes are declarative lists of rows. The two controls `import SwiftUI` only, generic over the option type, no `GrabberKit`. `GlobalDownloadOptions` is a new value type in `GrabberKit` beside `YtDlpArguments`; the engine reads it off `preferences` at spawn time.

**Tech Stack:** Swift 6, SwiftUI, `@Observable`, Tuist project, XCTest, `UserDefaults`-backed model, `NSOpenPanel` / `NSWorkspace` for folder actions.

**Spec:** `docs/superpowers/specs/archived/2026-08-31-media-grabber-phase-3.md` (repo-root relative; parent design `docs/superpowers/specs/2026-08-28-youtube-downloader-mac-design.md` §12.1). The maintained mockup is `apps/media-grabber/docs/mockups/screens.html` — built as the first task, it is the visual source of truth for every later task.

## Global Constraints

- **Deployment target macOS 14.** `Synchronization.Mutex` needs macOS 15 — banned. `NSLock.lock()/.unlock()` banned in async contexts (use the `os_unfair_lock`-backed `LockedBox` pattern).
- **Comments: one line, or zero.** Only to explain *why*, only when type/function names don't already carry it. No `///` doc comments. No stacked `//` blocks. A wrapped comment is never acceptable. `// MARK:` is fine.
- **No phase / ticket / epic reference anywhere in code OR in shipped UI copy.** Not in comments, not in strings, not in placeholder-pane copy, not in `Info.plist`. The spec and this plan are the only place phase numbers live. `screens.html` is a meta file — phase references are allowed there, minimally.
- **`swiftformat --lint` + `swiftlint --strict` must be clean.** Do not inline a multi-line `if` condition (`||` / `,`) — extract a named predicate function. `swiftformat` promotes a `//` directly above a declaration to `///` unless `docComments` is disabled (it is — keep it).
- **`ProcessRunner` is the ONLY place `Foundation.Process` is touched. `DownloadEngine` is the ONLY component that spawns download processes.**
- Two targets: `GrabberKit` (no SwiftUI) and `MediaGrabber` (App, SwiftUI over it). `SkinnedSegment` / `SkinnedPicker` / `PreferencesView` / panes are App-target. `GlobalDownloadOptions`, `MediaType`, `AudioFormat`, `ThemeKind`, and the `Preferences` changes are `GrabberKit`.
- After adding/removing/renaming files: `mise exec -- tuist generate --no-open`.
- Test command: `xcodebuild -workspace MediaGrabber.xcworkspace -scheme MediaGrabber-Workspace -destination 'platform=macOS' test`. Single suite: append `-only-testing:GrabberKitTests/<Suite>` or `-only-testing:AppUnitTests/<Suite>`. Do NOT use `tuist test` when debugging (hides compiler errors).
- Lint: `mise exec -- swiftformat --lint .` and `mise exec -- swiftlint lint --strict`. Run from `apps/media-grabber/`.
- **"Best available" video quality is stored as `Int.max`** in `defaultVideoHeight` / `lastVideoHeight`. `YtDlpArguments` needs no special case. `defaultVideoHeight` default stays `1080`.
- Quality ladder everywhere (Preferences + runway): `2160 / 1440 / 1080 / 720 / 480 / Best available`. **Drop `360`** (currently in `RunwayView.heights`).
- `speedLimitKBps` is a **non-optional `Int`, default `0`**; `0` = no limit; clamp `0…100000` on set.
- Concurrency stepper range is **1–6** (the model clamps `1…6`).
- Panes a later phase fills (Sign-in & cookies, Updates) ship as **stepless** panes — title + sub + one plain-language "coming in a later update" line, no phase number. No `Preferences` field, `YtDlpArguments` wiring, or control introduced here is a shape a later phase must replace (parent §12 scoping rule).

---

## File Structure

**New — App target:**

| File | Responsibility |
|---|---|
| `Sources/App/Controls/SkinnedSegment.swift` | Skinned 2–3-option segmented control. Equal-width segments, control hugs content, flush right. |
| `Sources/App/Controls/SkinnedPicker.swift` | Skinned trigger button + popover list (NOT a modal). Content-sized popover width, clamped `[trigger … 340pt]`. |
| `Sources/App/Preferences/PreferencesView.swift` | The page: left rail + selected-pane switch. Holds `@State selectedPane`. |
| `Sources/App/Preferences/PreferencesPane.swift` | `enum PreferencesPane`: cases, titles, subs, rail group; deep-link target. `enum PreferencesRailGroup`. |
| `Sources/App/Preferences/PrefRow.swift` | Shared `label + helper` / `control` row + `PrefPaneHeader` + `PrefSteplessPane`. |
| `Sources/App/Preferences/FileNamingPreset.swift` | `enum FileNamingPreset` (not persisted): preset ↔ `filenameTemplate` string mapping. |
| `Sources/App/Preferences/ConcurrencyNote.swift` | `shouldShowConcurrencyNote(newValue:runningCount:) -> Bool` pure function + the inline note view. |
| `Sources/App/Preferences/Panes/DownloadsPane.swift` | Downloads pane rows. |
| `Sources/App/Preferences/Panes/AppearancePane.swift` | Appearance pane rows + palette swatch view. |
| `Sources/App/Preferences/Panes/NetworkPane.swift` | Network pane rows. |
| `Sources/App/Preferences/Panes/SignInCookiesPane.swift` | Stepless. |
| `Sources/App/Preferences/Panes/UpdatesPane.swift` | Stepless. |
| `Sources/App/Preferences/Panes/LogsPrivacyPane.swift` | Logs & privacy pane rows. |
| `Sources/App/Preferences/Panes/AdvancedPane.swift` | Advanced pane rows. |
| `Sources/App/Home/RunwaySeed.swift` | `RunwaySeed` struct + `runwaySeed(from:)` pure resolver. |

**New — GrabberKit:**

| File | Responsibility |
|---|---|
| `Sources/GrabberKit/Download/GlobalDownloadOptions.swift` | `struct GlobalDownloadOptions: Sendable, Equatable` — proxy / IPv4 / speed limit. |
| `Sources/GrabberKit/Model/MediaType.swift` | `public enum MediaType: String, Codable, Sendable, CaseIterable { case video, audio }` (or add to `Preferences.swift` — see Task 3). |

**Renamed files:**

| Old | New |
|---|---|
| `Sources/App/Theme/Skin.swift` | `Sources/App/Theme/Theme.swift` |
| `Sources/App/Theme/SkinEnvironment.swift` | `Sources/App/Theme/ThemeEnvironment.swift` |

**Modified (rename sweep — Tasks 2–4):** `Sources/GrabberKit/Model/Preferences.swift`, `Sources/GrabberKit/Download/DownloadRequest.swift`, `Sources/GrabberKit/Download/YtDlpArguments.swift`, `Sources/GrabberKit/Logging/JobLog.swift`, `Sources/App/AppModel.swift`, `Sources/App/MainWindow.swift`, `Sources/App/MediaGrabberApp.swift`, `Sources/App/ConfirmationDialog.swift`, `Sources/App/Home/HomeView.swift`, `Sources/App/Home/RunwayView.swift`, `Sources/App/Rows/RequestBuilder.swift`, every file under `Sources/App/Theme/`, `Sources/App/Table/`, `Sources/App/Chrome/`, `Sources/App/Onboarding/` that reads `theme.skin.*`, and tests: `ThemeTests`, `ConfirmationTests`, `PreferencesTests`, `RequestBuilderTests`, `AppModelTests`, `PersistenceTests`, `DownloadRequestTests`, `YtDlpArgumentsTests`, `ValueTypesTests`.

**Modified (feature work — Tasks 5+):** `Sources/GrabberKit/Download/DownloadEngine.swift`, `Sources/App/AppModel.swift`, `Sources/App/MainWindow.swift`, `Sources/App/Home/RunwayView.swift`, `Sources/App/Home/HomeView.swift`, `apps/media-grabber/docs/design-system.md`, `apps/media-grabber/docs/mockups/screens.html`, `apps/media-grabber/Project.swift` (PRIVACY.md resource), parent spec §12.1 / §12.2.

---

## Task 1: Rebuild `screens.html`

The visual source of truth for every later task. Mechanical, single file, no code. Do this first.

**Files:**
- Rewrite: `apps/media-grabber/docs/mockups/screens.html`

**Interfaces:**
- Consumes: spec §8.2 (the build brief), the current `screens.html` (structure to carry forward), `apps/media-grabber/docs/design-system.md` (token values).
- Produces: the rendered target-state mockup. No code symbols.

- [ ] **Step 1: Add the TOC + section scaffold**

At the top of `<body>`, before the switcher: a table of contents with jump links (`<a href="#s1-1">`). Every `.screen` block gets an `id`. Sections and dotted numbers per spec §8.2:

```
§1 Home        1.1 first run · 1.2 link resolved · 1.3 column filter menu open
§2 Onboarding  2.1 first-run setup
§3 Preferences 3.1 Downloads · 3.2 Appearance · 3.3 Network · 3.4 Sign-in & cookies ·
               3.5 Updates · 3.6 Logs & privacy · 3.7 Advanced · 3.8 Control details
§4 Dialogs     4.1 confirmation — destructive · 4.2 confirmation — notice
§5 Playlist    5.1 picker modal · 5.2 group in table
§6 Diagnostics 6.1 report card
```

- [ ] **Step 2: Rename `data-skin` → `data-theme` throughout**

Every `:root[data-skin="…"]` → `:root[data-theme="…"]`; the `<html>` attribute writes and the switcher `<script>` `root.setAttribute("data-skin", …)` → `data-theme`. The switcher's `PALS` map and palette-swatch generation stay; verify each palette button writes the correct `data-palette` value and that the Tape Deck palettes carry the **darkened** `--warn` (see Step 7).

- [ ] **Step 3: Fix the window frame to 980×720, 1:1**

`.app` gets `width: 980px; height: 720px;` (was full-width, unbounded height). Content that overflows scrolls inside its region, not the block. Add thin dashed dimension guides + pt labels on the margins for: window `980 × 720`, Preferences rail width (`200`), pane padding (`s6 = 30`), a row divider, `SkinnedPicker` trigger height, confirmation card `max-width 420`. Keep them subtle (`--accent-2` at ~0.5 opacity, 10px labels) — not a full redline.

- [ ] **Step 4: Update §1 Home screens (1.1–1.3)**

- Rename captions to the new numbering.
- **Runway (1.2, 1.3 where shown):** replace the native `▾` dropdown depiction of Media type / Format / Save-to with the skinned style: Media type = a 2-segment pill (`Video | Audio`); Format = a 2-segment pill for audio (`M4A | MP3`) when audio, or a `SkinnedPicker` trigger (`1080p ▾`) when video; Save-to = a `SkinnedPicker` trigger showing the folder name. Show 1.2 as video (picker for quality), and ensure the quality options in any depicted popover are `2160p / 1440p / 1080p / 720p / 480p / Best available` — **no 360p**.
- **Save-to (1.2):** the step is always filled (never `wait` / `Choose…` as the value) — show it seeded to `Downloads`. If a Save-to popover is depicted, rows are: `Downloads` (subtitle `/Users/you/Downloads`), then `Choose…`. Add a last-used row only if you depict a distinct last-used folder.
- Keep the future-phase chrome already on 1.2 (cooldown health chip, cooldown banner, success toast). Add a minimal phase tag to the 1.2 caption, e.g. `(cooldown chip + banner and the toast arrive in later phases)`.

- [ ] **Step 5: Rewrite §3 Preferences — one `.app` block per pane**

Replace the single Screen 6 (Downloads + Appearance) with seven blocks, each a full 980×720 window with the brand row + health strip on top and `PreferencesView` filling the body. Rail: three group captions (**General**: Downloads · Appearance · Network — **YouTube**: Sign-in & cookies — **System**: Updates · Logs & privacy · Advanced), the active item highlighted per block, **no scrollbar on the rail**. Right pane: fixed height, `overflow:auto`; show the **Downloads** pane mid-scroll (some rows clipped at the top or bottom) to demonstrate the fixed-window / scrolling-pane split.

Per-pane rows — labels, helpers, and controls exactly per spec §5.1–5.7:

- **3.1 Downloads** — sub *"Defaults for new downloads. Change any of these per download on the Home screen."* Rows: Downloads folder (folder button `~/Downloads`, **no chevron**) · Simultaneous downloads (stepper `2`, range 1–6) · Automatic retries (stepper `3`) · Media type (segment Video|Audio) · Video quality (picker trigger `1080p ▾`) · Audio format (segment M4A|MP3) · Filename format (picker trigger `Title ▾`) · Clipboard detection (toggle on). Helpers per spec (label-only rows: Downloads folder, Media type, Audio format, Filename format).
- **3.2 Appearance** — sub *"Pick a look. Theme sets the personality; palette sets the colours."* Rows: Theme (segment Aurora|Tape Deck) · Palette (3 split-fill swatches ~38pt, name below, selected has a 2pt `--accent` outline at 2pt offset). Helper on Theme only.
- **3.3 Network** — sub *"Applied to new downloads."* Rows: Proxy server (text field, helper `http://host:port` — blank for none.) · Force IPv4 (toggle, helper "Can help when connections stall.") · Speed limit (stepper showing `Off`, helper "Applies to each download separately.").
- **3.4 Sign-in & cookies** — stepless. Sub *"Sign in to reach private or age-restricted videos."* Body line (`--faint`): *"Cookie sign-in is coming in a later update."*
- **3.5 Updates** — stepless. Sub *"Check for new versions of the app and the downloader."* Body line: *"Update checks are coming in a later update."*
- **3.6 Logs & privacy** — sub *"What the app records, and where to find it."* Rows: Log files (button "Show in Finder") · Verbose logging (toggle, helper "More detail for troubleshooting.") · Privacy details (button "Open").
- **3.7 Advanced** — sub *"Reset options. These don't touch your downloaded files."* Rows: App data (button "Show in Finder") · Reset columns (button "Reset", helper "Table layout back to default.") · Reset settings (button "Reset…" in `--danger` style, helper "All preferences back to default. Downloads are untouched.").

- [ ] **Step 6: Add §3.8 Control details**

One block, not a full window — pane-region fragments only, clubbed vertically with small labels:

1. **Concurrency note** — the "Simultaneous downloads" row at expanded height: stepper showing `2`, and under it a `--dim` line with the warn glyph: `⚠ 3 still running — the new limit applies as they finish.`
2. **Custom filename** — the "Filename format" row with the trigger showing `Custom… ▾`, and a monospace text field row revealed below it, pre-filled `%(title)s - %(id)s.%(ext)s`.
3. **Open picker popover** — the "Filename format" `SkinnedPicker` with its popover open: caption header `FILE NAMING`, hairline rule, rows `Title` (checkmark, subtitle `Never Gonna Give You Up.mp4`), `Title – channel` (hover wash, subtitle `Never Gonna Give You Up - Rick Astley.mp4`), `Date – title` (subtitle `2009-10-25 - Never Gonna Give You Up.mp4`), `Custom…`. Popover ≈ 320pt wide; annotate the width.

- [ ] **Step 7: Darken Tape Deck `--warn` in the mockup CSS**

In the `:root[data-theme="tapedeck"][data-palette="…"]` blocks, replace `--warn:#E4A11B` / `#E8B24A` / `#F2B12E` with darker ambers (start from ≈ `#9C5A00` / `#9A6410` / `#8E6318`; verify each hits WCAG AA for normal text on that palette's `--panel-solid` and record the final value). **Leave `--go`** (which currently reuses the same hex) unchanged. Aurora `--warn` unchanged.

- [ ] **Step 8: Add §4 Dialogs**

Two blocks, each a 980×720 window with a dimmed Advanced pane behind a scrim:
- **4.1 destructive** — centered card `max-width 420`, `--panel-solid` fill, theme border + `cardRadius` + elevation. Warn glyph tinted `--danger`, title "Reset settings?", message "All preferences go back to their defaults. Your downloads and table columns aren't affected.", buttons right-aligned: `Cancel` (plain) then `Reset` (`--danger` fill). Initial focus ring on Cancel.
- **4.2 notice** — same card, no glyph, title "Those files were moved", message text, single `OK` button.

- [ ] **Step 9: Carry §5 Playlist and §6 Diagnostics forward**

Move the current Screen 3/4 (playlist picker modal, group in table) to §5.1 / §5.2 and Screen 7 (Diagnostics) to §6.1, renumbered. Caption note on each: `(depiction is refined when this screen's phase is detailed)`. In the playlist runway (§5.1), apply the same skinned-control swap as §1 (it shows a runway).

- [ ] **Step 10: Open it, eyeball every section, both themes**

Open `screens.html` in a browser. Toggle Aurora ↔ Tape Deck and every palette. Confirm: no horizontal body scroll, each `.app` is 980×720, the Preferences rail doesn't scroll, the Downloads pane does, the switcher writes correct `data-theme` / `data-palette`, the darkened Tape Deck `--warn` is legible on cream.

- [ ] **Step 11: Hand off for review**

Report the rebuilt file to the user for review.

---

## Task 2: Rename `Skin` → `Theme` (types + files + env, no behaviour change)

**Files:**
- Rename: `Sources/App/Theme/Skin.swift` → `Theme.swift`; `Sources/App/Theme/SkinEnvironment.swift` → `ThemeEnvironment.swift`
- Modify: `Sources/GrabberKit/Model/Preferences.swift` (`SkinKind` → `ThemeKind`, `skin` → `theme`, key `mg.skin` → `mg.theme`)
- Modify: every file listed in "Modified (rename sweep)" that references `Skin` / `SkinKind` / `ResolvedTheme` / `theme.skin`
- Test: `Tests/AppUnitTests/ThemeTests.swift`, `Tests/GrabberKitTests/PreferencesTests.swift`, `Tests/AppUnitTests/ConfirmationTests.swift`

**Interfaces:**
- Consumes: nothing new.
- Produces:
  - `public enum ThemeKind: String, Codable, Sendable, CaseIterable { case tapeDeck, aurora }` (GrabberKit) — raw values unchanged.
  - `enum Theme` (App, was `enum Skin`) — `init(_ kind: ThemeKind)`, all the radius / font / motif accessors unchanged.
  - `Preferences.theme: ThemeKind` (was `.skin`), `UserDefaults` key `mg.theme`.
  - The `ResolvedTheme` wrapper is **kept for this task** (renamed member only): `ResolvedTheme.skin` → `ResolvedTheme.style` of type `Theme`. Full collapse is Task 4. (Rationale: keeping the wrapper here makes this task a pure rename with a green build gate; Task 4 does the structural change separately.)
  - Every `theme.skin.xxx` call site → `theme.style.xxx`.

- [ ] **Step 1: Update `ThemeTests` for the new names**

```swift
func test_auroraTheme_radii() {
    let theme = Theme(.aurora)
    XCTAssertEqual(theme.windowRadius, 18)
    XCTAssertEqual(theme.cardRadius, 14)
    // … rest unchanged
}
func test_auroraTheme_motifIsOrb() { XCTAssertEqual(Theme(.aurora).motif, .orb) }
func test_defaultEnvironmentTheme_isAuroraMintIris() {
    XCTAssertEqual(EnvironmentValues().theme.palette.accent, Color(hex: "#5EF2C8"))
}
```

Update `PreferencesTests.test_defaults` (`prefs.skin` → `prefs.theme`, expect `.aurora`) and `ConfirmationTests` (any `Skin(` → `Theme(`).

- [ ] **Step 2: Run the tests, verify they fail (compile error)**

Run: `xcodebuild ... test -only-testing:AppUnitTests/ThemeTests`
Expected: FAIL — `Theme` undefined / `prefs.theme` undefined.

- [ ] **Step 3: Rename the GrabberKit type + field**

In `Preferences.swift`: `enum SkinKind` → `enum ThemeKind` (keep `public`, keep raw values, keep `CaseIterable`). `var skin: SkinKind` → `var theme: ThemeKind`, and inside it `forKey: "mg.skin"` → `"mg.theme"`, `SkinKind.init` → `ThemeKind.init`. The comment above `ThemeKind` ("String-raw identity only…") stays one line.

- [ ] **Step 4: Rename the App type + file**

`mv Sources/App/Theme/Skin.swift Sources/App/Theme/Theme.swift`. In it: `enum Skin` → `enum Theme`, `init(_ kind: SkinKind)` → `init(_ kind: ThemeKind)`. `MotifKind` stays.

- [ ] **Step 5: Rename the env file + wrapper member**

`mv Sources/App/Theme/SkinEnvironment.swift Sources/App/Theme/ThemeEnvironment.swift`. In it: `struct ResolvedTheme { let skin: Skin … }` → `{ let style: Theme … }`; `init(skin:palette:)` → `init(style:palette:)`; `init(skinKind:paletteKind:)` → `init(themeKind:paletteKind:)` with `style = Theme(themeKind)`; `static let auroraMintIris = ResolvedTheme(skin: Skin(.aurora), …)` → `(style: Theme(.aurora), …)`. Keep `@Entry var theme: ResolvedTheme`.

- [ ] **Step 6: Sweep every call site**

`theme.skin.` → `theme.style.` across `Sources/App/` (MainWindow, HomeView, RunwayView, ConfirmationDialog, MotifView, ColumnsMenu, DownloadsTable, DownloadRow, WarningBanner, HealthStrip, OnboardingView). `MediaGrabberApp.swift`: `.theme(ResolvedTheme(skinKind: …, paletteKind: …))` → `(themeKind:…, paletteKind:…)`; `prefs.skin` → `prefs.theme`.

- [ ] **Step 7: Regenerate, build, run the full suite**

Run: `mise exec -- tuist generate --no-open`, then `xcodebuild ... build`, then `xcodebuild ... test`.
Expected: builds clean; all tests pass (this is a pure rename — no behaviour change).

- [ ] **Step 8: Lint**

```bash
mise exec -- swiftformat --lint . && mise exec -- swiftlint lint --strict
```

---

## Task 3: Rename `AudioCodec` → `AudioFormat`, promote `KindSelector` → `MediaType`

**Files:**
- Modify: `Sources/GrabberKit/Download/DownloadRequest.swift` (`AudioCodec` → `AudioFormat`, `DownloadKind.audio(codec:)` → `.audio(format:)`)
- Create: `Sources/GrabberKit/Model/MediaType.swift`
- Modify: `Sources/GrabberKit/Model/Preferences.swift` (drop the private `KindSelector`)
- Modify: `Sources/GrabberKit/Download/YtDlpArguments.swift` (`case let .audio(codec:)` → `.audio(format:)`), `Sources/GrabberKit/Logging/JobLog.swift` (`describe` switch)
- Modify: `Sources/App/Home/RunwayView.swift` (delete nested `KindSelector`), `Sources/App/Home/HomeView.swift`, `Sources/App/Rows/RequestBuilder.swift`, `Sources/App/AppModel.swift`
- Test: `Tests/GrabberKitTests/DownloadRequestTests.swift`, `ValueTypesTests.swift`, `YtDlpArgumentsTests.swift`, `PreferencesTests.swift`, `Tests/AppUnitTests/RequestBuilderTests.swift`

**Interfaces:**
- Consumes: nothing new.
- Produces:
  - `public enum AudioFormat: String, Codable, Sendable, CaseIterable { case m4a, mp3 }` (was `AudioCodec`) — raw values unchanged.
  - `public enum MediaType: String, Codable, Sendable, CaseIterable { case video, audio }` (was the `private` `KindSelector` in `Preferences`, and the nested `RunwayView.KindSelector`).
  - `DownloadKind.audio(format: AudioFormat)` (was `.audio(codec: AudioCodec)`). `.video(maxHeight:)` unchanged. `DownloadKind` name kept.

- [ ] **Step 1: Update the tests**

`DownloadRequestTests`, `ValueTypesTests` — `AudioCodec` → `AudioFormat`, `.audio(codec:)` → `.audio(format:)`. `YtDlpArgumentsTests` — same in the `request(kind:)` helper. Add to `ValueTypesTests` (or a new `MediaTypeTests`): `MediaType.allCases == [.video, .audio]`, raw values `"video"` / `"audio"`, `Codable` round-trip.

- [ ] **Step 2: Run, verify fail**

Run: `xcodebuild ... test -only-testing:GrabberKitTests/DownloadRequestTests -only-testing:GrabberKitTests/ValueTypesTests`
Expected: FAIL — `AudioFormat` / `MediaType` undefined.

- [ ] **Step 3: Rename `AudioCodec`, add `MediaType`**

In `DownloadRequest.swift`: `enum AudioCodec` → `enum AudioFormat`; `case audio(codec: AudioCodec)` → `case audio(format: AudioFormat)`. Create `Sources/GrabberKit/Model/MediaType.swift` with the `MediaType` enum. In `Preferences.swift` delete `private enum KindSelector`.

- [ ] **Step 4: Sweep GrabberKit call sites**

`YtDlpArguments.formatSelector` — `case let .audio(codec: codec)` → `case let .audio(format: format)`, `codec.rawValue` → `format.rawValue`. `JobLog.describe` — `case let .audio(codec)` → `case let .audio(format)`, `"audio:\(codec.rawValue)"` → `"audio:\(format.rawValue)"`.

- [ ] **Step 5: Sweep App call sites**

`RunwayView.swift` — delete `enum KindSelector`, all `KindSelector` → `MediaType`, `AudioCodec` → `AudioFormat`, the `formatMenu` audio branch `AudioCodec.allCases` → `AudioFormat.allCases`. `HomeView.swift` — `@State var audioCodec: AudioCodec` → `audioFormat: AudioFormat`, `RunwayView.KindSelector` → `MediaType`, `selectedKind`'s `.audio(codec:)` → `.audio(format:)`. `RequestBuilder.swift` — `container(for:)`'s `if case .video` unchanged; no `codec` ref. `AppModel.swift` — none yet (grab writes are Task 12).

- [ ] **Step 6: Regenerate, run full suite**

Run: `mise exec -- tuist generate --no-open`, `xcodebuild ... test`.
Expected: all pass (pure rename).

- [ ] **Step 7: Lint**

```bash
mise exec -- swiftformat --lint . && mise exec -- swiftlint lint --strict
```

---

## Task 4: Rename `Preferences` fields + `DownloadRequest.outputTemplate`; collapse `ResolvedTheme`

**Files:**
- Modify: `Sources/GrabberKit/Model/Preferences.swift` (7 field renames + `mg.*` keys)
- Modify: `Sources/GrabberKit/Download/DownloadRequest.swift` (`outputTemplate` → `filenameTemplate`), `YtDlpArguments.swift` (`-o` arg), `JobLog.swift` (`describe`)
- Modify: `Sources/App/Theme/ThemeEnvironment.swift` (collapse `ResolvedTheme` → env value is `Theme`)
- Modify: `Sources/App/` — `RequestBuilder.swift`, `HomeView.swift`, `RunwayView.swift`, `AppModel.swift`, `MediaGrabberApp.swift`, every `theme.style.` → `theme.`
- Test: `PreferencesTests`, `RequestBuilderTests`, `AppModelTests`, `PersistenceTests`, `DownloadRequestTests`, `YtDlpArgumentsTests`, `ThemeTests`, `ConfirmationTests`

**Interfaces:**
- Consumes: `Theme`, `ThemeKind`, `MediaType`, `AudioFormat` (Tasks 2–3).
- Produces:
  - `Preferences`: `defaultDownloadFolder`, `lastUsedDownloadFolder`, `defaultVideoHeight`, `defaultAudioFormat`, `filenameTemplate`, `maxAutoRetries`, `defaultMediaType` (now **public**). Keys `mg.defaultDownloadFolder` / `mg.lastUsedDownloadFolder` / `mg.defaultVideoHeight` / `mg.defaultAudioFormat` / `mg.filenameTemplate` / `mg.maxAutoRetries` / `mg.defaultMediaType`. `defaultKind` (computed), `maxConcurrentDownloads`, `verboseLogging`, `palette` unchanged.
  - `DownloadRequest.filenameTemplate` (was `outputTemplate`); the `init` label and default (`"%(title)s.%(ext)s"`) carry over.
  - The `@Entry var theme` environment value is now `Theme` directly. `Theme` gains a stored `palette: PaletteTokens`. `Theme(.aurora)` still works; a second init `Theme(themeKind:paletteKind:)` builds the palette. Call sites: `theme.cardRadius`, `theme.bodyFont(…)`, `theme.palette.accent`.

- [ ] **Step 1: Update every test to the new names**

`PreferencesTests` — `defaultMaxHeight` → `defaultVideoHeight`, `defaultAudioCodec` → `defaultAudioFormat`, `outputTemplate` → `filenameTemplate`, `maxAutoAttempts` → `maxAutoRetries`, `lastUsedDestFolder` → `lastUsedDownloadFolder`, `defaultDestFolder` → `defaultDownloadFolder`. `RequestBuilderTests` / `AppModelTests` — `prefs.lastUsedDestFolder` → `prefs.lastUsedDownloadFolder`, `outputTemplate:` (in `DownloadRequest(...)`) → `filenameTemplate:`. `PersistenceTests` / `DownloadRequestTests` — `outputTemplate` → `filenameTemplate` on `DownloadRequest`. `ThemeTests` — `EnvironmentValues().theme.palette.accent` still valid; `theme.style.xxx` → `theme.xxx` if any test reads it (none currently — `ThemeTests` uses `Theme(.aurora)` directly, fine).

Add a test: old keys don't resolve —

```swift
func test_renamedKeys_oldKeysIgnored() {
    defaults.set(480, forKey: "mg.defaultMaxHeight")   // old key
    XCTAssertEqual(Preferences(defaults: defaults).defaultVideoHeight, 1080)  // new getter, default
}
```

- [ ] **Step 2: Run, verify fail**

Run: `xcodebuild ... test -only-testing:GrabberKitTests/PreferencesTests`
Expected: FAIL — new field names undefined.

- [ ] **Step 3: Rename the `Preferences` fields + keys**

In `Preferences.swift`, rename each `var` and its `forKey:` string per the Interfaces block. `defaultAudioOrVideo` (private) → `defaultMediaType` (public), key `mg.defaultKindSelector` → `mg.defaultMediaType`, type `KindSelector` → `MediaType`. `defaultKind` computed prop reads `defaultMediaType` / `defaultVideoHeight` / `defaultAudioFormat` — update its body. The helper functions (`intValue`, `url`, `setURL`) prepend `mg.` already — pass the bare new name.

- [ ] **Step 4: Rename `DownloadRequest.outputTemplate`**

`DownloadRequest.swift` — `var outputTemplate` → `var filenameTemplate`, `init(… outputTemplate: String = …)` → `filenameTemplate:`. `YtDlpArguments.build` — `["-o", request.outputTemplate]` → `request.filenameTemplate`. `JobLog.describe` — `template=\(request.outputTemplate)` → `request.filenameTemplate`.

- [ ] **Step 5: Collapse `ResolvedTheme`**

In `ThemeEnvironment.swift`: delete `struct ResolvedTheme`. Move `palette` onto `Theme` as a stored `let palette: PaletteTokens` (in `Theme.swift`). Add `Theme(themeKind: ThemeKind, paletteKind: PaletteKind)` → sets the enum case + `palette = MediaGrabber.palette(for: paletteKind)`. The bare `Theme(.aurora)` init stays for tests — give it `palette = .auroraMintIris` as a default, or make the palette-less init test-only. `@Entry var theme: Theme = Theme(themeKind: .aurora, paletteKind: .auroraMintIris)`. `func theme(_:)` view modifier takes a `Theme`.

- [ ] **Step 6: Sweep `theme.style.` → `theme.` and `prefs.*` renames in App**

Every `theme.style.xxx` → `theme.xxx`. `MediaGrabberApp.swift` — `.theme(ResolvedTheme(themeKind: prefs.theme, paletteKind: prefs.palette))` → `.theme(Theme(themeKind: prefs.theme, paletteKind: prefs.palette))`. `HomeView.seedFromPrefs` — `prefs.defaultKind` still works (computed); `prefs.lastUsedDestFolder` → `prefs.lastUsedDownloadFolder`. `RunwayView` bindings unchanged in name. `RequestBuilder` — `prefs.lastUsedDestFolder` → `prefs.lastUsedDownloadFolder`, `prefs.outputTemplate` → `prefs.filenameTemplate`.

- [ ] **Step 7: Regenerate, build, full suite**

Run: `mise exec -- tuist generate --no-open`, `xcodebuild ... build`, `xcodebuild ... test`.
Expected: all pass.

- [ ] **Step 8: Lint**

```bash
mise exec -- swiftformat --lint . && mise exec -- swiftlint lint --strict
```

---

## Task 5: `Preferences` — new fields

**Files:**
- Modify: `Sources/GrabberKit/Model/Preferences.swift`
- Test: `Tests/GrabberKitTests/PreferencesTests.swift`

**Interfaces:**
- Consumes: `MediaType`, `AudioFormat` (Task 3).
- Produces:
  - `Preferences.detectClipboardLinks: Bool` (default `true`)
  - `Preferences.proxyURL: String?` (trimmed; empty → `nil`)
  - `Preferences.forceIPv4: Bool` (default `false`)
  - `Preferences.speedLimitKBps: Int` (default `0`; clamp `0…100000` on set)
  - `Preferences.lastVideoHeight: Int?` (nil default; `Int.max` valid)
  - `Preferences.lastMediaType: MediaType?` (nil default)
  - `Preferences.lastAudioFormat: AudioFormat?` (nil default)

- [ ] **Step 1: Write failing tests**

```swift
func test_newFieldDefaults() {
    let p = Preferences(defaults: defaults)
    XCTAssertTrue(p.detectClipboardLinks)
    XCTAssertNil(p.proxyURL)
    XCTAssertFalse(p.forceIPv4)
    XCTAssertEqual(p.speedLimitKBps, 0)
    XCTAssertNil(p.lastVideoHeight)
    XCTAssertNil(p.lastMediaType)
    XCTAssertNil(p.lastAudioFormat)
}
func test_proxyURL_trimAndEmptyToNil() {
    let p = Preferences(defaults: defaults)
    p.proxyURL = "  "
    XCTAssertNil(Preferences(defaults: defaults).proxyURL)
    p.proxyURL = " http://h:1 "
    XCTAssertEqual(Preferences(defaults: defaults).proxyURL, "http://h:1")
}
func test_speedLimitKBps_clamp() {
    let p = Preferences(defaults: defaults)
    p.speedLimitKBps = -5
    XCTAssertEqual(p.speedLimitKBps, 0)
    p.speedLimitKBps = 999_999
    XCTAssertEqual(p.speedLimitKBps, 100_000)
}
func test_lastSelected_roundTripIncludingIntMax() {
    let p = Preferences(defaults: defaults)
    p.lastVideoHeight = .max
    p.lastMediaType = .audio
    p.lastAudioFormat = .mp3
    let r = Preferences(defaults: defaults)
    XCTAssertEqual(r.lastVideoHeight, .max)
    XCTAssertEqual(r.lastMediaType, .audio)
    XCTAssertEqual(r.lastAudioFormat, .mp3)
}
```

- [ ] **Step 2: Run, verify fail**

Run: `xcodebuild ... test -only-testing:GrabberKitTests/PreferencesTests`
Expected: FAIL — fields undefined.

- [ ] **Step 3: Implement**

```swift
// MARK: - Clipboard
public var detectClipboardLinks: Bool {
    get { defaults.object(forKey: "mg.detectClipboardLinks") == nil ? true : defaults.bool(forKey: "mg.detectClipboardLinks") }
    set { defaults.set(newValue, forKey: "mg.detectClipboardLinks") }
}

// MARK: - Network
public var proxyURL: String? {
    get { defaults.string(forKey: "mg.proxyURL") }
    set {
        let trimmed = newValue?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if trimmed.isEmpty { defaults.removeObject(forKey: "mg.proxyURL") }
        else { defaults.set(trimmed, forKey: "mg.proxyURL") }
    }
}
public var forceIPv4: Bool {
    get { defaults.bool(forKey: "mg.forceIPv4") }
    set { defaults.set(newValue, forKey: "mg.forceIPv4") }
}
public var speedLimitKBps: Int {
    get { intValue(forKey: "speedLimitKBps", default: 0) }
    set { defaults.set(min(100_000, max(0, newValue)), forKey: "mg.speedLimitKBps") }
}

// MARK: - Runway last-selected
public var lastVideoHeight: Int? {
    get { defaults.object(forKey: "mg.lastVideoHeight") == nil ? nil : defaults.integer(forKey: "mg.lastVideoHeight") }
    set {
        guard let v = newValue else { defaults.removeObject(forKey: "mg.lastVideoHeight"); return }
        defaults.set(v, forKey: "mg.lastVideoHeight")
    }
}
public var lastMediaType: MediaType? {
    get { defaults.string(forKey: "mg.lastMediaType").flatMap(MediaType.init) }
    set {
        guard let v = newValue else { defaults.removeObject(forKey: "mg.lastMediaType"); return }
        defaults.set(v.rawValue, forKey: "mg.lastMediaType")
    }
}
public var lastAudioFormat: AudioFormat? {
    get { defaults.string(forKey: "mg.lastAudioFormat").flatMap(AudioFormat.init) }
    set {
        guard let v = newValue else { defaults.removeObject(forKey: "mg.lastAudioFormat"); return }
        defaults.set(v.rawValue, forKey: "mg.lastAudioFormat")
    }
}
```

- [ ] **Step 4: Run, verify pass**

Run: `xcodebuild ... test -only-testing:GrabberKitTests/PreferencesTests`
Expected: PASS.

- [ ] **Step 5: Lint**

```bash
mise exec -- swiftformat --lint . && mise exec -- swiftlint lint --strict
```

---

## Task 6: `Preferences.resetToDefaults()`

**Files:**
- Modify: `Sources/GrabberKit/Model/Preferences.swift`
- Test: `Tests/GrabberKitTests/PreferencesTests.swift`

**Interfaces:**
- Consumes: nothing new.
- Produces: `Preferences.resetToDefaults()` — removes every `mg.*` key the model owns. Getters fall back to defaults.

- [ ] **Step 1: Write the failing test**

```swift
func test_resetToDefaults_restoresEveryField() {
    let p = Preferences(defaults: defaults)
    p.defaultVideoHeight = 480
    p.theme = .tapeDeck
    p.palette = .tapeDeckC
    p.forceIPv4 = true
    p.proxyURL = "http://h:1"
    p.speedLimitKBps = 500
    p.detectClipboardLinks = false
    p.maxConcurrentDownloads = 6
    p.filenameTemplate = "%(id)s.%(ext)s"
    p.lastMediaType = .audio
    p.resetToDefaults()
    XCTAssertEqual(p.defaultVideoHeight, 1080)
    XCTAssertEqual(p.theme, .aurora)
    XCTAssertEqual(p.palette, .auroraMintIris)
    XCTAssertFalse(p.forceIPv4)
    XCTAssertNil(p.proxyURL)
    XCTAssertEqual(p.speedLimitKBps, 0)
    XCTAssertTrue(p.detectClipboardLinks)
    XCTAssertEqual(p.maxConcurrentDownloads, 3)
    XCTAssertEqual(p.filenameTemplate, "%(title)s.%(ext)s")
    XCTAssertNil(p.lastMediaType)
}
```

- [ ] **Step 2: Run, verify fail**

Run: `xcodebuild ... test -only-testing:GrabberKitTests/PreferencesTests`
Expected: FAIL — `resetToDefaults` undefined.

- [ ] **Step 3: Implement**

```swift
public func resetToDefaults() {
    for key in Self.ownedKeys { defaults.removeObject(forKey: key) }
}

private static let ownedKeys = [
    "mg.defaultDownloadFolder", "mg.lastUsedDownloadFolder", "mg.defaultMediaType",
    "mg.defaultVideoHeight", "mg.defaultAudioFormat", "mg.filenameTemplate",
    "mg.maxAutoRetries", "mg.maxConcurrentDownloads", "mg.verboseLogging",
    "mg.theme", "mg.palette", "mg.detectClipboardLinks", "mg.proxyURL",
    "mg.forceIPv4", "mg.speedLimitKBps", "mg.lastVideoHeight",
    "mg.lastMediaType", "mg.lastAudioFormat",
]
```

Cross-check this list against every `forKey:` literal in the file — it must be exhaustive.

- [ ] **Step 4: Run, verify pass**

Run: `xcodebuild ... test -only-testing:GrabberKitTests/PreferencesTests`
Expected: PASS.

- [ ] **Step 5: Lint**

```bash
mise exec -- swiftformat --lint . && mise exec -- swiftlint lint --strict
```

---

## Task 7: `GlobalDownloadOptions` + `YtDlpArguments` options

**Files:**
- Create: `Sources/GrabberKit/Download/GlobalDownloadOptions.swift`
- Modify: `Sources/GrabberKit/Download/YtDlpArguments.swift`
- Test: `Tests/GrabberKitTests/GlobalDownloadOptionsTests.swift` (new), `Tests/GrabberKitTests/YtDlpArgumentsTests.swift`

**Interfaces:**
- Consumes: `DownloadRequest`.
- Produces:

```swift
public struct GlobalDownloadOptions: Sendable, Equatable {
    public var proxyURL: String?
    public var forceIPv4: Bool
    public var speedLimitKBps: Int
    public init(proxyURL: String?, forceIPv4: Bool, speedLimitKBps: Int)
    public static let none: GlobalDownloadOptions   // nil / false / 0
}

public static func build(for request: DownloadRequest, options: GlobalDownloadOptions = .none) -> [String]
public static func redacted(for request: DownloadRequest, options: GlobalDownloadOptions = .none) -> [String]
```

Flag rules: `--proxy <url>` when `proxyURL` non-nil non-empty · `-4` when `forceIPv4` · `--limit-rate <N>K` when `speedLimitKBps > 0` · `redacted` masks `user:pass@` → `***@` in the proxy URL, identical to `build` otherwise.

- [ ] **Step 1: Write failing tests**

`GlobalDownloadOptionsTests.swift`:

```swift
@testable import GrabberKit
import XCTest

final class GlobalDownloadOptionsTests: XCTestCase {
    func test_none() {
        let n = GlobalDownloadOptions.none
        XCTAssertNil(n.proxyURL); XCTAssertFalse(n.forceIPv4); XCTAssertEqual(n.speedLimitKBps, 0)
    }
    func test_equatable() {
        XCTAssertEqual(GlobalDownloadOptions.none, GlobalDownloadOptions(proxyURL: nil, forceIPv4: false, speedLimitKBps: 0))
    }
}
```

Add to `YtDlpArgumentsTests`:

```swift
func test_options_none_noGlobalFlags() {
    let a = YtDlpArguments.build(for: request(kind: .video(maxHeight: 1080)))
    XCTAssertFalse(a.contains("--proxy")); XCTAssertFalse(a.contains("-4")); XCTAssertFalse(a.contains("--limit-rate"))
}
func test_options_proxy() {
    let o = GlobalDownloadOptions(proxyURL: "http://host:8080", forceIPv4: false, speedLimitKBps: 0)
    XCTAssertTrue(hasSubsequence(YtDlpArguments.build(for: request(kind: .audio(format: .m4a)), options: o), ["--proxy", "http://host:8080"]))
}
func test_options_forceIPv4() {
    let o = GlobalDownloadOptions(proxyURL: nil, forceIPv4: true, speedLimitKBps: 0)
    XCTAssertTrue(YtDlpArguments.build(for: request(kind: .audio(format: .m4a)), options: o).contains("-4"))
}
func test_options_speedLimit() {
    let o = GlobalDownloadOptions(proxyURL: nil, forceIPv4: false, speedLimitKBps: 500)
    XCTAssertTrue(hasSubsequence(YtDlpArguments.build(for: request(kind: .audio(format: .m4a)), options: o), ["--limit-rate", "500K"]))
}
func test_options_speedLimit_zeroOmitsFlag() {
    let o = GlobalDownloadOptions(proxyURL: nil, forceIPv4: false, speedLimitKBps: 0)
    XCTAssertFalse(YtDlpArguments.build(for: request(kind: .audio(format: .m4a)), options: o).contains("--limit-rate"))
}
func test_redacted_masksProxyUserinfo() {
    let o = GlobalDownloadOptions(proxyURL: "http://user:secret@host:8080", forceIPv4: false, speedLimitKBps: 0)
    let r = YtDlpArguments.redacted(for: request(kind: .audio(format: .m4a)), options: o)
    let i = r.firstIndex(of: "--proxy")!
    XCTAssertFalse(r[i + 1].contains("secret")); XCTAssertFalse(r[i + 1].contains("user:")); XCTAssertTrue(r[i + 1].contains("host:8080"))
}
func test_redacted_identicalWhenNoProxyCreds() {
    let o = GlobalDownloadOptions(proxyURL: "http://host:8080", forceIPv4: true, speedLimitKBps: 200)
    XCTAssertEqual(YtDlpArguments.redacted(for: request(kind: .video(maxHeight: 720)), options: o),
                   YtDlpArguments.build(for: request(kind: .video(maxHeight: 720)), options: o))
}
```

- [ ] **Step 2: Run, verify fail**

Run: `xcodebuild ... test -only-testing:GrabberKitTests/YtDlpArgumentsTests -only-testing:GrabberKitTests/GlobalDownloadOptionsTests`
Expected: FAIL.

- [ ] **Step 3: Create the type**

```swift
import Foundation

public struct GlobalDownloadOptions: Sendable, Equatable {
    public var proxyURL: String?
    public var forceIPv4: Bool
    public var speedLimitKBps: Int

    public init(proxyURL: String?, forceIPv4: Bool, speedLimitKBps: Int) {
        self.proxyURL = proxyURL
        self.forceIPv4 = forceIPv4
        self.speedLimitKBps = speedLimitKBps
    }

    public static let none = GlobalDownloadOptions(proxyURL: nil, forceIPv4: false, speedLimitKBps: 0)
}
```

- [ ] **Step 4: Wire `YtDlpArguments`**

```swift
public static func build(for request: DownloadRequest, options: GlobalDownloadOptions = .none) -> [String] {
    baseArgv(for: request) + globalFlags(options, proxyURL: options.proxyURL) + [request.url]
}

public static func redacted(for request: DownloadRequest, options: GlobalDownloadOptions = .none) -> [String] {
    baseArgv(for: request) + globalFlags(options, proxyURL: options.proxyURL.map(maskUserinfo(in:))) + [request.url]
}

private static func baseArgv(for request: DownloadRequest) -> [String] {
    var argv: [String] = []
    argv += ["-P", request.destFolder.path]
    argv += ["-o", request.filenameTemplate]
    argv += formatSelector(for: request)
    argv += ["--newline", "--progress", "--progress-template", progressTemplate]
    argv += ["--no-playlist", "--no-warnings"]
    return argv
}

private static func globalFlags(_ options: GlobalDownloadOptions, proxyURL: String?) -> [String] {
    var flags: [String] = []
    if let proxy = proxyURL, !proxy.isEmpty { flags += ["--proxy", proxy] }
    if options.forceIPv4 { flags += ["-4"] }
    if options.speedLimitKBps > 0 { flags += ["--limit-rate", "\(options.speedLimitKBps)K"] }
    return flags
}

private static func maskUserinfo(in url: String) -> String {
    guard let at = url.firstIndex(of: "@"), let scheme = url.range(of: "://"), scheme.upperBound < at
    else { return url }
    return String(url[..<scheme.upperBound]) + "***@" + String(url[url.index(after: at)...])
}
```

The pre-existing `test_redactedEqualsBuild_phase1` calls the no-arg forms — `.none` default keeps it green.

- [ ] **Step 5: Regenerate, run, verify pass**

Run: `mise exec -- tuist generate --no-open`, `xcodebuild ... test -only-testing:GrabberKitTests/YtDlpArgumentsTests -only-testing:GrabberKitTests/GlobalDownloadOptionsTests`
Expected: PASS.

- [ ] **Step 6: Lint**

```bash
mise exec -- swiftformat --lint . && mise exec -- swiftlint lint --strict
```

---

## Task 8: `DownloadEngine` passes `GlobalDownloadOptions` at spawn

**Files:**
- Modify: `Sources/GrabberKit/Download/DownloadEngine.swift` (`launchDownload(id:)`, the `YtDlpArguments.build(for: request)` call ~line 261)
- Test: a focused test in `Tests/GrabberKitTests/` (see Step 1)

**Interfaces:**
- Consumes: `preferences.proxyURL` / `.forceIPv4` / `.speedLimitKBps` (Task 5), `GlobalDownloadOptions` (Task 7).
- Produces: behaviour change only — the spawned `yt-dlp` argv carries the global flags.

- [ ] **Step 1: Write the failing test**

The spawned argv is observable through `FakeProcessRunner` (records `ProcessLaunch`). Check `Tests/GrabberKitTests/DownloadEngineTestHelpers.swift` + `Tests/TestSupport/FakeProcessRunner.swift` for the recorded-launches accessor. Add a `@MainActor` test that sets `preferences.forceIPv4 = true`, submits a job, polls until a launch is recorded, and asserts its `arguments.contains("-4")`. Follow the poll-until-terminal pattern from `DownloadEngineLiveTests` / CLAUDE.md.

- [ ] **Step 2: Run, verify fail**

Expected: FAIL — argv has no `-4`.

- [ ] **Step 3: Implement**

In `launchDownload(id:)`, before the `Task { }`:

```swift
let options = GlobalDownloadOptions(
    proxyURL: preferences.proxyURL,
    forceIPv4: preferences.forceIPv4,
    speedLimitKBps: preferences.speedLimitKBps
)
```

Capture `options` (a `Sendable` value) into the `Task` alongside `request`. Change the `arguments:` line to `YtDlpArguments.build(for: request, options: options)`. Read all three `preferences` fields **before** the `Task` (same pattern as `let request = job.request`).

- [ ] **Step 4: Run, verify pass + no regression**

Run the new test plus `-only-testing:GrabberKitTests/DownloadEngineTests -only-testing:GrabberKitTests/DownloadEngineSchedulerTests`.
Expected: PASS.

- [ ] **Step 5: Lint**

```bash
mise exec -- swiftformat --lint . && mise exec -- swiftlint lint --strict
```

---

## Task 9: `PreferencesPane` + deep-link on `AppModel.Page`

**Files:**
- Create: `Sources/App/Preferences/PreferencesPane.swift`
- Modify: `Sources/App/AppModel.swift` (`Page` enum), `Sources/App/MainWindow.swift` (nav target + `page` switch — minimal; full `PreferencesView` in Task 13)
- Test: `Tests/AppUnitTests/PreferencesPaneTests.swift` (new)

**Interfaces:**
- Consumes: nothing.
- Produces:

```swift
enum PreferencesPane: String, CaseIterable, Hashable {
    case downloads, appearance, network, cookies, updates, logsPrivacy, advanced
    var title: String        // "Downloads" … "Sign-in & cookies" … "Logs & privacy" … "Advanced"
    var subtitle: String     // the --dim one-liner above the title rule (spec §5.1–5.7 subs)
    var group: PreferencesRailGroup
}
enum PreferencesRailGroup: String, CaseIterable, Hashable {
    case general, youtube, system
    var caption: String      // "General" / "YouTube" / "System"
    var panes: [PreferencesPane]   // ordered per spec §5
}
```

`AppModel.Page` → `case preferences(PreferencesPane = .downloads)`, `Page: Equatable`.

- [ ] **Step 1: Write failing tests**

```swift
@testable import MediaGrabber
import XCTest

final class PreferencesPaneTests: XCTestCase {
    func test_railGroupsCoverEveryPaneOnce() {
        let all = PreferencesRailGroup.allCases.flatMap(\.panes)
        XCTAssertEqual(Set(all), Set(PreferencesPane.allCases))
        XCTAssertEqual(all.count, PreferencesPane.allCases.count)
    }
    func test_railOrder() {
        XCTAssertEqual(PreferencesRailGroup.general.panes, [.downloads, .appearance, .network])
        XCTAssertEqual(PreferencesRailGroup.youtube.panes, [.cookies])
        XCTAssertEqual(PreferencesRailGroup.system.panes, [.updates, .logsPrivacy, .advanced])
    }
    func test_pageDeepLinkDefault() {
        XCTAssertEqual(AppModel.Page.preferences(), .preferences(.downloads))
    }
    func test_titles() {
        XCTAssertEqual(PreferencesPane.cookies.title, "Sign-in & cookies")
        XCTAssertEqual(PreferencesPane.logsPrivacy.title, "Logs & privacy")
    }
}
```

- [ ] **Step 2: Run, verify fail**

Run: `xcodebuild ... test -only-testing:AppUnitTests/PreferencesPaneTests`
Expected: FAIL.

- [ ] **Step 3: Create `PreferencesPane.swift`**

Implement both enums. `title` / `subtitle` are `switch self`, copy from spec §5.1–5.7 (e.g. `.downloads` sub `"Defaults for new downloads. Change any of these per download on the Home screen."`, `.cookies` sub `"Sign in to reach private or age-restricted videos."`).

- [ ] **Step 4: Update `AppModel.Page`**

Add `: Equatable` to `Page`. Change `case preferences` → `case preferences(PreferencesPane = .downloads)`.

- [ ] **Step 5: Fix `MainWindow`**

`navButton("Preferences", .preferences, page)` → `.preferences()`. Active check: any `.preferences(_)` counts —

```swift
private func isActive(_ page: AppModel.Page, _ target: AppModel.Page) -> Bool {
    switch (page, target) {
    case (.preferences, .preferences): true
    default: page == target
    }
}
```

`page` switch: `case .preferences:` keeps the `placeholder("Preferences")` for now (Task 13 swaps it).

- [ ] **Step 6: Regenerate, run, verify pass**

Run: `mise exec -- tuist generate --no-open`, `xcodebuild ... test -only-testing:AppUnitTests/PreferencesPaneTests -only-testing:AppUnitTests/AppModelTests`.
Expected: PASS.

- [ ] **Step 7: Lint**

```bash
mise exec -- swiftformat --lint . && mise exec -- swiftlint lint --strict
```

---

## Task 10: `SkinnedSegment`

**Files:**
- Create: `Sources/App/Controls/SkinnedSegment.swift`
- Test: none (SwiftUI rendering not unit-tested — spec §9). Verified by compiling into panes + the manual smoke.

**Interfaces:**
- Consumes: `@Environment(\.theme)` → `Theme` (Task 4 collapsed it — `theme.chipRadius`, `theme.palette`, `theme.bodyFont`).
- Produces:

```swift
struct SkinnedSegment<Option: Hashable>: View {
    init(_ options: [Option], selection: Binding<Option>, label: @escaping (Option) -> String)
}
```

- All options as segments in a `--panel` track, `--stroke` border; selected segment `--panel-solid` fill.
- **Equal-width segments** (each sized to the widest label — measure or use a fixed `minWidth` per segment and `fixedSize`); the whole control **hugs content** and is placed by the caller flush-right.
- One tap sets `selection`. Left/Right arrow moves selection when focused. Radius `theme.chipRadius`.
- `.accessibilityElement(children: .contain)`; selected segment `.isSelected`.

- [ ] **Step 1: Implement**

```swift
import SwiftUI

struct SkinnedSegment<Option: Hashable>: View {
    @Environment(\.theme) private var theme
    private let options: [Option]
    @Binding private var selection: Option
    private let label: (Option) -> String

    init(_ options: [Option], selection: Binding<Option>, label: @escaping (Option) -> String) {
        self.options = options
        _selection = selection
        self.label = label
    }

    var body: some View {
        HStack(spacing: 2) {
            ForEach(Array(options.enumerated()), id: \.offset) { _, option in
                segment(option)
            }
        }
        .padding(2)
        .background(theme.palette.panel, in: shape)
        .overlay(shape.stroke(theme.palette.stroke, lineWidth: theme.hairlineWidth))
        .fixedSize()
        .focusable()
        .onMoveCommand(perform: move)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Segmented control")
    }

    private var shape: RoundedRectangle { RoundedRectangle(cornerRadius: theme.chipRadius) }

    private func segment(_ option: Option) -> some View {
        let selected = option == selection
        return Text(label(option))
            .font(theme.bodyFont(12, .medium))
            .foregroundStyle(selected ? theme.palette.text : theme.palette.dim)
            .frame(minWidth: 52)
            .padding(.horizontal, Spacing.s2)
            .padding(.vertical, Spacing.s1)
            .background(selected ? theme.palette.panelSolid : .clear, in: shape)
            .contentShape(Rectangle())
            .onTapGesture { selection = option }
            .accessibilityAddTraits(selected ? [.isButton, .isSelected] : .isButton)
            .accessibilityLabel(label(option))
    }

    private func move(_ direction: MoveCommandDirection) {
        guard let i = options.firstIndex(of: selection) else { return }
        if direction == .left, i > 0 { selection = options[i - 1] }
        if direction == .right, i < options.count - 1 { selection = options[i + 1] }
    }
}
```

- [ ] **Step 2: Regenerate + build**

Run: `mise exec -- tuist generate --no-open`, `xcodebuild ... build`.
Expected: clean.

- [ ] **Step 3: Lint**

```bash
mise exec -- swiftformat --lint . && mise exec -- swiftlint lint --strict
```

---

## Task 11: `SkinnedPicker`

**Files:**
- Create: `Sources/App/Controls/SkinnedPicker.swift`
- Test: none (rendering + popover geometry excluded — spec §9).

**Interfaces:**
- Consumes: `@Environment(\.theme)` → `Theme`.
- Produces:

```swift
struct SkinnedPickerRow<Option: Hashable>: Identifiable {
    var id: Option
    var title: String
    var subtitle: String?   // nil -> single-line
}

struct SkinnedPicker<Option: Hashable>: View {
    init(caption: String,
         rows: [SkinnedPickerRow<Option>],
         selection: Binding<Option>,
         triggerLabel: String? = nil)   // defaults to selected row's title
}
```

- Trigger: label + chevron, `--panel` fill, `--stroke` border, `theme.controlRadius`. Trigger width = its own label.
- Popover (`.popover(isPresented:arrowEdge:.bottom)`): `--panel-solid`, theme border + `theme.cardRadius` + elevation (Aurora glow via `theme.palette.glowB`; Tape Deck hard offset shadow — branch on the theme case). Width sized to the widest row, clamped `[trigger width … 340]` — use a `GeometryReader`/measured width or a computed max on the row strings; simplest acceptable: a fixed `min(340, max(triggerWidth, contentWidth))` where `contentWidth` is estimated from the longest `title`/`subtitle` via a hidden measuring `Text`.
- Caption header: `--faint`, `.textCase(.uppercase)`, hairline `--hair` rule under.
- Rows: leading checkmark column (fixed width; `--accent` `Image(systemName: "checkmark")` on the selected row only), title (`--text`), optional subtitle (`--dim`, second line). Hover / arrow highlight = `theme.palette.accent.opacity(0.12)`. No icons.
- Keyboard on the popover content: Up/Down move `highlighted` through `rows.map(\.id)`; Return commits `highlighted` + closes; Esc closes unchanged. `.onAppear` seeds `highlighted = selection`.
- Trigger `.accessibilityAddTraits(.isButton)` + `.accessibilityValue(currentLabel)`; popover `.accessibilityElement(children: .contain)`; selected row `.isSelected`.

- [ ] **Step 1: Implement**

Build with `@State private var isPresented = false`, `@State private var highlighted: Option?`. Structure per the Interfaces block. Elevation:

```swift
private var isAurora: Bool { theme.kind == .aurora }   // expose `kind` on Theme if not present
// shadow: isAurora ? .init(color: theme.palette.glowB, radius: 20)
//                  : .init(color: .black.opacity(0.35), radius: 0, x: 3, y: 3)
```

(If `Theme` has no `kind` accessor, add a `var kind: ThemeKind` or `var isAurora: Bool` — trivial, one line.)

- [ ] **Step 2: Regenerate + build**

Run: `mise exec -- tuist generate --no-open`, `xcodebuild ... build`.
Expected: clean.

- [ ] **Step 3: Lint**

```bash
mise exec -- swiftformat --lint . && mise exec -- swiftlint lint --strict
```

---

## Task 12: `FileNamingPreset` + `ConcurrencyNote` + `RunwaySeed`

**Files:**
- Create: `Sources/App/Preferences/FileNamingPreset.swift`, `Sources/App/Preferences/ConcurrencyNote.swift`, `Sources/App/Home/RunwaySeed.swift`
- Test: `Tests/AppUnitTests/FileNamingPresetTests.swift`, `ConcurrencyNoteTests.swift`, `RunwaySeedTests.swift`

**Interfaces:**
- Consumes: `Preferences`, `MediaType`, `AudioFormat`.
- Produces:

```swift
enum FileNamingPreset: CaseIterable, Hashable {
    case title, titleAndChannel, dateAndTitle, custom
    var rowLabel: String        // "Title" / "Title – channel" / "Date – title" / "Custom…"
    var template: String?       // nil for .custom
    var exampleSubtitle: String?
    static func matching(_ stored: String) -> FileNamingPreset
}

func shouldShowConcurrencyNote(newValue: Int, runningCount: Int) -> Bool   // newValue < runningCount

struct RunwaySeed: Equatable {
    var mediaType: MediaType
    var videoHeight: Int
    var audioFormat: AudioFormat
    var downloadFolder: URL
}
func runwaySeed(from prefs: Preferences) -> RunwaySeed
```

Templates (exact): `.title` → `%(title)s.%(ext)s` · `.titleAndChannel` → `%(title)s - %(uploader)s.%(ext)s` · `.dateAndTitle` → `%(upload_date>%Y-%m-%d)s - %(title)s.%(ext)s`.

- [ ] **Step 1: Write failing tests**

`ConcurrencyNoteTests`:

```swift
func test_trueOnlyWhenNewBelowRunning() {
    XCTAssertTrue(shouldShowConcurrencyNote(newValue: 2, runningCount: 3))
    XCTAssertFalse(shouldShowConcurrencyNote(newValue: 3, runningCount: 3))
    XCTAssertFalse(shouldShowConcurrencyNote(newValue: 4, runningCount: 3))
    XCTAssertFalse(shouldShowConcurrencyNote(newValue: 3, runningCount: 0))
}
```

`FileNamingPresetTests`:

```swift
func test_templates() {
    XCTAssertEqual(FileNamingPreset.title.template, "%(title)s.%(ext)s")
    XCTAssertEqual(FileNamingPreset.titleAndChannel.template, "%(title)s - %(uploader)s.%(ext)s")
    XCTAssertEqual(FileNamingPreset.dateAndTitle.template, "%(upload_date>%Y-%m-%d)s - %(title)s.%(ext)s")
    XCTAssertNil(FileNamingPreset.custom.template)
}
func test_matching() {
    XCTAssertEqual(FileNamingPreset.matching("%(title)s.%(ext)s"), .title)
    XCTAssertEqual(FileNamingPreset.matching("%(id)s.%(ext)s"), .custom)
}
```

`RunwaySeedTests`:

```swift
private func prefs() -> Preferences { Preferences(defaults: UserDefaults(suiteName: "mg.seed.\(UUID())")!) }
func test_fallsBackToDefaults() {
    let s = runwaySeed(from: prefs())
    XCTAssertEqual(s.mediaType, .video)
    XCTAssertEqual(s.videoHeight, 1080)
    XCTAssertEqual(s.audioFormat, .m4a)
}
func test_prefersLastSelected() {
    let p = prefs()
    p.lastMediaType = .audio; p.lastVideoHeight = .max; p.lastAudioFormat = .mp3
    let s = runwaySeed(from: p)
    XCTAssertEqual(s.mediaType, .audio)
    XCTAssertEqual(s.videoHeight, .max)
    XCTAssertEqual(s.audioFormat, .mp3)
}
```

- [ ] **Step 2: Run, verify fail**

Run: `xcodebuild ... test -only-testing:AppUnitTests/FileNamingPresetTests -only-testing:AppUnitTests/ConcurrencyNoteTests -only-testing:AppUnitTests/RunwaySeedTests`
Expected: FAIL.

- [ ] **Step 3: Implement `ConcurrencyNote.swift`**

```swift
import SwiftUI

func shouldShowConcurrencyNote(newValue: Int, runningCount: Int) -> Bool {
    newValue < runningCount
}

struct ConcurrencyNote: View {
    @Environment(\.theme) private var theme
    let runningCount: Int

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: Spacing.s1) {
            Text(Icon.warn)   // use the design-system warn glyph constant from Sources/App/Theme/Icon.swift
                .foregroundStyle(theme.palette.warn)
            Text("\(runningCount) still running \u{2014} the new limit applies as they finish.")
                .font(theme.bodyFont(11.5, .regular))
                .foregroundStyle(theme.palette.dim)
        }
    }
}
```

Check `Sources/App/Theme/Icon.swift` for the actual warn-glyph constant; use it, don't hardcode a codepoint.

- [ ] **Step 4: Implement `FileNamingPreset.swift`**

```swift
import Foundation

enum FileNamingPreset: CaseIterable, Hashable {
    case title, titleAndChannel, dateAndTitle, custom

    var rowLabel: String {
        switch self {
        case .title: "Title"
        case .titleAndChannel: "Title \u{2013} channel"
        case .dateAndTitle: "Date \u{2013} title"
        case .custom: "Custom\u{2026}"
        }
    }
    var template: String? {
        switch self {
        case .title: "%(title)s.%(ext)s"
        case .titleAndChannel: "%(title)s - %(uploader)s.%(ext)s"
        case .dateAndTitle: "%(upload_date>%Y-%m-%d)s - %(title)s.%(ext)s"
        case .custom: nil
        }
    }
    var exampleSubtitle: String? {
        switch self {
        case .title: "Never Gonna Give You Up.mp4"
        case .titleAndChannel: "Never Gonna Give You Up - Rick Astley.mp4"
        case .dateAndTitle: "2009-10-25 - Never Gonna Give You Up.mp4"
        case .custom: nil
        }
    }
    static func matching(_ stored: String) -> FileNamingPreset {
        allCases.first { $0.template == stored } ?? .custom
    }
}
```

- [ ] **Step 5: Implement `RunwaySeed.swift`**

```swift
import Foundation
import GrabberKit

struct RunwaySeed: Equatable {
    var mediaType: MediaType
    var videoHeight: Int
    var audioFormat: AudioFormat
    var downloadFolder: URL
}

func runwaySeed(from prefs: Preferences) -> RunwaySeed {
    let folder = prefs.lastUsedDownloadFolder != prefs.defaultDownloadFolder
        ? prefs.lastUsedDownloadFolder
        : prefs.defaultDownloadFolder
    return RunwaySeed(
        mediaType: prefs.lastMediaType ?? prefs.defaultMediaType,
        videoHeight: prefs.lastVideoHeight ?? prefs.defaultVideoHeight,
        audioFormat: prefs.lastAudioFormat ?? prefs.defaultAudioFormat,
        downloadFolder: folder
    )
}
```

- [ ] **Step 6: Regenerate, run, verify pass**

Run: `mise exec -- tuist generate --no-open`, the three suites from Step 2.
Expected: PASS.

- [ ] **Step 7: Lint**

```bash
mise exec -- swiftformat --lint . && mise exec -- swiftlint lint --strict
```

---

## Task 13: `PrefRow` + `PreferencesView` shell + stepless panes

**Files:**
- Create: `Sources/App/Preferences/PrefRow.swift`, `Sources/App/Preferences/PreferencesView.swift`, `Sources/App/Preferences/Panes/SignInCookiesPane.swift`, `Sources/App/Preferences/Panes/UpdatesPane.swift`
- Modify: `Sources/App/MainWindow.swift` (`page` switch → `PreferencesView(initialPane:)`)
- Test: none (view shell; pane resolution covered by Task 9).

**Interfaces:**
- Consumes: `PreferencesPane` / `PreferencesRailGroup` (Task 9), `@Environment(\.theme)`, `@Environment(AppModel.self)`.
- Produces:

```swift
struct PrefRow<Control: View>: View {
    init(_ label: String, helper: String? = nil, @ViewBuilder control: () -> Control)
}
struct PrefPaneHeader: View { init(_ pane: PreferencesPane) }
struct PrefSteplessPane: View { init(_ pane: PreferencesPane, line: String) }
struct PreferencesView: View { init(initialPane: PreferencesPane = .downloads) }
```

- [ ] **Step 1: Implement `PrefRow.swift`**

`PrefRow`: `HStack(alignment: .top)` — left `VStack(alignment: .leading, spacing: Spacing.s1)` with `label` (`theme.bodyFont(13, .semibold)`, `--text`) + optional `helper` (`theme.bodyFont(11.5, .regular)`, `--dim`); `Spacer()`; `control()` trailing. Trailing `Divider().overlay(theme.palette.hair)`.

`PrefPaneHeader`: `VStack(alignment: .leading, spacing: Spacing.s1)` — `pane.subtitle` (`--dim`, 11.5), `pane.title` (`theme.displayFont(20, .heavy)`, `--headline`), `Divider().overlay(theme.palette.hair)`.

`PrefSteplessPane`: `PrefPaneHeader(pane)` then `Text(line).font(theme.bodyFont(12, .regular)).foregroundStyle(theme.palette.faint)`.

- [ ] **Step 2: Implement the two stepless panes**

```swift
struct SignInCookiesPane: View {
    var body: some View { PrefSteplessPane(.cookies, line: "Cookie sign-in is coming in a later update.") }
}
struct UpdatesPane: View {
    var body: some View { PrefSteplessPane(.updates, line: "Update checks are coming in a later update.") }
}
```

- [ ] **Step 3: Implement `PreferencesView.swift`**

`HStack(spacing: 0)` — rail (fixed `width: 200`, `VStack` of group captions + `railButton`s, **no `ScrollView`**), `Divider().overlay(theme.palette.hair)`, then `ScrollView { paneBody.padding(Spacing.s6) }`. `@State selectedPane` seeded from `initialPane`. `paneBody` switches over `selectedPane` to the seven pane views. Since Tasks 14–17 build five of them, either (a) build this shell last, or (b) stub `DownloadsPane` / `AppearancePane` / `NetworkPane` / `LogsPrivacyPane` / `AdvancedPane` as `struct X: View { var body: some View { PrefPaneHeader(.x) } }` in their own files now and let Tasks 14–17 replace the body (fill, not rip-and-replace).

- [ ] **Step 4: Wire `MainWindow`**

`case .preferences(let pane): PreferencesView(initialPane: pane)`. Remove `placeholder("Preferences")`.

- [ ] **Step 5: Regenerate, build, run AppUnitTests**

Run: `mise exec -- tuist generate --no-open`, `xcodebuild ... build`, `xcodebuild ... test -only-testing:AppUnitTests`.
Expected: builds; tests green.

- [ ] **Step 6: Lint**

```bash
mise exec -- swiftformat --lint . && mise exec -- swiftlint lint --strict
```

---

## Task 14: Downloads pane

**Files:**
- Create/replace-stub: `Sources/App/Preferences/Panes/DownloadsPane.swift`
- Test: none new.

**Interfaces:**
- Consumes: `@Environment(AppModel.self)` → `appModel.prefs`, `appModel.rowStore.rows`; `SkinnedSegment`, `SkinnedPicker`, `FileNamingPreset` + `shouldShowConcurrencyNote` + `ConcurrencyNote`, `PrefRow`, `MediaType`, `AudioFormat`.
- Produces: `struct DownloadsPane: View`.

Rows per spec §5.1 (labels/helpers exact):

| Label | Helper | Control | Backs |
|---|---|---|---|
| Downloads folder | — | folder button `~/Downloads` (abbreviated path), **no chevron** → `NSOpenPanel` dirs-only | `defaultDownloadFolder` |
| Simultaneous downloads | Automatically reduced if a site rate-limits you. | `Stepper` 1–6 · `ConcurrencyNote` under it when `shouldShowConcurrencyNote(newValue: prefs.maxConcurrentDownloads, runningCount:)` | `maxConcurrentDownloads` |
| Automatic retries | Attempts before the app asks you what to do. | `Stepper` 1–5 | `maxAutoRetries` |
| Media type | — | `SkinnedSegment([.video, .audio]) { $0 == .video ? "Video" : "Audio" }` | `defaultMediaType` |
| Video quality | Highest available if the exact height isn't offered. | `SkinnedPicker` — quality ladder | `defaultVideoHeight` (`Int.max`=Best) |
| Audio format | — | `SkinnedSegment([.m4a, .mp3]) { $0.rawValue.uppercased() }` | `defaultAudioFormat` |
| Filename format | — | `SkinnedPicker` of `FileNamingPreset` + custom field | `filenameTemplate` |
| Clipboard detection | Offer to grab links you copy. | `Toggle` | `detectClipboardLinks` |

- [ ] **Step 1: Implement**

Key details:
- `runningCount = appModel.rowStore.rows.filter { $0.snapshot.state == .running }.count`.
- Quality ladder: `[("2160p", 2160), ("1440p", 1440), ("1080p", 1080), ("720p", 720), ("480p", 480), ("Best available", Int.max)]`. `SkinnedPicker` rows keyed by height; `caption: "Resolution"`; trigger label = matching row label, fallback `"\(prefs.defaultVideoHeight)p"`.
- Media type: `Binding` onto `prefs.defaultMediaType` (now public).
- Filename format: `@State namingPreset` seeded `.onAppear` from `FileNamingPreset.matching(prefs.filenameTemplate)`; `@State customText` seeded from `prefs.filenameTemplate`. Picker `caption: "File naming"`, rows from `FileNamingPreset.allCases` (subtitle = `exampleSubtitle`). On select: preset with a `template` → `prefs.filenameTemplate = template`; `.custom` → reveal the monospace `TextField` (`theme.monoFont(12, .regular)`), on blur/submit trimmed-empty reverts `customText` to `prefs.filenameTemplate` else writes it.
- "Downloads folder" button: `NSOpenPanel` pattern from `RunwayView.chooseFolder()` (dirs only, no multi). Show `prefs.defaultDownloadFolder.path` abbreviated with `(_ as NSString).abbreviatingWithTildeInPath` → `~/Downloads`.
- `@Bindable var prefs = appModel.prefs` for `Stepper` / `Toggle`.
- Wrap: `PrefPaneHeader(.downloads)` + `VStack(spacing: 0)` of `PrefRow`s.

- [ ] **Step 2: Regenerate + build**

Run: `mise exec -- tuist generate --no-open`, `xcodebuild ... build`.
Expected: clean.

- [ ] **Step 3: Lint**

```bash
mise exec -- swiftformat --lint . && mise exec -- swiftlint lint --strict
```

---

## Task 15: Appearance pane + palette swatch

**Files:**
- Create/replace-stub: `Sources/App/Preferences/Panes/AppearancePane.swift`
- Test: none new.

**Interfaces:**
- Consumes: `appModel.prefs.theme` / `.palette`, `ThemeKind` / `PaletteKind`, `palette(for:)` (App-target free function), `SkinnedSegment`, `PrefRow`, `@Environment(\.theme)`.
- Produces: `struct AppearancePane: View`.

Rows per spec §5.2:

| Label | Helper | Control | Backs |
|---|---|---|---|
| Theme | Aurora is dark and luminous. Tape Deck is warm and light. | `SkinnedSegment([.aurora, .tapeDeck]) { $0 == .aurora ? "Aurora" : "Tape Deck" }` | `theme` |
| Palette | — | 3 swatches for the selected theme | `palette` |

- [ ] **Step 1: Implement**

- `palettes(for:)`:
  ```swift
  private func palettes(for theme: ThemeKind) -> [PaletteKind] {
      switch theme {
      case .aurora: [.auroraMintIris, .auroraLimeForest, .auroraMagentaViolet]
      case .tapeDeck: [.tapeDeckA, .tapeDeckB, .tapeDeckC]
      }
  }
  ```
- Swatch: `RoundedRectangle` ~38pt tall, split into two halves — left `palette(for: kind).accent`, right `.accent2`; palette display name below (`--text`, small). Selected (`kind == prefs.palette`): `.overlay(RoundedRectangle(...).stroke(theme.palette.accent, lineWidth: 2).padding(-2))`.
- Palette display names: local `switch` — `"Mint & Iris"`, `"Lime & Forest"`, `"Magenta & Violet"`, `"Teal & Rust"`, `"Plum & Blush"`, `"Navy & Aqua"` (from design-system §5.2/5.3).
- `.onChange(of: prefs.theme) { _, new in prefs.palette = defaultPalette(for: new) }` where `defaultPalette` → `.auroraMintIris` / `.tapeDeckA`.
- Both controls write straight to `prefs` — live re-theme via the existing `@Observable` binding.

Note: `palette(for:)` currently returns Aurora Mint tokens for every kind — swatches render identically until Phase 9. Expected; do not add palette values here.

- [ ] **Step 2: Regenerate + build**

Run: `mise exec -- tuist generate --no-open`, `xcodebuild ... build`.
Expected: clean.

- [ ] **Step 3: Lint**

```bash
mise exec -- swiftformat --lint . && mise exec -- swiftlint lint --strict
```

---

## Task 16: Network pane

**Files:**
- Create/replace-stub: `Sources/App/Preferences/Panes/NetworkPane.swift`
- Test: none new (field behaviour covered in Task 5; argv wiring Task 7).

**Interfaces:**
- Consumes: `appModel.prefs.proxyURL` / `.forceIPv4` / `.speedLimitKBps`, `PrefRow`, `@Environment(\.theme)`.
- Produces: `struct NetworkPane: View`.

Rows per spec §5.3:

| Label | Helper | Control | Backs |
|---|---|---|---|
| Proxy server | `http://host:port` — blank for none. | `TextField` | `proxyURL` |
| Force IPv4 | Can help when connections stall. | `Toggle` | `forceIPv4` |
| Speed limit | Applies to each download separately. | KB/s stepper, "Off" at 0 | `speedLimitKBps` |

- [ ] **Step 1: Implement**

- Proxy: `@State proxyText` seeded `.onAppear` from `prefs.proxyURL ?? ""`; `.onSubmit` / focus-loss → `prefs.proxyURL = proxyText` (setter trims + empty→nil).
- IPv4: `Toggle("", isOn: $prefs.forceIPv4)`.
- Speed limit: custom `-`/`+` stepper. Display `prefs.speedLimitKBps == 0 ? "Off" : "\(prefs.speedLimitKBps) KB/s"`. `-` from the minimum real value (100) lands on 0; `+` from 0 lands on 100. Step 100. Setter clamps `0…100000`.
- `PrefPaneHeader(.network)`.

- [ ] **Step 2: Regenerate + build**

Run: `mise exec -- tuist generate --no-open`, `xcodebuild ... build`.
Expected: clean.

- [ ] **Step 3: Lint**

```bash
mise exec -- swiftformat --lint . && mise exec -- swiftlint lint --strict
```

---

## Task 17: Logs & privacy + Advanced panes + `AppModel.resetAllSettings()`

**Files:**
- Create/replace-stub: `Sources/App/Preferences/Panes/LogsPrivacyPane.swift`, `Sources/App/Preferences/Panes/AdvancedPane.swift`
- Modify: `Sources/App/AppModel.swift` (add `resetAllSettings()`), `apps/media-grabber/Project.swift` (PRIVACY.md resource, if not present)
- Test: `Tests/AppUnitTests/AppModelTests.swift`

**Interfaces:**
- Consumes: `appModel.prefs`, `appModel.columnConfig`, `appModel.confirm(_:)`, `ConfirmationRequest` (GrabberKit), `NSWorkspace`, `PrefRow`.
- Produces:
  - `AppModel.resetAllSettings()` → `prefs.resetToDefaults()`.
  - `struct LogsPrivacyPane: View`, `struct AdvancedPane: View`.

Spec §5.6 / §5.7 rows (labels/helpers exact — see spec).

- [ ] **Step 1: Write the failing test**

Add to `AppModelTests`:

```swift
@MainActor
func test_resetAllSettings_restoresDefaults() {
    let model = makeAppModel()   // match existing helper
    model.prefs.defaultVideoHeight = 480
    model.prefs.theme = .tapeDeck
    model.resetAllSettings()
    XCTAssertEqual(model.prefs.defaultVideoHeight, 1080)
    XCTAssertEqual(model.prefs.theme, .aurora)
}
```

(`Preferences.resetToDefaults()` itself is covered in Task 6 — this just checks the `AppModel` passthrough.)

- [ ] **Step 2: Run, verify fail**

Run: `xcodebuild ... test -only-testing:AppUnitTests/AppModelTests`
Expected: FAIL — `resetAllSettings` undefined.

- [ ] **Step 3: Implement `AppModel.resetAllSettings()`**

```swift
func resetAllSettings() {
    prefs.resetToDefaults()
}
```

- [ ] **Step 4: Implement the two panes**

`LogsPrivacyPane` — three `PrefRow`s:
- "Log files" → `Button("Show in Finder") { NSWorkspace.shared.activateFileViewerSelecting([logFolderURL]) }` where `logFolderURL = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Logs/MediaGrabber")`.
- "Verbose logging" → `Toggle("", isOn: $prefs.verboseLogging)`, helper "More detail for troubleshooting."
- "Privacy details" → `Button("Open") { if let u = Bundle.main.url(forResource: "PRIVACY", withExtension: "md") { NSWorkspace.shared.open(u) } }`.

`AdvancedPane` — three `PrefRow`s:
- "App data" → `Button("Show in Finder")` → reveal `~/Library/Application Support/MediaGrabber`.
- "Reset columns" → `Button("Reset") { appModel.columnConfig = .default }`, helper "Table layout back to default."
- "Reset settings" → `Button("Reset\u{2026}")` styled `--danger`; on tap:
  ```swift
  Task {
      let ok = await appModel.confirm(ConfirmationRequest(
          title: "Reset settings?",
          message: "All preferences go back to their defaults. Your downloads and table columns aren't affected.",
          confirmTitle: "Reset",
          cancelTitle: "Cancel",
          isDestructive: true,
          suppressionKey: nil
      ))
      if ok { appModel.resetAllSettings() }
  }
  ```
  Match `ConfirmationRequest.init` labels to `Sources/GrabberKit/App/Confirming.swift` exactly (verify: `title`, `message`, `confirmTitle`, `cancelTitle`, `isDestructive`, `suppressionKey`).

- [ ] **Step 5: PRIVACY.md bundle resource**

Check `apps/media-grabber/Project.swift` — if the App target's `resources` doesn't include `PRIVACY.md`, add it. `PRIVACY.md` is at the leaf root. Confirm it lands in the bundle (`xcodebuild ... build` then inspect, or trust the Tuist glob).

- [ ] **Step 6: Regenerate, run, verify pass**

Run: `mise exec -- tuist generate --no-open`, `xcodebuild ... test -only-testing:AppUnitTests`.
Expected: PASS. Build the app; manually confirm "Reset settings" re-themes live (Task 19 smoke). If a bulk `removeObject` doesn't fire `@Observable` observation and the theme goes stale, add a minimal fix: a `@ObservationIgnored`-free stored `var revision = 0` on `Preferences` bumped in `resetToDefaults()`, referenced once in `MediaGrabberApp`'s `.theme(...)` closure so a reset re-evaluates it.

- [ ] **Step 7: Lint**

```bash
mise exec -- swiftformat --lint . && mise exec -- swiftlint lint --strict
```

---

## Task 18: Runway — skinned controls + `lastSelected*` seeding

**Files:**
- Modify: `Sources/App/Home/RunwayView.swift`, `Sources/App/Home/HomeView.swift`, `Sources/App/AppModel.swift` (`grab` writes `last*`), `Sources/App/Rows/RequestBuilder.swift` (only if `RunwayOverrides` needs a change)
- Test: `Tests/AppUnitTests/RunwaySeedTests.swift` (Task 12 — add a HomeView-seed assertion if useful), `Tests/AppUnitTests/AppModelTests.swift`

**Interfaces:**
- Consumes: `SkinnedSegment`, `SkinnedPicker`, `MediaType`, `AudioFormat`, `runwaySeed(from:)` (Task 12), `Preferences.last*` (Task 5).
- Produces:
  - `RunwayView` uses `MediaType` (nested `KindSelector` already deleted in Task 3).
  - `AppModel.grab(overrides:)` writes `prefs.lastMediaType` / `.lastVideoHeight` / `.lastAudioFormat` from `overrides.kind`.

- [ ] **Step 1: Write failing tests**

Add to `AppModelTests`:

```swift
@MainActor
func test_grab_writesLastSelectedFromOverrides() async {
    let model = makeAppModel(/* resolved metadata set via the test path */)
    await model.grab(overrides: RunwayOverrides(kind: .video(maxHeight: 720), destFolder: nil))
    XCTAssertEqual(model.prefs.lastMediaType, .video)
    XCTAssertEqual(model.prefs.lastVideoHeight, 720)
}
```

Match `makeAppModel` + resolved-metadata setup to the existing helpers.

- [ ] **Step 2: Run, verify fail**

Run: `xcodebuild ... test -only-testing:AppUnitTests/AppModelTests`
Expected: FAIL — `grab` doesn't write `last*`.

- [ ] **Step 3: Wire `HomeView` seeding**

`HomeView.seedFromPrefs`:

```swift
private func seedFromPrefs() {
    guard !seeded else { return }
    seeded = true
    let seed = runwaySeed(from: appModel.prefs)
    mediaType = seed.mediaType
    videoHeight = seed.videoHeight
    audioFormat = seed.audioFormat
    destFolder = seed.downloadFolder
}
```

Rename `HomeView`'s `@State` vars: `kindSelector` → `mediaType: MediaType`, `maxHeight` → `videoHeight: Int`, `audioCodec` → `audioFormat: AudioFormat`. `selectedKind` computed prop switches on `mediaType`, `.audio(format: audioFormat)`.

- [ ] **Step 4: Swap `RunwayView` controls**

- `typeMenu` → `SkinnedSegment([.video, .audio], selection: $mediaType) { $0 == .video ? "Video" : "Audio" }`.
- `formatMenu` video branch → `SkinnedPicker` quality ladder (`caption: "Resolution"`, rows keyed by height, `nil` subtitles, ladder `2160/1440/1080/720/480/Best available` — **no 360**), `selection: $videoHeight`.
- `formatMenu` audio branch → `SkinnedSegment([.m4a, .mp3], selection: $audioFormat) { $0.rawValue.uppercased() }`.
- `saveMenu` → `SkinnedPicker`, `caption: "Save to"`:
  - Model `Option` as `enum SaveTarget: Hashable { case folder(URL); case choose }` local to `RunwayView`.
  - Row 1: `.folder(defaultDownloadFolder)` — title = name, subtitle = path.
  - Row 2: `.folder(lastUsedDownloadFolder)` **only if `!= defaultDownloadFolder`**.
  - Row 3: `.choose` — title "Choose…", no subtitle.
  - On select `.folder(url)` → `destFolder = url`; `.choose` → `NSOpenPanel`, on pick `destFolder = url` and `appModel.prefs.lastUsedDownloadFolder = url`.
  - `triggerLabel` = `destFolder.lastPathComponent`.
- Delete `RunwayView.heights`.

- [ ] **Step 5: `AppModel.grab` writes `last*`**

In `grab(overrides:)`, after `RequestBuilder.build(...)` and the existing `lastUsedDownloadFolder` write:

```swift
if let kind = overrides.kind {
    switch kind {
    case let .video(maxHeight):
        prefs.lastMediaType = .video
        prefs.lastVideoHeight = maxHeight
    case let .audio(format):
        prefs.lastMediaType = .audio
        prefs.lastAudioFormat = format
    }
}
```

- [ ] **Step 6: Regenerate, run, verify pass**

Run: `mise exec -- tuist generate --no-open`, `xcodebuild ... test -only-testing:AppUnitTests`.
Expected: PASS. Full app build clean.

- [ ] **Step 7: Lint**

```bash
mise exec -- swiftformat --lint . && mise exec -- swiftlint lint --strict
```

---

## Task 19: design-system.md · full test pass · manual smoke · DoD

**Files:**
- Modify: `apps/media-grabber/docs/design-system.md`
- Modify: parent spec `docs/superpowers/specs/2026-08-28-youtube-downloader-mac-design.md` §12.1 / §12.2
- Create: a manual smoke checklist file (check where prior phases kept theirs; if none, put it beside the plan)

**Interfaces:**
- Consumes: everything from Tasks 1–18.
- Produces: nothing new.

- [ ] **Step 1: Update `design-system.md` per spec §8.1**

1. Global "Skin" → "Theme": §2 heading, §2.1/§2.2 prose, every "skin" occurrence, `data-skin` → `data-theme`.
2. §4.6 Preferences — full rewrite to match spec §5: two-column rows, title hierarchy, fixed window / rail no-scroll / right pane scrolls, per-pane row tables with the final labels/helpers/controls, stepless Sign-in / Updates, Advanced buttons, concurrency note. Fix concurrency stepper range to 1–6. Update the "new Preferences fields" line to the §3 set.
3. §4.9 `SkinnedSegment` (new) — spec §4.1, incl. equal-width / hug-content / flush-right.
4. §4.10 `SkinnedPicker` (new) — spec §4.2, incl. "popover, not a modal" + content-sized-clamped width.
5. §4.2.2 — runway Media-type / Format / Save-to now `SkinnedSegment` / `SkinnedPicker`, not `Menu`.
6. §5.2 Tape Deck `--warn` — replace `#E4A11B` / `#E8B24A` / `#F2B12E` with the darker ambers finalised in Task 1 Step 7 (same values). Leave `--go` rows. Aurora `--warn` unchanged. Add a one-line note it also affects future `--warn`-as-text uses.
7. §3.4 — confirm the warn glyph is reused for the concurrency note; no new glyph.

- [ ] **Step 2: Full test + lint**

```bash
xcodebuild -workspace MediaGrabber.xcworkspace -scheme MediaGrabber-Workspace -destination 'platform=macOS' test
mise exec -- swiftformat --lint .
mise exec -- swiftlint lint --strict
```
Expected: all green, both linters clean.

- [ ] **Step 3: Manual smoke (spec §9)**

`make` to build + launch. Walk:
- Open each of the 7 panes from the rail; rail doesn't scroll, Downloads pane does.
- Change Theme (Aurora ↔ Tape Deck) and Palette — whole app re-themes on click.
- Start a download, lower "Simultaneous downloads" below the running count — note appears; finish a download so running ≤ new value — note clears.
- Set proxy / Force IPv4 / speed limit — start a download, check its job log / process argv carries `--proxy` / `-4` / `--limit-rate NNNK`.
- Advanced → "Reset settings" → confirm → every preference back to default; theme/palette snap live.
- Advanced → "Reset columns" → columns restore; independent of "Reset settings".
- Runway: Media-type / Quality / Save-to pickers open, select, persist to the next paste (relaunch, paste a new link, runway shows last selection).
- Filename format: pick each preset (template changes); "Custom…" reveals the field, edit, persists, re-derives to the right row on reopen.

Record pass/fail per item; fix failures via the owning task before proceeding.

- [ ] **Step 4: Update parent spec §12.1 / §12.2**

- §12.1 Phase 3 stub → rewrite to what shipped (7-pane `PreferencesView`, `SkinnedSegment` / `SkinnedPicker` as popover/segment, new `Preferences` fields, the vocabulary sweep, `GlobalDownloadOptions` wiring, concurrency note, deep-link seam).
- §12.2 `PreferencesView` row → updated status.
- Confirm the Phase 5 / 7 / 8 / 10 hints are present (added during design — verify, don't duplicate).

- [ ] **Step 5: Archive the spec + plan (CLAUDE.md convention)**

```bash
mv docs/superpowers/specs/2026-08-31-media-grabber-phase-3.md docs/superpowers/specs/archived/
mv docs/superpowers/plans/2026-08-31-media-grabber-phase-3.md docs/superpowers/plans/archived/
```

Keep the `assets/2026-08-31-media-grabber-phase-3/` folder where it is (frozen; the archived spec still references it by relative path — adjust the path in the archived spec if needed).

- [ ] **Step 6: Hand off**

Report the full Phase 3 build to the user for review.

---

## Self-Review

**1. Spec coverage:**

| Spec section | Task |
|---|---|
| §1 7-pane `PreferencesView`, rail no-scroll, right pane scrolls | 9, 13 |
| §1 filled panes | 14, 15, 16, 17 |
| §1 stepless panes, "coming in a later update", no phase ref | 13 |
| §1 `SkinnedSegment` (equal-width, hug, flush right) | 10 |
| §1 `SkinnedPicker` (popover, content-sized width) | 11 |
| §1 controls replace runway `Menu`s | 18 |
| §1 new `Preferences` fields | 5 |
| §1 rename sweep (§11) | 2, 3, 4 |
| §1 `GlobalDownloadOptions` + `YtDlpArguments` + engine | 7, 8 |
| §1 concurrency note | 12, 14 |
| §1 `Page.preferences(PreferencesPane)` deep-link | 9 |
| §1 doc updates | 1 (screens.html), 19 (design-system, parent spec) |
| §2.1 navigation / `MainWindow` | 9, 13 |
| §3 fields + `speedLimitKBps: Int` default 0 + `MediaType` | 3, 5 |
| §3 "Best available" = `Int.max` | 5, 14, 18 |
| §3.1 `runwaySeed(from:)`, Save-to always seeded | 12, 18 |
| §4.1 / §4.2 control design | 1, 10, 11 |
| §5.1 Downloads rows + copy | 14 |
| §5.1.1 filename presets + custom field | 12, 14 |
| §5.1.2 runway Save-to | 18 |
| §5.1.3 runway Media-type/Quality/Format, drop 360 | 18 |
| §5.2 Appearance + swatch | 15 |
| §5.3 Network + Off-at-0 | 16 |
| §5.4 / §5.5 stepless | 13 |
| §5.6 Logs & privacy | 17 |
| §5.7 Advanced + resets | 17 |
| §6 concurrency note copy + predicate | 12, 14 |
| §7 `GlobalDownloadOptions` + `YtDlpArguments` | 7 |
| §8.1 design-system | 19 |
| §8.2 screens.html rebuild | 1 |
| §9 tests | 2–18 (per task) |
| §10 DoD | 19 |
| §11 vocabulary sweep (all sub-parts) | 2 (Skin→Theme), 3 (AudioCodec, KindSelector), 4 (fields, outputTemplate, ResolvedTheme collapse) |

No gaps.

**2. Placeholder scan:** every code step has real code or a precise description with exact symbol names, paths, copy. Tape Deck `--warn` hexes are "start from ≈X, verify AA, record final" — a real step, not a placeholder. Pane subtitle strings and a few button labels are quoted verbatim from spec §5. `makeAppModel` / poll-helper names in Tasks 8/17/18 say "match the existing helper" — acceptable, the helpers exist and the task says to use them.

**3. Type consistency:**
- `ThemeKind` / `Theme` — Task 2 renames both; `Theme` env value after Task 4 collapse; all later tasks use `theme.xxx` (not `theme.skin.xxx` / `theme.style.xxx`).
- `AudioFormat` / `MediaType` — Task 3 creates them; Tasks 5, 12, 14, 18 consume the same names; `DownloadKind.audio(format:)` consistent across 3, 7, 8, 18.
- `Preferences` field names — Task 4 renames; Tasks 5, 6, 12, 14, 15, 16, 17, 18 all use the post-rename names (`defaultDownloadFolder`, `defaultVideoHeight`, `defaultAudioFormat`, `filenameTemplate`, `maxAutoRetries`, `defaultMediaType`, `theme`).
- `speedLimitKBps: Int` default `0` — consistent Tasks 5, 7, 16.
- `GlobalDownloadOptions(proxyURL:forceIPv4:speedLimitKBps:)` — same signature Tasks 7, 8.
- `PreferencesPane` cases — same Tasks 9, 13.
- `shouldShowConcurrencyNote(newValue:runningCount:)` — Tasks 12, 14.
- `FileNamingPreset` cases + `.matching` / `.template` / `.exampleSubtitle` / `.rowLabel` — Tasks 12, 14.
- `runwaySeed(from:)` / `RunwaySeed` fields (`mediaType`, `videoHeight`, `audioFormat`, `downloadFolder`) — Tasks 12, 18.
- `Preferences.resetToDefaults()` (model) ← `AppModel.resetAllSettings()` (wrapper) — Tasks 6, 17.
- Quality ladder tuple identical — Tasks 1, 14, 18.
- `ConfirmationRequest.init` labels — Task 17 verifies against `Confirming.swift`.

**Ordering note:** Tasks 2→3→4 are the rename sweep and must run in that order (each builds green on the previous). Task 13's shell references pane types built in 14–17 — the plan says stub-then-fill with a green gate between tasks. Task 1 (screens.html) is independent and first so it's the reference for 10–18.

---

## Execution Handoff

**Plan complete and saved to `docs/superpowers/plans/2026-08-31-media-grabber-phase-3.md`. Two execution options:**

**1. Subagent-Driven (recommended)** — a fresh subagent per task, review between tasks, fast iteration.

**2. Inline Execution** — tasks in this session via executing-plans, batch execution with checkpoints.

Per the user's stated sequence: Task 1 (`screens.html`) is done and reviewed **first**, in its own thread, before Tasks 2–19 (code) begin.
