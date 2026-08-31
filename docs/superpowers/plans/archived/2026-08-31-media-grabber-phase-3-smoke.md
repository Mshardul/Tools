# Phase 3 — manual smoke checklist

Run on a real machine: `make run` (builds + launches, kills any prior instance).

Automated in this session: `make build` succeeds, the app launches without a
crash. The interactive walk below needs screen + click access and was **not**
run here — do it before signing off Phase 3.

## Walk

- [ ] Open each of the 7 panes from the rail. Rail does not scroll; the
      Downloads pane's right side scrolls when the window is short.
- [ ] Change Theme (Aurora ↔ Tape Deck) and Palette — the whole app re-themes
      on click.
- [ ] Start a download. Lower "Simultaneous downloads" below the running count —
      the concurrency note appears under the stepper (warn glyph + one line).
      Let a download finish so running ≤ the new value — the note clears.
- [ ] Set a proxy / Force IPv4 / speed limit. Start a download. Check its job
      log (`~/Library/Logs/MediaGrabber/jobs/<id>.log` header line) or the
      process argv carries `--proxy <url>` / `-4` / `--limit-rate NNNK`.
- [ ] Advanced → "Reset settings" → confirm in the dialog → every preference
      back to default; Theme / Palette snap live. If the theme goes **stale**
      after a reset (does not repaint until a manual theme change), the fix is a
      `revision` bump on `Preferences.resetToDefaults()` referenced once in
      `MediaGrabberApp`'s `.theme(...)` closure (plan Task 17 Step 6).
- [ ] Advanced → "Reset columns" → table columns restore; independent of
      "Reset settings".
- [ ] Runway: Media-type / Quality / Save-to pickers open, select, and persist
      to the next paste (relaunch, paste a new link, runway shows last
      selection).
- [ ] Filename format: pick each preset — the template changes. "Custom…"
      reveals the monospace field; edit it, it persists, and on reopen the
      picker re-derives to the right row (or "Custom…" for a non-preset string).
- [ ] Quality ladder shows `2160p / 1440p / 1080p / 720p / 480p / Best
      available` — **no 360p** — on both the Downloads pane and the runway.
- [ ] Logs & privacy → "Show in Finder" reveals the log folder; "Open" opens
      the bundled PRIVACY.md.
- [ ] `screens.html` (Task 1, already reviewed) still matches the built panes.

Record pass/fail per item; fix a failure via its owning task before sign-off.
