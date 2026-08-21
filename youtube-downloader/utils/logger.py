import logging

class DeprecationFilter(logging.Filter):
    """A filter to ignore specific deprecation warnings from libraries."""
    def filter(self, record):
        # Return False to prevent the log record from being processed
        if "Deprecated Feature" in record.getMessage():
            return False
        # Return True to allow other messages to pass through
        return True
    
LOGGER = logging.getLogger("yt_downloader")

class YtdlLogger:
    """A custom logger to capture specific yt-dlp messages."""
    def __init__(self, ui_callback=None):
        self.ui_callback = ui_callback # A function to send messages to the UI

    def debug(self, msg):
        # You can parse debug messages here if needed
        pass

    def warning(self, msg):
        LOGGER.warning(msg)

    def error(self, msg):
        LOGGER.error(msg)
        # Example of providing more specific user feedback
        user_friendly_error = msg
        if 'Unsupported URL' in msg:
            user_friendly_error = "The provided URL is not supported."
        elif 'HTTP Error 404' in msg:
            user_friendly_error = "Video not found (404 Error). It may be private or deleted."
        
        if self.ui_callback:
            self.ui_callback('error', user_friendly_error)

def setup_logging(level=logging.INFO):
    """Configures the root logger for the application."""
    # You can expand this to log to a file, etc.
    handler = logging.StreamHandler()
    formatter = logging.Formatter('%(asctime)s - %(name)s - %(levelname)s - %(message)s')
    handler.setFormatter(formatter)
    handler.addFilter(DeprecationFilter())

    if not LOGGER.handlers: # Prevent adding handlers multiple times
        LOGGER.addHandler(handler)
    LOGGER.setLevel(level)
    LOGGER.propagate = False
