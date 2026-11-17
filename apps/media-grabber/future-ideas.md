# Future ideas

Features and ideas for the distant future. None of these is scheduled, none has a phase, and each has only a limited view of what it would be. They are written down so they are not lost. Each one gets discussed, scoped and given a phase when planning reaches it.

An entry here is not a commitment. Work that already has an owner lives in `roadmap.md` or `tickets.md`.

## v2

### Failure-code explainer page

A page that explains every failure reason the app can show (the codes behind a failed row), and where a fix exists, offers plain "how to" steps for it.

Today a failed row shows its reason in plain words and offers Restart, so the user can act and try again. The page would go further: what the reason means, why it happens, and the steps to fix it.

Related today: the reason on the row (mg-018) and Restart on every failed row (mg-067).

## Declined for Phase 17

Subtitles and embed, a menu-bar extra, schedules, stats, bandwidth graphs, a light and dark variant of each skin, and a compact breakpoint. Looked at while scoping site and identity work, and left unscheduled.

### A permissively licensed replacement for the sign-in helper

The bundled YouTube sign-in helper (bgutil-ytdlp-pot-provider) is GPL-3.0, so the app ships it as a separate program with its licence text and source, and that is the only copyleft piece in the app. Its token generation is the MIT library `bgutils-js` (https://github.com/LuanRT/BgUtils) plus `youtubei.js` (MIT). A small server and a yt-dlp plugin written on those two would be MIT and keep the app free of copyleft, at the cost of owning the upkeep when YouTube changes its checks. `yt-dlp-getpot-wpc` (MIT) is not a fit because it needs a visible browser. Decide when the app is sold or distributed more widely.
