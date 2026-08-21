import configparser
from dataclasses import dataclass, field
import logging
import os
from typing import List, Optional, Dict

# --- Constants ---
DEFAULT_RESOLUTION_NUM: int = 720
DEFAULT_DOWNLOAD_DIR: str = "downloads"
LOGGER: logging.Logger = logging.getLogger("yt_downloader")

# --- Data Structure ---
@dataclass
class DownloadConfig:
    """A dataclass to hold all download parameters."""
    url: str
    dest_folder: str = "downloads"
    output_template: str = "%(title)s.%(ext)s"
    
    # Media selection
    content_type: str = 'video'     # 'video', 'audio', or 'playlist'
    media_type: str = "video"       # 'video' or 'audio'
    video_format: str = "mp4" 
    resolution: str = "1080p"       # resolution string like '720p', or 'audio_only'
    
    # Subtitles
    enable_subtitles: bool = False
    subtitle_langs: List[str] = field(default_factory=lambda: ['en'])
    embed_subtitles: bool = True

    # Resume Support
    resume_download: bool = True
    
    # Post-processing
    extract_audio: bool = False
    audio_codec: str = "mp3"
    embed_metadata: bool = True
    embed_thumbnail: bool = False
    
    # Download Segments    
    time_range: Optional[str] = None                # e.g., "1:23-5:45"
    chapters: Optional[List[int]] = None            # list of chapters to download e.g., [1, 3]
    playlist_items: Optional[str] = None

    # Advanced
    proxy_opts: Dict = field(default_factory=dict)

def load_config(path: str = "config.ini") -> Dict:
    """Loads settings from an INI file."""
    config = configparser.ConfigParser()
    if not os.path.exists(path):
        return {} # Return empty if no config file
    config.read(path)
    
    settings = {}
    if 'Defaults' in config:
        settings.update(config['Defaults'])
    if 'Proxy' in config:
        settings['proxy_opts'] = dict(config['Proxy'])
        
    # Convert string 'true'/'false' to boolean
    def _parse_list(value: str) -> List[str]:
        return [item.strip() for item in value.split(',')] if value else []
    for key, value in settings.items():
        if isinstance(value, str):
            if value.lower() in ['true', 'false']:
                settings[key] = value.lower() == 'true'
            elif ',' in value:
                # Convert comma-separated string to list
                settings[key] = _parse_list(value)

            
    return settings