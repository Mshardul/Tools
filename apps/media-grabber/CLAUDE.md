# MediaGrabber — agent notes

macOS app. Two targets: `GrabberKit` (headless SPM-style framework, no SwiftUI)
and `MediaGrabber` (thin SwiftUI app over it). Tuist-generated project.

Specs: `docs/superpowers/specs/` — parent design `2026-08-28-youtube-downloader-mac-design.md`
(living), current phase spec alongside it. Built phases' specs + plans move to
`specs/archived/` and `plans/archived/`. Phase 1: `specs/archived/core-download-pipeline.md`.

## Phase scoping — three rules

Every planning conversation decides, per item raised: IN this phase, or DEFERRED.

1. **In this phase → build it to final-app form.** No stubs to swap later, no
   "minimum that passes this phase," no shape a later phase must replace. If the
   confirmation dialog is in scope, it gets its real skinned UI + design-system
   entry now.
2. **Deferred → a one-line hint in the phase that owns it.** Don't fully solve
   it, don't silently drop it. Pick its phase, add the briefest pointer there
   (a few words — "review X", "plan Y") so it surfaces when that phase starts.
   Hints live in the parent design spec §12 or the target phase's spec.
3. **Completed phases are closed.** No blame, no rework to match a later rule,
   no framing current work as fixing past mistakes. If current work must touch
   completed-phase code (e.g. the P2 engine rework demoting `DownloadJob`), do
   it as a plain change the current phase makes. Present and future only.
4. **Splitting an oversized phase → new sibling phases, renumber.** Never
   `4a`/`4b`. Insert a phase, shift every later number up. Each result is still
   an independently buildable working-app increment. Finish the design + spec
   for the first split phase (dependency order); mark the rest "in progress"
   for their normal turn. Update §12 + §12.2 numbering in the same pass.

## Design decisions

- **Every code change is made for the app's end state, not the current phase.**
  The target is the app as envisioned at its final phase (all features:
  multi-concurrent scheduler, per-host rate limiting, circuit breaker, adaptive
  concurrency, playlist queues of thousands, retry/backoff, cookies, POT
  rotation, diagnostics). Pick the structure that serves that. Do NOT build the
  minimum that passes this phase and plan to replace it later — rewriting/
  removing working code is wasted effort and is treated as a failure of the
  design pass, not normal iteration. Shell-and-fill (build the full structure
  now, a later phase adds cases/wiring without relayout) is the pattern; rip-
  and-replace is not.
- Decide architecture on what the app / subsystem should be at its end state.
  The phase plan (`docs/superpowers/specs/2026-08-28-youtube-downloader-mac-design.md`
  §12) is an output — it gets rewritten to match a decision, not treated as fixed
  scope. Never argue a design choice from "a later phase needs it"; argue from
  the app-level need, pick the fit, then update the phase list and say so.
- When weighing an option, walk the concrete future features that would stress
  it (playlists → thousand-row queues, higher concurrency cap, larger history)
  and check the option holds. "Sub-millisecond at current scale" is not the
  test; "still the right shape when the headline feature lands" is.
- Brainstorming forks: plain-chat prose — the fork, the real tradeoff, a
  recommendation. Not the AskUserQuestion box. One position at a time; revise on
  merit, don't pitch-then-collapse.

## Build & test

- Run: `make` (rebuilds, kills any running instance, launches the new build).
- `mise exec -- tuist generate --no-open` after adding/removing files.
- Test: `xcodebuild -workspace MediaGrabber.xcworkspace -scheme MediaGrabber-Workspace -destination 'platform=macOS' test`
- Single suite: append `-only-testing:GrabberKitTests/<SuiteName>` (or `AppUnitTests/<SuiteName>`).
- Do NOT use `tuist test` when debugging — its output filtering hides compiler
  errors. `tuist test` is fine in CI where a pass/fail is all that matters.
- Lint: `mise exec -- swiftformat --lint .` and `mise exec -- swiftlint lint --strict`.
- The `MediaGrabber` scheme only exists because `AppUnitTests` depends on it;
  the workspace-wide scheme is `MediaGrabber-Workspace`.
- `MediaGrabber-Workspace` is defined explicitly in `Project.swift` (not
  auto-generated) so it can carry code coverage for `GrabberKit` + `MediaGrabber`.

## Release

- Versions are manual SemVer, pre-1.0. `make release-patch` / `release-minor` /
  `release-major` computes the next version from the latest `media-grabber-v*`
  tag, confirms, then tags and pushes. Bare `make release` errors.
- The **tag** is `media-grabber-vX.Y.Z`; every derived string (`MARKETING_VERSION`,
  DMG name, `bump-version.sh` I/O) is the bare `X.Y.Z`.
- The build reads the version from `TUIST_MG_VERSION` (unset → `0.0.0`); the
  release workflow exports it before `tuist generate`.
- A tag push runs `.github/workflows/media-grabber-release.yml`: build Release,
  ad-hoc sign, DMG via the vendored `scripts/create-dmg`, verify the DMG's app
  version matches the tag, publish a GitHub Release with the `.dmg` + `SHA256SUMS`.
- To test the release path without publishing: Actions tab → media-grabber-release
  → Run workflow → set `version`, tick `dry_run`.
- `XCODE_VERSION` is pinned in an `env:` block at the top of BOTH workflow files;
  a bump edits both. A weekly scheduled CI run tests against Xcode `latest` so a
  retired pin surfaces out of band.
- Notarization, real Developer ID signing, and hardened runtime are not wired —
  the release workflow's sign step marks where they slot in.
- `scripts/create-dmg` is vendored (andreyvit) at a pinned SHA with one local
  patch (support-dir path); see `scripts/support/PROVENANCE`.

## Toolchain

- `mise` pins tuist / swiftformat / swiftlint to exact versions in `.mise.toml`.
  Don't run `mise use <tool>@latest` — it rewrites the pin.
- `.swiftformat` has `--disable docComments`; `.swiftlint.yml` has
  `disabled_rules: [todo]`. Both exclude `Derived/`.

## Code style

- Comments: single-line only, only to explain *why*, only when the type/function
  names don't already carry it. No `///` doc comments. No stacked `//` blocks.
  If the "why" needs more than one line, restructure the code instead.
- `// MARK:` is fine (navigation, not a comment).

## Swift 6 / concurrency traps (hit these already — will recur)

- **`NSLock.lock()` / `.unlock()` are banned in async contexts.**
  `Synchronization.Mutex` needs macOS 15; deployment target is 14. Use the
  `os_unfair_lock`-backed `LockedBox` in `Tests/GrabberKitTests/Support/FakeProcessRunner.swift`
  (or an equivalent) for any shared mutable state touched from `async` code.
- **Actors are reentrant across `await`.** An actor method that suspends
  (awaiting a child process, a stream, the network) does NOT hold the actor
  between suspensions — a second call runs concurrently. To truly serialize,
  chain an internal `Task` (see `MetadataProbe.tail`). Actor isolation alone is
  not a queue.
- **`XCTestCase` is not `Sendable`.** A `Task { }` inside a test can't call an
  instance helper method. Build the value (`ProcessLaunch`, etc.) before the
  `Task` and capture only `Sendable` locals.
- **`DownloadJob` is `@MainActor @Observable`.** The engine hops
  `await MainActor.run { … }` for every job mutation. Tests that read
  `job.state` / `job.progress` must be `@MainActor` and poll until the job
  reaches a terminal state (`submit` returns instantly at `.queued`).

## Lint traps

- `swiftformat` and `swiftlint` disagree on where the opening `{` goes for a
  wrapped multi-line `if` condition. Fix: extract the condition into a named
  predicate function, don't inline a multi-line `||` / `,` condition.
- `swiftformat` promotes a `//` comment directly above a declaration to `///`
  unless `docComments` is disabled (it is — keep it that way).

## Process / child-process rules

- `ProcessRunner` is the ONLY place `Foundation.Process` is touched.
  `DownloadEngine` is the ONLY component that spawns download processes.
- `ProcessRunner` drains each pipe on its own blocking-`read` thread + a
  2-count latch to finish the stream. `readabilityHandler` + a
  `terminationHandler` drain was tried and dropped lines under concurrent tests
  — don't reintroduce it.
- Shell fixture scripts that must die on SIGTERM use `exec` (e.g.
  `exec sleep 60`) so the signal reaches the real process, not an orphaned child.

## Fixtures / network

- No network in tests. Real-network tests gated behind `MG_LIVE_TESTS=1`, off in CI.
- Capture fixtures from `commons.wikimedia.org` / `archive.org` (Creative
  Commons). **YouTube is bot-blocked without a POT provider** — out of Phase 1.
- Network-failure stderr on macOS says "Failed to resolve … nodename nor
  servname provided", not "getaddrinfo". `ProgressParser`'s signature list
  covers both — keep macOS phrasing in it.

## Known Phase 1 gaps (tracked in ticket-backlog.md, not bugs)

- Aurora typefaces (Sora / Inter / JetBrains Mono) are not bundled — `Skin`'s
  font accessors fall back to the system face.
- Onboarding's `testRun` canary is auto-pass (real probe needs later-task types).
- No queue / persistence / resume — a quit mid-download loses the job.

## Python

- If you need Python for a bulk text edit or script, use the repo-root venv:
  `/Users/shardul/Documents/Github/Tools/.venv/bin/python`. Never system
  `python3`, never create a venv in this leaf.
