# Included tools

MediaGrabber includes these tools inside the app. Nothing is installed from Homebrew.

- **yt-dlp**, the Unlicense. https://github.com/yt-dlp/yt-dlp
- **FFmpeg 7.1.1**, LGPL 2.1 or later. Built from the unmodified source https://ffmpeg.org/releases/ffmpeg-7.1.1.tar.xz with `./configure --disable-gpl --disable-nonfree --disable-shared --enable-static --enable-libmp3lame`. The build script is `apps/media-grabber/scripts/fetch-tools.sh` in https://github.com/Mshardul/Tools. License text: https://www.gnu.org/licenses/old-licenses/lgpl-2.1.html
- **LAME 3.100**, LGPL 2.1 or later, built into FFmpeg for mp3 files. https://lame.sourceforge.io
- **Node.js 22**, the MIT license. Only the `node` program is included. https://nodejs.org
- **The YouTube check helper (bgutil-ytdlp-pot-provider 2.0.2)**, GPL 3.0 only. It runs as a separate program that yt-dlp talks to. The source for the exact version included is https://github.com/Brainicism/bgutil-ytdlp-pot-provider/archive/refs/tags/2.0.2.tar.gz and the license text is https://www.gnu.org/licenses/gpl-3.0.html. The packages it depends on come with their own licenses, in each package's folder inside the app.
- **Sparkle**, the MIT license, checks for and installs app updates. https://github.com/sparkle-project/Sparkle
