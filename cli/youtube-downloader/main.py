# main.py

import logging
import time

from .core.config import DownloadConfig
from .core.downloader import YoutubeDownloader
from .utils.logger import setup_logging


def main():
    """Main function to run the downloader application."""
    setup_logging(logging.INFO)

    downloader = YoutubeDownloader()

    # Example: Create a configuration for a specific download.
    # In a real app, this would come from a GUI or command-line arguments.
    video_url = "https://www.youtube.com/playlist?list=PLVD3APpfd1ts0x9qpHagm5Nyd2GKxwrly"
    download_id = "abc"

    config = DownloadConfig(
        url=video_url,
        dest_folder=downloader.config_defaults.get("download_directory", "downloads"),
        resolution=downloader.config_defaults.get("default_resolution", "720p"),
        enable_subtitles=True,
    )

    logging.info(f"Starting download for: {config.url}")
    downloader.start_download_task(download_id, config)

    # Monitor progress from the main thread
    while True:
        progress = downloader.get_download_progress(download_id)
        status = progress.get("status", "pending")

        if status in ["completed", "failed", "cancelled", "paused"]:
            logging.info(f"Task '{download_id}' finished with status: {status.upper()}")
            if progress.get("error"):
                logging.error(f"Details: {progress.get('error')}")
            break

        elif status == "downloading":
            total_bytes = progress.get("total_bytes", 0)
            downloaded_bytes = progress.get("downloaded_bytes", 0)

            # Format the output string based on whether it's a playlist or single video
            prefix = ""
            if "playlist_info" in progress:
                pl_info = progress["playlist_info"]
                prefix = (
                    f"Playlist - [{pl_info.get('current_index')}/{pl_info.get('total_files')}] "
                    f"'{pl_info.get('current_title')}': "
                )
            else:
                prefix = "Downloading: "

            if total_bytes > 0:
                percent = (downloaded_bytes / total_bytes) * 100
                speed = progress.get("speed") or 0
                eta = progress.get("eta") or 0
                logging.info(
                    f"{prefix}{percent:.1f}% | "
                    f"Speed: {speed / 1024 / 1024:.2f} MB/s | "
                    f"ETA: {eta:.0f}s"
                )
            else:
                # For streams of unknown size, just show downloaded amount
                logging.info(f"{prefix}{downloaded_bytes / 1024 / 1024:.2f} MB downloaded")
        else:
            # For other statuses like 'pending', 'merging', etc.
            logging.info(f"Status: {status.upper()}...")

        time.sleep(5)  # Update every 5 seconds as requested


if __name__ == "__main__":
    main()
