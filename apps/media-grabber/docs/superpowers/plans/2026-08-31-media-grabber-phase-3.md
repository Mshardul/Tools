# Preferences Screen (Phase 3) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build the in-app 7-pane Preferences page over the `Preferences` model, plus the two reusable skinned form controls (`SkinnedSegment`, `SkinnedPicker`) that also replace the native `Menu` dropdowns on the Home runway.

**Architecture:** `PreferencesView` is a plain SwiftUI page in the App target, selected by `AppModel.page`, reading/writing the `@Observable Preferences` model directly — every consumer (runway, engine `cap`, `Skin`/`Palette` resolution) already binds that model live, so an edit re-themes and re-defaults the app with no extra plumbing. One file per pane. `PrefRow` is the shared field primitive; panes are declarative lists of rows. The two controls `import SwiftUI` only, generic over the option type, no `GrabberKit`. `GlobalDownloadOptions` is a new value type in `GrabberKit` beside `YtDlpArguments`; the engine builds it from `preferences` at spawn time.

**Tech Stack:** Swift 6, SwiftUI, `@Observable`, Tuist project, XCTest, `UserDefaults`-backed model, `NSOpenPanel` / `NSWorkspace` for folder actions.

**Spec:** `docs/superpowers/specs/2026-08-31-media-grabber-phase-3.md` (parent design `docs/superpowers/specs/2026-08-28-youtube-downloader-mac-design.md` §12.1).

## Global Constraints

- **Deployment target macOS 14.** `Synchronization.Mutex` needs macOS 15 — banned. `NSLock.lock()/.unlock()` banned in async contexts.
- **Comments: single-line only, only to explain *why*, only when type/function names don't already carry it.** No `///` doc comments. No stacked `//` blocks. `// MARK:` is fine. No Task/plan references in code comments.
- **`swiftformat --lint` + `swiftlint --strict` must be clean.** Do not inline a multi-line `if` condition (`||` / `,`) — extract a named predicate function.
- **`ProcessRunner` is the ONLY place `Foundation.Process` is touched. `DownloadEngine` is the ONLY component that spawns download processes.**
- Two targets: `GrabberKit` (no SwiftUI) and `MediaGrabber` (App, SwiftUI over it). `SkinnedSegment` / `SkinnedPicker` / `PreferencesView` / panes are App-target. `GlobalDownloadOptions` + `YtDlpArguments` changes are `GrabberKit`.
- After adding/removing files: `mise exec -- tuist generate --no-open`.
- Test command: `xcodebuild -workspace MediaGrabber.xcworkspace -scheme MediaGrabber-Workspace -destination 'platform=macOS' test`. Single suite: append `-only-testing:GrabberKitTests/<Suite>` or `-only-testing:AppUnitTests/<Suite>`. Do NOT use `tuist test` when debugging (hides compiler errors).
- Lint: `mise exec -- swiftformat --lint .` and `mise exec -- swiftlint lint --strict`.
- **"Best available" video quality is stored as `Int.max`** in `defaultMaxHeight` / `lastSelectedMaxHeight`. `YtDlpArguments` needs no special case. Existing default stays `1080`.
- Quality ladder everywhere (Preferences + runway): `2160 / 1440 / 1080 / 720 / 480 / Best available`. **Drop `360`** (currently in `RunwayView.heights`).
- Panes a later phase fills (Sign-in & cookies → Phase 5, Updates → Phase 10) ship as complete headers only. No `Preferences` field, `YtDlpArguments` wiring, or control introduced here is a shape a later phase must replace (parent §12 scoping rule).
- Concurrency stepper range is **1–6** (the model clamps to `1…6`), not 1–5.

---

## File Structure

**New — App target:**

| File | Responsibility |
|---|---|
| `Sources/App/Controls/SkinnedSegment.swift` | Skinned 2–3-option segmented control, generic over `Hashable & CaseIterable`-ish option. |
| `Sources/App/Controls/SkinnedPicker.swift` | Skinned trigger button + popover list, generic over the option type. |
| `Sources/App/Preferences/PreferencesView.swift` | The page: left rail + selected-pane switch. Holds `@State selectedPane`. |
| `Sources/App/Preferences/PreferencesPane.swift` | `enum PreferencesPane`: cases, titles, subs, rail group; deep-link target. |
| `Sources/App/Preferences/PrefRow.swift` | Shared `label + helper` (left) / `control` (right) two-column row + `--hair` divider. Also the pane title/sub/rule header helper. |
| `Sources/App/Preferences/FileNamingPreset.swift` | `enum FileNamingPreset` (not persisted): preset ↔ `outputTemplate` string mapping. |
| `Sources/App/Preferences/ConcurrencyNote.swift` | `shouldShowConcurrencyNote(newValue:runningCount:) -> Bool` pure function + the inline note view. |
| `Sources/App/Preferences/Panes/DownloadsPane.swift` | Downloads pane rows. |
| `Sources/App/Preferences/Panes/AppearancePane.swift` | Appearance pane rows + palette swatch view. |
| `Sources/App/Preferences/Panes/NetworkPane.swift` | Network pane rows. |
| `Sources/App/Preferences/Panes/SignInCookiesPane.swift` | Header-only. |
| `Sources/App/Preferences/Panes/UpdatesPane.swift` | Header-only. |
| `Sources/App/Preferences/Panes/LogsPrivacyPane.swift` | Logs & privacy pane rows. |
| `Sources/App/Preferences/Panes/AdvancedPane.swift` | Advanced pane rows. |

**New — GrabberKit:**

| File | Responsibility |
|---|---|
| `Sources/GrabberKit/Download/GlobalDownloadOptions.swift` | `struct GlobalDownloadOptions: Sendable, Equatable` — proxy / IPv4 / rate-limit. |

**Modified:**

| File | Change |
|---|---|
| `Sources/GrabberKit/Model/Preferences.swift` | Promote `KindSelector` to public; add 7 new fields (§3). |
| `Sources/GrabberKit/Download/YtDlpArguments.swift` | `build` / `redacted` gain `options: GlobalDownloadOptions = .none`; append proxy / `-4` / `--limit-rate`; `redacted` masks proxy userinfo. |
| `Sources/GrabberKit/Download/DownloadEngine.swift` | Build `GlobalDownloadOptions` from `preferences` at spawn, pass to `build(for:options:)`. |
| `Sources/App/AppModel.swift` | `Page.preferences` gains associated `PreferencesPane = .downloads`; `grab(...)` writes `lastSelected*`. |
| `Sources/App/MainWindow.swift` | `page` switch renders `PreferencesView`; nav button targets `.preferences()`. |
| `Sources/App/Home/RunwayView.swift` | Type / Format / Save-to slots → `SkinnedSegment` / `SkinnedPicker`; drop `360`, add "Best available". |
| `Sources/App/Home/HomeView.swift` | `seedFromPrefs` reads `lastSelected*` with fallback; pass `KindSelector` from `GrabberKit`. |
| `Sources/App/Rows/RequestBuilder.swift` | (only if `RunwayOverrides` needs `audioCodec` / `maxHeight` carried explicitly — see Task 12). |
| `apps/media-grabber/docs/design-system.md` | §4.6 rewrite, new §4.9 / §4.10, §4.2.2 note, §5.2 `--warn` darken, §3.4 confirm. |
| `apps/media-grabber/docs/mockups/screens.html` | Phase 3 depiction (§8.2). |
| Parent spec `§12.1` / `§12.2` / Phase 7 stub | DoD doc updates. |

---

## Task 1: Mockup + design-system doc updates

Mechanical, low-risk, single-file-at-a-time doc work. No code. Do this first so the visual target is locked before building.

**Files:**
- Modify: `apps/media-grabber/docs/mockups/screens.html`
- Modify: `apps/media-grabber/docs/design-system.md`

**Interfaces:**
- Consumes: nothing.
- Produces: the locked control specs later tasks implement against (§4.9 `SkinnedSegment`, §4.10 `SkinnedPicker`, §4.6 pane layout). No code symbols.

- [ ] **Step 1: Update `screens.html` — Screen 6 Downloads pane**

Work within the file's existing `<style>` token system (`.field2` / `.fl` / `.fc` / `.stepper` classes) — **do not import the brainstorm mockup CSS**. In the Screen 6 "Preferences — Downloads pane" `.app` block:
- Add an "If a download fails, try" row (stepper 1–5) after "At the same time".
- Add the concurrency note markup in the "At the same time" row's right column: a small line with a warn glyph + `--dim` text `"2 running at the old limit — restart to apply now."`.
- Render Type / Quality / Audio-format / File-naming as the skinned segment / skinned-picker style (styled `<div>`s matching `skinned-picker-v2.html` / `appearance-swatch-final.html` visual language), not native `<select>` / `<input>`.

- [ ] **Step 2: Update `screens.html` — Screen 6 Appearance pane**

Align helper copy and the swatch treatment to spec §5.2: split-fill `--accent` / `--accent-2` tile ~38px, palette name underneath, selected swatch gets a 2px `--accent` outline with 2px offset. Show only the 3 palettes of the selected skin.

- [ ] **Step 3: Update `screens.html` — add Network / Sign-in & cookies / Updates / Logs & privacy / Advanced panes**

Add as sibling `.app` blocks after Appearance, one per pane, keeping the file's existing screen numbering and section-comment style:
- Network (spec §5.3): Proxy text field, "Use IPv4 only" toggle, "Limit download speed" stepper with "Off".
- Sign-in & cookies (header-only): title + sub + `"Filled in Phase 5 — browser picker, Firefox profile, Full Disk Access, tip text."`
- Updates (header-only): title + sub + `"Filled in Phase 10 — yt-dlp / ffmpeg / app versions, check buttons, daily-check toggle."`
- Logs & privacy (spec §5.6): "Open log folder" button, "Detailed logging" toggle, "What's in the logs" View button.
- Advanced (spec §5.7): "Open app data folder", "Reset table columns", "Reset all settings" (`--danger`) buttons.

- [ ] **Step 4: Update `screens.html` — Screens 0–2 (Home) runway**

Show the runway Type / Format / Save-to slots as `SkinnedSegment` / `SkinnedPicker` style, replacing the native-dropdown depiction. Save-to picker shows default + last-used (if distinct) + "Choose…". Show both skins where the file already shows both. Quality ladder drops `360`, adds "Best available".

- [ ] **Step 5: Rewrite `design-system.md` §4.6 Preferences**

Replace §4.6 to match spec §5: two-column row layout (`label` 13/`--text`/semibold + `helper` 11.5/`--dim` stacked left; control right-aligned; `--hair` divider between rows), page title 20/heavy in `--headline` with a rule under it and a one-line `--dim` sub above the rule, fixed window height with the right pane scrolling independently. Rail groups: **General** (Downloads · Appearance · Network), **YouTube** (Sign-in & cookies), **System** (Updates · Logs & privacy · Advanced). Per-pane row tables with the locked controls from spec §5.1–5.7. Header-only Sign-in / Updates. Advanced buttons. The concurrency note. Fix the concurrency stepper range to **1–6**. Update the "New `Preferences` fields this section introduces" line to list the §3 fields.

- [ ] **Step 6: Add `design-system.md` §4.9 `SkinnedSegment`**

New subsection after §4.8, per spec §4.1: 2–3 options all rendered as segments in a `--panel` track with `--stroke` border; selected segment gets a `--panel-solid` fill; one tap selects, no popover; Left/Right moves selection when focused; VoiceOver exposes a radio group / segmented control with option labels; track / border / selected-fill are skin tokens; radius is the skin's `chipRadius`. Note used by: Skin (Appearance), Default type (Downloads + runway), Default audio format (Downloads + runway).

- [ ] **Step 7: Add `design-system.md` §4.10 `SkinnedPicker`**

New subsection, per spec §4.2 (reference `assets/2026-08-31-media-grabber-phase-3/skinned-picker-v2.html`): trigger button (current label + chevron, `--panel` fill, `--stroke` border, skin `controlRadius`); popover opens below trigger, flips above if no room, `--panel-solid` fill, skin border + `cardRadius` + elevation (glow on Aurora, hard shadow on Tape Deck) matching the confirmation-dialog card; caption header (`--faint` uppercase label + hairline rule under it); rows (label; optional `--dim` second-line subtitle, `nil` → single-line; `--accent` checkmark on selected; hover / arrow-key highlight = translucent accent wash); no row icons; keyboard Return/Space opens, Up/Down moves highlight, Return selects, Esc closes unchanged; VoiceOver menu/pop-up button, popover traps focus, selected row announced; no scroll cap this phase (every list ≤ 6 rows). Note used by: Default video quality (Downloads + runway), File naming (Downloads), Save to (runway).

- [ ] **Step 8: Update `design-system.md` §4.2.2**

Add a note that the runway's Type / Format / Save-to slots now use `SkinnedSegment` / `SkinnedPicker`, not native `Menu`.

- [ ] **Step 9: Darken Tape Deck `--warn` in `design-system.md` §5.2**

Replace the three Tape Deck `--warn` values (`#E4A11B` / `#E8B24A` / `#F2B12E`) with darker ambers chosen against a WCAG AA check for normal text on each palette's `--panel-solid` (spec suggests ≈ `#9C5A00` / `#9A6410` / `#8E6318` — verify each against AA and record the final value). **Only the `--warn` rows** — leave the `--go` rows (which currently share the same hex) unchanged. Aurora `--warn` unchanged. Add a one-line note that this also affects future `--warn`-as-text uses (Phase 6 cooldown copy).

- [ ] **Step 10: Confirm §3.4 warn glyph reuse**

In §3.4, confirm (a sentence) the warn glyph the confirmation dialog already references is reused for the concurrency note; no new glyph is added.

- [ ] **Step 11: Commit**

```bash
git add apps/media-grabber/docs/mockups/screens.html apps/media-grabber/docs/design-system.md
git commit -m "docs: phase 3 preferences design — panes, SkinnedSegment/SkinnedPicker, Tape Deck --warn"
```

---

## Task 2: `Preferences` — promote `KindSelector`, add new fields

**Files:**
- Modify: `Sources/GrabberKit/Model/Preferences.swift`
- Test: `Tests/GrabberKitTests/PreferencesTests.swift`

**Interfaces:**
- Consumes: existing `Preferences` helpers (`intValue(forKey:default:)`, `url(forKey:default:)`, `defaults`).
- Produces:
  - `public enum KindSelector: String, Codable, Sendable, CaseIterable { case video, audio }` (top-level in the file, not nested).
  - `Preferences.clipboardAutoDetect: Bool` (default `true`)
  - `Preferences.proxyURL: String?` (trimmed; empty → `nil`)
  - `Preferences.forceIPv4: Bool` (default `false`)
  - `Preferences.selfRateLimitKBps: Int?` (`nil` = Off; clamped `1…100000` when set)
  - `Preferences.lastSelectedMaxHeight: Int?` (`nil` default; `Int.max` valid)
  - `Preferences.lastSelectedKind: KindSelector?` (`nil` default)
  - `Preferences.lastSelectedAudioCodec: AudioCodec?` (`nil` default)
  - `Preferences.defaultAudioOrVideo: KindSelector` becomes **`public`** (was `private`) — the runway seed reads it.

- [ ] **Step 1: Write failing tests for the new fields**

Add to `PreferencesTests.swift`:

```swift
func test_newFieldDefaults() {
    let prefs = Preferences(defaults: defaults)
    XCTAssertTrue(prefs.clipboardAutoDetect)
    XCTAssertNil(prefs.proxyURL)
    XCTAssertFalse(prefs.forceIPv4)
    XCTAssertNil(prefs.selfRateLimitKBps)
    XCTAssertNil(prefs.lastSelectedMaxHeight)
    XCTAssertNil(prefs.lastSelectedKind)
    XCTAssertNil(prefs.lastSelectedAudioCodec)
}

func test_proxyURL_emptyStringStoresNil() {
    let prefs = Preferences(defaults: defaults)
    prefs.proxyURL = "  "
    XCTAssertNil(Preferences(defaults: defaults).proxyURL)
    prefs.proxyURL = " http://h:1 "
    XCTAssertEqual(Preferences(defaults: defaults).proxyURL, "http://h:1")
}

func test_selfRateLimitKBps_clampBounds() {
    let prefs = Preferences(defaults: defaults)
    prefs.selfRateLimitKBps = 0
    XCTAssertEqual(prefs.selfRateLimitKBps, 1)
    prefs.selfRateLimitKBps = 999_999
    XCTAssertEqual(prefs.selfRateLimitKBps, 100_000)
    prefs.selfRateLimitKBps = nil
    XCTAssertNil(prefs.selfRateLimitKBps)
}

func test_lastSelected_roundTripIncludingIntMax() {
    let prefs = Preferences(defaults: defaults)
    prefs.lastSelectedMaxHeight = .max
    prefs.lastSelectedKind = .audio
    prefs.lastSelectedAudioCodec = .mp3
    let reloaded = Preferences(defaults: defaults)
    XCTAssertEqual(reloaded.lastSelectedMaxHeight, .max)
    XCTAssertEqual(reloaded.lastSelectedKind, .audio)
    XCTAssertEqual(reloaded.lastSelectedAudioCodec, .mp3)
}
```

- [ ] **Step 2: Run the tests, verify they fail**

Run: `xcodebuild -workspace MediaGrabber.xcworkspace -scheme MediaGrabber-Workspace -destination 'platform=macOS' test -only-testing:GrabberKitTests/PreferencesTests`
Expected: FAIL — `clipboardAutoDetect` / `proxyURL` / etc. not members of `Preferences`.

- [ ] **Step 3: Promote `KindSelector` and implement the fields**

In `Preferences.swift`: move `KindSelector` out to a top-level `public enum KindSelector: String, Codable, Sendable, CaseIterable { case video, audio }`. Make `defaultAudioOrVideo` `public`. Add:

```swift
// MARK: - Clipboard

public var clipboardAutoDetect: Bool {
    get { defaults.object(forKey: "mg.clipboardAutoDetect") == nil ? true : defaults.bool(forKey: "mg.clipboardAutoDetect") }
    set { defaults.set(newValue, forKey: "mg.clipboardAutoDetect") }
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

public var selfRateLimitKBps: Int? {
    get {
        guard defaults.object(forKey: "mg.selfRateLimitKBps") != nil else { return nil }
        return defaults.integer(forKey: "mg.selfRateLimitKBps")
    }
    set {
        guard let value = newValue else { defaults.removeObject(forKey: "mg.selfRateLimitKBps"); return }
        defaults.set(min(100_000, max(1, value)), forKey: "mg.selfRateLimitKBps")
    }
}

// MARK: - Runway last-selected

public var lastSelectedMaxHeight: Int? {
    get {
        guard defaults.object(forKey: "mg.lastSelectedMaxHeight") != nil else { return nil }
        return defaults.integer(forKey: "mg.lastSelectedMaxHeight")
    }
    set {
        guard let value = newValue else { defaults.removeObject(forKey: "mg.lastSelectedMaxHeight"); return }
        defaults.set(value, forKey: "mg.lastSelectedMaxHeight")
    }
}

public var lastSelectedKind: KindSelector? {
    get { defaults.string(forKey: "mg.lastSelectedKind").flatMap(KindSelector.init) }
    set {
        guard let value = newValue else { defaults.removeObject(forKey: "mg.lastSelectedKind"); return }
        defaults.set(value.rawValue, forKey: "mg.lastSelectedKind")
    }
}

public var lastSelectedAudioCodec: AudioCodec? {
    get { defaults.string(forKey: "mg.lastSelectedAudioCodec").flatMap(AudioCodec.init) }
    set {
        guard let value = newValue else { defaults.removeObject(forKey: "mg.lastSelectedAudioCodec"); return }
        defaults.set(value.rawValue, forKey: "mg.lastSelectedAudioCodec")
    }
}
```

Note: `defaults.integer(forKey:)` round-trips `Int.max` correctly (`UserDefaults` stores it as `NSNumber`).

- [ ] **Step 4: Run the tests, verify they pass**

Run: `xcodebuild ... test -only-testing:GrabberKitTests/PreferencesTests`
Expected: PASS (all, including pre-existing).

- [ ] **Step 5: Fix any `private KindSelector` compile fallout**

`tuist generate --no-open` not needed (no new files). Build the workspace; the promotion may surface `KindSelector` name clashes with `RunwayView.KindSelector` — leave `RunwayView` for Task 11, it still compiles as a distinct nested type for now.

- [ ] **Step 6: Lint + commit**

```bash
mise exec -- swiftformat --lint . && mise exec -- swiftlint lint --strict
git add Sources/GrabberKit/Model/Preferences.swift Tests/GrabberKitTests/PreferencesTests.swift
git commit -m "feat: Preferences new fields + promote KindSelector to public"
```

---

## Task 3: `GlobalDownloadOptions`

**Files:**
- Create: `Sources/GrabberKit/Download/GlobalDownloadOptions.swift`
- Test: `Tests/GrabberKitTests/ValueTypesTests.swift` (append) — or a new `GlobalDownloadOptionsTests.swift`

**Interfaces:**
- Consumes: nothing.
- Produces:

```swift
public struct GlobalDownloadOptions: Sendable, Equatable {
    public var proxyURL: String?
    public var forceIPv4: Bool
    public var rateLimitKBps: Int?
    public init(proxyURL: String?, forceIPv4: Bool, rateLimitKBps: Int?)
    public static let none: GlobalDownloadOptions
}
```

- [ ] **Step 1: Write the failing test**

Create `Tests/GrabberKitTests/GlobalDownloadOptionsTests.swift`:

```swift
@testable import GrabberKit
import XCTest

final class GlobalDownloadOptionsTests: XCTestCase {
    func test_none_isAllEmpty() {
        let none = GlobalDownloadOptions.none
        XCTAssertNil(none.proxyURL)
        XCTAssertFalse(none.forceIPv4)
        XCTAssertNil(none.rateLimitKBps)
    }

    func test_equatable() {
        XCTAssertEqual(GlobalDownloadOptions.none, GlobalDownloadOptions(proxyURL: nil, forceIPv4: false, rateLimitKBps: nil))
        XCTAssertNotEqual(GlobalDownloadOptions.none, GlobalDownloadOptions(proxyURL: "http://h:1", forceIPv4: false, rateLimitKBps: nil))
    }
}
```

- [ ] **Step 2: Run, verify it fails**

Run: `xcodebuild ... test -only-testing:GrabberKitTests/GlobalDownloadOptionsTests`
Expected: FAIL — `GlobalDownloadOptions` undefined.

- [ ] **Step 3: Create the type**

```swift
import Foundation

public struct GlobalDownloadOptions: Sendable, Equatable {
    public var proxyURL: String?
    public var forceIPv4: Bool
    public var rateLimitKBps: Int?

    public init(proxyURL: String?, forceIPv4: Bool, rateLimitKBps: Int?) {
        self.proxyURL = proxyURL
        self.forceIPv4 = forceIPv4
        self.rateLimitKBps = rateLimitKBps
    }

    public static let none = GlobalDownloadOptions(
        proxyURL: nil, forceIPv4: false, rateLimitKBps: nil
    )
}
```

- [ ] **Step 4: Regenerate project, run, verify pass**

Run: `mise exec -- tuist generate --no-open` then `xcodebuild ... test -only-testing:GrabberKitTests/GlobalDownloadOptionsTests`
Expected: PASS.

- [ ] **Step 5: Lint + commit**

```bash
mise exec -- swiftformat --lint . && mise exec -- swiftlint lint --strict
git add Sources/GrabberKit/Download/GlobalDownloadOptions.swift Tests/GrabberKitTests/GlobalDownloadOptionsTests.swift
git commit -m "feat: GlobalDownloadOptions value type"
```

---

## Task 4: `YtDlpArguments` — `options:` parameter + proxy redaction

**Files:**
- Modify: `Sources/GrabberKit/Download/YtDlpArguments.swift`
- Test: `Tests/GrabberKitTests/YtDlpArgumentsTests.swift`

**Interfaces:**
- Consumes: `GlobalDownloadOptions` (Task 3), `DownloadRequest`.
- Produces:

```swift
public static func build(for request: DownloadRequest, options: GlobalDownloadOptions = .none) -> [String]
public static func redacted(for request: DownloadRequest, options: GlobalDownloadOptions = .none) -> [String]
```

Flag rules:
- `--proxy <url>` appended when `options.proxyURL` is non-nil and non-empty.
- `-4` appended when `options.forceIPv4`.
- `--limit-rate <N>K` appended when `options.rateLimitKBps != nil && > 0`.
- `redacted` masks `user:pass@` userinfo in the proxy URL to `***:***@` (or `***@`); identical to `build` in every other respect.

- [ ] **Step 1: Write failing tests**

Add to `YtDlpArgumentsTests.swift`:

```swift
func test_options_none_emitsNoGlobalFlags() {
    let argv = YtDlpArguments.build(for: request(kind: .video(maxHeight: 1080)))
    XCTAssertFalse(argv.contains("--proxy"))
    XCTAssertFalse(argv.contains("-4"))
    XCTAssertFalse(argv.contains("--limit-rate"))
}

func test_options_proxy_emitsFlag() {
    let opts = GlobalDownloadOptions(proxyURL: "http://host:8080", forceIPv4: false, rateLimitKBps: nil)
    let argv = YtDlpArguments.build(for: request(kind: .audio(codec: .m4a)), options: opts)
    XCTAssertTrue(hasSubsequence(argv, ["--proxy", "http://host:8080"]))
}

func test_options_forceIPv4_emitsDash4() {
    let opts = GlobalDownloadOptions(proxyURL: nil, forceIPv4: true, rateLimitKBps: nil)
    XCTAssertTrue(YtDlpArguments.build(for: request(kind: .audio(codec: .m4a)), options: opts).contains("-4"))
}

func test_options_rateLimit_emitsKSuffix() {
    let opts = GlobalDownloadOptions(proxyURL: nil, forceIPv4: false, rateLimitKBps: 500)
    XCTAssertTrue(hasSubsequence(YtDlpArguments.build(for: request(kind: .audio(codec: .m4a)), options: opts), ["--limit-rate", "500K"]))
}

func test_options_rateLimit_omittedWhenZeroOrNegative() {
    for value in [0, -1] {
        let opts = GlobalDownloadOptions(proxyURL: nil, forceIPv4: false, rateLimitKBps: value)
        XCTAssertFalse(YtDlpArguments.build(for: request(kind: .audio(codec: .m4a)), options: opts).contains("--limit-rate"))
    }
}

func test_redacted_masksProxyUserinfo() {
    let opts = GlobalDownloadOptions(proxyURL: "http://user:secret@host:8080", forceIPv4: false, rateLimitKBps: nil)
    let redacted = YtDlpArguments.redacted(for: request(kind: .audio(codec: .m4a)), options: opts)
    let i = redacted.firstIndex(of: "--proxy")!
    XCTAssertFalse(redacted[i + 1].contains("secret"))
    XCTAssertFalse(redacted[i + 1].contains("user:"))
    XCTAssertTrue(redacted[i + 1].contains("host:8080"))
}

func test_redacted_identicalToBuild_whenNoProxyCreds() {
    let opts = GlobalDownloadOptions(proxyURL: "http://host:8080", forceIPv4: true, rateLimitKBps: 200)
    XCTAssertEqual(
        YtDlpArguments.redacted(for: request(kind: .video(maxHeight: 720)), options: opts),
        YtDlpArguments.build(for: request(kind: .video(maxHeight: 720)), options: opts)
    )
}
```

- [ ] **Step 2: Run, verify fail**

Run: `xcodebuild ... test -only-testing:GrabberKitTests/YtDlpArgumentsTests`
Expected: FAIL — `build` has no `options:` label.

- [ ] **Step 3: Implement**

```swift
public static func build(for request: DownloadRequest, options: GlobalDownloadOptions = .none) -> [String] {
    var argv: [String] = []
    argv += ["-P", request.destFolder.path]
    argv += ["-o", request.outputTemplate]
    argv += formatSelector(for: request)
    argv += ["--newline", "--progress", "--progress-template", progressTemplate]
    argv += ["--no-playlist"]
    argv += ["--no-warnings"]
    argv += globalOptionFlags(options, proxyURL: options.proxyURL)
    argv += [request.url]
    return argv
}

public static func redacted(for request: DownloadRequest, options: GlobalDownloadOptions = .none) -> [String] {
    var argv: [String] = []
    argv += ["-P", request.destFolder.path]
    argv += ["-o", request.outputTemplate]
    argv += formatSelector(for: request)
    argv += ["--newline", "--progress", "--progress-template", progressTemplate]
    argv += ["--no-playlist"]
    argv += ["--no-warnings"]
    argv += globalOptionFlags(options, proxyURL: options.proxyURL.map(maskUserinfo))
    argv += [request.url]
    return argv
}

private static func globalOptionFlags(_ options: GlobalDownloadOptions, proxyURL: String?) -> [String] {
    var flags: [String] = []
    if let proxy = proxyURL, !proxy.isEmpty {
        flags += ["--proxy", proxy]
    }
    if options.forceIPv4 {
        flags += ["-4"]
    }
    if let rate = options.rateLimitKBps, rate > 0 {
        flags += ["--limit-rate", "\(rate)K"]
    }
    return flags
}

private static func maskUserinfo(in url: String) -> String {
    guard let atIndex = url.firstIndex(of: "@"),
          let schemeRange = url.range(of: "://")
    else { return url }
    let afterScheme = schemeRange.upperBound
    guard afterScheme < atIndex else { return url }
    return String(url[..<afterScheme]) + "***@" + String(url[url.index(after: atIndex)...])
}
```

Extract the shared body into a private helper if `swiftformat` / duplication review flags it — but the two public funcs reading identically apart from one argument is acceptable and matches the spec's "otherwise identical" wording. If deduplicating, keep the public signatures exactly as the Interfaces block specifies.

Note: `maskUserinfo` is a free function name — call it `maskUserinfo(in:)` consistently.

- [ ] **Step 4: Run, verify pass**

Run: `xcodebuild ... test -only-testing:GrabberKitTests/YtDlpArgumentsTests`
Expected: PASS (including the pre-existing `test_redactedEqualsBuild_phase1` — it calls the no-arg form, `.none` default keeps it green).

- [ ] **Step 5: Lint + commit**

```bash
mise exec -- swiftformat --lint . && mise exec -- swiftlint lint --strict
git add Sources/GrabberKit/Download/YtDlpArguments.swift Tests/GrabberKitTests/YtDlpArgumentsTests.swift
git commit -m "feat: YtDlpArguments global options + proxy userinfo redaction"
```

---

## Task 5: `DownloadEngine` passes `GlobalDownloadOptions` at spawn

**Files:**
- Modify: `Sources/GrabberKit/Download/DownloadEngine.swift:261` (the `YtDlpArguments.build(for: request)` call in `launchDownload`)
- Test: `Tests/GrabberKitTests/EngineJobLogTests.swift` — or a focused new test; see Step 1

**Interfaces:**
- Consumes: `preferences.proxyURL` / `.forceIPv4` / `.selfRateLimitKBps` (Task 2), `GlobalDownloadOptions` (Task 3), `YtDlpArguments.build(for:options:)` (Task 4).
- Produces: nothing new; behavior change only — the spawned `yt-dlp` argv now carries the global flags.

- [ ] **Step 1: Write the failing test**

The engine's spawned argv is observable through `FakeProcessRunner` (it records `ProcessLaunch`). Check the existing engine test helpers for how `ProcessLaunch.arguments` is captured (`Tests/GrabberKitTests/DownloadEngineTestHelpers.swift`, `Tests/TestSupport/FakeProcessRunner.swift`). Add a test that sets `preferences.proxyURL = "http://p:1"`, submits a job, waits for it to reach `.running`, and asserts the recorded launch's `arguments` contains `["--proxy", "http://p:1"]`.

```swift
@MainActor
func test_spawnedArgv_carriesGlobalOptions() async throws {
    let prefs = Preferences(defaults: makeDefaults())
    prefs.forceIPv4 = true
    let (engine, runner) = makeEngine(preferences: prefs)   // match the helper's actual signature
    _ = await engine.submit(sampleRequest(), force: false, prefetchedMetadata: nil)
    try await pollUntil { runner.launches.contains { $0.arguments.contains("-4") } }
}
```

Adapt names to the real helpers (`makeEngine`, `FakeProcessRunner` accessor for recorded launches, the poll helper). If no poll helper exists, follow the `@MainActor` + poll-until-terminal pattern from CLAUDE.md and the existing `DownloadEngineLiveTests`.

- [ ] **Step 2: Run, verify fail**

Run: `xcodebuild ... test -only-testing:GrabberKitTests/<the suite you added it to>`
Expected: FAIL — argv has no `-4`.

- [ ] **Step 3: Implement**

In `DownloadEngine.launchDownload(id:)`, before building the `Task`:

```swift
let options = GlobalDownloadOptions(
    proxyURL: preferences.proxyURL,
    forceIPv4: preferences.forceIPv4,
    rateLimitKBps: preferences.selfRateLimitKBps
)
```

Capture `options` (a `Sendable` value) into the `Task` and change line 261 to:

```swift
arguments: YtDlpArguments.build(for: request, options: options)
```

`preferences` is not `Sendable`-safe to touch inside the `Task` — read all three fields into the local `options` value **before** the `Task { }` (same pattern as `let request = job.request`).

- [ ] **Step 4: Run, verify pass**

Run the suite from Step 2, plus the full `GrabberKitTests/DownloadEngine*` set to confirm no regression.
Expected: PASS.

- [ ] **Step 5: Lint + commit**

```bash
mise exec -- swiftformat --lint . && mise exec -- swiftlint lint --strict
git add Sources/GrabberKit/Download/DownloadEngine.swift Tests/GrabberKitTests/
git commit -m "feat: DownloadEngine passes global download options to yt-dlp"
```

---

## Task 6: `PreferencesPane` enum + deep-link on `AppModel.Page`

**Files:**
- Create: `Sources/App/Preferences/PreferencesPane.swift`
- Modify: `Sources/App/AppModel.swift:36-40` (the `Page` enum)
- Modify: `Sources/App/MainWindow.swift` (nav button target + `page` switch — minimal, full `PreferencesView` wiring is Task 10)
- Test: `Tests/AppUnitTests/AppModelTests.swift` (append) or a new `PreferencesPaneTests.swift`

**Interfaces:**
- Consumes: nothing.
- Produces:

```swift
enum PreferencesPane: String, CaseIterable, Hashable {
    case downloads, appearance, network, cookies, updates, logsPrivacy, advanced

    var title: String          // "Downloads", "Appearance", "Network", "Sign-in & cookies", "Updates", "Logs & privacy", "Advanced"
    var subtitle: String       // one-line --dim sub shown above the title rule
    var group: PreferencesRailGroup   // .general / .youtube / .system
}

enum PreferencesRailGroup: String, CaseIterable, Hashable {
    case general, youtube, system
    var caption: String        // "General" / "YouTube" / "System"
    var panes: [PreferencesPane]   // ordered
}
```

And `AppModel.Page` becomes:

```swift
enum Page: Equatable {
    case home
    case preferences(PreferencesPane = .downloads)
    case diagnostics
}
```

- [ ] **Step 1: Write failing tests**

Create `Tests/AppUnitTests/PreferencesPaneTests.swift`:

```swift
@testable import MediaGrabber
import XCTest

final class PreferencesPaneTests: XCTestCase {
    func test_railGroups_coverEveryPaneOnce() {
        let all = PreferencesRailGroup.allCases.flatMap(\.panes)
        XCTAssertEqual(Set(all), Set(PreferencesPane.allCases))
        XCTAssertEqual(all.count, PreferencesPane.allCases.count)
    }

    func test_railGroupOrder() {
        XCTAssertEqual(PreferencesRailGroup.general.panes, [.downloads, .appearance, .network])
        XCTAssertEqual(PreferencesRailGroup.youtube.panes, [.cookies])
        XCTAssertEqual(PreferencesRailGroup.system.panes, [.updates, .logsPrivacy, .advanced])
    }

    func test_pageDeepLinkDefaultsToDownloads() {
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
Expected: FAIL — types undefined; `.preferences()` takes no argument.

- [ ] **Step 3: Create `PreferencesPane.swift`**

Implement the two enums per the Interfaces block. `title` / `subtitle` are `switch self`. `subtitle` copy (from spec §5 / §5.4 / §5.5), one line each — e.g. Downloads: `"Where files go, how many at once, and default formats."`; Cookies: `"Sign in to download age-restricted or private videos."`; Updates: `"Keep the downloader and app current."` (author reasonable one-liners in the app's plain-language voice; they are `--dim` subs, not helper text).

- [ ] **Step 4: Update `AppModel.Page`**

Add `: Equatable` to `Page` (it currently has no conformance — the tests and `MainWindow`'s `page.wrappedValue == value` need it; `PreferencesPane` is `Hashable` so the associated-value synthesis works). Change the `preferences` case to `case preferences(PreferencesPane = .downloads)`.

- [ ] **Step 5: Fix `MainWindow` fallout**

`navButton("Preferences", .preferences, page)` → `.preferences()`. The `active` check `page.wrappedValue == value` for the Preferences button should treat any `.preferences(_)` as active — change to a helper:

```swift
private func isActive(_ page: AppModel.Page, _ target: AppModel.Page) -> Bool {
    switch (page, target) {
    case (.preferences, .preferences): true
    default: page == target
    }
}
```

In the `page` switch, `case .preferences:` → `case .preferences:` still matches (ignores the value) — keep the `placeholder("Preferences")` for now; Task 10 swaps it.

- [ ] **Step 6: Regenerate, run, verify pass**

Run: `mise exec -- tuist generate --no-open` then `xcodebuild ... test -only-testing:AppUnitTests/PreferencesPaneTests` and `-only-testing:AppUnitTests/AppModelTests`.
Expected: PASS.

- [ ] **Step 7: Lint + commit**

```bash
mise exec -- swiftformat --lint . && mise exec -- swiftlint lint --strict
git add Sources/App/Preferences/PreferencesPane.swift Sources/App/AppModel.swift Sources/App/MainWindow.swift Tests/AppUnitTests/PreferencesPaneTests.swift
git commit -m "feat: PreferencesPane enum + deep-link seam on AppModel.Page"
```

---

## Task 7: `SkinnedSegment`

**Files:**
- Create: `Sources/App/Controls/SkinnedSegment.swift`
- Test: none (SwiftUI view rendering is explicitly not unit-tested — spec §9 "Not tested"). Verified by the manual smoke checklist (Task 16) and by compiling into the panes.

**Interfaces:**
- Consumes: `@Environment(\.theme)` (`ResolvedTheme` → `theme.skin`, `theme.palette`).
- Produces:

```swift
struct SkinnedSegment<Option: Hashable>: View {
    init(_ options: [Option], selection: Binding<Option>, label: (Option) -> String)
}
```

- All `options` rendered as segments in a `--panel` track with a `--stroke` border.
- Selected segment: `--panel-solid` fill.
- One tap sets `selection`. No popover.
- Radius = `theme.skin.chipRadius`.
- Left/Right arrow moves selection when the control is focused (`.focusable()` + `.onMoveCommand` or `onKeyPress`).
- `.accessibilityElement(children: .contain)` + each segment `.accessibilityAddTraits(.isButton)` and the selected one `.isSelected`; wrap with `.accessibilityRepresentation` as a Picker if simpler for VoiceOver to announce a segmented control.

- [ ] **Step 1: Implement `SkinnedSegment.swift`**

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
        .overlay(shape.stroke(theme.palette.stroke, lineWidth: theme.skin.hairlineWidth))
        .focusable()
        .onMoveCommand { direction in
            move(direction)
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Segmented control")
    }

    private var shape: RoundedRectangle {
        RoundedRectangle(cornerRadius: theme.skin.chipRadius)
    }

    private func segment(_ option: Option) -> some View {
        let selected = option == selection
        return Text(label(option))
            .font(theme.skin.bodyFont(12, .medium))
            .foregroundStyle(selected ? theme.palette.text : theme.palette.dim)
            .padding(.horizontal, Spacing.s3)
            .padding(.vertical, Spacing.s1)
            .frame(maxWidth: .infinity)
            .background(selected ? theme.palette.panelSolid : .clear, in: shape)
            .contentShape(Rectangle())
            .onTapGesture { selection = option }
            .accessibilityAddTraits(selected ? [.isButton, .isSelected] : .isButton)
            .accessibilityLabel(label(option))
    }

    private func move(_ direction: MoveCommandDirection) {
        guard let index = options.firstIndex(of: selection) else { return }
        switch direction {
        case .left where index > 0: selection = options[index - 1]
        case .right where index < options.count - 1: selection = options[index + 1]
        default: break
        }
    }
}
```

- [ ] **Step 2: Regenerate + build**

Run: `mise exec -- tuist generate --no-open` then build the workspace (`xcodebuild -workspace MediaGrabber.xcworkspace -scheme MediaGrabber-Workspace -destination 'platform=macOS' build`).
Expected: builds clean.

- [ ] **Step 3: Lint + commit**

```bash
mise exec -- swiftformat --lint . && mise exec -- swiftlint lint --strict
git add Sources/App/Controls/SkinnedSegment.swift
git commit -m "feat: SkinnedSegment control"
```

---

## Task 8: `SkinnedPicker`

**Files:**
- Create: `Sources/App/Controls/SkinnedPicker.swift`
- Test: none (view rendering not unit-tested; popover flip geometry explicitly excluded — spec §9).

**Interfaces:**
- Consumes: `@Environment(\.theme)`.
- Produces:

```swift
struct SkinnedPickerRow<Option: Hashable>: Identifiable {
    let id: Option
    let option: Option
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

- Trigger: button, current selection's label + chevron, `--panel` fill, `--stroke` border, `theme.skin.controlRadius`.
- Popover (`.popover` or a custom overlay — `.popover` is acceptable this phase; flip-above is its default behavior): `--panel-solid` fill, skin border + `theme.skin.cardRadius` + elevation (`theme.palette.glowA/glowB` shadow on Aurora, a hard offset shadow on Tape Deck — branch on `theme.skin`).
- Caption header: `--faint` uppercase (`.textCase(.uppercase)`), hairline `--hair` rule under it.
- Rows: `title` (`--text`); `subtitle` in `--dim` when non-nil; `--accent` checkmark on the selected row; hover / arrow-key highlight = `theme.palette.accent.opacity(0.12)` wash. No row icons.
- Keyboard: Return/Space opens; Up/Down moves highlight; Return selects highlighted + closes; Esc closes unchanged. Use `.onKeyPress` on the trigger for open, and on the popover content for navigation.
- VoiceOver: trigger `.accessibilityAddTraits(.isButton)` + `.accessibilityValue(currentLabel)`; popover content `.accessibilityElement(children: .contain)`; selected row `.isSelected`.
- No `maxVisibleRows` / scroll cap this phase.

- [ ] **Step 1: Implement `SkinnedPicker.swift`**

Build with a `@State private var isPresented = false` and `@State private var highlighted: Option?`. Trigger is a `Button { isPresented = true }` styled per spec, `.popover(isPresented: $isPresented, arrowEdge: .bottom) { popoverBody }`. `popoverBody` is a `VStack(alignment: .leading, spacing: 0)` — caption header, `Divider().overlay(theme.palette.hair)`, then `ForEach(rows) { row in rowView(row) }`. `rowView` shows an `HStack` of a leading checkmark column (fixed width, `--accent` `Image(systemName: "checkmark")` only when `row.id == selection`), a `VStack` of title + optional subtitle, `Spacer()`. `.background(highlighted == row.id ? theme.palette.accent.opacity(0.12) : .clear)`. `.onTapGesture { selection = row.id; isPresented = false }`. `.onHover { highlighted = $0 ? row.id : highlighted }`.

Keyboard on `popoverBody`: `.onKeyPress(.upArrow)` / `.onKeyPress(.downArrow)` move `highlighted` through `rows.map(\.id)`; `.onKeyPress(.return)` commits `highlighted`; `.onKeyPress(.escape)` sets `isPresented = false`. Seed `highlighted = selection` in `.onAppear` of `popoverBody`.

Elevation branch:

```swift
private var isAurora: Bool { theme.skin == .aurora }
// shadow: isAurora ? .init(color: theme.palette.glowB, radius: 20) : .init(color: .black.opacity(0.35), radius: 0, x: 3, y: 3)
```

- [ ] **Step 2: Regenerate + build**

Run: `mise exec -- tuist generate --no-open` then build the workspace.
Expected: builds clean.

- [ ] **Step 3: Lint + commit**

```bash
mise exec -- swiftformat --lint . && mise exec -- swiftlint lint --strict
git add Sources/App/Controls/SkinnedPicker.swift
git commit -m "feat: SkinnedPicker control"
```

---

## Task 9: `FileNamingPreset` + `ConcurrencyNote` predicate

**Files:**
- Create: `Sources/App/Preferences/FileNamingPreset.swift`
- Create: `Sources/App/Preferences/ConcurrencyNote.swift`
- Test: `Tests/AppUnitTests/FileNamingPresetTests.swift`, `Tests/AppUnitTests/ConcurrencyNoteTests.swift`

**Interfaces:**
- Consumes: nothing.
- Produces:

```swift
enum FileNamingPreset: CaseIterable, Hashable {
    case title, titleAndChannel, dateAndTitle, custom

    var rowLabel: String        // "Title" / "Title and channel" / "Date and title" / "Custom…"
    var template: String?       // nil for .custom
    var exampleSubtitle: String?   // the §5.1.1 example filename; nil for .custom

    static func matching(_ storedTemplate: String) -> FileNamingPreset   // string-match -> preset, else .custom
}

func shouldShowConcurrencyNote(newValue: Int, runningCount: Int) -> Bool   // newValue < runningCount
```

Templates (exact, from spec §5.1.1):
- `.title` → `%(title)s.%(ext)s`
- `.titleAndChannel` → `%(title)s - %(uploader)s.%(ext)s`
- `.dateAndTitle` → `%(upload_date>%Y-%m-%d)s - %(title)s.%(ext)s`

- [ ] **Step 1: Write failing tests**

`ConcurrencyNoteTests.swift`:

```swift
@testable import MediaGrabber
import XCTest

final class ConcurrencyNoteTests: XCTestCase {
    func test_trueOnlyWhenNewValueBelowRunning() {
        XCTAssertTrue(shouldShowConcurrencyNote(newValue: 2, runningCount: 3))
        XCTAssertFalse(shouldShowConcurrencyNote(newValue: 3, runningCount: 3))
        XCTAssertFalse(shouldShowConcurrencyNote(newValue: 4, runningCount: 3))
        XCTAssertFalse(shouldShowConcurrencyNote(newValue: 3, runningCount: 0))
    }
}
```

`FileNamingPresetTests.swift`:

```swift
@testable import MediaGrabber
import XCTest

final class FileNamingPresetTests: XCTestCase {
    func test_eachPresetMapsToItsExactTemplate() {
        XCTAssertEqual(FileNamingPreset.title.template, "%(title)s.%(ext)s")
        XCTAssertEqual(FileNamingPreset.titleAndChannel.template, "%(title)s - %(uploader)s.%(ext)s")
        XCTAssertEqual(FileNamingPreset.dateAndTitle.template, "%(upload_date>%Y-%m-%d)s - %(title)s.%(ext)s")
        XCTAssertNil(FileNamingPreset.custom.template)
    }

    func test_matching_recognisesPresetString() {
        XCTAssertEqual(FileNamingPreset.matching("%(title)s.%(ext)s"), .title)
        XCTAssertEqual(FileNamingPreset.matching("%(title)s - %(uploader)s.%(ext)s"), .titleAndChannel)
    }

    func test_matching_unrecognisedStringIsCustom() {
        XCTAssertEqual(FileNamingPreset.matching("%(id)s.%(ext)s"), .custom)
    }
}
```

- [ ] **Step 2: Run, verify fail**

Run: `xcodebuild ... test -only-testing:AppUnitTests/FileNamingPresetTests -only-testing:AppUnitTests/ConcurrencyNoteTests`
Expected: FAIL — undefined.

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
            Text("\u{26A0}\u{FE0E}")
                .foregroundStyle(theme.palette.warn)
            Text("\(runningCount) running at the old limit \u{2014} restart to apply now.")
                .font(theme.skin.bodyFont(11.5, .regular))
                .foregroundStyle(theme.palette.dim)
        }
    }
}
```

Use the design-system §3.4 warn glyph — check `Sources/App/Theme/Icon.swift` for the app's actual warn-glyph constant and use that rather than a raw codepoint if one exists.

- [ ] **Step 4: Implement `FileNamingPreset.swift`**

```swift
import Foundation

enum FileNamingPreset: CaseIterable, Hashable {
    case title, titleAndChannel, dateAndTitle, custom

    var rowLabel: String {
        switch self {
        case .title: "Title"
        case .titleAndChannel: "Title and channel"
        case .dateAndTitle: "Date and title"
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

    static func matching(_ storedTemplate: String) -> FileNamingPreset {
        allCases.first { $0.template == storedTemplate } ?? .custom
    }
}
```

- [ ] **Step 5: Regenerate, run, verify pass**

Run: `mise exec -- tuist generate --no-open` then the two suites from Step 2.
Expected: PASS.

- [ ] **Step 6: Lint + commit**

```bash
mise exec -- swiftformat --lint . && mise exec -- swiftlint lint --strict
git add Sources/App/Preferences/FileNamingPreset.swift Sources/App/Preferences/ConcurrencyNote.swift Tests/AppUnitTests/FileNamingPresetTests.swift Tests/AppUnitTests/ConcurrencyNoteTests.swift
git commit -m "feat: FileNamingPreset mapping + concurrency-note predicate"
```

---

## Task 10: `PrefRow` + `PreferencesView` shell + header-only panes

**Files:**
- Create: `Sources/App/Preferences/PrefRow.swift`
- Create: `Sources/App/Preferences/PreferencesView.swift`
- Create: `Sources/App/Preferences/Panes/SignInCookiesPane.swift`
- Create: `Sources/App/Preferences/Panes/UpdatesPane.swift`
- Modify: `Sources/App/MainWindow.swift` (`page` switch → `PreferencesView(initialPane:)`)
- Test: none (view shell); the `selectedPane` seeding is covered by Task 6's `PreferencesPane` tests + the manual smoke.

**Interfaces:**
- Consumes: `PreferencesPane` / `PreferencesRailGroup` (Task 6), `@Environment(\.theme)`, `@Environment(AppModel.self)`.
- Produces:

```swift
struct PrefRow<Control: View>: View {
    init(_ label: String, helper: String? = nil, @ViewBuilder control: () -> Control)
}

struct PrefPaneHeader: View {
    init(_ pane: PreferencesPane)   // title 20/heavy --headline + rule + --dim sub above rule
}

struct PrefHeaderOnlyPane: View {
    init(_ pane: PreferencesPane, line: String)   // title + sub + one "filled in Phase N" line
}

struct PreferencesView: View {
    init(initialPane: PreferencesPane = .downloads)
}
```

- [ ] **Step 1: Implement `PrefRow.swift`**

`PrefRow`: an `HStack(alignment: .top)` — left `VStack(alignment: .leading, spacing: Spacing.s1)` with `label` (`theme.skin.bodyFont(13, .semibold)`, `--text`) and optional `helper` (`theme.skin.bodyFont(11.5, .regular)`, `--dim`); `Spacer()`; the `control()` right-aligned. Below: a `Divider().overlay(theme.palette.hair)` — or make the divider the caller's responsibility via a `.prefRowDivider()` modifier and stack rows in a `VStack`. Keep it simple: `PrefRow` renders its own trailing divider.

`PrefPaneHeader`: `VStack(alignment: .leading, spacing: Spacing.s1)` — `pane.subtitle` (`--dim`, 11.5), `pane.title` (`theme.skin.displayFont(20, .heavy)`, `--headline`), `Divider().overlay(theme.palette.hair)`.

`PrefHeaderOnlyPane`: `PrefPaneHeader(pane)` then a single `Text(line).font(theme.skin.bodyFont(12, .regular)).foregroundStyle(theme.palette.faint)`.

- [ ] **Step 2: Implement the two header-only panes**

```swift
// SignInCookiesPane.swift
import SwiftUI
struct SignInCookiesPane: View {
    var body: some View {
        PrefHeaderOnlyPane(.cookies, line: "Filled in Phase 5 \u{2014} browser picker, Firefox profile, Full Disk Access, tip text.")
    }
}
```

```swift
// UpdatesPane.swift
import SwiftUI
struct UpdatesPane: View {
    var body: some View {
        PrefHeaderOnlyPane(.updates, line: "Filled in Phase 10 \u{2014} yt-dlp / ffmpeg / app versions, check buttons, daily-check toggle.")
    }
}
```

- [ ] **Step 3: Implement `PreferencesView.swift` shell**

```swift
import SwiftUI

struct PreferencesView: View {
    @Environment(\.theme) private var theme
    @State private var selectedPane: PreferencesPane

    init(initialPane: PreferencesPane = .downloads) {
        _selectedPane = State(initialValue: initialPane)
    }

    var body: some View {
        HStack(spacing: 0) {
            rail
            Divider().overlay(theme.palette.hair)
            ScrollView {
                paneBody
                    .padding(Spacing.s6)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var rail: some View {
        VStack(alignment: .leading, spacing: Spacing.s4) {
            ForEach(PreferencesRailGroup.allCases, id: \.self) { group in
                VStack(alignment: .leading, spacing: Spacing.s1) {
                    Text(group.caption)
                        .font(theme.skin.monoFont(10, .medium))
                        .foregroundStyle(theme.palette.faint)
                    ForEach(group.panes, id: \.self) { pane in
                        railButton(pane)
                    }
                }
            }
            Spacer()
        }
        .padding(Spacing.s4)
        .frame(width: 200, alignment: .leading)
    }

    private func railButton(_ pane: PreferencesPane) -> some View {
        let active = pane == selectedPane
        return Button { selectedPane = pane } label: {
            Text(pane.title)
                .font(theme.skin.bodyFont(12, active ? .semibold : .regular))
                .foregroundStyle(active ? theme.palette.text : theme.palette.dim)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, Spacing.s2)
                .padding(.vertical, Spacing.s1)
                .background(active ? theme.palette.panel : .clear, in: RoundedRectangle(cornerRadius: theme.skin.chipRadius))
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private var paneBody: some View {
        switch selectedPane {
        case .downloads: DownloadsPane()
        case .appearance: AppearancePane()
        case .network: NetworkPane()
        case .cookies: SignInCookiesPane()
        case .updates: UpdatesPane()
        case .logsPrivacy: LogsPrivacyPane()
        case .advanced: AdvancedPane()
        }
    }
}
```

`DownloadsPane` / `AppearancePane` / `NetworkPane` / `LogsPrivacyPane` / `AdvancedPane` do not exist yet — this task will not compile until Tasks 11–14 land. **Order the build:** implement this shell referencing the pane types, then do Tasks 11–14, then wire `MainWindow` in Step 4. If executing strictly task-by-task with a green build gate between each, temporarily stub the five unbuilt panes as `struct XPane: View { var body: some View { PrefPaneHeader(.x) } }` in their own files and fill them in Tasks 11–14 (each of those tasks replaces the stub body — this is fill, not rip-and-replace).

- [ ] **Step 4: Wire `MainWindow`**

`case .preferences(let pane): PreferencesView(initialPane: pane)` in the `page` switch. Remove the `placeholder("Preferences")` line.

- [ ] **Step 5: Regenerate + build + run existing tests**

Run: `mise exec -- tuist generate --no-open`, build the workspace, `xcodebuild ... test -only-testing:AppUnitTests`.
Expected: builds; AppUnitTests green.

- [ ] **Step 6: Lint + commit**

```bash
mise exec -- swiftformat --lint . && mise exec -- swiftlint lint --strict
git add Sources/App/Preferences/ Sources/App/MainWindow.swift
git commit -m "feat: PreferencesView shell + PrefRow + header-only panes"
```

---

## Task 11: Downloads pane

**Files:**
- Create/replace-stub: `Sources/App/Preferences/Panes/DownloadsPane.swift`
- Test: none new (row wiring is view code; `FileNamingPreset` + concurrency predicate already covered).

**Interfaces:**
- Consumes: `@Environment(AppModel.self)` → `appModel.prefs`, `appModel.rowStore.rows`; `SkinnedSegment` (Task 7), `SkinnedPicker` (Task 8), `FileNamingPreset` + `shouldShowConcurrencyNote` + `ConcurrencyNote` (Task 9), `PrefRow` (Task 10), `KindSelector` (Task 2).
- Produces: `struct DownloadsPane: View`.

Rows in order (spec §5.1):

| Row | Control | Backs |
|---|---|---|
| Save to | trigger button showing `prefs.defaultDestFolder.lastPathComponent`; tap → `NSOpenPanel` (directories only). No list. | `defaultDestFolder` |
| At the same time | `Stepper` 1–6 · helper "The app lowers this on its own if a site starts throttling." + `ConcurrencyNote` under it when `shouldShowConcurrencyNote(newValue: prefs.maxConcurrentDownloads, runningCount: runningCount)` | `maxConcurrentDownloads` |
| If a download fails, try | `Stepper` 1–5 · helper "How many times to retry automatically before asking you." | `maxAutoAttempts` |
| Default type | `SkinnedSegment([.video, .audio], label: capitalized)` | `prefs.defaultAudioOrVideo` |
| Default video quality | `SkinnedPicker` — quality ladder | `prefs.defaultMaxHeight` (`Int.max` for Best) |
| Default audio format | `SkinnedSegment([.m4a, .mp3])` | `prefs.defaultAudioCodec` |
| File naming | `SkinnedPicker` of `FileNamingPreset.allCases` (subtitle = `exampleSubtitle`); "Custom…" reveals a monospace `TextField` below | `prefs.outputTemplate` |
| Watch the clipboard | `Toggle` · helper "Offer to grab a link when you copy one." | `prefs.clipboardAutoDetect` |

- [ ] **Step 1: Implement the pane**

Key details:
- `runningCount`: `appModel.rowStore.rows.filter { $0.snapshot.state == .running }.count`.
- Quality ladder as `[(label: String, height: Int)]`: `[("2160p", 2160), ("1440p", 1440), ("1080p", 1080), ("720p", 720), ("480p", 480), ("Best available", Int.max)]`. `SkinnedPicker` rows keyed by `height`; `selection` bound to `prefs.defaultMaxHeight`; trigger label = the matching row's label (fallback `"\(prefs.defaultMaxHeight)p"` if somehow off-ladder).
- Default type: bind a local `Binding<KindSelector>` that reads `prefs.defaultAudioOrVideo` and writes it. (`defaultAudioOrVideo` is now `public` — Task 2.)
- File naming: `@State private var namingPreset: FileNamingPreset` seeded in `.onAppear` from `FileNamingPreset.matching(prefs.outputTemplate)`; `@State private var customText: String` seeded from `prefs.outputTemplate`. On picker select: if preset has a `template`, set `prefs.outputTemplate = template` and `namingPreset = preset`; if `.custom`, set `namingPreset = .custom` and show the field pre-filled with `customText`. Custom `TextField`: `.font(theme.skin.monoFont(12, .regular))`; `.onSubmit` / focus-loss → if trimmed empty revert `customText` to `prefs.outputTemplate`, else `prefs.outputTemplate = customText`.
- "Save to": reuse the `NSOpenPanel` pattern from `RunwayView.chooseFolder()` (directories only, no multiple selection); on OK set `prefs.defaultDestFolder = url`.
- Wrap the pane in `PrefPaneHeader(.downloads)` then a `VStack(spacing: 0)` of `PrefRow`s.
- `@Bindable var prefs = appModel.prefs` at the top of `body` for `Toggle` / `Stepper` bindings.

- [ ] **Step 2: Regenerate + build**

Run: `mise exec -- tuist generate --no-open` then build the workspace.
Expected: builds clean.

- [ ] **Step 3: Lint + commit**

```bash
mise exec -- swiftformat --lint . && mise exec -- swiftlint lint --strict
git add Sources/App/Preferences/Panes/DownloadsPane.swift
git commit -m "feat: Preferences Downloads pane"
```

---

## Task 12: Appearance pane + palette swatch

**Files:**
- Create/replace-stub: `Sources/App/Preferences/Panes/AppearancePane.swift`
- Test: none new (live re-theme is visual, excluded by spec §9).

**Interfaces:**
- Consumes: `appModel.prefs.skin` / `.palette`, `SkinKind` / `PaletteKind` (`GrabberKit`), `SkinnedSegment`, `PrefRow`, `@Environment(\.theme)`.
- Produces: `struct AppearancePane: View`.

Rows (spec §5.2):

| Row | Control | Backs |
|---|---|---|
| Skin | `SkinnedSegment([.aurora, .tapeDeck], label: "Aurora"/"Tape Deck")` · helper "Aurora is dark and luminous. Tape Deck is warm and light." | `skin` |
| Palette | 3 swatches for the selected skin | `palette` |

- [ ] **Step 1: Implement**

- Palettes per skin:
  ```swift
  private func palettes(for skin: SkinKind) -> [PaletteKind] {
      switch skin {
      case .aurora: [.auroraMintIris, .auroraLimeForest, .auroraMagentaViolet]
      case .tapeDeck: [.tapeDeckA, .tapeDeckB, .tapeDeckC]
      }
  }
  ```
- Swatch view: a `RoundedRectangle` ~38pt tall split into two halves — left `--accent`, right `--accent-2` of *that palette* (`palette(for: kind).accent` / `.accent2` — the `palette(for:)` free function in `Sources/App/Theme/Palette.swift`); palette display name (`--text`, small) underneath. Selected swatch (`kind == prefs.palette`): `.overlay(RoundedRectangle(...).stroke(theme.palette.accent, lineWidth: 2).padding(-2))` for a 2px outline at 2px offset.
- Palette display names: add a `PaletteKind.displayName` computed property in a small App-target extension file, or a local `switch` — `"Mint & Iris"`, `"Lime & Forest"`, `"Magenta & Violet"`, `"Tape Deck A/B/C"` (author reasonable names; the doc §5.2/5.3 has them).
- Skin change resets `palette`: `.onChange(of: prefs.skin) { _, newSkin in prefs.palette = defaultPalette(for: newSkin) }` where `defaultPalette` returns `.auroraMintIris` / `.tapeDeckA`.
- Both controls write straight to `prefs` — the app re-themes live via the existing `@Observable` binding (no extra work).

Note: `Sources/App/Theme/Palette.swift`'s `palette(for:)` currently returns `auroraMintIris` for every kind (Phase 9 fills the real values). The swatch will show identical colors across all three until Phase 9 — that is expected and correct; do not add palette values in this phase (out of scope, parent §12).

- [ ] **Step 2: Regenerate + build**

Run: `mise exec -- tuist generate --no-open` then build.
Expected: builds clean.

- [ ] **Step 3: Lint + commit**

```bash
mise exec -- swiftformat --lint . && mise exec -- swiftlint lint --strict
git add Sources/App/Preferences/Panes/AppearancePane.swift Sources/App/Theme/
git commit -m "feat: Preferences Appearance pane + palette swatch"
```

---

## Task 13: Network pane

**Files:**
- Create/replace-stub: `Sources/App/Preferences/Panes/NetworkPane.swift`
- Test: none new (`Preferences` field behavior covered in Task 2; `YtDlpArguments` wiring in Task 4).

**Interfaces:**
- Consumes: `appModel.prefs.proxyURL` / `.forceIPv4` / `.selfRateLimitKBps`, `PrefRow`, `@Environment(\.theme)`.
- Produces: `struct NetworkPane: View`.

Rows (spec §5.3):

| Row | Control | Backs |
|---|---|---|
| Proxy | `TextField` · helper "e.g. `http://host:port`. Leave blank for none." | `proxyURL` |
| Use IPv4 only | `Toggle` · helper "Try this if downloads stall on connection errors." | `forceIPv4` |
| Limit download speed | stepper (KB/s) with an "Off" position | `selfRateLimitKBps` |

- [ ] **Step 1: Implement**

- Proxy: `@State private var proxyText: String` seeded in `.onAppear` from `prefs.proxyURL ?? ""`; `.onSubmit` / focus loss → `prefs.proxyURL = proxyText` (the setter trims + maps empty → `nil`, Task 2).
- IPv4: `Toggle("", isOn: $prefs.forceIPv4)` via `@Bindable`.
- Limit download speed: a custom stepper. Model `nil` as "Off". Below some minimum, stepping down lands on "Off"; stepping up from "Off" lands on a sensible first value (e.g. 100 KB/s). Display: `prefs.selfRateLimitKBps.map { "\($0) KB/s" } ?? "Off"` with `-` / `+` buttons (reuse the mockup's stepper visual language). Clamp is handled by the setter (`1…100000`); the view just needs to pass `nil` for Off and a positive Int otherwise. Step size: 100 KB/s is reasonable.
- Header: `PrefPaneHeader(.network)`.

- [ ] **Step 2: Regenerate + build**

Run: `mise exec -- tuist generate --no-open` then build.
Expected: builds clean.

- [ ] **Step 3: Lint + commit**

```bash
mise exec -- swiftformat --lint . && mise exec -- swiftlint lint --strict
git add Sources/App/Preferences/Panes/NetworkPane.swift
git commit -m "feat: Preferences Network pane"
```

---

## Task 14: Logs & privacy + Advanced panes

**Files:**
- Create/replace-stub: `Sources/App/Preferences/Panes/LogsPrivacyPane.swift`
- Create/replace-stub: `Sources/App/Preferences/Panes/AdvancedPane.swift`
- Test: `Tests/AppUnitTests/AppModelTests.swift` (append) — reset-all-settings + reset-columns mutations.

**Interfaces:**
- Consumes: `appModel.prefs`, `appModel.columnConfig`, `appModel.confirm(_:)` (`AppModel`), `ConfirmationRequest` (`GrabberKit`), `NSWorkspace` (`AppKit`), `PrefRow`.
- Produces:
  - `struct LogsPrivacyPane: View`
  - `struct AdvancedPane: View`
  - `AppModel.resetAllSettings()` — writes every `Preferences` field to its default (a new method on `AppModel`, or a `Preferences.resetToDefaults()` on the model — put it on `Preferences` in `GrabberKit` so it is unit-testable without the view; `AppModel` just calls it).

Spec §5.6 Logs & privacy:

| Row | Control | Action |
|---|---|---|
| Open log folder | button | `NSWorkspace.shared.open(URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent("Library/Logs/MediaGrabber"))` |
| Detailed logging | toggle | `prefs.verboseLogging` |
| What's in the logs | button "View" | `NSWorkspace.shared.open` the bundled `PRIVACY.md` (`Bundle.main.url(forResource: "PRIVACY", withExtension: "md")`) |

Spec §5.7 Advanced:

| Row | Control | Action |
|---|---|---|
| Open app data folder | button | reveal `~/Library/Application Support/MediaGrabber` via `NSWorkspace.shared.activateFileViewerSelecting` |
| Reset table columns | button | `appModel.columnConfig = .default` (propagates via the existing `didSet`) |
| Reset all settings | button (`--danger`), `ConfirmationRequest(isDestructive: true, suppressionKey: nil)` | on confirm → `appModel.resetAllSettings()` |

- [ ] **Step 1: Write the failing tests**

Add to `PreferencesTests.swift` (GrabberKit) — put reset on the model:

```swift
func test_resetToDefaults_restoresEveryField() {
    let prefs = Preferences(defaults: defaults)
    prefs.defaultMaxHeight = 480
    prefs.skin = .tapeDeck
    prefs.palette = .tapeDeckC
    prefs.forceIPv4 = true
    prefs.proxyURL = "http://h:1"
    prefs.selfRateLimitKBps = 500
    prefs.clipboardAutoDetect = false
    prefs.maxConcurrentDownloads = 6
    prefs.outputTemplate = "%(id)s.%(ext)s"
    prefs.lastSelectedKind = .audio

    prefs.resetToDefaults()

    XCTAssertEqual(prefs.defaultMaxHeight, 1080)
    XCTAssertEqual(prefs.skin, .aurora)
    XCTAssertEqual(prefs.palette, .auroraMintIris)
    XCTAssertFalse(prefs.forceIPv4)
    XCTAssertNil(prefs.proxyURL)
    XCTAssertNil(prefs.selfRateLimitKBps)
    XCTAssertTrue(prefs.clipboardAutoDetect)
    XCTAssertEqual(prefs.maxConcurrentDownloads, 3)
    XCTAssertEqual(prefs.outputTemplate, "%(title)s.%(ext)s")
    XCTAssertNil(prefs.lastSelectedKind)
}
```

Add to `AppModelTests.swift` (AppUnitTests):

```swift
@MainActor
func test_resetTableColumns_restoresDefault() {
    let model = makeAppModel()   // match the existing helper
    var custom = ColumnConfig.default
    // mutate `custom` to a non-default order/visibility per ColumnConfig's API
    model.columnConfig = custom
    model.columnConfig = .default
    XCTAssertEqual(model.columnConfig, .default)
}
```

(If `AppModelTests` already exercises `columnConfig` round-trips, a dedicated test may be redundant — check first; skip if `ColumnConfigTests` / `AppModelTests` already covers `= .default`.)

- [ ] **Step 2: Run, verify fail**

Run: `xcodebuild ... test -only-testing:GrabberKitTests/PreferencesTests`
Expected: FAIL — `resetToDefaults` undefined.

- [ ] **Step 3: Implement `Preferences.resetToDefaults()`**

In `Preferences.swift`, add a method that removes every `mg.*` key this model owns (enumerate them explicitly — do not `removePersistentDomain`, other subsystems' keys share the suite):

```swift
public func resetToDefaults() {
    for key in Self.ownedKeys {
        defaults.removeObject(forKey: key)
    }
}

private static let ownedKeys = [
    "mg.defaultDestFolder", "mg.lastUsedDestFolder", "mg.defaultKindSelector",
    "mg.defaultMaxHeight", "mg.defaultAudioCodec", "mg.outputTemplate",
    "mg.maxAutoAttempts", "mg.maxConcurrentDownloads", "mg.verboseLogging",
    "mg.skin", "mg.palette", "mg.clipboardAutoDetect", "mg.proxyURL",
    "mg.forceIPv4", "mg.selfRateLimitKBps", "mg.lastSelectedMaxHeight",
    "mg.lastSelectedKind", "mg.lastSelectedAudioCodec"
]
```

Cross-check this list against every `forKey:` string literal in the file — it must be exhaustive. Note the getters already fall back to the right defaults once a key is removed.

Then `AppModel.resetAllSettings()`:

```swift
func resetAllSettings() {
    prefs.resetToDefaults()
}
```

`prefs` is `@Observable`; removing keys does not fire observation. Since the getters are computed off `defaults` and SwiftUI re-reads on any `@Observable` access, a view already bound to `prefs` re-renders when *any* tracked property changes — but a bulk `removeObject` touches none. Force a notification: after `resetToDefaults()`, the model needs to signal change. Simplest: give `Preferences` a `private var resetToken = 0` `@Observable`-tracked property, bump it in `resetToDefaults()`, and have `PreferencesView` / consumers read nothing special — actually the clean fix is for each computed getter already being tracked. **Verify** in Step 5 whether the live re-theme happens; if not, add `withMutation`/`access` via an explicit `@ObservationIgnored`-free stored `var revision` bumped on reset and referenced in `ResolvedTheme` resolution. Keep this minimal and only if the smoke test shows a stale theme.

- [ ] **Step 4: Implement the two panes**

`LogsPrivacyPane`: three `PrefRow`s with `Button`s / `Toggle` per the table. Log folder URL as above. `PRIVACY.md` via `Bundle.main.url(forResource:withExtension:)` — if the bundle lookup returns `nil` (not yet added as a resource), fall back to opening the repo copy path is not possible in a shipped app; guard with `if let url = ... { NSWorkspace.shared.open(url) }` and no-op otherwise. Confirm whether `PRIVACY.md` is a bundled resource in the Tuist target; if not, add it to the App target's resources in `Project.swift` as part of this step.

`AdvancedPane`: three `PrefRow`s. "Reset all settings" button uses `theme.palette.danger` styling and triggers:

```swift
Button("Reset all settings") {
    Task {
        let confirmed = await appModel.confirm(ConfirmationRequest(
            title: "Reset all settings?",
            message: "Every preference goes back to its default. Your downloads and table columns are not affected.",
            confirmTitle: "Reset",
            cancelTitle: "Cancel",
            isDestructive: true,
            suppressionKey: nil
        ))
        if confirmed { appModel.resetAllSettings() }
    }
}
```

Match `ConfirmationRequest.init` parameter labels to `Sources/GrabberKit/App/Confirming.swift` exactly (check: `title`, `message`, `confirmTitle`, `cancelTitle`, `isDestructive`, `suppressionKey`).

- [ ] **Step 5: Regenerate, run tests, verify pass**

Run: `mise exec -- tuist generate --no-open`, then `xcodebuild ... test -only-testing:GrabberKitTests/PreferencesTests -only-testing:AppUnitTests`.
Expected: PASS. Build the app and manually verify "Reset all settings" re-themes live (Task 16 smoke); if it doesn't, apply the minimal revision-token fix noted in Step 3.

- [ ] **Step 6: Lint + commit**

```bash
mise exec -- swiftformat --lint . && mise exec -- swiftlint lint --strict
git add Sources/App/Preferences/Panes/LogsPrivacyPane.swift Sources/App/Preferences/Panes/AdvancedPane.swift Sources/GrabberKit/Model/Preferences.swift Sources/App/AppModel.swift Tests/ Project.swift
git commit -m "feat: Preferences Logs & privacy + Advanced panes, resetToDefaults"
```

---

## Task 15: Runway — swap native `Menu` for skinned controls + `lastSelected*` seeding

**Files:**
- Modify: `Sources/App/Home/RunwayView.swift`
- Modify: `Sources/App/Home/HomeView.swift`
- Modify: `Sources/App/AppModel.swift` (`grab(...)` writes `lastSelected*`)
- Modify: `Sources/App/Rows/RequestBuilder.swift` + `RunwayOverrides` (carry `maxHeight` / `audioCodec` explicitly so `grab` can persist them)
- Test: `Tests/AppUnitTests/RequestBuilderTests.swift` (seeding / override behavior), `Tests/AppUnitTests/AppModelTests.swift` (grab writes `lastSelected*`)

**Interfaces:**
- Consumes: `SkinnedSegment` (Task 7), `SkinnedPicker` (Task 8), `KindSelector` (Task 2, `GrabberKit`), `Preferences.lastSelected*` (Task 2).
- Produces:
  - `RunwayView` uses `KindSelector` from `GrabberKit` (delete the nested `RunwayView.KindSelector`).
  - `RunwayOverrides` gains enough to reconstruct the selection: keep `kind: DownloadKind?` + `destFolder: URL?` (the `kind` already encodes height/codec — no new fields needed; `grab` decomposes `kind` to write `lastSelected*`).
  - `AppModel.grab(overrides:)`: after building the request, write `prefs.lastSelectedKind` / `.lastSelectedMaxHeight` / `.lastSelectedAudioCodec` from `overrides.kind` (when non-nil).

- [ ] **Step 1: Write failing tests**

`HomeView.seedFromPrefs` is view code; test the *seed resolution* as a pure helper instead. Extract seeding into a testable function:

```swift
// in a new Sources/App/Home/RunwaySeed.swift
struct RunwaySeed: Equatable {
    var kind: KindSelector
    var maxHeight: Int
    var audioCodec: AudioCodec
    var destFolder: URL
}

func runwaySeed(from prefs: Preferences) -> RunwaySeed
```

Test `Tests/AppUnitTests/RunwaySeedTests.swift`:

```swift
@testable import MediaGrabber
import GrabberKit
import XCTest

final class RunwaySeedTests: XCTestCase {
    private func prefs() -> Preferences { Preferences(defaults: UserDefaults(suiteName: "mg.test.\(UUID())")!) }

    func test_seed_fallsBackToDefaultsWhenNoLastSelected() {
        let p = prefs()
        let seed = runwaySeed(from: p)
        XCTAssertEqual(seed.kind, .video)
        XCTAssertEqual(seed.maxHeight, 1080)
        XCTAssertEqual(seed.audioCodec, .m4a)
    }

    func test_seed_prefersLastSelected() {
        let p = prefs()
        p.lastSelectedKind = .audio
        p.lastSelectedMaxHeight = .max
        p.lastSelectedAudioCodec = .mp3
        let seed = runwaySeed(from: p)
        XCTAssertEqual(seed.kind, .audio)
        XCTAssertEqual(seed.maxHeight, .max)
        XCTAssertEqual(seed.audioCodec, .mp3)
    }
}
```

Add to `AppModelTests.swift`:

```swift
@MainActor
func test_grab_writesLastSelectedFromOverrides() async {
    let model = makeAppModel(/* with a fake engine + a resolved metadata */)
    // set model.resolved via the test path, then:
    await model.grab(overrides: RunwayOverrides(kind: .video(maxHeight: 720), destFolder: nil))
    XCTAssertEqual(model.prefs.lastSelectedKind, .video)
    XCTAssertEqual(model.prefs.lastSelectedMaxHeight, 720)
}
```

Match `makeAppModel` / resolved-metadata setup to the existing `AppModelTests` helpers.

- [ ] **Step 2: Run, verify fail**

Run: `xcodebuild ... test -only-testing:AppUnitTests/RunwaySeedTests -only-testing:AppUnitTests/AppModelTests`
Expected: FAIL — `runwaySeed` undefined; `grab` doesn't write `lastSelected*`.

- [ ] **Step 3: Implement `runwaySeed` + wire `HomeView`**

`RunwaySeed.swift`:

```swift
import Foundation
import GrabberKit

struct RunwaySeed: Equatable {
    var kind: KindSelector
    var maxHeight: Int
    var audioCodec: AudioCodec
    var destFolder: URL
}

func runwaySeed(from prefs: Preferences) -> RunwaySeed {
    let kind = prefs.lastSelectedKind ?? prefs.defaultAudioOrVideo
    let maxHeight = prefs.lastSelectedMaxHeight ?? prefs.defaultMaxHeight
    let codec = prefs.lastSelectedAudioCodec ?? prefs.defaultAudioCodec
    let dest = prefs.lastUsedDestFolder != prefs.defaultDestFolder
        ? prefs.lastUsedDestFolder
        : prefs.defaultDestFolder
    return RunwaySeed(kind: kind, maxHeight: maxHeight, audioCodec: codec, destFolder: dest)
}
```

`HomeView.seedFromPrefs`:

```swift
private func seedFromPrefs() {
    guard !seeded else { return }
    seeded = true
    let seed = runwaySeed(from: appModel.prefs)
    kindSelector = seed.kind
    maxHeight = seed.maxHeight
    audioCodec = seed.audioCodec
    destFolder = seed.destFolder
}
```

Change `HomeView`'s `@State private var kindSelector: RunwayView.KindSelector` → `KindSelector` (from `GrabberKit`). `selectedKind` computed prop switches on the `GrabberKit` `KindSelector`.

- [ ] **Step 4: Swap `RunwayView` controls**

Delete `RunwayView.KindSelector` (use `GrabberKit.KindSelector`). Replace:
- `typeMenu` → `SkinnedSegment([.video, .audio], selection: $kindSelector) { $0.rawValue.capitalized }`.
- `formatMenu` video branch → `SkinnedPicker` with the quality ladder rows (same ladder as Task 11 — `2160/1440/1080/720/480/Best available`, `Int.max` for Best; **drop 360**), `selection: $maxHeight`, `caption: "Resolution"`, all-`nil` subtitles.
- `formatMenu` audio branch → `SkinnedSegment(AudioCodec.allCases, selection: $audioCodec) { $0.rawValue }`.
- `saveMenu` → `SkinnedPicker` per spec §5.1.2:
  - Row 1: `defaultDestFolder` — label = `lastPathComponent`, subtitle = full path.
  - Row 2: `lastUsedDestFolder` — **only if `!= defaultDestFolder`** — label + subtitle.
  - Row 3: "Choose…" → `NSOpenPanel`; on pick set `destFolder` + `appModel.prefs.lastUsedDestFolder`.
  - `caption: "Save to"`. Default selection: `lastUsedDestFolder` if valid & set, else `defaultDestFolder`.
  - The "Choose…" row needs a sentinel `Option` — model the picker's `Option` as an enum `SaveToChoice { case folder(URL); case choose }` or key rows by a `String` id and handle "choose" specially. Keep it local to `RunwayView`.

`private let heights` constant: update to drop 360, or replace with the shared ladder tuple.

- [ ] **Step 5: `AppModel.grab` writes `lastSelected*`**

In `grab(overrides:)`, after `let request = RequestBuilder.build(...)` and the existing `lastUsedDestFolder` write:

```swift
if let kind = overrides.kind {
    switch kind {
    case let .video(maxHeight):
        prefs.lastSelectedKind = .video
        prefs.lastSelectedMaxHeight = maxHeight
    case let .audio(codec):
        prefs.lastSelectedKind = .audio
        prefs.lastSelectedAudioCodec = codec
    }
}
```

(`HomeView.runwayOverrides` already passes `kind: selectedKind` — non-nil on every grab.)

- [ ] **Step 6: Regenerate, run, verify pass**

Run: `mise exec -- tuist generate --no-open`, then `xcodebuild ... test -only-testing:AppUnitTests`. Also run `-only-testing:AppUnitTests/RequestBuilderTests` explicitly.
Expected: PASS. Full app build clean.

- [ ] **Step 7: Lint + commit**

```bash
mise exec -- swiftformat --lint . && mise exec -- swiftlint lint --strict
git add Sources/App/Home/ Sources/App/AppModel.swift Sources/App/Rows/RequestBuilder.swift Tests/AppUnitTests/
git commit -m "feat: runway uses SkinnedSegment/SkinnedPicker + lastSelected seeding"
```

---

## Task 16: Full test pass, manual smoke, DoD doc updates, tag

**Files:**
- Modify: `docs/superpowers/specs/2026-08-28-youtube-downloader-mac-design.md` (§12.1 Phase 3 stub, §12.2 `PreferencesView` row, Phase 7 stub)
- Create: `docs/superpowers/plans/2026-08-31-media-grabber-phase-3-smoke.md` (or inline the checklist wherever the project keeps them — check for a prior phase's smoke checklist location)

**Interfaces:**
- Consumes: everything built in Tasks 1–15.
- Produces: nothing new.

- [ ] **Step 1: Full test + lint**

Run:
```bash
xcodebuild -workspace MediaGrabber.xcworkspace -scheme MediaGrabber-Workspace -destination 'platform=macOS' test
mise exec -- swiftformat --lint .
mise exec -- swiftlint lint --strict
```
Expected: all green, both linters clean.

- [ ] **Step 2: Manual smoke (spec §9)**

`make` to build + launch. Walk:
- Open each of the 7 panes from the rail.
- Change Skin (Aurora ↔ Tape Deck) and Palette — the whole app re-themes on click.
- Start a download, lower "At the same time" below the running count — the concurrency note appears in the row; it clears when the running count drops to ≤ the new value.
- Set a proxy / toggle IPv4 / set a rate limit — start a download, check its job log / `processLaunched` argv carries `--proxy` / `-4` / `--limit-rate NNNK`.
- Advanced → "Reset all settings" → confirm → every preference back to default; skin/palette snap live.
- Advanced → "Reset table columns" → table columns restore; independent of "Reset all settings".
- Runway: Type / Quality / Save-to pickers open, select, and the selection persists to the next paste (relaunch, paste a new link, confirm the runway shows the last selection).
- File naming: pick each preset, confirm the template; pick "Custom…", edit, confirm it persists and re-derives to the right row on reopen.

Record pass/fail per item. Fix any failure before proceeding (return to the owning task).

- [ ] **Step 3: Update parent spec §12.1 / §12.2**

- §12.1 Phase 3 stub → rewrite to reflect what shipped (7-pane `PreferencesView`, `SkinnedSegment` / `SkinnedPicker`, new `Preferences` fields, `GlobalDownloadOptions` wiring, concurrency note, deep-link seam).
- §12.2 `PreferencesView` row → updated status.
- Phase 7 stub → add the deferred hint: "runway quality picker restricted to probe-reported available heights; the seed then resolves `lastSelected` → if available use it → else `defaultMaxHeight` if available → else best available height."

- [ ] **Step 4: Move built spec + plan to archived (per CLAUDE.md)**

```bash
git mv docs/superpowers/specs/2026-08-31-media-grabber-phase-3.md docs/superpowers/specs/archived/
git mv docs/superpowers/plans/2026-08-31-media-grabber-phase-3.md docs/superpowers/plans/archived/
```

(Keep the `assets/` folder reference path valid — move or update as the archived siblings expect.)

- [ ] **Step 5: Commit + tag**

```bash
git add -A
git commit -m "docs: phase 3 DoD — parent spec updates, archive spec+plan"
git tag phase-3
```

---

## Self-Review

**1. Spec coverage:**

| Spec section | Task |
|---|---|
| §1 7-pane `PreferencesView` | 6, 10 |
| §1 filled panes (Downloads/Appearance/Network/Logs/Advanced) | 11, 12, 13, 14 |
| §1 header-only panes (Sign-in/Updates) | 10 |
| §1 `SkinnedSegment` | 7 |
| §1 `SkinnedPicker` | 8 |
| §1 controls replace runway `Menu`s | 15 |
| §1 new `Preferences` fields + persistence | 2 |
| §1 `GlobalDownloadOptions` + `YtDlpArguments` wiring | 3, 4, 5 |
| §1 concurrency inline note | 9, 11 |
| §1 `Page.preferences(PreferencesPane)` deep-link | 6 |
| §1 doc updates (design-system + screens.html) | 1 |
| §2.1 navigation / `MainWindow` target | 6, 10 |
| §3 fields table + `KindSelector` promotion | 2 |
| §3 "Best available" = `Int.max` | 2, 11, 15 (Global Constraints) |
| §3.1 runway seeding | 15 |
| §4.1 `SkinnedSegment` design | 1, 7 |
| §4.2 `SkinnedPicker` design | 1, 8 |
| §5.1 Downloads pane rows | 11 |
| §5.1.1 File naming presets | 9, 11 |
| §5.1.2 runway Save-to | 15 |
| §5.1.3 runway Type/Quality/Format | 15 |
| §5.2 Appearance + swatch | 12 |
| §5.3 Network | 13 |
| §5.4 / §5.5 header-only | 10 |
| §5.6 Logs & privacy | 14 |
| §5.7 Advanced + resets | 14 |
| §6 concurrency note predicate + view | 9, 11 |
| §7 `GlobalDownloadOptions` + `YtDlpArguments` + engine | 3, 4, 5 |
| §8.1 design-system doc | 1 |
| §8.2 screens.html | 1 |
| §9 testing (all units) | 2, 3, 4, 5, 6, 9, 14, 15 |
| §10 DoD | 16 |

No gaps.

**2. Placeholder scan:** Every code step carries real code or a precise description with exact symbol names, file paths, and copy strings. Sub-line helper copy for pane subtitles and a few button labels is delegated to the implementer with the spec section cited and the voice constraint stated — acceptable, as the spec itself leaves that wording open.

**3. Type consistency:**
- `KindSelector` — promoted to `public` top-level in `GrabberKit` (Task 2); `RunwayView.KindSelector` deleted (Task 15); `runwaySeed` / `RunwaySeed` / `HomeView` all use the `GrabberKit` one.
- `GlobalDownloadOptions(proxyURL:forceIPv4:rateLimitKBps:)` — same signature in Tasks 3, 4, 5.
- `YtDlpArguments.build(for:options:)` / `.redacted(for:options:)` — same in Tasks 4, 5.
- `PreferencesPane` cases (`downloads, appearance, network, cookies, updates, logsPrivacy, advanced`) — same in Tasks 6, 10.
- `shouldShowConcurrencyNote(newValue:runningCount:)` — same in Tasks 9, 11.
- `FileNamingPreset` cases (`title, titleAndChannel, dateAndTitle, custom`) + `.matching(_:)` / `.template` / `.exampleSubtitle` — same in Tasks 9, 11.
- `Preferences.resetToDefaults()` (model) ← `AppModel.resetAllSettings()` (wrapper) — Task 14.
- Quality ladder `[("2160p",2160),("1440p",1440),("1080p",1080),("720p",720),("480p",480),("Best available",Int.max)]` — identical in Tasks 11 and 15 (Global Constraints).
- `ConfirmationRequest.init` labels — Task 14 Step 4 instructs verifying against `Confirming.swift` before use.

---

## Execution Handoff

**Plan complete and saved to `apps/media-grabber/docs/superpowers/plans/2026-08-31-media-grabber-phase-3.md`. Two execution options:**

**1. Subagent-Driven (recommended)** — I dispatch a fresh subagent per task, review between tasks, fast iteration.

**2. Inline Execution** — Execute tasks in this session using executing-plans, batch execution with checkpoints.

**Which approach?**
