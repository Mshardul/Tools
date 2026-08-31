import re
from urllib.parse import urlparse


def is_valid_url(url: str) -> bool:
    """
    Validates YouTube URL structure and accessibility.

    Args:
        url (str): The URL to validate.

    Returns:
        bool: True if the URL is a valid YouTube link, False otherwise.
    """
    try:
        result = urlparse(url)

        # check basic structure
        valid_domains = ["www.youtube.com", "youtube.com", "youtu.be", "music.youtube.com"]
        if not all([result.scheme in ["http", "https"], result.netloc in valid_domains]):
            return False

        # additional checks for specific URL patterns
        if result.netloc == "youtu.be" and len(result.path) > 1:  # short url must have ID
            return True
        elif "watch" in result.path and "v=" in result.query:  # standard watch URL
            return True
        elif any(x in result.path for x in ["playlist", "channel", "c/", "user", "shorts"]):
            return True
        return False
    except Exception:
        return False


def sanitize_filename(filename: str) -> str:
    """
    Removes characters from a string that are typically illegal or problematic in file paths across different OSes.

    Args:
        filename (str): The original filename string, potentially containing invalid characters.

    Returns:
        str: A sanitized filename string with illegal characters removed.
    """

    return re.sub(r'[\\/*?:"<>|]', "", filename)


def format_file_size(bytes_size: int) -> str:
    """
    Converts a file size in bytes to a human-readable string with appropriate units.

    Args:
        bytes_size (int): The file size in bytes.

    Returns:
        str: A human-readable string representing the file size (e.g., "2.5 MB").
    """
    if bytes_size < 0:
        return "Invalid size"

    units = ["B", "KB", "MB", "GB", "TB"]
    size = float(bytes_size)
    unit_index = 0

    while size >= 1024 and unit_index < len(units) - 1:
        size /= 1024
        unit_index += 1

    return f"{size:.2f} {units[unit_index]}"
