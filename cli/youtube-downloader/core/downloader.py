import configparser
import copy
import logging
import os
import threading
from dataclasses import asdict
from datetime import datetime, timedelta
from typing import Dict, Optional

import yt_dlp
from yt_dlp.utils import DownloadError

from ..utils import utils
from ..utils.logger import YtdlLogger, setup_logging
from .config import DEFAULT_RESOLUTION_NUM, DownloadConfig


class YoutubeDownloader:
    """
    A comprehensive class to manage YouTube downloads, configuration, and state.

    This class handles everything from extracting video metadata to running downloads
    in separate threads, managing progress, and applying user configurations.
    """

    def __init__(self, config_path: str = "config.ini", max_concurrent_downloads: int = 3):
        """
        Initializes the YoutubeDownloader instance.

        Args:
            config_path (str): The path to the configuration .ini file.
            max_concurrent_downloads (int): The maximum number of downloads to run at once.

        """
        # Ensure logging is configured once before getting the logger
        setup_logging()
        self.logger = logging.getLogger("yt_downloader")
        self.progress_store: Dict[str, Dict] = {}
        self.progress_lock = threading.Lock()
        self.info_cache: Dict[str, Dict] = {}
        self.cancellation_events: Dict[str, threading.Event] = {}
        self.download_semaphore = threading.Semaphore(max_concurrent_downloads)
        self.config_defaults = self._load_config(config_path)

    def _load_config(self, path: str) -> Dict:
        """
        Loads and parses default settings from an INI configuration file.

        Args:
            path (str): The path to the configuration file.

        Returns:
            dict: Parsed settings where values are appropriately typed,
                    e.g., integers, booleans, or list of strings.
                    returns empty dict if file doesn't exist

        Note:
            Converts 'true' / 'false' strings to booleans
            command-separated strings to lists
            and attempts integer conversion for numeric values.
        """
        parser = configparser.ConfigParser()
        if not os.path.exists(path):
            self.logger.info("No config file found, using default settings.")
            return {}
        parser.read(path)

        settings = {}

        def _cast_value(value: str):
            if value.lower() in ["true", "false"]:
                return value.lower() == "true"
            if "," in value:
                return [v.strip() for v in value.split(",")]
            try:
                return int(value)
            except ValueError:
                return value

        if "Defaults" in parser:
            for key, value in parser["Defaults"].items():
                settings[key] = _cast_value(value)
        if "Proxy" in parser:
            # Note: The keys here match the config.ini file directly
            settings["proxy_opts"] = dict(parser["Proxy"])

        return settings

    def create_config_from_url(self, url: str, overrides: Optional[Dict] = None) -> DownloadConfig:
        """
        Creates a DownloadConfig instance from a URL, merging defaults and overrides.

        Args:
            url (str): The video URL, which is the only required parameter.
            overrides (Optional[Dict]): A dictionary of settings to override the defaults.

        Returns:
            DownloadConfig: A fully populated configuration object.
        """
        if overrides is None:
            overrides = {}

        # Prioritize overrides, then defaults, then dataclass defaults
        merged_settings = {**self.config_defaults, **overrides}

        # Filter settings to only include valid DownloadConfig fields
        valid_keys = {f.name for f in DownloadConfig.__dataclass_fields__.values()}
        filtered_settings = {k: v for k, v in merged_settings.items() if k in valid_keys}

        return DownloadConfig(url=url, **filtered_settings)

    def clear_info_cache(self):
        """Clears the in-memory info cache."""
        self.logger.debug("Clearing info cache.")
        self.info_cache.clear()

    # --- Extractor Methods ---
    def _extract_info(self, url: str) -> Optional[Dict]:
        """
        Robustly extracts video info using an in-memory cache to avoid redundant calls.

        Args:
            url (str): The video URL.

        Returns:
            Optional[Dict]: The extracted info dictionary, or None on failure.
        """
        if url in self.info_cache:
            self.logger.debug(f"Returning cached info for {url}")
            return self.info_cache[url]

        ydl_opts = {"quiet": True, "extract_flat": True}
        try:
            self.logger.debug(f"Fetching fresh info for {url}")
            with yt_dlp.YoutubeDL(ydl_opts) as ydl:
                info = ydl.extract_info(url, download=False)
                self.info_cache[url] = info  # Cache the result
                if info.get("is_live"):
                    self.logger.error("Live streams cannot be downloaded.")
                    return None
                if info.get("availability") == "upcoming":
                    self.logger.error("Upcoming videos cannot be downloaded.")
                    return None
                return info
        except DownloadError as e:
            error_msg = str(e)
            if "Private video" in error_msg:
                self.logger.error("This video is private and cannot be downloaded.")
            elif "Age restricted" in error_msg:
                self.logger.error("This video is age-restricted and requires login.")
            elif "Video unavailable" in error_msg:
                self.logger.error("This video is unavailable.")
            else:
                self.logger.error(f"Error extracting info for {url}: {e}")
            return None

    def get_video_metadata(self, url: str) -> Dict:
        """
        Fetches a curated set of metadata for a video.

        Args:
            url (str): The video URL to fetch metadata for.

        Returns:
            Dict: A dictionary containing key metadata fields.
                    returns an empty dict if info extraction fails after a valid URL is provided.
        """
        if not utils.is_valid_url(url):
            raise ValueError("Invalid YouTube URL format.")

        info = self._extract_info(url)
        if not info:
            return {}

        status = "VOD"  # Video On Demand
        if info.get("is_live"):
            status = "LIVE"
        elif info.get("was_live"):
            status = "WAS_LIVE"

        try:
            field_list = [
                "id",
                "title",
                "description",
                "channel",
                "upload_date",
                "duration",
                "tags",
                "view_count",
                "like_count",
                "subtitles",
                "chapters",
            ]
            metadata = {k: info.get(k) for k in field_list}
            metadata["status"] = status
            return metadata
        except Exception as e:
            self.logger.error(f"Error extracting metadata fields: {e}")
            return {}

    # --- Progress Methods ---
    def _create_progress_hook(self, download_id: str):
        """
        Creates a thread-safe closure for the yt-dlp progress hook that aggregates
        component progress into a single, file-level percentage.
        """

        def progress_hook(d):
            # Check for cancellation signal
            if (
                self.cancellation_events.get(download_id)
                and self.cancellation_events[download_id].is_set()
            ):
                raise InterruptedError("Download cancelled by user.")

            if d["status"] == "finished":
                # This now accurately reflects that a component, not the whole task, is done.
                filename = os.path.basename(d.get("filename", ""))
                self.logger.info(f"Component '{filename}' finished, starting post-processing...")

            with self.progress_lock:
                # Initialize the internal tracker for this download if it doesn't exist
                if "_components" not in self.progress_store[download_id]:
                    self.progress_store[download_id]["_components"] = {}

                status = d["status"]
                info_dict = d.get("info_dict", {})
                component_id = info_dict.get("format_id") or "postprocessing"

                if status == "downloading":
                    # Update the specific component's progress
                    self.progress_store[download_id]["_components"][component_id] = {
                        "total_bytes": d.get("total_bytes") or d.get("total_bytes_est", 0),
                        "downloaded_bytes": d.get("downloaded_bytes", 0),
                    }

                    # --- Aggregate Progress ---
                    total_downloaded = 0
                    total_size = 0
                    for comp in self.progress_store[download_id]["_components"].values():
                        total_downloaded += comp.get("downloaded_bytes", 0)
                        total_size += comp.get("total_bytes", 0)

                    # Update the main progress entry
                    self.progress_store[download_id].update(
                        {
                            "status": "downloading",
                            "total_bytes": total_size,
                            "downloaded_bytes": total_downloaded,
                            "speed": d.get("speed"),
                            "eta": d.get("eta"),
                        }
                    )

                elif status == "finished":
                    # Mark component as finished
                    if component_id in self.progress_store[download_id]["_components"]:
                        comp = self.progress_store[download_id]["_components"][component_id]
                        comp["downloaded_bytes"] = comp.get("total_bytes", 0)  # Mark as 100%

                # --- Playlist Info ---
                if info_dict.get("playlist_index") is not None:
                    self.progress_store[download_id]["playlist_info"] = {
                        "current_index": info_dict.get("playlist_index"),
                        "total_files": info_dict.get("n_entries"),
                        "current_title": info_dict.get("title"),
                    }

        return progress_hook

    def get_download_progress(self, download_id: str) -> Optional[Dict]:
        """Safely retrieves the progress for a given download ID."""
        with self.progress_lock:
            return self.progress_store.get(download_id, {}).copy()

    def get_all_statuses(self) -> Dict[str, Dict]:
        """
        Safely retrieves a copy of the entire progress store for all downloads.

        Returns:
            Dict[str, Dict]: all known download statuses, keyed by download id.
        """
        with self.progress_lock:
            return copy.deepcopy(self.progress_store)

    def cleanup_progress_of_old_downloads(self, max_age_hours: int = 24):
        """
        Cleans up progress entries older than max_age_hours.

        Args:
            max_age_hours (int): The age threshold in hours for cleanup.
        """
        cutoff_time = datetime.now() - timedelta(hours=max_age_hours)

        with self.progress_lock:
            downloads_to_keep = {}
            for download_id, progress_info in self.progress_store.items():
                status = progress_info.get("status")
                completion_time = progress_info.get("completion_time")
                # Keep if still pending/downloading or if recently completed/failed/cancelled
                if status in ["pending", "downloading", "pausing"] or (
                    completion_time and completion_time > cutoff_time
                ):
                    downloads_to_keep[download_id] = progress_info
                else:
                    self.logger.debug(f"Cleaning up old progress for download ID: {download_id}")
            self.progress_store = downloads_to_keep

        with self.progress_lock:
            self.progress_store = {
                k: v
                for k, v in self.progress_store.items()
                if v.get("status") != "completed"
                or v.get("completion_time", datetime.now()) > cutoff_time
            }
            to_delete = [
                k
                for k, v in self.progress_store.items()
                if v.get("status") in ["completed", "failed", "cancelled"]
                and v.get("timestamp", 0) < cutoff_time
            ]
            for k in to_delete:
                del self.progress_store[k]
                self.logger.debug(f"Cleaned up progress entry for download ID: {k}")

    # --- Cancel Download ---
    def cancel_download(self, download_id: str):
        """Signals a download thread to cancel its operation."""
        if download_id in self.cancellation_events:
            self.logger.info(f"Sending cancellation signal to download '{download_id}'...")
            self.cancellation_events[download_id].set()

    # --- Pause Download ---
    def pause_download(self, download_id: str):
        """Pauses a download by cancelling it and marking its state as paused."""
        self.logger.info(f"Pausing download '{download_id}'...")
        with self.progress_lock:
            if download_id in self.progress_store:
                # Set a flag to indicate this was a pause, not a full cancel
                self.progress_store[download_id]["status"] = "pausing"
        self.cancel_download(download_id)

    # --- Resume Download ---
    def resume_download(self, download_id: str):
        """Resumes a paused or failed download."""
        self.logger.info(f"Attempting to resume download '{download_id}'...")
        with self.progress_lock:
            progress = self.progress_store.get(download_id)
            if not progress or "config" not in progress:
                self.logger.error(f"Cannot resume '{download_id}': Original config not found.")
                return

            status = progress.get("status")
            if status not in ["paused", "failed", "cancelled"]:
                self.logger.warning(
                    f"Cannot resume '{download_id}': not in a resumable state (status: {status})."
                )
                return

            original_config_dict = progress["config"]

        # Create a new config object from the stored dictionary
        original_config = DownloadConfig(**original_config_dict)

        # yt-dlp resumes from the .part file on its own.
        self.start_download_task(download_id, original_config)

    # --- Proxy Method ---
    def _build_proxy_options(self, config: Dict) -> Dict:
        """
        Builds the proxy dictionary for yt-dlp, aligning with config.ini keys.

        Args:
            config (Dict): A dictionary containing proxy keys like 'http_proxy'.

        Returns:
            Dict: A dictionary formatted for yt-dlp's options.
        """
        options = {}
        if config.get("http_proxy"):
            options["http_proxy"] = config["http_proxy"]
        if config.get("https_proxy"):
            options["https_proxy"] = config["https_proxy"]
        if config.get("socks5_proxy"):
            options["proxy"] = config["socks5_proxy"]
        if config.get("no_proxy"):
            options["no_proxy"] = config["no_proxy"]
        return options

    # --- Core Download Logic ---
    def start_download_task(self, download_id: str, config: DownloadConfig):
        """
        Starts a new download task in a background thread with concurrency control.
        Validates parameters, prepares yt-dlp options (subtitles, proxies, chapters,
        time ranges), tracks progress, and handles cancellation.

        Args:
            download_id (str): A unique identifier for this download task.
            config (DownloadConfig): The configuration object for the download.

        Raises:
            None directly; errors are caught and logged, and reported in progress store.
        """
        # 1. Validate URL before proceeding
        if not utils.is_valid_url(config.url):
            self.logger.error(f"Invalid URL provided for task '{download_id}': {config.url}")
            with self.progress_lock:
                self.progress_store[download_id] = {
                    "status": "failed",
                    "error": "Invalid URL format.",
                }
            return

        os.makedirs(config.dest_folder, exist_ok=True)

        # 2. Sanitize the user-provided template part
        sanitized_template = utils.sanitize_filename(config.output_template)
        final_template = sanitized_template.replace(
            "{current_date}", datetime.now().strftime("%Y%m%d")
        )
        outtmpl = os.path.join(config.dest_folder, final_template)

        # Build format selector string
        if config.media_type == "audio":
            ytdl_format = "bestaudio/best"
        else:
            try:
                res_num = int("".join(filter(str.isdigit, config.resolution)))
            except ValueError, TypeError:
                self.logger.warning(
                    f"Invalid resolution '{config.resolution}', using {DEFAULT_RESOLUTION_NUM}p."
                )
                res_num = DEFAULT_RESOLUTION_NUM
            ytdl_format = f"bestvideo[height<={res_num}]+bestaudio/best[height<={res_num}]"

        ytdl_opts = {
            "format": ytdl_format,
            "outtmpl": outtmpl,
            "logger": YtdlLogger(),
            "progress_hooks": [self._create_progress_hook(download_id)],
            "postprocessors": [],
            "continuedl": True,
            "noprogress": False,
            "retries": 10,
            "fragment_retries": 10,
        }

        # Subtitles
        if config.enable_subtitles:
            ytdl_opts.update(
                {
                    "writesubtitles": True,
                    "subtitleslangs": config.subtitle_langs,
                    "embedsubtitles": config.embed_subtitles,
                }
            )

        # Post-processing
        if config.extract_audio:
            ytdl_opts["postprocessors"].append(
                {"key": "FFmpegExtractAudio", "preferredcodec": config.audio_codec}
            )
        if config.chapters:
            ytdl_opts["postprocessors"].append(
                {"key": "FFmpegSplitChapters", "chapters": ",".join(map(str, config.chapters))}
            )
        if config.embed_metadata:
            ytdl_opts["postprocessors"].append({"key": "FFmpegMetadata", "add_metadata": True})
        if config.embed_thumbnail:
            ytdl_opts["writethumbnail"] = True
            ytdl_opts["postprocessors"].append({"key": "EmbedThumbnail"})
        if config.media_type != "audio" and config.video_format:
            ytdl_opts["postprocessors"].append(
                {
                    "key": "FFmpegVideoConvertor",
                    "preferedformat": config.video_format,
                }
            )

        # Specific downloads
        if config.time_range:
            ytdl_opts["download_sections"] = f"*{config.time_range}"
        if config.playlist_items:
            ytdl_opts["playlist_items"] = config.playlist_items  # string like '1-5,8,10'

        # Proxy settings
        if config.proxy_opts:
            ytdl_opts.update(self._build_proxy_options(config.proxy_opts))

        # --- Initialize cancellation and run download in a thread ---
        self.cancellation_events[download_id] = threading.Event()

        # Guarantees the key exists before the thread starts
        with self.progress_lock:
            self.progress_store[download_id] = {"status": "pending", "config": asdict(config)}

        def run():
            acquired = False
            try:
                # Loop to acquire semaphore while checking for cancellation
                while not acquired:
                    if self.cancellation_events[download_id].is_set():
                        self.logger.warning(
                            f"Task '{download_id}' was cancelled while waiting for a download slot."
                        )
                        raise InterruptedError("Cancelled while queued.")
                    acquired = self.download_semaphore.acquire(blocking=True, timeout=1)

                # Proceed with download if semaphore was acquired
                with yt_dlp.YoutubeDL(ytdl_opts) as ydl:
                    ydl.download([config.url])
                self.logger.info(f"Download task '{download_id}' completed successfully.")
                if self.cancellation_events[download_id].is_set():
                    raise InterruptedError("Download cancelled by user.")
                with self.progress_lock:
                    self.progress_store[download_id]["status"] = "completed"
                    self.progress_store[download_id]["completion_time"] = datetime.now()

            except InterruptedError as e:
                # Check the status to see if this was a pause or a cancel
                with self.progress_lock:
                    current_status = self.progress_store[download_id].get("status")
                    final_status = "paused" if current_status == "pausing" else "cancelled"
                    self.logger.info(f"Download task '{download_id}' was {final_status}.")
                    self.progress_store[download_id].update(
                        {"status": final_status, "error": str(e), "completion_time": datetime.now()}
                    )
            except Exception as e:
                self.logger.error(f"Download task '{download_id}' failed: {e}", exc_info=True)
                with self.progress_lock:
                    self.progress_store[download_id].update(
                        {"status": "failed", "error": str(e), "completion_time": datetime.now()}
                    )
            finally:
                if acquired:
                    self.download_semaphore.release()
                if download_id in self.cancellation_events:
                    del self.cancellation_events[download_id]

        thread = threading.Thread(target=run, name=f"Downloader-{download_id}", daemon=True)
        thread.start()
