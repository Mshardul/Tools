# Release, install, update and uninstall

**Status:** accepted. Implementation is in progress: install location, uninstall, and Sparkle are in the app. The name stays MediaGrabber, and the Dock icon is the existing Aurora orb. The appcast is published once the EdDSA key pair is stored as `MG_SPARKLE_PUBLIC_KEY` and `SPARKLE_EDDSA_PRIVATE_KEY`. Bundled tools resolve through `ManagedTools` and are fetched by `scripts/fetch-tools.sh`. The user-facing README is `apps/media-grabber/README.md`; build notes are in `apps/media-grabber/docs/development.md`. This is the Phase 19 branding and release gate (`apps/media-grabber/roadmap.md`). Renumbered from Phase 18 on 2026-11-05.

**Scope:** how MediaGrabber reaches testers and ordinary users, how it updates itself, and how it removes itself. Covers CI, the update mechanism, the in-app uninstall action, install-location handling and the user-facing README.

---

## Intent

A friend or family member downloads one file from GitHub, installs it by dragging it to Applications, approves it once in System Settings, and from then on the app keeps itself current without any further downloading or dragging. If they want it gone, one button in Preferences removes the app and everything it stored, and leaves their downloaded files alone.

The app is Apple Silicon only and requires macOS 14 or later. It is signed ad-hoc, so the first launch needs **Open Anyway** in System Settings → Privacy & Security. Developer ID signing and notarization can be added later without changing anything below except the signing step in CI.

---

## 1. Distribution

The repository is public, so release assets download anonymously and no separate releases repository exists.

- A release is created by pushing a tag `media-grabber-vN.N.N` (the existing `make release-patch|minor|major` flow). CI builds the app, signs it, packages `MediaGrabber-N.N.N.dmg`, verifies the DMG, writes `SHA256SUMS`, and publishes a GitHub Release carrying both files.
- Published releases are never deleted or replaced. A bad release is superseded by a higher version, and its entry is removed from the appcast (section 2) if it must stop being offered.
- The repository is a monorepo, so `releases/latest` can resolve to another tool's release. The README download link therefore points at the release list filtered by the tag prefix (`releases?q=media-grabber-v`), never at `releases/latest`.
- The marketing version `N.N.N` is used for both `CFBundleShortVersionString` and `CFBundleVersion`. Sparkle compares dotted versions natively.

## 2. Updates

Updates use Sparkle 2, embedded in the app. The user never downloads or drags anything to update.

- **Feed.** The app reads `https://mshardul.github.io/Tools/media-grabber/appcast.xml`, served by the repository's GitHub Pages site. It is not a release asset, because release-asset URLs for "latest" are ambiguous in a monorepo.
- **Archive.** Each appcast item's enclosure is the release DMG. One artifact serves both first install and update. The enclosure URL is the GitHub Release asset URL for that version.
- **Verification.** Every enclosure carries an EdDSA signature. The public key is in the app's Info.plist (`SUPublicEDKey`); the private key is a CI secret and exists nowhere else. Updates are accepted on the EdDSA signature alone, so they work with ad-hoc code signing.
- **Quarantine.** Sparkle-installed updates are not quarantined, so Open Anyway is needed once, on first install only.
- **Release notes.** Each appcast item links to its GitHub Release page.
- **Delta updates.** Full-DMG updates are the baseline. Sparkle's binary deltas can be switched on in appcast generation later by keeping prior archives available to the generator; no app change is needed.
- **Schedule and control.** Preferences → Updates holds the existing `autoCheckAppUpdates` toggle, which drives Sparkle's automatic check. The About page and the app menu carry **Check for Updates…**, which shows Sparkle's standard prompt. A background check never interrupts a running download; installation waits for the user to accept, and the app's existing quit confirmation covers active downloads.
- **yt-dlp** updates through its own path (`autoCheckYtDlpUpdates`, section 5) and is unrelated to app releases.
- **Delta updates** matter once the tools are bundled (section 5): most releases change only the app, so deltas keep updates small.

### CI steps added to the release workflow

1. Sign `Sparkle.framework`'s nested helpers and the framework itself, then the app, inside-out (ad-hoc), before the existing `codesign --verify --strict`.
2. After the DMG is verified, produce its EdDSA signature with the CI-held key.
3. Generate `appcast.xml` from the published releases and publish it to the Pages site under `/media-grabber/`.

## 3. Install location

An ad-hoc-signed app opened from Downloads or straight from the DMG runs from a randomized read-only path (App Translocation), where it cannot replace itself.

- On launch, if the app is not in `/Applications` (or `~/Applications`), it offers to move itself there, then relaunches from the new location. Declining is allowed; the offer repeats on the next launch until the app is in an Applications folder.
- Sparkle's Check for Updates is disabled with an explanatory line while the app is running from a location it cannot update.

## 4. Uninstall

**Preferences → Advanced → Uninstall MediaGrabber…**, placed beside the existing App data row.

Confirmation (destructive style, through the existing confirmation dialog): _"Remove MediaGrabber and everything it saved? Your downloaded files stay where they are."_ Active downloads are named in the dialog when any exist.

On confirm, in order:

1. Cancel active downloads and shut down child processes, including the sign-in helper server.
2. Delete the app's footprint (below) without going through the persistence flush, so nothing is rewritten after deletion.
3. Clear the app's preferences domain.
4. Move the app bundle to the Trash.
5. Quit.

If the bundle cannot be moved to the Trash (read-only location), the app finishes steps 1–3, tells the user plainly that the last step is theirs, and reveals the app in Finder.

**Footprint** (one list in code, used by the action and by Diagnostics):

- `~/Library/Application Support/MediaGrabber/` (queue, history, column layout, sign-in helper server and plugin archives, yt-dlp plugins)
- `~/Library/Logs/MediaGrabber/`
- `~/Library/Caches/app.mediagrabber.mac/` (includes Sparkle's cache)
- the preferences domain `app.mediagrabber.mac` and the confirmation-suppression keys stored in it
- saved window state for the bundle identifier

**Left alone:** the user's downloaded media, and any tools the user installed themselves outside the app.

The Share Extension, the URL scheme and the Services entry are part of the bundle and disappear with it.

## 5. Bundled tools

The app ships every tool it runs. A user installs nothing else: no Homebrew, no Node, no pipx.

| Tool | Source | Pinned in |
| --- | --- | --- |
| `yt-dlp` | the official standalone macOS binary from the yt-dlp release, checked against that release's `SHA2-256SUMS` | `scripts/tools.lock` |
| `ffmpeg`, `ffprobe` | built in CI from a pinned source tarball, arm64, static, configured `--disable-gpl --disable-nonfree` with `libmp3lame` and the native AAC encoder (m4a and mp3 extraction, mp4/mkv merging) | `scripts/tools.lock` |
| `node` | the official Node 22 `darwin-arm64` release, the `node` executable only, checked against `SHASUMS256.txt` | `scripts/tools.lock` |
| sign-in helper server and plugin | the bgutil release already pinned by the app, built in CI (`npm ci`, `tsc`, production dependencies) | `ShieldInstaller.version` |

- **Location.** `Contents/Resources/Tools/` holds the executables and `Contents/Resources/Shield/` holds the built server and the plugin archive. CI signs each executable ad-hoc, then the app, inside-out, before the existing verify step.
- **Resolution.** One type, `ManagedTools`, answers "where is this tool". `ffmpeg`, `ffprobe` and `node` always resolve to the bundled copy. `yt-dlp` resolves to the higher version of the bundled copy and the updated copy at `~/Library/Application Support/MediaGrabber/bin/yt-dlp`. No `PATH` search and no Homebrew paths exist anywhere in the app.
- **yt-dlp updates.** When `autoCheckYtDlpUpdates` is on, and from Preferences → Updates on request, the app fetches the latest yt-dlp release's `yt-dlp_macos` and `SHA2-256SUMS`, verifies the checksum, installs the file atomically into the `bin` directory and marks it executable. The canary check then runs against it; if the canary fails, the updated copy is deleted and the bundled copy is used. The engine's minimum-version floor still applies.
- **First run.** There is nothing to install. First run performs the canary check and nothing else. The sign-in helper is available from the first launch; its plugin is copied into place on first use.
- **Notices.** About carries third-party notices for every bundled tool, including the ffmpeg license text and a link to the exact source tarball used.
- **Size.** The app is roughly 200 MB. Section 2's delta updates keep routine updates small.

## 6. README

`apps/media-grabber/README.md` is written for people who use the app, not people who build it.

- What the app does, in plain language, with screenshots.
- **Download:** a button linking to the filtered release list, and the requirements line (Apple Silicon, macOS 14 or later).
- **Install:** drag to Applications; first launch via Open Anyway, with a screenshot for each step.
- **Updating:** automatic; where to find Check for Updates.
- **Uninstalling:** the Preferences button, and the folders it removes, for anyone who prefers to do it by hand.
- **Getting help:** how to share a diagnostic bundle.

Build, test, lint and debug-flag content moves to `apps/media-grabber/docs/development.md`.

## 7. Testing

- Footprint deletion runs against an injected temporary home directory; a test asserts every path in the footprint list is removed and that nothing outside the list is touched, including a sibling "Downloads" directory.
- The uninstall sequence is tested with fakes for the engine, the bundle-trashing call and the preferences domain: order of steps, the no-flush guarantee, and the can't-trash fallback.
- The install-location check is tested for `/Applications`, `~/Applications`, a translocated path and a mounted-volume path.
- The workflow is exercised with the existing dry-run dispatch; the appcast step is verified by generating a feed from a throwaway DMG and checking it with Sparkle's own verification.
- `ManagedTools` is tested with an injected resource root and support directory: bundled-only, updated-newer, updated-older, updated-corrupt. The yt-dlp updater is tested against a fake download source for checksum mismatch, network failure and canary failure, each leaving the previous working copy in place.
- The release workflow's dry run asserts every bundled executable runs (`--version`) on the runner and that `codesign --verify --deep --strict` passes on the finished app.
- The full loop (install from DMG on a clean account with no Homebrew, update from vN to vN+1, uninstall) is run by hand on a second Mac or user account before the first tester is invited.
