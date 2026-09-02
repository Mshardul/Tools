# MediaGrabber Phase 5 (Cookies) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Let a user hand `yt-dlp` a browser's YouTube sign-in — opt-in via Preferences or a `🔑` retry — so age-restricted, private, and bot-checked videos download.

**Architecture:** A new self-contained `GrabberKit/Cookies/` unit (no SwiftUI) owns `CookieSource` (the browser enum) and `CookieResolver` (Firefox `profiles.ini` parse, Safari Full-Disk-Access probe-read, spawn-time argument resolution). `DownloadEngine` resolves a cookie argument in its synchronous launch setup and threads it through `YtDlpArguments`. A filled Sign-in & cookies Preferences pane and a `🔑 retryWithCookies` row action consume the same resolver. `cookieReadFailed` gets a live classifier (stderr signatures + a `Extracted 0 cookies` + downstream-failure override).

**Tech Stack:** Swift 6, SwiftUI (App target), XCTest, Tuist. Two targets: `GrabberKit` (headless) and `MediaGrabber` (app).

**Spec:** `docs/superpowers/specs/2026-09-02-media-grabber-phase-5.md`

## Global Constraints

- **Comments:** single-line only, only to explain *why*, only when names don't carry it. No `///` doc comments, no stacked `//` blocks. If the "why" needs two lines, restructure instead.
- **No phase / ticket / epic references** anywhere in source, tests, UI copy, log strings, mockup HTML, or `Info.plist`. The plan and specs are the only place phase numbers live.
- **No git.** No plan step commits, branches, tags, or mentions VCS. Each task's gate is a clean lint + test pass, then hand off. File moves use `mv`.
- **Every change is built to the app's final-app form** — no stubs a later phase must replace. `CookieSource`, `CookieResolver`, and the filled pane are the shapes the app keeps.
- **Deployment target macOS 14.** `Synchronization.Mutex` needs 15 — use `os_unfair_lock`-backed `LockedBox` for shared mutable state touched from `async` code. `NSLock.lock()/.unlock()` banned in async contexts.
- **Build:** `mise exec -- tuist generate --no-open` after adding/removing files.
- **Test:** `xcodebuild -workspace MediaGrabber.xcworkspace -scheme MediaGrabber-Workspace -destination 'platform=macOS' test`. Single suite: append `-only-testing:GrabberKitTests/<SuiteName>` or `AppUnitTests/<SuiteName>`. Do NOT use `tuist test` while debugging — it hides compiler errors.
- **Lint:** `mise exec -- swiftformat --lint .` and `mise exec -- swiftlint lint --strict` — both must be clean.
- **Lint traps (hit before, will recur):**
  - `swiftformat` + `swiftlint` disagree on the `{` placement for a wrapped multi-line `if` / `for ... where`. Fix: extract the condition into a named predicate function; use `table.first { entry in ... }?.field` not `for entry in table where ...`.
  - `swiftlint cyclomatic_complexity` (limit 10) fails a `switch` mixing `case let` bindings with comma-grouped patterns. Use a dictionary lookup or split the function.
  - `swiftlint type_body_length` (250, strict) — adding ~3 tests or a helper to an already-large `XCTestCase` trips it. Put new tests in a sibling `Foo+X.swift` / `FooXTests.swift` file; drop `private` on the few stored props the extension needs.
- **Concurrency traps:** `XCTestCase` is not `Sendable` — build a value before a `Task {}` and capture only `Sendable` locals. `DownloadJob` is engine-actor-isolated; the engine hops `MainActor.run` for job mutations. Engine tests that read `job.state` must be `@MainActor` and poll to a terminal state.
- **No network in tests.** `CookieResolver`'s filesystem is injected; tests script a fake. No real `profiles.ini`, real cookie DBs, real System Settings, real `NSWorkspace`, or SwiftUI rendering in tests.
- **`browserKey` values:** `"none"`, `"safari"`, `"chrome"`, `"brave"`, `"edge"`, `"firefox"`.
- **`ytDlpSpec` values:** `nil` for `.none`; `"safari"` / `"chrome"` / `"brave"` / `"edge"`; `"firefox:<profile>"` or `"firefox"` for `.firefox`.

---

## File Structure

### New — `Sources/GrabberKit/Cookies/`

| File | Responsibility |
|---|---|
| `CookieSource.swift` | The `CookieSource` enum + `browserKey` + `ytDlpSpec` + `isNone`; `Codable` |
| `FirefoxProfile.swift` | `FirefoxProfile` value — `{ name, path, isDefault }`, `Identifiable` |
| `CookieVerdict.swift` | `SafariCookieAccess`, `CookieVerdict`, `CookieResolution` value types |
| `FileManaging.swift` | The 3-method filesystem protocol + `FoundationFileManager` real impl |
| `CookieResolver.swift` | `firefoxProfiles()`, `safariAccess()`, `resolve(source:jobOverride:)` |
| `CookieHelpURL.swift` | `browserKey` → help URL, one config constant |

### New — App target

| File | Responsibility |
|---|---|
| `Sources/App/Preferences/CookiePaneModel.swift` | `@Observable` bridge: `CookieResolver` ↔ pane rows; deep-link sinks |
| `Sources/App/Preferences/SettingsLinkOpening.swift` | Protocol + `WorkspaceSettingsLink` for the FDA System-Settings deep link |

### Modified — `GrabberKit`

| File | Change |
|---|---|
| `Sources/GrabberKit/Model/Preferences.swift` | `+ cookiesFromBrowser: CookieSource` (default `.none`); key in `ownedKeys` |
| `Sources/GrabberKit/Download/DownloadJob.swift` | `+ var forceCookies: Bool` (default `false`) |
| `Sources/GrabberKit/Model/PersistedJob.swift` | `+ forceCookies: Bool` round-trip |
| `Sources/GrabberKit/Download/DownloadEngine+State.swift` | `persistedJob(from:)` / `downloadJob(from:)` carry `forceCookies` |
| `Sources/GrabberKit/Download/YtDlpArguments.swift` | `build` / `redacted` gain `cookieArgument: String? = nil` |
| `Sources/GrabberKit/Download/ErrorSignatures.swift` | `+ cookieReadFailed` entry, first in the table |
| `Sources/GrabberKit/Download/FailurePresentation.swift` | `cookieReadFailed` / `ageRestricted` / `private` gain `.retryWithCookies` |
| `Sources/GrabberKit/Download/DownloadEngineProtocol.swift` | `+ func retryWithCookies(_:) async`; `EngineDependencies + fileManager: FileManaging` |
| `Sources/GrabberKit/Download/DownloadEngine.swift` | `DownloadDrainOutcome + extractedZeroCookies`; spawn resolves the cookie argument; `recordExit` call passes `cookiesRequested` |
| `Sources/GrabberKit/Download/DownloadEngine+Mutations.swift` | `recordExit` gains `cookiesRequested: Bool`; the 0-cookies override |
| `Sources/GrabberKit/Download/DownloadEngine+Retry.swift` | `+ retryWithCookies(_:)` |

### Modified — App target

| File | Change |
|---|---|
| `Sources/App/Preferences/Panes/SignInCookiesPane.swift` | Replace the stepless placeholder with the filled pane |
| `Sources/App/AppModel.swift` | `+ pendingCookieRetryJobID`, `resolveCookieRetry()`, `page didSet` clear |
| `Sources/App/AppModelRowActions.swift` | Fill the `.retryWithCookies` case |

### Modified — mockups + parent spec

| File | Change |
|---|---|
| `docs/mockups/screens.html` | Screen 3.4 fills (both Firefox and Safari states); Screen 1.2 `cookieReadFailed` row gets the real sentence + enabled `🔑` |
| `docs/superpowers/specs/2026-08-28-youtube-downloader-mac-design.md` | §5 model, §7.2, §7.3, §9, §12.1 Phase 5 stub + onboarding row, §12.2 rows |

### Modified — test fakes

| File | Change |
|---|---|
| `Tests/AppUnitTests/Support/AppFakes.swift` | `FakeEngine + retryWithCookies` recorder |
| `Tests/GrabberKitTests/QuitCoordinatorTests.swift` | its private `FakeEngine + retryWithCookies` stub |
| `Tests/GrabberKitTests/DownloadEngineTestHelpers.swift` | `EngineFixture.engine` accepts an optional `FileManaging` |

---

## Task 1: `CookieSource` value type

**Files:**
- Create: `apps/media-grabber/Sources/GrabberKit/Cookies/CookieSource.swift`
- Create: `apps/media-grabber/Sources/GrabberKit/Cookies/FirefoxProfile.swift`
- Test: `apps/media-grabber/Tests/GrabberKitTests/CookieSourceTests.swift`

**Interfaces:**
- Produces:
  - `public enum CookieSource: Sendable, Equatable, Codable { case none, safari, chrome, brave, edge; case firefox(profile: String?) }`
  - `public var browserKey: String` — `"none" | "safari" | "chrome" | "brave" | "edge" | "firefox"`
  - `public var ytDlpSpec: String?` — `nil` for `.none`; `"safari"/"chrome"/"brave"/"edge"`; `"firefox:\(profile)"` or `"firefox"`
  - `public var isNone: Bool`
  - `public struct FirefoxProfile: Sendable, Equatable, Identifiable { var id: String { name }; let name: String; let path: String; let isDefault: Bool }`

- [x] **Step 1: Write the failing test**

```swift
@testable import GrabberKit
import XCTest

final class CookieSourceTests: XCTestCase {
    func test_browserKey_perCase() {
        XCTAssertEqual(CookieSource.none.browserKey, "none")
        XCTAssertEqual(CookieSource.safari.browserKey, "safari")
        XCTAssertEqual(CookieSource.chrome.browserKey, "chrome")
        XCTAssertEqual(CookieSource.brave.browserKey, "brave")
        XCTAssertEqual(CookieSource.edge.browserKey, "edge")
        XCTAssertEqual(CookieSource.firefox(profile: "dev").browserKey, "firefox")
        XCTAssertEqual(CookieSource.firefox(profile: nil).browserKey, "firefox")
    }

    func test_ytDlpSpec_perCase() {
        XCTAssertNil(CookieSource.none.ytDlpSpec)
        XCTAssertEqual(CookieSource.safari.ytDlpSpec, "safari")
        XCTAssertEqual(CookieSource.chrome.ytDlpSpec, "chrome")
        XCTAssertEqual(CookieSource.brave.ytDlpSpec, "brave")
        XCTAssertEqual(CookieSource.edge.ytDlpSpec, "edge")
        XCTAssertEqual(CookieSource.firefox(profile: "default-release").ytDlpSpec, "firefox:default-release")
        XCTAssertEqual(CookieSource.firefox(profile: nil).ytDlpSpec, "firefox")
    }

    func test_isNone() {
        XCTAssertTrue(CookieSource.none.isNone)
        XCTAssertFalse(CookieSource.safari.isNone)
    }

    func test_codableRoundTrip_includingFirefoxProfile() throws {
        let cases: [CookieSource] = [.none, .safari, .chrome, .brave, .edge,
                                     .firefox(profile: "x"), .firefox(profile: nil)]
        for source in cases {
            let data = try JSONEncoder().encode(source)
            let decoded = try JSONDecoder().decode(CookieSource.self, from: data)
            XCTAssertEqual(decoded, source)
        }
    }
}
```

- [x] **Step 2: Run test to verify it fails**

Run: `xcodebuild -workspace MediaGrabber.xcworkspace -scheme MediaGrabber-Workspace -destination 'platform=macOS' test -only-testing:GrabberKitTests/CookieSourceTests`
Expected: FAIL — `cannot find 'CookieSource' in scope`.

- [x] **Step 3: Write `FirefoxProfile.swift`**

```swift
import Foundation

public struct FirefoxProfile: Sendable, Equatable, Identifiable {
    public var id: String { name }
    public let name: String
    public let path: String
    public let isDefault: Bool

    public init(name: String, path: String, isDefault: Bool) {
        self.name = name
        self.path = path
        self.isDefault = isDefault
    }
}
```

- [x] **Step 4: Write `CookieSource.swift`**

```swift
import Foundation

public enum CookieSource: Sendable, Equatable, Codable {
    case none
    case safari
    case chrome
    case brave
    case edge
    case firefox(profile: String?)

    public var browserKey: String {
        switch self {
        case .none: "none"
        case .safari: "safari"
        case .chrome: "chrome"
        case .brave: "brave"
        case .edge: "edge"
        case .firefox: "firefox"
        }
    }

    public var ytDlpSpec: String? {
        switch self {
        case .none: nil
        case .safari: "safari"
        case .chrome: "chrome"
        case .brave: "brave"
        case .edge: "edge"
        case let .firefox(profile):
            profile.map { "firefox:\($0)" } ?? "firefox"
        }
    }

    public var isNone: Bool { self == .none }
}
```

- [x] **Step 5: Run tests to verify they pass**

Run: `xcodebuild ... test -only-testing:GrabberKitTests/CookieSourceTests` (after `mise exec -- tuist generate --no-open`)
Expected: PASS.

- [x] **Step 6: Lint**

Run: `mise exec -- swiftformat --lint . && mise exec -- swiftlint lint --strict`
Expected: clean.

---

## Task 2: `FileManaging` protocol + `CookieVerdict` value types

**Files:**
- Create: `apps/media-grabber/Sources/GrabberKit/Cookies/FileManaging.swift`
- Create: `apps/media-grabber/Sources/GrabberKit/Cookies/CookieVerdict.swift`
- Test: `apps/media-grabber/Tests/GrabberKitTests/FileManagingTests.swift`

**Interfaces:**
- Produces:
  - `public protocol FileManaging: Sendable { func fileExists(atPath path: String) -> Bool; func contentsOfDirectory(at url: URL) -> [URL]; func dataReadable(at url: URL) -> Bool }`
  - `public struct FoundationFileManager: FileManaging { public init() }` — `contentsOfDirectory` returns `[]` on throw; `dataReadable` opens `O_RDONLY` and immediately closes, `true` only on a successful open
  - `public enum SafariCookieAccess: Sendable, Equatable { case granted, denied, noContainer }`
  - `public enum CookieVerdict: Sendable, Equatable { case unconfigured; case ready(browserKey: String); case needsFullDiskAccess; case noProfiles }`
  - `public struct CookieResolution: Sendable, Equatable { public let argument: String?; public let verdict: CookieVerdict }`

- [x] **Step 1: Write the failing test**

```swift
@testable import GrabberKit
import XCTest

final class FileManagingTests: XCTestCase {
    func test_foundation_fileExists_andReadable_forThisSourceFile() {
        let fm = FoundationFileManager()
        let path = #filePath
        XCTAssertTrue(fm.fileExists(atPath: path))
        XCTAssertTrue(fm.dataReadable(at: URL(fileURLWithPath: path)))
    }

    func test_foundation_dataReadable_falseForMissingFile() {
        let fm = FoundationFileManager()
        let missing = URL(fileURLWithPath: "/nonexistent/\(UUID().uuidString)")
        XCTAssertFalse(fm.dataReadable(at: missing))
    }

    func test_foundation_contentsOfDirectory_emptyArrayForMissingDir() {
        let fm = FoundationFileManager()
        let missing = URL(fileURLWithPath: "/nonexistent-dir-\(UUID().uuidString)")
        XCTAssertEqual(fm.contentsOfDirectory(at: missing), [])
    }

    func test_foundation_contentsOfDirectory_listsRealDir() throws {
        let fm = FoundationFileManager()
        let dir = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("mg-fm-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let file = dir.appendingPathComponent("a.txt")
        try Data("x".utf8).write(to: file)
        XCTAssertEqual(fm.contentsOfDirectory(at: dir).map(\.lastPathComponent), ["a.txt"])
    }
}
```

- [x] **Step 2: Run test to verify it fails**

Run: `xcodebuild ... test -only-testing:GrabberKitTests/FileManagingTests`
Expected: FAIL — `cannot find 'FoundationFileManager' in scope`.

- [x] **Step 3: Write `CookieVerdict.swift`**

```swift
import Foundation

public enum SafariCookieAccess: Sendable, Equatable {
    case granted
    case denied
    case noContainer
}

public enum CookieVerdict: Sendable, Equatable {
    case unconfigured
    case ready(browserKey: String)
    case needsFullDiskAccess
    case noProfiles
}

public struct CookieResolution: Sendable, Equatable {
    public let argument: String?
    public let verdict: CookieVerdict

    public init(argument: String?, verdict: CookieVerdict) {
        self.argument = argument
        self.verdict = verdict
    }
}
```

- [x] **Step 4: Write `FileManaging.swift`**

```swift
import Foundation

public protocol FileManaging: Sendable {
    func fileExists(atPath path: String) -> Bool
    func contentsOfDirectory(at url: URL) -> [URL]
    func dataReadable(at url: URL) -> Bool
}

public struct FoundationFileManager: FileManaging {
    public init() {}

    public func fileExists(atPath path: String) -> Bool {
        FileManager.default.fileExists(atPath: path)
    }

    public func contentsOfDirectory(at url: URL) -> [URL] {
        (try? FileManager.default.contentsOfDirectory(
            at: url,
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles]
        )) ?? []
    }

    public func dataReadable(at url: URL) -> Bool {
        let descriptor = open(url.path, O_RDONLY)
        guard descriptor >= 0 else { return false }
        close(descriptor)
        return true
    }
}
```

- [x] **Step 5: Run tests to verify they pass**

Run: `xcodebuild ... test -only-testing:GrabberKitTests/FileManagingTests`
Expected: PASS.

- [x] **Step 6: Lint**

Run: `mise exec -- swiftformat --lint . && mise exec -- swiftlint lint --strict`
Expected: clean.

---

## Task 3: `CookieResolver.firefoxProfiles()`

**Files:**
- Create: `apps/media-grabber/Sources/GrabberKit/Cookies/CookieResolver.swift`
- Test: `apps/media-grabber/Tests/GrabberKitTests/CookieResolverFirefoxTests.swift`
- Create: `apps/media-grabber/Tests/GrabberKitTests/Support/FakeFileManaging.swift`

**Interfaces:**
- Consumes: `FileManaging` (Task 2), `FirefoxProfile` (Task 1).
- Produces:
  - `public struct CookieResolver: Sendable { public init(fileManager: FileManaging = FoundationFileManager(), home: URL = FileManager.default.homeDirectoryForCurrentUser) }`
  - `public func firefoxProfiles() -> [FirefoxProfile]` — parses `<home>/Library/Application Support/Firefox/profiles.ini`; absent file → `[]`; unparseable sections skipped, never thrown
  - `struct FakeFileManaging: FileManaging` (test support) — scripted `files: Set<String>`, `dirs: [String: [URL]]`, `readable: Set<String>`, `contents: [String: String]` (path → text, for the INI read via `contentsOfDirectory`-independent reads — see note below)

**Note on reading `profiles.ini`:** `FileManaging` has no "read file text" method. `firefoxProfiles()` reads the INI through `String(contentsOf:)` guarded by `fileManager.fileExists(atPath:)` and `fileManager.dataReadable(at:)`. To keep it testable, add one method to `FileManaging`:
`func fileContents(at url: URL) -> String?` (real impl: `try? String(contentsOf: url, encoding: .utf8)`). Update Task 2's protocol, `FoundationFileManager`, and `FileManagingTests` in this task (add a `fileContents` assertion on `#filePath`).

- [x] **Step 1: Add `fileContents(at:)` to `FileManaging` and `FoundationFileManager`**

In `Sources/GrabberKit/Cookies/FileManaging.swift`:

```swift
public protocol FileManaging: Sendable {
    func fileExists(atPath path: String) -> Bool
    func contentsOfDirectory(at url: URL) -> [URL]
    func dataReadable(at url: URL) -> Bool
    func fileContents(at url: URL) -> String?
}
```

```swift
    public func fileContents(at url: URL) -> String? {
        try? String(contentsOf: url, encoding: .utf8)
    }
```

- [x] **Step 2: Write `FakeFileManaging.swift` (test support)**

```swift
import Foundation
@testable import GrabberKit

struct FakeFileManaging: FileManaging {
    var files: Set<String> = []
    var readable: Set<String> = []
    var dirs: [String: [URL]] = [:]
    var contents: [String: String] = [:]

    func fileExists(atPath path: String) -> Bool { files.contains(path) }
    func contentsOfDirectory(at url: URL) -> [URL] { dirs[url.path] ?? [] }
    func dataReadable(at url: URL) -> Bool { readable.contains(url.path) }
    func fileContents(at url: URL) -> String? { contents[url.path] }
}
```

- [x] **Step 3: Write the failing test**

```swift
@testable import GrabberKit
import XCTest

final class CookieResolverFirefoxTests: XCTestCase {
    private let home = URL(fileURLWithPath: "/Users/tester")

    private var iniPath: String {
        home.appendingPathComponent("Library/Application Support/Firefox/profiles.ini").path
    }

    private var profilesDir: String {
        home.appendingPathComponent("Library/Application Support/Firefox/Profiles").path
    }

    private func resolver(ini: String?) -> CookieResolver {
        var fm = FakeFileManaging()
        if let ini {
            fm.files = [iniPath]
            fm.readable = [iniPath]
            fm.contents = [iniPath: ini]
        }
        return CookieResolver(fileManager: fm, home: home)
    }

    func test_absentFile_returnsEmpty() {
        XCTAssertEqual(resolver(ini: nil).firefoxProfiles(), [])
    }

    func test_twoProfiles_relativePaths_defaultMarked() {
        let ini = """
        [Install4F96D1932A9F858E]
        Default=Profiles/abc.default-release

        [Profile1]
        Name=default
        IsRelative=1
        Path=Profiles/xyz.default

        [Profile0]
        Name=default-release
        IsRelative=1
        Path=Profiles/abc.default-release
        """
        let got = resolver(ini: ini).firefoxProfiles()
        XCTAssertEqual(Set(got.map(\.name)), ["default", "default-release"])
        let def = got.first { $0.isDefault }
        XCTAssertEqual(def?.name, "default-release")
        XCTAssertEqual(def?.path, "\(profilesDir)/abc.default-release")
    }

    func test_absolutePath_usedVerbatim() {
        let ini = """
        [Profile0]
        Name=custom
        IsRelative=0
        Path=/opt/ff/custom
        Default=1
        """
        let got = resolver(ini: ini).firefoxProfiles()
        XCTAssertEqual(got.count, 1)
        XCTAssertEqual(got[0].path, "/opt/ff/custom")
        XCTAssertTrue(got[0].isDefault)
    }

    func test_malformedSectionSkipped_notThrown() {
        let ini = """
        [Profile0]
        garbage line without equals
        Name=ok
        Path=Profiles/ok

        [Profile1]
        Name=
        Path=
        """
        let got = resolver(ini: ini).firefoxProfiles()
        XCTAssertEqual(got.map(\.name), ["ok"])
    }

    func test_zeroProfiles_returnsEmpty() {
        XCTAssertEqual(resolver(ini: "[General]\nStartWithLastProfile=1").firefoxProfiles(), [])
    }
}
```

- [x] **Step 4: Run test to verify it fails**

Run: `xcodebuild ... test -only-testing:GrabberKitTests/CookieResolverFirefoxTests`
Expected: FAIL — `cannot find 'CookieResolver' in scope`.

- [x] **Step 5: Write `CookieResolver.swift` (firefoxProfiles only for now)**

```swift
import Foundation

public struct CookieResolver: Sendable {
    private let fileManager: FileManaging
    private let home: URL

    public init(
        fileManager: FileManaging = FoundationFileManager(),
        home: URL = FileManager.default.homeDirectoryForCurrentUser
    ) {
        self.fileManager = fileManager
        self.home = home
    }

    private var firefoxRoot: URL {
        home.appendingPathComponent("Library/Application Support/Firefox")
    }

    public func firefoxProfiles() -> [FirefoxProfile] {
        let iniURL = firefoxRoot.appendingPathComponent("profiles.ini")
        guard fileManager.fileExists(atPath: iniURL.path),
              fileManager.dataReadable(at: iniURL),
              let text = fileManager.fileContents(at: iniURL)
        else {
            return []
        }
        return parseProfiles(fromINI: text)
    }

    private func parseProfiles(fromINI text: String) -> [FirefoxProfile] {
        let sections = iniSections(text)
        let defaultPaths = Set(
            sections
                .filter { $0.header.hasPrefix("Install") }
                .compactMap { $0.values["Default"] }
        )
        return sections.compactMap { section in
            guard section.header.hasPrefix("Profile"),
                  let name = section.values["Name"], !name.isEmpty,
                  let rawPath = section.values["Path"], !rawPath.isEmpty
            else {
                return nil
            }
            let isRelative = (section.values["IsRelative"] ?? "1") != "0"
            let absolute = isRelative
                ? firefoxRoot.appendingPathComponent(rawPath).path
                : rawPath
            let markedDefault = section.values["Default"] == "1"
                || defaultPaths.contains(rawPath)
            return FirefoxProfile(name: name, path: absolute, isDefault: markedDefault)
        }
    }

    private struct INISection {
        var header: String
        var values: [String: String]
    }

    private func iniSections(_ text: String) -> [INISection] {
        var sections: [INISection] = []
        for line in text.split(separator: "\n", omittingEmptySubsequences: true) {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.hasPrefix("["), trimmed.hasSuffix("]") {
                sections.append(INISection(header: String(trimmed.dropFirst().dropLast()), values: [:]))
                continue
            }
            guard !sections.isEmpty,
                  let eq = trimmed.firstIndex(of: "=")
            else {
                continue
            }
            let key = String(trimmed[..<eq]).trimmingCharacters(in: .whitespaces)
            let value = String(trimmed[trimmed.index(after: eq)...]).trimmingCharacters(in: .whitespaces)
            sections[sections.count - 1].values[key] = value
        }
        return sections
    }
}
```

- [x] **Step 6: Run tests to verify they pass**

Run: `xcodebuild ... test -only-testing:GrabberKitTests/CookieResolverFirefoxTests -only-testing:GrabberKitTests/FileManagingTests`
Expected: PASS.

- [x] **Step 7: Lint**

Run: `mise exec -- swiftformat --lint . && mise exec -- swiftlint lint --strict`
Expected: clean. Watch `cyclomatic_complexity` on `parseProfiles` / `iniSections` — split further if it trips.

---

## Task 4: `CookieResolver.safariAccess()`

**Files:**
- Modify: `apps/media-grabber/Sources/GrabberKit/Cookies/CookieResolver.swift`
- Test: `apps/media-grabber/Tests/GrabberKitTests/CookieResolverSafariTests.swift`

**Interfaces:**
- Produces: `public func safariAccess() -> SafariCookieAccess` — targets `<home>/Library/Containers/com.apple.Safari/Data/Library/Cookies/Cookies.binarycookies`. Not `fileExists` → `.noContainer`; `fileExists` + `dataReadable` → `.granted`; `fileExists` + not `dataReadable` → `.denied`.

- [x] **Step 1: Write the failing test**

```swift
@testable import GrabberKit
import XCTest

final class CookieResolverSafariTests: XCTestCase {
    private let home = URL(fileURLWithPath: "/Users/tester")

    private var cookiePath: String {
        home.appendingPathComponent(
            "Library/Containers/com.apple.Safari/Data/Library/Cookies/Cookies.binarycookies"
        ).path
    }

    private func resolver(exists: Bool, readable: Bool) -> CookieResolver {
        var fm = FakeFileManaging()
        if exists { fm.files = [cookiePath] }
        if readable { fm.readable = [cookiePath] }
        return CookieResolver(fileManager: fm, home: home)
    }

    func test_noContainer() {
        XCTAssertEqual(resolver(exists: false, readable: false).safariAccess(), .noContainer)
    }

    func test_granted() {
        XCTAssertEqual(resolver(exists: true, readable: true).safariAccess(), .granted)
    }

    func test_denied() {
        XCTAssertEqual(resolver(exists: true, readable: false).safariAccess(), .denied)
    }
}
```

- [x] **Step 2: Run test to verify it fails**

Run: `xcodebuild ... test -only-testing:GrabberKitTests/CookieResolverSafariTests`
Expected: FAIL — `value of type 'CookieResolver' has no member 'safariAccess'`.

- [x] **Step 3: Add `safariAccess()` to `CookieResolver`**

```swift
    public func safariAccess() -> SafariCookieAccess {
        let cookiesURL = home.appendingPathComponent(
            "Library/Containers/com.apple.Safari/Data/Library/Cookies/Cookies.binarycookies"
        )
        guard fileManager.fileExists(atPath: cookiesURL.path) else { return .noContainer }
        return fileManager.dataReadable(at: cookiesURL) ? .granted : .denied
    }
```

- [x] **Step 4: Run tests to verify they pass**

Run: `xcodebuild ... test -only-testing:GrabberKitTests/CookieResolverSafariTests`
Expected: PASS.

- [x] **Step 5: Lint**

Run: `mise exec -- swiftformat --lint . && mise exec -- swiftlint lint --strict`
Expected: clean.

---

## Task 5: `CookieResolver.resolve(source:jobOverride:)`

**Files:**
- Modify: `apps/media-grabber/Sources/GrabberKit/Cookies/CookieResolver.swift`
- Test: `apps/media-grabber/Tests/GrabberKitTests/CookieResolverResolveTests.swift`

**Interfaces:**
- Consumes: `CookieSource` (Task 1), `firefoxProfiles()` (Task 3), `safariAccess()` (Task 4).
- Produces: `public func resolve(source: CookieSource, jobOverride: Bool) -> CookieResolution`

**Decision table:**

| `source` | `jobOverride` | `argument` | `verdict` |
|---|---|---|---|
| `.none` | `false` | `nil` | `.unconfigured` |
| `.none` | `true` | substituted browser's spec, or `nil` | `.ready(browserKey:)` / `.unconfigured` |
| `.safari` | either | `"safari"` if `safariAccess() == .granted`, else `nil` | `.ready("safari")` / `.needsFullDiskAccess` |
| `.firefox(name)` | either | `"firefox:<resolved>"` or `"firefox"`, or `nil` | `.ready("firefox")` / `.noProfiles` |
| `.chrome` / `.brave` / `.edge` | either | `"<key>"` | `.ready(key)` |

- `.firefox(name)` resolution: if `name` is non-nil and present in `firefoxProfiles()` → `"firefox:\(name)"`. If `name` is non-nil but absent, or `name` is nil: pick the `isDefault` profile's name → `"firefox:\(defaultName)"`; if no profiles at all → `nil`, `.noProfiles`; if profiles exist but none marked default and `name` was nil → `"firefox"` (yt-dlp's own default), `.ready("firefox")`.
- `.none + jobOverride` substitution order: `.safari` when `safariAccess() != .denied` (i.e. `.granted` or `.noContainer` — but `.noContainer` yields `argument: nil` from the Safari arm, so effectively only `.granted` produces `"safari"`); else the first of `.chrome` / `.brave` / `.edge` / `.firefox` whose browser-support directory exists; else `argument: nil`, `.unconfigured`.

**Browser support directories** (existence check via `fileManager.contentsOfDirectory(at:).isEmpty == false` OR `fileManager.fileExists(atPath:)` on the dir):
- Chrome: `<home>/Library/Application Support/Google/Chrome`
- Brave: `<home>/Library/Application Support/BraveSoftware/Brave-Browser`
- Edge: `<home>/Library/Application Support/Microsoft Edge`
- Firefox: `<home>/Library/Application Support/Firefox`

- [x] **Step 1: Write the failing test**

```swift
@testable import GrabberKit
import XCTest

final class CookieResolverResolveTests: XCTestCase {
    private let home = URL(fileURLWithPath: "/Users/tester")

    private var safariCookiePath: String {
        home.appendingPathComponent(
            "Library/Containers/com.apple.Safari/Data/Library/Cookies/Cookies.binarycookies"
        ).path
    }

    private var chromeDir: String {
        home.appendingPathComponent("Library/Application Support/Google/Chrome").path
    }

    private func resolver(_ fm: FakeFileManaging) -> CookieResolver {
        CookieResolver(fileManager: fm, home: home)
    }

    func test_none_noOverride_unconfigured() {
        let got = resolver(FakeFileManaging()).resolve(source: .none, jobOverride: false)
        XCTAssertNil(got.argument)
        XCTAssertEqual(got.verdict, .unconfigured)
    }

    func test_none_override_picksSafariWhenReadable() {
        var fm = FakeFileManaging()
        fm.files = [safariCookiePath]
        fm.readable = [safariCookiePath]
        let got = resolver(fm).resolve(source: .none, jobOverride: true)
        XCTAssertEqual(got.argument, "safari")
        XCTAssertEqual(got.verdict, .ready(browserKey: "safari"))
    }

    func test_none_override_fallsToFirstExistingBrowserDir() {
        var fm = FakeFileManaging()
        fm.dirs = [chromeDir: [home.appendingPathComponent("x")]]
        let got = resolver(fm).resolve(source: .none, jobOverride: true)
        XCTAssertEqual(got.argument, "chrome")
        XCTAssertEqual(got.verdict, .ready(browserKey: "chrome"))
    }

    func test_none_override_noBrowsers_unconfigured() {
        let got = resolver(FakeFileManaging()).resolve(source: .none, jobOverride: true)
        XCTAssertNil(got.argument)
        XCTAssertEqual(got.verdict, .unconfigured)
    }

    func test_safari_denied_needsFullDiskAccess() {
        var fm = FakeFileManaging()
        fm.files = [safariCookiePath]
        let got = resolver(fm).resolve(source: .safari, jobOverride: false)
        XCTAssertNil(got.argument)
        XCTAssertEqual(got.verdict, .needsFullDiskAccess)
    }

    func test_safari_granted_ready() {
        var fm = FakeFileManaging()
        fm.files = [safariCookiePath]
        fm.readable = [safariCookiePath]
        let got = resolver(fm).resolve(source: .safari, jobOverride: false)
        XCTAssertEqual(got.argument, "safari")
        XCTAssertEqual(got.verdict, .ready(browserKey: "safari"))
    }

    func test_chrome_ready() {
        let got = resolver(FakeFileManaging()).resolve(source: .chrome, jobOverride: false)
        XCTAssertEqual(got.argument, "chrome")
        XCTAssertEqual(got.verdict, .ready(browserKey: "chrome"))
    }

    func test_firefox_namedProfilePresent() {
        let fm = firefoxFM(ini: """
        [Profile0]
        Name=work
        Path=Profiles/work
        """)
        let got = resolver(fm).resolve(source: .firefox(profile: "work"), jobOverride: false)
        XCTAssertEqual(got.argument, "firefox:work")
        XCTAssertEqual(got.verdict, .ready(browserKey: "firefox"))
    }

    func test_firefox_namedProfileAbsent_fallsToDefault() {
        let fm = firefoxFM(ini: """
        [Profile0]
        Name=main
        Path=Profiles/main
        Default=1
        """)
        let got = resolver(fm).resolve(source: .firefox(profile: "gone"), jobOverride: false)
        XCTAssertEqual(got.argument, "firefox:main")
    }

    func test_firefox_noProfiles_noProfilesVerdict() {
        let fm = firefoxFM(ini: "[General]\nStartWithLastProfile=1")
        let got = resolver(fm).resolve(source: .firefox(profile: nil), jobOverride: false)
        XCTAssertNil(got.argument)
        XCTAssertEqual(got.verdict, .noProfiles)
    }

    private func firefoxFM(ini: String) -> FakeFileManaging {
        var fm = FakeFileManaging()
        let iniPath = home
            .appendingPathComponent("Library/Application Support/Firefox/profiles.ini").path
        fm.files = [iniPath]
        fm.readable = [iniPath]
        fm.contents = [iniPath: ini]
        return fm
    }
}
```

- [x] **Step 2: Run test to verify it fails**

Run: `xcodebuild ... test -only-testing:GrabberKitTests/CookieResolverResolveTests`
Expected: FAIL — `value of type 'CookieResolver' has no member 'resolve'`.

- [x] **Step 3: Add `resolve(source:jobOverride:)` and helpers to `CookieResolver`**

```swift
    public func resolve(source: CookieSource, jobOverride: Bool) -> CookieResolution {
        switch source {
        case .none:
            return jobOverride ? substitutedResolution() : CookieResolution(
                argument: nil, verdict: .unconfigured
            )
        case .safari:
            return safariResolution()
        case let .firefox(profile):
            return firefoxResolution(requestedName: profile)
        case .chrome, .brave, .edge:
            return CookieResolution(
                argument: source.ytDlpSpec,
                verdict: .ready(browserKey: source.browserKey)
            )
        }
    }

    private func safariResolution() -> CookieResolution {
        safariAccess() == .granted
            ? CookieResolution(argument: "safari", verdict: .ready(browserKey: "safari"))
            : CookieResolution(argument: nil, verdict: .needsFullDiskAccess)
    }

    private func firefoxResolution(requestedName: String?) -> CookieResolution {
        let profiles = firefoxProfiles()
        if let requestedName, profiles.contains(where: { $0.name == requestedName }) {
            return CookieResolution(
                argument: "firefox:\(requestedName)", verdict: .ready(browserKey: "firefox")
            )
        }
        if profiles.isEmpty {
            return CookieResolution(argument: nil, verdict: .noProfiles)
        }
        if let defaultName = profiles.first(where: \.isDefault)?.name {
            return CookieResolution(
                argument: "firefox:\(defaultName)", verdict: .ready(browserKey: "firefox")
            )
        }
        return CookieResolution(argument: "firefox", verdict: .ready(browserKey: "firefox"))
    }

    private func substitutedResolution() -> CookieResolution {
        if safariAccess() == .granted {
            return CookieResolution(argument: "safari", verdict: .ready(browserKey: "safari"))
        }
        for source in [CookieSource.chrome, .brave, .edge, .firefox(profile: nil)]
            where browserSupportDirectoryExists(for: source) {
            return CookieResolution(
                argument: source.ytDlpSpec, verdict: .ready(browserKey: source.browserKey)
            )
        }
        return CookieResolution(argument: nil, verdict: .unconfigured)
    }

    private func browserSupportDirectoryExists(for source: CookieSource) -> Bool {
        let appSupport = home.appendingPathComponent("Library/Application Support")
        let relativePath: String
        switch source {
        case .chrome: relativePath = "Google/Chrome"
        case .brave: relativePath = "BraveSoftware/Brave-Browser"
        case .edge: relativePath = "Microsoft Edge"
        case .firefox: relativePath = "Firefox"
        case .none, .safari: return false
        }
        let dir = appSupport.appendingPathComponent(relativePath)
        return fileManager.fileExists(atPath: dir.path)
            || !fileManager.contentsOfDirectory(at: dir).isEmpty
    }
```

Note: `.firefox(profile: nil).ytDlpSpec` is `"firefox"`; the substitution loop yields `argument: "firefox"` for that case, which is correct (yt-dlp picks Firefox's default profile).

- [x] **Step 4: Run tests to verify they pass**

Run: `xcodebuild ... test -only-testing:GrabberKitTests/CookieResolverResolveTests`
Expected: PASS.

- [x] **Step 5: Run the whole Cookies suite + lint**

Run: `xcodebuild ... test -only-testing:GrabberKitTests/CookieSourceTests -only-testing:GrabberKitTests/FileManagingTests -only-testing:GrabberKitTests/CookieResolverFirefoxTests -only-testing:GrabberKitTests/CookieResolverSafariTests -only-testing:GrabberKitTests/CookieResolverResolveTests`
Then: `mise exec -- swiftformat --lint . && mise exec -- swiftlint lint --strict`
Expected: all PASS, lint clean. `resolve`'s `switch` mixes `case let` with grouped `.chrome, .brave, .edge` — if `cyclomatic_complexity` trips, the helper split above already isolates each arm; move the `.none` branch into its own `noneResolution(jobOverride:)` helper.

---

## Task 6: `CookieHelpURL`

**Files:**
- Create: `apps/media-grabber/Sources/GrabberKit/Cookies/CookieHelpURL.swift`
- Test: `apps/media-grabber/Tests/GrabberKitTests/CookieHelpURLTests.swift`

**Interfaces:**
- Produces: `public enum CookieHelpURL { public static func url(forBrowserKey key: String) -> URL }`

- [x] **Step 1: Write the failing test**

```swift
@testable import GrabberKit
import XCTest

final class CookieHelpURLTests: XCTestCase {
    func test_everyBrowserKey_yieldsAValidURL() {
        for key in ["safari", "chrome", "brave", "edge", "firefox"] {
            let url = CookieHelpURL.url(forBrowserKey: key)
            XCTAssertEqual(url.scheme, "https")
            XCTAssertTrue(url.absoluteString.contains("yt-dlp"))
            XCTAssertTrue(url.absoluteString.contains("#"))
        }
    }
}
```

- [x] **Step 2: Run test to verify it fails**

Run: `xcodebuild ... test -only-testing:GrabberKitTests/CookieHelpURLTests`
Expected: FAIL — `cannot find 'CookieHelpURL' in scope`.

- [x] **Step 3: Write `CookieHelpURL.swift`**

```swift
import Foundation

public enum CookieHelpURL {
    public static func url(forBrowserKey key: String) -> URL {
        URL(string: base + anchor(forBrowserKey: key))!
    }

    private static let base = "https://github.com/yt-dlp/yt-dlp/wiki/FAQ"

    private static func anchor(forBrowserKey _: String) -> String {
        "#how-do-i-pass-cookies-to-yt-dlp"
    }
}
```

- [x] **Step 4: Run tests to verify they pass**

Run: `xcodebuild ... test -only-testing:GrabberKitTests/CookieHelpURLTests`
Expected: PASS.

- [x] **Step 5: Lint**

Run: `mise exec -- swiftformat --lint . && mise exec -- swiftlint lint --strict`
Expected: clean. `swiftlint force_unwrapping` is not in the strict default rule set for a static known-good URL literal; if a project override flags it, wrap in a `guard let ... else { preconditionFailure(...) }`.

---

## Task 7: `Preferences.cookiesFromBrowser`

**Files:**
- Modify: `apps/media-grabber/Sources/GrabberKit/Model/Preferences.swift`
- Test: `apps/media-grabber/Tests/GrabberKitTests/PreferencesTests.swift` (add cases)

**Interfaces:**
- Consumes: `CookieSource` (Task 1).
- Produces: `public var cookiesFromBrowser: CookieSource` (get/set), default `.none`, stored as JSON under `mg.cookiesFromBrowser`, decode failure → `.none`. Key added to `ownedKeys`; `resetToDefaults` clears it.

- [x] **Step 1: Write the failing test**

Add to `PreferencesTests`:

```swift
    func test_cookiesFromBrowser_defaultsToNone() {
        let prefs = Preferences(defaults: UserDefaults(suiteName: UUID().uuidString)!)
        XCTAssertEqual(prefs.cookiesFromBrowser, .none)
    }

    func test_cookiesFromBrowser_roundTripsFirefoxProfile() {
        let suite = UUID().uuidString
        let defaults = UserDefaults(suiteName: suite)!
        Preferences(defaults: defaults).cookiesFromBrowser = .firefox(profile: "work")
        XCTAssertEqual(Preferences(defaults: defaults).cookiesFromBrowser, .firefox(profile: "work"))
    }

    func test_cookiesFromBrowser_malformedJSON_decodesToNone() {
        let defaults = UserDefaults(suiteName: UUID().uuidString)!
        defaults.set("not json", forKey: "mg.cookiesFromBrowser")
        XCTAssertEqual(Preferences(defaults: defaults).cookiesFromBrowser, .none)
    }

    func test_resetToDefaults_clearsCookiesFromBrowser() {
        let defaults = UserDefaults(suiteName: UUID().uuidString)!
        let prefs = Preferences(defaults: defaults)
        prefs.cookiesFromBrowser = .safari
        prefs.resetToDefaults()
        XCTAssertEqual(prefs.cookiesFromBrowser, .none)
    }
```

- [x] **Step 2: Run test to verify it fails**

Run: `xcodebuild ... test -only-testing:GrabberKitTests/PreferencesTests`
Expected: FAIL — `value of type 'Preferences' has no member 'cookiesFromBrowser'`.

- [x] **Step 3: Add the property to `Preferences`**

After the `// MARK: - Network` block (add a `// MARK: - Cookies` section):

```swift
    // MARK: - Cookies

    public var cookiesFromBrowser: CookieSource {
        get {
            guard let data = defaults.data(forKey: "mg.cookiesFromBrowser"),
                  let decoded = try? JSONDecoder().decode(CookieSource.self, from: data)
            else {
                return .none
            }
            return decoded
        }
        set {
            guard let data = try? JSONEncoder().encode(newValue) else {
                defaults.removeObject(forKey: "mg.cookiesFromBrowser")
                return
            }
            defaults.set(data, forKey: "mg.cookiesFromBrowser")
        }
    }
```

Add `"mg.cookiesFromBrowser"` to the `ownedKeys` array.

- [x] **Step 4: Run tests to verify they pass**

Run: `xcodebuild ... test -only-testing:GrabberKitTests/PreferencesTests`
Expected: PASS.

- [x] **Step 5: Lint**

Run: `mise exec -- swiftformat --lint . && mise exec -- swiftlint lint --strict`
Expected: clean.

---

## Task 8: `YtDlpArguments` cookie argument

**Files:**
- Modify: `apps/media-grabber/Sources/GrabberKit/Download/YtDlpArguments.swift`
- Test: `apps/media-grabber/Tests/GrabberKitTests/YtDlpArgumentsTests.swift` (add cases)

**Interfaces:**
- Produces:
  - `public static func build(for:options:tuning:cookieArgument: String? = nil) -> [String]` — emits `["--cookies-from-browser", cookieArgument]` after the resilience flags and before the URL when non-nil
  - `public static func redacted(for:options:tuning:cookieArgument: String? = nil) -> [String]` — same position, emits `["--cookies-from-browser", "<redacted>"]` when non-nil

- [x] **Step 1: Write the failing test**

Add to `YtDlpArgumentsTests`:

```swift
    func test_cookieArgument_emittedBeforeURL() {
        let argv = YtDlpArguments.build(for: Self.req, cookieArgument: "safari")
        let idx = argv.firstIndex(of: "--cookies-from-browser")
        XCTAssertNotNil(idx)
        XCTAssertEqual(argv[idx! + 1], "safari")
        XCTAssertLessThan(idx!, argv.firstIndex(of: Self.req.url)!)
    }

    func test_cookieArgument_nil_omitsBothTokens() {
        let argv = YtDlpArguments.build(for: Self.req, cookieArgument: nil)
        XCTAssertFalse(argv.contains("--cookies-from-browser"))
    }

    func test_redacted_masksCookieSpec() {
        let argv = YtDlpArguments.redacted(for: Self.req, cookieArgument: "firefox:work")
        let idx = argv.firstIndex(of: "--cookies-from-browser")!
        XCTAssertEqual(argv[idx + 1], "<redacted>")
        XCTAssertFalse(argv.contains("firefox:work"))
    }
```

(If `YtDlpArgumentsTests` has no `static let req` / `static var req`, add `private static let req = DownloadRequest(url: "https://archive.org/details/x", destFolder: URL(fileURLWithPath: "/tmp"), kind: .video(maxHeight: 1080), container: "mp4")` — match the existing fixture shape in that file.)

- [x] **Step 2: Run test to verify it fails**

Run: `xcodebuild ... test -only-testing:GrabberKitTests/YtDlpArgumentsTests`
Expected: FAIL — extra argument 'cookieArgument' in call.

- [x] **Step 3: Thread `cookieArgument` through `YtDlpArguments`**

```swift
    public static func build(
        for request: DownloadRequest,
        options: GlobalDownloadOptions = .none,
        tuning: YtDlpTuning = .default,
        cookieArgument: String? = nil
    ) -> [String] {
        baseArgv(for: request, tuning: tuning)
            + cookieFlags(cookieArgument, redact: false)
            + globalFlags(options, proxyURL: options.proxyURL)
            + [request.url]
    }

    public static func redacted(
        for request: DownloadRequest,
        options: GlobalDownloadOptions = .none,
        tuning: YtDlpTuning = .default,
        cookieArgument: String? = nil
    ) -> [String] {
        baseArgv(for: request, tuning: tuning)
            + cookieFlags(cookieArgument, redact: true)
            + globalFlags(options, proxyURL: options.proxyURL.map(maskUserinfo(in:)))
            + [request.url]
    }

    private static func cookieFlags(_ argument: String?, redact: Bool) -> [String] {
        guard let argument else { return [] }
        return ["--cookies-from-browser", redact ? "<redacted>" : argument]
    }
```

- [x] **Step 4: Run tests to verify they pass**

Run: `xcodebuild ... test -only-testing:GrabberKitTests/YtDlpArgumentsTests`
Expected: PASS. (Existing argv-position assertions in that suite still hold — cookie tokens are absent by default.)

- [x] **Step 5: Lint**

Run: `mise exec -- swiftformat --lint . && mise exec -- swiftlint lint --strict`
Expected: clean.

---

## Task 9: `cookieReadFailed` stderr signatures

**Files:**
- Modify: `apps/media-grabber/Sources/GrabberKit/Download/ErrorSignatures.swift`
- Test: `apps/media-grabber/Tests/GrabberKitTests/ErrorSignaturesTests.swift` (add cases)

**Interfaces:**
- Produces: `ErrorSignatures.table` gains a `.cookieReadFailed` entry, **first** in the array. Each of its fragment groups is an AND of substrings on one line. `ErrorSignatures.firstMatch(in:)` returns `.cookieReadFailed` when any group's every fragment is present (case-insensitive).

**Fragment groups (AND within a group, OR across groups):**
- `could not find` + `cookies database`
- `permission denied` + `cookies`
- `failed to decrypt`
- `unable to open database file` + `cookies`
- `could not copy` + `cookie`
- `you must provide at least one` + `cookies`

**Design:** the current `table` is `[(errorClass, substrings: [String])]` with OR semantics inside `substrings`. Add a parallel, AND-group representation only for this row. Simplest fit: give `ErrorSignatures` a separate `cookieReadFailedGroups: [[String]]` constant and check it first in `firstMatch`.

- [x] **Step 1: Write the failing test**

Add to `ErrorSignaturesTests`:

```swift
    func test_cookieReadFailed_eachFragmentGroupClassifies() {
        let lines = [
            "ERROR: could not find chrome cookies database in \"...\"",
            "ERROR: Permission denied while opening Cookies for Safari",
            "ERROR: Failed to decrypt with DPAPI",
            "ERROR: unable to open database file (cookies)",
            "ERROR: could not copy Chrome's cookie database",
            "ERROR: You must provide at least one --cookies or --cookies-from-browser"
        ]
        for line in lines {
            XCTAssertEqual(ErrorSignatures.firstMatch(in: line), .cookieReadFailed, line)
        }
    }

    func test_cookieReadFailed_winsOverPrivate_whenBothPresent() {
        let line = "ERROR: Private video. could not find firefox cookies database"
        XCTAssertEqual(ErrorSignatures.firstMatch(in: line), .cookieReadFailed)
    }

    func test_phase4Signatures_stillClassify() {
        XCTAssertEqual(ErrorSignatures.firstMatch(in: "ERROR: Private video"), .private)
        XCTAssertEqual(ErrorSignatures.firstMatch(in: "This video is age-restricted"), .ageRestricted)
    }
```

- [x] **Step 2: Run test to verify it fails**

Run: `xcodebuild ... test -only-testing:GrabberKitTests/ErrorSignaturesTests`
Expected: FAIL — `firstMatch` returns `nil` / `.private` for the cookie lines.

- [x] **Step 3: Add the AND-group check to `ErrorSignatures`**

```swift
    static let cookieReadFailedGroups: [[String]] = [
        ["could not find", "cookies database"],
        ["permission denied", "cookies"],
        ["failed to decrypt"],
        ["unable to open database file", "cookies"],
        ["could not copy", "cookie"],
        ["you must provide at least one", "cookies"]
    ]

    static func firstMatch(in line: String) -> ErrorClass? {
        let lowered = line.lowercased()
        if cookieReadFailedGroups.contains(where: { group in
            group.allSatisfy { lowered.contains($0) }
        }) {
            return .cookieReadFailed
        }
        return table.first { entry in
            entry.substrings.contains { lowered.contains($0.lowercased()) }
        }?.errorClass
    }
```

- [x] **Step 4: Run tests to verify they pass**

Run: `xcodebuild ... test -only-testing:GrabberKitTests/ErrorSignaturesTests -only-testing:GrabberKitTests/ProgressParserTests`
Expected: PASS.

- [x] **Step 5: Lint**

Run: `mise exec -- swiftformat --lint . && mise exec -- swiftlint lint --strict`
Expected: clean. `firstMatch`'s two-`contains`-closure nesting can trip `closure_body_length` / `cyclomatic_complexity` — if so, extract `private static func matchesCookieReadFailed(_ lowered: String) -> Bool`.

---

## Task 10: `FailurePresentation` widened actions

**Files:**
- Modify: `apps/media-grabber/Sources/GrabberKit/Download/FailurePresentation.swift`
- Test: `apps/media-grabber/Tests/GrabberKitTests/FailurePresentationTests.swift` (add cases)

**Interfaces:**
- Produces: `FailurePresentation.for(_:).offeredActions` —
  - `.cookieReadFailed` → `[.retry, .retryWithCookies]`
  - `.ageRestricted` → `[.retryWithCookies]`
  - `.private` → `[.retryWithCookies]`
  - `.geoBlocked` / `.unavailable` / `.depMissing` → `[]`
- Sentences unchanged for all three.

- [x] **Step 1: Write the failing test**

Add to `FailurePresentationTests`:

```swift
    func test_cookieReadFailed_offersRetryAndRetryWithCookies() {
        XCTAssertEqual(
            ErrorClass.cookieReadFailed.presentation.offeredActions,
            [.retry, .retryWithCookies]
        )
    }

    func test_ageRestricted_and_private_offerRetryWithCookiesOnly() {
        XCTAssertEqual(ErrorClass.ageRestricted.presentation.offeredActions, [.retryWithCookies])
        XCTAssertEqual(ErrorClass.private.presentation.offeredActions, [.retryWithCookies])
    }

    func test_stillActionless_geoBlocked_unavailable_depMissing() {
        XCTAssertEqual(ErrorClass.geoBlocked.presentation.offeredActions, [])
        XCTAssertEqual(ErrorClass.unavailable.presentation.offeredActions, [])
        XCTAssertEqual(ErrorClass.depMissing.presentation.offeredActions, [])
    }

    func test_everyClassHasNonEmptySentence() {
        let classes: [ErrorClass] = [
            .rateLimited(), .botCheck, .sabrGated, .formatsMissing, .cookieReadFailed,
            .geoBlocked, .private, .unavailable, .ageRestricted, .networkDown,
            .diskFull, .permissionDenied, .incomplete, .depMissing, .potProviderDown,
            .unknown(raw: "x")
        ]
        for errorClass in classes {
            XCTAssertFalse(errorClass.presentation.sentence.isEmpty, errorClass.key)
        }
    }
```

- [x] **Step 2: Run test to verify it fails**

Run: `xcodebuild ... test -only-testing:GrabberKitTests/FailurePresentationTests`
Expected: FAIL — `.cookieReadFailed` returns `[.retry]`, `.ageRestricted` returns `[]`.

- [x] **Step 3: Update `FailurePresentation.actions(for:)`**

```swift
    private static let cookieRetryKeys: Set<String> = [
        "cookie_read_failed", "age_restricted", "private"
    ]

    private static func actions(for errorClass: ErrorClass) -> Set<RowAction> {
        var actions: Set<RowAction> = noRetryKeys.contains(errorClass.key) ? [] : [.retry]
        if cookieRetryKeys.contains(errorClass.key) {
            actions.insert(.retryWithCookies)
        }
        return actions
    }
```

`noRetryKeys` currently contains `"private"`, `"age_restricted"` (among others) → those keep `[.retry]` out; `cookieRetryKeys` then adds `.retryWithCookies`. `"cookie_read_failed"` is not in `noRetryKeys` → keeps `.retry` and gains `.retryWithCookies`. Matches the target sets.

- [x] **Step 4: Run tests to verify they pass**

Run: `xcodebuild ... test -only-testing:GrabberKitTests/FailurePresentationTests -only-testing:GrabberKitTests/AvailableActionsTests`
Expected: PASS.

- [x] **Step 5: Add an `AvailableActionsTests` case for the flow-through**

Add to `AvailableActionsTests`:

```swift
    func test_failedCookieReadFailed_includesRetryWithCookies() {
        let actions = DownloadEngine.availableActions(for: .failed(.cookieReadFailed))
        XCTAssertTrue(actions.isSuperset(of: [.retry, .retryWithCookies, .showLog, .remove, .openInBrowser]))
    }

    func test_failedPrivate_hasRetryWithCookies_notRetry() {
        let actions = DownloadEngine.availableActions(for: .failed(.private))
        XCTAssertTrue(actions.contains(.retryWithCookies))
        XCTAssertFalse(actions.contains(.retry))
    }

    func test_failedGeoBlocked_hasNeither() {
        let actions = DownloadEngine.availableActions(for: .failed(.geoBlocked))
        XCTAssertFalse(actions.contains(.retry))
        XCTAssertFalse(actions.contains(.retryWithCookies))
    }
```

- [x] **Step 6: Run + lint**

Run: `xcodebuild ... test -only-testing:GrabberKitTests/FailurePresentationTests -only-testing:GrabberKitTests/AvailableActionsTests`
Then: `mise exec -- swiftformat --lint . && mise exec -- swiftlint lint --strict`
Expected: PASS, clean.

---

## Task 11: `DownloadJob.forceCookies` + persistence round-trip

**Files:**
- Modify: `apps/media-grabber/Sources/GrabberKit/Download/DownloadJob.swift`
- Modify: `apps/media-grabber/Sources/GrabberKit/Model/PersistedJob.swift`
- Modify: `apps/media-grabber/Sources/GrabberKit/Download/DownloadEngine+State.swift`
- Test: `apps/media-grabber/Tests/GrabberKitTests/PersistenceRetryTests.swift` (add cases) or a new `PersistenceCookieTests.swift` if `type_body_length` trips

**Interfaces:**
- Produces:
  - `DownloadJob.var forceCookies: Bool` — default `false`, set in `init` to `false`
  - `PersistedJob.var forceCookies: Bool` — new stored property with `init` default `false`; synthesized `Codable` decodes a missing key... **no** — synthesized `Codable` on a non-optional without a default fails to decode a missing key. Make it `public var forceCookies: Bool = false` in the declaration AND give the memberwise `init` param a default; add an explicit `init(from decoder:)`? No — simplest: declare `public var forceCookies: Bool = false` (a stored property default). Swift's synthesized `Decodable` **does** skip missing keys only for optionals. So use a custom `CodingKeys` + `decodeIfPresent`. See Step 3.
  - `DownloadEngine.persistedJob(from:)` copies `job.forceCookies`; `downloadJob(from:)` copies `persisted.forceCookies`

- [x] **Step 1: Write the failing test**

```swift
@testable import GrabberKit
import XCTest

final class PersistenceCookieTests: XCTestCase {
    func test_forceCookiesTrue_roundTrips() throws {
        let job = PersistedJob(
            id: UUID(),
            request: EngineFixture.request(),
            state: .failed(reason: "cookie_read_failed"),
            addedAt: .now,
            forceCookies: true
        )
        let data = try JSONEncoder().encode(job)
        XCTAssertEqual(try JSONDecoder().decode(PersistedJob.self, from: data).forceCookies, true)
    }

    func test_oldQueueJSON_withoutForceCookies_decodesToFalse() throws {
        let json = """
        {"id":"\(UUID().uuidString)","request":\(Self.requestJSON),
         "state":{"queued":{}},"attempt":0,"addedAt":0}
        """
        // Use the real request-encoding shape from an actual encode:
        let sample = PersistedJob(id: UUID(), request: EngineFixture.request(),
                                  state: .queued, addedAt: .now)
        var dict = try JSONSerialization.jsonObject(
            with: JSONEncoder().encode(sample)
        ) as! [String: Any]
        dict.removeValue(forKey: "forceCookies")
        let stripped = try JSONSerialization.data(withJSONObject: dict)
        XCTAssertEqual(try JSONDecoder().decode(PersistedJob.self, from: stripped).forceCookies, false)
    }
}
```

(Drop the first `requestJSON` sketch — keep only the `test_oldQueueJSON...` approach that encodes a real `PersistedJob`, strips the key, and re-decodes. Adjust `as!` casts to the project's lint tolerance; `PersistenceRetryTests` in the repo already casts `JSONSerialization` output — match its style.)

- [x] **Step 2: Run test to verify it fails**

Run: `xcodebuild ... test -only-testing:GrabberKitTests/PersistenceCookieTests`
Expected: FAIL — `extra argument 'forceCookies'` / missing member.

- [x] **Step 3: Add `forceCookies` to `PersistedJob` with tolerant decode**

```swift
public struct PersistedJob: Codable, Sendable, Equatable {
    public var id: UUID
    public var request: DownloadRequest
    public var title: String?
    public var extractor: String?
    public var durationSeconds: Int?
    public var state: PersistedState
    public var attempt: Int
    public var forceCookies: Bool
    public var playlistGroupID: UUID?
    public var addedAt: Date
    public var finishedAt: Date?

    public init(
        id: UUID,
        request: DownloadRequest,
        title: String? = nil,
        extractor: String? = nil,
        durationSeconds: Int? = nil,
        state: PersistedState,
        attempt: Int = 0,
        forceCookies: Bool = false,
        playlistGroupID: UUID? = nil,
        addedAt: Date,
        finishedAt: Date? = nil
    ) {
        self.id = id
        self.request = request
        self.title = title
        self.extractor = extractor
        self.durationSeconds = durationSeconds
        self.state = state
        self.attempt = attempt
        self.forceCookies = forceCookies
        self.playlistGroupID = playlistGroupID
        self.addedAt = addedAt
        self.finishedAt = finishedAt
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        request = try container.decode(DownloadRequest.self, forKey: .request)
        title = try container.decodeIfPresent(String.self, forKey: .title)
        extractor = try container.decodeIfPresent(String.self, forKey: .extractor)
        durationSeconds = try container.decodeIfPresent(Int.self, forKey: .durationSeconds)
        state = try container.decode(PersistedState.self, forKey: .state)
        attempt = try container.decodeIfPresent(Int.self, forKey: .attempt) ?? 0
        forceCookies = try container.decodeIfPresent(Bool.self, forKey: .forceCookies) ?? false
        playlistGroupID = try container.decodeIfPresent(UUID.self, forKey: .playlistGroupID)
        addedAt = try container.decode(Date.self, forKey: .addedAt)
        finishedAt = try container.decodeIfPresent(Date.self, forKey: .finishedAt)
    }
}
```

(The synthesized encoder is fine — only `init(from:)` needs to be custom. If the type already had a custom `init(from:)` or `CodingKeys`, extend that instead.)

- [x] **Step 4: Add `forceCookies` to `DownloadJob`**

```swift
    var attempt: Int
    var forceCookies: Bool
```

In `init`, after `attempt = 0`: `forceCookies = false`.

- [x] **Step 5: Wire the mappers in `DownloadEngine+State.swift`**

`persistedJob(from:)` — add `forceCookies: job.forceCookies,` after `attempt: job.attempt,`.
`downloadJob(from:)` — add `job.forceCookies = persisted.forceCookies` after `job.attempt = persisted.attempt`.

- [x] **Step 6: Run tests to verify they pass**

Run: `xcodebuild ... test -only-testing:GrabberKitTests/PersistenceCookieTests -only-testing:GrabberKitTests/PersistenceTests -only-testing:GrabberKitTests/PersistenceRetryTests`
Expected: PASS.

- [x] **Step 7: Lint**

Run: `mise exec -- swiftformat --lint . && mise exec -- swiftlint lint --strict`
Expected: clean. `PersistedJob`'s `init(from:)` is long — if `function_body_length` trips (strict default 40 for body), split into `init(from:)` calling a private helper, or accept that `PersistenceRetryTests` shows the pattern is tolerated. If `type_body_length` trips on `PersistedJob.swift`, move `init(from:)` to a `PersistedJob+Codable.swift` extension.

---

## Task 12: `EngineDependencies.fileManager` + spawn-time cookie resolution

**Files:**
- Modify: `apps/media-grabber/Sources/GrabberKit/Download/DownloadEngineProtocol.swift`
- Modify: `apps/media-grabber/Sources/GrabberKit/Download/DownloadEngine.swift`
- Modify: `apps/media-grabber/Sources/GrabberKit/Download/DownloadEngine+Mutations.swift`
- Modify: `apps/media-grabber/Tests/GrabberKitTests/DownloadEngineTestHelpers.swift`
- Test: `apps/media-grabber/Tests/GrabberKitTests/EngineCookieSpawnTests.swift`

**Interfaces:**
- Consumes: `CookieResolver` (Task 5), `FileManaging` (Task 2), `CookieSource` (Task 1), `YtDlpArguments.build(...cookieArgument:)` (Task 8).
- Produces:
  - `EngineDependencies.var fileManager: FileManaging` — new stored property, `init` default `FoundationFileManager()`, `.live(...)` leaves the default
  - `DownloadEngine.launchDownload` resolves `let cookieArgument = CookieResolver(fileManager: dependencies.fileManager).resolve(source: preferences.cookiesFromBrowser, jobOverride: job.forceCookies).argument` in the synchronous setup block, captures it into the launcher `Task`, passes it to `YtDlpArguments.build(...cookieArgument:)` and to `recordExit(...cookiesRequested: cookieArgument != nil)`
  - `recordExit` signature gains `cookiesRequested: Bool` (see Task 13 for the override logic — this task only threads the parameter and passes `false`-equivalent through; **actually** wire the real value here and land the override in Task 13). To keep this task's deliverable testable on its own, land the full `cookiesRequested` plumbing here and assert only the argv; Task 13 adds the `extractedZeroCookies` override.

- [x] **Step 1: Write the failing test**

```swift
@testable import GrabberKit
import TestSupport
import XCTest

@MainActor
final class EngineCookieSpawnTests: XCTestCase {
    private func prefs(_ source: CookieSource) -> Preferences {
        let p = Preferences(defaults: UserDefaults(suiteName: UUID().uuidString)!)
        p.cookiesFromBrowser = source
        return p
    }

    func test_safariGranted_argvCarriesCookiesFromBrowser() async {
        let runner = FakeProcessRunner()
        runner.script(.stdout("done", exitCode: 0), forPathEndingIn: "yt-dlp")
        let safariPath = FileManager.default.homeDirectoryForCurrentUser // unused; see fm below
        var fm = FakeFileManaging()
        let home = URL(fileURLWithPath: "/Users/tester")
        let cookiePath = home.appendingPathComponent(
            "Library/Containers/com.apple.Safari/Data/Library/Cookies/Cookies.binarycookies"
        ).path
        fm.files = [cookiePath]
        fm.readable = [cookiePath]

        let engine = EngineFixture.engine(
            runner: runner,
            probe: FakeMetadataProbe(.success(.init(title: "t", extractor: "e", durationSeconds: 1))),
            preferences: prefs(.safari),
            fileManager: fm,
            resolverHome: home
        )
        let collector = EventCollector(engine)
        let id = await submitJob(engine, EngineFixture.request())
        await expectState(collector, id) { $0.isTerminal }

        let argv = runner.launches.first?.arguments ?? []
        XCTAssertTrue(argv.contains("--cookies-from-browser"))
        XCTAssertEqual(argv[argv.firstIndex(of: "--cookies-from-browser")! + 1], "safari")
    }

    func test_safariDenied_noCookieTokens() async {
        let runner = FakeProcessRunner()
        runner.script(.stdout("done", exitCode: 0), forPathEndingIn: "yt-dlp")
        var fm = FakeFileManaging()
        let home = URL(fileURLWithPath: "/Users/tester")
        fm.files = [home.appendingPathComponent(
            "Library/Containers/com.apple.Safari/Data/Library/Cookies/Cookies.binarycookies"
        ).path]

        let engine = EngineFixture.engine(
            runner: runner,
            probe: FakeMetadataProbe(.success(.init(title: "t", extractor: "e", durationSeconds: 1))),
            preferences: prefs(.safari),
            fileManager: fm,
            resolverHome: home
        )
        let collector = EventCollector(engine)
        let id = await submitJob(engine, EngineFixture.request())
        await expectState(collector, id) { $0.isTerminal }
        XCTAssertFalse((runner.launches.first?.arguments ?? []).contains("--cookies-from-browser"))
    }
}
```

**Adjust to project reality:** `EngineFixture.engine` currently takes no `fileManager` / `resolverHome`. This test drives Step 3's additions. `MediaMetadata`'s initializer and `EventCollector` / `isTerminal` / `waitForState` are from the existing `DownloadEngineTestHelpers` / `EventCollector` — match their real signatures (check `Tests/TestSupport/EventCollector.swift` and existing engine tests for the exact `expectState` predicate helpers; `JobState.isTerminal` may be named differently — use the same poll helper the Phase 4 engine tests use).

- [x] **Step 2: Run test to verify it fails**

Run: `xcodebuild ... test -only-testing:GrabberKitTests/EngineCookieSpawnTests`
Expected: FAIL — `extra arguments 'fileManager', 'resolverHome'` / missing member.

- [x] **Step 3: Add `fileManager` to `EngineDependencies`**

In `DownloadEngineProtocol.swift`, `EngineDependencies`:
- Add stored property `public var fileManager: FileManaging`
- Add `init` param `fileManager: FileManaging = FoundationFileManager()` (place it near `runner`), assign it
- `.live(...)` — no change needed (the default applies)

Also add to the protocol:
```swift
    func retryWithCookies(_ id: UUID) async
```
(Implemented in Task 14; add a `{}` -free real impl there. For this task, add the protocol requirement and a temporary `DownloadEngine` stub is NOT allowed — instead, order Task 14 before wiring the protocol, OR add `retryWithCookies` to the protocol in Task 14. **Decision:** move the protocol line to Task 14. This task touches only `fileManager`.)

- [x] **Step 4: Resolve the cookie argument in `launchDownload`**

In `DownloadEngine.swift`, `launchDownload(id:)`, in the synchronous setup block (alongside `let tuning = ...`):

```swift
        let cookieArgument = CookieResolver(fileManager: dependencies.fileManager)
            .resolve(source: preferences.cookiesFromBrowser, jobOverride: job.forceCookies)
            .argument
```

For test injection of `home`, add an optional stored `cookieResolverHome: URL?` to `EngineDependencies` (default `nil`) and build the resolver as
`CookieResolver(fileManager: dependencies.fileManager, home: dependencies.cookieResolverHome ?? FileManager.default.homeDirectoryForCurrentUser)`.

Inside the launcher `Task`, pass `cookieArgument` to `YtDlpArguments.build`:
```swift
                arguments: YtDlpArguments.build(
                    for: request,
                    options: options,
                    tuning: tuning.ytDlp,
                    cookieArgument: cookieArgument
                )
```

And to `recordExit`:
```swift
            await self?.recordExit(
                id,
                result,
                integrity: integrity,
                lastError: outcome.lastError,
                launchFailed: outcome.launchFailed && result.exitCode == 127,
                cookiesRequested: cookieArgument != nil
            )
```

- [x] **Step 5: Add `cookiesRequested` to `recordExit`**

In `DownloadEngine+Mutations.swift`, add the parameter to `recordExit`'s signature (default it so no other call site breaks — actually there is one call site; give it no default and pass `false` from any test that calls `recordExit` directly, or default `= false`). Use `= false` default. Do not use it yet (Task 13 adds the override) — but reference it once to avoid an "unused parameter" lint: land the override skeleton now:

```swift
    func recordExit(
        _ id: UUID,
        _ result: ProcessResult,
        integrity: IntegrityResult?,
        lastError: ErrorClass?,
        launchFailed: Bool,
        cookiesRequested: Bool = false
    ) {
```

Replace the `classifyExit` line in the failure path:
```swift
        let errorClass = classifiedFailure(
            result: result, lastError: lastError, cookiesRequested: cookiesRequested
        )
```

Add:
```swift
    private func classifiedFailure(
        result: ProcessResult,
        lastError: ErrorClass?,
        cookiesRequested: Bool
    ) -> ErrorClass {
        classifyExit(result: result, lastError: lastError)
    }
```

(Task 13 fills `classifiedFailure` with the `extractedZeroCookies` check. Splitting it out now keeps Task 13 a one-function change.)

- [x] **Step 6: Update `EngineFixture.engine`**

```swift
    static func engine(
        runner: FakeProcessRunner,
        probe: FakeMetadataProbe,
        cap: Int = 3,
        preferences: Preferences? = nil,
        fileManager: FileManaging = FoundationFileManager(),
        resolverHome: URL? = nil
    ) -> DownloadEngine {
        DownloadEngine(
            dependencies: EngineDependencies(
                runner: runner,
                fileManager: fileManager,
                probe: probe,
                envProbe: FakeEnvironmentProbe(.with(ytDlp: true, ffmpeg: true)),
                ytDlpURL: ytDlp,
                jobLogDir: scratchLogDir(),
                debugFlags: EngineDebugFlags(concurrencyCapOverride: cap),
                cookieResolverHome: resolverHome
            ),
            preferences: preferences
                ?? Preferences(defaults: UserDefaults(suiteName: UUID().uuidString)!)
        )
    }
```

(Match the real `EngineDependencies.init` parameter order after your Step 3 edit.)

- [x] **Step 7: Run tests to verify they pass**

Run: `xcodebuild ... test -only-testing:GrabberKitTests/EngineCookieSpawnTests -only-testing:GrabberKitTests/DownloadEngineTests -only-testing:GrabberKitTests/DownloadEngineSchedulerTests`
Expected: PASS. Fix any fixture in other engine suites that constructed `EngineDependencies` positionally (search `EngineDependencies(` across `Tests/`).

- [x] **Step 8: Lint**

Run: `mise exec -- swiftformat --lint . && mise exec -- swiftlint lint --strict`
Expected: clean.

---

## Task 13: The `Extracted 0 cookies` override

**Files:**
- Modify: `apps/media-grabber/Sources/GrabberKit/Download/DownloadEngine.swift` (`DownloadDrainOutcome`, `drainDownload`)
- Modify: `apps/media-grabber/Sources/GrabberKit/Download/DownloadEngine+Mutations.swift` (`classifiedFailure`, `recordExit` signature threading `outcome`)
- Test: `apps/media-grabber/Tests/GrabberKitTests/EngineZeroCookiesTests.swift`

**Interfaces:**
- Consumes: `cookiesRequested: Bool` (Task 12), `DownloadDrainOutcome` (private struct in `DownloadEngine.swift`).
- Produces:
  - `DownloadDrainOutcome.var extractedZeroCookies = false` — set `true` in `drainDownload` when any drained line (stdout or stderr) contains `"Extracted 0 cookies"`
  - `recordExit` gains `extractedZeroCookies: Bool` (passed from `outcome.extractedZeroCookies` in the launcher). When `result.exitCode != 0 && cookiesRequested && extractedZeroCookies` → the classified error class is forced to `.cookieReadFailed`, bypassing `classifyExit`. This runs before the `isAutoRetryable` check, so the job goes straight to `.failed(.cookieReadFailed)` (not auto-retryable → no backoff).
  - An `Extracted 0 cookies` line on an **exit-0** run is ignored (the download completed).

- [x] **Step 1: Write the failing test**

```swift
@testable import GrabberKit
import TestSupport
import XCTest

@MainActor
final class EngineZeroCookiesTests: XCTestCase {
    private func cookiePrefs() -> Preferences {
        let p = Preferences(defaults: UserDefaults(suiteName: UUID().uuidString)!)
        p.cookiesFromBrowser = .chrome
        return p
    }

    private func chromeFM() -> (FakeFileManaging, URL) {
        var fm = FakeFileManaging()
        let home = URL(fileURLWithPath: "/Users/tester")
        fm.dirs = [home.appendingPathComponent("Library/Application Support/Google/Chrome").path:
            [home.appendingPathComponent("x")]]
        return (fm, home)
    }

    func test_zeroCookiesLine_plusNonZeroExit_withCookieArg_classifiesCookieReadFailed() async {
        let runner = FakeProcessRunner()
        runner.script(
            Script(lines: [.stderr("WARNING: Extracted 0 cookies from chrome"),
                           .stderr("ERROR: Sign in to confirm you're not a bot")],
                   exitCode: 1),
            forPathEndingIn: "yt-dlp"
        )
        let (fm, home) = chromeFM()
        let engine = EngineFixture.engine(
            runner: runner,
            probe: FakeMetadataProbe(.success(.init(title: "t", extractor: "e", durationSeconds: 1))),
            preferences: cookiePrefs(), fileManager: fm, resolverHome: home
        )
        let collector = EventCollector(engine)
        let id = await submitJob(engine, EngineFixture.request())
        await expectState(collector, id) { state in
            if case .failed(.cookieReadFailed) = state { return true }
            return false
        }
        let job = await engine.currentSnapshot().jobs.first { $0.id == id }
        XCTAssertEqual(job?.attempt, 0)
    }

    func test_zeroCookiesLine_withoutCookieArg_usesNormalClassification() async {
        let runner = FakeProcessRunner()
        runner.script(
            Script(lines: [.stderr("WARNING: Extracted 0 cookies"),
                           .stderr("ERROR: Private video")],
                   exitCode: 1),
            forPathEndingIn: "yt-dlp"
        )
        let engine = EngineFixture.engine(
            runner: runner,
            probe: FakeMetadataProbe(.success(.init(title: "t", extractor: "e", durationSeconds: 1)))
        )
        let collector = EventCollector(engine)
        let id = await submitJob(engine, EngineFixture.request())
        await expectState(collector, id) { state in
            if case .failed(.private) = state { return true }
            return false
        }
    }

    func test_zeroCookiesLine_onExitZero_completes() async {
        let runner = FakeProcessRunner()
        runner.script(
            Script(lines: [.stderr("WARNING: Extracted 0 cookies"),
                           .stdout("[download] 100%")],
                   exitCode: 0),
            forPathEndingIn: "yt-dlp"
        )
        let (fm, home) = chromeFM()
        let engine = EngineFixture.engine(
            runner: runner,
            probe: FakeMetadataProbe(.success(.init(title: "t", extractor: "e", durationSeconds: 1))),
            preferences: cookiePrefs(), fileManager: fm, resolverHome: home
        )
        let collector = EventCollector(engine)
        let id = await submitJob(engine, EngineFixture.request())
        await expectState(collector, id) { $0 == .completed }
    }
}
```

(`Script` is `FakeProcessRunner.Script`; `.init` for `MediaMetadata` — match the real type. `EngineFixture.completingScript` builds a passing script — reuse where it fits.)

- [x] **Step 2: Run test to verify it fails**

Run: `xcodebuild ... test -only-testing:GrabberKitTests/EngineZeroCookiesTests`
Expected: FAIL — first test classifies `.botCheck` or `.unknown`, not `.cookieReadFailed`.

- [x] **Step 3: Add `extractedZeroCookies` to `DownloadDrainOutcome` + `drainDownload`**

In `DownloadEngine.swift`:

```swift
    private struct DownloadDrainOutcome {
        var lastError: ErrorClass?
        var launchFailed = false
        var extractedZeroCookies = false
    }
```

In `drainDownload`, after `jobLog.append(line)` (works for both stdout/stderr — factor the text out first; the function already binds `text` per branch, so add after the `switch`):

```swift
            if text.contains("Extracted 0 cookies") {
                outcome.extractedZeroCookies = true
            }
```

- [x] **Step 4: Thread `extractedZeroCookies` into `recordExit`**

Launcher `Task` call:
```swift
            await self?.recordExit(
                id, result,
                integrity: integrity,
                lastError: outcome.lastError,
                launchFailed: outcome.launchFailed && result.exitCode == 127,
                cookiesRequested: cookieArgument != nil,
                extractedZeroCookies: outcome.extractedZeroCookies
            )
```

`recordExit` signature (`DownloadEngine+Mutations.swift`):
```swift
    func recordExit(
        _ id: UUID,
        _ result: ProcessResult,
        integrity: IntegrityResult?,
        lastError: ErrorClass?,
        launchFailed: Bool,
        cookiesRequested: Bool = false,
        extractedZeroCookies: Bool = false
    ) {
```

Fill `classifiedFailure`:
```swift
    private func classifiedFailure(
        result: ProcessResult,
        lastError: ErrorClass?,
        cookiesRequested: Bool,
        extractedZeroCookies: Bool
    ) -> ErrorClass {
        if result.exitCode != 0, cookiesRequested, extractedZeroCookies {
            return .cookieReadFailed
        }
        return classifyExit(result: result, lastError: lastError)
    }
```

Update its one call site in `recordExit` to pass `extractedZeroCookies`.

- [x] **Step 5: Run tests to verify they pass**

Run: `xcodebuild ... test -only-testing:GrabberKitTests/EngineZeroCookiesTests -only-testing:GrabberKitTests/DownloadEngineTests`
Expected: PASS.

- [x] **Step 6: Lint**

Run: `mise exec -- swiftformat --lint . && mise exec -- swiftlint lint --strict`
Expected: clean. `recordExit` is now a longer function — if `function_body_length` trips, the `classifiedFailure` extraction already helps; move the exit-0 integrity block into a `private func handleSuccessfulExit(...)` helper if needed.

---

## Task 14: `engine.retryWithCookies(_:)`

**Files:**
- Modify: `apps/media-grabber/Sources/GrabberKit/Download/DownloadEngine+Retry.swift`
- Modify: `apps/media-grabber/Sources/GrabberKit/Download/DownloadEngineProtocol.swift` (protocol requirement)
- Modify: `apps/media-grabber/Tests/AppUnitTests/Support/AppFakes.swift` (`FakeEngine`)
- Modify: `apps/media-grabber/Tests/GrabberKitTests/QuitCoordinatorTests.swift` (private `FakeEngine`)
- Test: `apps/media-grabber/Tests/GrabberKitTests/EngineRetryWithCookiesTests.swift`

**Interfaces:**
- Consumes: `FailurePresentation.offeredActions` (Task 10), `job.forceCookies` (Task 11), `RowAction.retryWithCookies`.
- Produces:
  - `public func retryWithCookies(_ id: UUID) async` on `DownloadEngine` — guard: job exists, `case let .failed(errorClass) = job.state`, `errorClass.presentation.offeredActions.contains(.retryWithCookies)`. Sets `job.forceCookies = true`, `job.attempt = 0`, resets `state`/`finishedAt`/`progress`/`sizeBytes`/`integrityVerdict`/`actualQuality` (same fields as `retry`'s from-scratch branch), `deletePartFiles`, `move(job, toTail: true)`, `logEvent(.jobRetried(id:))`, `bump()` / `emitSnapshot()` / `evaluateSchedule()`. Always from-scratch, never resume. `forceCookies` stays set for the job's life.
  - `DownloadEngineProtocol` gains `func retryWithCookies(_ id: UUID) async`

- [x] **Step 1: Write the failing test**

```swift
@testable import GrabberKit
import TestSupport
import XCTest

@MainActor
final class EngineRetryWithCookiesTests: XCTestCase {
    private func failedEngine(
        _ errorClass: ErrorClass,
        script: FakeProcessRunner.Script
    ) async -> (DownloadEngine, UUID, FakeProcessRunner) {
        let runner = FakeProcessRunner()
        runner.script(script, forPathEndingIn: "yt-dlp")
        let engine = EngineFixture.engine(
            runner: runner,
            probe: FakeMetadataProbe(.success(.init(title: "t", extractor: "e", durationSeconds: 1)))
        )
        let collector = EventCollector(engine)
        let id = await submitJob(engine, EngineFixture.request())
        await expectState(collector, id) { state in
            if case .failed = state { return true }
            return false
        }
        return (engine, id, runner)
    }

    func test_cookieReadFailed_job_retriesFromScratch_setsForceCookies() async {
        let (engine, id, _) = await failedEngine(
            .cookieReadFailed,
            script: Script(lines: [.stderr("ERROR: could not find chrome cookies database")], exitCode: 1)
        )
        await engine.retryWithCookies(id)
        let job = await engine.currentSnapshot().jobs.first { $0.id == id }
        XCTAssertEqual(job?.attempt, 0)
        XCTAssertNotEqual(job?.state, nil)
        // forceCookies is engine-internal; assert via the next spawn's argv instead:
    }

    func test_geoBlocked_job_isNoOp() async {
        let (engine, id, _) = await failedEngine(
            .geoBlocked,
            script: Script(lines: [.stderr("ERROR: This video is not available in your country")], exitCode: 1)
        )
        let before = await engine.currentSnapshot().jobs.first { $0.id == id }?.state
        await engine.retryWithCookies(id)
        let after = await engine.currentSnapshot().jobs.first { $0.id == id }?.state
        XCTAssertEqual(before, after)
    }

    func test_completedJob_isNoOp() async {
        let runner = FakeProcessRunner()
        runner.script(.stdout("done", exitCode: 0), forPathEndingIn: "yt-dlp")
        let engine = EngineFixture.engine(
            runner: runner,
            probe: FakeMetadataProbe(.success(.init(title: "t", extractor: "e", durationSeconds: 1)))
        )
        let collector = EventCollector(engine)
        let id = await submitJob(engine, EngineFixture.request())
        await expectState(collector, id) { $0 == .completed }
        await engine.retryWithCookies(id)
        let job = await engine.currentSnapshot().jobs.first { $0.id == id }
        XCTAssertEqual(job?.state, .completed)
    }

    func test_afterRetryWithCookies_noStandingDefault_nextSpawnCarriesCookieArg() async {
        // preferences.cookiesFromBrowser == .none, but a fake FS reports Safari readable
        let runner = FakeProcessRunner()
        runner.script(
            Script(lines: [.stderr("ERROR: could not find safari cookies database")], exitCode: 1),
            forPathEndingIn: "yt-dlp"
        )
        var fm = FakeFileManaging()
        let home = URL(fileURLWithPath: "/Users/tester")
        let cookiePath = home.appendingPathComponent(
            "Library/Containers/com.apple.Safari/Data/Library/Cookies/Cookies.binarycookies"
        ).path
        fm.files = [cookiePath]; fm.readable = [cookiePath]
        let engine = EngineFixture.engine(
            runner: runner,
            probe: FakeMetadataProbe(.success(.init(title: "t", extractor: "e", durationSeconds: 1))),
            fileManager: fm, resolverHome: home
        )
        let collector = EventCollector(engine)
        let id = await submitJob(engine, EngineFixture.request())
        await expectState(collector, id) { state in
            if case .failed = state { return true }
            return false
        }
        await engine.retryWithCookies(id)
        await expectState(collector, id) { state in
            if case .failed = state { return true }
            return false
        }
        XCTAssertTrue(runner.launches.count >= 2)
        XCTAssertTrue((runner.launches.last?.arguments ?? []).contains("--cookies-from-browser"))
    }
}
```

- [x] **Step 2: Run test to verify it fails**

Run: `xcodebuild ... test -only-testing:GrabberKitTests/EngineRetryWithCookiesTests`
Expected: FAIL — `value of type 'DownloadEngine' has no member 'retryWithCookies'`.

- [x] **Step 3: Implement `retryWithCookies` in `DownloadEngine+Retry.swift`**

```swift
    public func retryWithCookies(_ id: UUID) async {
        guard let job = jobs.first(where: { $0.id == id }),
              case let .failed(errorClass) = job.state,
              errorClass.presentation.offeredActions.contains(.retryWithCookies)
        else {
            return
        }

        job.forceCookies = true
        job.attempt = 0
        job.state = .queued
        job.finishedAt = nil
        job.progress = nil
        job.sizeBytes = nil
        job.integrityVerdict = nil
        job.actualQuality = nil
        deletePartFiles(for: job)
        move(job, toTail: true)
        logEvent(.jobRetried(id: id))

        bump()
        emitSnapshot()
        evaluateSchedule()
    }
```

- [x] **Step 4: Add the protocol requirement**

`DownloadEngineProtocol.swift`, after `func retry(_ id: UUID) async`:
```swift
    func retryWithCookies(_ id: UUID) async
```

- [x] **Step 5: Update the two `FakeEngine` conformers**

`Tests/AppUnitTests/Support/AppFakes.swift` — add to `State`: `var retriedWithCookies: [UUID] = []`; add accessor `var retriedWithCookiesIDs: [UUID] { box.read { $0.retriedWithCookies } }`; add method:
```swift
    func retryWithCookies(_ jobID: UUID) async {
        box.mutate { $0.retriedWithCookies.append(jobID) }
    }
```

`Tests/GrabberKitTests/QuitCoordinatorTests.swift` — its private `FakeEngine`: add `func retryWithCookies(_: UUID) async {}`.

- [x] **Step 6: Run tests to verify they pass**

Run: `xcodebuild ... test -only-testing:GrabberKitTests/EngineRetryWithCookiesTests -only-testing:GrabberKitTests/QuitCoordinatorTests -only-testing:GrabberKitTests/EngineRetryTests -only-testing:GrabberKitTests/EngineRetryIntentTests`
Expected: PASS.

- [x] **Step 7: Lint**

Run: `mise exec -- swiftformat --lint . && mise exec -- swiftlint lint --strict`
Expected: clean. `DownloadEngine+Retry.swift` gains a second ~20-line function — if `type_body_length` on the extension trips, that's unlikely for an extension file; if `file_length` trips, split `retryWithCookies` into `DownloadEngine+RetryWithCookies.swift`.

---

## Task 15: `AppModel` — `retryWithCookies` row action + pending-retry handoff

**Files:**
- Modify: `apps/media-grabber/Sources/App/AppModel.swift`
- Modify: `apps/media-grabber/Sources/App/AppModelRowActions.swift`
- Test: `apps/media-grabber/Tests/AppUnitTests/AppModelRowActionTests.swift` (add cases) or a new `AppModelCookieRetryTests.swift`

**Interfaces:**
- Consumes: `engine.retryWithCookies(_:)` (Task 14), `prefs.cookiesFromBrowser` (Task 7), `AppModel.Page.preferences(.cookies)`.
- Produces:
  - `AppModel.private(set) var pendingCookieRetryJobID: UUID?`
  - `AppModel.func resolveCookieRetry() async` — `guard let id = pendingCookieRetryJobID else { return }; pendingCookieRetryJobID = nil; await engine.retryWithCookies(id)`
  - `AppModel.page` `didSet` — when the new value is not `.preferences(.cookies)` and `pendingCookieRetryJobID != nil`, set `pendingCookieRetryJobID = nil`
  - `handleRowAction(_:action:)` `.retryWithCookies` case:
    ```swift
    case .retryWithCookies:
        if prefs.cookiesFromBrowser.isNone {
            pendingCookieRetryJobID = id
            page = .preferences(.cookies)
        } else {
            await engine.retryWithCookies(id)
        }
    ```

- [x] **Step 1: Write the failing test**

```swift
@testable import GrabberKit
@testable import MediaGrabber
import XCTest

@MainActor
final class AppModelCookieRetryTests: XCTestCase {
    private func model(cookieSource: CookieSource) -> (AppModel, FakeEngine) {
        let engine = FakeEngine()
        let prefs = Preferences(defaults: UserDefaults(suiteName: UUID().uuidString)!)
        prefs.cookiesFromBrowser = cookieSource
        let model = AppModel.testInstance(engine: engine, prefs: prefs) // match existing helper
        return (model, engine)
    }

    func test_noBrowser_setsPendingAndOpensPane() async {
        let (model, engine) = model(cookieSource: .none)
        let id = UUID()
        await model.handleRowAction(id, action: .retryWithCookies)
        XCTAssertEqual(model.pendingCookieRetryJobID, id)
        XCTAssertEqual(model.page, .preferences(.cookies))
        XCTAssertTrue(engine.retriedWithCookiesIDs.isEmpty)
    }

    func test_browserSet_callsEngineNoPageChange() async {
        let (model, engine) = model(cookieSource: .safari)
        let id = UUID()
        await model.handleRowAction(id, action: .retryWithCookies)
        XCTAssertEqual(engine.retriedWithCookiesIDs, [id])
        XCTAssertEqual(model.page, .home)
    }

    func test_resolveCookieRetry_firesAndClears() async {
        let (model, engine) = model(cookieSource: .none)
        let id = UUID()
        await model.handleRowAction(id, action: .retryWithCookies)
        await model.resolveCookieRetry()
        XCTAssertEqual(engine.retriedWithCookiesIDs, [id])
        XCTAssertNil(model.pendingCookieRetryJobID)
    }

    func test_resolveCookieRetry_noPending_isNoOp() async {
        let (model, engine) = model(cookieSource: .none)
        await model.resolveCookieRetry()
        XCTAssertTrue(engine.retriedWithCookiesIDs.isEmpty)
    }

    func test_pageChangeAwayFromCookies_clearsPending() async {
        let (model, engine) = model(cookieSource: .none)
        let id = UUID()
        await model.handleRowAction(id, action: .retryWithCookies)
        model.page = .home
        XCTAssertNil(model.pendingCookieRetryJobID)
        XCTAssertTrue(engine.retriedWithCookiesIDs.isEmpty)
    }
}
```

(`AppModel.testInstance` / the existing construction helper — check `Tests/AppUnitTests/Support/AppModelTestHelpers.swift` for the real factory; match its signature. If it takes no `prefs`, set `model.prefs.cookiesFromBrowser` after construction — `prefs` is a `let` but `Preferences` is a reference type, so mutate through it.)

- [x] **Step 2: Run test to verify it fails**

Run: `xcodebuild ... test -only-testing:AppUnitTests/AppModelCookieRetryTests`
Expected: FAIL — `value of type 'AppModel' has no member 'pendingCookieRetryJobID'`.

- [x] **Step 3: Add the state + method to `AppModel`**

```swift
    private(set) var pendingCookieRetryJobID: UUID?
```

Change `var page: Page = .home` to add a `didSet`:
```swift
    var page: Page = .home {
        didSet {
            if page != .preferences(.cookies), pendingCookieRetryJobID != nil {
                pendingCookieRetryJobID = nil
            }
        }
    }
```

```swift
    func resolveCookieRetry() async {
        guard let id = pendingCookieRetryJobID else { return }
        pendingCookieRetryJobID = nil
        await engine.retryWithCookies(id)
    }
```

- [x] **Step 4: Fill the row-action case in `AppModelRowActions.swift`**

```swift
        case .retryWithCookies:
            if prefs.cookiesFromBrowser.isNone {
                pendingCookieRetryJobID = id
                page = .preferences(.cookies)
            } else {
                await engine.retryWithCookies(id)
            }
```

`pendingCookieRetryJobID` is `private(set)` — the setter must be reachable from the `AppModel` extension in `AppModelRowActions.swift` (same module, same type → `private(set)` allows it). If Swift rejects the cross-file `private(set)` write from an extension, change to `internal(set)` or `fileprivate(set)` won't span files — use a plain `private(set)` and add a `func setPendingCookieRetry(_ id: UUID?)` on `AppModel` if the compiler complains. (In practice `private(set)` is writable from any extension of the same type in the same module.)

- [x] **Step 5: Run tests to verify they pass**

Run: `xcodebuild ... test -only-testing:AppUnitTests/AppModelCookieRetryTests -only-testing:AppUnitTests/AppModelRowActionTests -only-testing:AppUnitTests/AppModelTests`
Expected: PASS.

- [x] **Step 6: Lint**

Run: `mise exec -- swiftformat --lint . && mise exec -- swiftlint lint --strict`
Expected: clean.

---

## Task 16: `SettingsLinkOpening` + `CookiePaneModel`

**Files:**
- Create: `apps/media-grabber/Sources/App/Preferences/SettingsLinkOpening.swift`
- Create: `apps/media-grabber/Sources/App/Preferences/CookiePaneModel.swift`
- Test: `apps/media-grabber/Tests/AppUnitTests/CookiePaneModelTests.swift`

**Interfaces:**
- Consumes: `CookieResolver` (Task 5), `CookieSource` (Task 1), `FirefoxProfile`, `SafariCookieAccess`, `CookieHelpURL` (Task 6), `OpenURLSink` (existing in `AppModel.swift`), `Preferences.cookiesFromBrowser` (Task 7).
- Produces:
  - `@MainActor protocol SettingsLinkOpening { func open(_ url: URL) }` + `struct WorkspaceSettingsLink: SettingsLinkOpening`
  - `@MainActor @Observable final class CookiePaneModel` with:
    - `init(prefs: Preferences, resolver: CookieResolver = CookieResolver(), settingsLink: SettingsLinkOpening = WorkspaceSettingsLink(), openURL: OpenURLSink = WorkspaceOpenURLSink())`
    - `var source: CookieSource { get set }` — get/set `prefs.cookiesFromBrowser`; `set` calls `refresh()`
    - `private(set) var firefoxProfiles: [FirefoxProfile]`
    - `private(set) var safariAccess: SafariCookieAccess`
    - `var selectedFirefoxProfile: String?` — get/set the `.firefox(profile:)` associated value on `source`
    - `func onAppear()` → `refresh()`
    - `func openFullDiskAccessSettings()` → `settingsLink.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_AllFiles")!)`
    - `func openHelp()` → `openURL.open(CookieHelpURL.url(forBrowserKey: source.browserKey))`
    - computed visibility flags: `var showsFirefoxProfilePicker: Bool` (`source is .firefox` && `firefoxProfiles.count >= 2`), `var showsFirefoxNoProfilesNote: Bool` (`source is .firefox` && `firefoxProfiles.isEmpty`), `var showsFullDiskAccessRow: Bool` (`source == .safari` && `safariAccess != .noContainer`), `var showsLearnMore: Bool` (`!source.isNone`), `var showsTip: Bool` (`!source.isNone`)
    - `private func refresh()` — `firefoxProfiles = resolver.firefoxProfiles()`; `safariAccess = resolver.safariAccess()`; if `source` is `.firefox(name)` with `name` non-nil and not in `firefoxProfiles.map(\.name)` → set `source = .firefox(profile: nil)`

- [x] **Step 1: Write the failing test**

```swift
@testable import GrabberKit
@testable import MediaGrabber
import XCTest

@MainActor
final class CookiePaneModelTests: XCTestCase {
    private func prefs(_ source: CookieSource) -> Preferences {
        let p = Preferences(defaults: UserDefaults(suiteName: UUID().uuidString)!)
        p.cookiesFromBrowser = source
        return p
    }

    private func resolver(profiles: [FirefoxProfile], safari: SafariCookieAccess) -> CookieResolver {
        // A CookieResolver over a FakeFileManaging scripted to yield exactly these.
        // Build the profiles.ini text + Safari file flags to match `profiles` / `safari`.
        var fm = FakeFileManaging()
        let home = URL(fileURLWithPath: "/Users/tester")
        if !profiles.isEmpty {
            let iniPath = home.appendingPathComponent(
                "Library/Application Support/Firefox/profiles.ini").path
            fm.files.insert(iniPath); fm.readable.insert(iniPath)
            fm.contents[iniPath] = profiles.enumerated().map { i, p in
                "[Profile\(i)]\nName=\(p.name)\nIsRelative=0\nPath=\(p.path)\(p.isDefault ? "\nDefault=1" : "")"
            }.joined(separator: "\n\n")
        }
        let cookiePath = home.appendingPathComponent(
            "Library/Containers/com.apple.Safari/Data/Library/Cookies/Cookies.binarycookies").path
        switch safari {
        case .granted: fm.files.insert(cookiePath); fm.readable.insert(cookiePath)
        case .denied: fm.files.insert(cookiePath)
        case .noContainer: break
        }
        return CookieResolver(fileManager: fm, home: home)
    }

    func test_refresh_populatesProfilesAndSafariAccess() {
        let ffProfiles = [
            FirefoxProfile(name: "a", path: "/p/a", isDefault: true),
            FirefoxProfile(name: "b", path: "/p/b", isDefault: false)
        ]
        let model = CookiePaneModel(
            prefs: prefs(.firefox(profile: "a")),
            resolver: resolver(profiles: ffProfiles, safari: .denied)
        )
        model.onAppear()
        XCTAssertEqual(model.firefoxProfiles.count, 2)
        XCTAssertEqual(model.safariAccess, .denied)
        XCTAssertTrue(model.showsFirefoxProfilePicker)
    }

    func test_refresh_rewritesStaleFirefoxProfile() {
        let model = CookiePaneModel(
            prefs: prefs(.firefox(profile: "stale")),
            resolver: resolver(
                profiles: [FirefoxProfile(name: "real", path: "/p/real", isDefault: true)],
                safari: .noContainer
            )
        )
        model.onAppear()
        XCTAssertEqual(model.source, .firefox(profile: nil))
    }

    func test_fdaRow_visibleOnlyForSafariWithContainer() {
        let safariModel = CookiePaneModel(
            prefs: prefs(.safari), resolver: resolver(profiles: [], safari: .denied))
        safariModel.onAppear()
        XCTAssertTrue(safariModel.showsFullDiskAccessRow)

        let noContainerModel = CookiePaneModel(
            prefs: prefs(.safari), resolver: resolver(profiles: [], safari: .noContainer))
        noContainerModel.onAppear()
        XCTAssertFalse(noContainerModel.showsFullDiskAccessRow)
    }

    func test_openFullDiskAccessSettings_callsSink() {
        let link = FakeSettingsLink()
        let model = CookiePaneModel(
            prefs: prefs(.safari),
            resolver: resolver(profiles: [], safari: .denied),
            settingsLink: link
        )
        model.openFullDiskAccessSettings()
        XCTAssertEqual(link.opened.first?.scheme, "x-apple.systempreferences")
    }

    func test_openHelp_callsOpenURLSinkWithBrowserKeyURL() {
        let sink = FakeOpenURLSink()
        let model = CookiePaneModel(
            prefs: prefs(.chrome),
            resolver: resolver(profiles: [], safari: .noContainer),
            openURL: sink
        )
        model.openHelp()
        XCTAssertEqual(sink.opened.first, CookieHelpURL.url(forBrowserKey: "chrome"))
    }

    func test_learnMoreAndTip_hiddenForNone_shownForBrowser() {
        let none = CookiePaneModel(prefs: prefs(.none),
                                   resolver: resolver(profiles: [], safari: .noContainer))
        XCTAssertFalse(none.showsLearnMore)
        XCTAssertFalse(none.showsTip)
        let chrome = CookiePaneModel(prefs: prefs(.chrome),
                                     resolver: resolver(profiles: [], safari: .noContainer))
        XCTAssertTrue(chrome.showsLearnMore)
        XCTAssertTrue(chrome.showsTip)
    }
}

@MainActor
final class FakeSettingsLink: SettingsLinkOpening {
    private(set) var opened: [URL] = []
    nonisolated init() {}
    func open(_ url: URL) { opened.append(url) }
}
```

(`FakeFileManaging` lives in `GrabberKitTests/Support` — either move it to a shared `TestSupport` target so `AppUnitTests` can use it, or add a small App-side copy. **Recommendation:** move `FakeFileManaging.swift` to `Tests/TestSupport/` in Task 3 instead of `GrabberKitTests/Support/` — it is `@testable import GrabberKit` and `TestSupport` already `@testable`-imports `GrabberKit`. Do that move now if not done: `mv Tests/GrabberKitTests/Support/FakeFileManaging.swift Tests/TestSupport/FakeFileManaging.swift`, drop `@testable import GrabberKit` → `import GrabberKit` if the protocol is `public` (it is), then `mise exec -- tuist generate --no-open`.)

- [x] **Step 2: Run test to verify it fails**

Run: `xcodebuild ... test -only-testing:AppUnitTests/CookiePaneModelTests`
Expected: FAIL — `cannot find 'CookiePaneModel' in scope`.

- [x] **Step 3: Write `SettingsLinkOpening.swift`**

```swift
import Foundation

#if canImport(AppKit)
    import AppKit
#endif

@MainActor
protocol SettingsLinkOpening {
    func open(_ url: URL)
}

struct WorkspaceSettingsLink: SettingsLinkOpening {
    func open(_ url: URL) {
        #if canImport(AppKit)
            NSWorkspace.shared.open(url)
        #endif
    }
}
```

- [x] **Step 4: Write `CookiePaneModel.swift`**

```swift
import GrabberKit
import Observation

@MainActor
@Observable
final class CookiePaneModel {
    private let prefs: Preferences
    private let resolver: CookieResolver
    private let settingsLink: SettingsLinkOpening
    private let openURL: OpenURLSink

    private(set) var firefoxProfiles: [FirefoxProfile] = []
    private(set) var safariAccess: SafariCookieAccess = .noContainer

    init(
        prefs: Preferences,
        resolver: CookieResolver = CookieResolver(),
        settingsLink: SettingsLinkOpening = WorkspaceSettingsLink(),
        openURL: OpenURLSink = WorkspaceOpenURLSink()
    ) {
        self.prefs = prefs
        self.resolver = resolver
        self.settingsLink = settingsLink
        self.openURL = openURL
    }

    var source: CookieSource {
        get { prefs.cookiesFromBrowser }
        set {
            prefs.cookiesFromBrowser = newValue
            refresh()
        }
    }

    var selectedFirefoxProfile: String? {
        get {
            if case let .firefox(profile) = source { return profile }
            return nil
        }
        set { source = .firefox(profile: newValue) }
    }

    var showsFirefoxProfilePicker: Bool { isFirefox && firefoxProfiles.count >= 2 }
    var showsFirefoxNoProfilesNote: Bool { isFirefox && firefoxProfiles.isEmpty }
    var showsFullDiskAccessRow: Bool { source == .safari && safariAccess != .noContainer }
    var showsLearnMore: Bool { !source.isNone }
    var showsTip: Bool { !source.isNone }

    func onAppear() {
        refresh()
    }

    func openFullDiskAccessSettings() {
        guard let url = URL(
            string: "x-apple.systempreferences:com.apple.preference.security?Privacy_AllFiles"
        ) else {
            return
        }
        settingsLink.open(url)
    }

    func openHelp() {
        openURL.open(CookieHelpURL.url(forBrowserKey: source.browserKey))
    }

    private var isFirefox: Bool {
        if case .firefox = source { return true }
        return false
    }

    private func refresh() {
        firefoxProfiles = resolver.firefoxProfiles()
        safariAccess = resolver.safariAccess()
        if case let .firefox(name) = prefs.cookiesFromBrowser,
           let name,
           !firefoxProfiles.contains(where: { $0.name == name }) {
            prefs.cookiesFromBrowser = .firefox(profile: nil)
        }
    }
}
```

Note: `refresh()`'s `if case let ... , let name, !contains` is a multi-clause `if` — swiftformat/swiftlint may reject the wrap. If lint trips, extract `private func staleFirefoxProfileName() -> String?` returning the name to rewrite, and call `if staleFirefoxProfileName() != nil { prefs.cookiesFromBrowser = .firefox(profile: nil) }`.

- [x] **Step 5: Run tests to verify they pass**

Run: `xcodebuild ... test -only-testing:AppUnitTests/CookiePaneModelTests`
Expected: PASS.

- [x] **Step 6: Lint**

Run: `mise exec -- swiftformat --lint . && mise exec -- swiftlint lint --strict`
Expected: clean.

---

## Task 17: The filled Sign-in & cookies pane

**Files:**
- Modify: `apps/media-grabber/Sources/App/Preferences/Panes/SignInCookiesPane.swift`
- Modify: `apps/media-grabber/Sources/App/AppModel.swift` (expose `pendingCookieRetryJobID` job title lookup helper if needed) — actually the pane reads `appModel.pendingCookieRetryJobID` and looks the title up via `appModel.rowStore.rows`
- Modify: `apps/media-grabber/Sources/App/Preferences/PreferencesView.swift` (no change — `SignInCookiesPane()` already routed)
- Test: `apps/media-grabber/Tests/AppUnitTests/PreferencesPaneTests.swift` (add a pane-row-visibility assertion via `CookiePaneModel`, not SwiftUI rendering)

**Interfaces:**
- Consumes: `CookiePaneModel` (Task 16), `SkinnedPicker` / `SkinnedPickerRow` (existing), `PrefRow` / `PrefPaneHeader` (existing), `AppModel.pendingCookieRetryJobID` + `resolveCookieRetry()` (Task 15).
- Produces: a `SignInCookiesPane` view with the five row types + the pending-retry banner. No new public API — this is a view. Its logic-bearing parts (row visibility) are already covered by `CookiePaneModelTests`; this task's test asserts the pending-retry banner text builder if extracted.

**Pane structure:**
1. `PrefPaneHeader(.cookies)`
2. Pending-retry banner row (only when `appModel.pendingCookieRetryJobID != nil`): `--warn` styled, text `Pick a browser to retry "\(jobTitle)" with your sign-in.` where `jobTitle` = `appModel.rowStore.rows.first { $0.id == pendingID }?.snapshot.title ?? "this download"`.
3. **Browser** `PrefRow("Browser", helper: "Use your browser's YouTube sign-in for age-restricted or private videos.")` → `SkinnedPicker<CookieSource>` with rows `None`, `Safari`, `Chrome`, `Brave`, `Microsoft Edge`, `Firefox`. Selecting Firefox → `.firefox(profile: nil)`. The picker's binding is `model.source` (via a local `Binding` mapping the 6 display cases to `CookieSource`; the `.firefox` row maps to `.firefox(profile: nil)` and displays selected for any `.firefox(_)`).
4. **Firefox profile** `PrefRow` — only `model.showsFirefoxProfilePicker`. `SkinnedPicker<String>` of `model.firefoxProfiles.map(\.name)`, bound to `model.selectedFirefoxProfile` (nil-coalesced to the default profile's name). When `model.showsFirefoxNoProfilesNote` → a `--dim` `PrefRow` with `No Firefox profiles found.`
5. **Full Disk Access** `PrefRow` — only `model.showsFullDiskAccessRow`:
   - `.granted` → `.ok` dot + `Full Disk Access granted.`, no button
   - `.denied` → `--warn` dot + `MediaGrabber needs Full Disk Access to read Safari's sign-in.` + an `Open System Settings` button → `model.openFullDiskAccessSettings()`
6. **Learn more** `PrefRow` — only `model.showsLearnMore`. A link-style button: `Cookie access for \(browserName) — Learn more ↗` → `model.openHelp()`. `browserName` from a local `displayName(for:)` on `CookieSource`.
7. **Tip** — only `model.showsTip`. A `--dim` block: `For the most reliable results, use a browser profile that's signed in to YouTube and keep it closed while downloading.`

`onChange(of: model.source)`: when it moves off `.none` and `appModel.pendingCookieRetryJobID != nil` → `Task { await appModel.resolveCookieRetry() }`.

`.onAppear { model.onAppear() }`. `@State private var model: CookiePaneModel` built in `init` from `appModel.prefs` — but `SignInCookiesPane` currently has no `init` and reads `@Environment(AppModel.self)`. Use `@State private var model: CookiePaneModel?` set in `.onAppear`, or a `CookiePaneModelBox`. **Simplest:** give the pane an `init()` that can't see the environment; instead lazily create the model in `.task`/`.onAppear`:
```swift
struct SignInCookiesPane: View {
    @Environment(AppModel.self) private var appModel
    @State private var model: CookiePaneModel?
    // build model in .onAppear from appModel.prefs; guard the body on model != nil
}
```
Match whatever pattern the other panes use for view-models if one exists; `NetworkPane` / `DownloadsPane` read `appModel.prefs` directly with `@Bindable`, no view-model — so the `@State CookiePaneModel?` lazy-init is the local precedent to establish.

- [x] **Step 1: Write the failing test**

`PreferencesPaneTests` (or a new `SignInCookiesPaneTests` if `type_body_length` trips) — assert the display-name helper and the banner-title helper if you extract them as free functions / static methods. Example, assuming a `SignInCookiesPane.displayName(for:)` static:

```swift
    func test_cookieSourceDisplayNames() {
        XCTAssertEqual(SignInCookiesPane.displayName(for: .none), "None")
        XCTAssertEqual(SignInCookiesPane.displayName(for: .safari), "Safari")
        XCTAssertEqual(SignInCookiesPane.displayName(for: .edge), "Microsoft Edge")
        XCTAssertEqual(SignInCookiesPane.displayName(for: .firefox(profile: nil)), "Firefox")
    }
```

- [x] **Step 2: Run test to verify it fails**

Run: `xcodebuild ... test -only-testing:AppUnitTests/PreferencesPaneTests`
Expected: FAIL — no `displayName` member.

- [x] **Step 3: Write the pane**

Build `SignInCookiesPane.swift` per the structure above. Keep `displayName(for:)` and the pending-banner title as `static` / free helpers so they're unit-testable without rendering. Use existing `theme.palette.warn` / `.ok` / `.dim` tokens and `Spacing` constants — match `NetworkPane` / `DownloadsPane` styling exactly. No phase references in any string.

- [x] **Step 4: Run tests to verify they pass**

Run: `xcodebuild ... test -only-testing:AppUnitTests/PreferencesPaneTests -only-testing:AppUnitTests/CookiePaneModelTests`
Expected: PASS.

- [x] **Step 5: Build the app to catch SwiftUI compile errors**

Run: `mise exec -- tuist generate --no-open && xcodebuild -workspace MediaGrabber.xcworkspace -scheme MediaGrabber-Workspace -destination 'platform=macOS' build`
Expected: BUILD SUCCEEDED.

- [x] **Step 6: Lint**

Run: `mise exec -- swiftformat --lint . && mise exec -- swiftlint lint --strict`
Expected: clean. If `SignInCookiesPane.swift` exceeds `type_body_length` / `file_length`, split the row builders into a `SignInCookiesPane+Rows.swift` extension.

---

## Task 18: Full test sweep + `screens.html` + parent-spec edits

**Files:**
- Modify: `docs/mockups/screens.html`
- Modify: `docs/superpowers/specs/2026-08-28-youtube-downloader-mac-design.md`
- No source changes.

- [x] **Step 1: Run the entire test suite**

Run: `mise exec -- tuist generate --no-open && xcodebuild -workspace MediaGrabber.xcworkspace -scheme MediaGrabber-Workspace -destination 'platform=macOS' test`
Expected: all suites PASS. Fix any fallout — especially other `EngineDependencies(` / `PersistedJob(` / `FakeEngine` construction sites in `Tests/` that the new parameters broke.

- [x] **Step 2: Full lint**

Run: `mise exec -- swiftformat --lint . && mise exec -- swiftlint lint --strict`
Expected: clean across the whole tree.

- [x] **Step 3: Update `screens.html` — Screen 3.4**

Replace the `<div class="stepless">...</div>` inside `#s3-4`'s `.main` with the filled pane markup, matching the existing pane-row CSS classes used in screens 3.1–3.3:
- A browser row: label `Browser`, helper `Use your browser's YouTube sign-in for age-restricted or private videos.`, a `SkinnedPicker`-style trigger showing `Firefox`.
- A Firefox-profile row: label `Firefox profile`, a picker trigger showing `default-release`, with a second profile `dev-edition` in the popover sketch (or just the trigger).
- A `Learn more` link row: `Cookie access for Firefox — Learn more ↗`.
- The tip block (`--dim`): `For the most reliable results, use a browser profile that's signed in to YouTube and keep it closed while downloading.`
- Update `<div class="sub">` for 3.4 to describe the filled pane (drop "stepless", "No rows, no controls").
- Update the `<div class="cap">` — remove `(stepless)`.

Add a second inset after the main 3.4 app frame showing the **Safari state**: browser trigger = `Safari`, a Full Disk Access row with a `--warn` dot, text `MediaGrabber needs Full Disk Access to read Safari's sign-in.`, and an `Open System Settings` button. Label it `<div class="sub">Safari selected, Full Disk Access not yet granted.</div>`.

- [x] **Step 4: Update `screens.html` — Screen 1.2**

Find the failed row in the Home table (id `#s1-2`) that currently reads like a cookie failure ("couldn't verify you" / similar). Change its reason sentence to `Couldn't read your browser's sign-in.` and render its `🔑` button **enabled** (remove any `disabled` class / styling on that specific button).

- [x] **Step 5: Update the parent spec — §5 model**

Line ~238–239: replace the two bullets
```
- `cookiesFromBrowser: BrowserChoice` — `.none | .safari | .chrome | .brave | .firefox | .edge` (default `.safari`)
- `firefoxProfile: String?` — used only when `cookiesFromBrowser == .firefox`
```
with one bullet:
```
- `cookiesFromBrowser: CookieSource` — `.none | .safari | .chrome | .brave | .edge | .firefox(profile:)` (default `.none`). Cookies are opt-in; nothing reads a browser's sign-in unless the user picks one here or presses Retry-with-cookies on a failed row. The Firefox profile rides inside `.firefox(profile:)`.
```

- [x] **Step 6: Update the parent spec — §7.2**

The passage ending line ~435 ("...as `cookieReadFailed` only if the download then fails.") describes an always-on-cookies model with a silent fallback. Reword the cookie portion of §7.2 to: cookies are opt-in, default `.none`; `cookieReadFailed` fires on a direct user-requested cookie read that failed (a chosen browser or a Retry-with-cookies). Attach the "always on, default `.safari`, silent-fallback-then-classify-`cookieReadFailed`-only-if-the-download-fails" behaviour as a note for a future always-on-cookies phase, e.g.:
```
> A later always-on-cookies model would default `cookiesFromBrowser` to `.safari`, attempt the cookie read on every download, silently fall back to no cookies on a read failure, and classify `cookieReadFailed` only if the cookieless download then also fails. `CookieResolver` is built to support that unchanged.
```

- [x] **Step 7: Update the parent spec — §7.3**

Keep the existing bullets. Add:
- to the Safari bullet (line ~441): note the FDA check is a just-in-time probe-read of `Cookies.binarycookies` from the Preferences pane — no onboarding step.
- a bullet: Chrome (v127+) app-bound encryption prints no error; it is detected from a `Extracted 0 cookies` line on a run that carried a cookie argument and then failed downstream → `cookieReadFailed`.

- [x] **Step 8: Update the parent spec — §9**

Line ~544: the sentence "Phase 5 wires `cookieReadFailed`" stays accurate. No change needed unless the surrounding text implies always-on cookies — if so, align it with §7.2's opt-in wording.

- [x] **Step 9: Update the parent spec — §12.1 Phase 5 stub**

Replace the Phase 5 bullet (line ~706) and its hint (line ~707) with the shipped surface:
```
- **Phase 5 — Cookies.** `CookieSource` (`.none | .safari | .chrome | .brave | .edge | .firefox(profile:)`) + `CookieResolver` (Firefox `profiles.ini` enumeration, Safari Full-Disk-Access probe-read, spawn-time argument resolution). Opt-in, `Preferences.cookiesFromBrowser` default `.none`. The Sign-in & cookies pane filled: browser picker, Firefox-profile picker (shown at 2+ profiles), a just-in-time Full Disk Access status row + System Settings deep link (Safari only), a "Learn more" link, the recommended-setup tip. `--cookies-from-browser` threaded through `YtDlpArguments` (redacted in logs). `cookieReadFailed` classifier — stderr signatures plus an `Extracted 0 cookies` + downstream-failure override (the Chrome app-bound-encryption case). The `🔑` Retry-with-cookies row action, offered on `cookieReadFailed` / `ageRestricted` / `private`; `engine.retryWithCookies` does a from-scratch retry with `job.forceCookies` (persisted). `CookieHelpURL`. No Full-Disk-Access onboarding step — onboarding stays 4 steps.
```
Drop the old hint entirely (its content is now shipped / captured in this plan and Task 3–4 of screens.html).

- [x] **Step 10: Update the parent spec — §12.1 onboarding step row + §12.2 rows**

- Line ~706 (or wherever the Phase 5 bullet mentioned "a Full-Disk-Access `OnboardingStepID` case") — already removed in Step 9.
- Line ~746 (§12.2 "Onboarding step list" row): strike the `| Phase 5 — a Full-Disk-Access case ... |` right-hand cell; replace with `| — |` (onboarding stays as shipped in Phase 1).
- Line ~740 (§12.2 row-action bar row): the `retryWithCookies` mention stays; no wording change needed (it already says "Phase 5 (`retryWithCookies` `🔑`) — the engine adds them to the set, no UI change").
- Line ~744 (§12.2 `ErrorClass` emit paths row): `Phase 5 (`cookieReadFailed`)` stays accurate.
- Line ~745 (§12.2 `PreferencesView` panes row): change `Phase 5 (Firefox profile picker)` → `Phase 5 (the whole Sign-in & cookies pane)`.

- [x] **Step 11: Verify the spec edits are internally consistent**

Re-read §5, §7.2, §7.3, §9, §12.1, §12.2 in one pass. No "always-on" / "default `.safari`" claims remain outside a clearly-marked future-phase note. No dangling reference to a Phase 5 onboarding step. Section numbering and the §12.2 table columns intact.

- [x] **Step 12: Final full test + lint + build**

Run:
```
mise exec -- tuist generate --no-open
xcodebuild -workspace MediaGrabber.xcworkspace -scheme MediaGrabber-Workspace -destination 'platform=macOS' test
mise exec -- swiftformat --lint .
mise exec -- swiftlint lint --strict
```
Expected: all green.

---

## Manual smoke checklist

Run on a real machine after Task 18. (Hand to the user — not an automated step.)

- With `cookiesFromBrowser == .none`, grab an age-restricted video → it fails `This video is age-restricted and needs you to be signed in.`, the `🔑` button is enabled. Press `🔑` → Preferences opens on Sign-in & cookies with the `Pick a browser to retry "…" with your sign-in.` banner. Pick Safari.
- Safari selected, no Full Disk Access → the pane shows the `--warn` FDA row; `Open System Settings` opens the Full Disk Access pane. Grant it, return → the row flips to `.ok` (re-open the pane / it refreshes on appear).
- With Safari + FDA, retry the age-restricted video (`🔑` or Retry) → it downloads.
- Select Firefox with 2+ profiles → the profile picker appears, the default profile preselected. Pick a signed-in profile, retry a private video you have access to → it downloads.
- Select Chrome (v127+) → grab a bot-checked video → it fails `Couldn't read your browser's sign-in.`; the pane's `Learn more` opens the yt-dlp FAQ.
- Quit mid-retry with a `forceCookies` job queued → relaunch → the job is still queued and still retries with cookies.

---

## Self-Review

**Spec coverage:**

| Spec §1 item | Task |
|---|---|
| `CookieSource` value type | 1 |
| `CookieResolver` (`firefoxProfiles`, `safariAccess`, `resolve`) | 3, 4, 5 |
| `FileManaging` protocol + injection | 2, 3 |
| `CookieVerdict` / `SafariCookieAccess` / `CookieResolution` | 2 |
| `Preferences.cookiesFromBrowser` default `.none` | 7 |
| The filled Sign-in & cookies pane | 16, 17 |
| `cookieReadFailed` stderr signatures, ordered first | 9 |
| The `Extracted 0 cookies` + downstream-failure override | 13 |
| `🔑 retryWithCookies` row action | 14, 15 |
| `engine.retryWithCookies` + `job.forceCookies` persisted | 11, 14 |
| `YtDlpArguments.build` + `redacted` `cookieArgument` | 8 |
| `CookieHelpURL` | 6 |
| `FailurePresentation` widened for `cookieReadFailed` / `ageRestricted` / `private` | 10 |
| `EngineDependencies.fileManager` + spawn resolution | 12 |
| `screens.html` 3.4 + 1.2 | 18 |
| Parent-spec §5 / §7.2 / §7.3 / §9 / §12.1 / §12.2 edits | 18 |
| The `.none + jobOverride` substitution path | 5 |
| Preferences reset clears `cookiesFromBrowser` | 7 |
| `AppModel.pendingCookieRetryJobID` + `resolveCookieRetry` + page-change clear | 15 |
| `SettingsLinkOpening` deep link | 16 |

Deferred items (non-fatal fallback during a normal download, browser-tailored sentence, `player_client` interplay, Instagram/Twitter/TikTok heuristics) and not-in-scope items (FDA onboarding step, Keychain-prompt handling, `WarningBanner`/`HealthStrip`, rate limiting, POT provider, toasts) are correctly absent — the spec places their hints in their owning phases, which this plan does not touch.

**Type consistency:** `CookieSource.browserKey` / `ytDlpSpec` / `isNone` used identically in Tasks 5, 12, 15, 16. `CookieResolution.argument` (not `.arg`) throughout. `resolve(source:jobOverride:)` label order fixed. `retryWithCookies(_:)` (not `retryWithCookiesFor`) on the engine, protocol, and both fakes. `forceCookies` (not `forcedCookies`) on `DownloadJob` and `PersistedJob`. `cookiesRequested` + `extractedZeroCookies` params on `recordExit` in that order.

**Placeholder scan:** every code step carries real code; every test step carries real assertions; the two `recordExit`-threading tasks (12, 13) split `classifiedFailure` so each is a bounded change with its own test. Task 12 Step 3 defers the protocol line to Task 14 to avoid an un-implemented protocol requirement.

## Execution Handoff

Plan complete and saved to `docs/superpowers/plans/2026-09-02-media-grabber-phase-5.md`. Two execution options:

1. **Subagent-Driven (recommended)** — a fresh subagent per task, review between tasks, fast iteration.
2. **Inline Execution** — tasks in this session using executing-plans, batch execution with checkpoints.

Which approach?
