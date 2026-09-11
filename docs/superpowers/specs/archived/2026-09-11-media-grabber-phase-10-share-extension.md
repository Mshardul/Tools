# Phase 10 — Share Extension

**Status:** ready for plan.

**Replaces:** `docs/superpowers/specs/2026-09-10-media-grabber-share-extension-STUB.md` (superseded by this file; stub content folded in below).

## Intent

User is in another app (Safari, Finder, Mail, any app that shares a URL)
and shares a link to MediaGrabber. MediaGrabber's icon appears in the OS
Share sheet under the name "MediaGrabber". Picking it hands the URL to the
main app: the app activates, the shared URL lands in the Home field, and
resolution starts automatically — the same idle/busy behavior every other
ingress path (paste, drag, Services, `mediagrabber://` scheme) already
has. The user still presses Grab themselves once the runway is armed.

There is exactly one share action. No second "download immediately with
defaults" action — a silent background download from the Share sheet was
considered and rejected as UX-unfriendly; every entry point converges on
the same "arm the runway, human presses Grab" behavior.

## Not this phase

- A second, faster "download with defaults" Share action — rejected (see
  Intent).
- Chrome / Safari browser extensions — backlog; they use the
  `mediagrabber://` URL scheme directly, same as any other external
  caller, not this appex.
- Any payload richer than a URL (files, images, multi-item share) — out
  of scope for a link-based downloader.

## Architecture

**One new Tuist target:** `ShareExtension`, `product: .appExtension`,
bundle id `app.mediagrabber.mac.share`, embedded in `MediaGrabber` via a
`.target(name: "ShareExtension")` dependency (same pattern as the existing
target list in `Project.swift`). It links neither `GrabberKit` nor the app
target — the appex has no engine access and no UI beyond what the OS
share-sheet chrome provides.

**Handoff mechanism: URL scheme only, no App Group.** The appex's entire
job is: read the shared item, extract a `URL`, call
`NSExtensionContext.open(_:completionHandler:)` (via
`NSWorkspace`/`extensionContext`) with
`mediagrabber://open?url=<percent-encoded>`, then complete the extension
request and terminate. This is the exact scheme + query shape
`IncomingLinkScheme.openURL(from:)` already parses
(`Sources/App/Ingress/IncomingLinkScheme.swift`) — the appex reuses it
verbatim, no new scheme variant, no new main-app parsing path.

This was a deliberate choice, not a default: for the app's permanent
identity (one ingestion surface, every entry point resolves through the
same probe/engine), a shared container would only earn its cost if the
appex needed to do independent work (pre-fetch metadata, hold multi-item
state) before handoff. It never does — resolution always happens through
the main app's probe regardless of entry point, so there's nothing for a
shared container to carry that a URL string doesn't already.

**Extraction logic** (the one piece of real logic in the appex): given the
`NSExtensionItem`s off `extensionContext.inputItems`, find an
`NSItemProvider` conforming to `UTType.url` (preferred) or
`UTType.plainText` (fallback — some senders only attach text), load it
asynchronously, produce a `URL?`. This is a pure, testable function —
`ShareExtractor.extractURL(from:) async -> URL?` — separate from the
`NSExtensionContext` glue that calls it. Mirrors the existing
`LinkExtractor` split: pure parsing logic isolated from the OS-facing
caller.

If extraction fails (no usable item), the appex completes the request
with no scheme call — no error UI, no main-app notice. This differs from
the scheme's own failure path (Phase 9's "Couldn't open that link" notice)
because the appex can't reliably produce anything the scheme parser would
call malformed if extraction itself already failed — there's no URL to
hand off. The Share sheet closing with no visible effect is the correct
failure mode for "the shared item wasn't a link."

**Main-app path:** unchanged. `handleOpenURL` → `IncomingLinkScheme.openURL`
→ success routes through `IncomingLinkController` exactly as any other
scheme caller (browser link, `open` CLI, Spotlight) — busy-confirm dialog
if Home is mid-task, silent fill+probe if idle. `NSApp.activate` fires on
accept, same as today.

**Field reset on Grab:** already correct in the shipped code
(`HomeView.grab()`, `HomeView.swift:226-237` — `homeFieldText` clears
immediately after the grab call resolves, not on download completion).
No change needed here; confirmed during this design pass, noted so future
readers don't re-derive it.

## Signing

Appex gets its own `.entitlements` file: minimal App Sandbox, no App
Group, no network client entitlement (it never makes a network call —
`NSExtensionContext.open` is the only OS call it makes). Same signing
identity/team as the main app, embedded in the same `.app` bundle via
Tuist. Smallest possible entitlement set for the smallest possible appex.

## Share sheet presentation

- **Display name:** `CFBundleDisplayName` = "MediaGrabber" — bare app
  name, matching how every other app's icon reads in the same grid (no
  verb-phrase label; Share sheet cells are narrow and a longer label
  would truncate first).
- **Activation rule:** `NSExtensionActivationRule` accepting one
  `NSExtensionItem` with a `public.url` or `public.plain-text` attachment
  — matches what `ShareExtractor` can actually resolve. No file/image
  activation (the app doesn't download from local files).
- No custom sharing UI. The appex shows no screen of its own — Apple's
  default handling for an extension with no view controller is a brief
  spinner while `completeRequest` is pending, then the sheet dismisses.

## Mockups

None new. The OS Share sheet chrome (grid, icon, name) is not ours to
design — only the icon and display name (above) are customizable, and
those aren't visual-mockup territory. The resulting Home-field-filled
state is pixel-identical to the existing Phase 9 screens (`docs/mockups/screens.html`
§4.x, "link landed in field, resolving") since Share converges on the
same path. No `screens.html` changes this phase.

## Testing

- **Unit test** `ShareExtractor.extractURL(from:)` — the pure extraction
  function — against constructed `NSExtensionItem`/`NSItemProvider`
  fixtures: URL-type item, plain-text item containing a URL, plain-text
  item containing non-URL text, item with no usable provider, multiple
  items (first-match wins). New test target or file alongside
  `LinkExtractorTests`, same rigor.
- **No XCTest for the `NSExtensionContext` glue itself** (`open`,
  `completeRequest`) — this is OS lifecycle plumbing that requires a live
  extension host to test meaningfully, same reasoning already applied to
  the Phase 9 Services handler (`downloadWithMediaGrabber`). Covered by
  manual smoke instead.
- **Manual smoke checklist** (post-implementation, before marking
  shipped): share a link from Safari → MediaGrabber appears in the Share
  sheet as "MediaGrabber" → selecting it activates the main app and fills
  the Home field → share a non-link item (e.g. plain text with no URL) →
  sheet dismisses with no crash and no main-app change → share while Home
  is busy → busy-confirm dialog appears (existing Phase 9 behavior,
  exercised via this new entry point).
- Everything past "we have a URL" (probe, runway arm, Grab, field reset)
  is already covered by existing `IncomingLinkController` /
  `IncomingLinkScheme` / `HomeView` test suites — no duplicate coverage.

## Open questions

None outstanding — all four items the stub flagged (App Group vs
scheme-only, share-grid display name, signing, appex test strategy) are
resolved above.
