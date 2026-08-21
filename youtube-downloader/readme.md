# Python YouTube Downloader

A robust, multi-threaded YouTube downloader application built with Python and `yt-dlp`.

## Features

- **Concurrent Downloads:** Download multiple videos at once, with configurable limits.
- **Flexible Formats:** Choose between video and audio-only downloads, with specific resolution control.
- **Subtitle Support:** Download subtitles in multiple languages, either as separate files or embedded in the video.
- **Advanced Controls:**
    - Download specific time ranges or chapters.
    - Cancel in-progress downloads.
    - Automatic resuming of interrupted downloads.
    - Proxy support.
- **Custom Filenames:** Use dynamic placeholders like `%(title)s` and `{current_date}` to organize your downloads.
- **Configuration File:** Set your default preferences in a simple `config.ini` file.

## Getting Started

### Prerequisites

- Python 3.8+
- `ffmpeg` (must be installed and available in your system's PATH)

### Installation

1.  Clone the repository:
    ```bash
    git clone <your-repo-url>
    cd python-youtube-downloader
    ```

2.  Install the required dependencies:
    ```bash
    pip install -r requirements.txt
    ```

### Usage

1.  (Optional) Copy `config.sample.ini` to `config.ini` and customize your default settings.
2.  Run the application from the command line:
    ```bash
    python src/youtube_downloader/main.py
    ```
    *(Note: Adjust the path based on your final project structure)*

You can modify `main.py` to change the video URL and download options.