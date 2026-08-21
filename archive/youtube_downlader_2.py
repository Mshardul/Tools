### working
# source: https://tabcode.net/threads/download-youtube-playlists-easily-with-yt-dlp.920/

import yt_dlp
import os

# playlist details
playlist_url = input("Enter Playlist URL: ")
playlist_title = input("Enter Playlist Title: ")

# output directory
output_dir = "~/Downloads/%{playlist_title}"
if not os.path.exists(output_dir):
    print(f"[downloader] Directory doesn't exist. Creating...")
    os.makedirs(output_dir)
print(f"[downloader] Downloading playlist \"{playlist_title}\" to directory: {output_dir}")

# yt_dlp options
ydl_opts = {
    'format': 'best[ext=mp4]/best',
    'outtmpl': f'{output_dir}/%(playlist_index)02d_%(title)s.%(ext)s',
    'merge_output_format': 'mp4',
    'quiet': False,
    'no_warnings': False,
}

# download playlist
try:
    with yt_dlp.YoutubeDL(ydl_opts) as ydl:
        ydl.download([playlist_url])
    print("[downloader] Playlist downloaded successfully!")
except Exception as e:
    print(f"[downloader] Error occurred: {str(e)}")