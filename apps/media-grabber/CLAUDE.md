# MediaGrabber — agent notes

macOS app. Two targets: `GrabberKit` (headless SPM-style framework, no SwiftUI)
and `MediaGrabber` (thin SwiftUI app over it). Tuist-generated project. Plan:
`docs/superpowers/plans/2026-08-29-media-grabber-phase-1.md`.

## Build & test

- `mise exec -- tuist generate --no-open` after adding/removing files.
- Test: `xcodebuild -workspace MediaGrabber.xcworkspace -scheme MediaGrabber-Workspace -destination 'platform=macOS' test`
- Single suite: append `-only-testing:GrabberKitTests/<SuiteName>` (or `AppUnitTests/<SuiteName>`).
- Do NOT use `tuist test` when debugging — its output filtering hides compiler
  errors. `tuist test` is fine in CI where a pass/fail is all that matters.
- Lint: `mise exec -- swiftformat --lint .` and `mise exec -- swiftlint lint --strict`.
- The `MediaGrabber` scheme only exists because `AppUnitTests` depends on it;
  the workspace-wide scheme is `MediaGrabber-Workspace`.

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
