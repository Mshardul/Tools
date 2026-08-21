"""
Download Youtube Playlist locally.
"""
from datetime import datetime
import os
import pprint

import yt_dlp
from youtube_video_downloader import download_youtube_video


# CONSTANTS
NOW: datetime = datetime.now()
DOWNLOAD_DIR = f"data/youtube-playlist-downloader/{NOW.strftime('%Y_%m_%d__%H_%M')}"

def extract_video_urls_from_playlist(youtube_playlist_url) -> list[str]:
    ydl_opts: dict[str, bool] = {
        'quiet': True,
        'extract_flat': True,
        'force_generic_extractor': False,
        'skip_download': True
    }

    with yt_dlp.YoutubeDL(ydl_opts) as ydl:
        info = ydl.extract_info(youtube_playlist_url, download=False)
        if not info:
            return []
        urls: list[str] = [entry['url'] for entry in info['entries'] if entry and 'url' in entry]
        return urls

def get_playlist_video_count(youtube_playlist_url: str = "") -> int:
    with yt_dlp.YoutubeDL({"quiet": True, "extract_flat": True}) as ydl:
        info = ydl.extract_info(youtube_playlist_url, download=False)
        if not info:
            return 0
        total_videos: int = len(info.get("entries", []))
        return total_videos

def download_playlist_videos_using_yt_dlp(youtube_playlist_url: str = ""):
    # Set expected total number of videos to decide padding
    pad_length: int = min(get_playlist_video_count(youtube_playlist_url), 3)

    # Set `yt_dlp` options
    ydl_opts = {
        "format": "bestvideo[height<=720]+bestaudio/best[height<=720]",
        "outtmpl": f"{DOWNLOAD_DIR}/%(playlist_index)0{pad_length}d. %(title)s.%(ext)s",
        "quiet": False,
        "extract_flat": False,
        "noplaylist": False,  # Allow full playlist
        "dump_single_json": True,
        "ignoreerrors": True,  # Skip failed videos
        "postprocessors": [{
            'key': 'FFmpegVideoConvertor',
            'preferedformat': 'mp4'
        }]
    }

    # Download playlist
    with yt_dlp.YoutubeDL(ydl_opts) as ydl:
        ydl.download([youtube_playlist_url])

def __get_pad_length(n: int) -> int:
    if n>999:
        return 4
    elif n>99:
        return 3
    elif n>9:
        return 2
    return 1

def download_playlist_videos_individually_using_yt_dl(video_urls: list[str] = None):
    if not video_urls:
        return

    successful_downloads: list[str] = []
    unsuccessful_downloads: list[str] = []

    os.makedirs(DOWNLOAD_DIR, exist_ok=True)

    n: int = len(video_urls)
    pad_length: int = __get_pad_length(n)
    for index, video_url in enumerate(video_urls, start=1):
        print(f"Downloading video {index} / {n}: ", end='')
        filename: str = f"{DOWNLOAD_DIR}/{index}0{pad_length}d. %(title)s.%(ext)s"
        is_downloaded: bool = download_youtube_video(video_url, filename)
        if is_downloaded:
            print("✅")
            successful_downloads.append(video_url)
        else:
            print("❌")
            unsuccessful_downloads.append(video_url)

    print(f"✅ {len(successful_downloads)} ❌ {len(unsuccessful_downloads)}")
    pprint.pprint(unsuccessful_downloads)


if __name__ == "__main__":
    playlist_url: str = "https://www.youtube.com/playlist?list=PLQpVsaqBj4RLwXMZ9LaAFf4rVowiC3ZcG"

    # Option1: Download playlist videos using `yt_dlp`
    # download_playlist_videos_using_yt_dlp(playlist_url)

    # Option2: Download playlist videos individually using `yt_dl`
    video_urls: list[str] = extract_video_urls_from_playlist(playlist_url)
    download_playlist_videos_individually_using_yt_dl(video_urls)
