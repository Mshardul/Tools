# MediaGrabber

MediaGrabber downloads a video from a link you paste. It shows the title, a progress bar, and **Saved** when the file is ready, with a button to reveal it in Finder.

You can keep several downloads going, pause or cancel one, and paste a playlist and pick which items to keep. Sign-in is only suggested when a site needs it.

## Download

[Download MediaGrabber](https://github.com/Mshardul/Tools/releases?q=media-grabber-v)

Take the latest `MediaGrabber-N.N.N.dmg` from that list. Do not use the repository’s overall “latest” release; other tools in this repo publish releases too.

Apple Silicon Mac, macOS 14 or later.

## Install

1. Open the disk image.
2. Drag **MediaGrabber** onto the **Applications** folder.
3. Eject the disk image and open MediaGrabber from Applications.

The first time you open a downloaded copy, macOS blocks it. Go to **System Settings → Privacy & Security**, choose **Open Anyway** next to the MediaGrabber notice, then open the app again and confirm.

If you opened it from the disk image or from Downloads, the app offers to move itself into Applications. Updates stay off until it lives there.

## Updating

With the app in Applications, it can look for a newer version about once a day. Nothing is installed until you accept it.

- **MediaGrabber → Check for Updates…**
- **About → Check for updates**
- **Preferences → Updates** turns the automatic check on or off.

## Uninstall

**Preferences → Advanced → Uninstall…**

Confirm with **Remove MediaGrabber?**. The app and the files it saved are removed. Videos you already downloaded stay where they are.

If you would rather delete those files yourself, they are:

- `~/Library/Application Support/MediaGrabber/`
- `~/Library/Logs/MediaGrabber/`
- `~/Library/Caches/app.mediagrabber.mac/`
- `~/Library/Saved Application State/app.mediagrabber.mac.savedState/`
- `~/Library/Preferences/app.mediagrabber.mac.plist`

Then drag MediaGrabber from Applications to the Trash.

## Getting help

**Preferences → Diagnostics → Share diagnostic bundle** sends a report through the Mac share sheet. Logs stay on your Mac unless you share them. [PRIVACY.md](PRIVACY.md) says what they contain.

## License

MIT.
