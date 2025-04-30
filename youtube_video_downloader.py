"""
Download Youtube Video locally.
"""
import yt_dlp

# CONSTANTS
DOWNLOAD_DIR: str = "data/youtube_video_downloader"
MAX_RESOLUTION: int = 720  # [720, 1080]

def download_youtube_video(video_url, filename=f"{DOWNLOAD_DIR}/%(title)s.%(ext)s") -> bool:
    """ Download YouTube Video using yt_dl """
    # yt_dlp options
    ytdl_options: dict[str, str] = {
        "format": f"bestvideo[height<={MAX_RESOLUTION}]+bestaudio/best[height<={MAX_RESOLUTION}]",
        "outtmpl": filename
    }

    # Download YouTube video using `yt_dl`
    with yt_dlp.YoutubeDL(ytdl_options) as ydl:
        try:
            ydl.download([video_url])
            return True
        except Exception as e:
            print(f"Failed to download {video_url}: {e}")
            return False
