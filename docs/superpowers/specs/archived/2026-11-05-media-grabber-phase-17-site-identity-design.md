# Phase 17 — Site / identity maturity

YouTube still fails in ways the app explains poorly, and the bot-check helper is one local process with a player-client list baked into the binary. This phase makes the explanation true, lets the client order change without an app release, and lets a chosen browser apply to one site instead of every site. The generic download flow stays the flow for every site.

## Goals

- Every user-visible sentence is true for the cause that actually fired it, is plain, and offers one action that the user can reach again later.
- The YouTube player-client order can change without shipping a new app. A client that just failed a bot-check is not reused for that job's remaining attempts.
- The bot-check helper stays optional. Someone who already has the downloader tools, and therefore never sits through setup, still gets one chance to turn the helper on.
- A browser chosen in Preferences can apply to every site, or only to sites the user names. Cookies are still read only from that one browser.

## Non-goals

- A second bot-check provider, a remote POT server, or more than one local helper process.
- Scanning browsers the user did not choose, reading cookie values into the app, or recommending a browser.
- Subtitles, embed, a menu bar, schedules, stats, bandwidth graphs, per-skin light and dark, or a compact breakpoint. Those leave this phase. On approval they move from the Phase 17 roadmap bullet into `future-ideas.md`. They are not scheduled.
- The visual-fidelity ticket board. Those rows stay on `tickets.md` and are not this phase.
- Product name, app icon, Sparkle, notarization, or bundled yt-dlp. Those stay Phase 19.
- The seven review decisions from 2026-11-05 (launch flash of the YouTube-check line, rejecting unsafe remote client names, named-site list wording, `state-flow.md` catching up, the full copy audit, removing `client(forAttempt:)`, and the jargon test reading real chip labels). Those are Phase 18, written in full on `roadmap.md`.

## Calls made here

These are the writer's calls. They are not prior decisions from the parent spec.

- The client-order file is a JSON file in this repo, fetched from the raw URL of the default branch. No new host.
- The fetch happens when a YouTube probe or download is about to pick a client and the saved copy is older than 24 hours. It does not run on every launch.
- The sign-in mode is stored on its own, separate from the site list. Default is All sites. An empty Only these sites list sends the browser nowhere and does not flip the mode back.
- The helper nudge is one dismissible Home line, stored so it stays dismissed. It is not a modal and it does not block Home.
- Zoom's passcode path stays as it is. This phase does not add a helper for any named site besides the YouTube client rotation above.

## 1. Copy

Walk every sentence the app can show: row remarks, probe errors, banners, toasts, dialogs, onboarding, the helper setup sheet, Preferences, About, and Diagnostics. For each sentence record the surface, the trigger, the exact string, and four verdicts:

1. True for the trigger that shows it, not for a nearby trigger.
2. Plain. No command, tool name, or jargon.
3. Says what is wrong.
4. Where a fix exists, one action (a button or a link to the place the fix lives). That action still exists after the message is gone.

Raw installer or downloader text stays behind a collapsed Details control. It is never the message.

Output of the walk is a table in `apps/media-grabber/docs/copy-audit.md`. Each row that fails a verdict is fixed in the same phase, and a test pins that trigger to that sentence. Existing bot-check tests stay: a missing helper on YouTube does not tell the user to sign in, and a non-YouTube bot-check does not blame the helper.

## 2. The helper stays optional

`isReadyForDownloads` stays "yt-dlp and ffmpeg are present." A missing helper does not send the user back through onboarding and does not stop the queue.

When onboarding is already complete and the helper status is `.missing`, Home shows one line: the YouTube check is not set up, with a button that opens the existing setup sheet. Dismissing the line persists. The line does not return. A later YouTube bot-check still uses the cause-specific failure sentence and its own action. The line is absent when the helper is `.running` or `.down`. `.down` keeps today's chip and banner.

## 3. Player clients

`PlayerClientRotation.default` remains the bundled order: `tv`, `ios`, `tv_embedded`, `mweb`, `web_safari`.

The remote file is `apps/media-grabber/config/player-clients.json`:

```json
{
  "playerClients": ["tv", "ios", "tv_embedded", "mweb", "web_safari"]
}
```

The app requests that file from the raw GitHub URL of the repository's default branch. A response is used only when it is a JSON object whose `playerClients` value is a non-empty array of non-empty strings. Anything else, including a network failure, keeps the newest valid saved copy, then the bundled order.

The saved copy and the time it was fetched live in the app's support directory. Tests supply the response through a fake fetcher. No test opens a network connection.

Picking a client for attempt N uses the active order and skips any client this job has already burned. A YouTube exit classified as a bot-check burns the client that attempt used. When every client in the order is burned, the attempt uses the last client in the order, which is today's clamp. A successful download does not un-burn clients for other jobs. The burned set is on the job, in memory, and is not persisted.

POT is attached on the same rule as today: the helper status is `.running` and the host is YouTube. The chosen client does not change that rule.

## 4. One helper process

`ShieldStatus` stays `running(port)` / `down` / `missing`. This phase does not add a provider list, a second process, or a remote POT URL. Client rotation is the rotation. The parked "provider pool" is satisfied by keeping the single local helper as the only provider and recording that a second provider is out of scope above.

## 5. Sign-in scope

Cookie independence still holds. The app reads cookies only from the one browser the user chose. It does not look at any other browser. It does not store cookie values. Logs stay redacted.

Preferences gains one control on the sign-in pane: "Use sign-in for" with two choices. The choice is its own stored value. The site list does not imply the choice.

- **All sites.** Default. A chosen browser is sent on every probe and download. The list is ignored. This is the current standing consent. A user who never touches the control sees no change.
- **Only these sites.** The chosen browser is sent only when the link's site is on the list. Every other site stays cookie-less. An empty list sends the browser nowhere. Removing the last site leaves the choice on Only these sites.

The list stores site keys the app already uses for rate limiting (`RateHost.canonical`), not raw URLs. It is edited on that pane.

A failure that earns a sign-in hint adds a site only in Only these sites mode, and only through a confirmation that names the site. Confirm adds the site and restarts the held job. Cancel drops the held retry. The row click alone does not add the site. Adding a site never switches All sites over to Only these sites. When the mode is already All sites and a browser is chosen, cookies were already sent, so there is no add step. When no browser is chosen, today's retry-with-sign-in flow is unchanged: the user picks a browser, and leaving the picker without a choice drops the held retry.

The hint sentence names the site when the failure earns a sign-in hint. It does not name a browser the user did not choose. Firefox profile listing stays limited to the chosen Firefox installation.

## 6. Tests

- Copy: one assertion per cause that has its own sentence, including the helper-missing YouTube case, the non-YouTube bot-check, a cooling site, and a paused site.
- Client order: a valid payload replaces the bundled order; an invalid payload and a thrown fetch keep the previous order; a stale saved copy is refreshed; a fresh saved copy is not fetched again.
- Burned clients: a bot-check on `tv` makes the next attempt of that job use the next client; a second job starts at the first client again; exhausting the order uses the last client.
- Sign-in scope: All sites sends the browser on a non-YouTube probe and ignores the list. Only these sites sends it for a listed site and omits it for an unlisted site, including when the list is empty. Removing the last site does not change the mode. The default preference is All sites. A failure on an unlisted site in Only these sites mode adds that site and restarts only after confirm; cancel leaves the list unchanged and does not restart. A failure while All sites is selected does not change the mode.
- Nudge: shown only when onboarding is complete and the helper is `.missing`; dismissal hides it across a new model; `.running` hides it.

## 7. On approval

Update `roadmap.md`, `CLAUDE.md`, the parent spec §12.1 Phase 17 bullet, and `docs/state-flow.md` §4 so they match this document. Move the optional extras sentence into `future-ideas.md`. Do that in the same change as the plan, before implementation.
