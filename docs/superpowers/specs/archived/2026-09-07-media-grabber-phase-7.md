# YouTube hardening (Phase 7)

**Status:** shipped. Plan:
`docs/superpowers/plans/archived/2026-09-07-media-grabber-phase-7.md`. Parent spec:
`docs/superpowers/specs/2026-08-28-youtube-downloader-mac-design.md` §7.2, §7.8,
§7.9, §12.1.
Phase 2 (shipped): `docs/superpowers/specs/queue-foundation.md`.
Phase 3 (shipped): `docs/superpowers/specs/archived/2026-08-31-media-grabber-phase-3.md`.
Phase 4 (shipped): `docs/superpowers/specs/archived/2026-09-01-media-grabber-phase-4.md`.
Phase 5 (shipped): `docs/superpowers/specs/archived/2026-09-02-media-grabber-phase-5.md`.
Phase 6 (shipped): `docs/superpowers/specs/archived/2026-09-04-media-grabber-phase-6.md`.
Phase 1 (shipped): `docs/superpowers/specs/archived/core-download-pipeline.md`.

Phases 1–6 built the download pipeline, the engine-owned queue and scheduler,
retry / classification, cookies, per-host rate limiting, and the banner / health
strip. Phase 7 is YouTube resilience: a supervised bot-check shield process,
`player_client` rotation across retries, honest format and language pickers
driven by the same YouTube identity the first download will use, and the
YouTube `ErrorClass` emit paths plus chrome.

Everything here is built to its final-app form. `PotProviderProcess`,
`ExtractorContext`, `engine.preview`, the Language runway slot, and the
`potProviderDown` banner case are the shapes the app keeps. Phase 8 playlist
items inherit the runway's language and quality; Phase 10 adds the engine-
freshness chip beside the shield chip; Phase 11 adds the chip-refresh failure
toast. None of those relayout the strip, the banner resolver, or the runway.

UI copy stays plain language: "bot-check shield", "couldn't verify you". Never
"POT", "yt-dlp", or `player_client` in a user-visible string.

---

## 1. Scope

**In this phase:**

- **`GrabberKit/PotProvider/`** — `PotProviderProcess` (child on `127.0.0.1` +
  a free port, `GET /ping` health, restart on crash, stop on `shutdown`) and
  `PotPluginInstaller` (plugin on disk, `--plugin-dirs`).
- **`ExtractorContext`** — plugin dirs, shield base URL if healthy, cookies if
  opted in, `player_client` for this attempt. Built at spawn. Passed to both
  `MetadataProbe` and `YtDlpArguments` so paste and Grab cannot drift.
- **`PlayerClientRotation.default`** — `tv → ios → tv_embedded → mweb →
  web_safari`. Attempt 0 is `tv`; each auto-retry takes the next; the last
  client sticks. `web` and `android` are skipped. `job.playerClientUsed` is set
  at spawn (the Phase 2-shelled field).
- **Engine-owned shield.** `ensureShield()` and `restartShield()`; `shutdown()`
  stops the child. Onboarding still *installs* (pipx, recommended, not
  blocking) and calls `ensureShield()` when that step succeeds. Returning
  launches call `ensureShield()` from `onAppear` / after `revalidate()`.
  `revalidate()` stays deps-only.
- **`engine.preview(url)`** — Home paste uses this instead of a second
  `MetadataProbe`. Same probe instance, same context, first client, same cookie
  policy, respects `blockedProbeHostIDs` and `.networkDown`. No job is created.
  `MediaGrabberApp` stops constructing a duplicate probe.
- **`QueueSnapshot.shieldStatus`** — `running(port:)` / `down` / `missing`.
  `QueueSnapshot.init` gains a defaulted param `shieldStatus: ShieldStatus =
  .missing` (engine always passes a real value; existing fixtures keep
  compiling). `potProviderDown` is **not** a `QueueHaltReason`; the queue keeps
  moving.
- **`EngineTuning`** — `potHealthTimeoutSeconds` (default 2,
  `MG_POT_HEALTH_TIMEOUT`) and `potRestartBackoffSeconds` (default 2,
  `MG_POT_RESTART_BACKOFF`).
- **Probe JSON** — parse `formats` into `formatAvailability`, `videoHeights`,
  `audioTracks`. New stored `let` fields on `MediaMetadata`; init params
  append after `extractor` with defaults. One `-J` call; no second `-F`; no
  client rotation on paste.
- **Runway** — five slots: Link · Type · Format · Language · Save to. Language
  always filled, Video and Audio. Quality picker restricted to this probe's
  offered ladder rungs. Grab still only waits on a resolved link.
- **Preferences (Downloads pane)** — **Audio language** row:
  `YouTube default` | `Original`. No eighth pane. No shield Preferences row.
- **`DownloadRequest.audioLanguage`** — sibling of `kind`: `.unspecified |
  .original | .code(String)`. Old `queue.json` decodes as `.unspecified`.
- **YouTube `ErrorClass` emit + copy** — `botCheck`, `sabrGated`,
  `formatsMissing` on jobs; `potProviderDown` is chrome-only (sentence exists
  for exhaustiveness; nothing emits it on a row).
- **VPN hint** on a `botCheck` row or paste failure when a VPN/utun interface
  is up.
- **HealthStrip** shield chip + live `ChipInteraction.refresh` (`↻` button is
  **new** — the enum case exists and currently renders like `.none`).
  **BannerReason.potProviderDown** last in the resolver, Restart button →
  `restartShield()`. Files: `BannerResolver.swift`, `AppModel+Banner.swift`,
  `HealthStrip.swift`, `MainWindow.swift`.
- **Job log header** records the `player_client` used. `LogEvent` cases for
  shield start / exit / restart — extend exhaustive `key`, `category`, and
  `fields` switches.
- **`screens.html`** — five-slot runway, Downloads language row, shield chip,
  `potProviderDown` banner. design-system §4.2.2 / §4.6 already describe
  Language and Audio language; verify they still match, do not rewrite.

**Implementation notes.** Comments are single-line why only — no `///`.
`DownloadEngineProtocol` fakes that must grow the three new methods:
`Tests/AppUnitTests/Support/AppFakes.swift` `FakeEngine` and the private
`FakeEngine` in `QuitCoordinatorTests.swift` (plus live `DownloadEngine`).
`preview` is stubbable (default `.failure(.malformedOutput)`, matching today's
`FakeMetadataProbe`); `ensureShield` / `restartShield` are no-ops. App-layer
tests that today stub `FakeMetadataProbe` for `resolvePasted` stub
`FakeEngine.preview` instead.

**Deferred (hints in their phase):**

- Chip-refresh **toast** on a failed `↻` — Phase 11 (chip stays amber here).
- Engine-freshness chip — Phase 10 (`HealthController` already appends; this
  phase inserts the shield chip first, engine chip still absent).
- Playlist items inherit the runway's language and quality — Phase 8.
- Remote `player_client` order JSON — parent §13, v1.1.
- Bundled vs external shield binary — parent §10; `PotProviderProcess` is the
  swappable resolver.
- `brew install node` as an onboarding step — not this phase. If `node` (or a
  console-script server) cannot be launched, status is `.missing` and downloads
  proceed degraded.

**Not touched:** Phase 6 rate limiter / circuit / network monitor. Cookie
subsystem (preview *uses* cookies when set; it does not change CookieResolver).
Scheduler loop. Onboarding step *list* (still four steps).

---

## 2. Shared YouTube identity

### 2.1 `ExtractorContext`

`GrabberKit/Download/ExtractorContext.swift`.

```swift
public struct ExtractorContext: Sendable, Equatable {
    public var pluginDirs: [URL]
    public var potBaseURL: URL?          // nil → omit POT extractor-args
    public var playerClient: String?     // nil → omit player_client
    public var cookieArgument: String?

    public static let none = ExtractorContext(
        pluginDirs: [], potBaseURL: nil, playerClient: nil, cookieArgument: nil
    )
}
```

Built at spawn by the engine:

- `pluginDirs` from `PotPluginInstaller` when a private plugin dir exists.
- `potBaseURL` from `PotProviderProcess` only when `shieldStatus ==
  .running`.
- `playerClient` from `PlayerClientRotation.client(forAttempt:)` only when
  `RateHost(urlString:) == youtube` (canonical `"youtube"`).
- `cookieArgument` from the existing `CookieResolver` path (same as today's
  download spawn, including `forceCookies`).

Non-YouTube URLs (archive.org) get plugin dirs if present, no `player_client`,
no POT extractor-args. yt-dlp ignores an unused plugin; we still omit the
YouTube-only flags so job logs stay clean.

### 2.2 `PlayerClientRotation`

`GrabberKit/Download/PlayerClientRotation.swift`. A config constant, not a
Preference.

```swift
public enum PlayerClientRotation {
    public static let `default` = ["tv", "ios", "tv_embedded", "mweb", "web_safari"]

    public static func client(forAttempt attempt: Int) -> String {
        let list = Self.default
        return list[min(max(attempt, 0), list.count - 1)]
    }
}
```

Attempt is the job's existing `attempt` field (0 on first spawn). The last
entry sticks when `attempt` exceeds the list. `web` and `android` are not in
the list.

### 2.3 `YtDlpArguments`

`build` / `redacted` gain `context: ExtractorContext = .none` (defaulted, after
`cookieArgument` or last — existing labeled call sites stay valid;
`concurrentFragments` stays required).

When `pluginDirs` is non-empty: `--plugin-dirs <path>` (colon-joined if
several, same as yt-dlp).

When `potBaseURL` is set: `--extractor-args
youtubepot-bgutilhttp:base_url=<url>`.

When `playerClient` is set: `--extractor-args
youtube:player_client=<client>`. Two `--extractor-args` flags, not a merged
string — yt-dlp treats them as different extractor namespaces.

Cookie flags stay as today. Redaction: cookie spec masked; `base_url` is
loopback and appears verbatim; `player_client` appears verbatim. A
`test_redactedEqualsBuild` with a non-`.none` context passes `context` to both
`build` and `redacted`.

Format selector: see §6.

---

## 3. Shield process

`GrabberKit/PotProvider/`.

### 3.1 `ShieldStatus`

```swift
public enum ShieldStatus: Sendable, Equatable {
    case running(port: Int)
    case down
    case missing
}
```

- `.running` — child is alive and `GET http://127.0.0.1:<port>/ping` returned
  2xx within `tuning.potHealthTimeoutSeconds` (default 2, `MG_POT_HEALTH_TIMEOUT`).
  **New** `EngineTuning` stored properties: `potHealthTimeoutSeconds`,
  `potRestartBackoffSeconds` (default 2, `MG_POT_RESTART_BACKOFF`), read by
  `EngineTuning.resolved()` like the existing `MG_*` keys.
- `.down` — package/plugin was resolved but the process is not healthy
  (crashed, ping failed, not started yet).
- `.missing` — no launchable server (no `node`, no console script, no plugin
  dir). Distinct from `.down` so the chip can stay honest; both are amber and
  both drive the banner.

### 3.2 `PotProviding`

```swift
public protocol PotProviding: Sendable {
    var status: ShieldStatus { get async }
    func ensure() async
    func restart() async
    func stop() async
    var baseURL: URL? { get async }
    var pluginDirs: [URL] { get async }
}
```

Live type: `PotProviderProcess`. Tests inject a fake (no real bind, no
network). `EngineDependencies` gains `potProvider: any PotProviding`.

- **`EngineDependencies.init`** — new param `potProvider: any PotProviding =
  MissingPotProvider()` (reports `.missing`, `ensure`/`restart`/`stop` are
  no-ops). Same pattern as `networkMonitor` defaulting to `AlwaysOnlineMonitor`.
  Existing test `EngineDependencies(` call sites do not change.
- **`EngineDependencies.live(...)`** — constructs the real `PotProviderProcess`
  (and the plugin installer) and passes it in. This is the factory
  `MediaGrabberApp` already calls; it is not a second overload of `init`.

### 3.3 Launch

HTTP server (Brainicism `bgutil-ytdlp-pot-provider`), **not** the per-call
script provider — the chip needs a process to supervise.

Resolver (`PotPluginInstaller.resolveServerLaunch(port:) -> ProcessLaunch?`):

1. An executable named `bgutil-ytdlp-pot-provider` on PATH that accepts
   `--port` / `--host` (pipx console script, if present).
2. Else `node` on PATH (same search paths as `EnvironmentProbe`) plus
   `server/build/main.js` under the plugin install. Candidate roots: pipx
   share, or `~/Library/Application Support/MediaGrabber/bgutil-server/`.
   The exact pipx on-disk layout (`~/.local/share/pipx/venvs/…`) is
   **plan-time discovery**, not a frozen path here — the resolver is injected.
3. Else `nil` → `.missing`.

Bind **only** `127.0.0.1`. Port: prefer **4416** if free (the plugin's
default), else the next free loopback port. Always pass
`youtubepot-bgutilhttp:base_url=http://127.0.0.1:<port>` so a non-4416 bind
cannot silently miss the plugin. `--host 127.0.0.1`.

Health: `GET /ping`. No other endpoints. No token is logged.

Crash: wait `tuning.potRestartBackoffSeconds` (default 2) and `ensure()`
again, cap at 30 s, do not tight-loop. `restart()` is a user intent: stop,
then `ensure()` immediately (no backoff).

`stop()` SIGTERM, then SIGKILL after 2 s if needed. `DownloadEngine.shutdown()`
calls it after cancelling download tasks.

Onboarding: the existing `botCheckShield` step still `pipx install
bgutil-ytdlp-pot-provider` and stays non-blocking. When that step finishes
`.done` (or is `.skipped` because already installed), `AppModel` calls
`engine.ensureShield()`. A `.failed` pipx step does **not** call it; status
stays `.missing`. No fifth onboarding step. No `brew install node`.

### 3.4 `PotPluginInstaller`

Ensures the yt-dlp POT plugin is visible:

Always install/copy the plugin into
`~/Library/Application Support/MediaGrabber/yt-dlp-plugins/` when the resolver
can find a source (pipx share or the GitHub plugin zip already on disk). Always
pass that path as `--plugin-dirs`. Do **not** shell out to `yt-dlp -v` to detect
an existing provider — one private dir is the whole story.

Filesystem is injected. Tests never hit the network or pipx.

---

## 4. Engine seams

### 4.1 New intents

`DownloadEngineProtocol` gains:

```swift
func preview(_ url: String) async -> Result<MediaMetadata, MetadataError>
func ensureShield() async
func restartShield() async
```

`preview`:

- If `queueHalt == .networkDown` → `.failure(.network)`.
- If `RateHost` is in `blockedProbeHostIDs` → `.failure(.hostBlocked)` (new
  `MetadataError` case). Copy: "This site is cooling down. Try again in a
  moment."
- Else `CookieResolver` (prefs, not `forceCookies`) + `ExtractorContext` with
  `playerClient` for attempt 0 + current shield URL → `dependencies.probe`.
- Does not set `probeInFlight` (that flag is for *job* probes). Serialization
  is the existing `MetadataProbe` tail-chain — Home and a job probe never
  overlap inside yt-dlp.
- Does not enqueue a job, does not emit a queue snapshot besides whatever the
  probe already logs.

`AppModel` already holds `engine`. `resolvePasted` calls `engine.preview`.
`AppModel.init` drops the `probe: MetadataProbing` parameter and the stored
property. `MediaGrabberApp` no longer constructs `MetadataProbe`;
`EngineDependencies.live` remains the single owner. `AppModelTestHelpers.makeModel`
drops `probe:`; tests that stubbed `FakeMetadataProbe` for paste stub
`FakeEngine.preview` instead (`stubPreview` / equivalent).

`ensureShield()` / `restartShield()` delegate to `potProvider`, then
`emitSnapshot()` so the chip/banner update. They do not call
`evaluateSchedule()` (shield is not a halt).

`onboardingFinished()`: `revalidate()` then `ensureShield()`.
`onAppear` when onboarding is not needed: `ensureShield()`.

### 4.2 Snapshot

`QueueSnapshot` gains `shieldStatus: ShieldStatus`. The memberwise init adds
**`shieldStatus: ShieldStatus = .missing`** — a defaulted parameter, not a
fixture sweep. `DownloadEngine.buildSnapshot()` always passes the live value.
Existing `QueueSnapshot(...)` call sites keep compiling; tests that care set
it explicitly.

`JobSnapshot.playerClientUsed` is populated at spawn from the context's
`playerClient`. Unchanged for non-YouTube (stays `nil`).

### 4.3 Spawn

`launchDownload` builds `ExtractorContext` with
`PlayerClientRotation.client(forAttempt: job.attempt)`, sets
`job.playerClientUsed`, passes context into `YtDlpArguments.build`. The
in-engine job probe (`launchProbe`) uses the same context with attempt 0.

---

## 5. Probe JSON — formats and languages

The probe stays one `-J --no-playlist --no-warnings --no-update` call, plus
the `ExtractorContext` flags. No `--flat-playlist` this phase (Phase 8).

`MetadataError` gains `.hostBlocked` (preview short-circuit only; the probe
process itself never returns it). Existing cases are unchanged.
`AppModelDialogs.probeErrorMessage` is an exhaustive switch — add
`.hostBlocked` → "This site is cooling down. Try again in a moment." (compile
break if skipped). The VPN rewrite of the `.botCheck` arm is a separate edit
in the same function (§8.3).

### 5.1 `MediaMetadata` additions

```swift
public enum FormatAvailability: Sendable, Equatable {
    case unknown
    case listed
}

public struct AudioTrack: Sendable, Equatable, Identifiable, Hashable {
    public let id: String
    public let languageCode: String? // nil → synthetic Default
    public let label: String
    public let isOriginal: Bool
    public let isDefault: Bool
}
```

`id` and the dedup key are the same formula:

- a real track: `"\(languageCode ?? "und")|\(isOriginal ? "orig" : "dub")"`
- synthetic Default only: `"default"`

`MediaMetadata` stays all `public let`. Extend the existing explicit init —
append these parameters **after `extractor`**, defaulted, so
`FakeMetadataProbe.success(...)` and `MediaMetadata(title:duration:…)` keep
compiling:

```swift
formatAvailability: FormatAvailability = .unknown,
videoHeights: [Int] = [],
audioTracks: [AudioTrack] = []
```

Do **not** make the new fields `var`. `.unknown` / empty arrays are the
defaults.

- `videoHeights` — distinct heights where `vcodec` is present and not
  `"none"`, sorted descending
- `audioTracks` — see §5.2

`.unknown` — no usable `formats` array (missing, unparseable, or empty in a
way we cannot trust). Runway does **not** restrict quality; Language is the
synthetic Default.
`.listed` — we parsed `formats`. `videoHeights` may be empty (audio-only).
Paste still succeeds.

### 5.2 Parse rules

From each `formats[]` element:

| Field | Use |
|---|---|
| `height` (number) | video height if `vcodec` is a real codec |
| `vcodec` | `"none"` / missing → not a video format |
| `acodec` | `"none"` / missing → not an audio format |
| `language` | ISO code for the track |
| `format_note` | label + original detection |
| `language_preference` (number) | default-track election |
| `audio_track.display_name` (optional object) | preferred label |

**Video heights:** unique `height` values from video formats.

**Audio tracks:** from audio formats. Dedup by `id` (§5.1 formula). Two
formats that share language + `isOriginal` collapse to one track.

- `isOriginal` — `format_note` contains `"original"`
  (case-insensitive), or `language` equals top-level `original_language` when
  that field is present.
- `isDefault` — among audio formats, the one with the highest
  `language_preference`; ties break to the first listed. This is YouTube's
  default track, **not** highest bitrate.
- `label` — `audio_track.display_name` if present, else a readable
  `format_note` if it is not a technical tag, else the language code, else
  `"Default"`. Original tracks append `" (original)"` when the label does not
  already say so.

If `.listed` and no audio format has a language code or original/default
mark, `audioTracks` is one synthetic track: `id: "default"`,
`languageCode: nil`, `label: "Default"`, `isOriginal: false`,
`isDefault: true`.

### 5.3 `formatsMissing` is a download failure

A thin or audio-only probe list still fills the runway. The download
classifier emits `ErrorClass.formatsMissing` from stderr (requested format
not available, audio-only when Video was asked, images-only that is not
`sabrGated`). Paste never returns `MetadataError` for a thin list.

### 5.4 Fixtures

`Tests/GrabberKitTests/Fixtures/`:

- YouTube `-J` with original + dubbed audio and a 1080 max height
- YouTube audio-only / no video formats (`.listed`, empty `videoHeights`)
- archive.org-style blob with no languages (synthetic Default)
- blob with no `formats` key (`.unknown`)

`MetadataProbe.decodeForTest` covers these. Engine tests keep using
`FakeMetadataProbe.success` (unknown formats).

---

## 6. Request, format selector, persistence

### 6.1 `AudioLanguage`

```swift
public enum AudioLanguage: Sendable, Equatable, Codable {
    case unspecified
    case original
    case code(String)
}
```

`DownloadRequest` gains `audioLanguage: AudioLanguage = .unspecified`. Custom
`init(from:)` defaults a missing key to `.unspecified` so old `queue.json`
loads. `PersistedJob` needs no extra field — it already embeds `request`.

### 6.2 Format selector

`YtDlpArguments.formatSelector` keeps today's fallback chain and splices
language onto every `ba` token:

- `.unspecified` — today's string, no language filter.
- `.code("ja")` — `ba[language=ja][ext=m4a]` / `ba[language=ja]` first, then
  the unfiltered `ba` fallbacks.
- `.original` — `ba[format_note*=original][ext=m4a]` /
  `ba[format_note*=original]` first, then unfiltered `ba`. The selector cannot
  express §5.2's `language == original_language` signal; that mark is
  probe/seed only. A miss still downloads via the unfiltered `ba` fallback.

Audio-only (`-x --audio-format`): add `-f ba[…]/ba` with the same language
filter before `-x`.

### 6.3 Preferences

```swift
public enum AudioLanguagePolicy: String, Codable, Sendable, CaseIterable {
    case youtubeDefault
    case original
}
```

- `defaultAudioLanguagePolicy` — key `mg.defaultAudioLanguagePolicy`, default
  `.youtubeDefault`. Downloads pane row **Audio language**, helper: "Used when
  this video has that kind of track." `SkinnedSegment` — YouTube default /
  Original.
- `lastAudioLanguage: LastAudioLanguage?` — key `mg.lastAudioLanguage`.

```swift
public enum LastAudioLanguage: Codable, Sendable, Equatable {
    case original
    case code(String)
}
```

Written **on Grab only**, not on picker change:

- user picked the original track → `.original`
- user picked a coded non-original track → `.code(lang)`
- user picked synthetic Default → do not write (leave previous last)

`resetToDefaults` clears both new keys. `ownedKeys` gains them.

Preferences **Video quality** stays the full ladder. It is a policy, not this
video's catalog.

---

## 7. Runway seed and chrome

### 7.1 Slots

Link · Type · Format · **Language** · Save to. Language is a `SkinnedPicker`,
always filled, shown for Video and Audio. Format stays resolution (video) or
M4A/MP3 (audio). Grab disabled only until the link is resolved and
downloadable; Language cannot be empty.

### 7.2 Offered quality rungs

Fixed ladder: `2160, 1440, 1080, 720, 480`, plus `Int.max` (Best available).

```swift
enum VideoQualityOptions {
    static func offered(from meta: MediaMetadata) -> [Int]
    static func seed(last: Int?, defaultHeight: Int, offered: [Int]) -> Int
}
```

- `.unknown` → full ladder + Best.
- `.listed` with `max(videoHeights) = H` → ladder rungs `<= H`, plus Best.
  Lower caps stay choosable.
- `.listed` with no video heights → `[Int.max]` only.

Seed: `last` if that value is in `offered` → else `defaultHeight` if in
`offered` → else the highest numeric offered rung, else `Int.max`.

`RunwayView.qualityLadder` already maps `Int.max` → "Best available".
`VideoQualityOptions.offered` feeds that same map — do not invent a second
label table.

### 7.3 Language seed

```swift
enum AudioLanguageSeed {
    static func pick(
        tracks: [AudioTrack],
        last: LastAudioLanguage?,
        policy: AudioLanguagePolicy
    ) -> AudioTrack
}
```

Order:

1. `last == .original` and an `isOriginal` track exists → that track.
2. `last == .code(x)` and a track with `languageCode == x` exists → that
   track (prefer `isOriginal == false` if last was a dub and both exist,
   else any `x`).
3. Policy `.original` and an original track exists → original.
4. The `isDefault` track.
5. Synthetic Default (always exists once §5.2 has run; if `tracks` is empty,
   the picker still shows Default and Grab sends `.unspecified`).

Map track → `AudioLanguage`: nil code → `.unspecified`; `isOriginal` →
`.original`; else `.code(code)`.

### 7.4 When seed runs

`runwaySeed(from:)` still seeds Type / Format-codec / folder from last ??
default on first appear.

On each **successful** `preview`, Home re-seeds **only** `videoHeight` and
the language pick from §7.2 / §7.3 against that metadata. Type and Save-to
keep the current runway values. An in-progress picker change is discarded on
a new paste.

`RunwayOverrides` gains `audioLanguage`. `RequestBuilder` writes it onto
`DownloadRequest`. `AppModel.grab` writes `lastAudioLanguage` as in §6.3 and
keeps writing `lastVideoHeight` / type / format / folder.

### 7.5 design-system / mockup

design-system §4.2.2 and §4.6 already list Language and the Audio language
row. Verify at close. `screens.html` still needs the five-slot runway, the
Downloads row, the shield chip, and the `potProviderDown` banner.

---

## 8. Failures

### 8.1 Classifier

`ErrorSignatures.table` gains, **before** geo/private/unavailable is fine
(first match still wins), YouTube-specific groups. Probe's private
`botCheckSignatures` **move into this table** so paste and Grab agree.

`MetadataProbe.classify` returns `MetadataError`; the table returns
`ErrorClass`. Bridge: after the existing URL/unsupported/unavailable checks,
call `ErrorSignatures.firstMatch(in:)` and map `.botCheck` →
`MetadataError.botCheck` (other `ErrorClass` cases from the table that the
probe already handles — `.unavailable` / `.private` / `.geoBlocked` — stay on
the existing `unavailableSignatures` path). Delete the private
`botCheckSignatures` array.

`sharedUnavailableSignatures` filters `ErrorSignatures.table` to
`.unavailable` / `.private` / `.geoBlocked` only. New `.botCheck` /
`.sabrGated` / `.formatsMissing` rows **do not** leak into that list. Do not
widen the filter.

**`botCheck`** — existing probe strings: `"page needs to be reloaded"`,
`"confirm you're not a bot"`, `"Sign in to confirm"`, `"unable to extract
uploader id"`, `"HTTP Error 403"`, `"This content isn't available, try again
later"`. (403 is already a bot-check signal on YouTube; a non-YouTube 403
that hits this substring still classifies as `botCheck` — acceptable, the
sentence is still honest.)

**`sabrGated`** — `"only images are available"`, `"sabr"`. First match in
this group wins over `formatsMissing`. Fixture:
`ytdlp-stderr-sabr.txt`.

**`formatsMissing`** — `"requested format is not available"`. Kind-aware extra:
when `kind` is `.video` and stderr contains `"audio only"` as the reason no
video stream was picked. That extra lives in `classifyExit` (it has the job),
not in the pure substring table. Fixture: `ytdlp-stderr-formats-missing.txt`.

`potProviderDown` is **never** assigned to a job. A download that fails
because the shield is down classifies as `botCheck` / `formatsMissing` /
`sabrGated` as the stderr warrants. The banner already explains the
degradation.

### 8.2 Presentation and auto-retry

`FailurePresentation` has no auto-retry field. Auto-retry is
`ErrorClass.isAutoRetryable`: add `.botCheck` and `.formatsMissing` to that
switch; `.sabrGated` and `.potProviderDown` stay in the `default: false` arm.

Copy and row actions (edit `fixedSentences`, `noRetryKeys`, `cookieRetryKeys`):

| key | sentence | `noRetryKeys` | `cookieRetryKeys` |
|---|---|---|---|
| `bot_check` | Couldn't verify you. Try again, or add browser cookies in Preferences. | no | **add** |
| `sabr_gated` | YouTube isn't offering a downloadable video for this link. | **add** | no |
| `formats_missing` | The quality you picked isn't available for this video. | no | **add** |
| `pot_provider_down` | Bot-check protection is offline. | no (retry only) | no |

`bot_check` / `formats_missing` stay off `noRetryKeys` so they keep the default
`.retry`, then pick up `.retryWithCookies` from `cookieRetryKeys`. `sabr_gated`
is added to `noRetryKeys` (no retry). `pot_provider_down` is on neither set →
retry only.

Auto-retry walks `PlayerClientRotation` because `attempt` increments on each
auto-retry (existing Phase 4 path). After `maxAutoRetries`, the row offers the
actions above.

`FailurePresentationTests` adds the four cases to its exhaustive list and
asserts `isAutoRetryable` / `offeredActions` match this table.

### 8.3 VPN hint

`GrabberKit/Network/VPNDetecting.swift` (or beside RateLimiting):

```swift
public protocol VPNDetecting: Sendable {
    var isVPNActive: Bool { get }
}
```

Live impl: `getifaddrs`, treat an interface as VPN if its name has prefix
`utun`, `ipsec`, `ppp`, or `wg`. No packet is sent. Injected; tests pass a
stub.

This is **display-only**. `FailurePresentation.for(.botCheck)` stays the
no-VPN sentence. `RowStatusText` and `AppModelDialogs.probeErrorMessage` use:

- VPN off → the table sentence.
- VPN on → "Couldn't verify you. Turn off your VPN, or add browser cookies in
  Preferences."

Paste `botCheck` drops the current brew-upgrade line (Phase 10 owns engine
freshness).

### 8.4 Probe mapping

`DownloadEngine+Helpers.swift` `errorClass(for: MetadataError)` is exhaustive.
Add `.hostBlocked` → `.rateLimited()` so a job probe that somehow ran during
cooldown still takes the rate-limit path. Home preview never creates a job on
`.hostBlocked`.

---

## 9. Banner and HealthStrip

### 9.1 Banner

```swift
enum BannerReason: Equatable {
    case depMissing, networkDown, circuitOpen, potProviderDown
}
```

Priority: `depMissing > networkDown > circuitOpen > potProviderDown`.

`AppModel.activeBannerReasons` (`AppModel+Banner.swift`) unions halt-derived
reasons with `snapshot.shieldStatus != .running` → `.potProviderDown`. Today
it keys off `QueueHaltReason` only. `bannerPriority` in `BannerResolver.swift`
appends `.potProviderDown` last. `depMissing` is still onboarding, not a
banner (`bannerCopy` returns nil).

`potProviderDown` copy: "Bot-check protection is offline — some downloads may
fail or be low-res." Button **"Restart"** → `engine.restartShield()`.

### 9.2 Shield chip

`HealthController.update` prepends a shield chip (before online), reading
`snapshot.shieldStatus`:

- `.running` — id `"shield"`, label `"shield"`, dot `.ok`, interaction
  `.none`
- `.down` / `.missing` — label `"shield · offline"`, dot `.attention`,
  interaction `.refresh`

`ChipInteraction.refresh` **already exists** and is currently grouped with
`.none` (not a button). This phase splits that arm: `.refresh` is a button
with a trailing `↻`. `HealthStrip` gains `onRefresh: (HealthChip) -> Void`.
`MainWindow` changes from `HealthStrip(chips:)` to pass the closure.
`AppModel` maps a `"shield"` refresh to `restartShield()`.

Chip-refresh **toast** is Phase 11. A failed restart leaves the chip amber;
the banner stays up.

---

## 10. Logs

`LogEvent` gains:

- `shieldStarted(port: Int)`
- `shieldExited(code: Int32)`
- `shieldRestarted(reason: String)` — `"crash"` or `"user"`
- `shieldMissing`

Extend the exhaustive `key`, `category`, and `fields` switches for all four
(`jobID` already has `default: nil`). Category: `.deps` (or `.engine` if
`.deps` does not fit the existing use — pick `.deps` for start/exit/missing,
`.engine` for restart-from-user is also fine; **one choice: all four
`.deps`**).

`JobLog.writeHeader` gains a `player_client:` line (value or `-`).
`processLaunched` redacted argv already includes the extractor-args.

`playerClientUsed` remains the table "Client used" column; it starts showing
real values for YouTube jobs.

---

## 11. Testing

No real network, no real port bind, no pipx, no node in unit tests.

| Suite | Covers |
|---|---|
| `ExtractorContext` / `YtDlpArgumentsTests` | plugin-dirs, POT URL, player_client, language spliced into `-f`, YouTube-only flags absent for a non-YouTube URL |
| `PlayerClientRotationTests` | attempt 0…n, stick on last |
| `PotProviderProcessTests` | fake process: ensure → running, ping fail → down, resolve nil → missing, restart, stop |
| `MetadataProbeTests` | fixtures in §5.4; ExtractorContext appears in argv; `hostBlocked` is engine-side not probe-side |
| `EnginePreviewTests` | networkDown, blocked host, success uses attempt-0 client + cookies; no job enqueued |
| `EngineShieldTests` | snapshot.shieldStatus; restart emits snapshot; shutdown stops; missing is not a halt |
| `EngineRetryClientTests` | botCheck auto-retry increments client; sabrGated does not auto-retry |
| `ErrorSignatures` / `FailurePresentationTests` | four YouTube sentences + actions + auto-retry set |
| `VPNCopyTests` / `RowStatusText` | VPN on/off botCheck sentences |
| `BannerResolverTests` | potProviderDown last; Restart action |
| `HealthControllerTests` | shield first; ↻ only when amber |
| `RunwaySeedTests` / `VideoQualityOptionsTests` / `AudioLanguageSeedTests` | seed order, unknown vs listed, last discarded on new paste |
| `RequestBuilderTests` / `PreferencesTests` | audioLanguage round-trip, policy default, reset |
| `DownloadRequestTests` | missing JSON key → unspecified |
| `JobLogTests` | player_client header line |
| `OnboardingInstallerTests` | unchanged: pipx failure does not block Home |

`FakePotProvider`, `FakeVPNDetector`, `MissingPotProvider`. `QueueSnapshot`
init default covers fixtures; tests that assert the chip set `shieldStatus`
explicitly.

Lint: `mise exec -- swiftformat --lint .` and `swiftlint lint --strict`.
Full suite: `MediaGrabber-Workspace`. Comments: single-line why only, no `///`.

### 11.1 Manual smoke

- Onboarding: skip shield → Home loads, chip `shield · offline`, banner with
  Restart; archive.org URL still downloads.
- Shield installed: chip green `shield`; paste a YouTube URL → Language slot
  filled, quality rungs match the probe; Grab; Client used column shows `tv`
  (or the winner).
- Preferences Audio language = Original; paste a dubbed video → original
  selected; change Language; Grab; next paste of a video that has original
  keeps original.
- Force shield down (kill the child) → banner + amber chip; ↻ brings it
  back; in-flight downloads are not paused.
- Bot-check row (if reproducible) shows the sentence; with VPN on, the VPN
  variant.

---

## 12. Parent, design-system, backlog deltas

Living docs must match this spec (no changelog framing). Parent and
design-system **Language / Audio language / shield** copy was updated in the
design pass; the implementation-close task **verifies** they still match,
and fills `screens.html`. Do not rewrite design-system §4.2.2 / §4.6 from
scratch.

**Parent `2026-08-28-…-design.md`** — verify §5.2 / §5.3 / §7.2 / §7.8 /
§12.1 Phase 7 / §12.2 still match this spec after code lands.

**design-system.md** — verify §4.2.2 five slots and §4.6 Audio language row.

**`apps/media-grabber/ticket-backlog.md`** — already matches; verify at close.

**`screens.html`** — Home runway with Language; Downloads pane row; shield
chip; `potProviderDown` banner. This is the remaining mockup delta.

Phase 6 still exists in both `docs/superpowers/specs/` and
`docs/superpowers/specs/archived/` (same for its plan). Pre-existing clutter;
this phase does not duplicate Phase 7 into `archived/` until it ships.

---

## 13. Out of scope

Remote rotation JSON; bundled shield Mach-O; script-provider fallback as a
second code path; a Preferences toggle to disable the shield; a fifth
onboarding step; `brew install node`; changing Phase 6 halt semantics;
playlist expansion; diagnostics report-card rows (Phase 10 reads
`shieldStatus`).
