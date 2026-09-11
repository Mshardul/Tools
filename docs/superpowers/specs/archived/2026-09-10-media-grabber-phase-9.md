# Add flows (Phase 9)

**Status:** shipped.

**Plan:** `docs/superpowers/plans/archived/2026-09-10-media-grabber-phase-9.md`.  
**Parent:** `docs/superpowers/specs/2026-08-28-youtube-downloader-mac-design.md`
§12.1 Phase 9.  
**Prefs (already shipped):** `Preferences.detectClipboardLinks` (default
`true`) — Downloads pane toggle.

**Out of this phase:** Share Extension —
`docs/superpowers/specs/2026-09-10-media-grabber-share-extension-STUB.md`.
Browser extensions (Chrome/Safari) are separate backlog; they should call
this phase’s URL scheme when they exist.

---

## 1. Goal

Every Phase 9 URL ingress lands in the **same Home field** and continues
through today’s `resolvePasted` → probe / playlist picker → Grab path. No
second download pipeline.

---

## 2. Ingresses

| Ingress | This phase |
|---|---|
| Clipboard sniff | Yes |
| Drag URL/text onto window or Dock | Yes |
| Services (“Download with MediaGrabber”) | Yes |
| Custom URL scheme | Yes |
| Share sheet / Share Extension | No (sibling stub) |
| Browser extensions | No (backlog) |

---

## 3. Idle vs busy

One policy for every Phase 9 ingress:

- **Idle** → put the URL in the Home field and start probe (no confirm).
- **Busy** → skinned confirmation via `AppModel.confirm`, then fill + probe
  only if confirmed.

Home is **busy** when any of these hold:

- the Home field is non-empty, or
- `isProbing`, or
- the playlist picker is presented

Jobs already in the queue do **not** make Home busy.

---

## 4. Offer UI

Busy-path offer uses the existing skinned confirmation dialog host
(`ConfirmationRequest` / `AppModel.confirm`) — same family as duplicate
submit and playlist cancel-all. Not an inline Home row; not
`WarningBanner`.

Copy:

- Title: `Grab this link?`
- Message: the candidate URL (full string)
- Confirm: `Grab`
- Cancel: `Not now`
- `suppressionKey`: `nil` (ask every busy-path time)

---

## 5. Link extraction

Ingress takes the first `http://` or `https://` URL in the inbound string.
Trim surrounding whitespace and wrapping `<>`. No yt-dlp extractor check at
ingress time — the normal Home probe remains the extractor truth.

Do **not** invent schemes for bare `www.` hosts or host-only paths in this
phase.

Multiple URLs → first match only.

---

## 6. Clipboard

When `detectClipboardLinks` is true:

- sniff on activation (launch / become key), and
- sniff while frontmost on pasteboard changes

Dedupe with pasteboard change count and the last ingested or offered URL so
the same clip is not handled in a loop.

Ignore pasteboard changes the app itself wrote (Copy report, copy diagnostic
bundle, and any other known app write). When `detectClipboardLinks` turns
off, stop sniffing immediately and dismiss any in-flight busy-path offer.

---

## 7. URL scheme

Scheme (working name):

```
mediagrabber://open?url=<percent-encoded http(s) URL>
```

After decode, accept only `http` / `https`. Bring the app forward on a
successful accept. Share Extension (sibling) and a future browser extension
should use this same shape.

Missing `url`, malformed encoding, or a decoded value that is not `http`/`https`
→ bring the app forward and show a one-shot notice via the confirmation host
(`cancelTitle: nil`):

- Title: `Couldn’t open that link`
- Message: `The link was missing or not a web address.`
- Confirm: `OK`

Extra query keys are ignored. Rename the scheme host when the product name is
final (mechanical).

---

## 8. Services

Info.plist Services entry.

- Menu title: `Download with MediaGrabber` (working name; rename with the product)
- Send types: selected text and URL pasteboard types
- If the app is not running, launch it, then run the same Home ingress path as
  scheme/drag (idle silent / busy confirm / loose extract)

---

## 9. Architecture

`IncomingLinkController` (App) owns every external URL ingress for the life of
the app: clipboard (prefs, ignore-self, dedupe, activation + frontmost), drag /
Dock, custom URL scheme, Services, and later Share Extension handoff.

It owns idle/busy policy, the busy-path confirm, and scheme-failure notices.
AppModel exposes a narrow API: busy signals + apply URL to Home (field +
`resolvePasted`). The controller does not own the queue or probe.

`LinkExtractor` (GrabberKit) is a pure string → URL? helper (first http(s),
trim, `<>`). No yt-dlp at extract time.

Share Extension and browser extensions use `mediagrabber://open?url=…`; the
controller is the in-app receiver.

---

## 10. Out of scope

- Share Extension target
- Browser extensions
- Changes to probe / playlist / Grab semantics
- Product / bundle rename (scheme may keep a placeholder host until then)

---

## 11. Mockups

Update `apps/media-grabber/docs/mockups/screens.html`:

- **§4 Dialogs** — add busy-path “Grab this link?” (URL in message, Grab /
  Not now) and scheme-failure notice (“Couldn’t open that link” / OK).
- **§3 Preferences** — Clipboard detection row already depicted; leave unless
  copy drifts.
- **§1 Home** — optional one frame noting drop-target on the window (caption
  only is enough if chrome is unchanged).

No Share Extension frames in this phase.

---

## 12. Tests

| Area | Coverage |
|---|---|
| `LinkExtractor` | first http(s); trim; `<>`; multiple URLs → first; reject bare `www.` / no scheme |
| Idle vs busy | idle applies; busy presents confirm and applies only on Grab; Not now leaves Home unchanged |
| Clipboard policy | prefs off → no sniff; ignore-self writes; dedupe same change count / URL; toggle off dismisses in-flight offer |
| Scheme | valid `open?url=` applies; missing/malformed/non-http → failure notice |
| Services / drag | route into the same controller entry (fakes / adapters); no second pipeline |

Pasteboard / openURL / Services use injectable seams (no real NSPasteboard /
AppKit Services in unit tests).

---

## 13. Definition of Done

- All Phase 9 ingresses e2e into Home (clipboard, drag, Services, scheme)
- Prefs gate, dedupe, ignore-self, busy confirm, scheme failure notice
- `IncomingLinkController` + `LinkExtractor` as above
- Mockups §4 (+ optional §1 drop caption)
- Lint + full `MediaGrabber-Workspace` suite green for Phase 9 surfaces
- Parent §12.1 / backlog / CLAUDE: Phase 9 shipped; archive spec + plan
- Share Extension stub unchanged (separate epic)

---

## 14. Delivery rule

When implementation starts, every Phase 9 ingress ships end-to-end. No code
stubs. Share Extension remains a separate epic.
