# Release hardening

**Status:** proposed, awaiting review. Written before the repository split (Phase 20); the workflow, update-feed and release-asset parts are rewritten against the new repository once the split lands.

**Scope:** what a release must prove before it is published: the licenses it ships under, the behaviour of the built and signed app, the update path, and the risks the release plan flagged. The manual run on a clean account is a checklist run before each release, and which phase finishes the pre-release work is decided separately.

---

## Intent

A release is published only when the built, signed app has shown that it works on a Mac with nothing else installed. Unit tests prove the logic; this phase proves the artifact. The sign-in helper shipped broken in 0.1.1 while every unit test was green, because no test ever ran the helper from inside the bundle. The same class of fault must not reach a user again.

## 1. Licenses

The app is MIT. It bundles tools under other licenses, and each one is stated in the app itself.

| Component | License | How it is bundled |
| --- | --- | --- |
| yt-dlp | Unlicense | standalone binary |
| FFmpeg, LAME | LGPL 2.1 or later | one separate executable, built from the pinned source without GPL options |
| Node | MIT | the `node` executable |
| Sign-in helper (bgutil) | GPL 3.0 only | a separate Node program and a yt-dlp plugin; the app never links it |
| Sparkle | MIT with bundled third-party notices | framework |

- **Where it is shown.** A **Licenses** pane in Preferences (System group) lists every component with its license and a button that opens the full text. About's "Read licenses" row opens this pane. The pane states that MediaGrabber is MIT-licensed and that the listed tools keep their own licenses.
- **Full texts.** `Contents/Resources/Licenses/` holds each license text, copied by `scripts/fetch-tools.sh` from the pinned sources so the text always matches the shipped version. A component with no entry in the catalogue, or a catalogue entry with no text file, fails a test.
- **Source.** Each release carries the pinned source tarballs for FFmpeg, LAME and the sign-in helper as release assets, listed in `SHA256SUMS`, so the source stays available for as long as that version does.
- **Replacement.** A permissively licensed replacement for the helper is tracked in `future-ideas.md`. Nothing in this phase depends on it.

## 2. End-to-end run on the built app

A test target `E2ETests` runs against a real `MediaGrabber.app` path given by `MG_E2E_APP`, and skips when it is unset, so `make test` is unchanged. `make e2e` builds the Release app, signs it with `scripts/sign-app.sh`, runs the target against it and removes the build copy.

Every case runs with a temporary home directory and `PATH=/usr/bin:/bin`, which is the Mac with no Homebrew, no Node and nothing else.

- Every bundled tool runs and reports its version.
- The setup check passes with the bundled downloader.
- A video downloads from the Creative Commons fixture to a temporary folder, and the file exists and is not empty.
- Audio extraction produces an m4a and an mp3 that `ffprobe` reads as audio.
- The sign-in helper starts from inside the bundle with the bundled Node, answers `/ping`, and returns a token for a test video.
- An updated downloader in Application Support is chosen over the bundled one when newer, and ignored when older.
- Homebrew tools and a leftover `bgutil-server` folder in Application Support are never run.
- Uninstall against the temporary home removes the footprint, leaves a sibling `Downloads` file, and does not recreate `queue.json` while a save is pending.

Cases that need the internet (the download, the setup check, the token) retry once and are the only ones allowed to retry.

## 3. Update test

`scripts/e2e/update-test.sh` proves Sparkle updates the app in place. It builds two throwaway versions signed with a test EdDSA key pair whose public key goes in through `TUIST_SPARKLE_PUBLIC_KEY` and whose feed URL points at a local server, serves a generated appcast and the newer disk image, runs the older app from an Applications folder under the temporary home, and asserts that the installed bundle is the newer version afterwards. The real signing key is never used.

## 4. Review Focus coverage

Each risk named in the release plan has a test or a written manual check.

| Risk | Covered by |
| --- | --- |
| Run from Downloads or a disk image | unit tests for the location check and the disabled update copy |
| Uninstall while a download is running | persistence test plus the end-to-end uninstall case |
| Bundle cannot be moved to the Trash | sequence test, plus a manual check on a read-only copy |
| Downloader update with a bad or truncated download | updater unit tests |
| Downloader update that fails the check | updater unit test, and the bundled copy stays in use |
| Mac with no Homebrew, Node or `PATH` entries | the end-to-end environment |
| Old Homebrew tools and old helper folder | end-to-end case and a unit test |

## 5. Release gate in CI

The release workflow runs the end-to-end target against the signed app after the smoke test and before the disk image is built. A failure stops the release. A dry run runs it too.

## Not in this phase

The review of the existing unit tests is its own phase, after this one (`2026-11-17-media-grabber-phase-22-test-suite-review-design.md`). The user-facing README and the portfolio showcase page are planned in their own threads and land in this phase or a later one.
