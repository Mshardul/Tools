# Copy audit

Sentences changed for plain language, plus the sign-in and probe sentences that stayed.

| Surface | Trigger | String | True | Plain | Says what is wrong | Later action |
| --- | --- | --- | --- | --- | --- | --- |
| Row / probe | YouTube bot-check, helper down | YouTube didn't accept this request because the YouTube check stopped working. | yes | yes | yes | Restart on the health chip |
| Row / probe | YouTube bot-check, helper missing | YouTube didn't accept this request. The YouTube check isn't set up on this Mac. | yes | yes | yes | Set up on the health chip |
| Probe | Downloader missing | The downloader isn't installed. Open setup. | yes | yes | yes | Open setup |
| Toast | Downloader update failed | Couldn't update the downloader. | yes | yes | yes | Update on About |
| Toast | YouTube check restart failed | Couldn't restart the YouTube check. | yes | yes | yes | The health chip stays |
| Health chip | Helper running | YouTube check · on | yes | yes | yes | none |
| Health chip | Helper down | YouTube check · offline | yes | yes | yes | Restart |
| Health chip | Helper missing | YouTube check · not set up | yes | yes | yes | Set up |
| Banner | Helper down | The YouTube check stopped working. Some YouTube downloads may fail or be lower quality. | yes | yes | yes | Restart |
| Onboarding | Helper step | YouTube check | yes | yes | yes | Set up |
| About | Downloader row | Downloader | yes | yes | yes | Update |
| About | Media tools row | Media tools | yes | yes | yes | none |
| Sheet | Idle | Set up the YouTube check | yes | yes | yes | The sheet's setup button |
| Prompt | Missing | Set up the YouTube check | yes | yes | yes | Opens the sheet |
| Prompt | Down | Restart the YouTube check | yes | yes | yes | Restarts the check |
| Sign-in | Age-restricted, no browser | This video is age-restricted. Signing in with your browser may let you download it. | kept | yes | yes | Restart with sign-in |
| Sign-in | Age-restricted, browser chosen | This video is age-restricted. Make sure your browser is signed in to an account that can watch it. | kept | yes | yes | Preferences |
| Sign-in | Private, no browser | This video is private. If you have access, signing in with your browser may let you download it. | kept | yes | yes | Restart with sign-in |
| Sign-in | Private, browser chosen | This video is private. Make sure your browser is signed in to an account that has access. | kept | yes | yes | Preferences |
| Probe | Bad link | That doesn't look like a valid link. | kept | yes | yes | none |
| Probe | Unsupported | That site isn't supported. | kept | yes | yes | none |
| Probe | Unavailable | This video isn't available. | kept | yes | yes | none |
| Probe | Network | No internet connection. | kept | yes | yes | none |
| Probe | Sign-in unreadable | Couldn't read your browser's sign-in. Close the browser and try again. | kept | yes | yes | Close the browser |
| Probe | Cooling | This site is cooling down. Try again in m:ss. | kept | yes | yes | Wait |
| Probe | Paused | This site is paused. Choose Retry now to continue. | kept | yes | yes | Retry now |
| Health chip | Downloader current | Downloader · current | yes | yes | yes | none |
| Health chip | Downloader behind | Downloader · update available | yes | yes | yes | Update |
| Home | Setup skipped and the check is missing | YouTube downloads work better with the YouTube check set up. | yes | yes | yes | Set it up |
| Preferences | Only these sites, empty list | Cookies go nowhere until you add a site. | yes | yes | yes | A later failure can add the site |
| Dialog | Add a site | Use your signed-in browser for YouTube? | yes | yes | yes | Use sign-in |
| Row | YouTube check offline | The YouTube check is offline. | yes | yes | yes | none |
| Quit | Downloader missing | Downloads are paused — the downloader needs reinstalling. Quit anyway? | yes | yes | yes | Quit |

Row remarks for a failed download use `FailurePresentation`: the site is limiting speed; not available in your region; private; no longer available; age-restricted and needs a sign-in; no internet; couldn't read the browser's sign-in; disk full; folder isn't writable; kept ending early; downloader needs reinstalling; couldn't verify this request; YouTube isn't offering a downloadable video; picked quality isn't available; YouTube check is offline; recording needs a passcode; passcode didn't work. An unknown failure shows the tool's own sentence, which can still name the downloader. Dialogs cover download again, already queued, file moved, log unavailable, grab this link, couldn't open that link, start this now, remove, cancel playlist, clear sorting, an update is available, and cancel selected. Onboarding steps are Paste a link, Pick a format, and Press Grab, plus Install now. About titles are MediaGrabber, Downloader, and Media tools. Diagnostics says Not checked yet and Run a health check or copy a report for support.
