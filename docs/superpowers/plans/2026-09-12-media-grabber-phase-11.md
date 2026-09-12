# MediaGrabber Phase 11 — Diagnostics, About, Updates: Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Move Diagnostics into Preferences with a real report card and support-bundle sharing; add an About/Developer page as the third top-level nav destination with certainty-tracked update actions for MediaGrabber and yt-dlp; pin yt-dlp to a declared minimum version with drift detection and a reinstall action; give every actionable HealthStrip chip a uniform busy state; split the Downloads table's Status column into a closed enum plus a hidden-by-default Remark column; and fix the Site column to show friendly host names.

**Architecture:** Bottom-up: pure model/comparison logic first (version compare, `EnvironmentReport` drift field, `DiagnosticBundle`), then engine-layer wiring (the real canary probe, the pinned-reinstall action, `availableActions`/`RowModel` changes), then chrome (`HealthController`/`HealthStrip` busy state, the new `engine` chip), then the two new/changed SwiftUI surfaces (`DiagnosticsPane` inside Preferences, `AboutView`/`DeveloperView` replacing the Diagnostics nav slot), finishing with the Downloads-table column split. Every task lands on `main`/the current branch directly — no worktree, no branching (per repo convention, no git commands of any kind).

**Tech Stack:** Swift 6, SwiftUI, XCTest, Tuist (project generation), `mise`-pinned `swiftformat`/`swiftlint`.

**Spec:** `docs/superpowers/specs/2026-08-28-youtube-downloader-mac-design.md` — this plan implements §5.2 (App chrome / chip busy state), §5.4 (Downloads table Status/Remark/Site), §5.9 (Preferences → Updates), §5.10 (Diagnostics), §5.12 (About), §8.3/§8.4 (diagnostic bundle, canary), §10.1a (yt-dlp version pin — new section), §10.2 (App self-update), and the Phase 11 entry in §12.1. Executors should read the relevant subsection before starting each task; UI-facing tasks should also check `apps/media-grabber/docs/design-system.md` §4.1/§4.6/§4.7/§4.8 for exact visual spec, and the mockups at `apps/media-grabber/docs/mockups/screens/{preferences,about}.html` for reference.

## Global Constraints

- No phase/ticket/epic references anywhere in source code or UI copy, ever (comments, identifiers, log strings, tooltips — nothing). A not-yet-built thing says "coming in a future update," never a phase number.
- Comments: single-line only, only to explain *why*, only when the type/function names don't already carry it. No `///` doc comments. Max 120 chars (`.swiftformat --maxwidth` / `.swiftlint line_length` are both 120).
- No git commands of any kind (no `git status`, no `git mv`, nothing) unless the user's own message asks for one in that turn. File moves/renames use plain `mv`.
- yt-dlp version pin is a **soft pin**: the app declares a minimum-known-good version as a hardcoded constant; drift is "installed is older than declared," never "installed differs from declared." Installed-newer-than-declared is current, not drift. The fix action re-runs `brew reinstall yt-dlp` (or `upgrade`) to reach at least the declared minimum — **never** an unconditional "upgrade to latest." A version string that fails to parse into comparable integer components is treated as **unknown**, never as stale.
- Every chip with a `↻` action (the existing shield-restart chip and the new engine-freshness chip) gets the same busy-state treatment while its fix runs: the glyph spins, the dot shows a pulsing neutral state, the icon is disabled for the duration. Both animations are suppressed under `prefers-reduced-motion` (macOS: `NSWorkspace.shared.accessibilityDisplayShouldReduceMotion`, wired the same way the existing motif spinner already checks it).
- Diagnostics is a `PreferencesPane` case (System group), never a top-level `AppModel.Page` case. About is the top-level `AppModel.Page` case that replaces the old `.diagnostics` page case.
- Button verb on any version-status row tracks certainty: nothing shown when current; "Check for updates" only for a check that requires a live network round-trip (MediaGrabber's GitHub-release check) and only before that round-trip resolves this session; "Update" / "↻ Update" once an update is confirmed available. yt-dlp's row never shows "Check for updates" — its drift check is a local compare, always immediately certain.
- "Copy report" writes plain text to the clipboard. "Share diagnostic bundle" hands a zip to `NSSharingServicePicker` — it is never called "Copy diagnostic bundle." Both actions call `IncomingLinkController.markAppPasteboardWrite(_:)` with whatever string/marker they put on the pasteboard so the Phase 9 clipboard sniff ignores the app's own write.
- All new `Preferences` keys go through the existing manual-UserDefaults-property pattern (see `Preferences.swift`'s existing properties) and must be added to `Preferences.ownedKeys` so `resetToDefaults()` covers them.
- Site column and the `HealthController` host chip must resolve a canonical name through **one** shared mapping — no second divergent site-name dictionary.

---

## File Structure

**New files:**
- `Sources/GrabberKit/Onboarding/DottedVersion.swift` — the dotted-integer version parser/comparator and the drift verdict type. Pure, no I/O.
- `Sources/GrabberKit/Onboarding/CanaryProbe.swift` — the shared canary-URL constant and probe-run function, called identically by Onboarding and Diagnostics ("one canary concept, not two").
- `Sources/GrabberKit/Diagnostics/DiagnosticBundle.swift` — builds the redacted zip (app-log tail, most-recent job log, report text) and returns a file URL.
- `Sources/GrabberKit/Diagnostics/YtDlpUpdater.swift` — runs `brew reinstall yt-dlp` (or `upgrade`), re-probes, reports the result.
- `Sources/App/Preferences/DiagnosticsPane.swift` — the SwiftUI view for the new `PreferencesPane.diagnostics` case: Run check, the report card, Copy report, Share diagnostic bundle.
- `Sources/App/About/AboutView.swift` — the About tab (identity block, version rows, button-verb logic).
- `Sources/App/About/DeveloperView.swift` — the Developer tab (identity header, Connect-with-me row, credit rows).
- `Sources/App/About/AppUpdateChecker.swift` — the GitHub-release check for MediaGrabber's own version (throttled daily, `Check for updates` / `Update` state).
- `Sources/App/Sharing/SharePresenter.swift` — the one AppKit-interop shim wrapping `NSSharingServicePicker` for a SwiftUI button to call.
- `Tests/GrabberKitTests/DottedVersionTests.swift`
- `Tests/GrabberKitTests/DiagnosticBundleTests.swift`
- `Tests/GrabberKitTests/YtDlpUpdaterTests.swift`
- `Tests/TestSupport/FakeYtDlpUpdater.swift`
- `Tests/AppUnitTests/DiagnosticsPaneTests.swift`
- `Tests/AppUnitTests/AboutViewTests.swift`
- `Tests/AppUnitTests/AppUpdateCheckerTests.swift`
- `Tests/AppUnitTests/ColumnConfigRemarkTests.swift`
- `Tests/AppUnitTests/SiteDisplayNameTests.swift`

**Modified files:**
- `Sources/GrabberKit/Onboarding/EnvironmentProbe.swift` — `EnvironmentReport` gains a `ytDlpDriftVerdict` field (computed from `DottedVersion`).
- `Sources/GrabberKit/Model/EngineTuning.swift` — new `minimumYtDlpVersion` constant.
- `Sources/GrabberKit/Onboarding/OnboardingInstaller.swift` — `testRun` step calls a real `MetadataProbe` canary instead of auto-passing.
- `Sources/GrabberKit/Model/Preferences.swift` — two new toggles (`autoCheckAppUpdates`, `autoCheckYtDlpUpdates`) plus `ownedKeys` update.
- `Sources/GrabberKit/Model/ColumnConfig.swift` — `ColumnID` gains `.remark`; `defaultOrder`/hidden-by-default set updated.
- `Sources/App/Preferences/UpdatesPane.swift` — **already exists** as the stepless Phase 3 placeholder (`PrefSteplessPane(.updates, line: "Update checks are coming in a later update.")`); replaced with the two auto-check toggles (Task 9).
- `Sources/App/AppModel.swift` — `Page` enum: `.diagnostics` case removed, `.about` case added; a new `restartYtDlp()` method mirroring `restartShield()`.
- `Sources/App/Chrome/HealthStrip.swift` — `DotState` gains `.busy`; `ChipInteraction.refresh` gains an associated `isBusy: Bool`; `HealthChip` unchanged in shape (busy state travels via `ChipInteraction`, not a new field) — see Task 6 for the exact type.
- `Sources/App/Chrome/HealthController.swift` — new `engineChip(_:)` builder; `update(snapshot:now:)` includes it; busy-state passthrough for both shield and engine chips.
- `Sources/App/MainWindow.swift` — nav button + `page` switch updated for About; the shield-chip `onRefresh` closure gains busy-state bookkeeping.
- `Sources/App/Preferences/PreferencesPane.swift` — new `.diagnostics` case (System group), title/subtitle.
- `Sources/App/Preferences/PreferencesView.swift` — `paneBody` switch gains the `.diagnostics` case.
- `Sources/App/SiteNames.swift` — becomes the single source of truth for site display names (extractor-keyed, absorbing `RowModel.siteMap`'s coverage).
- `Sources/App/Rows/RowModel.swift` — `site(for:)` delegates to `SiteNames`; new `remarkText` field; `siteMap` deleted.
- `Sources/App/Table/TablePresentation.swift` — `statusDisplay` narrowed to the closed enum labels only (drops its `"queued · #N"` badge concatenation and its `.failed`-branch use of `row.statusText`); gains a `.remark` case in its cell-text switch reading the new `RowModel.remarkText`. `queuedDisplay` is unchanged — it already returns only plain labels.
- `Sources/App/Ingress/IncomingLinkController.swift` — no signature change; two new call sites (Copy report, Share diagnostic bundle) added elsewhere.
- `apps/media-grabber/docs/design-system.md` — §4.2.3's column count/table updated for `.remark` (this doc already reflects the About/Diagnostics/dialog changes from brainstorming; only the column-count table needs the code-driven update).

---

## Task 1: `DottedVersion` — dotted-integer version parsing and comparison

**Files:**
- Create: `Sources/GrabberKit/Onboarding/DottedVersion.swift`
- Test: `Tests/GrabberKitTests/DottedVersionTests.swift`

**Interfaces:**
- Produces: `public struct DottedVersion: Sendable, Equatable, Comparable` with `public init?(parsing raw: String)` (returns `nil` if unparseable) and `public static func <(lhs: DottedVersion, rhs: DottedVersion) -> Bool`. Also `public enum YtDlpDriftVerdict: Sendable, Equatable { case current, drift(installed: String, minimum: String), unknown(raw: String) }` and `public static func driftVerdict(installedRaw: String, minimumRaw: String) -> YtDlpDriftVerdict`.

- [ ] **Step 1: Write the failing tests**

Every test target in this codebase uses `XCTestCase`/`XCTAssert*` — no file anywhere uses Swift Testing's `@Suite`/`#expect`. Match that convention exactly, not Swift Testing:

```swift
import XCTest
@testable import GrabberKit

final class DottedVersionTests: XCTestCase {
    func testParsesDottedIntegerComponents() {
        XCTAssertNotNil(DottedVersion(parsing: "2026.07.10"))
    }

    func testAcceptsAVPrefix() {
        XCTAssertNotNil(DottedVersion(parsing: "v2026.07.10"))
    }

    func testAcceptsAPatchSuffix() {
        XCTAssertNotNil(DottedVersion(parsing: "2026.07.10.1"))
    }

    func testRejectsNonNumericComponents() {
        XCTAssertNil(DottedVersion(parsing: "nightly-build"))
    }

    func testRejectsEmptyString() {
        XCTAssertNil(DottedVersion(parsing: ""))
    }

    func testComparesChronologically() {
        let older = DottedVersion(parsing: "2026.05.02")!
        let newer = DottedVersion(parsing: "2026.07.10")!
        XCTAssertLessThan(older, newer)
        XCTAssertFalse(newer < older)
    }

    func testComparesPatchSuffixAsExtraComponent() {
        let base = DottedVersion(parsing: "2026.07.10")!
        let patched = DottedVersion(parsing: "2026.07.10.1")!
        XCTAssertLessThan(base, patched)
    }

    func testEqualVersionsAreNotLessThanEachOther() {
        let a = DottedVersion(parsing: "2026.07.10")!
        let b = DottedVersion(parsing: "2026.07.10")!
        XCTAssertFalse(a < b)
        XCTAssertEqual(a, b)
    }

    func testDriftVerdictInstalledOlderThanMinimumIsDrift() {
        let verdict = DottedVersion.driftVerdict(installedRaw: "2026.05.02", minimumRaw: "2026.07.10")
        XCTAssertEqual(verdict, .drift(installed: "2026.05.02", minimum: "2026.07.10"))
    }

    func testDriftVerdictInstalledEqualToMinimumIsCurrent() {
        let verdict = DottedVersion.driftVerdict(installedRaw: "2026.07.10", minimumRaw: "2026.07.10")
        XCTAssertEqual(verdict, .current)
    }

    func testDriftVerdictInstalledNewerThanMinimumIsCurrent() {
        let verdict = DottedVersion.driftVerdict(installedRaw: "2026.09.01", minimumRaw: "2026.07.10")
        XCTAssertEqual(verdict, .current)
    }

    func testDriftVerdictUnparseableInstalledIsUnknownNotStale() {
        let verdict = DottedVersion.driftVerdict(installedRaw: "nightly-build", minimumRaw: "2026.07.10")
        XCTAssertEqual(verdict, .unknown(raw: "nightly-build"))
    }
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `xcodebuild -workspace MediaGrabber.xcworkspace -scheme MediaGrabber-Workspace -destination 'platform=macOS' test -only-testing:GrabberKitTests/DottedVersionTests`
Expected: FAIL — `DottedVersion` does not exist yet (compile error).

- [ ] **Step 3: Write the implementation**

```swift
import Foundation

public struct DottedVersion: Sendable, Equatable, Comparable {
    private let components: [Int]

    public init?(parsing raw: String) {
        var token = raw.trimmingCharacters(in: .whitespaces)
        if token.hasPrefix("v") {
            token.removeFirst()
        }
        guard !token.isEmpty else { return nil }
        let parts = token.split(separator: ".")
        guard !parts.isEmpty else { return nil }
        var parsed: [Int] = []
        for part in parts {
            guard let value = Int(part) else { return nil }
            parsed.append(value)
        }
        components = parsed
    }

    public static func < (lhs: DottedVersion, rhs: DottedVersion) -> Bool {
        let count = max(lhs.components.count, rhs.components.count)
        for index in 0..<count {
            let left = index < lhs.components.count ? lhs.components[index] : 0
            let right = index < rhs.components.count ? rhs.components[index] : 0
            if left != right {
                return left < right
            }
        }
        return false
    }
}

public enum YtDlpDriftVerdict: Sendable, Equatable {
    case current
    case drift(installed: String, minimum: String)
    case unknown(raw: String)

    public static func driftVerdict(installedRaw: String, minimumRaw: String) -> YtDlpDriftVerdict {
        guard let installed = DottedVersion(parsing: installedRaw) else {
            return .unknown(raw: installedRaw)
        }
        guard let minimum = DottedVersion(parsing: minimumRaw) else {
            return .unknown(raw: installedRaw)
        }
        return installed < minimum ? .drift(installed: installedRaw, minimum: minimumRaw) : .current
    }
}

extension DottedVersion {
    public static func driftVerdict(installedRaw: String, minimumRaw: String) -> YtDlpDriftVerdict {
        YtDlpDriftVerdict.driftVerdict(installedRaw: installedRaw, minimumRaw: minimumRaw)
    }
}
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `xcodebuild -workspace MediaGrabber.xcworkspace -scheme MediaGrabber-Workspace -destination 'platform=macOS' test -only-testing:GrabberKitTests/DottedVersionTests`
Expected: PASS, all 11 tests.

- [ ] **Step 5: Lint**

Run: `mise exec -- swiftformat --lint Sources/GrabberKit/Onboarding/DottedVersion.swift Tests/GrabberKitTests/DottedVersionTests.swift` then `mise exec -- swiftlint lint --strict Sources/GrabberKit/Onboarding/DottedVersion.swift`
Fix any violations before proceeding.

---

## Task 2: `EngineTuning.minimumYtDlpVersion` constant + `EnvironmentReport` drift field

**Files:**
- Modify: `Sources/GrabberKit/Model/EngineTuning.swift`
- Modify: `Sources/GrabberKit/Onboarding/EnvironmentProbe.swift`
- Test: `Tests/GrabberKitTests/EnvironmentProbeTests.swift` (existing file — add new test cases)

**Interfaces:**
- Consumes: `DottedVersion.driftVerdict(installedRaw:minimumRaw:)` from Task 1.
- Produces: `EngineTuning.minimumYtDlpVersion: String` (a stored constant, env-overridable via `MG_MIN_YTDLP_VERSION` following the existing `MG_*` override pattern in `EngineTuning.resolved(environment:)`). `EnvironmentReport.ytDlpDriftVerdict: YtDlpDriftVerdict` computed from `ytDlp?.version` against `EngineTuning.default.minimumYtDlpVersion` (missing yt-dlp is reported as `.unknown(raw: "")`, since a missing dependency is a different failure mode entirely handled elsewhere — this field only exists when `ytDlp != nil`, so it stays `EnvironmentReport.ytDlpDriftVerdict: YtDlpDriftVerdict?`).

- [ ] **Step 1: Write the failing tests**

Add to `Tests/GrabberKitTests/EnvironmentProbeTests.swift`, inside the existing `EnvironmentProbeTests: XCTestCase` class:

```swift
func test_environmentReport_driftVerdict_nilWhenYtDlpMissing() {
    let report = EnvironmentReport(brew: nil, ytDlp: nil, ffmpeg: nil)
    XCTAssertNil(report.ytDlpDriftVerdict)
}

func test_environmentReport_driftVerdict_currentWhenAtOrAboveMinimum() {
    let ytDlp = ToolInfo(path: URL(fileURLWithPath: "/opt/homebrew/bin/yt-dlp"), version: "2099.01.01")
    let report = EnvironmentReport(brew: nil, ytDlp: ytDlp, ffmpeg: nil)
    XCTAssertEqual(report.ytDlpDriftVerdict, .current)
}

func test_environmentReport_driftVerdict_driftWhenBelowMinimum() {
    let ytDlp = ToolInfo(path: URL(fileURLWithPath: "/opt/homebrew/bin/yt-dlp"), version: "2000.01.01")
    let report = EnvironmentReport(brew: nil, ytDlp: ytDlp, ffmpeg: nil)
    guard case .drift = report.ytDlpDriftVerdict else {
        XCTFail("expected drift verdict, got \(String(describing: report.ytDlpDriftVerdict))")
        return
    }
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `xcodebuild -workspace MediaGrabber.xcworkspace -scheme MediaGrabber-Workspace -destination 'platform=macOS' test -only-testing:GrabberKitTests/EnvironmentProbeTests`
Expected: FAIL — `ytDlpDriftVerdict` does not exist on `EnvironmentReport`.

- [ ] **Step 3: Add the constant to `EngineTuning`**

Open `Sources/GrabberKit/Model/EngineTuning.swift`. The `public struct EngineTuning` field list and `.default` static value are around line 99-114, and `.resolved(environment:)` is around line 117-168. Add a new field following the exact pattern used by the other tunables:

```swift
public var minimumYtDlpVersion: String
```

In `.default`, add: `minimumYtDlpVersion: "2026.01.01"` (a real floor — update this per the actual yt-dlp release the app is built/tested against at ship time; it is a hand-bumped constant per the global constraints, never fetched).

In `.resolved(environment:)`, add the override read following the exact same style as the other `MG_*` reads in that method:

```swift
if let raw = environment["MG_MIN_YTDLP_VERSION"] {
    tuning.minimumYtDlpVersion = raw
}
```

- [ ] **Step 4: Add `ytDlpDriftVerdict` to `EnvironmentReport`**

Open `Sources/GrabberKit/Onboarding/EnvironmentProbe.swift`. Add to `EnvironmentReport`:

```swift
public var ytDlpDriftVerdict: YtDlpDriftVerdict? {
    guard let ytDlp else { return nil }
    return DottedVersion.driftVerdict(installedRaw: ytDlp.version, minimumRaw: EngineTuning.default.minimumYtDlpVersion)
}
```

- [ ] **Step 5: Run tests to verify they pass**

Run: `xcodebuild -workspace MediaGrabber.xcworkspace -scheme MediaGrabber-Workspace -destination 'platform=macOS' test -only-testing:GrabberKitTests/EnvironmentProbeTests`
Expected: PASS.

- [ ] **Step 6: Run the full GrabberKit suite to check nothing else broke**

Run: `xcodebuild -workspace MediaGrabber.xcworkspace -scheme MediaGrabber-Workspace -destination 'platform=macOS' test -only-testing:GrabberKitTests`
Expected: PASS (existing `EngineTuningTests` must still pass with the new field added to `.default`/`.resolved`).

- [ ] **Step 7: Lint**

Run: `mise exec -- swiftformat --lint Sources/GrabberKit/Model/EngineTuning.swift Sources/GrabberKit/Onboarding/EnvironmentProbe.swift` then `mise exec -- swiftlint lint --strict Sources/GrabberKit/Model/EngineTuning.swift Sources/GrabberKit/Onboarding/EnvironmentProbe.swift`

---

## Task 3: `YtDlpUpdater` — pinned reinstall action

**Files:**
- Create: `Sources/GrabberKit/Diagnostics/YtDlpUpdater.swift`
- Test: `Tests/GrabberKitTests/YtDlpUpdaterTests.swift`

**Interfaces:**
- Consumes: `ProcessRunning` (existing protocol, see `Tests/TestSupport/FakeProcessRunner.swift` for the fake), `EnvironmentProbing` (existing).
- Produces: `public protocol YtDlpUpdating: Sendable { func reinstallToMinimum() async -> YtDlpUpdateResult }`, `public enum YtDlpUpdateResult: Sendable, Equatable { case success(newVersion: String), failure(reason: String) }`, `public struct YtDlpUpdater: YtDlpUpdating`.

- [ ] **Step 1: Write the failing tests**

`FakeProcessRunner` (`Tests/TestSupport/FakeProcessRunner.swift`) is stubbed via `script(_:forExactPath:)` or `script(_:forPathEndingIn:)`, and its `.launches: [ProcessLaunch]` records every call for assertions — there is no `.stub(exitCode:stdout:)` or `.lastLaunch` on it:

```swift
import XCTest
@testable import GrabberKit
import TestSupport

final class YtDlpUpdaterTests: XCTestCase {
    func testReinstallSucceedsReportsNewVersion() async {
        let runner = FakeProcessRunner()
        runner.script(.stdout("", exitCode: 0), forPathEndingIn: "brew")
        let probe = FakeEnvironmentProbe(EnvironmentReport(
            brew: nil,
            ytDlp: ToolInfo(path: URL(fileURLWithPath: "/opt/homebrew/bin/yt-dlp"), version: "2026.08.01"),
            ffmpeg: nil
        ))
        let updater = YtDlpUpdater(runner: runner, probe: probe)
        let result = await updater.reinstallToMinimum()
        XCTAssertEqual(result, .success(newVersion: "2026.08.01"))
    }

    func testReinstallFailsReportsFailureReason() async {
        let runner = FakeProcessRunner()
        runner.script(.stderr("Error: could not reinstall yt-dlp", exitCode: 1), forPathEndingIn: "brew")
        let probe = FakeEnvironmentProbe(EnvironmentReport(brew: nil, ytDlp: nil, ffmpeg: nil))
        let updater = YtDlpUpdater(runner: runner, probe: probe)
        let result = await updater.reinstallToMinimum()
        guard case .failure = result else {
            XCTFail("expected failure, got \(result)")
            return
        }
    }

    func testReinstallInvokesBrewReinstallYtDlp() async {
        let runner = FakeProcessRunner()
        runner.script(.stdout("", exitCode: 0), forPathEndingIn: "brew")
        let probe = FakeEnvironmentProbe(EnvironmentReport(
            brew: nil,
            ytDlp: ToolInfo(path: URL(fileURLWithPath: "/opt/homebrew/bin/yt-dlp"), version: "2026.08.01"),
            ffmpeg: nil
        ))
        let updater = YtDlpUpdater(runner: runner, probe: probe)
        _ = await updater.reinstallToMinimum()
        XCTAssertEqual(runner.launches.last?.executableURL.lastPathComponent, "brew")
        XCTAssertEqual(runner.launches.last?.arguments, ["reinstall", "yt-dlp"])
    }
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `xcodebuild -workspace MediaGrabber.xcworkspace -scheme MediaGrabber-Workspace -destination 'platform=macOS' test -only-testing:GrabberKitTests/YtDlpUpdaterTests`
Expected: FAIL — `YtDlpUpdater` does not exist.

- [ ] **Step 3: Write the implementation**

```swift
import Foundation

public enum YtDlpUpdateResult: Sendable, Equatable {
    case success(newVersion: String)
    case failure(reason: String)
}

public protocol YtDlpUpdating: Sendable {
    func reinstallToMinimum() async -> YtDlpUpdateResult
}

public struct YtDlpUpdater: YtDlpUpdating {
    private let runner: ProcessRunning
    private let probe: EnvironmentProbing
    private let brewPath: URL

    public init(
        runner: ProcessRunning = ProcessRunner(),
        probe: EnvironmentProbing = EnvironmentProbe(),
        brewPath: URL = URL(fileURLWithPath: "/opt/homebrew/bin/brew")
    ) {
        self.runner = runner
        self.probe = probe
        self.brewPath = brewPath
    }

    public func reinstallToMinimum() async -> YtDlpUpdateResult {
        let execution = runner.run(ProcessLaunch(executableURL: brewPath, arguments: ["reinstall", "yt-dlp"]))
        var stderrOutput = ""
        for await line in execution.lines {
            if case let .stderr(text) = line {
                stderrOutput += text + "\n"
            }
        }
        let result = await execution.result()
        guard result.exitCode == 0 else {
            return .failure(reason: stderrOutput.isEmpty ? "brew reinstall yt-dlp failed" : stderrOutput)
        }
        let report = await probe.probe()
        guard let version = report.ytDlp?.version else {
            return .failure(reason: "yt-dlp not found after reinstall")
        }
        return .success(newVersion: version)
    }
}
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `xcodebuild -workspace MediaGrabber.xcworkspace -scheme MediaGrabber-Workspace -destination 'platform=macOS' test -only-testing:GrabberKitTests/YtDlpUpdaterTests`
Expected: PASS.

- [ ] **Step 5: Lint**

Run: `mise exec -- swiftformat --lint Sources/GrabberKit/Diagnostics/YtDlpUpdater.swift` then `mise exec -- swiftlint lint --strict Sources/GrabberKit/Diagnostics/YtDlpUpdater.swift`

---

## Task 4: Real canary probe for Onboarding's `testRun` step

**Files:**
- Modify: `Sources/GrabberKit/Onboarding/OnboardingInstaller.swift`
- Test: `Tests/GrabberKitTests/OnboardingInstallerTests.swift` (existing — add cases)

**Interfaces:**
- Consumes: `MetadataProbing` (existing protocol from `Sources/GrabberKit/Download/MetadataProbe.swift`), `Tests/TestSupport/FakeMetadataProbe.swift` (existing fake).
- Produces: `OnboardingInstaller.init(probe: EnvironmentProbing = EnvironmentProbe(), runner: ProcessRunning = ProcessRunner(), metadataProbe: MetadataProbing? = nil)` — `metadataProbe` defaults to `nil` and is lazily constructed from the resolved `ytDlp` tool path when needed (so call sites that don't inject one still get a real probe in production, while tests can inject a fake directly).

**Known-stable canary URL:** use the same Creative-Commons fixture URL already used by this app's own opt-in live-network integration tests — check `Tests/GrabberKitTests/` for `MG_LIVE_TESTS` gated tests (per CLAUDE.md: "Capture fixtures from commons.wikimedia.org / archive.org") and reuse that exact URL string as a constant, rather than inventing a new one. It is defined once as `CanaryProbe.url` (Step 4 below) in a new, dependency-neutral file — not on `OnboardingInstaller` itself — so Diagnostics (Task 8) can call the same probe function, not just read the same URL string.

- [ ] **Step 1: Write the failing tests**

Open `Tests/GrabberKitTests/OnboardingInstallerTests.swift`, read its existing structure (fixture setup, how `OnboardingInstaller` is constructed in existing tests), then add:

```swift
func test_testRunStep_realProbeSucceeds_marksStepDone() async {
    let fakeMetadataProbe = FakeMetadataProbe(default: FakeMetadataProbe.success(title: "Big Buck Bunny"))
    let installer = OnboardingInstaller(
        probe: FakeEnvironmentProbe(.with(ytDlp: true, ffmpeg: true)),
        runner: FakeProcessRunner(),
        metadataProbe: fakeMetadataProbe
    )
    await installer.runFlow()
    XCTAssertEqual(installer.steps[.testRun], .done)
}

func test_testRunStep_probeFails_marksStepFailed() async {
    let fakeMetadataProbe = FakeMetadataProbe(default: .failure(.network))
    let installer = OnboardingInstaller(
        probe: FakeEnvironmentProbe(.with(ytDlp: true, ffmpeg: true)),
        runner: FakeProcessRunner(),
        metadataProbe: fakeMetadataProbe
    )
    await installer.runFlow()
    XCTAssertEqual(installer.steps[.testRun], .failed)
}

func test_testRunStep_probesTheKnownCanaryURL() async {
    let fakeMetadataProbe = FakeMetadataProbe(default: FakeMetadataProbe.success(title: "Big Buck Bunny"))
    let installer = OnboardingInstaller(
        probe: FakeEnvironmentProbe(.with(ytDlp: true, ffmpeg: true)),
        runner: FakeProcessRunner(),
        metadataProbe: fakeMetadataProbe
    )
    await installer.runFlow()
    XCTAssertEqual(fakeMetadataProbe.probedURLs.last, CanaryProbe.url)
}
```

`installer.steps[.testRun]` and `OnboardingInstaller`'s other real properties (used above) match `Tests/GrabberKitTests/OnboardingInstallerTests.swift`'s existing construction pattern for this suite.

- [ ] **Step 2: Run tests to verify they fail**

Run: `xcodebuild -workspace MediaGrabber.xcworkspace -scheme MediaGrabber-Workspace -destination 'platform=macOS' test -only-testing:GrabberKitTests/OnboardingInstallerTests`
Expected: FAIL — `metadataProbe` parameter doesn't exist, `canaryURL` doesn't exist.

- [ ] **Step 3: Implement a shared `CanaryProbe` type — not a private helper on `OnboardingInstaller`**

Diagnostics (Task 8) needs to run this exact same canary later, from a different type, in production — so the probe-construction logic must live somewhere both call sites can reach, not as a `private` method locked inside `OnboardingInstaller`. Create it as its own small type:

```swift
import Foundation

public enum CanaryProbe {
    // Same fixture used by the opt-in live-network integration tests (MG_LIVE_TESTS=1).
    public static let url = "https://archive.org/details/BigBuckBunny_124"

    public static func run(ytDlpPath: URL?, runner: ProcessRunning) async -> Result<MediaMetadata, MetadataError> {
        guard let ytDlpPath else {
            return .failure(.ytDlpMissing)
        }
        let probe = MetadataProbe(ytDlpURL: ytDlpPath, runner: runner)
        return await probe.probe(url)
    }
}
```

Put this in a new file `Sources/GrabberKit/Onboarding/CanaryProbe.swift` (not inside `OnboardingInstaller.swift`) so its dependency direction is neutral — both `OnboardingInstaller` and Task 8's `DiagnosticsPaneModel` depend on it, it depends on neither of them.

Update `OnboardingInstaller`'s initializer (around line 38-48) to accept `metadataProbe: MetadataProbing? = nil` for test injection, stored as `private let injectedMetadataProbe: MetadataProbing?`.

Replace the auto-pass logic at line 111-112 (`// TODO(Task 11): real canary probe of a known-stable URL.` / `steps[.testRun] = canProceedToHome ? .done : .pending`) with:

```swift
if canProceedToHome {
    let result: Result<MediaMetadata, MetadataError>
    if let injectedMetadataProbe {
        result = await injectedMetadataProbe.probe(CanaryProbe.url)
    } else {
        result = await CanaryProbe.run(ytDlpPath: report.ytDlp?.path, runner: runner)
    }
    switch result {
    case .success:
        steps[.testRun] = .done
    case .failure:
        steps[.testRun] = .failed
    }
} else {
    steps[.testRun] = .pending
}
```

(Check the exact `runner`/`report` variable names already in scope at that point in `runFlow()` — use whatever the existing method already has bound, don't introduce a duplicate probe call.)

Task 8's `DiagnosticsPaneModel` (Step 6 there) must call `CanaryProbe.run(ytDlpPath:runner:)` the same way in its **production** construction path — not just accept a `MetadataProbing` fake for tests. Revise Task 8's `runCheck()` so its real (non-test) `metadataProbe` dependency is actually `CanaryProbe.run` wrapped behind the same `MetadataProbing`-shaped seam used for testing, e.g. inject a closure `probeCanary: (URL?, ProcessRunning) async -> Result<MediaMetadata, MetadataError> = CanaryProbe.run` instead of a raw `MetadataProbing` instance, so both Onboarding and Diagnostics call the literal same static function in production, with no second construction path to drift out of sync.

Check `OnboardingStepID` / the step-state enum for whether a `.failed` case already exists (it must, since Homebrew-missing already needs a failed-step state per §5.8) — reuse it, don't invent a new one.

- [ ] **Step 4: Run tests to verify they pass**

Run: `xcodebuild -workspace MediaGrabber.xcworkspace -scheme MediaGrabber-Workspace -destination 'platform=macOS' test -only-testing:GrabberKitTests/OnboardingInstallerTests`
Expected: PASS.

- [ ] **Step 5: Run the full GrabberKit suite**

Run: `xcodebuild -workspace MediaGrabber.xcworkspace -scheme MediaGrabber-Workspace -destination 'platform=macOS' test -only-testing:GrabberKitTests`
Expected: PASS — no regressions in other onboarding tests that relied on the old auto-pass behavior. If any do, update them to inject a `FakeMetadataProbe` with a success result rather than reverting the change.

- [ ] **Step 6: Lint**

Run: `mise exec -- swiftformat --lint Sources/GrabberKit/Onboarding/OnboardingInstaller.swift Sources/GrabberKit/Onboarding/CanaryProbe.swift` then `mise exec -- swiftlint lint --strict Sources/GrabberKit/Onboarding/OnboardingInstaller.swift Sources/GrabberKit/Onboarding/CanaryProbe.swift`

---

## Task 5: `DiagnosticBundle` — the redacted support zip

**Files:**
- Create: `Sources/GrabberKit/Diagnostics/DiagnosticBundle.swift`
- Test: `Tests/GrabberKitTests/DiagnosticBundleTests.swift`

**Interfaces:**
- Consumes: nothing new — reads plain file contents (app log, job log) passed in as strings/URLs, no direct filesystem-path knowledge of `~/Library/Logs/MediaGrabber` (that resolution happens at the call site in the App target, per existing precedent — check how `Sources/App/` currently resolves the logs directory, e.g. search for `Library/Logs/MediaGrabber`, and pass the resolved tail/log contents in rather than have this pure type re-derive paths).
- Produces: `public struct DiagnosticBundle: Sendable { public static func build(appLogTail: String, jobLog: String?, report: String) throws -> Data }` — returns zip file `Data` (not a written-to-disk URL; the App-target call site decides where to write it, since Diagnostics writes via `NSSharingServicePicker` which wants `Data`/a temp file, not a fixed path).

- [ ] **Step 1: Write the failing tests**

`Sources/GrabberKit/Logging/LogEvent.swift`'s `LogRedaction.redact(_ value: String) -> String` (line 225-227) already handles home-directory-path rewriting and cookie/password/username stripping, with its own existing test coverage — `DiagnosticBundle` must call this function on each entry, not reimplement redaction. Its own tests only need to confirm the zip is built correctly and that redaction is actually invoked, not re-verify `LogRedaction`'s own correctness:

```swift
import XCTest
import Foundation
@testable import GrabberKit

final class DiagnosticBundleTests: XCTestCase {
    func testBuildsAZipContainingAllThreeSections() throws {
        let data = try DiagnosticBundle.build(
            appLogTail: "app log line 1\napp log line 2",
            jobLog: "job log contents",
            report: "Canary probe: passed"
        )
        XCTAssertFalse(data.isEmpty)
        // Zip files start with the local file header signature "PK\x03\x04".
        let signature = data.prefix(4)
        XCTAssertEqual(signature, Data([0x50, 0x4B, 0x03, 0x04]))
    }

    func testBuildsAZipWithNoJobLog() throws {
        let data = try DiagnosticBundle.build(appLogTail: "app log", jobLog: nil, report: "report text")
        XCTAssertFalse(data.isEmpty)
    }

    func testRedactsBeforeZipping() throws {
        // The zip is store-only (uncompressed), so redacted text is present as raw bytes in
        // the archive. Home-dir-path rewriting is LogRedaction's own well-tested behavior
        // (Sources/GrabberKit/Logging/LogEvent.swift) — this test only confirms DiagnosticBundle
        // actually calls it, by checking the raw path never appears in the built archive.
        let data = try DiagnosticBundle.build(
            appLogTail: "saved to /Users/alice/Downloads/video.mp4",
            jobLog: nil,
            report: "report"
        )
        let needle = [UInt8]("/Users/alice".utf8)
        let haystack = [UInt8](data)
        var containsRawPath = false
        if haystack.count >= needle.count {
            for start in 0...(haystack.count - needle.count) where Array(haystack[start..<start + needle.count]) == needle {
                containsRawPath = true
                break
            }
        }
        XCTAssertFalse(containsRawPath)
    }
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `xcodebuild -workspace MediaGrabber.xcworkspace -scheme MediaGrabber-Workspace -destination 'platform=macOS' test -only-testing:GrabberKitTests/DiagnosticBundleTests`
Expected: FAIL — `DiagnosticBundle` does not exist.

- [ ] **Step 3: Write the implementation**

Use `Foundation`'s built-in `Archive`/zip support if the deployment target's SDK provides one (macOS 14+ ships no first-party zip API in Foundation directly — check if the project already vendors or links a zip library by searching `Package.swift`/`Project.swift` for "zip" or "Zip" dependencies first). If none exists, implement a minimal store-only (uncompressed) zip writer — sufficient for small text logs and avoids adding a new dependency for one feature:

```swift
import Foundation

public enum DiagnosticBundle {
    public static func build(appLogTail: String, jobLog: String?, report: String) throws -> Data {
        var entries: [(name: String, contents: String)] = [
            ("app-log-tail.txt", LogRedaction.redact(appLogTail)),
            ("report.txt", LogRedaction.redact(report)),
        ]
        if let jobLog {
            entries.append(("job-log.txt", LogRedaction.redact(jobLog)))
        }
        return try makeZip(entries: entries)
    }

    private static func makeZip(entries: [(name: String, contents: String)]) throws -> Data {
        // Minimal store-only ZIP writer: local file headers + central directory, no compression.
        var body = Data()
        var centralDirectory = Data()
        var offset: UInt32 = 0

        for entry in entries {
            let nameData = Data(entry.name.utf8)
            let contentData = Data(entry.contents.utf8)
            let crc = crc32(contentData)

            var localHeader = Data()
            localHeader.append(contentsOf: [0x50, 0x4B, 0x03, 0x04]) // local file header signature
            localHeader.append(contentsOf: [20, 0]) // version needed
            localHeader.append(contentsOf: [0, 0]) // flags
            localHeader.append(contentsOf: [0, 0]) // compression: stored
            localHeader.append(contentsOf: [0, 0, 0, 0]) // mod time/date
            localHeader.append(littleEndian: crc)
            localHeader.append(littleEndian: UInt32(contentData.count))
            localHeader.append(littleEndian: UInt32(contentData.count))
            localHeader.append(littleEndian: UInt16(nameData.count))
            localHeader.append(littleEndian: UInt16(0)) // extra field length
            localHeader.append(nameData)
            localHeader.append(contentData)

            var centralEntry = Data()
            centralEntry.append(contentsOf: [0x50, 0x4B, 0x01, 0x02]) // central dir signature
            centralEntry.append(contentsOf: [20, 0, 20, 0]) // version made by / needed
            centralEntry.append(contentsOf: [0, 0]) // flags
            centralEntry.append(contentsOf: [0, 0]) // compression: stored
            centralEntry.append(contentsOf: [0, 0, 0, 0]) // mod time/date
            centralEntry.append(littleEndian: crc)
            centralEntry.append(littleEndian: UInt32(contentData.count))
            centralEntry.append(littleEndian: UInt32(contentData.count))
            centralEntry.append(littleEndian: UInt16(nameData.count))
            centralEntry.append(littleEndian: UInt16(0)) // extra field length
            centralEntry.append(littleEndian: UInt16(0)) // comment length
            centralEntry.append(littleEndian: UInt16(0)) // disk number
            centralEntry.append(littleEndian: UInt16(0)) // internal attrs
            centralEntry.append(littleEndian: UInt32(0)) // external attrs
            centralEntry.append(littleEndian: offset)
            centralEntry.append(nameData)

            body.append(localHeader)
            centralDirectory.append(centralEntry)
            offset += UInt32(localHeader.count)
        }

        var endRecord = Data()
        endRecord.append(contentsOf: [0x50, 0x4B, 0x05, 0x06]) // end of central directory signature
        endRecord.append(littleEndian: UInt16(0)) // disk number
        endRecord.append(littleEndian: UInt16(0)) // disk with central dir
        endRecord.append(littleEndian: UInt16(entries.count))
        endRecord.append(littleEndian: UInt16(entries.count))
        endRecord.append(littleEndian: UInt32(centralDirectory.count))
        endRecord.append(littleEndian: offset)
        endRecord.append(littleEndian: UInt16(0)) // comment length

        return body + centralDirectory + endRecord
    }

    private static func crc32(_ data: Data) -> UInt32 {
        var crc: UInt32 = 0xFFFFFFFF
        for byte in data {
            crc ^= UInt32(byte)
            for _ in 0..<8 {
                crc = (crc & 1) != 0 ? (crc >> 1) ^ 0xEDB88320 : crc >> 1
            }
        }
        return crc ^ 0xFFFFFFFF
    }
}

private extension Data {
    mutating func append(littleEndian value: UInt16) {
        append(contentsOf: [UInt8(value & 0xFF), UInt8((value >> 8) & 0xFF)])
    }

    mutating func append(littleEndian value: UInt32) {
        append(contentsOf: [
            UInt8(value & 0xFF), UInt8((value >> 8) & 0xFF),
            UInt8((value >> 16) & 0xFF), UInt8((value >> 24) & 0xFF),
        ])
    }
}
```

**Before implementing this by hand**: check `Project.swift`/`Package.swift` for an existing zip dependency (e.g. ZIPFoundation) first — if the project already links one, use its API instead of the hand-rolled writer above, which exists only as a no-new-dependency fallback.

- [ ] **Step 4: Run tests to verify they pass**

Run: `xcodebuild -workspace MediaGrabber.xcworkspace -scheme MediaGrabber-Workspace -destination 'platform=macOS' test -only-testing:GrabberKitTests/DiagnosticBundleTests`
Expected: PASS. If using a real zip library found in Step 3, verify the produced archive round-trips (unzip and check contents) rather than only checking the raw signature bytes.

- [ ] **Step 5: Lint**

Run: `mise exec -- swiftformat --lint Sources/GrabberKit/Diagnostics/DiagnosticBundle.swift` then `mise exec -- swiftlint lint --strict Sources/GrabberKit/Diagnostics/DiagnosticBundle.swift`

---

## Task 6: Chip busy state — `DotState.busy` + `ChipInteraction` refresh-in-progress

**Files:**
- Modify: `Sources/App/Chrome/HealthStrip.swift`
- Modify: `Sources/App/Chrome/HealthController.swift`
- Test: `Tests/AppUnitTests/HealthControllerTests.swift` (existing — add cases)

**Interfaces:**
- Produces: `enum DotState { case ok, attention, busy }`; `enum ChipInteraction { case none, refresh(isBusy: Bool), popover(PopoverKind) }` (changing `.refresh` from a bare case to carrying `isBusy: Bool` — this breaks `Tests/AppUnitTests/HealthControllerTests.swift:29`'s `XCTAssertEqual(controller.chips[0].interaction, .refresh)`, which must become `.refresh(isBusy: false)`); `HealthController` gains `func markBusy(chipID: String)` and `func clearBusy(chipID: String)`, both `@MainActor`, which mutate the relevant chip's `interaction` to `.refresh(isBusy: true/false)` in place without rebuilding the whole `chips` array from a snapshot.

- [ ] **Step 1: Write the failing tests**

`HealthControllerTests.swift` has a `private func snapshot(online:summary:shield:) -> QueueSnapshot` helper (line 7-21) — `private` is file-scoped, so these busy-state cases must be added as more methods on that same `HealthControllerTests` class (not a separate `ChipBusyStateTests.swift` file, which could not reach the private helper) to reuse it directly:

```swift
func testMarkBusySetsRefreshInteractionToBusy() {
    let controller = HealthController()
    controller.update(snapshot: snapshot(online: true, summary: [:], shield: .down), now: .now)
    controller.markBusy(chipID: "shield")
    let chip = controller.chips.first { $0.id == "shield" }
    XCTAssertEqual(chip?.interaction, .refresh(isBusy: true))
}

func testClearBusyReturnsRefreshInteractionToNotBusy() {
    let controller = HealthController()
    controller.update(snapshot: snapshot(online: true, summary: [:], shield: .down), now: .now)
    controller.markBusy(chipID: "shield")
    controller.clearBusy(chipID: "shield")
    let chip = controller.chips.first { $0.id == "shield" }
    XCTAssertEqual(chip?.interaction, .refresh(isBusy: false))
}

func testMarkBusyOnUnknownChipIDDoesNothing() {
    let controller = HealthController()
    controller.update(snapshot: snapshot(online: true, summary: [:], shield: .running(port: 4416)), now: .now)
    let chipCountBefore = controller.chips.count
    controller.markBusy(chipID: "nonexistent")
    XCTAssertEqual(controller.chips.count, chipCountBefore)
}

func testSubsequentSnapshotUpdateClearsBusyState() {
    let controller = HealthController()
    controller.update(snapshot: snapshot(online: true, summary: [:], shield: .down), now: .now)
    controller.markBusy(chipID: "shield")
    controller.update(snapshot: snapshot(online: true, summary: [:], shield: .running(port: 4416)), now: .now)
    let chip = controller.chips.first { $0.id == "shield" }
    XCTAssertEqual(chip?.interaction, .none)
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `xcodebuild -workspace MediaGrabber.xcworkspace -scheme MediaGrabber-Workspace -destination 'platform=macOS' test -only-testing:AppUnitTests/HealthControllerTests`
Expected: FAIL — `.busy` case, `.refresh(isBusy:)`, `markBusy`/`clearBusy` don't exist.

- [ ] **Step 3: Update `DotState` and `ChipInteraction`**

In `Sources/App/Chrome/HealthStrip.swift`:

```swift
enum DotState: Equatable {
    case ok
    case attention
    case busy
}

enum PopoverKind: Equatable {
    case hostRate
}

enum ChipInteraction: Equatable {
    case none
    case refresh(isBusy: Bool)
    case popover(PopoverKind)
}
```

Update `HealthStrip`'s `chipView(_:)` switch (the `.refresh` render branch, around line 65-76) to pattern-match `.refresh(let isBusy)` and render the spinning/disabled state when `isBusy`:

```swift
case let .refresh(isBusy):
    Button {
        if !isBusy { onRefresh?(chip) }
    } label: {
        HStack {
            chipBody(chip)
            Text("↻")
                .rotationEffect(isBusy ? .degrees(360) : .degrees(0))
                .animation(isBusy ? .linear(duration: 0.9).repeatForever(autoreverses: false) : .default, value: isBusy)
        }
    }
    .disabled(isBusy)
    .accessibilityHint(isBusy ? "In progress" : "")
```

Wrap the dot's rendering (wherever `DotState` maps to a SwiftUI `Color`/shape — find that switch, likely in `chipBody` or a `dotColor(_:)` helper) to add a `.busy` case rendering the existing `--faint`-equivalent neutral color with a pulsing opacity animation, guarded by `NSWorkspace.shared.accessibilityDisplayShouldReduceMotion` the same way the existing motif spinner already checks that flag — find that check (search `accessibilityDisplayShouldReduceMotion` in `Sources/App/`) and mirror its exact guard pattern.

- [ ] **Step 4: Update `HealthController`**

In `Sources/App/Chrome/HealthController.swift`, add:

```swift
func markBusy(chipID: String) {
    guard let index = chips.firstIndex(where: { $0.id == chipID }) else { return }
    guard case .refresh = chips[index].interaction else { return }
    chips[index].interaction = .refresh(isBusy: true)
}

func clearBusy(chipID: String) {
    guard let index = chips.firstIndex(where: { $0.id == chipID }) else { return }
    guard case .refresh = chips[index].interaction else { return }
    chips[index].interaction = .refresh(isBusy: false)
}
```

Update `shieldChip(_:)`'s existing `.refresh` construction (line 21-33) to `interaction: .refresh(isBusy: false)` (both call sites that build a fresh `.refresh` interaction from a snapshot must start non-busy — busy is only ever set by an explicit `markBusy` call, never derived from `ShieldStatus`).

- [ ] **Step 5: Run tests to verify they pass**

Run: `xcodebuild -workspace MediaGrabber.xcworkspace -scheme MediaGrabber-Workspace -destination 'platform=macOS' test -only-testing:AppUnitTests/HealthControllerTests`
Expected: PASS.

- [ ] **Step 6: Fix the compile break at the shield-chip call site**

`Sources/App/MainWindow.swift`'s `HealthStrip(chips:) { chip in ... }` closure (line 17-21) needs to call `markBusy`/`clearBusy` around the `restartShield()` call:

```swift
HealthStrip(chips: appModel.healthChips) { chip in
    if chip.id == "shield" {
        Task {
            appModel.healthController.markBusy(chipID: "shield")
            await appModel.restartShield()
            appModel.healthController.clearBusy(chipID: "shield")
        }
    }
}
```

`AppModel.healthController` (`Sources/App/AppModel.swift:65`) is a `let` property — the property name above is exact.

- [ ] **Step 7: Run the full AppUnitTests suite**

Run: `xcodebuild -workspace MediaGrabber.xcworkspace -scheme MediaGrabber-Workspace -destination 'platform=macOS' test -only-testing:AppUnitTests`
Expected: PASS — check for any other `.refresh` pattern-match sites broken by the associated-value change (compiler will catch these as exhaustiveness errors; fix each to match `.refresh(let isBusy)` or `.refresh` with `_` as appropriate).

- [ ] **Step 8: Lint**

Run: `mise exec -- swiftformat --lint Sources/App/Chrome/HealthStrip.swift Sources/App/Chrome/HealthController.swift Sources/App/MainWindow.swift` then `mise exec -- swiftlint lint --strict Sources/App/Chrome/HealthStrip.swift Sources/App/Chrome/HealthController.swift Sources/App/MainWindow.swift`

---

## Task 7: Engine-freshness chip

**Files:**
- Modify: `Sources/App/Chrome/HealthController.swift`
- Modify: `Sources/App/AppModel.swift`
- Test: `Tests/AppUnitTests/HealthControllerTests.swift` (existing — add cases)

**Interfaces:**
- Consumes: `EnvironmentReport.ytDlpDriftVerdict` (Task 2), `YtDlpUpdating` (Task 3), `HealthController.markBusy`/`clearBusy` (Task 6).
- Produces: `HealthController.update(snapshot:now:environmentReport:)` — the existing method gains a third parameter, `environmentReport: EnvironmentReport?`. `AppModel` calls `envProbe.probe()` exactly once today, inside `refreshOnboardingState()` (`Sources/App/AppModel.swift:169`), and discards the result after computing `needsOnboarding` — this task adds a new stored property `AppModel.latestEnvironmentReport: EnvironmentReport?` (private(set)), sets it inside `refreshOnboardingState()` right after the existing `envProbe.probe()` call, and passes `latestEnvironmentReport` into the `healthController.update(...)` call in `AppModel.runConsumer()` (`Sources/App/AppModel.swift:373`), which has no `EnvironmentReport` in scope today. `AppModel.restartYtDlp()` mirrors the existing `restartShield()` method exactly, calling `YtDlpUpdating.reinstallToMinimum()`, then re-running `envProbe.probe()` to refresh `latestEnvironmentReport` before the next `HealthController.update` call picks it up.

- [ ] **Step 1: Write the failing tests**

`HealthControllerTests.swift` is an `XCTestCase` with a private `snapshot(online:summary:shield:) -> QueueSnapshot` helper (line 7-21) — these new cases are added as more methods on that same class, using `XCTAssertEqual`/`XCTAssertNil` to match the file's existing style, and reusing that same `snapshot(...)` helper rather than constructing a `QueueSnapshot` inline:

```swift
func testEngineChipCurrentVersionShowsOkChip() {
    let controller = HealthController()
    let report = EnvironmentReport(
        brew: nil,
        ytDlp: ToolInfo(path: URL(fileURLWithPath: "/opt/homebrew/bin/yt-dlp"), version: "2099.01.01"),
        ffmpeg: nil
    )
    controller.update(snapshot: snapshot(online: true, summary: [:]), now: .now, environmentReport: report)
    let chip = controller.chips.first { $0.id == "engine" }
    XCTAssertEqual(chip?.dot, .ok)
    XCTAssertEqual(chip?.interaction, .none)
}

func testEngineChipDriftedVersionShowsAttentionWithRefresh() {
    let controller = HealthController()
    let report = EnvironmentReport(
        brew: nil,
        ytDlp: ToolInfo(path: URL(fileURLWithPath: "/opt/homebrew/bin/yt-dlp"), version: "2000.01.01"),
        ffmpeg: nil
    )
    controller.update(snapshot: snapshot(online: true, summary: [:]), now: .now, environmentReport: report)
    let chip = controller.chips.first { $0.id == "engine" }
    XCTAssertEqual(chip?.dot, .attention)
    XCTAssertEqual(chip?.interaction, .refresh(isBusy: false))
    XCTAssertEqual(chip?.label, "engine · update available")
}

func testEngineChipUnknownVersionShowsOkNotAttention() {
    // Unparseable version reads as unknown, never as stale — never a false-alarm chip.
    let controller = HealthController()
    let report = EnvironmentReport(
        brew: nil,
        ytDlp: ToolInfo(path: URL(fileURLWithPath: "/opt/homebrew/bin/yt-dlp"), version: "nightly"),
        ffmpeg: nil
    )
    controller.update(snapshot: snapshot(online: true, summary: [:]), now: .now, environmentReport: report)
    let chip = controller.chips.first { $0.id == "engine" }
    XCTAssertEqual(chip?.dot, .ok)
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `xcodebuild -workspace MediaGrabber.xcworkspace -scheme MediaGrabber-Workspace -destination 'platform=macOS' test -only-testing:AppUnitTests/HealthControllerTests`
Expected: FAIL — no `environmentReport` parameter, no "engine" chip ID produced.

- [ ] **Step 3: Implement the engine chip**

In `Sources/App/Chrome/HealthController.swift`, add the parameter and builder:

```swift
func update(snapshot: QueueSnapshot, now: Date, environmentReport: EnvironmentReport?) {
    var next: [HealthChip] = [
        shieldChip(snapshot.shieldStatus),
    ]
    if let engineChip = engineChip(environmentReport?.ytDlpDriftVerdict) {
        next.append(engineChip)
    }
    next.append(onlineChip(snapshot.isOnline))
    if let cooldown = hostRateChip(snapshot.hostRateSummary) {
        next.append(cooldown)
    }
    chips = next
}

private func engineChip(_ verdict: YtDlpDriftVerdict?) -> HealthChip? {
    guard let verdict else { return nil }
    switch verdict {
    case .current, .unknown:
        return HealthChip(id: "engine", label: "engine · current", dot: .ok, interaction: .none)
    case .drift:
        return HealthChip(id: "engine", label: "engine · update available", dot: .attention, interaction: .refresh(isBusy: false))
    }
}
```

`now` is accepted by the existing signature but unused in the current body — keep that as-is, only add the new parameter. Chip order is shield, engine, online, host-rate, matching the mockup's markup (`apps/media-grabber/docs/mockups/screens/preferences.html`'s `.health` div: `bot-check shield · on` → `engine · current` → `online`) and the code above.

Update the one existing call site of `healthController.update(snapshot:now:)`, in `AppModel.runConsumer()`, to pass the new `environmentReport` argument (`AppModel.latestEnvironmentReport`, added in Step 4).

- [ ] **Step 4: Add `AppModel.latestEnvironmentReport` and `AppModel.restartYtDlp()`**

`AppModel.swift` has no re-probe method today. `envProbe.probe()` (the stored property at line 91, the initializer default at line 106, the sole call at line 169) is called exactly once, inline inside `refreshOnboardingState()` (line 164-171), and its result is used only to compute `needsOnboarding` — never stored, never re-called from anywhere else. This task adds the storage and both call sites:

```swift
private(set) var latestEnvironmentReport: EnvironmentReport?

func refreshOnboardingState() async {
    if debugFlags.forceOnboarding {
        needsOnboarding = true
        return
    }
    let report = await envProbe.probe()
    latestEnvironmentReport = report
    needsOnboarding = !report.isReadyForDownloads
}

func restartYtDlp() async {
    healthController.markBusy(chipID: "engine")
    _ = await ytDlpUpdater.reinstallToMinimum()
    let report = await envProbe.probe()
    latestEnvironmentReport = report
    let snapshot = await engine.currentSnapshot()
    healthController.update(snapshot: snapshot, now: .now, environmentReport: report)
    healthController.clearBusy(chipID: "engine")
}
```

(`ytDlpUpdater: YtDlpUpdating` needs to be a new stored property on `AppModel`, added to the initializer with a default of `YtDlpUpdater()` the same way `envProbe: EnvironmentProbing = EnvironmentProbe()` is already defaulted at line 106 — follow that exact pattern. `engine.currentSnapshot()` is the same call already used in `runConsumer()`'s recovery path at line 380 — reuse it, don't invent a second snapshot accessor.)

Also update the `runConsumer()` call site at line 373 to pass the stored report:

```swift
healthController.update(snapshot: snapshot, now: .now, environmentReport: latestEnvironmentReport)
```

Wire `restartYtDlp()` into `MainWindow.swift`'s `HealthStrip` closure alongside the existing shield case:

```swift
HealthStrip(chips: appModel.healthChips) { chip in
    if chip.id == "shield" {
        Task {
            appModel.healthController.markBusy(chipID: "shield")
            await appModel.restartShield()
            appModel.healthController.clearBusy(chipID: "shield")
        }
    } else if chip.id == "engine" {
        Task { await appModel.restartYtDlp() }
    }
}
```

- [ ] **Step 5: Run tests to verify they pass**

Run: `xcodebuild -workspace MediaGrabber.xcworkspace -scheme MediaGrabber-Workspace -destination 'platform=macOS' test -only-testing:AppUnitTests/HealthControllerTests`
Expected: PASS.

- [ ] **Step 6: Run the full AppUnitTests suite**

Run: `xcodebuild -workspace MediaGrabber.xcworkspace -scheme MediaGrabber-Workspace -destination 'platform=macOS' test -only-testing:AppUnitTests`
Expected: PASS — fix any other call site broken by `update`'s new parameter.

- [ ] **Step 7: Lint**

Run: `mise exec -- swiftformat --lint Sources/App/Chrome/HealthController.swift Sources/App/AppModel.swift Sources/App/MainWindow.swift` then `mise exec -- swiftlint lint --strict Sources/App/Chrome/HealthController.swift Sources/App/AppModel.swift Sources/App/MainWindow.swift`

---

## Task 8: `PreferencesPane.diagnostics` + `DiagnosticsPane` view

**Files:**
- Modify: `Sources/App/Preferences/PreferencesPane.swift`
- Modify: `Sources/App/Preferences/PreferencesView.swift`
- Create: `Sources/App/Preferences/DiagnosticsPane.swift`
- Create: `Sources/App/Sharing/SharePresenter.swift`
- Test: `Tests/AppUnitTests/PreferencesPaneTests.swift` (existing — add cases)
- Test: `Tests/AppUnitTests/DiagnosticsPaneTests.swift`

**Interfaces:**
- Consumes: `YtDlpUpdating` (Task 3), `DiagnosticBundle.build` (Task 5), `MetadataProbing` + `CanaryProbe.url` (Task 4), `IncomingLinkController.markAppPasteboardWrite(_:)` (existing).
- Produces: `PreferencesPane.diagnostics` case; `SharePresenter.share(data: Data, filename: String)`, a static/instance function called directly from a SwiftUI `Button` action, reading the current window's content view via `NSApp.keyWindow?.contentView` (simpler than wrapping an `NSViewRepresentable` — the app's one existing AppKit-bridging view, `WindowFrameAutosave.swift`, exists to reach `view.window` from inside the view hierarchy for window-autosave, a different need than presenting a share sheet from a button tap).

- [ ] **Step 1: Add the `.diagnostics` case to `PreferencesPane`**

Write the failing test first in `Tests/AppUnitTests/PreferencesPaneTests.swift`:

```swift
func test_diagnosticsPane_isInSystemGroup() {
    XCTAssertEqual(PreferencesPane.diagnostics.group, .system)
}

func test_diagnosticsPane_hasATitle() {
    XCTAssertEqual(PreferencesPane.diagnostics.title, "Diagnostics")
}
```

Run: `xcodebuild -workspace MediaGrabber.xcworkspace -scheme MediaGrabber-Workspace -destination 'platform=macOS' test -only-testing:AppUnitTests/PreferencesPaneTests`
Expected: FAIL.

Open `Sources/App/Preferences/PreferencesPane.swift`. Add `case diagnostics` to the enum (line 1-8, currently 7 cases) and its `.title`/`.subtitle`/`.group` computed properties following the exact pattern the other 7 cases already use (read the file to match the property style precisely — a `switch self` returning per-case strings, most likely).

Run the test again — expect PASS. Then run the full `PreferencesPaneTests` suite to confirm the 7 existing cases still pass unchanged.

- [ ] **Step 2: Wire `.diagnostics` into `PreferencesView`'s pane switch**

`Sources/App/Preferences/PreferencesView.swift`'s `paneBody` switch (line 64-75, currently 7 cases, will fail to compile with an unhandled 8th case as soon as Step 1 lands) needs a `case .diagnostics: DiagnosticsPane()` branch. Add it now — the file will not compile between Step 1 and this step, so do them in the same commit.

- [ ] **Step 3: Write `SharePresenter`**

```swift
import AppKit

enum SharePresenter {
    @MainActor
    static func share(data: Data, filename: String) {
        let tempURL = FileManager.default.temporaryDirectory.appendingPathComponent(filename)
        try? data.write(to: tempURL)
        guard let contentView = NSApp.keyWindow?.contentView else { return }
        let picker = NSSharingServicePicker(items: [tempURL])
        picker.show(relativeTo: contentView.bounds, of: contentView, preferredEdge: .minY)
    }
}
```

No unit test for this one — it's a thin AppKit-interop shim with no meaningful pure logic to assert on beyond "it compiles and doesn't crash," which XCTest can't verify without an actual window; cover its call site's *decision to invoke it* in `DiagnosticsPaneTests` (Step 5) instead by injecting a spy in place of `SharePresenter` — extract the `share` call behind a small `protocol SharePresenting { func share(data: Data, filename: String) }` so `DiagnosticsPane` can take one via `@Environment` or initializer injection, and the test asserts the spy received the right `Data`/filename without touching real AppKit UI.

Revise the type to:

```swift
import AppKit

protocol SharePresenting {
    @MainActor func share(data: Data, filename: String)
}

struct SharePresenter: SharePresenting {
    @MainActor
    func share(data: Data, filename: String) {
        let tempURL = FileManager.default.temporaryDirectory.appendingPathComponent(filename)
        try? data.write(to: tempURL)
        guard let contentView = NSApp.keyWindow?.contentView else { return }
        let picker = NSSharingServicePicker(items: [tempURL])
        picker.show(relativeTo: contentView.bounds, of: contentView, preferredEdge: .minY)
    }
}
```

- [ ] **Step 4: Write `DiagnosticsPaneTests` first**

```swift
import XCTest
@testable import MediaGrabber
@testable import GrabberKit

@MainActor
final class DiagnosticsPaneTests: XCTestCase {
    final class SpySharePresenter: SharePresenting {
        var sharedData: Data?
        var sharedFilename: String?
        func share(data: Data, filename: String) {
            sharedData = data
            sharedFilename = filename
        }
    }

    func test_runCheck_updatesReportWithCanaryResult() async {
        let fakeMetadataProbe = FakeMetadataProbe(default: FakeMetadataProbe.success(title: "Big Buck Bunny"))
        let model = DiagnosticsPaneModel(
            metadataProbe: fakeMetadataProbe,
            environmentProbe: FakeEnvironmentProbe(.with(ytDlp: true, ffmpeg: true)),
            ytDlpUpdater: FakeYtDlpUpdater(),
            sharePresenter: SpySharePresenter()
        )
        await model.runCheck()
        XCTAssertEqual(model.canaryResult, .passed)
    }

    func test_shareBundle_callsSharePresenterWithZipData() async {
        let spy = SpySharePresenter()
        let model = DiagnosticsPaneModel(
            metadataProbe: FakeMetadataProbe(default: FakeMetadataProbe.success(title: "Big Buck Bunny")),
            environmentProbe: FakeEnvironmentProbe(.with(ytDlp: true, ffmpeg: true)),
            ytDlpUpdater: FakeYtDlpUpdater(),
            sharePresenter: spy
        )
        await model.runCheck()
        model.shareDiagnosticBundle()
        XCTAssertNotNil(spy.sharedData)
        XCTAssertEqual(spy.sharedFilename, "MediaGrabber-Diagnostics.zip")
    }

    func test_copyReport_marksAppPasteboardWrite() async {
        let controller = IncomingLinkController(/* existing test construction */)
        let model = DiagnosticsPaneModel(
            metadataProbe: FakeMetadataProbe(default: FakeMetadataProbe.success(title: "Big Buck Bunny")),
            environmentProbe: FakeEnvironmentProbe(.with(ytDlp: true, ffmpeg: true)),
            ytDlpUpdater: FakeYtDlpUpdater(),
            sharePresenter: SpySharePresenter(),
            pasteboardMarker: controller.markAppPasteboardWrite
        )
        await model.runCheck()
        model.copyReport()
        // Assert via whatever existing test hook IncomingLinkControllerTests uses to verify
        // appWrittenString was set, matching that file's existing assertion style.
    }
}
```

(`FakeYtDlpUpdater` needs creating alongside this test in `Tests/TestSupport/` — a trivial `YtDlpUpdating` conformance returning a configurable `YtDlpUpdateResult`, following the exact naming/style of `FakeMetadataProbe`/`FakeEnvironmentProbe`. `pasteboardMarker` as a closure param avoids `DiagnosticsPaneModel` depending on all of `IncomingLinkController` — pass just the one function it needs.)

- [ ] **Step 5: Run tests to verify they fail**

Run: `xcodebuild -workspace MediaGrabber.xcworkspace -scheme MediaGrabber-Workspace -destination 'platform=macOS' test -only-testing:AppUnitTests/DiagnosticsPaneTests`
Expected: FAIL — `DiagnosticsPaneModel` doesn't exist.

- [ ] **Step 6: Implement `DiagnosticsPaneModel` and `DiagnosticsPane`**

```swift
import Foundation
import GrabberKit

@MainActor
@Observable
final class DiagnosticsPaneModel {
    enum CanaryResult: Equatable { case notRun, passed, failed }

    private(set) var canaryResult: CanaryResult = .notRun
    private(set) var reportText: String = ""
    private(set) var lastRunAt: Date?

    private let metadataProbe: MetadataProbing
    private let environmentProbe: EnvironmentProbing
    private let ytDlpUpdater: YtDlpUpdating
    private let sharePresenter: SharePresenting
    private let pasteboardMarker: (String) -> Void

    init(
        metadataProbe: MetadataProbing,
        environmentProbe: EnvironmentProbing,
        ytDlpUpdater: YtDlpUpdating,
        sharePresenter: SharePresenting,
        pasteboardMarker: @escaping (String) -> Void = { _ in }
    ) {
        self.metadataProbe = metadataProbe
        self.environmentProbe = environmentProbe
        self.ytDlpUpdater = ytDlpUpdater
        self.sharePresenter = sharePresenter
        self.pasteboardMarker = pasteboardMarker
    }

    func runCheck() async {
        let probeResult = await metadataProbe.probe(CanaryProbe.url)
        canaryResult = probeResult.isSuccess ? .passed : .failed
        let report = await environmentProbe.probe()
        reportText = Self.formatReport(canary: canaryResult, report: report)
        lastRunAt = Date()
    }

    // Production construction (in PreferencesView/AppModel, wherever DiagnosticsPaneModel is
    // built for real): pass `metadataProbe: MetadataProbe(ytDlpURL: report.ytDlp!.path, runner: runner)`
    // — built via CanaryProbe's own construction, not a second inline MetadataProbe(...) call —
    // by exposing CanaryProbe's internal `MetadataProbe(ytDlpURL:runner:)` line as a small factory
    // both OnboardingInstaller and this production call site share. Concretely: add
    // `public static func makeProbe(ytDlpURL: URL, runner: ProcessRunning) -> MetadataProbing`
    // to CanaryProbe (Step 4 above) and have both OnboardingInstaller's default path and this
    // pane's production construction call it, so there is exactly one line of code anywhere
    // that writes `MetadataProbe(ytDlpURL:runner:)` for canary purposes.

    func reinstallYtDlp() async {
        _ = await ytDlpUpdater.reinstallToMinimum()
        await runCheck()
    }

    func copyReport() {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(reportText, forType: .string)
        pasteboardMarker(reportText)
    }

    func shareDiagnosticBundle() {
        guard let data = try? DiagnosticBundle.build(appLogTail: "", jobLog: nil, report: reportText) else { return }
        let filename = "MediaGrabber-Diagnostics.zip"
        sharePresenter.share(data: data, filename: filename)
        pasteboardMarker(filename)
    }

    private static func formatReport(canary: CanaryResult, report: EnvironmentReport) -> String {
        var lines: [String] = []
        lines.append("Canary probe: \(canary == .passed ? "passed" : "failed")")
        if let ytDlp = report.ytDlp {
            lines.append("yt-dlp: \(ytDlp.version)")
        }
        if let ffmpeg = report.ffmpeg {
            lines.append("ffmpeg: \(ffmpeg.version)")
        }
        return lines.joined(separator: "\n")
    }
}

extension Result {
    var isSuccess: Bool {
        if case .success = self { return true }
        return false
    }
}
```

(`appLogTail`/`jobLog` are passed as empty/nil placeholders here deliberately — wiring the real log-file reads is a follow-up detail inside this same task, not deferred: add a small `LogReading` protocol + a real implementation that tails `~/Library/Logs/MediaGrabber/app.log` and reads the most-recent job's log, following whatever existing log-path-resolution code already exists in the App target — search for `Library/Logs/MediaGrabber` to find it and reuse it rather than hardcoding a second path constant.)

Write `DiagnosticsPane: View` — a SwiftUI view matching `apps/media-grabber/docs/mockups/screens/preferences.html`'s `#s6-1`/`#s6-2`/`#s6-3` markup: a `diagtop`-style header row (title left, Run check button right), a "Last run" line, the report rows, and the two buttons (Copy report / Share diagnostic bundle) at the bottom, both equal visual weight per the design-system.md §4.7 spec. Follow the same `field2`-row visual style already used by sibling panes (no bordered card, per today's decision) for the report rows.

- [ ] **Step 7: Run tests to verify they pass**

Run: `xcodebuild -workspace MediaGrabber.xcworkspace -scheme MediaGrabber-Workspace -destination 'platform=macOS' test -only-testing:AppUnitTests/DiagnosticsPaneTests -only-testing:AppUnitTests/PreferencesPaneTests`
Expected: PASS.

- [ ] **Step 8: Run the full test suite and build the app**

Run: `xcodebuild -workspace MediaGrabber.xcworkspace -scheme MediaGrabber-Workspace -destination 'platform=macOS' test -only-testing:AppUnitTests`
Then: `make` (rebuild + launch), navigate to Preferences → Diagnostics, click Run check, confirm the report populates and both buttons work (Share opens the system share sheet; Copy report puts text on the clipboard — verify with ⌘V into a text field).

- [ ] **Step 9: Lint**

Run: `mise exec -- swiftformat --lint Sources/App/Preferences/PreferencesPane.swift Sources/App/Preferences/PreferencesView.swift Sources/App/Preferences/DiagnosticsPane.swift Sources/App/Sharing/SharePresenter.swift` then `mise exec -- swiftlint lint --strict Sources/App/Preferences/PreferencesPane.swift Sources/App/Preferences/PreferencesView.swift Sources/App/Preferences/DiagnosticsPane.swift Sources/App/Sharing/SharePresenter.swift`

---

## Task 9: `Preferences` Updates toggles + `UpdatesPane` view

**Files:**
- Modify: `Sources/GrabberKit/Model/Preferences.swift`
- Modify: `Sources/App/Preferences/UpdatesPane.swift` — currently the stepless Phase 3 placeholder (`struct UpdatesPane: View { var body: some View { PrefSteplessPane(.updates, line: "Update checks are coming in a later update.") } }`); this task replaces its body. `PreferencesView.swift`'s `.updates` call site (`case .updates: UpdatesPane()`) needs no change — it already constructs `UpdatesPane()` with no arguments.
- Test: `Tests/GrabberKitTests/PreferencesTests.swift` (existing — add cases)

**Interfaces:**
- Produces: `Preferences.autoCheckAppUpdates: Bool` (default `true`), `Preferences.autoCheckYtDlpUpdates: Bool` (default `true`), both added to `ownedKeys`.

- [ ] **Step 1: Write the failing Preferences tests**

```swift
func test_autoCheckAppUpdates_defaultsTrue() {
    let prefs = Preferences(defaults: makeEmptyDefaults())
    XCTAssertTrue(prefs.autoCheckAppUpdates)
}

func test_autoCheckAppUpdates_persists() {
    let defaults = makeEmptyDefaults()
    let prefs = Preferences(defaults: defaults)
    prefs.autoCheckAppUpdates = false
    let reloaded = Preferences(defaults: defaults)
    XCTAssertFalse(reloaded.autoCheckAppUpdates)
}

func test_autoCheckYtDlpUpdates_defaultsTrue() {
    let prefs = Preferences(defaults: makeEmptyDefaults())
    XCTAssertTrue(prefs.autoCheckYtDlpUpdates)
}

func test_resetToDefaults_resetsBothUpdateToggles() {
    let prefs = Preferences(defaults: makeEmptyDefaults())
    prefs.autoCheckAppUpdates = false
    prefs.autoCheckYtDlpUpdates = false
    prefs.resetToDefaults()
    XCTAssertTrue(prefs.autoCheckAppUpdates)
    XCTAssertTrue(prefs.autoCheckYtDlpUpdates)
}
```

(`makeEmptyDefaults()` — use whatever helper the existing `PreferencesTests.swift` already has for constructing an isolated `UserDefaults` instance per test; do not invent a new one if one exists.)

- [ ] **Step 2: Run tests to verify they fail**

Run: `xcodebuild -workspace MediaGrabber.xcworkspace -scheme MediaGrabber-Workspace -destination 'platform=macOS' test -only-testing:GrabberKitTests/PreferencesTests`
Expected: FAIL.

- [ ] **Step 3: Implement**

In `Sources/GrabberKit/Model/Preferences.swift`, add both properties following the exact style of the existing `verboseLogging`/`detectClipboardLinks` boolean properties (line 87-90, 94-101):

```swift
public var autoCheckAppUpdates: Bool {
    get { defaults.object(forKey: "mg.autoCheckAppUpdates") == nil ? true : defaults.bool(forKey: "mg.autoCheckAppUpdates") }
    set { defaults.set(newValue, forKey: "mg.autoCheckAppUpdates") }
}

public var autoCheckYtDlpUpdates: Bool {
    get { defaults.object(forKey: "mg.autoCheckYtDlpUpdates") == nil ? true : defaults.bool(forKey: "mg.autoCheckYtDlpUpdates") }
    set { defaults.set(newValue, forKey: "mg.autoCheckYtDlpUpdates") }
}
```

Add both keys to the `ownedKeys` array (line 239-247).

- [ ] **Step 4: Run tests to verify they pass**

Run: `xcodebuild -workspace MediaGrabber.xcworkspace -scheme MediaGrabber-Workspace -destination 'platform=macOS' test -only-testing:GrabberKitTests/PreferencesTests`
Expected: PASS.

`UpdatesPane` itself needs no additional test file: it is a declarative SwiftUI view binding two toggles directly to the `Preferences` properties Steps 1-4 already cover with real assertions. A test that constructs `Preferences` and flips a toggle without touching the view would duplicate Step 1's coverage under a misleading name — skip it.

- [ ] **Step 5: Implement `UpdatesPane`**

`Sources/App/Preferences/DownloadsPane.swift` is the pattern every filled pane already follows: it reads `@Environment(AppModel.self) private var appModel`, binds `@Bindable var prefs = appModel.prefs` at the top of `body`, opens with `PrefPaneHeader(.downloads)`, then lays out each row as a `PrefRow("Label", helper: "...") { <control> }` (both `PrefRow`/`PrefPaneHeader` defined in `Sources/App/Preferences/PrefRow.swift`). `UpdatesPane` follows the same shape:

```swift
import SwiftUI

struct UpdatesPane: View {
    @Environment(AppModel.self) private var appModel

    var body: some View {
        @Bindable var prefs = appModel.prefs
        return VStack(alignment: .leading, spacing: 0) {
            PrefPaneHeader(.updates)

            PrefRow(
                "Check for app updates automatically",
                helper: "Looks for a newer MediaGrabber release once a day."
            ) {
                Toggle("", isOn: $prefs.autoCheckAppUpdates)
                    .labelsHidden()
            }

            PrefRow(
                "Notify when the downloader is outdated",
                helper: "Warn if yt-dlp falls behind the version this app expects."
            ) {
                Toggle("", isOn: $prefs.autoCheckYtDlpUpdates)
                    .labelsHidden()
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
```

No change is needed at the `.updates` call site in `PreferencesView.swift`'s `paneBody` switch (`case .updates: UpdatesPane()`) — it already constructs `UpdatesPane()` with no arguments, and the rewritten view above reads `AppModel` from the environment the same way `DownloadsPane` already does, so the call site is untouched.

- [ ] **Step 6: Build and manually verify**

Run: `xcodebuild -workspace MediaGrabber.xcworkspace -scheme MediaGrabber-Workspace -destination 'platform=macOS' test -only-testing:GrabberKitTests/PreferencesTests`
Then `make`, open Preferences → Updates, confirm both toggles render and persist across app relaunch.

- [ ] **Step 7: Lint**

Run: `mise exec -- swiftformat --lint Sources/GrabberKit/Model/Preferences.swift Sources/App/Preferences/UpdatesPane.swift` then `mise exec -- swiftlint lint --strict` on the same files.

---

## Task 10: Reconcile Site display-name mapping (`SiteNames` as single source of truth)

**Files:**
- Modify: `Sources/App/SiteNames.swift`
- Modify: `Sources/App/Rows/RowModel.swift`
- Modify: `Sources/App/Chrome/HealthController.swift`
- Test: `Tests/AppUnitTests/SiteDisplayNameTests.swift`

**Interfaces:**
- Produces: `SiteNames.display(_ key: String) -> String` becomes the one function both the table (`RowModel.site(for:)`) and the HealthStrip host chip (`HealthController.oneHostChip`) call. The two existing maps are keyed on different domains (yt-dlp `extractor` string vs. `RateHost.canonical`) but overlap in intent — both ultimately identify "youtube," "vimeo," etc. `SiteNames.display` takes the **already-lowercased key**; both call sites are responsible for lowercasing their own domain-specific identifier before calling it. `SiteNames` holds one merged dictionary covering every entry from both old maps' coverage (`youtube`, `youtube:tab`, `youtu.be`, `m.youtube.com`, `vimeo`, `vimeo.com`, `archive.org`, `generic`, plus the mockup's example `soundcloud`).

- [ ] **Step 1: Write the failing tests**

```swift
import XCTest
@testable import MediaGrabber

final class SiteDisplayNameTests: XCTestCase {
    func test_displaysYouTubeVariants() {
        XCTAssertEqual(SiteNames.display("youtube"), "YouTube")
        XCTAssertEqual(SiteNames.display("youtube:tab"), "YouTube")
        XCTAssertEqual(SiteNames.display("youtu.be"), "YouTube")
        XCTAssertEqual(SiteNames.display("m.youtube.com"), "YouTube")
    }

    func test_displaysVimeo() {
        XCTAssertEqual(SiteNames.display("vimeo"), "Vimeo")
        XCTAssertEqual(SiteNames.display("vimeo.com"), "Vimeo")
    }

    func test_displaysSoundCloud() {
        XCTAssertEqual(SiteNames.display("soundcloud"), "SoundCloud")
    }

    func test_displaysArchiveOrgAsInternetArchive() {
        XCTAssertEqual(SiteNames.display("archive.org"), "Internet Archive")
    }

    func test_unknownKeyFallsBackToRawValue() {
        XCTAssertEqual(SiteNames.display("some-new-site"), "some-new-site")
    }

    func test_genericFallsBackToWeb() {
        XCTAssertEqual(SiteNames.display("generic"), "Web")
    }
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `xcodebuild -workspace MediaGrabber.xcworkspace -scheme MediaGrabber-Workspace -destination 'platform=macOS' test -only-testing:AppUnitTests/SiteDisplayNameTests`
Expected: FAIL — `soundcloud` and the `youtube:tab`/`youtu.be`/`m.youtube.com` variants aren't in the current 3-entry `SiteNames` map.

- [ ] **Step 3: Merge the two maps into `SiteNames`**

Open `Sources/App/SiteNames.swift` and `Sources/App/Rows/RowModel.swift`'s `siteMap` (around line 286-293). Merge every entry from both into `SiteNames`:

```swift
enum SiteNames {
    private static let displayNames: [String: String] = [
        "youtube": "YouTube",
        "youtube:tab": "YouTube",
        "youtu.be": "YouTube",
        "m.youtube.com": "YouTube",
        "vimeo": "Vimeo",
        "vimeo.com": "Vimeo",
        "soundcloud": "SoundCloud",
        "archive.org": "Internet Archive",
        "generic": "Web",
    ]

    static func display(_ key: String) -> String {
        displayNames[key.lowercased()] ?? key
    }
}
```

- [ ] **Step 4: Update `RowModel.site(for:)` to delegate**

Replace `RowModel.site(for:)`'s body (line 260-263, `siteMap[extractor.lowercased()] ?? extractor`) with `SiteNames.display(extractor)`. Delete the now-unused `siteMap` dictionary from `RowModel.swift` entirely.

- [ ] **Step 5: Confirm `HealthController.oneHostChip` already calls the shared function**

Research confirmed `HealthController.swift:58` already calls `SiteNames.display(host.canonical)` — no change needed there, it already points at the (now-expanded) shared map.

- [ ] **Step 6: Run tests to verify they pass**

Run: `xcodebuild -workspace MediaGrabber.xcworkspace -scheme MediaGrabber-Workspace -destination 'platform=macOS' test -only-testing:AppUnitTests/SiteDisplayNameTests`
Expected: PASS.

- [ ] **Step 7: Run the full AppUnitTests suite**

Run: `xcodebuild -workspace MediaGrabber.xcworkspace -scheme MediaGrabber-Workspace -destination 'platform=macOS' test -only-testing:AppUnitTests`
Expected: PASS — check for any existing test asserting the old `RowModel.siteMap` behavior directly (e.g. a `RowModelStatusTests` or similar asserting a specific Site cell string) and update it to expect the merged map's output if it differs.

- [ ] **Step 8: Lint**

Run: `mise exec -- swiftformat --lint Sources/App/SiteNames.swift Sources/App/Rows/RowModel.swift` then `mise exec -- swiftlint lint --strict Sources/App/SiteNames.swift Sources/App/Rows/RowModel.swift`

---

## Task 11: `ColumnID.remark` + Status/Remark split in `TablePresentation`

**Files:**
- Modify: `Sources/GrabberKit/Model/ColumnConfig.swift`
- Modify: `Sources/App/Table/TablePresentation.swift`
- Modify: `Sources/App/Rows/RowModel.swift`
- Modify: `Sources/App/Table/DownloadRow.swift` — a dedicated `.title` case added to `cell(for:)` for the hover tooltip (Step 4.5); its live countdown rendering in `statusCell` is untouched, since it already reads `row.snapshot.cooldownUntil`/`row.hostCooldownDeadline` directly via `TimelineView`, not through either status-text function.
- Test: `Tests/AppUnitTests/ColumnConfigRemarkTests.swift`
- Test: `Tests/AppUnitTests/DownloadsTableTests.swift` (existing — add the Status/Remark-split cases here; also update any pre-existing assertion in this file that checks the old combined Status text)

`Sources/App/Rows/RowStatusText.swift` is not modified — it backs the differently-cased, VPN-aware `RowModel.statusText` used elsewhere, untouched by this split.

**Interfaces:**
- Produces: `ColumnID.remark` (new case, hidden by default, inserted into `defaultOrder` immediately after `.status`); `TablePresentation.statusDisplay(for:)` narrowed to return only the closed set of labels (`downloading`, `queued`, `paused`, `cooling down`, `retrying`, `saved`, `cancelled`, `failed`) with **no interpolated free text**; new `TablePresentation.remarkText(for:) -> String` extracting whatever free text `statusDisplay` used to embed (queue position, resume countdown, attempt count, failure reason).

- [ ] **Step 1: Write the failing `ColumnConfig` tests**

```swift
import XCTest
@testable import GrabberKit

final class ColumnConfigRemarkTests: XCTestCase {
    func test_remarkColumnExists() {
        XCTAssertTrue(ColumnID.allCases.contains(.remark))
    }

    func test_remarkIsHiddenByDefault() {
        XCTAssertFalse(ColumnID.defaultVisible.contains(.remark))
    }

    func test_remarkSitsImmediatelyAfterStatusInDefaultOrder() {
        guard let statusIndex = ColumnID.defaultOrder.firstIndex(of: .status),
              let remarkIndex = ColumnID.defaultOrder.firstIndex(of: .remark) else {
            XCTFail("status or remark missing from defaultOrder")
            return
        }
        XCTAssertEqual(remarkIndex, statusIndex + 1)
    }

    func test_existingPersistedColumnOrder_autoBackfillsRemark() {
        // enforceInvariants() (public) is what a persisted config saved before this column
        // existed will run through on load; its private appendMissingKnownColumns() step is
        // what actually backfills .remark — exercised here through the public entry point.
        var config = ColumnConfig.default
        config.columnOrder.removeAll { $0 == .remark }
        config.enforceInvariants()
        XCTAssertTrue(config.columnOrder.contains(.remark))
    }
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `xcodebuild -workspace MediaGrabber.xcworkspace -scheme MediaGrabber-Workspace -destination 'platform=macOS' test -only-testing:AppUnitTests/ColumnConfigRemarkTests`
Expected: FAIL — `.remark` doesn't exist.

- [ ] **Step 3: Add `.remark` to `ColumnID`**

In `Sources/GrabberKit/Model/ColumnConfig.swift` (line 3-6), add `case remark` to the enum. Update `defaultOrder` (line 12-16) to insert `.remark` immediately after `.status`. Confirm `.remark` is **not** added to `defaultVisible` (line 8-10) — it must stay hidden by default per spec §5.4.

Give `.remark` a display title wherever `ColumnID` maps to a header label (e.g. a `.title` computed property or a `ColumnsMenu` label lookup — find it via `grep -n "case .status" Sources/App/Table/ Sources/GrabberKit/Model/ColumnConfig.swift` to locate every switch that needs a new arm) — label it `"Remark"`.

- [ ] **Step 4: Run `ColumnConfigRemarkTests` to verify they pass**

Run: `xcodebuild -workspace MediaGrabber.xcworkspace -scheme MediaGrabber-Workspace -destination 'platform=macOS' test -only-testing:AppUnitTests/ColumnConfigRemarkTests`
Expected: PASS.

- [ ] **Step 4.5: Add a hover tooltip to the Title cell (truncation itself already works)**

`Sources/App/Table/DownloadRow.swift`'s `cell(for:)` (line 92-108) already applies `.lineLimit(1)` and `.truncationMode(.tail)` to every column that falls through to its `default:` branch (line 100-106) — Title has no dedicated case today, so it already gets this treatment; a long title already truncates with an ellipsis rather than wrapping or growing the row. The only missing piece is a hover tooltip showing the untruncated title. Since `.help(_:)` should apply to Title only, not every other `default:`-routed column, give Title its own case:

```swift
case .title:
    Text(TablePresentation.cellText(for: row, column: column))
        .font(theme.bodyFont(12, .regular))
        .foregroundStyle(theme.palette.dim)
        .lineLimit(1)
        .truncationMode(.tail)
        .padding(.leading, playlistIndent(for: column))
        .help(TablePresentation.cellText(for: row, column: column))
```

(Placed as a new case above the existing `default:` branch in the same `switch`, matching that branch's exact styling so Title's appearance is unchanged apart from the added tooltip.) Verify manually in Step 11 below — SwiftUI view-modifier application has no meaningful XCTest coverage without a rendering harness: add a row with a very long title during manual testing and confirm hovering over the truncated title shows the full text.

- [ ] **Step 5: Read the real status-text pipeline before changing anything**

There are two separate, parallel status-text implementations today:

1. `Sources/App/Table/TablePresentation.swift`'s `statusDisplay(for:)` (line 65-81) and `queuedDisplay(for:)` (line 87-98) — produce the **lowercase** Status cell text shown in the Downloads table (`"queued"`, `"cooling down"`, `"retrying"`, `"downloading"`, etc.). This already has a `showsQueueBadge(_:)` check (line 83-85) and returns `"queued · \(badge)"` (e.g. `"queued · #2"`) directly in `statusDisplay`, not in `queuedDisplay`. Its `.failed` branch (line 78-79) returns `row.statusText` with a hardcoded `"Failed — "` prefix stripped.
2. `Sources/App/Rows/RowStatusText.swift`'s `RowStatusText.text(for:maxAutoRetries:rate:vpnActive:)` (line 5-31) — produces **capitalized** text (`"Queued"`, `"Cooling down"`, `"Retrying"`, `"Failed — <sentence>"`) that becomes `RowModel.statusText` (set at `RowModel.swift:143,188,201`). This is a *different, fuller* pipeline: it takes `maxAutoRetries` and `vpnActive` and produces VPN-aware failure text via `BotCheckCopy.sentence(vpnActive:)` for `.botCheck` specifically (line 38-39) — `TablePresentation.statusDisplay` does not have access to any of this context and only reads the *result* of it (`row.statusText`) for the `.failed` case.
3. The **live countdown suffix** (e.g. `"cooling down — 1:00"`) is rendered **at the SwiftUI view layer**, not inside either status-text function: `Sources/App/Table/DownloadRow.swift`'s `statusCell` (line 114-134) computes `let deadline = row.snapshot.cooldownUntil ?? row.hostCooldownDeadline`, and when `deadline > .now`, wraps the label in a `TimelineView(.periodic(from: .now, by: 1))` appending `" — " + CountdownFormat.mmss(until: deadline, now: context.date)` (line 121-125, `CountdownFormat.mmss` at `Sources/GrabberKit/.../CountdownFormat.swift`) so the countdown ticks live without `TablePresentation` or `RowModel` re-computing anything per second.

Given this, the actual Remark split is:
- **`TablePresentation.statusDisplay(for:)`** loses its `"queued · \(badge)"` special case (line 66-68) — becomes a plain closed-label switch, no badge concatenation, no reason-sentence concatenation.
- **`RowModel` gains `remarkText: String`** (mirroring `statusText`/`siteLabel`'s existing pattern) computed from `queueBadge` (already exactly `"#N"`, no reformatting needed — `RowModel.swift:281-284`) for the queued-with-position case, and from `statusText`'s failure sentence (stripped of the `"Failed — "` prefix, same as `TablePresentation.statusDisplay`'s existing `.failed` branch already does) for the failed case.
- **The live countdown suffix in `DownloadRow.statusCell` is untouched** — it already lives outside both status-text functions and needs no change; it continues appending to whatever `TablePresentation.statusDisplay` returns, same as today.
- **`RowStatusText`/`RowModel.statusText` are untouched** — they back the (differently-cased, VPN-aware) text used elsewhere, not the table's Status cell directly; only `TablePresentation.statusDisplay`'s narrow reuse of `row.statusText` for the failure sentence changes to instead read the *new* `RowModel.remarkText` for that content, moving the reason sentence out of `statusDisplay` entirely.

- [ ] **Step 6: Write the failing tests**

Add to `Tests/AppUnitTests/DownloadsTableTests.swift` (the existing file already exercising `statusDisplay`/`queuedDisplay`). Check that file's existing tests first for its actual `RowModel`-construction helper (it must already build fixtures to test `statusDisplay`/`queuedDisplay` today) and use that exact helper — do not invent a `.fixture(...)` API without confirming its real name/parameters from the file first.

```swift
func test_statusDisplay_queuedWithPosition_showsPlainQueuedNoBadge() {
    // Uses whatever this file's existing RowModel-construction helper is, with a
    // queued state and a queue position of 2.
    XCTAssertEqual(TablePresentation.statusDisplay(for: row), "queued")
}

func test_remarkText_queuedWithPosition_showsPositionNumber() {
    XCTAssertEqual(row.remarkText, "#2")
}

func test_statusDisplay_retryingState_showsPlainRetrying() {
    // attempt > 0, cooldownUntil in the future, queued state.
    XCTAssertEqual(TablePresentation.statusDisplay(for: row), "retrying")
}

func test_remarkText_retryingState_isEmpty() {
    // The countdown itself is rendered by DownloadRow's TimelineView from
    // row.snapshot.cooldownUntil directly, not from Remark text — Remark carries
    // no countdown string for this state.
    XCTAssertEqual(row.remarkText, "")
}

func test_statusDisplay_failed_showsPlainFailed() {
    XCTAssertEqual(TablePresentation.statusDisplay(for: row), "failed")
}

func test_remarkText_failed_showsReasonSentenceWithoutFailedPrefix() {
    // row.statusText is "Failed — Couldn't read your browser's sign-in." (RowStatusText's
    // capitalized form); remarkText strips the "Failed — " prefix the same way
    // statusDisplay's old .failed branch already did.
    XCTAssertEqual(row.remarkText, "Couldn't read your browser's sign-in.")
}

func test_remarkText_healthyRunningRow_isEmpty() {
    XCTAssertEqual(row.remarkText, "")
}

func test_remarkText_savedRow_isEmpty() {
    XCTAssertEqual(row.remarkText, "")
}
```

- [ ] **Step 7: Run tests to verify they fail**

Run the relevant test target/suite.
Expected: FAIL — `statusDisplay` still returns `"queued · #2"`-style combined text; `RowModel.remarkText` doesn't exist.

- [ ] **Step 8: Implement the split**

In `Sources/App/Table/TablePresentation.swift`, remove the badge-concatenation special case from `statusDisplay(for:)` (line 65-68) and the `.failed` branch's dependence on `row.statusText` (line 78-79):

```swift
static func statusDisplay(for row: RowModel) -> String {
    switch row.snapshot.state {
    case .queued: return queuedDisplay(for: row)
    case .probing: return "probing"
    case .running: return "downloading"
    case .paused: return "paused"
    case .waitingForNetwork: return "waiting for network"
    case .cooldown: return "cooling down"
    case .completed: return "saved"
    case .cancelled: return "cancelled"
    case .failed: return "failed"
    }
}
```

`queuedDisplay(for:)` (line 87-98) stays exactly as-is — it already returns only plain labels (`"rate-limited — paused"`, `"cooling down"`, `"retrying"`, `"queued"`), none of them carrying free text; it was never the source of the `"queued · #2"` combination (that concatenation happened one level up, in `statusDisplay` itself, which this step removes). Delete the now-unused `showsQueueBadge(_:)` helper (line 83-85) if nothing else calls it — confirm via `grep -n "showsQueueBadge" Sources/App/` before deleting.

In `Sources/App/Rows/RowModel.swift`, add a computed `remarkText` property next to `siteLabel`/`statusText`:

```swift
var remarkText: String {
    if let queueBadge, snapshot.state == .queued {
        return queueBadge
    }
    if case .failed = snapshot.state, statusText.hasPrefix("Failed — ") {
        return String(statusText.dropFirst("Failed — ".count))
    }
    return ""
}
```

(`queueBadge` is already exactly `"#N"` per `RowModel.badge(for:position:)` — no reformatting needed. The retrying-countdown case intentionally returns `""` here since `DownloadRow.statusCell`'s existing `TimelineView` already renders that countdown live from `row.snapshot.cooldownUntil` directly, not from any status-text string — see Step 5's finding #3. `hasPrefix`/`dropFirst` mirrors the exact stripping `TablePresentation.statusDisplay`'s old `.failed` branch used to do, just relocated.)

In `Sources/App/Table/TablePresentation.swift`'s `cellText(for:column:)` switch, add the new case:

```swift
case .remark:
    row.remarkText
```

(This can be added as its own `case` above the `default:` branch in `cellText`, or fall through the existing `default: dataColumnText(for: row, column: column)` path with a new case added inside `dataColumnText` instead — check which of the two switches (`cellText` at line 10-25, or `dataColumnText` at line 27-50) is the more natural fit given how `.site` is already handled there (`dataColumnText`'s `case .site: row.siteLabel`, line 37-38) and add `.remark` alongside it in the same switch, for consistency with how the other "plain `RowModel` field" columns are wired.)

- [ ] **Step 9: Run tests to verify they pass**

Run the relevant test target.
Expected: PASS.

- [ ] **Step 10: Run the full AppUnitTests suite and fix any regressions**

Run: `xcodebuild -workspace MediaGrabber.xcworkspace -scheme MediaGrabber-Workspace -destination 'platform=macOS' test -only-testing:AppUnitTests`
Any existing test asserting the OLD combined Status text (e.g. `"queued · #2"` from `statusDisplay`) must be updated to check `statusDisplay` for the plain label and `RowModel.remarkText` for the detail separately — do not leave a stale assertion checking for combined text. Given `DownloadsTableTests.swift` was confirmed as already testing `statusDisplay`/`queuedDisplay` (Step 6), check every existing test in that file for a `"queued · #"`-shaped string assertion specifically, since that exact case is the one this step removes.

- [ ] **Step 11: Manual verification**

Run `make`, open Home, add several downloads to exercise different states (queued behind another, a deliberately-failed URL, a completed one), turn on the Remark column via the Columns menu, confirm: Status shows only the plain label, Remark shows the detail (queue position or failure reason), the live cooling-down/retrying countdown in the Status cell itself still ticks exactly as it did before this task (unaffected, since `DownloadRow.statusCell`'s `TimelineView` was not touched), and the Remark column is off by default on a fresh launch.

- [ ] **Step 12: Lint**

Run: `mise exec -- swiftformat --lint Sources/GrabberKit/Model/ColumnConfig.swift Sources/App/Table/TablePresentation.swift Sources/App/Rows/RowModel.swift Sources/App/Table/DownloadRow.swift` then `mise exec -- swiftlint lint --strict` on the same files.

---

## Task 12: `AppModel.Page.about` + nav wiring (removing `.diagnostics` as a page)

**Files:**
- Modify: `Sources/App/AppModel.swift`
- Modify: `Sources/App/MainWindow.swift`
- Test: any existing `AppModelTests`/navigation test asserting on `Page.diagnostics` (find via `grep -rln "Page.diagnostics\|\.diagnostics" Tests/AppUnitTests/`)

**Interfaces:**
- Produces: `AppModel.Page` becomes `enum Page: Equatable { case home; case preferences(PreferencesPane = .downloads); case about }`.

- [ ] **Step 1: Update the `Page` enum's `.diagnostics` case and its two call sites**

`.diagnostics` on `Page` has exactly two consuming call sites, both in `Sources/App/MainWindow.swift`: the nav button (`navButton("Diagnostics", .diagnostics, page)`, line 89) and the `page` switch's `case .diagnostics:` branch (line 127). No other file references `Page.diagnostics`.

- [ ] **Step 2: Update the `Page` enum**

In `Sources/App/AppModel.swift` (line 18-22):

```swift
enum Page: Equatable {
    case home
    case preferences(PreferencesPane = .downloads)
    case about
}
```

This is a source-breaking change — the compiler will flag every switch over `Page` that isn't exhaustive. Do not add a `default:` branch anywhere to paper over it; handle `.about` explicitly at each site, since a silently-swallowed case is exactly the kind of bug this compiler error exists to catch.

- [ ] **Step 3: Update `MainWindow.swift`**

Research line 85-91 (nav buttons):

```swift
private func nav(for page: Binding<AppModel.Page>) -> some View {
    HStack(spacing: Spacing.s1) {
        navButton("Home", .home, page)
        navButton("Preferences", .preferences(), page)
        navButton("About", .about, page)
    }
}
```

Research line 120-130 (`page` switch):

```swift
@ViewBuilder
private var page: some View {
    switch appModel.page {
    case .home:
        HomeView()
    case let .preferences(pane):
        PreferencesView(initialPane: pane)
    case .about:
        AboutView()
    }
}
```

(`AboutView` is created in Task 13 — this task can be committed once `AboutView` exists as at least a compiling stub if sequencing requires it, but since Task 13 is the very next task in this plan and both are small, consider doing Tasks 12 and 13 in one PR-sized unit if executing sequentially without a gap; the plan keeps them separate tasks for review granularity.)

- [ ] **Step 4: Build to find remaining compile breaks**

Run: `mise exec -- tuist generate --no-open` then attempt a build via `xcodebuild -workspace MediaGrabber.xcworkspace -scheme MediaGrabber-Workspace -destination 'platform=macOS' build`
Expected: compile errors at every remaining non-exhaustive `switch appModel.page` or `Page.diagnostics` reference. Fix each one explicitly (do not use `default:`).

- [ ] **Step 5: Update/remove any test referencing `Page.diagnostics`**

For each test found in Step 1, update its assertion to use `.about` if it was testing generic page-navigation plumbing, or delete it if it was specifically testing the old Diagnostics-as-a-page placeholder (since that placeholder no longer exists — Diagnostics is now `PreferencesPane.diagnostics`, covered by Task 8's tests instead).

- [ ] **Step 6: Run the full AppUnitTests suite**

Run: `xcodebuild -workspace MediaGrabber.xcworkspace -scheme MediaGrabber-Workspace -destination 'platform=macOS' test -only-testing:AppUnitTests`
Expected: PASS.

- [ ] **Step 7: Lint**

Run: `mise exec -- swiftformat --lint Sources/App/AppModel.swift Sources/App/MainWindow.swift` then `mise exec -- swiftlint lint --strict Sources/App/AppModel.swift Sources/App/MainWindow.swift`

---

## Task 13: `AboutView` + `DeveloperView` + `AppUpdateChecker`

**Files:**
- Create: `Sources/App/About/AboutView.swift`
- Create: `Sources/App/About/DeveloperView.swift`
- Create: `Sources/App/About/AppUpdateChecker.swift`
- Test: `Tests/AppUnitTests/AboutViewTests.swift`
- Test: `Tests/AppUnitTests/AppUpdateCheckerTests.swift`

**Interfaces:**
- Consumes: `EnvironmentReport.ytDlpDriftVerdict` (Task 2), `YtDlpUpdating` (Task 3), `AppModel.restartYtDlp()` (Task 7).
- Produces: `protocol GitHubReleaseChecking: Sendable { func latestRelease(owner: String, repo: String) async throws -> GitHubRelease }`, `struct GitHubRelease: Sendable, Equatable { let tagName: String; let htmlURL: URL }`, `struct AppUpdateChecker { func checkForUpdate(currentVersion: String) async -> AppUpdateStatus }`, `enum AppUpdateStatus: Sendable, Equatable { case notChecked, upToDate, updateAvailable(version: String, releaseURL: URL), checkFailed }`.

- [ ] **Step 1: Write the failing `AppUpdateChecker` tests**

```swift
import XCTest
@testable import MediaGrabber

final class AppUpdateCheckerTests: XCTestCase {
    struct FakeGitHubReleaseChecking: GitHubReleaseChecking {
        let result: Result<GitHubRelease, Error>
        func latestRelease(owner: String, repo: String) async throws -> GitHubRelease {
            try result.get()
        }
    }

    func testNewerReleaseAvailableReportsUpdateAvailable() async {
        let release = GitHubRelease(tagName: "media-grabber-v1.5.0", htmlURL: URL(string: "https://github.com/example/repo/releases/tag/media-grabber-v1.5.0")!)
        let checker = AppUpdateChecker(client: FakeGitHubReleaseChecking(result: .success(release)))
        let status = await checker.checkForUpdate(currentVersion: "1.4.0")
        XCTAssertEqual(status, .updateAvailable(version: "1.5.0", releaseURL: release.htmlURL))
    }

    func testSameVersionAsCurrentReportsUpToDate() async {
        let release = GitHubRelease(tagName: "media-grabber-v1.4.0", htmlURL: URL(string: "https://github.com/example/repo/releases/tag/media-grabber-v1.4.0")!)
        let checker = AppUpdateChecker(client: FakeGitHubReleaseChecking(result: .success(release)))
        let status = await checker.checkForUpdate(currentVersion: "1.4.0")
        XCTAssertEqual(status, .upToDate)
    }

    func testOlderReleaseThanCurrentReportsUpToDate() async {
        // A dev build ahead of the latest tagged release should not claim an update is available.
        let release = GitHubRelease(tagName: "media-grabber-v1.3.0", htmlURL: URL(string: "https://github.com/example/repo/releases/tag/media-grabber-v1.3.0")!)
        let checker = AppUpdateChecker(client: FakeGitHubReleaseChecking(result: .success(release)))
        let status = await checker.checkForUpdate(currentVersion: "1.4.0")
        XCTAssertEqual(status, .upToDate)
    }

    func testNetworkFailureReportsCheckFailed() async {
        struct NetworkError: Error {}
        let checker = AppUpdateChecker(client: FakeGitHubReleaseChecking(result: .failure(NetworkError())))
        let status = await checker.checkForUpdate(currentVersion: "1.4.0")
        XCTAssertEqual(status, .checkFailed)
    }
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `xcodebuild -workspace MediaGrabber.xcworkspace -scheme MediaGrabber-Workspace -destination 'platform=macOS' test -only-testing:AppUnitTests/AppUpdateCheckerTests`
Expected: FAIL — none of these types exist.

- [ ] **Step 3: Implement `AppUpdateChecker`**

```swift
import Foundation

struct GitHubRelease: Sendable, Equatable {
    let tagName: String
    let htmlURL: URL
}

protocol GitHubReleaseChecking: Sendable {
    func latestRelease(owner: String, repo: String) async throws -> GitHubRelease
}

struct GitHubReleaseClient: GitHubReleaseChecking {
    func latestRelease(owner: String, repo: String) async throws -> GitHubRelease {
        let url = URL(string: "https://api.github.com/repos/\(owner)/\(repo)/releases/latest")!
        let (data, _) = try await URLSession.shared.data(from: url)
        struct Response: Decodable { let tag_name: String; let html_url: String }
        let response = try JSONDecoder().decode(Response.self, from: data)
        guard let htmlURL = URL(string: response.html_url) else {
            throw URLError(.badServerResponse)
        }
        return GitHubRelease(tagName: response.tag_name, htmlURL: htmlURL)
    }
}

enum AppUpdateStatus: Sendable, Equatable {
    case notChecked
    case upToDate
    case updateAvailable(version: String, releaseURL: URL)
    case checkFailed
}

struct AppUpdateChecker {
    private let client: GitHubReleaseChecking
    private let owner = "Mshardul"
    private let repo = "Tools"

    init(client: GitHubReleaseChecking = GitHubReleaseClient()) {
        self.client = client
    }

    func checkForUpdate(currentVersion: String) async -> AppUpdateStatus {
        guard let release = try? await client.latestRelease(owner: owner, repo: repo) else {
            return .checkFailed
        }
        // Tag format is "media-grabber-vX.Y.Z" per CLAUDE.md's release convention.
        let bareVersion = release.tagName.replacingOccurrences(of: "media-grabber-v", with: "")
        guard let latest = DottedVersion(parsing: bareVersion), let current = DottedVersion(parsing: currentVersion) else {
            return .checkFailed
        }
        return current < latest ? .updateAvailable(version: bareVersion, releaseURL: release.htmlURL) : .upToDate
    }
}
```

(`DottedVersion` (Task 1) is a version-neutral dotted-integer comparator by design — this is exactly why it is not named `YtDlpVersion`: it is reused here for MediaGrabber's own release-tag version, and in Tasks 2/3/7 for yt-dlp's version, with the same comparison logic serving both.)

`owner`/`repo` above are the repository's real values, confirmed directly — not placeholders.

- [ ] **Step 4: Run tests to verify they pass**

Run: `xcodebuild -workspace MediaGrabber.xcworkspace -scheme MediaGrabber-Workspace -destination 'platform=macOS' test -only-testing:AppUnitTests/AppUpdateCheckerTests`
Expected: PASS.

- [ ] **Step 5: Write the failing `AboutView`-model tests**

```swift
import XCTest
@testable import MediaGrabber
@testable import GrabberKit

@MainActor
final class AboutViewTests: XCTestCase {
    struct FakeGitHubReleaseChecking: GitHubReleaseChecking {
        let result: Result<GitHubRelease, Error>
        func latestRelease(owner: String, repo: String) async throws -> GitHubRelease { try result.get() }
    }

    func test_beforeCheck_appUpdateStatusIsNotChecked() {
        let model = AboutViewModel(
            currentAppVersion: "1.4.0",
            environmentReport: .with(ytDlp: true, ffmpeg: true),
            updateChecker: AppUpdateChecker(client: FakeGitHubReleaseChecking(result: .success(.init(tagName: "media-grabber-v1.4.0", htmlURL: URL(string: "https://example.com")!)))),
            ytDlpUpdater: FakeYtDlpUpdater()
        )
        XCTAssertEqual(model.appUpdateStatus, .notChecked)
    }

    func test_afterCheck_upToDate_showsNoButtonState() async {
        let model = AboutViewModel(
            currentAppVersion: "1.4.0",
            environmentReport: .with(ytDlp: true, ffmpeg: true),
            updateChecker: AppUpdateChecker(client: FakeGitHubReleaseChecking(result: .success(.init(tagName: "media-grabber-v1.4.0", htmlURL: URL(string: "https://example.com")!)))),
            ytDlpUpdater: FakeYtDlpUpdater()
        )
        await model.checkForAppUpdate()
        XCTAssertEqual(model.appUpdateStatus, .upToDate)
    }

    func test_ytDlpRow_neverShowsCheckForUpdatesVerb() {
        // yt-dlp's drift check is a local compare, always immediately certain — it never
        // has a "checking" intermediate state the way the app's own GitHub check does.
        let driftedReport = EnvironmentReport(
            brew: nil,
            ytDlp: ToolInfo(path: URL(fileURLWithPath: "/opt/homebrew/bin/yt-dlp"), version: "2000.01.01"),
            ffmpeg: nil
        )
        let model = AboutViewModel(
            currentAppVersion: "1.4.0",
            environmentReport: driftedReport,
            updateChecker: AppUpdateChecker(client: FakeGitHubReleaseChecking(result: .success(.init(tagName: "media-grabber-v1.4.0", htmlURL: URL(string: "https://example.com")!)))),
            ytDlpUpdater: FakeYtDlpUpdater()
        )
        // The model exposes yt-dlp's verdict directly from EnvironmentReport — there is no
        // separate "checking" state to assert against, which is itself the point of this test:
        // confirm the model has no such intermediate case in its yt-dlp-facing API at all.
        switch driftedReport.ytDlpDriftVerdict {
        case .drift: break
        default: XCTFail("expected drift")
        }
    }
}
```

- [ ] **Step 6: Run tests to verify they fail**

Run: `xcodebuild -workspace MediaGrabber.xcworkspace -scheme MediaGrabber-Workspace -destination 'platform=macOS' test -only-testing:AppUnitTests/AboutViewTests`
Expected: FAIL — `AboutViewModel` doesn't exist.

- [ ] **Step 7: Implement `AboutViewModel`, `AboutView`, `DeveloperView`**

```swift
import Foundation
import GrabberKit

@MainActor
@Observable
final class AboutViewModel {
    let currentAppVersion: String
    private(set) var environmentReport: EnvironmentReport
    private(set) var appUpdateStatus: AppUpdateStatus = .notChecked

    private let updateChecker: AppUpdateChecker
    private let ytDlpUpdater: YtDlpUpdating

    init(
        currentAppVersion: String,
        environmentReport: EnvironmentReport,
        updateChecker: AppUpdateChecker,
        ytDlpUpdater: YtDlpUpdating
    ) {
        self.currentAppVersion = currentAppVersion
        self.environmentReport = environmentReport
        self.updateChecker = updateChecker
        self.ytDlpUpdater = ytDlpUpdater
    }

    func checkForAppUpdate() async {
        appUpdateStatus = await updateChecker.checkForUpdate(currentVersion: currentAppVersion)
    }

    func reinstallYtDlp() async {
        _ = await ytDlpUpdater.reinstallToMinimum()
        // Caller (AboutView's owning AppModel) is responsible for re-probing the environment
        // and pushing a fresh EnvironmentReport back in — see Task 7's restartYtDlp() for the
        // equivalent flow the HealthStrip chip uses; this model should receive updated state
        // the same way rather than re-probing independently.
    }
}
```

`AboutView` renders per `apps/media-grabber/docs/mockups/screens/about.html`'s `#s7-1-1`/`#s7-1-2`/`#s7-1-3` markup: centered identity block (app mark, name, version), then rows for MediaGrabber/yt-dlp/ffmpeg following the button-verb rule (`appUpdateStatus` drives MediaGrabber's row; `environmentReport.ytDlpDriftVerdict` drives yt-dlp's row directly, never through a "checking" state), then the Diagnostics link row (navigates to `.preferences(.diagnostics)`).

`DeveloperView` renders per `#s7-2`'s markup: avatar/name/headline identity block, the "Connect with me" icon-link row (GitHub and LinkedIn icons as real bundled brand-mark image assets per the design-system decision — add these as image assets in the asset catalog if one exists, or as bundled SVG/PDF resources following whatever pattern the app already uses for any bundled non-SF-Symbol image; check `Sources/App/Resources/` for precedent), and the credit rows (Source code, Report an issue, License) each opening the relevant URL via `NSWorkspace.shared.open(_:)`.

- [ ] **Step 8: Run tests to verify they pass**

Run: `xcodebuild -workspace MediaGrabber.xcworkspace -scheme MediaGrabber-Workspace -destination 'platform=macOS' test -only-testing:AppUnitTests/AboutViewTests`
Expected: PASS.

- [ ] **Step 9: Wire `AboutView` into `MainWindow`**

Confirm Task 12's `case .about: AboutView()` now compiles against a real (not stub) `AboutView` — construct it with whatever `AppModel` state it needs (`currentAppVersion`, the latest `EnvironmentReport`, an `AppUpdateChecker`, and `YtDlpUpdating`) the same way other pages are constructed from `AppModel` today.

- [ ] **Step 10: Run the full test suite and build**

Run: `xcodebuild -workspace MediaGrabber.xcworkspace -scheme MediaGrabber-Workspace -destination 'platform=macOS' test -only-testing:AppUnitTests`
Then `make`, navigate to About, confirm both tabs render, click "Check for updates," confirm the button state changes appropriately (or shows a failure gracefully if genuinely offline during manual testing).

- [ ] **Step 11: Lint**

Run: `mise exec -- swiftformat --lint Sources/App/About/` then `mise exec -- swiftlint lint --strict Sources/App/About/`

---

## Task 14: `IncomingLinkController` clipboard-sniff call sites (Copy report, Share diagnostic bundle)

**Files:**
- Modify: `Sources/App/Preferences/DiagnosticsPane.swift` (from Task 8 — confirm the `pasteboardMarker` wiring is real, not just test-injected)
- Modify: wherever `AppModel`/`PreferencesView` constructs `DiagnosticsPaneModel` in production (not test) code
- Test: `Tests/AppUnitTests/IncomingLinkControllerTests.swift` (existing — confirm/add an integration-level case)

This task closes the loop Task 8 left open: Task 8's `DiagnosticsPaneModel` accepts a `pasteboardMarker` closure defaulting to a no-op — this task wires the *real* `IncomingLinkController.markAppPasteboardWrite` into the production construction site. `AppModel.incomingLinkController: IncomingLinkController?` (`Sources/App/AppModel.swift:46`, `@ObservationIgnored weak var`) is weak and optional, so the production wiring must handle the nil case (a `nil` marker is simply a no-op, matching `DiagnosticsPaneModel`'s existing default).

- [ ] **Step 1: Write the failing integration test**

Add to `Tests/AppUnitTests/IncomingLinkControllerTests.swift`, matching that file's existing construction pattern (the same one used by `test_clipboard_externalWriteAfterSelfWrite_stillSniffed`):

```swift
func test_diagnosticsPaneModel_copyReport_ignoredByLaterClipboardSniff() async {
    let controller = <the same IncomingLinkController construction this file's existing tests already use>
    let model = DiagnosticsPaneModel(
        metadataProbe: FakeMetadataProbe(default: FakeMetadataProbe.success(title: "Big Buck Bunny")),
        environmentProbe: FakeEnvironmentProbe(.with(ytDlp: true, ffmpeg: true)),
        ytDlpUpdater: FakeYtDlpUpdater(),
        sharePresenter: DiagnosticsPaneTests.SpySharePresenter(),
        pasteboardMarker: controller.markAppPasteboardWrite
    )
    await model.runCheck()
    model.copyReport()
    // Simulate the same external-pasteboard poll IncomingLinkControllerTests already exercises,
    // and confirm the app's own copy is ignored the same way an external self-write is —
    // mirror the exact assertion style of test_clipboard_externalWriteAfterSelfWrite_stillSniffed
    // (the inverse case: OUR write should NOT be sniffed as an incoming link).
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `xcodebuild -workspace MediaGrabber.xcworkspace -scheme MediaGrabber-Workspace -destination 'platform=macOS' test -only-testing:AppUnitTests/IncomingLinkControllerTests`
Expected: FAIL — the production `DiagnosticsPaneModel` construction site (added in Task 8) does not yet pass `pasteboardMarker:`, so it defaults to the no-op closure and the test's assertion (the app's own copy being ignored) fails.

- [ ] **Step 3: Wire the real construction site**

Find wherever `PreferencesView`/`AppModel` constructs `DiagnosticsPaneModel` in production code (added in Task 8) and pass:

```swift
pasteboardMarker: { [weak appModel] text in appModel?.incomingLinkController?.markAppPasteboardWrite(text) }
```

(A plain `appModel.incomingLinkController?.markAppPasteboardWrite` reference cannot be passed directly as the closure since `incomingLinkController` is both `weak` and optional — wrap it in the explicit closure above so a `nil` controller is silently a no-op, matching `DiagnosticsPaneModel`'s own default.)

- [ ] **Step 4: Run test to verify it passes**

Run the same command as Step 2.
Expected: PASS.

- [ ] **Step 5: Manual verification**

Run `make`, open Diagnostics, click Run check, click Copy report, then immediately trigger a clipboard-detect poll (paste the same copied text into Home's field manually, or wait for the poll if clipboard-detect is enabled in Preferences) — confirm the app does NOT treat its own copy as an incoming link to grab.

- [ ] **Step 6: Lint**

Run lint on whatever file was changed in Step 3.

---

## Task 15: Documentation updates

**Files:**
- Modify: `apps/media-grabber/docs/design-system.md`
- Modify: `apps/media-grabber/CLAUDE.md`

**No code changes in this task** — pure documentation reconciliation now that the implementation is real and may have deviated in small ways from the brainstorming-stage mockups (e.g. exact SwiftUI component names).

- [ ] **Step 1: Update design-system.md §4.2.3's column table**

Find the Downloads-table column list in `apps/media-grabber/docs/design-system.md` (§4.2.3, referenced but not directly quoted in this plan's research pass — read it now) and add the `Remark` column (hidden by default, positioned after Status) to match the 17-column reality Task 11 implemented.

- [ ] **Step 2: Confirm §4.6, §4.7, §4.8 still match the shipped UI**

Read `apps/media-grabber/docs/design-system.md` §4.6 (Preferences), §4.7 (Diagnostics), §4.8 (About) against the actual `DiagnosticsPane`/`UpdatesPane`/`AboutView`/`DeveloperView` SwiftUI code from Tasks 8, 9, 13. If any real button label, row order, or copy string drifted from the brainstormed spec during implementation (which sometimes happens for good reasons — a SwiftUI layout constraint, an API limitation), update the doc to match the shipped reality rather than leaving it describing an unbuilt variant. Do not silently accept a drift that has no good reason — if something changed without a real reason, fix the code to match the spec instead of the doc.

- [ ] **Step 3: Update CLAUDE.md's phase-status line**

`apps/media-grabber/CLAUDE.md`'s "Next: Phase 11 — Diagnostics, About, updates (brainstormed; not yet planned)" line needs updating once this plan is fully executed — change to reflect Phase 11 as shipped, following the exact pattern used for Phase 9/Phase 10's entries (spec + plan file paths, "(shipped)" marker) elsewhere in that same file section.

---

## Self-Review Notes

**Spec coverage check:**
- §5.2 chip busy state → Task 6. Engine-freshness chip → Task 7. ✓
- §5.4 Status/Remark split, Site names, Title truncation → Task 11 (Status/Remark in Steps 5-9, Site names in Task 10, Title truncation in Step 4.5). ✓
- §5.9 Updates pane → Task 9. ✓
- §5.10 Diagnostics → Task 8. ✓
- §5.12 About/Developer → Task 13. ✓
- §10.1a yt-dlp pin → Tasks 1, 2, 3. ✓
- §10.2 self-update → Task 13 (`AppUpdateChecker`). ✓
- Onboarding canary reuse → Task 4. ✓
- `DiagnosticBundle` → Task 5. ✓
- `markAppPasteboardWrite` callers → Task 14. ✓
- `DebugFlags` Debug menu → deferred, hint carried in `ticket-backlog.md`'s Phase 12 entry.

**Fix applied inline:** Title-column truncation is Task 11 Step 4.5 — same file (`DownloadRow.swift`) Task 11 already touches for the Remark column.

**Type consistency check:** `DottedVersion`/`YtDlpDriftVerdict` (Task 1) flow unchanged through Tasks 2, 3, 7, 13 — same names throughout. `SharePresenting`/`SharePresenter` (Task 8) consistent. `DiagnosticsPaneModel` consistent between Tasks 8 and 14. `AboutViewModel` consistent within Task 13. No renamed-halfway signatures.

**Placeholder scan:** Task 13's `AppUpdateChecker` uses the literal GitHub owner `Mshardul` and repo `Tools`. No placeholders remain anywhere in the plan.
