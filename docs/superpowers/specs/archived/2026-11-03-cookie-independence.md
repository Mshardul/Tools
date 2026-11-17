# Cookie independence

MediaGrabber works without any sign-in. Browser cookies enter a download only when the user has already chosen a browser, or when a failure proves a sign-in is what the link needs and the user chooses to supply one.

## 1. Principles

- Nothing in onboarding, the add flow, or the first run asks for a login, a browser choice, or cookies.
- Every probe and download starts cookie-less unless the user has already chosen a browser in Preferences.
- A chosen browser is the user's standing consent: it is used for every probe and download.
- The app reads cookies only from the browser the user chose. It never inspects, detects, or reads any other browser's data.
- Cookie contents never leave the Mac except inside the request yt-dlp makes to the site being downloaded from, and are never stored, logged, or reported by MediaGrabber.

## 2. Cookie state

Exactly one of two states applies, derived from the Preferences browser choice.

| State        | Meaning             | Probe / download                 |
| ------------ | ------------------- | -------------------------------- |
| Unconfigured | No browser chosen   | Cookie-less                      |
| Configured   | A browser is chosen | Runs with that browser's cookies |

There is no per-job cookie override. A job runs with the cookies of the configured browser or with none.

## 3. Failure analysis

A failure earns a sign-in hint only when a sign-in can plausibly fix it. The class and host decide.

| Failure | Sign-in hint |
| --- | --- |
| Age-restricted | Yes |
| Private or members-only | Yes |
| Bot-check on YouTube | Yes |
| Bot-check on any other host (including a bare HTTP 403) | No |
| Quality not available | No |
| Rate-limited, circuit open | No |
| Geo-blocked, unavailable, network, disk, permission, incomplete, dependency, unknown | No |

A cookie-read failure belongs to the Configured state only. It names the chosen browser and offers no sign-in hint.

## 4. Surfaces

### 4.1 Download row failure

- A row whose failure earns a hint says so in one plain sentence that the link may need a sign-in.
- Unconfigured: the row offers Retry with cookies. The action opens the Preferences browser picker; once the user picks a browser the held job restarts with it. Leaving the picker without a choice drops the held retry.
- Configured: cookies were already used, so the row does not offer Retry with cookies. The sentence tells the user to check that the chosen browser is signed in to the site.

### 4.2 Paste-time probe failure

- The error message carries the same hint sentence as the row for the same failure.
- The probe offers no action; the user pastes again after choosing a browser in Preferences.

### 4.3 Banners and shared copy

- The circuit-open banner and every rate-limit sentence never mention cookies.
- The bot-check sentence mentions signing in only for YouTube.
- All copy says "sign in" and names the site generically; no copy says "YouTube sign-in" outside YouTube-specific failures.

### 4.4 Preferences

- The pane is titled and worded for any site that needs a sign-in.
- The browser picker, Full Disk Access row, Firefox profile row, and Test sign-in remain the only places cookies are configured and verified.
- Test sign-in confirms the app can read the chosen browser's cookies; it does not claim a sign-in on any particular site.

## 5. Privacy invariants

- **Storage.** Preferences persist only which browser was chosen. No cookie value, cookie file, or derived token is written by the app. Persisted jobs carry no cookie state.
- **Logs.** The yt-dlp command line shows the cookie option with its value redacted. Job logs, the app log, and the diagnostic bundle redact `Cookie` and `Set-Cookie` header values and any field whose key contains "cookie". Only counts ("Extracted N cookies") may appear.
- **Network.** The app has no endpoint that receives cookies. yt-dlp sends them to the site being downloaded from, as the browser would.
- **Telemetry and reports.** No crash report, diagnostic bundle, or share path includes cookie data.
- **Consent.** Any feature that reads browser data must be explicit, user-initiated, scoped to the one browser the user names, and satisfy every invariant above.

## 6. Deferred decisions

Sign-in recommendations for popular sites, consent-based cookie discovery, and per-site cookie scoping are owned by the site and identity phase in the roadmap.
