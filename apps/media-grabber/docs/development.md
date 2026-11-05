# Developing MediaGrabber

People who use the app should follow [the README](../README.md). This page is for building it.

## Build and run

```bash
brew install mise
cd apps/media-grabber
mise install
make
```

`make` fetches the bundled tools (the first run compiles ffmpeg and takes a while), rebuilds, replaces `/Applications/MediaGrabber.app`, and opens it. Run it again to replace the copy that is already running.

A build you compile yourself is not quarantined. A copy downloaded from a release is. See the README for **Open Anyway**.

## Test and lint

From `apps/media-grabber`:

```bash
make test
make test ONLY=AppUnitTests/SomeSuite
make lint
```

`make test` runs the plugin tests, generates the Tuist project, then the unit tests. One suite is `ONLY=Target/Suite`.

## Where the app writes

- Downloads default to `~/Downloads`. Change one destination in the runway, or the default in **Preferences → Downloads**.
- `~/Library/Logs/MediaGrabber/app.log` is the app log. `jobs/<job-id>.log` is one download transcript. See [PRIVACY.md](../PRIVACY.md).
- `~/Library/Application Support/MediaGrabber/` holds the queue, history, and column layout. Relaunch restores the queue.
- An updated downloader, when one has been accepted, is `~/Library/Application Support/MediaGrabber/bin/yt-dlp`. The copy in the app bundle is used when that file is missing or older.

## Debug flags

`-MGForceOnboarding`, `-MGResetState`, `-MGConcurrencyCap N`.

How the pieces fit: [architecture.md](architecture.md) and [state-flow.md](state-flow.md). What is left to ship: [roadmap.md](../roadmap.md).
