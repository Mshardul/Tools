# Phase 10 — Share Extension Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add a macOS Share Extension appex to MediaGrabber so a user can share a URL from any other app's Share sheet directly into MediaGrabber's existing Home-field ingestion path.

**Architecture:** A new `ShareExtension` Tuist target (`product: .appExtension`) embedded in the `MediaGrabber` app. The appex links `GrabberKit` only (no engine, no app-layer code) and contains one view controller whose entire job is: pull a `URL` out of the shared `NSExtensionItem` via a new pure `ShareExtractor.extractURL(from:)` (lives in `GrabberKit/Link/`, next to `LinkExtractor`, reusing it for the plain-text fallback), then call `extensionContext?.open(mediagrabber://open?url=…)` and complete the request. No App Group, no shared container — the existing Phase 9 `IncomingLinkScheme` / `IncomingLinkController` path in the main app handles everything from there, completely unchanged.

**Tech Stack:** Swift 6, AppKit-less `NSExtensionItem`/`NSItemProvider`/`UniformTypeIdentifiers` (Foundation-only appex logic), Tuist project generation, XCTest.

**Spec:** `docs/superpowers/specs/2026-09-11-media-grabber-phase-10-share-extension.md`

## Global Constraints

- Handoff is scheme-only (`mediagrabber://open?url=`) — no App Group, no shared container, no Darwin notifications.
- Exactly one share action, display name `CFBundleDisplayName` = "MediaGrabber" (bare name, no verb prefix).
- Appex entitlements: minimal App Sandbox only. No network client entitlement, no App Group entitlement — the appex never makes a network call.
- `ShareExtractor.extractURL(from:)` lives in `GrabberKit/Link/` (not appex-private) — pure, unit-tested by the existing `GrabberKitTests` target. No new XCTest target.
- The appex shows no custom UI of its own — default OS spinner-then-dismiss behavior only.
- No new mockups — reuses Phase 9's existing Home-field screens in `docs/mockups/screens.html`.
- Comments: single-line only, only for non-obvious *why* (per `apps/media-grabber/CLAUDE.md`).
- After adding/removing files: `mise exec -- tuist generate --no-open`. Lint: `mise exec -- swiftformat --lint .` and `mise exec -- swiftlint lint --strict`. Test: `xcodebuild -workspace MediaGrabber.xcworkspace -scheme MediaGrabber-Workspace -destination 'platform=macOS' test -only-testing:<suite>`. Do not use `tuist test` while debugging (hides compiler errors).
- No git commands of any kind (no `git add`/`commit`/`mv`) — file moves use `mv`, each task ends with the working tree left for the user to review and commit.

---

### Task 1: `ShareExtractor` pure extraction logic + tests

**Files:**
- Create: `Sources/GrabberKit/Link/ShareExtractor.swift`
- Test: `Tests/GrabberKitTests/ShareExtractorTests.swift`

**Interfaces:**
- Consumes: `LinkExtractor.extract(from:) -> URL?` (existing, `Sources/GrabberKit/Link/LinkExtractor.swift:4`)
- Produces: `public enum ShareExtractor { public static func extractURL(from items: [NSExtensionItem]) async -> URL? }` — Task 3 (the appex view controller) calls this with `extensionContext?.inputItems as? [NSExtensionItem] ?? []`.

Given the array of `NSExtensionItem`s a Share Extension receives, find the first attachment that resolves to a URL: prefer an `NSItemProvider` conforming to `UTType.url`, fall back to one conforming to `UTType.plainText` (some senders — e.g. certain in-app browsers — only attach text), run the resulting string through `LinkExtractor.extract(from:)` so it gets the same trimming/angle-bracket handling every other ingress path gets. Returns `nil` if nothing usable is found — the caller (Task 3) treats that as "complete the request, no scheme call."

- [ ] **Step 1: Write the failing tests**

```swift
import Foundation
@testable import GrabberKit
import UniformTypeIdentifiers
import XCTest

final class ShareExtractorTests: XCTestCase {
    private func item(url: URL) -> NSExtensionItem {
        let provider = NSItemProvider(object: url as NSURL)
        let item = NSExtensionItem()
        item.attachments = [provider]
        return item
    }

    private func item(text: String) -> NSExtensionItem {
        let provider = NSItemProvider(object: text as NSString)
        let item = NSExtensionItem()
        item.attachments = [provider]
        return item
    }

    private func item(noAttachment: Void = ()) -> NSExtensionItem {
        NSExtensionItem()
    }

    func test_urlTypeItem_extracts() async {
        let result = await ShareExtractor.extractURL(from: [item(url: URL(string: "https://example.com/a")!)])
        XCTAssertEqual(result?.absoluteString, "https://example.com/a")
    }

    func test_plainTextItem_withURL_extracts() async {
        let result = await ShareExtractor.extractURL(from: [item(text: "check this out https://example.com/b")])
        XCTAssertEqual(result?.absoluteString, "https://example.com/b")
    }

    func test_plainTextItem_withoutURL_returnsNil() async {
        let result = await ShareExtractor.extractURL(from: [item(text: "no link here")])
        XCTAssertNil(result)
    }

    func test_noAttachments_returnsNil() async {
        let result = await ShareExtractor.extractURL(from: [item()])
        XCTAssertNil(result)
    }

    func test_emptyItems_returnsNil() async {
        let result = await ShareExtractor.extractURL(from: [])
        XCTAssertNil(result)
    }

    func test_firstItemWins_whenMultiple() async {
        let items = [
            item(url: URL(string: "https://first.example")!),
            item(url: URL(string: "https://second.example")!)
        ]
        let result = await ShareExtractor.extractURL(from: items)
        XCTAssertEqual(result?.absoluteString, "https://first.example")
    }
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `mise exec -- xcodebuild -workspace MediaGrabber.xcworkspace -scheme MediaGrabber-Workspace -destination 'platform=macOS' test -only-testing:GrabberKitTests/ShareExtractorTests`
Expected: FAIL — `ShareExtractor` not defined.

- [ ] **Step 3: Write the implementation**

```swift
import Foundation
import UniformTypeIdentifiers

public enum ShareExtractor {
    public static func extractURL(from items: [NSExtensionItem]) async -> URL? {
        for item in items {
            guard let attachments = item.attachments else { continue }
            if let url = await firstURL(in: attachments) {
                return url
            }
            if let text = await firstPlainText(in: attachments), let url = LinkExtractor.extract(from: text) {
                return url
            }
        }
        return nil
    }

    private static func firstURL(in attachments: [NSItemProvider]) async -> URL? {
        for provider in attachments where provider.hasItemConformingToTypeIdentifier(UTType.url.identifier) {
            if let url = try? await provider.loadItem(forTypeIdentifier: UTType.url.identifier) as? URL {
                return url
            }
        }
        return nil
    }

    private static func firstPlainText(in attachments: [NSItemProvider]) async -> String? {
        for provider in attachments where provider.hasItemConformingToTypeIdentifier(UTType.plainText.identifier) {
            if let text = try? await provider.loadItem(forTypeIdentifier: UTType.plainText.identifier) as? String {
                return text
            }
        }
        return nil
    }
}
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `mise exec -- xcodebuild -workspace MediaGrabber.xcworkspace -scheme MediaGrabber-Workspace -destination 'platform=macOS' test -only-testing:GrabberKitTests/ShareExtractorTests`
Expected: PASS, all 6 tests.

- [ ] **Step 5: Lint**

Run: `mise exec -- swiftformat --lint Sources/GrabberKit/Link/ShareExtractor.swift Tests/GrabberKitTests/ShareExtractorTests.swift && mise exec -- swiftlint lint --strict --path Sources/GrabberKit/Link/ShareExtractor.swift --path Tests/GrabberKitTests/ShareExtractorTests.swift`
Fix any violations (run `mise exec -- swiftformat` without `--lint` to autofix, then hand-fix anything swiftlint still flags).
Expected: clean.

No commit step — this repo's changes are left uncommitted for the user (per Global Constraints).

---

### Task 2: `ShareExtension` Tuist target + appex Info.plist

**Files:**
- Create: `Sources/ShareExtension/Info.plist` (via Tuist `infoPlist`, inlined in `Project.swift` — see below; no standalone file needed since the app target uses `.extendingDefault(with:)` inline, follow the same pattern)
- Modify: `Project.swift`

**Interfaces:**
- Consumes: nothing (target scaffold only, no code yet — that's Task 3).
- Produces: a buildable, empty `ShareExtension` target that Task 3's view controller and `NSExtension` Info.plist keys attach to. `MediaGrabber` target's `dependencies` gains `.target(name: "ShareExtension")` so the appex embeds in the app bundle.

This task adds the target shell (bundle id, entitlements, Info.plist `NSExtension` dictionary, embed dependency) with a placeholder source file, so the project generates and builds before Task 3 adds real logic — avoids a big-bang target-plus-code change.

- [ ] **Step 1: Add the `ShareExtension` target to `Project.swift`**

Insert this target into the `targets:` array (after the `MediaGrabber` target, before `GrabberKit`):

```swift
.target(
    name: "ShareExtension",
    destinations: .macOS,
    product: .appExtension,
    bundleId: "app.mediagrabber.mac.share",
    deploymentTargets: .macOS("14.0"),
    infoPlist: .extendingDefault(with: [
        "CFBundleDisplayName": "MediaGrabber",
        "NSExtension": [
            "NSExtensionPointIdentifier": "com.apple.share-services",
            "NSExtensionPrincipalClass": "$(PRODUCT_MODULE_NAME).ShareViewController",
            "NSExtensionAttributes": [
                "NSExtensionActivationRule": [
                    "NSExtensionActivationSupportsWebURLWithMaxCount": 1,
                    "NSExtensionActivationSupportsText": true
                ]
            ]
        ]
    ]),
    sources: ["Sources/ShareExtension/**"],
    dependencies: [.target(name: "GrabberKit")],
    settings: .settings(base: [
        "CODE_SIGN_IDENTITY": "-",
        "CODE_SIGN_STYLE": "Manual",
        "ENABLE_HARDENED_RUNTIME": "NO",
        "ENABLE_APP_SANDBOX": "YES",
        "CODE_SIGN_ENTITLEMENTS": "Sources/ShareExtension/ShareExtension.entitlements"
    ])
),
```

Then add the embed dependency to the existing `MediaGrabber` target's `dependencies` array (`Project.swift:58`):

```swift
dependencies: [.target(name: "GrabberKit"), .target(name: "ShareExtension")],
```

- [ ] **Step 2: Create the entitlements file**

Create `Sources/ShareExtension/ShareExtension.entitlements`:

```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
	<key>com.apple.security.app-sandbox</key>
	<true/>
</dict>
</plist>
```

- [ ] **Step 3: Create a placeholder source file so the target has sources to compile**

Create `Sources/ShareExtension/ShareViewController.swift`:

```swift
import Foundation

final class ShareViewController: NSObject {}
```

(Task 3 replaces this with the real `NSViewController` subclass and logic.)

- [ ] **Step 4: Regenerate the Tuist project**

Run: `mise exec -- tuist generate --no-open`
Expected: succeeds, no errors. `ShareExtension.appex` target now visible in the generated Xcode project, embedded under `MediaGrabber.app`.

- [ ] **Step 5: Build**

Run: `make`
Expected: BUILD SUCCEEDED, app launches. (The appex isn't wired to do anything yet — this only confirms the target scaffold, entitlements, and Info.plist keys are valid and the embed step doesn't break the app build.)

- [ ] **Step 6: Lint**

Run: `mise exec -- swiftformat --lint Sources/ShareExtension/ && mise exec -- swiftlint lint --strict --path Sources/ShareExtension/`
Expected: clean (autofix with `swiftformat` sans `--lint` if needed).

No commit step.

---

### Task 3: `ShareViewController` — real extraction + scheme handoff

**Files:**
- Modify: `Sources/ShareExtension/ShareViewController.swift`

**Interfaces:**
- Consumes: `ShareExtractor.extractURL(from:) async -> URL?` (Task 1, `Sources/GrabberKit/Link/ShareExtractor.swift`).
- Produces: nothing further downstream — this is the appex's terminal logic. The URL it opens is consumed entirely by the existing Phase 9 `IncomingLinkScheme.openURL(from:)` / `IncomingLinkController.handleOpenURL(_:)` path in the main app, unchanged by this plan.

**Known duplication (accepted, not a defect):** `IncomingLinkScheme` (`Sources/App/Ingress/IncomingLinkScheme.swift:11`, `static let scheme = "mediagrabber"`) lives in the `MediaGrabber` app target, which the appex does not and should not link (App target links `ShareExtension`, not the reverse — linking it back would be a dependency cycle). The appex therefore hardcodes the literal `"mediagrabber"` scheme and `host = "open"` shape below, matching `IncomingLinkScheme.openURL(from:)`'s `isOpenAction` check exactly. If this string ever needs to change, both this file and `IncomingLinkScheme.swift` must be updated together — small enough surface (one string, one shape check) that extracting a shared constant into `GrabberKit` isn't worth the churn to Phase 9's shipped code for this plan.

This is the only task with real appex logic: read `extensionContext.inputItems`, extract a URL via `ShareExtractor`, build the `mediagrabber://open?url=<percent-encoded>` URL, hand it to the OS to open (which launches/activates the main app and triggers its existing `onOpenURL`/`application(_:open:)` handling — no new code needed there), then complete the extension request. No custom UI — no `.xib`/`.storyboard`, `NSViewController` with an empty view so the OS's default extension lifecycle (brief presentation, then dismiss) applies.

- [ ] **Step 1: Write the implementation**

Replace `Sources/ShareExtension/ShareViewController.swift`:

```swift
import AppKit
import Foundation
import GrabberKit

final class ShareViewController: NSViewController {
    override func loadView() {
        view = NSView()
    }

    override func viewDidAppear() {
        super.viewDidAppear()
        Task {
            await handleShare()
        }
    }

    private func handleShare() async {
        let items = extensionContext?.inputItems as? [NSExtensionItem] ?? []
        guard let url = await ShareExtractor.extractURL(from: items),
              let schemeURL = makeSchemeURL(for: url)
        else {
            extensionContext?.completeRequest(returningItems: nil)
            return
        }

        NSWorkspace.shared.open(schemeURL)
        extensionContext?.completeRequest(returningItems: nil)
    }

    private func makeSchemeURL(for url: URL) -> URL? {
        var components = URLComponents()
        components.scheme = "mediagrabber"
        components.host = "open"
        components.queryItems = [URLQueryItem(name: "url", value: url.absoluteString)]
        return components.url
    }
}
```

- [ ] **Step 2: Regenerate + build**

Run: `mise exec -- tuist generate --no-open && make`
Expected: BUILD SUCCEEDED, app launches.

- [ ] **Step 3: Lint**

Run: `mise exec -- swiftformat --lint Sources/ShareExtension/ && mise exec -- swiftlint lint --strict --path Sources/ShareExtension/`
Expected: clean.

No commit step.

---

### Task 4: Manual smoke test + doc verification

**Files:** none modified — verification only.

**Interfaces:** none — this task exercises the full path built in Tasks 1–3 end to end.

- [ ] **Step 1: Full workspace test run**

Run: `xcodebuild -workspace MediaGrabber.xcworkspace -scheme MediaGrabber-Workspace -destination 'platform=macOS' test`
Expected: GrabberKitTests and AppUnitTests both green, `ShareExtractorTests` included in the GrabberKitTests count, no regressions in existing suites (`IncomingLinkSchemeTests`, `IncomingLinkControllerTests`, etc. — unchanged, still passing).

- [ ] **Step 2: Repo-wide lint**

Run: `mise exec -- swiftformat --lint . && mise exec -- swiftlint lint --strict`
Expected: clean across the whole repo, including the new `Sources/ShareExtension/` files.

- [ ] **Step 3: Manual smoke — share a link from Safari**

1. `make` to build and launch the app (registers the appex with LaunchServices).
2. Open Safari, navigate to any page with a shareable URL (e.g. a Wikipedia article).
3. Click the Share icon → confirm "MediaGrabber" appears in the app grid with the bare app name (no verb prefix) and the correct icon.
4. Select it.
5. Expected: MediaGrabber activates, the shared URL appears in the Home field, and it begins resolving (same visual behavior as pasting the link directly — spinner/runway arming per existing Phase 9 behavior).

- [ ] **Step 4: Manual smoke — non-link share item**

1. In Safari (or Notes), select some plain text with no URL in it, share it.
2. Confirm MediaGrabber still appears in the grid (activation rule matches text).
3. Select it.
4. Expected: Share sheet dismisses, no crash, main app does not activate or change state (extraction correctly returned `nil`).

- [ ] **Step 5: Manual smoke — share while Home is busy**

1. Start a download in MediaGrabber so Home is busy (per the existing `isHomeBusy` definition — mid-resolve or the playlist picker open).
2. From Safari, share a different link to MediaGrabber.
3. Expected: existing Phase 9 busy-confirm dialog ("Grab this link?") appears, exercised via this new Share entry point — no new dialog code needed, this only confirms the existing `IncomingLinkController` busy path triggers correctly from a Share-originated `mediagrabber://open` call.

- [ ] **Step 6: Update `apps/media-grabber/CLAUDE.md`**

Modify the "Next:" line (currently added by the brainstorming session, pointing at the Phase 10 spec) to read "shipped" once this task confirms Tasks 1–4 all pass, mirroring how Phase 9's entry reads today. Also add a shipped-list entry for Phase 10 alongside the existing Phase 1–9 entries.

- [ ] **Step 7: Update the parent design doc**

In `docs/superpowers/specs/2026-08-28-youtube-downloader-mac-design.md` §12.1, change the Phase 10 bullet's opening to `**Phase 10 — Share Extension (shipped).**` once smoke testing passes, matching the `(shipped)` convention used by Phases 3–9.

- [ ] **Step 8: Archive the spec + this plan**

Once the user has reviewed and is satisfied: `mv docs/superpowers/specs/2026-09-11-media-grabber-phase-10-share-extension.md docs/superpowers/specs/archived/` and `mv docs/superpowers/plans/2026-09-11-media-grabber-phase-10-share-extension.md docs/superpowers/plans/archived/`. Update the "Spec:" reference inside the moved spec file if it mentions its own path anywhere (check first — it may not). Update `apps/media-grabber/CLAUDE.md`'s spec-path list to add the Phase 10 entry alongside Phase 9's, pointing at the archived path.

No commit step — the user commits when ready, per this repo's no-git-commands rule.
