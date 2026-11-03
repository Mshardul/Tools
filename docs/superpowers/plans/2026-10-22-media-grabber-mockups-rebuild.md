# MediaGrabber mockups rebuild

**Goal:** `apps/media-grabber/docs/mockups/` holds one complete, uniform set of HTML mockups that draws every screen and state of the app, generated from a single template system, with one shared stylesheet and one shared script.

**Status:** planning. No mockup file has been changed. Open decisions are listed under "Decisions pending".

## Source of truth

The app code in `Sources/App` and `Sources/GrabberKit`, plus the future plans (roadmap, parent spec, Phase 15 spec and plan, tickets), decide what each screen shows. Where the code and the plans do not settle a question, the question goes to the user. `design-system.md` supplies tokens and component anatomy and is updated afterwards where it is stale. Nothing in a mockup is invented.

## Locked decisions

- The final output shows ALL screens and states. Existing screens are updated, missing ones are added, stale ones are removed.
- Every mockup renders the full page chrome around the component shown: brand row and nav, health strip, left rail, and the hero or paste field on Home.
- First-run Home has no rail and no table. The rail and table appear after the first Grab.
- Onboarding shows the wordmark header and the steps only: no nav, no health strip, no rail.
- The Status column is visible by default. The full column order is Title, Status, Progress, Speed, ETA, Type, Quality, Size, Duration, Added at, then the hidden columns Remark, Site, Finished at, Destination, Attempt, Client used, with Actions always last. Visible by default: Title, Status, Progress, Speed, ETA, Type, Quality, Size, Duration, Added at and Actions. Actions is pinned to the right edge and the other columns scroll under it. Users can reorder columns freely, except Actions.
- Remark stays hidden by default. A failed row shows the Failed status, and its reason appears on hover and keyboard focus. Users who want the reason inline turn the Remark column on.
- Where a ticket specifies a visual the code does not draw yet, the mockup draws the ticket's version, for example the 6pt gradient progress bar and the stroked status pill.
- The Home rail is 200pt wide and the Preferences and About rails are 200pt wide.
- Site names are the friendly display names, never raw domains.
- Row actions use the contract wording: Restart, Restart with sign-in, Restart failed.
- Captions are one line stating what the screen shows. No rationale, no "because" or "so that".
- No phase, ticket, epic or spec-section reference appears in any mockup file, caption, comment or stylesheet. The one exception is a screen whose design is still open: it carries a one-line note naming the future phase or ticket that will deliver the updated mockup. The note is removed or rewritten when that phase or ticket ships.
- A failed save of the queue, history or columns shows a notice dialog. The mockup draws it, and it is owned by a ticket.
- Screens use the code's current icons through one swappable icon sprite. Icon choices are decided in a separate planning pass.
- The Developer page shows GitHub only, as the app does.
- First-run Home and the Aurora body face are drawn as they are today, each with an open-design note naming the phase that decides them.
- Surfaces that tickets describe and the code does not draw yet are drawn from the ticket text, each with an open-design note naming its ticket.
- The Debug menu, native alert and menu bar get their own sections in the mockup files, each with an open-design note naming its ticket.
- Common parts are shared: one navigation header, one chrome, one set of macros, one stylesheet, one script. A change to a common part is made once.
- The page files are split by area: home, playlist, table, chrome, dialog, onboarding, preferences, about, column-interactions.
- Every generated page starts with the same navigation header: All screens, then one link per page file, the current page highlighted, with the theme and palette switcher beside it. Every page is one click from every other page.
- Old files are kept in `docs/mockups/stale/` until the rebuild is accepted, then deleted on the user's explicit instruction.
- No git commands. Python runs through `/Users/shardul/Documents/Github/Tools/.venv/bin/python`.

## Build system

Jinja templates generate every page. Chrome, status pills, row actions per state, icons and window frames are defined once as macros, so every screen is uniform and row actions always match `job-status-and-actions.md`.

- `docs/mockups/requirements.txt` pins `jinja2`.
- `docs/mockups/build.py` renders the templates into the page files and into `screens.html`.
- `docs/mockups/src/` holds the sources: `base.html.j2` (document shell, switcher, shared css and js links), `chrome.html.j2` (brand row, health strip, rail, window frame, banner and toast slots), `macros.html.j2` (pills, row actions, icons, table rows, dialogs), and one fragment file per screen.
- `docs/mockups/screens.css` and `docs/mockups/screens.js` are the only stylesheet and script. Every generated page links both.
- The generated pages sit at their final paths: `screens.html` and `screens/*.html`. They carry a "generated, do not edit" marker and are never edited by hand.
- A screen fragment declares its id, caption, page, selected rail item, health chips and optional banner or toast, then supplies the page body.

## Shared sample data

One data file defines the sample downloads, playlists, sites, sizes, durations and dates. Every screen draws its rows from it, so the same download looks the same on every screen. The data covers all nine job states and every failure reason with friendly site names.

## Working in parallel

The shared parts (css, js, base template, chrome, macros, sample data, navigation header, build script, checker) are built first, in one thread, and then frozen. After that each page can be built in its own thread. A page thread edits only its own fragment files and never the shared parts. A change to a shared part goes through the shared-parts owner and is rebuilt for every page. The user reviews one page at a time; a page is accepted before the next page is reviewed.

## Chrome rules by screen kind

- Home after the first Grab: brand row (Home active), health strip, rail (All, Downloading, Done, Inactive with a badge only when the count is above zero), paste field, runway when a link is resolved, table.
- First-run Home: brand row, health strip, hero, paste field, step cards. No rail.
- Preferences: brand row (Preferences active), health strip, pane rail with the selected pane, pane content.
- About: brand row (About active), health strip, tab rail, content.
- Onboarding: wordmark header and steps.
- Dialogs and popovers: drawn over the screen they appear on, with that screen's full chrome behind them.

## Screen inventory (draft)

Files marked new are added; the others keep their current names.

**home.html**: first-run empty; first-run probing; first-run link resolved; first-run probe failed with and without the shield prompt; first-run audio runway; table with an idle field and the Share tip bar; table with a resolved video; table with audio runway; table with probe failed; table at the minimum window width; runway pickers open (quality, language, save-to with folder paths); disabled Grab; probe failures for each distinct layout (plain, with the shield prompt, with the sign-in hint); table with one row per job state; failed rows for every failure reason (rate limited, bot check, YouTube not offering a video, quality unavailable, sign-in unreadable, region, private, unavailable, age-restricted, offline, disk full, folder not writable, ended early, downloader missing, shield offline, other); Remark on hover and focus; Inactive badge; empty table; filtered-empty table with Clear filters; link dragged over the window.

**playlist.html** (new): playlist link resolved; picker with thumbnails, In queue and Already saved; picker with the already-in-queue banner; picker with zero selected; group expanded; group collapsed; group with failed and cancelled children; group actions.

**table.html** (new): header sort and filter popover; Columns menu; multi-select with the batch bar; Force start with one eligible row; row drag with the drop gap; column header dragging.

**column-interactions.html**: resize with the width readout; autofit; header reorder ghost; reorder drop line.

**chrome.html** (new): health strip states (all ok; shield offline with refresh; shield not set up; shield busy; engine update available; engine busy; engine missing; offline; one site cooling with countdown; one site paused; several sites cooling); cooldown popover (cooling down, rate-limited with Retry now, Retry all); banners (offline; one site rate-limited; several sites rate-limited; shield stopped); toasts (saved with Reveal, stacked, failure toasts, toast beside a banner); shield setup sheet (idle, working, done, needs Homebrew, failed with Details).

**dialog.html**: download again; already in queue; file moved; log unavailable; grab this link; couldn't open that link; start this now; remove this download with Don't ask again; cancel this playlist; clear sorting; MediaGrabber update available; cancel selected downloads; quit (running, paused for missing downloader, paused offline, paused by rate limit); reset settings; saving failed (disk full, folder not writable, other).

**onboarding.html**: first run with every step pending; some steps already installed; Homebrew missing; installing the downloader; step failed with collapsed Details; shield setup running; test run; ready to continue.

**preferences.html**: Downloads; Appearance; Network; Sign-in and cookies (no browser; Safari with and without access; Chrome, Brave and Edge; browser not installed; Firefox with one, several and no profiles; pending retry; test sign-in idle, testing, passed and the three failures); Updates; Logs and privacy; Advanced; control details (concurrency note, custom filename field, open picker, chip busy state); Diagnostics (neutral, check running, after check, canary failed, downloader below minimum with update running, downloader or ffmpeg not found, bundle file list before sharing).

**about.html**: not checked; checking; up to date; update available; check failed; downloader update running; downloader or ffmpeg not found; Developer.

## Process

1. Build the Jinja system and the shared css and js, with a first-run Home screen as the proof.
2. Move the old files to `docs/mockups/stale/` on the user's instruction.
3. Write fragments page by page in this order: Home, playlist, table, chrome, dialogs, onboarding, preferences, about, column interactions.
4. Generate `screens.html` from the same fragments.
5. Run the checker script: chrome present on every screen, no banned words, captions one line, ids unique, rail and nav match the page, generated files match a fresh build.
6. Screenshot every screen in both themes and all six palettes and review for overflow and clipping.
7. The user reviews. After acceptance, the user names `stale/` for deletion.
8. Update the documents that point at the mockups and the documents the new decisions change, one by one with the user's approval.

## Documents to update afterwards

- `docs/design-system.md`: default columns table, runway anatomy, rail width, Sign-in and cookies pane, dialog list, Developer links, mockup references.
- `docs/job-status-and-actions.md`: Status default line.
- `docs/architecture.md`: mockup reference.
- Parent spec `2026-08-28-youtube-downloader-mac-design.md`: mockup references, default-visible columns, runway wording, minimum window width.
- `roadmap.md`: Status default wording and mockup reference.

## Decisions pending

Each entry is removed from this list when the user decides it.

- Wording of the saving-failed dialog for each cause. The ticket owns the final copy; the mockup shows a draft and carries an open-design note.
