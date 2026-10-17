# MediaGrabber — Styling Audit

| | |
|---|---|
| **Date** | 2026-10-17 |
| **Subject** | MediaGrabber macOS app, `apps/media-grabber`, working tree as found (uncommitted changes included) |
| **Version / build** | `CFBundleShortVersionString` 0.0.0, `CFBundleVersion` 0.0.0 (Debug build produced by `make`, `TUIST_MG_VERSION` unset); deployment target macOS 14.0; audited on macOS 27.0, Xcode 26.3 toolchain |
| **Produced by** | Claude (`claude-sonnet-5-5`) in Claude Code, as an automated, read-only audit. No product decisions were made. |
| **Sources of truth** | `docs/mockups/screens/*.html` + `docs/mockups/screens/screens.css`; `docs/design-system.md`; `docs/job-status-and-actions.md` |
| **Scope** | Styling only: how things look and read (type, colour, spacing, radii, borders, elevation, icons, motion, layout, copy). Not code quality, naming, architecture, tests or formatting. Source code was read only to learn the style values in use. |

> Note on two mockup CSS files: `docs/mockups/screens.css` (with `docs/mockups/screens.html`) is an older copy; the six per-screen pages in `docs/mockups/screens/` load `docs/mockups/screens/screens.css`. All "L<n>" line references below are to the latter unless stated. They differ in a handful of rules (for example `.go` gains `white-space:nowrap;flex:none`, the runway/morph rules and the batch-selection rules exist only in the newer file).

---

## 2. Executive summary

**Overall verdict: far from the designed styling.** The Aurora / Mint & Iris look is a recognisable, mostly faithful skeleton of the mockup (Aurora tokens, radii, spacing scale, banner, selection bar and grid cell recipes are close). Around it, three structural gaps dominate what a user sees:

1. **Only one palette and one theme exist.** All six palettes resolve to Mint & Iris, and "Tape Deck" is Aurora with smaller corner radii in a forced light colour scheme, so its system controls are unreadable.
2. **Many controls are stock macOS widgets** (toggle/checkbox, stepper, buttons, two table menus, sheets, popover frame) inside an otherwise skinned UI.
3. **Table presentation lags the design** (no group spine, status pills uncoloured, header affordances missing, row actions off-screen at the default window size, toasts see-through and overlapping the banner).

**Findings: 101** (Broken 8 · Ugly 13 · Inconsistent 40 · Nit 40). Verified by render: 64; from code + CSS only: 37. The text audit (Section 8) lists 156 further string-level verdicts.

| Severity | Meaning | Count |
|---|---|---|
| Broken | Wrong, missing or unusable for a user, or a control that does nothing visible | 8 |
| Ugly | Works, but visibly off-design in a way a user would notice | 13 |
| Inconsistent | Differs from the mockup/design tokens or from sibling screens | 40 |
| Nit | Small deviation, or a note that could not be fully verified | 40 |


### Top 10 issues

1. **S-001 — All six palettes resolve to Aurora Mint & Iris** (Global / Preferences → Appearance / every screen; Broken). Picking "Lime & Forest", "Magenta & Violet", "Teal & Rust", "Plum & Blush" or "Navy & Aqua" changes nothing the user can see.
2. **S-002 — Tape Deck theme has no Tape Deck identity** (Global / theme = Tape Deck; Broken). Choosing "Tape Deck" yields a dark Aurora look in a window forced to the light colour scheme (see S-004).
3. **S-004 — Tape Deck forces the light colour scheme under a dark palette** (Global / native controls in Tape Deck; Broken). Stepper chevrons and the "Clipboard detection" checkbox tick are nearly invisible in Tape Deck; the Columns button label is faded.
4. **S-042 — Row actions are off-screen at the default window size** (Home table at 980×720 and 820×560; Broken). At the default window every row's buttons (pause, cancel, reveal, remove) are hidden until the user scrolls sideways; users won't discover them.
5. **S-073 — Toasts are translucent, collide with the banner and have no shadow** (Toast; Broken). While a banner is showing, toasts draw over the banner text and show table rows through their body (text illegible).
6. **S-036 — Toggle, Stepper and Button use system styling** (Preferences, Onboarding, Sheets; Ugly). Preferences — the screen with the most controls — mixes skinned segments/pickers with stock macOS widgets.
7. **S-035 — Columns menu and column-filter menu are system menus** (Home table / Columns, header filter; Ugly). Two of the most-used table controls open plain macOS menus in a fully skinned app; the filter menu cannot "clear" a filter except by clicking each ticked item or "Clear filters" only in the filtered-empty state.
8. **S-065 — Playlist group header and children** (Home table / playlist group; Ugly). An expanded group is indistinguishable from loose rows below its header, so membership and group end are unreadable; actions are text with no button affordance and are off-screen at 980pt (S-042); the rollup is cut mid-word.
9. **S-016 — Disabled gradient buttons are illegible** (Onboarding "Set up", "Continue"; Ugly). The disabled "Set up" and "Continue" buttons are blobs with an invisible label; users cannot tell what the button is or that it will unlock.
10. **S-074 — Confirmation dialog anatomy** (Confirmation dialog (all dialogs); Ugly). Every dialog looks different from the design (no inline icon, no type colouring, wrapping body); the duplicate-submit dialog nudges users to the unwanted action.

---

## 3. Method and limits

**How the app was seen.** The live app cannot be screenshotted (no Screen Recording permission). A temporary XCTest (`ZZStyleAuditHarness`, in `Tests/AppUnitTests`, deleted before finishing) hosted the real SwiftUI/AppKit views — `MainWindow`, `OnboardingView`, `ShieldSetupSheet`, `PlaylistPickerView` — in a borderless `NSWindow` at alpha 0, built state with `AppModelTestHelpers.makeModel` plus `FakeEngine`, fed `QueueSnapshot`s into the real `RowStore`, spun the run loop for 0.6–1.2 s and wrote `bitmapImageRepForCachingDisplay` + `cacheDisplay` PNGs (2× scale) to the scratch directory. It ran only through `make test ONLY=AppUnitTests/ZZStyleAuditHarness`. Window sizes: 980×720 (default), 820×560 (minimum), 1440×900. Tape Deck renders set the window to the light appearance to mimic the app's forced `.light` scheme.

**How the mockup was seen.** A small `WKWebView` snapshot tool (Swift, compiled in the scratch directory, not in the repo) loaded each `docs/mockups/screens/*.html` page, set `data-theme`/`data-palette`, waited for web fonts (Google Fonts reachable) and snapshotted every `.screen .app` element at 2×. Aurora Mint was rendered for all six pages; Tape Deck Teal for Home, Preferences, Dialog, Onboarding and About; Tape Deck Plum and Aurora Lime for Home. Only Teal (Home, Preferences) and Lime (Home) were compared against the app. Comparisons are mockup-left / app-right at the same 980-pt width; the renders were inspected as composite images (no image files are in the repo).

**Measurements.** Values come from the CSS (`screens.css`, inline styles), the design-system tables, the Swift style code (fonts, sizes, colours, paddings, radii, symbol names) and the renders (relative positions, measured from the 2× PNGs, ≈±1 pt). Contrast ratios are computed with the WCAG 2.x formula (Appendix B). Font resolution was measured in-process with `NSFont(name:)`.

**What could not be verified** (details in Appendix C): native menus and context menus (Columns, column filter, Debug menu bar), `NSAlert`, system sheet frames and window title bar/traffic lights, tooltips, live animation (orb spin, chip spin/pulse, dialog and toast transitions), hover/pressed/focus states, drag and drop states, the column-resize readout and drag ghost, scrollbars, and the host-rate popover (popover capture hit the wrong control). Picker popovers were captured but show a saturated halo that is probably a capture artefact of the popover window; their card content is trusted, their frame is not. Several onboarding/shield states that need real subprocess output were produced with fakes and show fixture data (for example "not found" tool versions in Diagnostics, which is also what the real pane shows before its first check, see S-100). The quit-dialog render used placeholder wording; the real quit copy is taken from code.

**Self-disclosure.** One read-only `git status` was run once by mistake in a compound command while exploring; no other git command was used and nothing in the repository was changed by it.

---

## 4. Coverage matrix

Legend: **R** = audited with renders (mockup and/or app); **C** = audited from code + CSS only; **N/A** = not applicable (no such element exists in the app or the mockup).

| Area | Item / state | Status | Notes |
|---|---|---|---|
| Onboarding | Fresh (no Homebrew) | R | `onb-fresh-nobrew` |
| | Fresh (Homebrew only) | R | `onb-fresh-brew-only` |
| | Partly set up | R | `onb-partly` |
| | All set up | R | `onb-allset`, `onb-allset-testfail` |
| | Install running | R | `onb2-running` (spinner) |
| | Failed | R | `onb2-failed`, `onb-install-failed` |
| Home first-run | Idle / probing / resolved / error / shield prompt | R | probing spinner not drawn offscreen (C) |
| | Min and full-size window | R | `home-firstrun-min`, `-full` |
| Home table | Empty | R | `home-table-empty` |
| | Filtered-empty | R | `home-table-filtered-empty` |
| | One row, many rows | R | `home-table-one`, `home-table-all-states` |
| | Every `JobState` (9) + failure variants | R | `home-table-all-states`, `-status-remark`, `-all-columns` |
| | Playlist group collapsed / expanded | R | `home-table-group-collapsed`, `-expanded` |
| | Multi-select + batch bar | R | `home-table-selected` |
| | Sort / filter active | R | `home-table-sort-filter`; filter menu itself C |
| Paste field | Idle / probing / resolved / probe error / shield prompt | R / C | probing spinner C |
| Runway | Type, Format (Resolution), Language, Save to pickers | R (trigger) / R (popover card) | popover frame unverified |
| Share-extension tip | | R | `home-table-resolved` |
| Left rail | All, Downloading, Done, Inactive (+ badge), Preferences rail, About rail | R | |
| Health strip | Every chip state: shield on/offline/not set up, engine current/update, online/offline, single-host cooldown, two-host, busy | R | busy motion C |
| | Host-rate popover | C | capture failed |
| Warning banner | network, circuit-open, shield down | R | `chrome-banner-*` |
| | dependency missing | N/A | `bannerCopy(.depMissing)` returns nil |
| Toast | Success, failure, stacked, with banner | R | `chrome-toast*` |
| Confirmation dialog | 13 of the 14 app dialogs (the batch-cancel dialog shares the cancel-all layout) + Tape Deck | R | `dialog-*`; Debug `NSAlert` is C |
| Set-up-the-shield sheet | idle, working, done, needs Homebrew, failed | R (content) / C (sheet frame) | |
| Playlist picker modal | | R (content) / C (sheet frame) | |
| Preferences | Downloads, Appearance, Network, Sign-in & cookies (None state), Updates, Logs & privacy, Advanced, Diagnostics | R | other cookie states C |
| | Every control type: segment, picker, stepper, toggle, folder button, text field, button, danger button, swatches | R | |
| About | About tab, Developer tab | R | |
| Menus | Columns menu | C | native `Menu` |
| | Column filter menu | C | native `NSMenu` |
| | Debug menu bar + NSAlert | C | |
| | Context menus | N/A | none implemented |
| Drag overlay | | C | none drawn |
| Window chrome | Title bar, traffic lights, window radius/shadow | C | |
| Brand row | Logo, wordmark, nav buttons | R | |
| Components | Rail items, badge | R | |
| | Chips and dots (all states) | R | |
| | Table header cells: title, sort icon, filter icon, drag grip, resize handle, divider | R (title/icons) / C (grip, handle: not drawn) | |
| | Checkbox (header/row, picker, dialog, prefs) | R | |
| | Row cells per column type | R | `home-table-all-columns` |
| | Status pills | R | |
| | Progress bar | R | |
| | Remark text | R | |
| | Action buttons | R | |
| | Tooltips | C | |
| | Scrollbars | C | |
| | Focus rings | C | |
| | Selection highlight | R | |
| | Group header + spine | R | spine absent |
| | Segmented control | R | |
| | Picker trigger + popover rows | R | |
| | Buttons: primary, secondary, destructive, disabled | R | |
| | Text fields | R | |
| | Toggles | R | system checkbox style |
| | Steppers | R | system |
| | Links | R | |
| | Badges | R | |
| | Separators/hairlines | R | |
| | Empty states | R | |
| Iconography | Set consistency, sizes, weights, optical alignment, SF Symbols vs mockup glyphs, colour per state | R / C | |
| Motion | Orb spin, chip spin/pulse, popover and toast in/out, dialog in, reduced motion | C | not renderable offscreen |
| Layout | 820×560, 980×720, 1440×900 | R | home, prefs, first-run |
| Themes | Aurora (3 palettes) | R | palettes identical (see S-001) |
| | Tape Deck (3 palettes) | R | all dark Aurora |
| | Dark appearance correctness | R | |
| Text audit | Every user-visible string | Section 8 | |


---

## 5. Mockup style model

How the mockup is styled, so the app can be judged against intent. Line numbers refer to `docs/mockups/screens/screens.css`.

### 5.1 Structure and layout model

- One fixed **980×720 window** (`.app`, L133): `display:flex; flex-direction:column`, border `var(--border-w)` stroke, radius `--r-window`, `overflow:hidden`, theme elevation. 1 CSS px = 1 pt.
- Stack top to bottom: brand row `.hdr` (flex, centred, gap 12, padding 15px 22px, bottom border) → health strip `.health` (flex-wrap, gap 9, padding 11px 22px, bottom border) → body.
- Body for Home with a table: `.body-home2` flex row = left rail `.mg-rail` (160px, border-right) + `.mg-main` (column: `.hero` fixed, `.tablewrap.fill` flex 1 with a sticky header and a scrolling `.table-scroll`). Preferences: `.prefs` flex row = `.side` 200px rail + `.main` (column; title/sub/rule fixed, `.main-scroll` scrolls). About re-uses the Preferences shell with a 2-item rail.
- Table is an HTML `<table>` (`width:100%`, collapse) inside the scroll container; cells `padding 11px 8px`; header cell `padding 8px 8px 8px` + `padding-right 14px` for the resize handle (L248, L544).
- Overlays (`.banner`, `.toaststack`, `.backdrop`, `.scrim`, `.pop`, `.fmenu`, `.colmenu`, `.ctxmenu`) are absolutely positioned inside `.app` with z-index 5 (banner), 6 (toast), 8 (modal backdrop), 9 (scrim), 20 (menus), 30 (picker popover), 40 (context menu).
- Responsive behaviour: none (fixed width); `@media (prefers-reduced-motion:reduce)` disables all animation/transition (L493).

### 5.2 Tokens (real values)

**Aurora (dark)** — defined per `[data-palette]` (L12-43); `--panel`, `--panel-hi`, `--hair`, `--on-accent` shared.

| Token | Mint & Iris | Lime & Forest | Magenta & Violet |
|---|---|---|---|
| `--ground` | #0C1013 | #0A0F0C | #100C14 |
| `--panel-solid` | #0E1117 | #0C1210 | #120E16 |
| `--panel` | rgba(255,255,255,.05) | same | same |
| `--panel-hi` | rgba(255,255,255,.08) | same | same |
| `--stroke` | rgba(255,255,255,.12) | rgba(190,255,210,.13) | rgba(230,190,255,.14) |
| `--hair` | rgba(255,255,255,.06) | same | same |
| `--text` | #EDF0F5 | #E9F2EC | #F1EAF5 |
| `--dim` | #9AA3B2 | #93A99C | #A996B5 |
| `--faint` | #6B7480 | #5F7268 | #7A6B85 |
| `--headline` | #F4F6FA | #F2F8F3 | #F7F2FA |
| `--on-accent` | #07080B | #07080B | #07080B |
| `--accent` | #5EF2C8 | #B6F04A | #F25C9E |
| `--accent-2` | #8B7BFF | #4ED6A0 | #9B6BFF |
| `--warn` | #FFC24B | #F2C14E | #FFC24B |
| `--danger` | #FF7A6B | #FF6F6F | #FF6B6B |
| `--go-fill` | 135° #5EF2C8→#8B7BFF | 135° #B6F04A→#4ED6A0 | 135° #F25C9E→#9B6BFF |
| `--orb` | conic #5EF2C8,#8B7BFF,#FF7A6B,#5EF2C8 | conic #B6F04A,#4ED6A0,#F2C14E,#B6F04A | conic #F25C9E,#9B6BFF,#5ED6E8,#F25C9E |
| `--bar-fill` | 90° #5EF2C8→#8B7BFF | 90° #B6F04A→#4ED6A0 | 90° #F25C9E→#9B6BFF |
| `--banner-fill` | 90° #FF7A6B→#FFC24B | 90° #FF6F6F→#F2C14E | 90° #FF6B6B→#FFC24B |
| `--glow-a / -b` | .14 mint / .16 iris | .16 lime / .14 green | .16 pink / .16 violet |
| status fills `--s-*` | transparent | transparent | transparent |

**Tape Deck (light)** — `[data-theme=tapedeck]` base (L46-50) + palette (L51-73).

| Token | Teal & Rust | Plum & Blush | Navy & Aqua |
|---|---|---|---|
| `--ground` | #F3E9D8 | #EFE9E9 | #E7E9E7 |
| `--panel-solid` | #FBF4E6 | #FBF5F5 | #F5F6F3 |
| `--panel` | #F3E9D8 | #EFE9E9 | #E7E9E7 |
| `--panel-hi` | rgba(0,0,0,.04) | same | same |
| `--stroke` = ink | #2B2118 | #281E26 | #1B222A |
| `--hair` | rgba(43,33,24,.18) | rgba(40,30,38,.18) | rgba(27,34,42,.18) |
| `--text` / `--headline` / `--on-accent` | #2B2118 | #281E26 | #1B222A |
| `--dim` = `--faint` | #8A7A60 | #8B8088 | #7C838A |
| `--brand` (header) | #0E5C57 | #5A2E52 | #1F3350 |
| `--accent` | #D2601A | #E98C89 | #2FA69A |
| `--accent-2` | #0E5C57 | #5A2E52 | #1F3350 |
| `--warn` | #9C5A00 | #8C5A0C | #805C14 |
| `--danger` | #B4472A | #C25B57 | #D9694C |
| `--go` (= `--go-fill`) | #E4A11B | #E8B24A | #F2B12E |
| `--bar-fill` / `--banner-fill` | #D2601A | #E98C89 | #2FA69A |
| status fills dl / done / fail / cool / queue | #CFE3E1 / #D9E8C8 / #F3D2C3 / #F6E2B8 / #FBF4E6 | #E1DCEC / #D8E6D0 / #F4D6D6 / #F3E3C0 / #FBF5F5 | #D6E6E3 / #D8E6D0 / #F3D8CC / #F6E6B6 / #F5F6F3 |
| `--orb`, `--glow-*` | none / transparent | same | same |

**Theme-independent tokens** (L76-89): spacing `--sp-1…--sp-8` = 4, 8, 12, 16, 22, 30, 44 (there is no `--sp-7`); radii window/card/control/pill/chip = Aurora 18/14/9/20/7, Tape Deck 14/12/8/20/6; border width Aurora 1px, Tape Deck 2px; `--ease:cubic-bezier(.2,.7,.2,1)`; `--dur:160ms`.

### 5.3 Type scale (as used in the CSS)

| Role | Face | Size / weight / case / tracking | Source |
|---|---|---|---|
| Hero headline | display | 32 / 700 (800 TD) / lh 1.04 / −.03em, max 18ch | L172 |
| Kicker | mono | 11 / 400 / UPPER / .16em / accent (brand in TD) | L170 |
| Wordmark | display | 18 / 700 (800 TD) / −.02em | L141 |
| Nav | display (TD: mono UPPER 11, .06em) | 12 | L144-145 |
| Chips | mono | 10 | L151 |
| Rail item | display | 13 | L526 |
| Rail group caption | mono | 10 / UPPER / .1em / faint | L394 |
| Runway label | mono | 9 / UPPER / .1em / faint | L190 |
| Picker / segment / control text | display | 12 (segment selected 600) | L204, L210 |
| Grab / Run check | display | 14 / 700 | L198, L440 |
| Pane title | display | 20 / 800 (Aurora 700) | L397-398 |
| Pane sub | body | 12 / lh 1.5 / dim | L399 |
| Row label / helper | body | 13 / 600 · 11.5 / dim, max 40ch | L402-403 |
| Table header | mono | 10 / UPPER / .08em / dim | L248 |
| Table cell | body | 13 | L247 |
| Site / Report | mono | 12 dim / 12 | L275, L445 |
| Status pill | mono | 10 | L278 |
| Group title / actions | display | 13/600 · 10 | L300, L306 |
| Dialog title / message | display / body | 15/600 headline · 13 dim, one line ellipsis | L365-366 |
| Toast | body | 12 (link 11) | L324-326 |
| Onboarding h1 / lead / step title / step text | display / body / display / body | 26/700 −.02em · 13 lh1.6 · 14 · 12 lh1.6 | L375-382 |
| Version display | display | 13 | L468 |

### 5.4 Colour roles

`--text` primary; `--dim` secondary and table header; `--faint` placeholder/captions/disabled; `--headline` display text; `--accent` kicker, "downloading", check marks, links, hover wash (12% mix), selected segment outline; `--accent-2` queued, playlist group wash (10% Aurora), table checkboxes, filter-active, drop line, selection wash; `--warn` cooldown, warnings, inline fix; `--danger` failure, errors, destructive buttons, badge; `--on-accent` text on accent fills. Surfaces: `--ground` (backdrop, command boxes, scrim base), `--panel-solid` (window body, cards, popovers, toasts, sticky header), `--panel` (inputs, chips, secondary buttons, active rail), `--panel-hi` (runway console, group header Tape Deck, toggle off-track).

### 5.5 Spacing, radii, borders

Spacing scale 4/8/12/16/22/30/44 with frequent literal values 6, 9, 10, 11, 14, 15, 18 in components (for example chip padding 4×10, nav 7×12, table cell 11×8). Radii: window 18/14, card 14/12 (dialogs, fields, cards), control 9/8 (buttons, pickers, popover menus), chip 7/6 (segments, rail items, nav items, action buttons), pill 20 (chips, status pills, bars), literal 11 (banner), 5 (header icon buttons), 4 (checkboxes), 6 (stepper buttons). Borders: Aurora 1px `--stroke` on structure, `--hair` on row rules; Tape Deck 2px ink on structure, 1.5px on chips/pills/small controls.

### 5.6 Elevation

Window/cards: Aurora `0 0 0 1px rgba(255,255,255,.02), 0 24px 60px rgba(0,0,0,.6)`; Tape Deck `8px 8px 0 rgba(0,0,0,.35)`. Runway console (`--console-elev`): `0 0 0 1px glow-a, 0 0 32px glow-b` (Aurora), none (TD). Picker popover and context menu (Aurora): `0 0 0 1px glow-a, 0 0 34px glow-b, 0 24px 60px rgba(0,0,0,.6)`; (TD) `--elev-card`. Filter/column menus `0 12px 40px rgba(0,0,0,.55)`. Banner `0 10px 34px rgba(0,0,0,.45)`. Toast `0 12px 30px rgba(0,0,0,.4)`. Playlist modal `0 30px 80px rgba(0,0,0,.6)`. Aurora dots glow (`0 0 8px` chips, `0 0 6px` pills), bar glow `0 0 10px glow-a`.

### 5.7 Motion tokens

`--ease` cubic-bezier(.2,.7,.2,1), `--dur` 160ms (toggle thumb `transition: all var(--dur)`); Aurora orb `spin 6s linear infinite`; chip refresh `chip-spin 900ms linear infinite`; chip busy dot `chip-pulse 1200ms ease-in-out infinite` (opacity 1→.35); everything disabled under `prefers-reduced-motion`. Design-system.md adds: running-row motif 14px 2s spin; dialog scale/fade over `--dur`/`--ease`.

### 5.8 Per-component rules (selected)

- **Chip**: pill, 1px (1.5 TD) stroke, `--panel` (TD: `--panel-solid`) fill, dim (TD: text) mono 10; dot 6px (ok = accent in Aurora, accent-2 in TD; warn = warn); `.warn` chip recolours text and border; busy = grey pulsing dot + spinning ↻.
- **Table header cell**: grip ⋮⋮ 9px (opacity .5, `cursor:grab`), title, 18×18 sort and filter buttons (hover border, active accent/accent-2), 6px resize handle with 1px 60%-height divider; sticky; `--panel-solid` fill.
- **Row**: 11×8 padding, bottom `--hair`; hover `--panel`; selected accent-2 10%; checkbox 15px radius 4 (`--panel` fill; on = accent-2).
- **Status pill**: mono 10, 1px stroke, 5px dot; colours by state; TD fills from `--s-*` with ink text.
- **Progress**: 110×6, pill, gradient fill (+ glow Aurora); TD 7px with 1.5px ink border.
- **Actions**: 27×27 buttons, chip radius, `--panel` fill, 1px stroke, 11px glyph; disabled .3.
- **Group header**: Aurora accent-2 10% wash (TD `--panel-hi`), stroke bottom, caret box 16px radius 5, rollup mono 11 + 110×5 bar, chips; children indented 28px with a 1px stroke spine at left 12px, 10px connector, dividers start after the spine.
- **Segmented control**: 34px, radius chip, panel track, selected `--panel-solid` + inset stroke (Aurora).
- **Picker trigger/popover**, **dialog**, **banner**, **toast**, **modal**: values listed in Sections 6-7 beside each finding.
- **Toggle** 34×20 pill, thumb 14px, on = accent fill; **stepper** 26px buttons; **swatch** 56×38 radius 8, selected outline 2px accent, offset 2.

### 5.9 Theme and palette differences

Aurora: dark, 1px hairlines, glow elevation, conic orb, transparent header, Sora/Inter/JetBrains Mono, gradients on Go/bar/banner. Tape Deck: light, 2px ink borders (1.5px small), hard shadow, brand-colour header with surface-colour wordmark, reel motif, solid fills (no gradients), uppercase mono nav, status pills filled from `--s-*`, Bricolage Grotesque/DM Sans/DM Mono. Palette changes colour tokens only.


---

## 6. Global findings

Finding format: Mockup = what the mockup specifies (file + selector/line + values); App = what the app does and how that was determined; Gap = concrete difference and why a user cares; Evidence = render description (no image files are kept in the repo); Verified = rendered or code+CSS only; Direction = one line, no code.

### 6.1 Themes and palettes

#### S-001 — All six palettes resolve to Aurora Mint & Iris

- **Screen / component / state:** Global / Preferences → Appearance / every screen
- **Severity:** Broken  ·  **Verified:** rendered
- **Mockup:** Six complete token sets: Aurora mint/lime/magenta (screens/screens.css L12-43) and Tape Deck teal/plum/navy (L46-73); design-system.md §5.2-5.3 repeats them. Palette swaps colour tokens only.
- **App:** `palette(for:)` in Theme/Palette.swift returns `.auroraMintIris` for every `PaletteKind` (a single `switch` arm lists all six). `DownloadsGridTokens.make(theme:)` discards its argument and returns `.aurora`. Determined from code, confirmed by renders of lime, magenta, tape-A/B/C home screens: pixel-identical to mint.
- **Gap:** Picking "Lime & Forest", "Magenta & Violet", "Teal & Rust", "Plum & Blush" or "Navy & Aqua" changes nothing the user can see. The Palette control in Preferences is a dead control that looks alive.
- **Evidence:** Renders `theme-aurora-lime-home`, `theme-aurora-magenta-home`, `theme-tape-{a,b,c}-home` all show the mint (#5EF2C8) accent and #0C1013 ground. Mockup renders of the same palettes (`home-s1-2-aurora-lime`) show lime #B6F04A accent.
- **Direction:** Build the six palette token sets from the mockup values.

#### S-002 — Tape Deck theme has no Tape Deck identity

- **Screen / component / state:** Global / theme = Tape Deck
- **Severity:** Broken  ·  **Verified:** rendered
- **Mockup:** Tape Deck is light: ground #F3E9D8, surface #FBF4E6, 2px ink borders (`--border-w:2px`, L87), hard offset shadow `8px 8px 0 rgba(0,0,0,.35)` (L87), brand-coloured header with surface-coloured wordmark (L135, L142), uppercase mono nav (L145), reel motif (L138-140), Bricolage Grotesque / DM Sans / DM Mono (L86), radii 14/12/8/20/6 (L85).
- **App:** `Theme` only changes five radii (Tape Deck 10/8/6/14/5; Theme.swift windowRadius/cardRadius/controlRadius/pillRadius/chipRadius) and `motif` (never used to pick a different drawing). Colours, fonts, borders (1pt hairline) and header are the Aurora ones. The only Tape Deck elevation is the `SkinnedPicker` popover shadow (black 0.35, offset 3×3, blur 0; mockup 8×8). `MotifView` never reads `motif` and always draws the conic orb.
- **Gap:** Choosing "Tape Deck" yields a dark Aurora look in a window forced to the light colour scheme (see S-004). The theme named in the Appearance pane does not exist visually.
- **Evidence:** Render `theme-tape-a-home` beside mockup `home-s1-2-tapedeck-teal`: mockup is cream with a teal header bar and ink outlines; app is the dark mint UI. `tape-firstrun` is dark.
- **Direction:** Implement the Tape Deck token set, border widths, header ground, hard shadow and reel.

#### S-003 — Tape Deck typefaces are not bundled; both themes use Sora/Inter/JetBrains Mono

- **Screen / component / state:** Global typography
- **Severity:** Broken  ·  **Verified:** rendered
- **Mockup:** Tape Deck display = Bricolage Grotesque 700/800, body = DM Sans 400/500/700, utility = DM Mono 400/500 (design-system.md §2.1; screens.css L86).
- **App:** Resources/Fonts holds only Inter, JetBrains Mono, Sora. `NSFont(name:)` for "Bricolage Grotesque", "DM Sans", "DM Mono" returns nil (measured in the harness: all three "NOT RESOLVED"). `Theme.displayFont/bodyFont/monoFont` hard-code Sora/Inter/JetBrains Mono and ignore `kind`.
- **Gap:** Even once palettes exist, Tape Deck would read as the same typography as Aurora. The warm, tactile personality is carried largely by the type.
- **Evidence:** `fonts.txt` from the harness; render `fonts-sample` shows the three bundled families resolving with named weight instances.
- **Direction:** Bundle the three Tape Deck families and select by theme.

#### S-004 — Tape Deck forces the light colour scheme under a dark palette

- **Screen / component / state:** Global / native controls in Tape Deck
- **Severity:** Broken  ·  **Verified:** rendered
- **Mockup:** Tape Deck is a light theme whose surfaces are light (design-system.md §1 "Tape Deck is light").
- **App:** `MediaGrabberApp` applies `.preferredColorScheme(.light)` for Tape Deck while the palette is still the dark Mint tokens (see S-001). System controls (Stepper arrows, Toggle checkmark, scrollers, ProgressView, DisclosureGroup chevron, disabled-button tints) therefore draw dark glyphs on dark panels.
- **Gap:** Stepper chevrons and the "Clipboard detection" checkbox tick are nearly invisible in Tape Deck; the Columns button label is faded. Users who pick Tape Deck get unreadable controls.
- **Evidence:** Renders `tape-prefs-downloads` (Stepper arrows faint, checkbox tick black on near-black), `theme-tape-a-home` (Columns label dim).
- **Direction:** Pair the colour scheme with the palette that is actually applied.

#### S-005 — Palette swatches all show the same colours

- **Screen / component / state:** Preferences → Appearance / palette control
- **Severity:** Broken  ·  **Verified:** rendered
- **Mockup:** Three split-fill swatches per theme, 56×38 tiles, radius 8, selected = 2px accent outline at 2px offset, name 10.5px below (L416-421); each tile shows that palette's accent | accent-2.
- **App:** `swatch()` fills `HStack { tokens.accent; tokens.accent2 }` from `palette(for: kind)`, which is always Mint (see S-001); tiles are 84×38, radius `chipRadius`, labels Inter 11.
- **Gap:** Aurora shows three identical mint/iris tiles named Mint & Iris, Lime & Forest, Magenta & Violet; the labels lie. Tile width is 50% larger than designed.
- **Evidence:** Render `pref-appearance` pair: mockup tiles are mint, lime, magenta; app tiles are all mint-iris. Tape Deck renders (`theme-tape-a-appearance`) show Aurora-mint tiles under names "Teal & Rust / Plum & Blush / Navy & Aqua".
- **Direction:** Feed the swatch from each palette's own tokens; 56pt wide.

#### S-006 — Dark appearance of system chrome

- **Screen / component / state:** Global
- **Severity:** Nit  ·  **Verified:** code+CSS only
- **Mockup:** Aurora is dark-first; `preferredColorScheme(.dark)` for Aurora.
- **App:** Aurora correctly forces `.dark`, so native controls draw dark. The window's native title bar, traffic lights and window title are system-drawn (not rendered here).
- **Gap:** Not a defect for Aurora; recorded so the matrix shows dark appearance was checked. Title bar is "not visually verified".
- **Evidence:** All Aurora renders.
- **Direction:** None.

### 6.2 Typography

#### S-007 — Letter-spacing is absent everywhere except table headers

- **Screen / component / state:** Global typography
- **Severity:** Inconsistent  ·  **Verified:** rendered
- **Mockup:** Kicker 11px mono, `letter-spacing:.16em` uppercase (L170); hero h1 `-.03em` (L172); wordmark `-.02em` (L141); Tape Deck nav `.06em` uppercase (L145); rail group caption `.1em` (L394); runway labels `.1em` (L190); popover caption `.1em` (L218); table header `.08em` (L248); onboarding h1 `-.02em` (L375).
- **App:** A repo search finds no `.tracking`/`.kerning`; only the AppKit header cell sets `.kern: 0.8` (≈.08em at 10pt, which matches). Kicker "PASTE. PICK. GRAB.", "FIRST RUN", rail captions "GENERAL/YOUTUBE/SYSTEM", popover captions are set tight.
- **Gap:** The signature spaced-caps kicker looks cramped; large Sora headings are not tightened so "One link in. One file out." sits wider than designed.
- **Evidence:** Render pair `home-s1-1--home-firstrun-idle`: mockup kicker is visibly letter-spaced; app kicker is solid. The hero headline sets visibly wider in the app than in the mockup at the same 32pt size.
- **Direction:** Add tracking per role (.16em kicker, −.03em hero, .1em captions).

#### S-008 — Heading weights differ from the mockup

- **Screen / component / state:** Global typography
- **Severity:** Inconsistent  ·  **Verified:** rendered
- **Mockup:** Aurora wordmark Sora 700 18px (L141); hero h1 700 (L172); Grab/Run-check Sora 700 14px (L198, L440); prefs h2 Aurora 700 20px (L397-398); onboarding h1 700 26px (L375); design-system.md §2.2 lists Sora 600/700 for Aurora.
- **App:** Wordmark Sora 17 semibold; hero Sora 32 semibold; Grab Inter 13 semibold; Run check Sora 13 bold; prefs/About/Developer titles Sora 20 `.heavy` (800, "Sora-Regular_ExtraBold"); onboarding h1 Sora 30 semibold; picker/shield titles Sora 20 semibold.
- **Gap:** Hierarchy reads heavier on settings pages (800 is outside the documented Aurora weights) and lighter on the hero and wordmark than designed.
- **Evidence:** Pair `pref-appearance`: app "Appearance" is visibly heavier than the mockup title. Pair `home-s1-1`: app hero is lighter-weight than mockup.
- **Direction:** Use 700 for Aurora display headings; 800 only in Tape Deck.

#### S-009 — Type sizes drift from the scale

- **Screen / component / state:** Global typography
- **Severity:** Inconsistent  ·  **Verified:** code+CSS only
- **Mockup:** Body 13/1.6; helper 12/1.5 `--dim`; kicker 11; table header 10; pills/chips 10–11 (design-system.md §3.2). Mockup chips 10px (L151), nav 12px Sora, rail 13px Sora (L526), onboarding step title 14px Sora (L381), lead 13px (L376), step cards h4 13px.
- **App:** Chips mono 11; nav Inter 12 medium (mockup Sora); Home rail Inter 12 vs Preferences/About rail Inter 13 (two sizes for one shared rail, MainWindow.railButton vs HomeRail); onboarding step title Inter 15 semibold, lead Inter 14, summary 13; hero cards title Inter 13 (mockup Sora 13); status-text sizes 10.5/11/11.5 mixed in Preferences/About helper text.
- **Gap:** One-point drifts add up: the rail changes size between Home and Preferences, onboarding text is larger than every other screen.
- **Evidence:** Pairs `onb1`, `pref-downloads`. Full size table in Appendix A.
- **Direction:** Align each role to the scale; one rail size.

#### S-010 — Display vs body family swapped on many controls

- **Screen / component / state:** Global typography
- **Severity:** Inconsistent  ·  **Verified:** rendered
- **Mockup:** Controls (nav, rail, segment, picker trigger, buttons, group actions, card titles) use the display family (Sora) at 12–13px: `.nav a`, `.mg-rail a`, `.seg button`, `.pick`, `.btn`, `.btn-txt`, `.gh`, `.step h3` (L144, L526, L204, L210, L355, L414, L300, L381).
- **App:** Nav, rail, `SkinnedSegment`, `SkinnedPicker`, runway Grab, selection bar and group actions use Inter (`theme.bodyFont`); About, Developer and Diagnostics buttons use Sora (`displayFont`, 12 semibold); dialog, Homebrew-recovery, shield-sheet and several Preferences buttons (Advanced, Logs & privacy, Sign-in) fall back to SF Pro (see S-011).
- **Gap:** Button labels use three different faces in one window (Sora, Inter, SF Pro), and none of them is the display face the mockup uses for controls.
- **Evidence:** Pairs `about1`, `pref-advanced`: "Open Diagnostics" (Sora) vs "Show in Finder" (SF) sit in rows that look identical in the mockup.
- **Direction:** One face per control role.

#### S-011 — Buttons without a font fall back to the system font (SF Pro)

- **Screen / component / state:** Confirmation dialog, onboarding Homebrew actions, shield sheet, Preferences buttons, banner-adjacent buttons
- **Severity:** Inconsistent  ·  **Verified:** rendered
- **Mockup:** All buttons are `font-family:var(--font-display)` 11–14px (L198, L355, L368, L414, L450).
- **App:** `Button("…")` calls with `.buttonStyle(.plain)` or default style and no `.font`: ConfirmationDialog Cancel/Confirm, Onboarding Copy command/Open Terminal/Check again/Copy, ShieldSetupSheet buttons, Logs & privacy "Show in Finder"/"Open", Advanced "Show in Finder"/"Reset"/"Reset…", Sign-in "Test sign-in"/"Open System Settings", HostRatePopover "Retry now"/"Retry all". These render in SF Pro 13, except the command-box Copy, which is `.controlSize(.small)`.
- **Gap:** Typography breaks exactly where the user acts. Dialog buttons "Cancel" and "Reset" do not match the dialog title in Sora.
- **Evidence:** Renders `dlg1`, `dlg5`, `pref-advanced`, `shield4`.
- **Direction:** Give every button the themed font.

#### S-012 — Table title and data cells are all dim

- **Screen / component / state:** Home table / cells
- **Severity:** Inconsistent  ·  **Verified:** rendered
- **Mockup:** `tbody td` inherits `--text` (#EDF0F5); only `.site` is `--dim` (L274-276); design-system.md §4.2.3 says Type/Quality/Size/Speed/ETA/Site are `--dim`, Title is primary.
- **App:** `textCell()` applies `tokens.dim` (#9AA3B2) to every text column including Title (DownloadsGridCells.swift `textCell` → `applyTextStyle(field, font: tokens.cell, color: tokens.dim)`).
- **Gap:** Row identity text has no more emphasis than metadata; scanning a long list is harder (title vs "Video / 1080p" are the same grey).
- **Evidence:** Render `home-table-all-states`: title "Unknown failure" and "Video" are the same grey; mockup titles are bright.
- **Direction:** Title in `--text`, metadata in `--dim`.

#### S-013 — Version/status values set in mono instead of the plain face

- **Screen / component / state:** About, Updates
- **Severity:** Inconsistent  ·  **Verified:** rendered
- **Mockup:** Comment L467: "plain-font version display — About / Updates rows; mono stays reserved for the Diagnostics report card"; `.verstat` Sora 13 `--text` / `--accent` / `--warn` (L468-469).
- **App:** About rows: title JetBrains Mono 12 dim (even "MediaGrabber", "Downloader (yt-dlp)", "Diagnostics"), values JetBrains Mono 12, subtitle Inter 10.5 faint. Developer rows likewise ("Connect with me", "Source code" in mono dim).
- **Gap:** About reads like the Diagnostics report; row labels lose the bold 13px hierarchy used in Preferences.
- **Evidence:** Pair `about1`: mockup rows are 13px labels with bold name; app rows are small grey mono.
- **Direction:** Use PrefRow typography on About.

#### S-014 — Top navigation typography and spacing

- **Screen / component / state:** Brand row nav
- **Severity:** Nit  ·  **Verified:** rendered
- **Mockup:** `.nav a` Sora 12, padding 7×12, radius chip, dim; active `--panel`/`--text`; gap 4. Tape Deck: mono uppercase 11 `.06em`, active surface fill with brand text (L143-147).
- **App:** Inter 12 medium, padding 4×12, radius chip, active `panel`/`text`, gap 4; Home/Preferences/About buttons are plain.
- **Gap:** Smaller hit area (≈24pt tall vs ≈34pt) and a different face; active pill height 24.
- **Evidence:** Pair `home-s1-1`.
- **Direction:** 7pt vertical padding; Sora.

### 6.3 Colour and contrast

#### S-015 — `--faint` text is below AA for small text

- **Screen / component / state:** Placeholders, rail captions, step numbers, empty messages
- **Severity:** Nit  ·  **Verified:** code+CSS only
- **Mockup:** `--faint:#6B7480` used for placeholder (L182), runway labels (L190), rail captions (L394), empty table (L244), step cards `.n` (accent), `.lastrun` (L442).
- **App:** Same token used in: paste placeholder (mono 13), rail group captions (mono 11), onboarding "Continue unlocks…" (12), empty-table message (13), step-card numbers (mono 12), "Last run" (mono 11), table empty-state, ClearLink "×" icon. Contrast: 4.03:1 on ground #0C1013, 3.99:1 on panel-solid, 3.57:1 on panel (computed, Appendix B).
- **Gap:** Below WCAG AA 4.5:1 for text under 18px; hint text is hard to read for low-vision users. The shortfall is inherited from the token value in the mockup and design-system.md.
- **Evidence:** Computed ratios; render `home-table-filtered-empty` message.
- **Direction:** Lift `--faint` to ≥4.5:1 or use `--dim` for informational text.

#### S-016 — Disabled gradient buttons are illegible

- **Screen / component / state:** Onboarding "Set up", "Continue"
- **Severity:** Ugly  ·  **Verified:** rendered
- **Mockup:** `.go[disabled]{opacity:.3;filter:grayscale(.5)}` (L200) — label stays readable as a muted version of the fill.
- **App:** `primaryButton` applies `.opacity(0.3)` and `.grayscale(1)` to a gradient whose label colour is `onAccent` (#07080B). Effective colours: fill ≈ rgb(51–66), label rgb(11,14,16): contrast 1.6–2.0:1.
- **Gap:** The disabled "Set up" and "Continue" buttons are blobs with an invisible label; users cannot tell what the button is or that it will unlock.
- **Evidence:** Renders `onb1`, `onb-run-fail` (button at x≈1290 y≈550 unreadable).
- **Direction:** Keep label contrast ≥3:1 when disabled (grayscale .5 as designed).

#### S-017 — Selected-row tint is mint 18% instead of iris 10%

- **Screen / component / state:** Home table / selection
- **Severity:** Inconsistent  ·  **Verified:** rendered
- **Mockup:** `tr.row-selected td{background:color-mix(in srgb,var(--accent-2) 10%,transparent)}` (L541); selected checkbox fill `--accent-2` (L537).
- **App:** `GridRowView.drawSelection` fills `accent.withAlphaComponent(0.18)`; the checkbox is accent-2. Result: mint-green row wash with a purple checkbox.
- **Gap:** Two different colours for one selected state; green wash also reads as "downloading/OK".
- **Evidence:** Render `home-table-selected` bottom row (green wash) vs mockup `home-s5-3` (indigo wash).
- **Direction:** Use accent-2 at 10%.

#### S-018 — Attention chips differ only by a 7px dot

- **Screen / component / state:** Health strip
- **Severity:** Inconsistent  ·  **Verified:** rendered
- **Mockup:** `.chip.warn{color:var(--warn);border-color:var(--warn)}` (L156) (cooldown chip in home.html 1.2); dots glow in Aurora (`box-shadow:0 0 8px`, L154-155).
- **App:** `chipLabel` always uses `dim` text and `stroke` border; state only recolours the dot (no glow).
- **Gap:** A cooling-down or offline chip is as quiet as a healthy one; warning state needs the dot colour alone, which fails for colour-blind users.
- **Evidence:** Render `chrome-shield-down-cooldown`: all chips identical grey outline.
- **Direction:** Warn text + border on attention chips; add dot glow in Aurora.

#### S-019 — Count badge text colour

- **Screen / component / state:** Home rail "Inactive"
- **Severity:** Nit  ·  **Verified:** code+CSS only
- **Mockup:** `.rbadge{background:var(--danger);color:#fff}` (L530): white on #FF7A6B = 2.55:1.
- **App:** App uses `onAccent` (#07080B): 7.87:1.
- **Gap:** App is more legible than the mockup; recorded as a divergence the owner may want to bless (see Section 9).
- **Evidence:** Computed.
- **Direction:** None (mockup value is the weak one).

### 6.4 Spacing, radii, borders, dimensions

#### S-020 — Control heights are smaller than designed

- **Screen / component / state:** Runway pickers, segments, Grab, chips
- **Severity:** Inconsistent  ·  **Verified:** rendered
- **Mockup:** `.rstep>.rv,.seg,.pick{height:34px}` (L192, L203, L210); `.go{min-height:44px}` (L198); chip padding 4px 10px (L151); nav padding 7px 12px (L144).
- **App:** SkinnedPicker height 28 (fixed `.frame(height: 28)`); SkinnedSegment ≈26 (2 + 4 padding + 12pt label); Grab ≈32 (13pt label + 8+8); chips 5 vertical padding (mockup 4, so chips are slightly taller than designed); nav 4+4.
- **Gap:** Pickers, segments, Grab and nav are ~15–25% smaller than the mockup, so the first-run hero is less prominent and click targets are small (Grab 32pt, segment 26pt).
- **Evidence:** Pair `home-s1-4`: mockup Grab is visibly taller; app pickers are shorter.
- **Direction:** 34pt controls, 44pt primary.

#### S-021 — Vertical rhythm of chrome is compressed

- **Screen / component / state:** Brand row, health strip, table rows
- **Severity:** Inconsistent  ·  **Verified:** rendered
- **Mockup:** `.hdr` padding 15px 22px (≈60pt incl. rule, measured on the mockup render); `.health` padding 11px 22px (L149, ≈45pt); table `tbody td` padding 11px 8px (L272).
- **App:** Brand row 12pt vertical padding (≈46pt incl. rule); health strip 8pt vertical (≈41pt); grid rows 41pt, group header 48pt.
- **Gap:** The two stacked chrome bars use ≈18pt less height than designed; the table is also denser than the mockup's roomier rows.
- **Evidence:** Pairs `home-s1-1`, `home-s1-2` (divider at y≈61 vs ≈47 in the 1000-px scaled halves).
- **Direction:** Match chrome paddings or document the compact variant.

#### S-022 — Paste field and table do not share a left edge

- **Screen / component / state:** Home with table
- **Severity:** Inconsistent  ·  **Verified:** rendered
- **Mockup:** `.tablewrap{padding:6px 22px 82px}` (L226); `.hero{padding:30px 22px 22px}` — field and table share the 22px gutter.
- **App:** `tableLayout`: paste block `.padding(.horizontal, 30)`; table fills the pane (select box at x≈8pt). Measured on the 980 render: the field's left edge sits ≈22pt to the right of the select-box column's left edge; the right edges differ likewise.
- **Gap:** Misaligned left/right edges between the hero and the table make the page look unaligned; the Share-tip strip sits on the field's edge, the table on a different one.
- **Evidence:** Render `home-table-resolved`: the field's outline starts to the right of the table's select boxes.
- **Direction:** One horizontal gutter for hero and table.

#### S-023 — Rail width and structure

- **Screen / component / state:** Left rail, all pages
- **Severity:** Nit  ·  **Verified:** rendered
- **Mockup:** Home `.mg-rail` 160px (L525); Preferences `.prefs .side` 200px (L391); About rail 200px in about.html. design-system.md §4.1 says rail position, width and styling are identical on every page.
- **App:** 160pt everywhere (`MainWindow` `frame(width: 160)`); the Home rail pads 8 on all sides, the Preferences and About rails pad 22 top and bottom.
- **Gap:** App follows the design-system, not the mockup; Preferences group captions and "Sign-in & cookies" are tighter than drawn. Conflict between the two sources is logged in Section 9.
- **Evidence:** Pair `pref-downloads`: mockup rail is wider (200).
- **Direction:** Decide which source rules.

#### S-024 — Border widths: no 2px / 1.5px structural borders

- **Screen / component / state:** Tape Deck
- **Severity:** Inconsistent  ·  **Verified:** code+CSS only
- **Mockup:** Tape Deck structural borders 2px `--ink`; chips/pills/small controls 1.5px (L87, L152, L279, L295, L317).
- **App:** All strokes are `theme.hairlineWidth` = 1pt in both themes (Theme.swift).
- **Gap:** Part of the missing Tape Deck identity (S-002); listed separately for the token matrix.
- **Evidence:** Code.
- **Direction:** Theme-dependent stroke widths.

#### S-025 — Radii differ by theme and from tokens

- **Screen / component / state:** Global
- **Severity:** Inconsistent  ·  **Verified:** code+CSS only
- **Mockup:** Aurora window 18 / card 14 / control 9 / pill 20 / chip 7; Tape Deck 14 / 12 / 8 / 20 / 6 (L77, L85). Banner radius is a literal 11px (L316) and progress/bar pill 20.
- **App:** Aurora radii match. Tape Deck is 10 / 8 / 6 / 14 / 5. Banner uses `cardRadius` (14, mockup 11). Progress bars use radius 2 on a 4pt track (already fully round, like the mockup's `--r-pill` 20 on a 6px bar); action buttons 7 (mockup `--r-chip` 7 ✓); status pill 10 (mockup 20; the 22pt-high pill is fully round in the mockup).
- **Gap:** Tape Deck corners are tighter than designed at every level; Aurora status pills are less round than designed.
- **Evidence:** Pair `home-s5-3` (pills).
- **Direction:** Tape Deck 14/12/8/20/6; status pills fully round.

### 6.5 Elevation

#### S-026 — Elevation values differ from the tokens

- **Screen / component / state:** Dialog, popover, banner, toast
- **Severity:** Inconsistent  ·  **Verified:** code+CSS only
- **Mockup:** Window/cards `--elev-card` = `0 0 0 1px rgba(255,255,255,.02), 0 24px 60px rgba(0,0,0,.6)` Aurora, `8px 8px 0 rgba(0,0,0,.35)` Tape Deck (L81, L87); popover Aurora `0 0 0 1px glow-a, 0 0 34px glow-b, 0 24px 60px rgba(0,0,0,.6)` (L217); toast `0 12px 30px rgba(0,0,0,.4)` (L324); banner `0 10px 34px rgba(0,0,0,.45)` (L316); runway console glow `0 0 0 1px glow-a, 0 0 32px glow-b` (L82).
- **App:** Dialog `shadow(black .35, r24, y8)`; picker popover `shadow(glowB, r20)` (Aurora) or black .35 offset 3 (Tape Deck) with no 1px glowA ring; banner `shadow(black .45, r17, y10)` ≈ mockup; toast has no shadow; paste field has no glow.
- **Gap:** Surfaces float less than designed; the toast and the paste "console" look flat against the table.
- **Evidence:** Renders `dlg1`, `chrome-toast`, `home-table-resolved`.
- **Direction:** Use the elevation tokens.

### 6.6 Iconography

#### S-027 — SF Symbols replace the bundled Phosphor/Lucide icon sets

- **Screen / component / state:** Global iconography
- **Severity:** Inconsistent  ·  **Verified:** rendered
- **Mockup:** Icons are bundled SVGs, Phosphor Bold on Tape Deck, Lucide on Aurora (design-system.md §3.4), about 26 glyphs; nominal 16px, 15px nav, 20–22px banner/onboarding. Mockup draws inline 2px-stroke SVGs through `.ico{width:1em;height:1em}` (L519).
- **App:** `Icon` maps 16 kinds to SF Symbols (`pause.fill`, `play.fill`, `xmark`, `arrow.up.to.line`, `arrow.clockwise`, `key.fill`, `folder`, `globe`, `trash`, `doc.text`, `arrow.up.arrow.down`, `chevron.up/down`, `line.3.horizontal.decrease.circle`, `tablecells`, `exclamationmark.triangle.fill`) at weight .medium; other glyphs are SF Symbols set inline (checkmark, chevron.down, xmark, puzzlepiece.extension, checkmark.square.fill) or text characters (`↻`, `↗`, "GH"). No theme switch.
- **Gap:** The icon style is the system's (filled pause/play, circled filter) rather than the stroke weight that matches the hairline borders; both themes get the same set. Disclosure carets, copy, terminal, shield, nav icons from the DS list do not exist.
- **Evidence:** Render `home-table-all-states-full` action column: filled play/pause beside outline trash/globe; mockup buttons use uniform 2px outline glyphs.
- **Direction:** Bundle the glyph set per theme.

#### S-028 — Icon sizes and weights vary

- **Screen / component / state:** Global iconography
- **Severity:** Inconsistent  ·  **Verified:** rendered
- **Mockup:** Dense 16px, nav 15px, banner/onboarding 20–22px (DS §3.4); action buttons 27px with 11px glyph (L293).
- **App:** Row actions 11pt regular; header sort/filter 11pt medium drawn into a 12pt box; picker chevron 9 semibold; dialog warning 20; tip icon 12; ClearLink × 11; share-tip × 10; checkmarks 10–12; warning 12 in notes.
- **Gap:** There is no consistent optical size; sort and filter icons at 12pt next to 10pt caps look cramped; the filter glyph (circled) is heavier than the sort arrows.
- **Evidence:** Render `home-table-all-states-full` header; row action icons.
- **Direction:** One size ladder (16/15/20).

#### S-029 — Glyph characters mixed with symbols

- **Screen / component / state:** Health chips, Learn more, Developer links
- **Severity:** Nit  ·  **Verified:** rendered
- **Mockup:** Mockup chip refresh uses an inline SVG `refresh-cw`; icon links use text "GH/in/X" plus a globe SVG.
- **App:** Chip refresh is the text glyph "↻" (mono 11); "Learn more ↗" is a text arrow (Inter 12 medium); "set up" chip suffix is text; GH badge is letters (recorded decision in DS §4.8).
- **Gap:** Glyph metrics depend on the font's coverage of ↻ (JetBrains Mono 11 in the chip) and ↗ (Inter 12 in the button); ↻ looks slightly off-baseline in chips.
- **Evidence:** Render `chrome-two-hosts-busy` chip glyphs.
- **Direction:** Use icons from the set.

### 6.7 Motion and interaction states

#### S-030 — Brand orb spins only while something downloads; no row motif

- **Screen / component / state:** Brand row, rows
- **Severity:** Inconsistent  ·  **Verified:** code+CSS only
- **Mockup:** Aurora `.orb{animation:spin 6s linear infinite}` always (L137); row motif 14px 2s on actively downloading rows (design-system.md §2); Tape Deck reel (L138-140).
- **App:** `MotifView(isActive: jobRunning, size: 20)` in the header (static when idle); no MotifView in any table row; About orb size 56 static; Onboarding header orb always active; reel not implemented.
- **Gap:** The brand mark is mostly still; the "this row is working" cue from the design is missing, so an active row only has a thin progress bar.
- **Evidence:** Render `home-table-all-states` (running row has no motif); code for spin period (6s).
- **Direction:** Add the 14px row motif; decide idle orb behaviour.

#### S-031 — Reduced-motion handling

- **Screen / component / state:** MotifView, HealthStrip, Toast, Dialog
- **Severity:** Nit  ·  **Verified:** code+CSS only
- **Mockup:** `@media (prefers-reduced-motion:reduce){*{animation:none!important;transition:none!important}}` (L493).
- **App:** `accessibilityReduceMotion` is honoured in MotifView (no spin), HealthStrip (no spin/pulse), ToastHost (opacity-only, no slide), ConfirmationDialog (no scale/fade). System controls (ProgressView) are not covered.
- **Gap:** Largely correct; the probe spinner (`ProgressView`) and onboarding step spinner keep animating.
- **Evidence:** Code.
- **Direction:** Replace the indeterminate spinner when reduce-motion is on.

#### S-032 — Easing/duration tokens not used

- **Screen / component / state:** Global motion
- **Severity:** Nit  ·  **Verified:** code+CSS only
- **Mockup:** `--ease:cubic-bezier(.2,.7,.2,1)`, `--dur:160ms` (L80); toggle thumb `transition: all 160ms` (L412); chip spin 900ms linear, pulse 1200ms ease-in-out .35→1 (L453-458).
- **App:** Dialog `easeOut(0.16)` (duration ✓, curve differs); chip spin `linear(0.9)` ✓; pulse triangle wave 1.2s .4→1 (≈ ✓); toast has a `.transition` but the center mutates without `withAnimation`, so it likely appears/vanishes instantly (not verified live); no hover/press transitions.
- **Gap:** Motion is mostly absent; the one custom easing (dialog) misses the token curve.
- **Evidence:** Code.
- **Direction:** Share the ease/duration token.

#### S-033 — No hover or pressed states

- **Screen / component / state:** Global interaction styling
- **Severity:** Inconsistent  ·  **Verified:** code+CSS only
- **Mockup:** Hover rules: `tbody tr:hover td{background:var(--panel)}` (L273), `.pop .prow:hover` accent 12% (L220), `.mrow:hover` (L342), `.fmenu/.colmenu label:hover` (L258, L267), `.thc .sortbtn:hover` border + text (L252), `.colrsz:hover::after` accent-2 (L547), `.iconlink:hover` (L473), ctxmenu rows (L554).
- **App:** Only SkinnedPicker rows react to hover (`onHover` accent 12%). Rail items, nav, table rows, header icons, resize handles, Grab, segments, toolbar buttons have no hover; `.buttonStyle(.plain)` removes pressed feedback (only `PlaylistPickerButtonStyle` dims on press, at 0.75 opacity; the playlist picker's footer and tool buttons use it).
- **Gap:** The UI feels inert; there is no signal which header icon is clickable.
- **Evidence:** Code (hover cannot be rendered offscreen).
- **Direction:** Add hover/pressed per the mockup rules.

### 6.8 Logo placement

#### S-034 — Brand row logo placement

- **Screen / component / state:** Brand row, onboarding header, About
- **Severity:** Nit  ·  **Verified:** rendered
- **Mockup:** `.hdr` padding 15px 22px, gap 12px, orb 20×20 (`.orb` L136), wordmark 18px/700 `-.02em` (L141), nav right.
- **App:** Brand row padding 22 horizontal / 12 vertical, spacing 12, `MotifView` 20 + Sora 17 semibold wordmark, nav right. Onboarding header identical minus nav. About identity block uses a 56pt orb (mockup 64×64, `.orb.big` L462) with a 12pt gap then 20pt title.
- **Gap:** Placement and spacing match; the row is ≈14pt shorter than the mockup (see S-021) and the wordmark is 1pt smaller and lighter (S-008). A native title bar sits above the brand row (see S-038), so the brand is shown twice if the window title is "MediaGrabber". Artwork is temporary and not audited.
- **Evidence:** Pair `home-s1-1`; render `about1`.
- **Direction:** Match 60pt row, 18/700 wordmark, 64pt About orb.

### 6.9 Native-control leakage

#### S-035 — Columns menu and column-filter menu are system menus

- **Screen / component / state:** Home table / Columns, header filter
- **Severity:** Ugly  ·  **Verified:** code+CSS only
- **Mockup:** Skinned `.colmenu` (180px, panel-solid, 1px stroke, radius `--r-control`, shadow `0 12px 40px rgba(0,0,0,.55)`, checkbox rows 13px accent-2, locked rows .5 opacity; L264-270) and `.fmenu` (190px; caption "FILTER" mono 10; checkbox list; Clear/Apply buttons; L255-263).
- **App:** Columns = SwiftUI `Menu { Button … }` with `.menuStyle(.borderlessButton)` (checkmark `Label`s; disabled Actions row). Filter = `NSMenu` popped with `NSMenu.popUpContextMenu` (`presentFilterMenu`): checkmark items or a disabled "(none)", no header, no Clear, no Apply. Not renderable offscreen.
- **Gap:** Two of the most-used table controls open plain macOS menus in a fully skinned app; the filter menu cannot "clear" a filter except by clicking each ticked item or "Clear filters" only in the filtered-empty state.
- **Evidence:** Not visually verified (native menus). Code values above.
- **Direction:** Use the skinned popover for both.

#### S-036 — Toggle, Stepper and Button use system styling

- **Screen / component / state:** Preferences, Onboarding, Sheets
- **Severity:** Ugly  ·  **Verified:** rendered
- **Mockup:** `.toggle` 34×20 pill with 14px thumb, accent when on (L411-413); `.stepper` − value + 26×26 skinned buttons (L408-410); `.btn-txt` skinned buttons radius 9 (L414-415).
- **App:** `Toggle("", isOn:).labelsHidden()` renders the macOS checkbox; `Stepper` renders system chevron pair (value text placed under it in "Simultaneous downloads", left of it in "Automatic retries" with an `.offset(x: -44)` hack, left of it with a Text in Speed limit); Show in Finder/Reset/Open buttons are system bordered buttons.
- **Gap:** Preferences — the screen with the most controls — mixes skinned segments/pickers with stock macOS widgets. Value placement differs between the two steppers.
- **Evidence:** Renders `pref-downloads`, `prefs-network` (checkbox, stepper), `pref-advanced` (system "Reset…" in red text on a tinted fill).
- **Direction:** Skin toggle, stepper and text buttons.

#### S-037 — Sheets use system sheet chrome

- **Screen / component / state:** Shield setup, Playlist picker
- **Severity:** Inconsistent  ·  **Verified:** code+CSS only
- **Mockup:** Playlist picker is an in-window modal over `.backdrop` (rgba(4,5,7,.55)); card `.modal` 560px, radius `--r-window` 18, 1px stroke, `0 30px 80px rgba(0,0,0,.6)` (L329-331); confirmation dialog is an in-window card (L358-371).
- **App:** `.sheet` for ShieldSetupSheet and PlaylistPickerView (macOS sheet: system corner radius, shadow, material; width 460 / 620–820 × 520–680) while ConfirmationDialog is a custom overlay with `ground .6` scrim.
- **Gap:** Three modals, two presentations: the picker and shield sheets slide down from the title bar with system chrome; dialogs fade in as skinned cards.
- **Evidence:** Content renders `playlist-picker`, `shield4` (sheet frame itself not renderable).
- **Direction:** Pick one modal presentation.

#### S-038 — Window chrome and title bar

- **Screen / component / state:** Main window
- **Severity:** Nit  ·  **Verified:** code+CSS only
- **Mockup:** Custom window: 980×720, radius 18, 1px stroke, deep shadow, no title bar (L133).
- **App:** Plain `WindowGroup` (titled, resizable, `.defaultSize(980, 720)`, `.windowResizability(.contentMinSize)`; min content 820×560 set in `MainWindow`). No `.windowStyle`, toolbar or hidden title bar. Window radius/shadow are the system's (Theme.windowRadius is unused).
- **Gap:** A system title bar and traffic lights sit above the brand row; the Tape Deck brand-colour header and 14/18pt window radius cannot appear. Not visually verified (no Screen Recording).
- **Evidence:** Code only.
- **Direction:** Decide on unified title bar.

#### S-039 — Debug menu and native alert in the menu bar

- **Screen / component / state:** Menu bar
- **Severity:** Inconsistent  ·  **Verified:** code+CSS only
- **Mockup:** No Debug menu in the mockup or design-system.md.
- **App:** `DebugMenuCommands` is attached in `MediaGrabberApp.commands` without a build-configuration guard: "Debug" menu (Force Onboarding (Relaunch), Reset State (Relaunch)…, Concurrency Cap ▸ 1–6) and an `NSAlert` ("Reset all local state?", warning style, buttons "Reset and Relaunch"/"Cancel").
- **Gap:** A developer menu with a destructive reset is in the shipped menu bar; the alert is a stock NSAlert in an app whose other confirmations are skinned.
- **Evidence:** Not visually verified (menu bar / alert).
- **Direction:** Confirm whether this ships; skin or remove.

#### S-040 — Focus rings are system defaults except grid rows

- **Screen / component / state:** Global
- **Severity:** Nit  ·  **Verified:** code+CSS only
- **Mockup:** Dialog focus ring `box-shadow:0 0 0 2px var(--accent)` on the focused button (L369).
- **App:** SwiftUI plain buttons draw the system focus ring (accent colour from System Settings, not the theme's); grid rows draw a 2px accent inset rectangle (GridRowView) ✓; dialog Cancel/Confirm have `keyboardShortcut` but no themed ring.
- **Gap:** Keyboard users see a blue/system-tinted ring on some controls and a mint ring on others.
- **Evidence:** Not visually verified (offscreen windows show no focus).
- **Direction:** Theme the focus ring.

#### S-041 — Scrollbars and tooltips are system-drawn

- **Screen / component / state:** Table, Preferences, About
- **Severity:** Nit  ·  **Verified:** code+CSS only
- **Mockup:** Mockup shows no custom scrollbars; row/header tooltips use `title`.
- **App:** AppKit `NSScrollView` with `autohidesScrollers`, SwiftUI `ScrollView`s with system indicators; native `toolTip` on row actions (label strings), Title cells (full title), Status cells (remark) and Developer link (`.help`).
- **Gap:** Overlay scrollers follow the system's appearance (dark under Aurora, light under Tape Deck's forced light scheme); tooltips are system yellow/grey rather than themed. Hover tooltips cannot be rendered offscreen: not visually verified.
- **Evidence:** Code.
- **Direction:** None required unless the design wants themed tooltips.

### 6.10 Layout and responsiveness

#### S-042 — Row actions are off-screen at the default window size

- **Screen / component / state:** Home table at 980×720 and 820×560
- **Severity:** Broken  ·  **Verified:** rendered
- **Mockup:** Table rows end with the Actions column inside the pane (home.html 1.2/5.3: pause/cancel/… buttons visible).
- **App:** Default visible columns Title 200 + Progress 100 + Speed 72 + ETA 72 + Type 96 + Quality 112 + Size 80 + Added at 120 + Actions 196 = 1048pt, plus the 32pt select column = 1080pt (the grid has no inter-column spacing), against an ≈820pt table viewport; `fillViewportWithTitle` only grows Title. At 980 wide the visible area ends mid "ADDED AT" and Actions is behind a horizontal scroll (autohiding scroller). At 1440 wide everything fits.
- **Gap:** At the default window every row's buttons (pause, cancel, reveal, remove) are hidden until the user scrolls sideways; users won't discover them.
- **Evidence:** Renders `home-table-all-states` (980) vs `home-table-all-states-full` (1440, Actions visible); `home-table-all-states-min` ends at QUALITY.
- **Direction:** Fit the default columns to the default window or collapse columns responsively.

#### S-043 — Default columns show no status; failed rows look like saved rows

- **Screen / component / state:** Home table / default columns
- **Severity:** Inconsistent  ·  **Verified:** rendered
- **Mockup:** Mockup tables show a Status pill column (1.2, 5.2, 5.3) next to Remark; design-system.md §4.2.3 hides Status by default and relies on the rail.
- **App:** Default columns are Title, Progress, Speed, ETA, Type, Quality, Size, Added at (`ColumnID.defaultVisible`) plus Actions (appended by `ColumnConfig.init`). With Status and Remark hidden, "Failed", "Saved", "Cancelled", "Queued" rows are visually identical except for the action icons that sit off-screen (S-042).
- **Gap:** In the All view a failed download cannot be told from a finished one. (Conflict between mockup and design-system; see Section 9.)
- **Evidence:** Render `home-table-all-states` rows 1–7.
- **Direction:** Decide whether a status cue (dot/pill) is visible by default.

#### S-044 — Dead space and centring at large sizes

- **Screen / component / state:** First-run Home, About
- **Severity:** Nit  ·  **Verified:** rendered
- **Mockup:** Hero is top-left aligned at 22px padding with full-width field (L169); step cards max 660 centred (L478).
- **App:** First-run layout is vertically centred with Spacers and `maxWidth: 760`: at 1440×900 the block floats with ≈280pt empty above it and ≈370pt on each side; About/Developer identity blocks start at 30pt top padding (mockup adds 30pt margin on top of the pane padding).
- **Gap:** Looks lost on large windows; the mockup anchors the hero to the top.
- **Evidence:** Renders `home-firstrun-full`, pair `about1`.
- **Direction:** Anchor hero to the top; cap width consistently.

#### S-045 — Preferences panes scroll as one block

- **Screen / component / state:** Preferences
- **Severity:** Inconsistent  ·  **Verified:** code+CSS only
- **Mockup:** Pane title, sub and rule are fixed; only rows scroll (`.prefs .main-scroll`, L395-396; design-system.md §4.6).
- **App:** `PreferencesView` wraps the whole `paneBody` (header + rows) in one `ScrollView`.
- **Gap:** At 560pt height the Downloads list continues below the fold, and because the title is inside the scroll view it scrolls out of sight with the rows.
- **Evidence:** Render `prefs-downloads-min`.
- **Direction:** Pin the pane header.

#### S-046 — Preference rows stretch across wide windows

- **Screen / component / state:** Preferences at 1440×900
- **Severity:** Nit  ·  **Verified:** rendered
- **Mockup:** Pane fixed at the 980pt window: label left, control right within ≈750pt of each other (`.prefs .main`, L395-396).
- **App:** `PreferencesView` ScrollView with `maxWidth: .infinity` and 30pt padding; rows span the whole pane.
- **Gap:** At 1440pt the label and its control are ≈1100pt apart with only a hairline between; helper text and control are hard to associate.
- **Evidence:** Render `prefs-downloads-full`.
- **Direction:** Cap the pane width (≈ 760pt).

#### S-047 — Minimum window (820×560)

- **Screen / component / state:** Home, Preferences
- **Severity:** Nit  ·  **Verified:** rendered
- **Mockup:** Mockup is fixed 980×720; design-system.md §6 requires usable narrow widths with the table scrolling inside its own container.
- **App:** Content min size 820×560 enforced in `MainWindow`. At 820: runway title truncates to "How the Mo…"; share tip truncates ("…in System Set…"); table shows Title…Quality only (Size, Added at, Actions behind horizontal scroll); Preferences Downloads lists to "Audio format" before the fold; banner stays on one line; first-run block fits without scrolling.
- **Gap:** Works without overlap or clipped chrome, but row actions are unreachable without scrolling (S-042).
- **Evidence:** Renders `home-table-all-states-min`, `home-table-resolved-min`, `prefs-downloads-min`, `home-firstrun-min`.
- **Direction:** See S-042.


---

## 7. Per-screen findings

### 7.1 Onboarding

#### S-048 — Homebrew-missing step: no command box, system buttons, different labels

- **Screen / component / state:** Onboarding / Homebrew failed
- **Severity:** Ugly  ·  **Verified:** rendered
- **Mockup:** Failed step shows a warning-triangle ring (28px, danger border), the install command in a bordered mono box with a Copy chip, then skinned "Open in Terminal" and "Re-check" buttons (`.step .cmd`, `.rowbtns`, L383-386; onboarding.html 2.2).
- **App:** `OnboardingView.homebrewActions`: three system `Button`s "Copy command", "Open Terminal", "Check again" (default style, SF font) and no command box in this state; failed icon is a 1.5pt danger ring with an "!" glyph (SF bold 12).
- **Gap:** The most important recovery screen uses stock buttons next to skinned ones; the user cannot see what "Copy command" copied; labels differ from the design ("Open in Terminal", "Re-check").
- **Evidence:** Pair `onb2`: mockup shows the command block and pill buttons; app shows three flat grey buttons.
- **Direction:** Skin the actions; show or explain the command.

#### S-049 — Running step uses a tiny system spinner and no progress

- **Screen / component / state:** Onboarding / install running
- **Severity:** Ugly  ·  **Verified:** rendered
- **Mockup:** Running/now step: accent-bordered 28px ring with step number (`.step.now .ic`, L380); design-system.md §4.5 says "spinner running".
- **App:** `ProgressView().controlSize(.small).tint(accent)` inside the 28pt slot (system spinner ≈16pt) with the static summary "Installing — this can take a few minutes."; only the shield step swaps in stage text.
- **Gap:** The only sign of work is a small spinner; the Homebrew and downloader steps show no stage text beyond the static sentence.
- **Evidence:** Render `onb2-running` (spinner barely visible next to the step title).
- **Direction:** Use the themed running ring/spinner.

#### S-050 — Onboarding column and text are larger than the mockup

- **Screen / component / state:** Onboarding
- **Severity:** Nit  ·  **Verified:** rendered
- **Mockup:** `.onb` max-width 620, padding 44px 30px; h1 26px; lead 13px/1.6; step title Sora 14; summary 12px (L374-382).
- **App:** Column 560 wide, vertical padding 44; h1 Sora 30; lead Inter 14; step title Inter 15 semibold; summary Inter 13.
- **Gap:** Text is 1–4pt larger. The column is the same width as the mockup's (620 max-width less 30px side padding on each side = 560), so the larger type and longer lead copy are what wrap the lead to two lines.
- **Evidence:** Pair `onb1`.
- **Direction:** Match the mockup sizes.

#### S-051 — Install command box styling

- **Screen / component / state:** Onboarding / step 2
- **Severity:** Nit  ·  **Verified:** rendered
- **Mockup:** `.cmd` mono 11 on `--ground`, stroke border, chip radius, padding 8px 10px; Copy chip Sora 10 (L383-384).
- **App:** Mono 12 text on `panel` with stroke border at `controlRadius`; system "Copy" button (`.controlSize(.small)`).
- **Gap:** Close; Copy is a stock button.
- **Evidence:** Pair `onb1`.
- **Direction:** Skinned Copy chip.

### 7.2 Home first-run and paste field

#### S-052 — First-run step cards and hero layout

- **Screen / component / state:** Home first-run
- **Severity:** Inconsistent  ·  **Verified:** rendered
- **Mockup:** Hero top-left (kicker, h1, full-width field `.field.solo`), then cards in a centred 660px grid: border `--border-w` stroke, padding 16, number mono 11 `--accent`, title Sora 13, text 12px/1.5 (L169-176, L476-484, L483).
- **App:** Block is vertically centred, max 760: kicker, h1, paste card, then three equal full-width cards (panel fill, no border, padding 12, number mono 12 **faint**, title Inter 13 semibold, text Inter 12 dim).
- **Gap:** The cards lose their outline and accent step numbers; they stretch to the field width instead of a compact 660 group.
- **Evidence:** Pair `home-s1-1`: mockup cards are outlined with mint numerals; app cards are borderless with grey numerals.
- **Direction:** Outlined 660px cards, accent numerals, top anchoring.

#### S-053 — Paste field is taller and uses different type

- **Screen / component / state:** Paste field idle
- **Severity:** Inconsistent  ·  **Verified:** rendered
- **Mockup:** `.field` padding 12, gap 10, radius card, border stroke, input mono 13 (L178-183); ≈42pt tall (measured).
- **App:** Card padding 16 around a `minHeight: 34` row ⇒ ≈66pt tall; mono 13 ✓; placeholder overlay "Paste a link" faint ✓; border `stroke` ✓.
- **Gap:** The hero field is ≈24pt taller than designed; at the minimum window it pushes the table down.
- **Evidence:** Pair `home-s1-1` (field outline ≈66pt vs ≈42pt tall).
- **Direction:** 12pt padding.

#### S-054 — Probe error sits under the URL instead of inline

- **Screen / component / state:** Paste field / probe error
- **Severity:** Inconsistent  ·  **Verified:** rendered
- **Mockup:** Failure text inline at the right end of the field, mono 11 `--danger` (`.field .status.err`, L185; home.html 1.5 "That doesn't look like a valid link." right-aligned) (`.probe-err` body 12 also defined, L186).
- **App:** Field holds the typed URL (mono 13), then a second line with the message in Inter 12 danger inside the same card (`pasteField`), optionally a shield prompt button (Inter 12 semibold accent).
- **Gap:** Card grows by ≈26pt on error and the step cards below jump down; the mockup keeps the row height.
- **Evidence:** Pair `home-s1-5`.
- **Direction:** Inline right-aligned status.

#### S-055 — Probing indicator

- **Screen / component / state:** Paste field / probing
- **Severity:** Nit  ·  **Verified:** code+CSS only
- **Mockup:** Not drawn (mockup has no probing state).
- **App:** `ProgressView().controlSize(.small).tint(accent)` right of the field; accessibility "Checking link".
- **Gap:** System spinner beside a skinned field; unverifiable offscreen (spinner not drawn in captures). Audited against the design language: acceptable but unthemed.
- **Evidence:** Render `home-firstrun-probing` shows no spinner (offscreen).
- **Direction:** Themed spinner.

### 7.3 Runway pickers and Grab

#### S-056 — Inline runway: control sizes, fonts and Grab

- **Screen / component / state:** Runway (Type, Format, Language, Save to, Grab)
- **Severity:** Inconsistent  ·  **Verified:** rendered
- **Mockup:** Resolved field = `✓ title` + `.rctrls` group of `.pick` triggers (34px high, radius control, Sora 12, padding 0 12, chevron 13px, max-width 132 with ellipsis) and `.go` Grab (min-height 44, padding 0 24, Sora 700 14, 135° gradient) (L563-569, L198-200, L210-213). No dots/labels in this variant.
- **App:** `RunwayView` inline: four `SkinnedPicker` triggers at 28pt high (Inter 12 medium, padding 8, chevron 9pt semibold, unlimited width) and Grab (Inter 13 semibold, padding 22×8 ≈32pt high, horizontal gradient `goFillStart→goFillEnd`), plus a "✕" clear control (22pt) at the far right that the mockup does not draw.
- **Gap:** Smaller targets, lighter label, and a diagonal gradient vs horizontal; the extra ✕ is unexplained in the mockup. design-system.md §4.2.2 describes a different structure (separate `--panel-hi` card with labelled slots and set/unset dots, Type as a segment) — see Section 9; the app follows neither exactly.
- **Evidence:** Pair `home-s1-4` and `home-s1-2`.
- **Direction:** Size controls 34/44pt; Sora labels; diagonal gradient.

#### S-057 — Picker popover is skinned inside a system popover frame

- **Screen / component / state:** Runway / Preferences pickers
- **Severity:** Inconsistent  ·  **Verified:** rendered
- **Mockup:** `.pop` positioned panel: panel-solid, 1px stroke, radius card, padding 8, caption mono 10 `.1em` faint with hairline, rows 12.5px (title) + mono 10.5 subtitle dim, check accent 11px, hover accent 12% (L216-223); Aurora glow shadow.
- **App:** `SkinnedPicker.popoverBody` inside a SwiftUI `.popover` → NSPopover: system arrow, system corner radius and material surround the skinned card; rows Inter 12, subtitle Inter 11 dim, rows padding 12×4, check accent 10pt, hover accent 12% ✓; caption mono 10 faint ✓.
- **Gap:** The card content matches; the popover's own frame (arrow, material, system shadow) is stock chrome and the capture shows a saturated violet halo (likely the glow shadow clipped to the popover window — treat as unverified). Subtitle font is Inter instead of mono.
- **Evidence:** Popover captures `pop-type`, `pop-res-win1` (card with TYPE / RESOLUTION caption, accent ticks, rows 12pt); halo not trusted.
- **Direction:** Draw the popover without the system frame, or verify the halo.

#### S-058 — Segmented control proportions

- **Screen / component / state:** SkinnedSegment (Preferences)
- **Severity:** Nit  ·  **Verified:** rendered
- **Mockup:** `.seg` 34px high, radius chip, 1px stroke, buttons padding 0 14, min-width 62, Sora 12; selected `--panel-solid` with inset stroke in Aurora (L203-207); selected weight 600.
- **App:** HStack spacing 2, padding 2 around segments: minWidth 52 + 8 side padding, 4 vertical padding ⇒ ≈28pt high; Inter 12 medium (selected not bolder, only brighter).
- **Gap:** Slightly smaller and the selected weight cue is colour-only.
- **Evidence:** Pair `pref-downloads`.
- **Direction:** 34pt, selected 600.

#### S-059 — Share-extension tip strip

- **Screen / component / state:** Home / after first Grab
- **Severity:** Nit  ·  **Verified:** rendered
- **Mockup:** Not in the mockup. Closest language: `.field`/`.toolbar` panels.
- **App:** Bordered strip (panel .6, `hair` stroke, radius control, padding 12×8): puzzle icon (SF 12 faint), Inter 12 dim sentence (one line, truncating), "Open Settings" Inter 12 semibold accent, × (10pt, 20×20 hit).
- **Gap:** Fits the design language; adds a third stacked bordered box between field and table (≈44pt), truncates at 820pt ("…in System Set…"), × target is small.
- **Evidence:** Renders `home-table-resolved`, `home-table-resolved-min`.
- **Direction:** Keep; consider integrating into the Columns row or banner area.

### 7.4 Home table

#### S-060 — Table header lacks grip, bordered icon buttons and resize dividers

- **Screen / component / state:** Home table / header cells
- **Severity:** Ugly  ·  **Verified:** rendered
- **Mockup:** `thead th` mono 10 uppercase `.08em` dim, padding 8 (L248); `.thc` with grip ⋮⋮ (9px, 50%), sort and filter buttons 18×18 radius 5, hover/active borders (`accent` for sort, `accent-2` + panel for filter) (L249-254); resize handle 6px wide with a persistent 1px 60%-height divider, hover accent-2 (L544-547); header checkbox 15px.
- **App:** `GridHeaderCell` draws: title (mono 10 medium, kern 0.8, dim, uppercase ✓), then a sort glyph and a filter glyph (SF 11pt medium in a 12pt box, 14pt advance, `faint`, or `accent` when active); no grip, no box/border, no divider (default AppKit resize cursor only). Header height 30 (mockup ≈35: 8+18+8 padding plus rule). Header checkbox 16pt ✓.
- **Gap:** The header is dense and mute: two tiny icons with no hover affordance, no visible column boundaries, no visible way to see columns can be dragged/resized. The filter glyph (circled lines) is heavier than the sort arrows.
- **Evidence:** Pair `home-s5-3` header vs `home-table-all-states-full` header.
- **Direction:** Add grip/dividers; 18pt icon buttons.

#### S-061 — Columns button location and form

- **Screen / component / state:** Home table / toolbar
- **Severity:** Inconsistent  ·  **Verified:** rendered
- **Mockup:** 27×27 icon-only `.colbtn` at the right end of the header row (`th.th-tools`), "Clear filters" link (Inter 12 accent) left of it; panel fill, 1px stroke, chip radius (L238-243).
- **App:** `ColumnsMenu` is its own row above the table: borderless text button (`tablecells` icon 14 + "Columns" Inter 12 medium dim + system chevron; panel 5% pill), "Clear filters" Inter 12 accent left of it; row adds ≈40pt of height.
- **Gap:** The control floats alone above the grid; its panel background is almost invisible, so it reads as a text label rather than a button.
- **Evidence:** Pair `home-s1-8`.
- **Direction:** Move into the header row as an icon button.

#### S-062 — Status pills: no border, wrong text colours

- **Screen / component / state:** Home table / Status column
- **Severity:** Inconsistent  ·  **Verified:** rendered
- **Mockup:** `.st` mono 10, padding 3px 9px, radius pill, 1px stroke (1.5px Tape Deck), 5px dot with Aurora glow; text colours `s-dl` accent, `s-queue` accent-2, `s-cool` warn, `s-fail` danger, `s-done`/`s-pause` dim (L278-287).
- **App:** `GridStatusCellView`: 22pt capsule (radius 10) filled `panel` with **no border**, 6px dot, mono 10 label; text colour `danger` for Failed, `dim` for Saved/Cancelled, otherwise `text` (white) — Downloading, Queued, Paused, Cooling down, Waiting for network all white.
- **Gap:** Only the dot differentiates running/queued/cooling; text does not carry state colour; no outline distinguishes the pill from the row.
- **Evidence:** Render `home-table-status-remark` vs mockup `home-s5-2` pills.
- **Direction:** Per-state text colours and 1px stroke.

#### S-063 — Remark column can show raw tool output

- **Screen / component / state:** Home table / Remark
- **Severity:** Ugly  ·  **Verified:** rendered
- **Mockup:** Remark is a short plain sentence in dim (design-system.md §4.2.3; `job-status-and-actions.md` §5 "short").
- **App:** For `ErrorClass.unknown(raw:)` the Remark is the raw string (`FailurePresentation.sentence` returns `raw.trimmingCharacters`), e.g. "ERROR: [youtube] abc: Unable to extract uploader id; please report this issue on https://github.com/yt-dlp/yt-dlp/issues"; shown in the cell truncated "ERROR: [youtube] abc:…" and as the notification body.
- **Gap:** Technical text appears in the table and in a macOS notification; violates the plain-language rule (Section 8).
- **Evidence:** Render `home-table-status-remark` row 1.
- **Direction:** Map to a plain sentence; keep raw text behind details.

#### S-064 — Progress bar proportions and fill

- **Screen / component / state:** Home table / Progress
- **Severity:** Inconsistent  ·  **Verified:** rendered
- **Mockup:** `.bar` 110×6, radius pill (fully round), track `rgba(150,150,150,.18)`, fill `--bar-fill` gradient (mint→iris) with `0 0 10px glow-a` in Aurora; Tape Deck 7px with 1.5px ink border (L288-291).
- **App:** `GridProgressCellView`: track 4pt high, radius 2, `panelHi` (8% white), inset 8 each side of the column (≈84pt at the 100pt column), fill is solid `barFillStart` (mint; the gradient end colour is never used), no glow.
- **Gap:** A thinner, flatter bar (radius 2 on a 4pt track is already fully round); loses the Aurora gradient signature. (`home-table-all-states` shows solid mint bars.)
- **Evidence:** Renders `home-table-all-states`, mockup `home-s5-3` (gradient bars).
- **Direction:** 6pt pill bar with gradient and glow.

#### S-065 — Playlist group header and children

- **Screen / component / state:** Home table / playlist group
- **Severity:** Ugly  ·  **Verified:** rendered
- **Mockup:** Header: caret box 16px (radius 5, stroke), tri-state group checkbox, title Sora 600 13, rollup mono 11 dim + 110×5 mini bar, group action chips (Sora 10, padding 4×9, radius chip, stroke, panel) pushed right (`.gh`, L298-306); children indented 28px with a continuous 1px vertical spine at left 12px and a 10px horizontal connector, row dividers start after the spine (L307-313; design-system.md §4.2.4).
- **App:** `GridGroupTitleCellView`: title Inter 13 semibold above a rollup line "N items · M done" (mono 11 dim) + 86×4 bar; caret = plain SF chevron (dim) in the select column, **no group checkbox**; children are not indented and **no spine/connector is drawn** (grep: no spine code); group actions are three borderless text buttons "Pause all", "Retry failed", "Cancel all" (Inter 12 medium, `text` or `faint` when disabled) living in the Actions column; the rollup truncates inside the 200pt title column ("4 items · 1 don").
- **Gap:** An expanded group is indistinguishable from loose rows below its header, so membership and group end are unreadable; actions are text with no button affordance and are off-screen at 980pt (S-042); the rollup is cut mid-word.
- **Evidence:** Pair `home-s5-2--home-table-group-expanded` (right: header with truncated rollup "1 don", children flush left).
- **Direction:** Draw the spine, indent children, tri-state checkbox, chip-style group actions.

#### S-066 — Empty and filtered-empty table body

- **Screen / component / state:** Home table / empty
- **Severity:** Ugly  ·  **Verified:** rendered
- **Mockup:** `.empty-table` centred 13px `--faint` text; header row stays the normal skinned header (L244; home.html 1.8).
- **App:** `emptyTableBody`: a separate pseudo-header row (`emptyHeaderRow`, mono 10 **semibold, sentence-case** "Title", "Progress", no sort/filter icons, no select box) that rendered ≈110pt below the Columns row, then the centred message "No downloads match this filter." / "No downloads — paste a link above." (Inter 13 faint, 4:1 contrast). The code has no spacer (8pt sits under Columns); the row's `Color.clear` select placeholder has a fixed width and no height limit, which is the likely cause of the band.
- **Gap:** The header style changes between empty and populated states (case, weight, icons); there is a large blank band between the Columns row and the header.
- **Evidence:** Render `home-table-filtered-empty`, `home-table-empty`, crop shows header floating mid-pane.
- **Direction:** Reuse the real header; remove the gap.

#### S-067 — Batch (selection) bar

- **Screen / component / state:** Home table / multi-select
- **Severity:** Nit  ·  **Verified:** rendered
- **Mockup:** Bar above the table: `N selected` (Inter 12/500 text), verbs Inter 12/500 accent, Clear dim right; panel-solid, hairline bottom, padding 8×16 (home.html 5.3 inline style).
- **App:** `SelectionBar` matches those values exactly (padding 16×8, Inter 12 medium, accent verbs, dim "Clear", hairline).
- **Gap:** Matches; it sits under the Columns row rather than replacing the toolbar position, so toolbar + bar + header stack three rows. No visual defect.
- **Evidence:** Render `home-table-selected`.
- **Direction:** None.

#### S-068 — Home rail items

- **Screen / component / state:** Home rail
- **Severity:** Nit  ·  **Verified:** rendered
- **Mockup:** `.mg-rail a` Sora 13, padding 8×12, radius chip, active `--panel`/`--text`; badge `.rbadge` mono 9, padding 1×6, white on danger (L525-530).
- **App:** `HomeRail`: Inter 12 (13 on Preferences/About), padding 8×12 ✓, active semibold + `panel`; badge mono 10 semibold `onAccent` on danger capsule ✓; rail 160 wide, 8pt padding.
- **Gap:** Slightly smaller type and no theme font; badge colour differs (improves contrast).
- **Evidence:** Pair `home-s1-8`.
- **Direction:** Align type.

#### S-069 — Dividers use `hair` where the mockup uses `stroke`

- **Screen / component / state:** Brand row, health strip, rail
- **Severity:** Nit  ·  **Verified:** rendered
- **Mockup:** `.hdr`, `.health`, `.prefs .side`, `.mg-rail` borders use `var(--border-w) solid var(--stroke)` (12% white) (L134, L149, L391, L525).
- **App:** `Divider().overlay(theme.palette.hair)` (6% white overlaid on a system `Divider`) between brand row / health strip / rail and page.
- **Gap:** Structural lines are half as strong; panels blend into one another.
- **Evidence:** Pairs `home-s1-1` (mockup lines visibly brighter).
- **Direction:** Use `stroke` for structural edges.

### 7.5 Chrome: health strip, banner, toast, dialog

#### S-070 — Health chips typography and states

- **Screen / component / state:** Health strip (all chip states)
- **Severity:** Inconsistent  ·  **Verified:** rendered
- **Mockup:** `.chip` mono 10, padding 4 vertical / 10 horizontal, radius pill, gap 6, dot 6px with glow, border 1px stroke (1.5 Tape Deck); busy: opacity .85, grey pulsing dot, spinning `↻` 900ms (L151-156, L452-459).
- **App:** Mono 11 dim, padding 5 vertical / 12 horizontal, capsule, gap 8, dot 7px flat; refresh/busy: text "↻" mono 11 dim with 0.9s linear rotation; busy dot `faint` pulsing 1.2s; set-up chip suffix "set up" accent mono 11 medium; popover chips are buttons with no marker that they open a popover.
- **Gap:** Chips are larger and noisier; attention state only on the dot (S-018). The label for the not-set-up shield renders "bot-check shield · not set up  set up" (duplicated phrase, Section 8). Rendered chips show stray vertical ticks at the left/right ends in the capture (likely a snapshot artefact of the stroked capsule; not verified live).
- **Evidence:** Renders `chrome-shield-down-cooldown`, `chrome-two-hosts-busy`, `home-firstrun-full` (chip "not set up  set up").
- **Direction:** Resize to 10pt; theme-coloured attention state.

#### S-071 — Host cooldown popover is unskinned

- **Screen / component / state:** Health strip / cooldown chip popover
- **Severity:** Ugly  ·  **Verified:** code+CSS only
- **Mockup:** DS §4.1: small popover with why, when it clears, "Retry now". No mockup frame; `.pop` language applies (L216-223).
- **App:** `HostRatePopover`: default SwiftUI popover, VStack padding 12, min width 240, hosts in `.headline` (system font), detail line system body, buttons "Retry now"/"Retry all" default system buttons. Not rendered (popover capture hit the wrong control).
- **Gap:** Off the design language: system fonts, system buttons, no panel-solid/stroke card. Not visually verified.
- **Evidence:** Code values.
- **Direction:** Use the picker popover language.

#### S-072 — Warning banner

- **Screen / component / state:** Warning banner (network, circuit-open, shield)
- **Severity:** Nit  ·  **Verified:** rendered
- **Mockup:** `position:absolute; left/right/bottom 16; padding 12×16; gap 11; radius 11; Aurora gradient; text #141210 13px; button padding 6×14 radius 8 rgba(0,0,0,.16) 12px/600; shadow 0 10px 34px rgba(0,0,0,.45)` (L316-319).
- **App:** `WarningBanner`: horizontal padding 16 / vertical 12, radius 14 (`cardRadius`), horizontal gradient bannerFillStart→End, text `onAccent` #07080B Inter 13 regular, button identical (14×6, radius 8, black 16%), shadow black .45 r17 y10, bottom/side 16 ✓, content inset via `safeAreaInset` ✓.
- **Gap:** Matches closely; radius 14 vs 11 and text colour #07080B vs #141210 (both ≥7:1). Text does not wrap at 820pt in the render (one line, ellipsis not needed). No "strong" lead phrase (copy is a single sentence).
- **Evidence:** Renders `chrome-banner-net-min`, `chrome-banner-circuit`.
- **Direction:** Radius 11.

#### S-073 — Toasts are translucent, collide with the banner and have no shadow

- **Screen / component / state:** Toast
- **Severity:** Broken  ·  **Verified:** rendered
- **Mockup:** `.toast` panel-solid fill, 1px stroke, radius control, padding 10×14, 12px, min-width 240, `0 12px 30px rgba(0,0,0,.4)`; stack right 16 / **bottom 82** (clears the banner); check accent, action link accent-2 underlined 11px (L323-326).
- **App:** `ToastHost`: padding 16 from the corner (no banner offset); fill `panel` (5% white — transparent); stroke; radius 14; Inter 13; action Inter 13 semibold accent with no underline; max width 320 (long titles wrap to two lines); no shadow; no check.
- **Gap:** While a banner is showing, toasts draw over the banner text and show table rows through their body (text illegible). Even without a banner, row text is visible through the toast.
- **Evidence:** Render `chrome-toast-banner`: second toast overprints the banner sentence; first toast shows "Video 1080p" through it.
- **Direction:** Opaque panel-solid, offset above the banner, shadow.

#### S-074 — Confirmation dialog anatomy

- **Screen / component / state:** Confirmation dialog (all dialogs)
- **Severity:** Ugly  ·  **Verified:** rendered
- **Mockup:** Icon (info `--accent-2` / warning `--warn` / error `--danger`, 19×19) inline left of the title on one row; title Sora 600 15 headline; message Inter 13 dim on **one line, ellipsised**; optional "Don't ask again"; buttons Sora 12 padding 9×16 radius control; Confirm filled danger/accent, focus ring 2px accent on the default button; card max 420, padding 22, radius card, `--elev-card`; "already in queue" inverts emphasis (Cancel filled) (L358-371; design-system.md §4.9).
- **App:** `ConfirmationDialog`: only destructive dialogs get an icon — a **filled warning triangle** (20pt, danger) stacked **above** the title; info dialogs have no icon (Moved, Log, Already downloaded, Grab this link, Couldn't open); message wraps to several lines (Inter 13 dim); "Don't ask again" is a stock `Toggle` (system checkbox); buttons are `.plain` with SF Pro 13 labels, Cancel `panel`, Confirm danger/accent with `onAccent` text; no focus ring; "Already in your queue" has accent-filled "Download Again" (not inverted).
- **Gap:** Every dialog looks different from the design (no inline icon, no type colouring, wrapping body); the duplicate-submit dialog nudges users to the unwanted action.
- **Evidence:** Pairs `dlg1`, `dlg5`, `dlg7`; render `dialog-remove` (system checkbox, SF buttons).
- **Direction:** Inline typed icon, single-line message, themed buttons, override for duplicates.

### 7.6 Sheets and modals

#### S-075 — Shield setup sheet

- **Screen / component / state:** Set-up-the-shield sheet (idle, working, done, needs Homebrew, failed)
- **Severity:** Ugly  ·  **Verified:** rendered
- **Mockup:** No mockup frame. Design language: card (panel-solid, stroke, radius card) with Sora title and skinned buttons (confirmation dialog).
- **App:** `ShieldSetupSheet`: width 460, padding 30, fill `ground` (#0C1013), title Sora 20 semibold, explanation Inter 13 `text`, default system buttons ("Not now", "Set up now", "Close", "Setting up…" disabled, "Get Homebrew", "Try again"), `ProgressView` (small, accent), failed state: native `DisclosureGroup("Details")` with the raw detail in mono 11 dim.
- **Gap:** A system sheet around flat content with stock buttons; the working state's spinner does not render offscreen (unverified); the raw detail disclosure uses the system chevron; copy for failures is identical for every cause (Section 8).
- **Evidence:** Renders `shield4` (idle, working, needs Homebrew, failed).
- **Direction:** Skin as a card.

#### S-076 — Playlist picker modal

- **Screen / component / state:** Playlist picker
- **Severity:** Inconsistent  ·  **Verified:** rendered
- **Mockup:** 560px card; header Sora 600 15 + mono 11 meta; banner band "already in your queue" (12px/600 warn on panel-hi); tools row: bordered chip links 11.5 + search field (icon, mono 11, 140px); rows flat with hairlines, 16px accent-2 checkbox, 52×30 thumb radius 5, title 12px, duration mono 10, warning mono 10 warn, warned rows tinted 6% warn, unchecked-off rows .42 opacity; footer mono 12 count + Cancel/Add primary gradient (L329-355).
- **App:** Sheet 620–820 × 520–680 (720 ideal); title Sora 20 semibold; meta Inter 12 dim; banner is a bordered box (warn stroke 40%); tool buttons Inter 12 semibold bordered pills; filter field 220px with placeholder "filter…" (no icon); rows are rounded cards (radius 9, panelHi 100% checked / 45% unchecked) 8pt apart; checkbox = SF `checkmark.square.fill` 16pt accent (mint, not accent-2); thumbnails 52×30 radius 9 placeholder (rendered flat panel); duration mono 11; warning mono 10 warn; no warned-row tint; footer Inter 12 dim; Add button solid accent.
- **Gap:** A heavier, larger, differently-structured list; mint checks vs the mockup's iris; the primary button loses the gradient.
- **Evidence:** Pair `picker`.
- **Direction:** Flat hairline rows, accent-2 checks, gradient primary, 560 card.

### 7.7 Preferences

#### S-077 — Preferences rail captions and rows

- **Screen / component / state:** Preferences rail
- **Severity:** Nit  ·  **Verified:** rendered
- **Mockup:** Group caption mono 10 uppercase `.1em` faint, padding 14×12×6; items Sora 13 dim, padding 8×12, radius chip; rail 200 wide, border-right stroke (L391-394).
- **App:** Caption mono 11 medium uppercase faint (no tracking), spacing 4 between items, groups 16 apart; items Inter 13 (semibold when active); rail 160; no border-right stroke strength (S-069); rail content begins 22pt from the divider.
- **Gap:** Slightly bolder active item; first caption sits tight under the health strip.
- **Evidence:** Pair `pref-downloads`.
- **Direction:** Match caption spacing.

#### S-078 — Preferences pane header order and spacing

- **Screen / component / state:** Preferences / all panes
- **Severity:** Inconsistent  ·  **Verified:** rendered
- **Mockup:** `h2` (20px, Aurora 700) with 4px gap then `p.psub` 12px dim then `.rule` (stroke, `--border-w`) with 12px gaps; pane padding 30; rail 200 wide (L395-400).
- **App:** `PrefPaneHeader` places the **subtitle above the title** (Inter 11.5 dim, 4pt gap) then Sora 20 heavy then a `hair` divider; Diagnostics is the exception (title first, Run check at right, then sub).
- **Gap:** Reading order is inverted and cramped (4pt between sub and title, matching the mockup's 4px, but only 4pt between title and rule where the mockup has 12px); Diagnostics breaks the pattern. Rule uses `hair` (faint) not `stroke`.
- **Evidence:** Pairs `pref-downloads`, `pref-appearance`, `pref-diag`.
- **Direction:** Title → sub → rule.

#### S-079 — Preferences rows and helper text

- **Screen / component / state:** Preferences / PrefRow
- **Severity:** Nit  ·  **Verified:** rendered
- **Mockup:** `.field2` padding 14, label 13/600, helper 11.5 dim max 40ch, controls right-aligned, rows separated by `--hair` (L401-404).
- **App:** `PrefRow`: padding 12, label Inter 13 semibold, helper Inter 11.5 dim with no max width (runs to the control), `hair` divider.
- **Gap:** Very long helper lines on wide windows; otherwise matches.
- **Evidence:** Pair `pref-downloads`.
- **Direction:** 40ch helper max.

#### S-080 — Downloads pane controls

- **Screen / component / state:** Preferences / Downloads
- **Severity:** Inconsistent  ·  **Verified:** rendered
- **Mockup:** Folder button chip; steppers; segments; picker; filename picker with optional custom field; toggle (L401-414).
- **App:** Folder pill `~/Downloads` Inter 12 medium (no chevron ✓ DS); Stepper system (S-036); Media type / Audio language / Audio format = `SkinnedSegment`; Video quality / Filename = `SkinnedPicker`; Clipboard detection = checkbox; custom filename field is a borderless 260pt field with only a panel fill (no stroke).
- **Gap:** Mixed skinned and stock controls; the custom template field lacks the stroke used by the Proxy field.
- **Evidence:** Renders `prefs-downloads`, pair `pref-downloads`.
- **Direction:** See controls finding.

#### S-081 — Network pane field and stepper

- **Screen / component / state:** Preferences / Network
- **Severity:** Nit  ·  **Verified:** rendered
- **Mockup:** Text input panel fill, 1px stroke, radius control, padding 8×10, mono 12, min-width 220 (L405).
- **App:** Proxy field: Inter 12 (not mono), 200pt wide, padding 4, fill panel + stroke; no placeholder, so the empty field is a blank bar; "Off"/"N KB/s" mono 12 dim beside a system Stepper.
- **Gap:** Empty field gives no cue; type face differs from the mockup's mono.
- **Evidence:** Render `prefs-network`.
- **Direction:** Mono 12, 220pt, placeholder.

#### S-082 — Sign-in & cookies pane rows and notes

- **Screen / component / state:** Preferences / Sign-in & cookies
- **Severity:** Nit  ·  **Verified:** rendered
- **Mockup:** `.note` rows with an 8px ok dot or warn glyph, 11.5 dim, max 34ch; `.pending` banner row; `.tip-block` 11.5 dim 52ch (L424-429, L407).
- **App:** Rows built from PrefRow; success/failure lines use SF symbols `checkmark.circle.fill` (accent) / `exclamationmark.triangle.fill` (warn) in a `Label`; FDA granted uses an 8px accent dot ✓; warnings use `Icon(.warning, 12)`; tip block Inter 11.5 dim; "Learn more ↗" accent plain button; Safari "Open System Settings" system button.
- **Gap:** Mixed icon sources; otherwise on language. Only the None state was rendered (other states audited from code).
- **Evidence:** Render `prefs-cookies` (None).
- **Direction:** Use the icon set.

#### S-083 — Diagnostics pane

- **Screen / component / state:** Preferences / Diagnostics
- **Severity:** Inconsistent  ·  **Verified:** rendered
- **Mockup:** Title left, **Run check** gradient Sora 700 14 (padding 12 vertical / 22 horizontal, radius control) at right; sub below; "Last run" mono 11 faint; report card rows 13/mono 12 with verdict colours; `.inline-fix` pill; Copy chips (L439-450).
- **App:** Run check = **solid accent** (no gradient), Sora 13 bold, padding 8 vertical / 16 horizontal; rows mono 12 with `verdict.color`; Update pill (SF `arrow.clockwise` label, warn stroke); Copy/Share chips Sora 12 semibold, chip radius; report has 3 rows (canary, yt-dlp, ffmpeg) vs the mockup's 8.
- **Gap:** The hero action loses the gradient; row padding 8 (mockup 14). The missing report rows are a content gap, noted in Section 9.
- **Evidence:** Pair `pref-diag` (note: yt-dlp/ffmpeg read "not found" because no check had run; the real pane does the same before the first check, see S-100).
- **Direction:** Gradient primary; row padding 14.

#### S-084 — Concurrency note

- **Screen / component / state:** Preferences / Downloads / stepper note
- **Severity:** Nit  ·  **Verified:** code+CSS only
- **Mockup:** `.note .wg` warn glyph + 11.5 dim text (L424-427).
- **App:** `ConcurrencyNote`: SF warning triangle 12pt `warn` + Inter 11.5 dim line.
- **Gap:** On language; sits under the stepper value (extra line). Not rendered (needs running jobs).
- **Evidence:** Code.
- **Direction:** None.

### 7.8 About and Developer

#### S-085 — About / Developer identity block and rows

- **Screen / component / state:** About, Developer
- **Severity:** Inconsistent  ·  **Verified:** rendered
- **Mockup:** Centred mark: About orb 64×64 (`.orb.big`), Developer avatar 64px circle with `--go-fill` gradient and initials Sora 700 20 (L461-465); name Sora, version 12px; rows `.field2` (13/600 label, helper 11.5) with skinned `.btn-txt`; icon links 36px circles (4 of them) (L471-473).
- **App:** About orb 56; Developer avatar 56 flat `panel` with stroke and "SL" Sora 20 bold; name Sora 20 heavy, headline Inter 12 dim; rows mono 12 dim label + Inter 10.5 faint subtitle (S-013); buttons Sora 12 semibold chip radius ✓; only one 28px "GH" icon link (recorded decision; others commented out).
- **Gap:** Smaller marks, flatter avatar, mono labels; the single GH badge looks lonely next to a 4-icon design.
- **Evidence:** Pairs `about1`, `about2`.
- **Direction:** 64pt marks; PrefRow typography.

#### S-086 — About / yt-dlp update pill

- **Screen / component / state:** About / Diagnostics
- **Severity:** Nit  ·  **Verified:** code+CSS only
- **Mockup:** `.inline-fix` Sora 11, padding 3×10, pill radius, warn stroke + warn text (L448).
- **App:** Same recipe with an SF `arrow.clockwise` label ("Update") Inter 11 semibold.
- **Gap:** On language; "↻ Update" in the DS is text glyph + label.
- **Evidence:** Code.
- **Direction:** None.

### 7.9 Interaction overlays

#### S-087 — No drag-and-drop target styling

- **Screen / component / state:** Window drop target
- **Severity:** Inconsistent  ·  **Verified:** code+CSS only
- **Mockup:** home.html 1.1 caption: "The window is a drop target." No drawn overlay in CSS.
- **App:** `.onDrop(of: [.url, .plainText], isTargeted: nil)`: no target feedback; no overlay is drawn when a link is dragged over.
- **Gap:** A valid drop looks identical to an invalid one; not visually verified (drag state).
- **Evidence:** Code.
- **Direction:** Add a drop highlight.

#### S-088 — Column resize/reorder visuals

- **Screen / component / state:** Home table / column interactions
- **Severity:** Inconsistent  ·  **Verified:** code+CSS only
- **Mockup:** column-interactions.html: resize handle 2px accent-2 while dragging with a live width readout; reorder ghost chip (mono 12 uppercase, accent-2 1.5px border, rotate −2°, shadow `0 12px 28px rgba(0,0,0,.45)`), source column 30% opacity with hatch, drop line 4px accent-2 with 9px end dots and glow (`<style>` block of column-interactions.html).
- **App:** AppKit `NSTableView` native column drag (system drag image, system insertion indicator, `allowsColumnReordering`) and resize (system cursor); `ColumnWidthReadoutView`: `NSTextField` "N pt" in monospacedDigit SF 11 medium, `controlBackgroundColor` at 95%, radius 4, `labelColor`.
- **Gap:** The readout uses system colours (`controlBackgroundColor`, `labelColor`) and SF digits rather than palette tokens and mono; the ghost chip, hatch and drop line are absent. Not visually verified (live interaction).
- **Evidence:** Mockup `colint` image vs code.
- **Direction:** Draw the custom ghost/drop line.

#### S-089 — No context menu

- **Screen / component / state:** Home table
- **Severity:** Nit  ·  **Verified:** code+CSS only
- **Mockup:** `.ctxmenu` skinned menu defined (L550-559) as optional batch actions (design note "may still mirror") and drawn in home.html over a multi-selection.
- **App:** No `contextMenu`/`menu(for:)` in the app.
- **Gap:** Gap rather than a defect; logged in Section 9.
- **Evidence:** Code search.
- **Direction:** None.

### 7.10 Further findings

#### S-090 — Picker row hover wash stays after the pointer leaves

- **Screen / component / state:** Runway pickers / popover rows
- **Severity:** Nit  ·  **Verified:** code+CSS only
- **Mockup:** `.pop .prow:hover` washes the row with accent 12% only while hovered (L220).
- **App:** `SkinnedPicker.rowView` `onHover` sets `highlighted` when `hovering` is true and never clears it; the same state drives the arrow-key highlight, so the wash stays on the last row the pointer touched.
- **Gap:** A row looks selected or focused after the pointer has moved to the caption or out of the popover.
- **Evidence:** Code.
- **Direction:** Clear the hover wash when the pointer leaves; keep the keyboard highlight separate.

#### S-091 — First-run Home keeps an empty rail slot

- **Screen / component / state:** Home first-run / rail slot
- **Severity:** Nit  ·  **Verified:** code+CSS only
- **Mockup:** The rail exists only on Home frames with a table (`.body-home2` with `.mg-rail`); first-run frames 1.1, 1.4 and 1.5 have none.
- **App:** `MainWindow` always frames the rail at 160pt and draws the hair divider after it; `rail` returns nothing for Home when `showsTable` is false, so the hero sits beside an empty slot and a vertical rule. Slot width not measured.
- **Gap:** The first-run block is pushed right of centre and bounded by a rule that separates nothing (see S-044 for the centring).
- **Evidence:** Code.
- **Direction:** Draw the rail slot and divider only when the rail has content.

#### S-092 — A busy health chip takes the system disabled fade

- **Screen / component / state:** Health strip / refresh chip while busy
- **Severity:** Nit  ·  **Verified:** code+CSS only
- **Mockup:** `.chip.busy{opacity:.85}` with a spinning `↻` and a pulsing grey dot (L457-458).
- **App:** `HealthStrip.refreshChip` sets `.disabled(isBusy)` on a `.plain` button, so SwiftUI's disabled dimming applies while the glyph rotates. Not rendered.
- **Gap:** The busy chip fades by whatever the system applies instead of the designed 0.85.
- **Evidence:** Code.
- **Direction:** Block the second click without the system dimming; set the busy opacity explicitly.

#### S-093 — Resolved link title typography

- **Screen / component / state:** Paste field / resolved
- **Severity:** Nit  ·  **Verified:** code+CSS only
- **Mockup:** `.field .rtitle` Sora 13 (display face), `--text`, 7px gap to the accent check icon (L564-565).
- **App:** `ResolvedLinkTitle` is Inter 14 medium with an SF `checkmark` (12 semibold) and an 8pt gap.
- **Gap:** The resolved title is a point larger and in the body face; the idle field is mono 13 (S-053), so the field changes face when a link resolves.
- **Evidence:** Code.
- **Direction:** Sora 13.

#### S-094 — Double-click autofit measures the wrong font

- **Screen / component / state:** Home table / column divider double-click
- **Severity:** Nit  ·  **Verified:** code+CSS only
- **Mockup:** Table cells are the 13pt body face (design-system.md §3.2).
- **App:** `ColumnMetrics.autoFitWidth` measures with `NSFont.systemFont(ofSize: 12)`; the cells are Inter 13 (`tokens.cell`).
- **Gap:** An autofitted column can come out narrower than its widest cell, so text still truncates right after the fit.
- **Evidence:** Code.
- **Direction:** Measure with the cell font.

#### S-095 — Empty-state header cells are wider than the live columns

- **Screen / component / state:** Home table / empty and filtered-empty header row
- **Severity:** Nit  ·  **Verified:** code+CSS only
- **Mockup:** The header row stays the normal header (L244), so its columns match the populated table.
- **App:** `DownloadsTable.emptyHeaderRow` sets each label to the column's resolved width and then applies `.padding(.horizontal, Spacing.s2)` outside that frame, so every header cell is 16pt wider than the matching `NSTableColumn`.
- **Gap:** Labels drift further right with every column, so the empty header does not line up with the headers that appear once rows exist. Adds to S-066.
- **Evidence:** Code.
- **Direction:** Reuse the real header (S-066).

#### S-096 — Group action labels do not fit the Actions column

- **Screen / component / state:** Home table / playlist group header / Actions column
- **Severity:** Inconsistent  ·  **Verified:** code+CSS only
- **Mockup:** Group actions are 10px display-face text (L306).
- **App:** `GridGroupActionsCellView` stacks "Pause all", "Retry failed" and "Cancel all" in Inter 12 medium with 8pt gaps and a 4pt leading inset, with no trailing constraint. The labels measure 172pt in the bundled Inter and the borderless buttons add roughly 5pt each, so the stack needs about 205pt in a 196pt non-resizable column.
- **Gap:** The last label runs past the column edge and is cut off at the table's right edge when the Actions column is scrolled into view. S-065 describes the buttons as borderless text; it does not cover this overflow.
- **Evidence:** Label widths measured with the bundled Inter font; button insets estimated.
- **Direction:** Size the labels to fit the column or let the column grow.

#### S-097 — A failed Homebrew step still offers "Install now"

- **Screen / component / state:** Onboarding / Homebrew missing
- **Severity:** Ugly  ·  **Verified:** code+CSS only
- **Mockup:** Frame 2.2 shows the Downloader step as plain text while Homebrew is missing: no command box and no button.
- **App:** When Homebrew is missing the installer sets Homebrew to failed and the downloader to pending, and `OnboardingView.actions` handles `(.downloaderTools, .pending)` on its own. The downloader row therefore shows the command box and the gradient "Install now" button beside the grey Homebrew buttons (S-048).
- **Gap:** Two competing next steps; the more prominent one cannot work until Homebrew is installed.
- **Evidence:** Code.
- **Direction:** Show the downloader action only once Homebrew is present.

#### S-098 — Other failed onboarding steps use a text link to retry

- **Screen / component / state:** Onboarding / failed downloader, shield and test-run steps
- **Severity:** Nit  ·  **Verified:** code+CSS only
- **Mockup:** Only the Homebrew failed state is drawn (Section 9.3).
- **App:** For any failure other than Homebrew, `OnboardingView.actions` shows "Try again" as Inter 12 semibold accent with `.buttonStyle(.plain)` and no fill, while the Homebrew row uses three buttons and the pending steps use gradient buttons.
- **Gap:** The retry control is the weakest-looking element on a failed step.
- **Evidence:** Code.
- **Direction:** Give the retry the same button treatment as the other step actions.

#### S-099 — The download-folder path does not truncate

- **Screen / component / state:** Preferences → Downloads / folder button
- **Severity:** Nit  ·  **Verified:** code+CSS only
- **Mockup:** The folder control is a button chip (L401-414); the frames show a short path.
- **App:** `DownloadsPane.folderButton` applies `.fixedSize()` to a one-line `Text`, so a long path keeps its full width. S-080 only describes the short `~/Downloads` pill.
- **Gap:** A deep folder path pushes the pill past the pane edge instead of shortening with an ellipsis.
- **Evidence:** Code.
- **Direction:** Truncate the middle of the path and show the full path as a tooltip.

#### S-100 — Diagnostics shows "not found" before any check has run

- **Screen / component / state:** Preferences → Diagnostics / report rows
- **Severity:** Broken  ·  **Verified:** code+CSS only
- **Mockup:** Report card rows carry real verdicts (L445); "Last run" is faint until a run exists.
- **App:** `DiagnosticsPaneModel.latestReport` starts as nil and is not seeded from the app's environment report. `reportRows` renders "not found" in `danger` for yt-dlp and ffmpeg whenever it is nil, which is the state on every first visit while "Last run: not yet run this session" is showing.
- **Gap:** A Mac with both tools installed reads as missing both until the user presses Run check. S-083 attributes this text to the render harness; the real pane does the same.
- **Evidence:** Code; the same strings appear in the `pref-diag` render.
- **Direction:** Show a neutral placeholder (or the app's last known report) until a check has run.

#### S-101 — Copy and Share are offered before a report exists

- **Screen / component / state:** Preferences → Diagnostics / action buttons
- **Severity:** Nit  ·  **Verified:** code+CSS only
- **Mockup:** Copy chips sit under a populated report card (L445-450).
- **App:** `DiagnosticsPane` renders "Copy report" and "Share diagnostic bundle" as soon as the pane model exists, including while the last-run line reads "not yet run this session"; `reportText` is empty at that point.
- **Gap:** The buttons look usable but Copy puts nothing on the pasteboard and the shared bundle carries a blank report (the log files are still included).
- **Evidence:** Code.
- **Direction:** Show them once a report exists.


---

## 8. Text audit (full inventory)

Every user-visible string found in the app source, grouped by area. **Verdict** — ✔ true, plain, consistent and (where an action exists) actionable; ⚠ a problem with truthfulness for some cause, plain-language, tone, case, truncation, missing action or naming consistency (see note); ✖ untrue for a cause that triggers it, or exposes a command, tool name or raw tool output, or contradicts a locked string. "n/a" = not rendered by the app. **Style** shows the app value, with the mockup value in parentheses when it differs. Copy rules checked: CLAUDE.md "User-facing copy is true, plain, and actionable".

Naming consistency issues that cut across rows: *shield / protection / helper* for the same feature; *cookies / sign-in / sign in with your browser* for the same feature; *engine / downloader / yt-dlp* for the same tool; *Retry / Restart* for the locked verb "Restart"; Title Case vs sentence case on dialog buttons ("Download Again", "Quit Anyway", "Cancel All", "Move Rows" vs "Start now", "Not now", "Set up now").

### Window chrome and navigation

| ID | Where | Exact text | Verdict | Notes | Style |
|---|---|---|---|---|---|
| T-001 | Brand row | MediaGrabber | ✔ | Product name; repeated in onboarding header, About name, a11y. | WM: Sora 17/600 text (mockup Sora 18/700 -.02em) |
| T-002 | Nav | Home · Preferences · About | ✔ | Consistent with page titles. | NAV: Inter 12/500 (mockup Sora 12) |
| T-003 | Health chip | bot-check shield · on | ✔ | Names the feature "bot-check shield" (also onboarding, sheet). Lowercase mono by design. | CH: mono 11 dim (mockup mono 10) |
| T-004 | Health chip | bot-check shield · offline | ⚠ | "offline" is also the network chip's word; reads like the Mac is offline. Action (↻) has no label; a11y says "Restart bot-check shield". | CH |
| T-005 | Health chip | bot-check shield · not set up + trailing "set up" | ✖ | Renders "not set up  set up" — the chip label and the action suffix repeat the phrase. | CH + accent mono 11/500 |
| T-006 | Health chip | engine · current / engine · update available | ⚠ | "engine" is internal vocabulary; About calls it "Downloader (yt-dlp)", prefs "the downloader". Inconsistent naming for one thing. | CH |
| T-007 | Health chip | online / offline | ✔ | Plain. | CH |
| T-008 | Health chip | `<Site> — m:ss` e.g. "YouTube — 1:35" | ⚠ | Mockup reads "youtube · cooldown 4:12"; the app drops the word "cooldown" so the countdown has no noun. | CH |
| T-009 | Health chip | `<Site> — paused` | ⚠ | "paused" implies user action; the cause is rate-limiting (popover says "Rate-limited — paused"). | CH |
| T-010 | Health chip | N sites cooling down | ✔ | Plain; "cooling down" matches the row status word. | CH |
| T-011 | Health chip a11y | Restart bot-check shield · Update the downloader · "<label>, set up" | ⚠ | Accessible text says "Restart" while the chip glyph is a refresh arrow; "Update the downloader" appears only in a11y. | n/a |
| T-012 | Host popover | `<Site>` / "Cooling down — m:ss · concurrency reduced to 1" / "Rate-limited — paused" / Retry now / Retry all | ⚠ | "concurrency reduced to 1" is jargon; "Retry now" fine. | System .headline + system body |
| T-013 | Banner | No internet connection — downloads paused. They'll resume automatically. | ✔ | True for halt = networkDown; no action needed (no button) — correct. | Inter 13/400 onAccent (mockup 13px #141210) |
| T-014 | Banner | Downloads from YouTube keep getting rate-limited. Wait a while, add browser cookies in Preferences, or turn off a VPN. | ⚠ | Says "browser cookies"; the pane and other copy say "sign-in" (see naming). Advice is conditional on cause (VPN) yet always shown. Button "Retry now". | Inter 13; button Inter 12/600 |
| T-015 | Banner | `N sites` keep getting rate-limited… | ✔ | Plural built from count; grammar OK ("N sites keep"). | same |
| T-016 | Banner | The bot-check shield stopped working — some YouTube downloads may fail or be low-res. [Restart] | ⚠ | Truthful and has an action; "low-res" is informal. Failure sentence for the same cause uses "Bot-check protection is offline." (naming). | same |
| T-017 | Banner | (dependency missing) | n/a | `bannerCopy(.depMissing)` returns nil — no banner; Onboarding takes over. | n/a |
| T-018 | Toast | `<title> saved` + Reveal | ✔ | Matches design-system.md §4.4. Falls back to the URL when no title. | Inter 13 text; action Inter 13/600 accent (mockup 12px, link accent-2 underlined) |
| T-019 | Toast | Bot-check shield restart failed | ⚠ | No reason and no next step (design: "the reason a fix did not work"). | Inter 13 |
| T-020 | Toast | yt-dlp update failed: `<reason>` | ✖ | `<reason>` is raw stderr (`brew reinstall…` output) or an internal string ("yt-dlp not found after reinstall"); names a tool; no action. | Inter 13 |
| T-021 | Notification | `<title>` failed / `<failure sentence>` | ⚠ | For unknown errors the body is raw tool output (see Remark). | system |

### Rail and table

| ID | Where | Exact text | Verdict | Notes | Style |
|---|---|---|---|---|---|
| T-022 | Rail | All · Downloading · Done · Inactive | ⚠ | "Inactive" is the only abstract label (means failed or cancelled); matches the locked rail contract. | RL: Inter 12 (Home) / 13 (Prefs) (mockup Sora 13) |
| T-023 | Rail badge | N (failed+cancelled) | ✔ | a11y "Inactive, N". | mono 10/600 on danger |
| T-024 | Toolbar | Columns | ✔ | — | Inter 12/500 dim + icon |
| T-025 | Toolbar | Clear filters | ✔ | Only offered in the filtered-empty state. | Inter 12 accent |
| T-026 | Empty body | No downloads — paste a link above. | ✔ | Matches design-system.md §4.2.1. | Inter 13 faint (4.03:1) |
| T-027 | Empty body | No downloads match this filter. | ✔ | Action ("Clear filters") sits in another row. | Inter 13 faint |
| T-028 | Filter menu | (none) | ⚠ | Disabled placeholder; DS permits it for unpopulated columns. | NSMenu system font |
| T-029 | Column titles | Title · Status · Remark · Progress · Speed · ETA · Type · Quality · Size · Site · Added at · Finished at · Duration · Destination · Attempt · Client used · Actions | ⚠ | "Client used" is internal vocabulary (player client); "ETA" is jargon-light. Header cells uppercase mono 10. | mono 10/500 +kern .8 dim (matches mockup) |
| T-030 | Cell | — (em dash) for unknown size/finished/attempt | ✔ | Consistent. | Inter 13 dim |
| T-031 | Cell | 15/11/23, 3:55 AM (short date + time) | ⚠ | Two-digit year and locale order are ambiguous; not set in the mockup. | Inter 13 dim |
| T-032 | Quality cell | 1080p · m4a · "m4a → 1080p" | ⚠ | Arrow form is shown when actual ≠ selected; no legend. | Inter 13 dim |
| T-033 | Selection bar | N selected | ✔ | — | Inter 12/500 text |
| T-034 | Selection bar | Pause · Resume · Cancel · Force start · Retry · Retry with cookies · Reveal in Finder · Open in browser · Remove · Show log (verbs offered by eligibility) | ✖ | Locked UI strings are "Restart" and "Restart with sign-in" (job-status-and-actions.md §4); app says "Retry", "Retry with cookies". | Inter 12/500 accent |
| T-035 | Selection bar | Clear | ✔ | a11y "Clear selection". | Inter 12 dim |
| T-036 | Row action tooltips | Pause · Resume · Cancel · Force start · Retry · Retry with cookies · Reveal in Finder · Open in browser · Remove · Show log | ✖ | Same as above for Retry/Retry with cookies. | system tooltip |
| T-037 | Group actions | Pause all · Retry failed · Cancel all | ✖ | Design: "Restart failed". "Cancel all" cancels only cancellable videos. | Inter 12/500 text\|faint |
| T-038 | Group rollup | `N items · M done` | ✔ | Truncated in the cell ("4 items · 1 don"). | mono 11 dim |
| T-039 | Status words | Queued · Probing · Downloading · Paused · Waiting for network · Cooling down · Saved · Cancelled · Failed | ⚠ | Match the locked list. "Probing" is jargon (it means "checking the link"). | mono 10 (white; danger for Failed) |
| T-040 | Remark | #N | ✔ | Queue position. | Inter 13 dim |
| T-041 | Remark | Try again in m:ss | ✔ | Used for cooldown and deferred queued rows. | Inter 13 dim |
| T-042 | Remark | No connection | ✔ | — | Inter 13 dim |
| T-043 | Remark | Rate-limited | ⚠ | "Rate-limited" is jargon for end users (banner says "keep getting rate-limited" too). | Inter 13 dim |
| T-044 | Remark | Waiting for probe slot · m:ss | ✖ | "probe slot" is internal; unexplained. | Inter 13 dim |
| T-045 | Failure sentence | The site is limiting how fast we can download right now. | ✔ | Plain, true for rate_limited. | Inter 13 dim |
| T-046 | Failure sentence | This video isn't available in your region. | ✔ | — | same |
| T-047 | Failure sentence | This video is private. | ✔ | Action (sign in) appears only as the key icon. | same |
| T-048 | Failure sentence | This video is no longer available. | ✔ | — | same |
| T-049 | Failure sentence | This video is age-restricted and needs you to be signed in. | ✔ | Offers key icon (Retry with cookies). | same |
| T-050 | Failure sentence | No internet connection. | ✔ | — | same |
| T-051 | Failure sentence | Couldn't read your browser's sign-in. | ✔ | Names "sign-in". | same |
| T-052 | Failure sentence | The disk is full. | ⚠ | No action; "disk" vs "drive". | same |
| T-053 | Failure sentence | The download folder isn't writable. | ⚠ | Technical word "writable"; no action. | same |
| T-054 | Failure sentence | The download kept ending early. | ✔ | — | same |
| T-055 | Failure sentence | The downloader needs reinstalling. | ⚠ | No action link; Onboarding is the fix. | same |
| T-056 | Failure sentence | Couldn't verify you. Try again, or add browser cookies in Preferences. | ⚠ | Fixed sentence exists but bot-check rows use `BotCheckCopy` instead; "cookies". | same |
| T-057 | Failure sentence | YouTube isn't offering a downloadable video for this link. | ✔ | — | same |
| T-058 | Failure sentence | The quality you picked isn't available for this video. | ✔ | — | same |
| T-059 | Failure sentence | Bot-check protection is offline. | ⚠ | Uses "protection" where UI says "shield". | same |
| T-060 | Failure sentence | (unknown) `<raw tool output>` | ✖ | Raw yt-dlp text shown in Remark and notification. | Inter 13 dim |
| T-061 | Failure sentence | This download failed. | ⚠ | Generic fallback; no cause or action. | same |
| T-062 | Bot-check copy | YouTube didn't accept this request because the bot-check shield stopped working. | ✔ | True for shield down. | same |
| T-063 | Bot-check copy | YouTube didn't accept this request. The bot-check shield that helps with this isn't set up on this Mac. | ✔ | True for shield missing; no inline action. | same |
| T-064 | Bot-check copy | `<Site>` didn't accept this request. Try turning off your VPN, or sign in with your browser in Preferences. / Try again, or sign in with your browser in Preferences. | ✔ | True; uses "sign in with your browser" (vs "cookies" elsewhere). | same |

### Home first-run, paste field, runway

| ID | Where | Exact text | Verdict | Notes | Style |
|---|---|---|---|---|---|
| T-065 | Kicker | PASTE. PICK. GRAB. | ✔ | Hard-coded uppercase string (mockup: CSS uppercase of "Paste. Pick. Grab."). | K: mono 11/500 accent, no tracking (mockup .16em) |
| T-066 | Headline | One link in. One file out. | ✔ | — | H1: Sora 32/600 (mockup 700, -.03em) |
| T-067 | Placeholder | Paste a link | ✔ | Same in mockup. | mono 13 faint |
| T-068 | Step card | 1 Paste a link — Any video page URL. | ✔ | — | Inter 13/600 + 12 dim |
| T-069 | Step card | 2 Pick a format — Video quality or audio only. | ✔ | — | same |
| T-070 | Step card | 3 Press Grab — It saves to your folder. | ✔ | — | same |
| T-071 | Probe a11y | Checking link | ✔ | Only a11y; no visible text. | n/a |
| T-072 | Probe error | That doesn't look like a valid link. | ✔ | — | Inter 12 danger (mockup mono 11 inline) |
| T-073 | Probe error | That site isn't supported. | ✔ | — | same |
| T-074 | Probe error | This video isn't available. | ⚠ | Covers several causes (private, removed, region); shown for `.unavailable` only. | same |
| T-075 | Probe error | No internet connection. | ✔ | — | same |
| T-076 | Probe error | yt-dlp is missing — reopen setup. | ✖ | Tool name; "reopen setup" has no button. | same |
| T-077 | Probe error | Couldn't read the video details. | ⚠ | Used for both malformed output and unknown errors; no action. | same |
| T-078 | Probe error | Couldn't read your browser's sign-in. Close the browser and try again, or pick another in Preferences. | ✔ | — | same |
| T-079 | Probe error | This site is cooling down. Try again in a moment. | ✔ | — | same |
| T-080 | Probe error | This link isn't a video or a playlist. | ✔ | — | same |
| T-081 | Shield prompt | Set up the shield · Restart the shield | ⚠ | Called "the shield" here, "bot-check shield" in chips/sheet. | Inter 12/600 accent |
| T-082 | Runway captions | Type · Resolution · Format · Language · Save to | ⚠ | The design slot is "Format"; video popover caption says "Resolution". | mono 10 uppercase faint |
| T-083 | Runway rows | Video · Audio · 2160p · 1440p · 1080p · 720p · 480p · Best available · M4A · MP3 · Default · `<track label>` · `<folder>` + path · Choose… | ✔ | "Default" language is an unexplained label when tracks are unknown. | Inter 12 |
| T-084 | Runway | Grab | ✔ | design-system.md §4.2.2 also lists "Grab all N" for a playlist (not in the mockup, not built); the mockup's playlist picker footer "Add 12" is built as "Add N". | Inter 13/600 (mockup Sora 14/700) |
| T-085 | Runway a11y | Clear link | ✔ | — | n/a |
| T-086 | Share tip | Grab links straight from Safari: turn on MediaGrabber in System Settings → Extensions. | ✔ | Truthful; action "Open Settings" opens the Extensions pane. | Inter 12 dim |
| T-087 | Share tip | Open Settings · Dismiss | ✔ | — | Inter 12/600 accent |

### Dialogs

| ID | Where | Exact text | Verdict | Notes | Style |
|---|---|---|---|---|---|
| T-088 | Dialog | Reset settings? / All preferences go back to their defaults. Your downloads and table columns aren't affected. [Reset] [Cancel] | ✔ | Message wraps two lines (design: one line). Shown with a warning triangle, DS says error type. | Sora 15/600 + Inter 13 dim |
| T-089 | Dialog | Quit MediaGrabber? / A download is still running. Quit anyway? [Quit Anyway] [Cancel] | ⚠ | Variants: "Downloads are paused — yt-dlp needs reinstalling. Quit anyway?" (tool name); "— a site is rate-limiting you."; "no internet connection. They'll resume…". Title Case "Quit Anyway". | same |
| T-090 | Dialog | File moved / The file is no longer at that location. [OK] | ⚠ | Doesn't say which file; no recovery action. | same |
| T-091 | Dialog | Log unavailable / The log for this download is no longer available. [OK] | ✔ | — | same |
| T-092 | Dialog | Download again? / You've already downloaded this. [Download Again] [Cancel] | ⚠ | Title Case on button vs sentence case elsewhere. | same |
| T-093 | Dialog | Already in your queue / This link is already waiting to download. [Download Again] [Cancel] | ⚠ | Primary emphasis lands on "Download Again" (design wants Cancel emphasised); Title Case. | same |
| T-094 | Dialog | Grab this link? / `<url>` [Grab] [Not now] | ⚠ | Message is a raw URL, wraps; no hint why asked. | same |
| T-095 | Dialog | Couldn't open that link / The link was missing or not a web address. [OK] | ✔ | Curly apostrophe in the title only; straight elsewhere. | same |
| T-096 | Dialog | Start this now? / The oldest download in progress will go back to the queue. [Start now] [Cancel] | ✔ | Matches job-status-and-actions.md §6. | same |
| T-097 | Dialog | Remove this download? / This deletes it from your list, along with any partial file and its log. [Remove] [Cancel] + Don't ask again | ⚠ | "its log" jargon-light. Suppression label straight apostrophe. | same |
| T-098 | Dialog | Cancel this playlist? / Videos still waiting or downloading will stop. Files already saved stay. [Cancel All] [Keep] | ⚠ | "Cancel All" Title Case; the verb "Cancel" appears on both sides of the question ("Cancel this playlist?" vs a "Keep" cancel button) — fine but unusual. | same |
| T-099 | Dialog | Clear sorting? / Moving rows turns off column sorting for this session. [Move Rows] [Cancel] | ⚠ | Title Case; "for this session" claim — sort is persisted in columns.json, so unclear. | same |
| T-100 | Dialog | MediaGrabber `<v>` is available / You have `<cur>`. Download the new version? Quit and replace the app to update. [Download] [Later] | ⚠ | Two-step instruction in a one-line message; wraps. | same |
| T-101 | Dialog | Cancel selected downloads? / Videos still waiting or downloading will stop. Files already saved stay. [Cancel] [Keep] | ⚠ | Confirm button "Cancel" and the dialog's own dismiss ("Keep") are inverted vs the usual pattern. | same |
| T-102 | Debug alert | Reset all local state? / This wipes the download queue, history, and preferences, then relaunches. This cannot be undone. [Reset and Relaunch] [Cancel] | ⚠ | Developer-facing, in release builds. | NSAlert system |

### Shield sheet

| ID | Where | Exact text | Verdict | Notes | Style |
|---|---|---|---|---|---|
| T-103 | Sheet title | Set up the bot-check shield | ✔ | — | Sora 20/600 |
| T-104 | Sheet body | YouTube sometimes asks apps to prove they aren't a robot. The bot-check shield is a small free helper that handles this for you. Setting it up takes about a minute. | ⚠ | Uses "helper" (third name for the feature: shield / protection / helper). | Inter 13 text |
| T-105 | Sheet body | Setting up. This can take a minute. | ✔ | — | same |
| T-106 | Sheet body | All set. Try your download again. | ✔ | — | same |
| T-107 | Sheet body | Setting this up needs Homebrew, a free tool installer for Mac. Install Homebrew, then come back and try again. | ✔ | Action "Get Homebrew" present. | same |
| T-108 | Sheet body | Setup didn't finish. Check your internet connection and try again. | ✖ | Fixed text for every failure including "installed, but the shield did not start" and node failures; asserts a cause (internet) that may be false. | same |
| T-109 | Sheet buttons | Not now · Set up now · Close · Setting up… · Done · Get Homebrew · Try again · Details | ✔ | "Close" vs "Not now" depending on state. | system buttons |
| T-110 | Sheet details | `<raw detail>` (mono 11) | ⚠ | Raw text behind "Details" is allowed by policy; detail strings can name node/brew. | mono 11 dim |

### Onboarding

| ID | Where | Exact text | Verdict | Notes | Style |
|---|---|---|---|---|---|
| T-111 | Onboarding | FIRST RUN | ✔ | — | mono 11/500 accent |
| T-112 | Onboarding | Let's get you set up. | ✔ | — | Sora 30/600 (mockup 26/700) |
| T-113 | Onboarding | MediaGrabber uses a few free tools to do the actual downloading. Anything already on your Mac is checked off below. | ✔ | — | Inter 14 dim (mockup 13) |
| T-114 | Onboarding step | Homebrew — A free tool installer for Mac. The other tools install through it. / Already installed. | ✔ | — | Inter 15/600 + 13 dim |
| T-115 | Onboarding step | Downloader + media tools — Does the actual downloading. Required. | ⚠ | Duplicates the intro sentence; does not say what is installed. The mockup says "Installs yt-dlp and ffmpeg. Required.", which names tools the copy rule disallows. | same |
| T-116 | Onboarding step | `brew install yt-dlp ffmpeg` + Copy | ✖ | Shows a command and tool names in a flow for non-technical users (CLAUDE.md rule) — but design-system.md §4.5 and the mockup require it: recorded conflict. | mono 12 on panel |
| T-117 | Onboarding step | Install now · Set up · Continue · Try again · Copy command · Open Terminal · Check again | ⚠ | "Open Terminal" asks a non-technical user to use a terminal. | Inter 13/600 / system |
| T-118 | Onboarding step | Installing — this can take a few minutes. | ✔ | — | Inter 13 dim |
| T-119 | Onboarding step | Setup didn't finish. Check your internet connection and try again. (downloader failed) | ⚠ | Asserts internet as the cause for any failure (e.g. disk, permissions). | same |
| T-120 | Onboarding step | Bot-check shield — Helps YouTube downloads get through. Recommended, not required. | ✔ | — | same |
| T-121 | Onboarding step | Setting this up needs Homebrew first. / Setup didn't finish. You can try again later from the top of the window. (shield) | ⚠ | "top of the window" = health chip; second sentence is true only if the chip is visible. | same |
| T-122 | Onboarding step | Test run — We'll check a known video to confirm everything works. / Everything works. / The check didn't pass. | ⚠ | Failure gives no cause or action ("Try again" link only). | same |
| T-123 | Onboarding | Continue unlocks once the required tools are installed. | ✔ | Faint 12px (4:1). | Inter 12 faint |
| T-124 | Onboarding | Already installed. · Installed. | ✔ | — | Inter 13 dim |

### Playlist picker

| ID | Where | Exact text | Verdict | Notes | Style |
|---|---|---|---|---|---|
| T-125 | Picker | Choose videos to download | ✔ | — | Sora 20/600 (mockup 15) |
| T-126 | Picker | `<playlist> · <host> · by <uploader> · N items` | ✔ | — | Inter 12 dim |
| T-127 | Picker | This playlist is already in your queue. | ✔ | — | Inter 12/600 warn |
| T-128 | Picker | Select all · Select none · filter… | ⚠ | Placeholder is lowercase with an ellipsis (mockup "Filter"). | Inter 12/600; field Inter 12 |
| T-129 | Picker row | In queue · Already saved | ✔ | The mockup draws only the "Already saved" row badge. | mono 10/500 warn |
| T-130 | Picker footer | `M of N selected · K already in queue · ≈ H:MM:SS` · Cancel · Add M | ✔ | Matches design. | Inter 12 dim |

### Preferences

| ID | Where | Exact text | Verdict | Notes | Style |
|---|---|---|---|---|---|
| T-131 | Pane subtitles | Defaults for new downloads. Change any of these per download on the Home screen. / Pick a look. Theme sets the personality; palette sets the colours. / Applied to new downloads. / Sign in to reach private or age-restricted videos. / Check for new versions of the app and the downloader. / What the app records, and where to find it. / Reset options. These don't touch your downloaded files. / Check the app's health when something looks wrong. | ⚠ | Spelling "colours" (British) vs American spellings elsewhere ("Color"?) — no other colour word in UI; Appearance sub sets British style. | Inter 11.5 dim |
| T-132 | Rail groups | General · YouTube · System · Downloads · Appearance · Network · Sign-in & cookies · Updates · Logs & privacy · Advanced · Diagnostics | ⚠ | "Sign-in & cookies" mixes the two words used inconsistently elsewhere. | RL |
| T-133 | Downloads | Downloads folder · Simultaneous downloads · Automatic retries · Media type · Video quality · Audio language · Audio format · Filename format · Clipboard detection | ✔ | Sentence case consistent. | Inter 13/600 |
| T-134 | Downloads helper | Automatically reduced if a site rate-limits you. / Attempts before the app asks you what to do. / Highest available if the exact height isn't offered. / Used when this video has that kind of track. / Offer to grab links you copy. | ⚠ | "rate-limits" jargon; "height" and "that kind of track" are vague. | Inter 11.5 dim |
| T-135 | Downloads values | YouTube default · Original · Title · Title – channel · Date – title · Custom… · Never Gonna Give You Up.mp4 (examples) | ✔ | — | Inter 12 |
| T-136 | Concurrency note | N still running — the new limit applies as they finish. | ✔ | — | Inter 11.5 dim |
| T-137 | Appearance | Theme · Aurora is dark and luminous. Tape Deck is warm and light. · Aurora · Tape Deck · Palette · Mint & Iris · Lime & Forest · Magenta & Violet · Teal & Rust · Plum & Blush · Navy & Aqua | ✖ | The helper text promises a warm, light Tape Deck and named palettes; the app delivers neither (see palette findings). | Inter 11.5 dim / 11 |
| T-138 | Network | Proxy server · http://host:port — blank for none. · Force IPv4 · Can help when connections stall. · Speed limit · Applies to each download separately. · Off / N KB/s | ⚠ | "Proxy", "IPv4", "KB/s" are technical but standard settings vocabulary. Proxy field has no placeholder. | Inter 13/600 |
| T-139 | Sign-in | Browser · Use your browser's YouTube sign-in for age-restricted or private videos. · None · Safari · Chrome · Brave · Microsoft Edge · Firefox · Firefox profile · No Firefox profiles found. · `<Browser>` isn't installed, so there's no sign-in to use. · Cookie access for `<Browser>` · Learn more ↗ | ⚠ | "Cookie access for X" uses the technical word the rest of the copy avoids. | Inter 13/600 / 11.5 |
| T-140 | Sign-in | Test sign-in · Testing… · Checks that MediaGrabber can read your browser's sign-in. · MediaGrabber can read your `<B>` sign-in. · MediaGrabber couldn't read your `<B>` sign-in. Close `<B>` and try again. If your Mac asks for permission, choose Allow. · The test couldn't finish because there's no internet connection. · The test couldn't finish. Try again in a moment. | ✔ | Cause-specific. | Inter 11.5 |
| T-141 | Sign-in | MediaGrabber needs permission to read Safari first. Use the Full Disk Access button above. / `<B>` isn't installed on this Mac, or hasn't been opened yet. | ✖ | The second sentence is used for `.noProfiles`, `.unconfigured` and `.ready` verdicts too — not true for those causes. | Inter 11.5 |
| T-142 | Sign-in | Full Disk Access · MediaGrabber needs Full Disk Access to read Safari's sign-in. · Open System Settings · Full Disk Access granted. | ✔ | — | Inter 13/600 / 11.5 |
| T-143 | Sign-in | Pick a browser to retry "`<title>`" with your sign-in. | ✔ | — | Inter 12 text |
| T-144 | Sign-in | For the most reliable results, use a browser profile that's signed in to YouTube and keep it closed while downloading. | ✔ | — | Inter 11.5 dim |
| T-145 | Updates | Check for app updates automatically · Looks for a newer MediaGrabber release once a day. · Notify when the downloader is outdated · Warn if yt-dlp falls behind the version this app expects. | ⚠ | "yt-dlp" tool name. | Inter 13/600 / 11.5 |
| T-146 | Logs & privacy | Log files · Show in Finder · Verbose logging · More detail for troubleshooting. · Privacy details · Open | ✔ | — | Inter 13/600 |
| T-147 | Advanced | App data · Show in Finder · Reset columns · Table layout back to default. · Reset · Reset settings · All preferences back to default. Downloads are untouched. · Reset… | ✔ | Dialog says "defaults" (plural) vs helper "default". | Inter 13/600 |
| T-148 | Diagnostics | Diagnostics · Check the app's health when something looks wrong. · Run check · Last run: not yet run this session / `<relative time>` · Canary probe · not yet run this session / passed / failed · yt-dlp · `<v>` · current / update available (min `<v>`) / not found · ffmpeg · Update · Copy report · Share diagnostic bundle | ✖ | "Canary probe", "yt-dlp", "(min v)" are internal/technical on a user-facing pane (support tool). | mono 12 |

### About and Developer

| ID | Where | Exact text | Verdict | Notes | Style |
|---|---|---|---|---|---|
| T-149 | About | MediaGrabber · Version `<x>` | ✔ | — | Sora 20/800 + Inter 12 dim |
| T-150 | About | MediaGrabber — Not checked yet this session. · Check for updates · Check failed · Version `<x>` is available. · Update | ⚠ | "Check failed" gives no reason or retry. | mono 12 / Inter 10.5 faint |
| T-151 | About | Downloader (yt-dlp) — `<v>` / `<v>` · update available + Update · not found | ⚠ | Lowercase "not found" with no action. | mono 12 |
| T-152 | About | ffmpeg — `<v>` / not found | ✔ | — | mono 12 |
| T-153 | About | Diagnostics — Run a health check or copy a report for support. · Open Diagnostics | ✔ | — | mono 12 / Inter 10.5 |
| T-154 | Developer | Shardul Lingwal · Solo developer, building in the open. · Connect with me · GH · Source code · GitHub · Report an issue · GitHub Issues · License · Open | ✔ | "GH" glyph label is jargon-free; a11y "GitHub". | Sora 20/800; mono 12; Sora 12/600 |

### Menus

| ID | Where | Exact text | Verdict | Notes | Style |
|---|---|---|---|---|---|
| T-155 | Debug menu | Debug · Force Onboarding (Relaunch) · Reset State (Relaunch)… · Concurrency Cap ▸ 1…6 | ⚠ | Developer vocabulary in the shipped menu bar. | system menu |
| T-156 | Columns menu | Title … Actions (checkable) | ✔ | Actions row disabled. | system menu |

**Text audit totals:** 156 rows — ✔ 87 · ⚠ 55 · ✖ 13 · n/a 1.


---

## 9. Mockup-vs-design-system conflicts and mockup gaps

`design-system.md` states "Mockups mirror these values; if they disagree, this file wins". The task for this audit is to report conflicts and leave the decision open, so every row below is **open**. "App" shows what the app does today.

### 9.1 Conflicts between the mockup (CSS/HTML) and `design-system.md` / `job-status-and-actions.md`

| # | Topic | Mockup | Design system / status doc | App today | Note |
|---|---|---|---|---|---|
| C-01 | Resolved-link structure | Field **morphs in place**: `✓ title` + four `.pick` triggers + Grab on one row (`.field.resolved`, L563-569; home.html 1.2). The older `.runway` / `.rstep` rules (L187-197) with labels and dots are still in the CSS and are still drawn by two frames in dialog.html. | §4.2.2: runway is a **separate full-width `--panel-hi` card** below the field with labelled slots and hollow/filled dots; Type is a `SkinnedSegment`. | Morph, Type as a picker, no dots/labels, plus a ✕. | Three different structures. |
| C-02 | Status column default | Tables show a Status pill column and Remark column, captioned "(hidden by default)" on the header (L277). | §4.2.3: Status and Remark are **hidden by default**; rail is the everyday filter. | Hidden by default. | See S-043. |
| C-03 | Format / Site columns | Combined **Format** column ("Video · 1080p") and **Site** column visible. | Separate **Type** and **Quality** columns; Site hidden by default. | Type + Quality, Site hidden. | |
| C-04 | Columns button | 27×27 icon-only button hosted in the header row (`th.th-tools`). | §4.2.3 "⊞ Columns button — opens a dropdown of checkboxes". | Text + icon button in its own row. | |
| C-05 | Rail width | Home `.mg-rail` 160px; Preferences and About rails 200px. | §4.1: rail "position, width, and row styling stay identical everywhere". | 160 everywhere. | |
| C-06 | Warn colour, Plum / Navy | `--warn` #8C5A0C (Plum), #805C14 (Navy). | §5.2 says #9A6410 (Plum), #8E6318 (Navy). Teal agrees (#9C5A00). | n/a (palettes not implemented). | Contrast on `--panel-solid`: DS 4.63 / 4.90; mockup 5.44 / 5.60. |
| C-07 | Pane title weight | Aurora `h2` 700; Tape Deck 800 (L397-398). | §3.2: section heading "18 / 1.3", display face; §4.6: "Pane title 20 / heavy". §2.2 lists Sora 600/700 only. | Sora 800 (heavy) in Aurora. | |
| C-08 | Attention chip | `.chip.warn` recolours text and border (L156). | §4.1: "Green dot = ok, amber dot = attention" only. | Dot only. | |
| C-09 | Dialog icon types | `info`, `warning`, `error` inline 19×19 (L360-364). The 4.2 caption says "no glyph", but the markup of every one of the eight dialogs draws an icon (`.ctrow info/error`). | §4.9: every dialog carries one of three icon types, never omitted. | Destructive only, stacked above the title. | The mockup contradicts its own 4.2 caption; the DS agrees with the markup. |
| C-10 | Count badge colour | White on danger (2.55:1). | Not specified. | `onAccent` on danger (7.87:1). | The mockup value fails AA. |
| C-11 | Icon set | One inline Lucide-style SVG family (`.ico`, 2px stroke) in both themes; no per-theme switch in CSS. | §3.4: Phosphor Bold (Tape Deck) and Lucide (Aurora), bundled assets, ≈26 glyphs. | SF Symbols. | |
| C-12 | Tape Deck `--faint` | Equals `--dim` (#8A7A60 etc.); dim on `--panel-solid` is 3.5–3.8:1. | §5.2 omits `--faint`, `--headline`, `--panel-hi` for Tape Deck; `--brand` is used but absent from §5.1. | n/a | Token list incomplete; Tape Deck dim fails AA for 12px text. |
| C-13 | Tape Deck banner text | Surface colour on `--accent`: 3.53 (Teal), 2.27 (Plum), 2.75 (Navy). | §4.1: "`--accent` on `--ink` border". | n/a | The DS names the fill and border only; the text colour comes from the mockup CSS (L317). Fails AA in the mockup itself. |
| C-14 | Section numbering | — | Table of contents lists §4.8 Confirmation / §4.9 SkinnedSegment / §4.10 SkinnedPicker, headings use 4.9/4.10/4.11; §4.1 refers to "About (§4.8)". | — | Documentation only. |
| C-15 | Spacing token naming | `--sp-8` = 44 (no `--sp-7`). | §3.1 `--sp-1 … --sp-8`. | `Spacing.s7` = 44. | Naming nit. |
| C-16 | Stale mockup file | `docs/mockups/screens.html` + `screens.css` (older copy) still present. | — | — | Two CSS files differ. |
| C-17 | Shield step command | onboarding.html step 3 shows `pipx install bgutil-ytdlp-pot-provider` with Copy. | §4.5: the shield step is a single `Set up` button and "no command is shown". | Set up button, no command. | See D-01 for the downloader step. |
| C-18 | Speed and ETA columns | home.html headers read one combined "Speed / ETA" column. | §4.2.3: Speed and ETA are separate columns. | Separate columns. | |
| C-19 | Playlist runway label | No "Grab all N" in any frame; the playlist picker footer reads "Add 12". | §4.2.2: label is `Grab` / `Grab all N` / `Add N`. | Runway always reads `Grab`; picker footer reads `Add N`. | |
| C-20 | Shield chip name | One home.html frame reads `shield · offline`. | The DS and the other frames read `bot-check shield`. | `bot-check shield`. | |

### 9.2 Conflicts with recorded decisions (left open)

| # | Item | Source A | Source B |
|---|---|---|---|
| D-01 | Show an install command in onboarding | `design-system.md` §4.5 and mockup 2.1/2.2: show `brew install …` / the Homebrew command with Copy. | `CLAUDE.md` "User-facing copy": "no commands, tool names, or jargon in the UI". The app currently shows `brew install yt-dlp ffmpeg`. |
| D-02 | Icon library | `design-system.md` §3.4: bundled Phosphor Bold (Tape Deck) / Lucide (Aurora) assets. | App ships SF Symbols and no icon assets; no recorded decision found in `CLAUDE.md` or the docs read. |
| D-03 | Connect-with-me icons | Mockup shows GH, in, globe, X. | `design-system.md` §4.8: GitHub only shipped, others commented out until real URLs exist. |
| D-04 | Palette fallback | `Palette.swift` comment: only Mint & Iris ships; other kinds fall back until a later phase. | `design-system.md` §1-2: user picks a theme then palette; Appearance pane exposes six. The pane shows six swatches that all fall back. |
| D-05 | Row verb names | `job-status-and-actions.md` §4 "UI strings: Force start; Restart; Restart with sign-in"; group action "Restart failed". | App labels: Retry, Retry with cookies, Retry failed. |
| D-06 | Sort overwrite copy | Dialog says sorting turns off "for this session". | `design-system.md` §4.2.3: sort persists in `columns.json`. |

### 9.3 Mockup gaps (app components with no mockup; audited against the design language)

| Component | Where | Audit approach / outcome |
|---|---|---|
| Share-extension tip strip | Home after first Grab | See S-059. |
| Set-up-the-shield sheet | Chip "set up", probe prompt | See S-075. |
| Host-rate popover | Health strip popover chips | See S-071. |
| Probing spinner | Paste field | See S-055. |
| Resolved-field clear (✕) | Runway | Mentioned in S-056. |
| Onboarding running/failed states for downloader and shield | Onboarding | See S-049; mockup only draws Homebrew failed. |
| Playlist picker row badge "In queue" | Playlist picker | The mockup draws the "Already saved" row badge and the footer count "already in queue", not a row badge "In queue"; audited against the "Already saved" badge style (S-076). |
| Row tooltips, drag-reorder | Table | Code only; native feedback. |
| Toast failure variant (no action) | Toast | Same box style; no mockup. |
| Diagnostics "Update" pill + Copy/Share | Diagnostics | Mockup 6.3 draws the pill. |
| Drop-target overlay | Window | None drawn in mockup or app (S-087). |
| Context menu | Table | home.html draws a `.ctxmenu` (Pause, Resume, Cancel, Remove) over a multi-selection; the app has none (S-089). |
| Hover / pressed / disabled / focus states | Everywhere | Mockup hover rules exist (listed in S-033); no pressed or focus-visible states except the dialog ring. |
| Debug menu and NSAlert | Menu bar | See S-039. |
| Header filter popover content ("Clear/Apply") | Header | Mockup 1.3 draws it; app has a plain menu (S-035). |
| Diagnostics report rows (shield, cookies, client, cooldown, network) | Diagnostics | Content gap: the app shows three of eight rows. |

---

## 10. Appendix

### Appendix A — Fonts, sizes and tokens actually used by the app

**Font resolution (measured in-process):** Sora → `Sora-Regular` (variable; weights resolve to `Sora-Regular_SemiBold`, `_Bold`, `_ExtraBold` named instances); Inter → `Inter-Regular`; JetBrains Mono → `JetBrainsMono-Regular`; Bricolage Grotesque, DM Sans, DM Mono → **not resolved**. The theme exposes `displayFont` = Sora, `bodyFont` = Inter, `monoFont` = JetBrains Mono for both themes.

**Palette actually applied (all palettes): Aurora Mint & Iris** — ground #0C1013, panel-solid #0E1117, panel white 5%, panel-hi white 8%, stroke white 12%, hair white 6%, text #EDF0F5, dim #9AA3B2, faint #6B7480, headline #F4F6FA, on-accent #07080B, accent #5EF2C8, accent-2 #8B7BFF, warn #FFC24B, danger #FF7A6B; go gradient #5EF2C8→#8B7BFF (horizontal); bar fill #5EF2C8 (solid in the grid); banner #FF7A6B→#FFC24B (horizontal); glow .14 mint / .16 iris (used only by the picker popover shadow).

**Radii (pt):** Aurora window 18, card 14, control 9, pill 20, chip 7; Tape Deck 10, 8, 6, 14, 5; grid-specific: status pill 10 (22pt capsule), action buttons 7, progress/mini-bar 2, readout 4.

**Spacing (pt):** s1 4, s2 8, s3 12, s4 16, s5 22, s6 30, s7 44. Hairline 1.

**Type sizes in use (family / size / weight):**

| Role | App | Mockup |
|---|---|---|
| Wordmark | Sora 17 / 600 | Sora 18 / 700, −.02em |
| Nav | Inter 12 / 500 | Sora 12 |
| Chips | JetBrains Mono 11 / 400 | mono 10 |
| Rail (Home) | Inter 12 (600 active) | Sora 13 |
| Rail (Prefs/About) | Inter 13 (600 active) | Sora 13 |
| Rail captions | mono 11 / 500 UPPER | mono 10 UPPER .1em |
| Kicker | mono 11 / 500 | mono 11 .16em |
| Hero | Sora 32 / 600 | Sora 32 / 700 −.03em |
| Paste field | mono 13 | mono 13 |
| Probe error | Inter 12 danger | mono 11 danger |
| Step card number / title / text | mono 12 faint / Inter 13/600 / Inter 12 dim | mono 11 accent / Sora 13 / 12 |
| Picker/segment text | Inter 12 / 500 | Sora 12 |
| Grab | Inter 13 / 600 | Sora 14 / 700 |
| Table header | mono 10 / 500 + 0.8 kern | mono 10 .08em |
| Table cell | Inter 13 dim | Inter 13 text |
| Status pill | mono 10 | mono 10 |
| Group title / rollup / actions | Inter 13/600 · mono 11 · Inter 12/500 | Sora 13/600 · mono 11 · Sora 10 |
| Selection bar | Inter 12 / 500 | Inter 12 / 500 |
| Banner | Inter 13 / button Inter 12/600 | Inter 13 / button 12/600 |
| Toast | Inter 13 / action Inter 13/600 | Inter 12 / link 11 |
| Dialog title / message | Sora 15/600 · Inter 13 dim | same |
| Dialog buttons | SF Pro 13 (no font set) | Sora 12 |
| Onboarding h1 / lead / step title / step text | Sora 30/600 · Inter 14 · Inter 15/600 · Inter 13 | Sora 26/700 · 13 · Sora 14 · 12 |
| Pane title / sub | Sora 20/800 · Inter 11.5 | Sora 20/700 (Aurora) · Inter 12 |
| Row label / helper | Inter 13/600 · Inter 11.5 | 13/600 · 11.5 |
| About rows | mono 12 dim · Inter 10.5 faint | 13/600 · 11.5 |
| Picker modal title / meta | Sora 20/600 · Inter 12 | Sora 15/600 · mono 11 |
| Shield sheet title / body | Sora 20/600 · Inter 13 | n/a |

**Component dimensions (pt):** brand row ≈46 (mockup ≈60); health strip ≈41; rail 160; picker trigger 28 (34); segment ≈28 (34); Grab ≈32 (44); table header 30; row 41; group header 48; action button 27; progress bar 4 (6); status pill 22; checkbox 16; toast max 320; banner side/bottom inset 16; dialog max 420, padding 22; sheet widths 460 / 620-820.

**Motion in use:** orb rotation 6s linear (only when a job runs); chip ↻ rotation 0.9s linear; busy dot opacity .4↔1.0 over 1.2s; dialog scale .96→1 + fade `easeOut` 0.16s; toast slide+fade (declared, likely not animated); toast auto-dismiss 4s.

**Icon sizes in use (pt):** row actions 11; header sort/filter 11 in 12; picker chevron 9; picker check 10; resolved check 12; clear/dismiss × 10–11; tip icon 12; dialog warning 20; concurrency/cookie warnings 12; Columns 14.

### Appendix B — Contrast measurements (WCAG 2.x)

Computed from token values; alpha surfaces composited over the stated base.

**Aurora Mint (applied to every palette today)**

| Pair | Ratio | Use |
|---|---|---|
| text on panel-solid | 16.54 | body |
| dim on panel-solid | 7.43 | helper, table cells |
| dim on panel (5% white) | 6.64 | |
| faint on ground | 4.03 | placeholders, captions, empty message |
| faint on panel-solid | 3.99 | |
| faint on panel | 3.57 | |
| accent on panel-solid | 13.51 | links, kicker |
| accent-2 on panel-solid | 5.74 | queued dot/text |
| warn on panel-solid | 11.76 | |
| danger on panel-solid | 7.42 | errors |
| on-accent on accent | 14.32 | Grab, confirm |
| on-accent on accent-2 | 6.08 | |
| on-accent on danger | 7.87 | badge, destructive confirm |
| banner text #07080B on #FF7A6B / #FFC24B | 7.87 / 12.46 | banner ends |
| disabled Grab label (0.3 opacity, grayscale) | 1.59–2.00 | onboarding disabled buttons |
| selected row text / dim on accent 18% wash | 10.93 / 4.91 | |

**Aurora Lime / Magenta (mockup values, not applied by the app):** faint on panel-solid 3.69 / 3.88; dim 7.57 / 7.01; accent on panel-solid 14.02 / 6.18; on-accent on accent 14.83 / 6.48 (Magenta pink fill at 6.48 is the weakest primary).

**Tape Deck mockup palettes:** text on surface 14.4–14.9; dim on surface 3.81 (Teal) / 3.52 (Plum) / 3.54 (Navy), on ground 3.47 / 3.16 / 3.15 (fails AA for ≤13px text); accent on surface 3.53 / 2.27 / 2.75 (fails for text/links); warn on surface 4.95 / 5.44 / 5.60; danger on surface 4.95 / 3.95 / 3.19; on-accent on go 7.06 / 8.36 / 8.48; surface on brand header 7.14 / 10.0 / 11.75.

### Appendix C — Items not visually verified

1. Native menus: Columns (SwiftUI `Menu`), column filter (`NSMenu`), Debug menu, context menus (none), menu-bar appearance.
2. `NSAlert` for Debug → Reset State.
3. System sheet chrome (shield setup, playlist picker), window title bar, traffic lights, window shadow/radius.
4. Tooltips (row actions, title, status/remark, Developer link).
5. Live motion: orb spin, chip ↻ spin and dot pulse, dialog scale/fade, toast slide/fade and 4s dismiss, picker popover open/close, probe and onboarding spinners (system spinners did not draw offscreen).
6. Hover, pressed, keyboard-focus rings, drag-over drop target, column drag ghost/drop line, resize cursor and width readout, row drag-reorder gap.
7. Scrollbars (overlay behaviour).
8. Host-rate popover (capture hit another control); picker popover frame (halo artefact).
9. Stray vertical ticks at the ends of every health chip in the captures (likely a stroked-capsule snapshot artefact).
10. Preferences → Sign-in & cookies states other than "None" (Firefox, Safari FDA denied/granted, pending retry, no profiles, test results) and the concurrency note (need runtime state); styling taken from code.
11. The real "Quit MediaGrabber?" dialog text (render used placeholder wording); About/Diagnostics "found" tool states (fixture had no probe).
12. Tape Deck rendering was approximated by forcing the light window appearance in the harness; the real app's native-control appearance under `preferredColorScheme(.light)` matches that approximation but was not seen live.



### Appendix D — Findings index

| ID | Title | Severity | Verified |
|---|---|---|---|
| S-001 | All six palettes resolve to Aurora Mint & Iris | Broken | rendered |
| S-002 | Tape Deck theme has no Tape Deck identity | Broken | rendered |
| S-003 | Tape Deck typefaces are not bundled; both themes use Sora/Inter/JetBrains Mono | Broken | rendered |
| S-004 | Tape Deck forces the light colour scheme under a dark palette | Broken | rendered |
| S-005 | Palette swatches all show the same colours | Broken | rendered |
| S-006 | Dark appearance of system chrome | Nit | code+CSS only |
| S-007 | Letter-spacing is absent everywhere except table headers | Inconsistent | rendered |
| S-008 | Heading weights differ from the mockup | Inconsistent | rendered |
| S-009 | Type sizes drift from the scale | Inconsistent | code+CSS only |
| S-010 | Display vs body family swapped on many controls | Inconsistent | rendered |
| S-011 | Buttons without a font fall back to the system font (SF Pro) | Inconsistent | rendered |
| S-012 | Table title and data cells are all dim | Inconsistent | rendered |
| S-013 | Version/status values set in mono instead of the plain face | Inconsistent | rendered |
| S-014 | Top navigation typography and spacing | Nit | rendered |
| S-015 | `--faint` text is below AA for small text | Nit | code+CSS only |
| S-016 | Disabled gradient buttons are illegible | Ugly | rendered |
| S-017 | Selected-row tint is mint 18% instead of iris 10% | Inconsistent | rendered |
| S-018 | Attention chips differ only by a 7px dot | Inconsistent | rendered |
| S-019 | Count badge text colour | Nit | code+CSS only |
| S-020 | Control heights are smaller than designed | Inconsistent | rendered |
| S-021 | Vertical rhythm of chrome is compressed | Inconsistent | rendered |
| S-022 | Paste field and table do not share a left edge | Inconsistent | rendered |
| S-023 | Rail width and structure | Nit | rendered |
| S-024 | Border widths: no 2px / 1.5px structural borders | Inconsistent | code+CSS only |
| S-025 | Radii differ by theme and from tokens | Inconsistent | code+CSS only |
| S-026 | Elevation values differ from the tokens | Inconsistent | code+CSS only |
| S-027 | SF Symbols replace the bundled Phosphor/Lucide icon sets | Inconsistent | rendered |
| S-028 | Icon sizes and weights vary | Inconsistent | rendered |
| S-029 | Glyph characters mixed with symbols | Nit | rendered |
| S-030 | Brand orb spins only while something downloads; no row motif | Inconsistent | code+CSS only |
| S-031 | Reduced-motion handling | Nit | code+CSS only |
| S-032 | Easing/duration tokens not used | Nit | code+CSS only |
| S-033 | No hover or pressed states | Inconsistent | code+CSS only |
| S-034 | Brand row logo placement | Nit | rendered |
| S-035 | Columns menu and column-filter menu are system menus | Ugly | code+CSS only |
| S-036 | Toggle, Stepper and Button use system styling | Ugly | rendered |
| S-037 | Sheets use system sheet chrome | Inconsistent | code+CSS only |
| S-038 | Window chrome and title bar | Nit | code+CSS only |
| S-039 | Debug menu and native alert in the menu bar | Inconsistent | code+CSS only |
| S-040 | Focus rings are system defaults except grid rows | Nit | code+CSS only |
| S-041 | Scrollbars and tooltips are system-drawn | Nit | code+CSS only |
| S-042 | Row actions are off-screen at the default window size | Broken | rendered |
| S-043 | Default columns show no status; failed rows look like saved rows | Inconsistent | rendered |
| S-044 | Dead space and centring at large sizes | Nit | rendered |
| S-045 | Preferences panes scroll as one block | Inconsistent | code+CSS only |
| S-046 | Preference rows stretch across wide windows | Nit | rendered |
| S-047 | Minimum window (820×560) | Nit | rendered |
| S-048 | Homebrew-missing step: no command box, system buttons, different labels | Ugly | rendered |
| S-049 | Running step uses a tiny system spinner and no progress | Ugly | rendered |
| S-050 | Onboarding column and text are larger than the mockup | Nit | rendered |
| S-051 | Install command box styling | Nit | rendered |
| S-052 | First-run step cards and hero layout | Inconsistent | rendered |
| S-053 | Paste field is taller and uses different type | Inconsistent | rendered |
| S-054 | Probe error sits under the URL instead of inline | Inconsistent | rendered |
| S-055 | Probing indicator | Nit | code+CSS only |
| S-056 | Inline runway: control sizes, fonts and Grab | Inconsistent | rendered |
| S-057 | Picker popover is skinned inside a system popover frame | Inconsistent | rendered |
| S-058 | Segmented control proportions | Nit | rendered |
| S-059 | Share-extension tip strip | Nit | rendered |
| S-060 | Table header lacks grip, bordered icon buttons and resize dividers | Ugly | rendered |
| S-061 | Columns button location and form | Inconsistent | rendered |
| S-062 | Status pills: no border, wrong text colours | Inconsistent | rendered |
| S-063 | Remark column can show raw tool output | Ugly | rendered |
| S-064 | Progress bar proportions and fill | Inconsistent | rendered |
| S-065 | Playlist group header and children | Ugly | rendered |
| S-066 | Empty and filtered-empty table body | Ugly | rendered |
| S-067 | Batch (selection) bar | Nit | rendered |
| S-068 | Home rail items | Nit | rendered |
| S-069 | Dividers use `hair` where the mockup uses `stroke` | Nit | rendered |
| S-070 | Health chips typography and states | Inconsistent | rendered |
| S-071 | Host cooldown popover is unskinned | Ugly | code+CSS only |
| S-072 | Warning banner | Nit | rendered |
| S-073 | Toasts are translucent, collide with the banner and have no shadow | Broken | rendered |
| S-074 | Confirmation dialog anatomy | Ugly | rendered |
| S-075 | Shield setup sheet | Ugly | rendered |
| S-076 | Playlist picker modal | Inconsistent | rendered |
| S-077 | Preferences rail captions and rows | Nit | rendered |
| S-078 | Preferences pane header order and spacing | Inconsistent | rendered |
| S-079 | Preferences rows and helper text | Nit | rendered |
| S-080 | Downloads pane controls | Inconsistent | rendered |
| S-081 | Network pane field and stepper | Nit | rendered |
| S-082 | Sign-in & cookies pane rows and notes | Nit | rendered |
| S-083 | Diagnostics pane | Inconsistent | rendered |
| S-084 | Concurrency note | Nit | code+CSS only |
| S-085 | About / Developer identity block and rows | Inconsistent | rendered |
| S-086 | About / yt-dlp update pill | Nit | code+CSS only |
| S-087 | No drag-and-drop target styling | Inconsistent | code+CSS only |
| S-088 | Column resize/reorder visuals | Inconsistent | code+CSS only |
| S-089 | No context menu | Nit | code+CSS only |
| S-090 | Picker row hover wash stays after the pointer leaves | Nit | code+CSS only |
| S-091 | First-run Home keeps an empty rail slot | Nit | code+CSS only |
| S-092 | A busy health chip takes the system disabled fade | Nit | code+CSS only |
| S-093 | Resolved link title typography | Nit | code+CSS only |
| S-094 | Double-click autofit measures the wrong font | Nit | code+CSS only |
| S-095 | Empty-state header cells are wider than the live columns | Nit | code+CSS only |
| S-096 | Group action labels do not fit the Actions column | Inconsistent | code+CSS only |
| S-097 | A failed Homebrew step still offers "Install now" | Ugly | code+CSS only |
| S-098 | Other failed onboarding steps use a text link to retry | Nit | code+CSS only |
| S-099 | The download-folder path does not truncate | Nit | code+CSS only |
| S-100 | Diagnostics shows "not found" before any check has run | Broken | code+CSS only |
| S-101 | Copy and Share are offered before a report exists | Nit | code+CSS only |
