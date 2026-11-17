# MediaGrabber — Phase 20: Repo split

**Status:** design agreed in discussion, awaiting review. Implementation plan follows.

## Intent

MediaGrabber lives in its own repository, `Mshardul/MediaGrabber`, before its first release. Every address the shipped app and its release pipeline depend on points at that final home from the first build, so no installed copy ever holds an address that has to change.

## Why this phase sits before release hardening

The release workflow, the update feed, the release asset URLs, the signing keys and Pages are what release hardening builds its checks against. The split fixes all of them, so the split comes first and hardening is written once, in its final home. Nothing is released yet, so none of these addresses has an installed copy depending on it.

## Goals, non-goals, anti-goals

Goals:

- The new repository builds, tests, lints and runs a release dry run green on its own, with no reference to the Tools repository or its paths.
- The update feed, tag scheme, release URLs, runtime config address and signing keys are final: they are the ones the first release ships with.
- The git history of the app and its documents is carried over, so blame and the reasoning in commit messages survive.

Non-goals:

- The user-facing README and the product page. They are written after the split, in the new repository.
- The release hardening checks and the test suite review. They are Phases 21 and 22.
- Notarization, bundle identifier changes, and any change to app behavior.

Anti-goals:

- Any build, including dry runs and test builds, that carries an address in the Tools repository.
- A compatibility shim, redirect stub or fallback for an old path or address. Nothing old is supported.
- The private signing key moving between machines or services.
- A second `MediaGrabber.app` on the machine while both checkouts exist.

## Decisions

**Repository name: `MediaGrabber`.** It matches the product name, gives `releases/latest`, a plain `vX.Y.Z` tag scheme, and the Pages address `https://mshardul.github.io/MediaGrabber/`. The repository is public, with `main` as its default branch.

**History: carried over.** The history is filtered from Tools to the paths listed under Carried-over paths. The user performs the filtering and the push. A secret scan over the filtered history runs before the first push.

**Layout: the old app folder is the repository root.** `Project.swift`, `Sources/`, `Makefile`, `CLAUDE.md`, `roadmap.md` and the rest sit at the top level. The documents from the Tools root keep their relative `docs/superpowers/` paths and merge with the app-local `docs/superpowers/` tree, so every `docs/superpowers/...` reference already in `CLAUDE.md`, the roadmap and the specs stays valid.

**Tags: `vX.Y.Z`.** The bare `X.Y.Z` drives `MARKETING_VERSION`, the DMG name and the Sparkle version. `make release-patch|minor|major` lists tags matching `v[0-9]*`, sorts them by version, strips the leading `v`, and falls back to `0.0.0` when none exists. It tags `vX.Y.Z` with the annotation `MediaGrabber vX.Y.Z` and pushes. The checks for a clean tree, being on `main` and matching `origin/main` stay, and bare `make release` still errors. `scripts/bump-version.sh` is unchanged. The workflow triggers on `v*`, strips `v`, and keeps its strict `N.N.N` validation, so a stray tag such as `vfoo` fails loudly.

**Make targets for release work.** Alongside `release-patch|minor|major`, the Makefile has `release-dry-run VERSION=X.Y.Z` (starts the release workflow as a dry run), `release-overwrite VERSION=X.Y.Z` (asks for confirmation, then starts the workflow with `overwrite`), `site-deploy` (starts the Pages deploy) and `venv` (creates `.venv` and installs `requirements.txt`). The workflow-starting targets use the GitHub CLI.

**Update feed: the `appcast.xml` asset of the latest release.** `SUFeedURL` is `https://github.com/Mshardul/MediaGrabber/releases/latest/download/appcast.xml`. The DMG and the appcast are assets of the same release, so updates depend on one service. Deleting or pulling the latest release makes the previous release "latest", and its own appcast is correct for that point in time. A release marked pre-release is never "latest", so it never reaches the feed.

**Pages: the product page only.** The page source is a `site/` folder on `main` holding `index.html`, `media/` and `fonts/`. A workflow deploys it with GitHub's Pages actions: it runs on a push to `main` that touches `site/`, and on manual dispatch. The workflow file is deliberately not a trigger, so adding the workflow before the page exists does not start a failing deploy (call made in review). Each deploy replaces the whole site. Pages' source setting is "GitHub Actions". The appcast is not on Pages, so a page deploy never touches updates and a release never touches the page.

**Runtime config address.** `PlayerClientCatalog.remoteURL` is `https://raw.githubusercontent.com/Mshardul/MediaGrabber/main/config/player-clients.json`.

**Python and tooling.** The repository has its own `.venv` at the root, git-ignored, with a short `requirements.txt` that pins pytest only. The Makefile's `PY` is `.venv/bin/python`, and `CLAUDE.md` names that relative path. A trimmed `pyproject.toml` carries the pytest and ruff settings. The pre-commit config (ruff, ruff-format, check-yaml, check-added-large-files, prettier-markdown), `.prettierrc.json`, `.prettierignore` and a `docs-format` workflow are copied from Tools and trimmed to what this repository uses. Python in CI stays the runner's `python3` for standard-library-only work.

**Licence: MIT, unchanged.** `LICENSE` is carried through the history filter. `README.md` and `NSHumanReadableCopyright` already say MIT.

**Signing keys: a fresh Sparkle pair.** No build carrying the old public key has been given to anyone, so nothing depends on it. The new pair is created under its own keychain account, the private key is exported once to a file outside the repository, backed up in a password manager, and stored as the repository secret `SPARKLE_EDDSA_PRIVATE_KEY`. The public key is the repository variable `MG_SPARKLE_PUBLIC_KEY`, which the build reads as `TUIST_SPARKLE_PUBLIC_KEY`. The old pair on Tools is retired. Losing the private key means no installed copy can ever update, so the backup exists before anything else uses the key.

**Claude project memory.** Claude's memory is stored per project folder, so the new folder starts empty. The memory folder is copied once to the new project's memory location and stays out of the repository, since it holds personal working rules, not contributor documentation. Memories that name the Tools venv path or closed phase progress are reviewed after the copy, one at a time, with the user naming each change.

**Cleanup in Tools: last.** Tools keeps its working copy until the new repository has passed its own checks. Only then are the app, its two workflows and its documents removed from Tools, and the root README points at the new repository.

## Approaches considered

Update feed location:

- Pages, as before. Works, but a second service sits on the update path, and every publisher of Pages content must carry the appcast forward or erase it.
- Release asset of the latest release. One service for DMG and feed, no shared state with the page, and a repository rename is covered by GitHub's redirects. It needs the release to be published only once all its assets are attached. Chosen.

Pages publishing:

- A `gh-pages` branch rewritten on each deploy. Works, but adds a branch nobody should touch and a third-party publishing action.
- GitHub Actions deployment from `site/`. Officially supported, atomic, nothing stale, no extra branch. Chosen.

History:

- A single snapshot commit. Clean, but permanent: blame and commit reasoning are lost and cannot be restored later.
- Filtered history. One filtering pass, Tools stays as the untouched source. Chosen.

Signing keys:

- Carry the old pair. Needs the private key exported and re-entered, and it may not be recoverable from GitHub secrets.
- A fresh pair. No installed copy depends on the old one. Chosen.

## Release workflow

The workflow is `release.yml`. The steps up to packaging are as before with the new tag handling. The feed-related steps are:

1. The previous appcast comes from the `appcast.xml` asset of the current latest release, downloaded through the GitHub CLI with the workflow token. If no release exists, the appcast starts empty. If a latest release exists and has no `appcast.xml`, the step fails: the feed is already broken and publishing on top of it would hide that.
2. The new item is inserted by `scripts/appcast.py` with the enclosure `https://github.com/Mshardul/MediaGrabber/releases/download/vX.Y.Z/MediaGrabber-X.Y.Z.dmg` and the notes link `https://github.com/Mshardul/MediaGrabber/releases/tag/vX.Y.Z`.
3. The release is created as a draft carrying the DMG, `SHA256SUMS` and `appcast.xml`. A check confirms all three assets are attached. Only then is the release published, so "latest" never points at a release without an appcast.
4. A dry run builds, signs and packages, uploads the appcast as a workflow artifact, and publishes nothing.

Re-runs, dispatch and signing (calls made in review):

- The `overwrite` dispatch input stays. A leftover draft for the same version is deleted at the start of every run, since a draft is never a published state. A published release for the version still stops the run unless `overwrite` is set. With `overwrite`, the previous appcast is downloaded first, then the existing release is deleted and recreated through the same draft-then-publish path. The check that decides whether release notes are generated counts only published releases. Replacing a published release is a deliberate, explicit action; at worst an update already in progress fails its signature check and succeeds on the next check.
- A dispatched run that publishes creates the tag at the dispatched commit when the release is published. The check that the commit is on `main` still applies.
- `MG_SIGN_IDENTITY` is not migrated. It stays unset, the app is signed ad hoc, and the workflow keeps falling back to ad hoc when the variable is unset.
- A dry run without the signing secret still skips the Sparkle signing, as today. The dry run that counts for verification is the one that uploads the appcast artifact; a run that skipped signing does not count.

"Latest" is decided by release creation date, not version number. The appcast is cumulative and Sparkle takes the highest version, so a hotfix cut after a newer release still produces a feed that lists both.

## Carried-over paths

The filtered history contains these, at the destination shown:

- The contents of `apps/media-grabber/` at the repository root.
- Everything under `docs/superpowers/` in the Tools root, at the same `docs/superpowers/` path, except four documents that belong to other tools: `2026-05-25-claude-usage-dashboard-design.md` with its plan, and `2026-08-21-tools-collection-design.md` with its layout plan. Excluding the four is safer than listing MediaGrabber files, since a file renamed in history keeps its early history only if its old name is also listed.
- `.github/workflows/media-grabber.yml` as `.github/workflows/ci.yml`, and `.github/workflows/media-grabber-release.yml` as `.github/workflows/release.yml`.
- `LICENSE`.

Junk committed at any point, such as `.DS_Store` files, is dropped by the filter. The Tools-root tooling files named under Python and tooling are copied and trimmed, not carried.

## Live references to change

Every one of these ends up naming the new repository, repository root paths, and `v` tags:

- `Project.swift`: `SUFeedURL`.
- `scripts/appcast.py`: `FEED`. A test pins that this and `SUFeedURL` are the same address.
- `Sources/GrabberKit/Download/PlayerClientCatalog.swift`: `remoteURL`, and any test that pins it.
- `Makefile`: `PY`, the tag glob and the tag text in `release`.
- `.github/workflows/ci.yml`: no `working-directory`, path filters or `apps/media-grabber/` prefixes; cache keys and `mise` working directory at the root.
- `.github/workflows/release.yml`: the same path changes, the tag handling, the feed steps above, and the release and appcast URLs.
- `Resources/NOTICES.md`: the build recipe pointer for ffmpeg is `scripts/fetch-tools.sh` in `https://github.com/Mshardul/MediaGrabber`. It ships in every build and is the source pointer the licence notice relies on.
- `README.md`: the download link is `https://github.com/Mshardul/MediaGrabber/releases/latest`. The full README is written afterwards.
- `CLAUDE.md`: the Release section (tag, workflow names, feed as a release asset, Pages for the page only, key names), the Python section, and the doc-tree description.
- `docs/development.md`: no `cd apps/media-grabber`.
- `docs/state-flow.md`: paths are relative to the repository root.
- `docs/superpowers/specs/2026-11-04-media-grabber-release-distribution-design.md`: the distribution and updates sections describe the feed as the latest release's asset and the `vX.Y.Z` tag, with no filtered-release-list workaround, and describe `overwrite` as the explicit way to replace a published release.
- The parent design's leaf line names the repository root.
- `roadmap.md` and the parent §12.1: the Phase 20 entry already carries the agreed decisions.

Closed phase specs and plans that mention the old paths are left as they are.

## User-run work

The plan orders all work by dependency and gives exact commands for each step. One constraint shapes the order: the first push carries the edited files, so no workflow on the pushed history holds an old path or tag. Tools stays untouched until verification passes.

The steps that need the user's accounts, keys or git:

- Create the empty `Mshardul/MediaGrabber` repository, public, default branch `main`.
- Filter the history to the carried-over paths into the new local folder, and scan the result for secrets.
- Copy Claude's project memory to the new folder's memory location, then review the two memories that name old paths, one at a time.
- Commit and push.
- Create the Sparkle key pair, back it up, and set the secret and the variable.
- Set Pages' source to "GitHub Actions".
- After verification: remove the app, its two workflows and its documents from Tools, retire the old secret and variable, turn off Pages on Tools if it served only this app, and point the Tools root README at the new repository.

## Verification

The phase is done when all of these hold in the new repository:

- `make lint` is clean and `make test` is green, including the feed-pin test and the appcast script test updated for the release-asset feed and the draft-then-publish order.
- The CI workflow is green on the pushed, edited history.
- A release workflow dry run is green end to end, including signing the disk image with the new key and uploading the `appcast.xml` artifact. A dry run that skipped signing does not count.
- The app built by that dry run has `SUFeedURL` set to the new feed and `SUPublicEDKey` equal to `MG_SPARKLE_PUBLIC_KEY`.
- A search of the repository, excluding closed-phase documents, finds no `Mshardul/Tools`, `mshardul.github.io/Tools`, `media-grabber-v`, `apps/media-grabber` or `../../.venv`.
- Exactly one `MediaGrabber.app` exists on the machine after building through `make` in the new repository.

The live feed cannot be tested until a release exists, so the redirect and the "latest release always carries the appcast" check are the update test in release hardening. The Pages workflow first deploys when the product page adds `site/`; that thread's first task confirms the deploy.

## Left to the builder

- The helper that keeps `Project.swift`'s feed and `appcast.py`'s feed from drifting, as long as a test pins them equal.
- How `appcast.py` treats a version already listed: a re-run for the same version replaces that version's entry, and the builder confirms the script does this.
- The venv bootstrap, such as a `make` target, and the exact ruff and pytest settings kept in the trimmed `pyproject.toml`.
- Pinned versions of the Pages actions, following the major-version pinning the existing workflows use.

## Downstream

- Release hardening is written against the new repository's layout and addresses. It also carries the feed end-to-end check and the `PRIVACY.md` listing of every connection the app makes, including the runtime config fetch.
- The user-facing README and the product page are written after the split, in the new repository.
