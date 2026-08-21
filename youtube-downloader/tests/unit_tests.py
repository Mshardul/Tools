from downloader import YoutubeDownloader 
import pytest
import re
from yt_dlp.utils import DownloadError

from config import DownloadConfig

@pytest.fixture
def downloader(mocker):
    """A fixture to provide a YoutubeDownloader instance with a mocked config."""
    mocker.patch('downloader.YoutubeDownloader._load_config', return_value={})
    return YoutubeDownloader()

def test_extract_info_success(mocker, downloader):
    """Test that _extract_info returns data on success."""
    mock_ydl_instance = mocker.MagicMock()
    mock_ydl_instance.extract_info.return_value = {'id': '123', 'title': 'Test Video'}

    mocker.patch('yt_dlp.YoutubeDL', return_value=mocker.MagicMock(__enter__=mocker.MagicMock(return_value=mock_ydl_instance)))

    result = downloader._extract_info("valid_url")
    assert result is not None
    assert result['title'] == 'Test Video'

def test_extract_info_failure(mocker, downloader):
    """Test that _extract_info returns None on DownloadError."""
    mock_ydl_instance = mocker.MagicMock()
    mock_ydl_instance.extract_info.side_effect = DownloadError("Test error")

    mocker.patch('yt_dlp.YoutubeDL', return_value=mocker.MagicMock(__enter__=mocker.MagicMock(return_value=mock_ydl_instance)))

    result = downloader._extract_info("invalid_url")
    assert result is None

def test_config_loading_with_type_casting(mocker, downloader):
    """Tests if the config loader correctly parses different data types."""
    mock_config_content = """
[Defaults]
download_directory = /test/path
default_resolution = 1080
embed_subtitles = false
subtitle_languages = en, fr, de
"""
    mocker.patch('os.path.exists', return_value=True)
    mocker.patch('builtins.open', mocker.mock_open(read_data=mock_config_content))
    
    config = downloader._load_config("dummy_path.ini")
    
    assert config['download_directory'] == '/test/path'
    assert config['default_resolution'] == 1080  # Should be an integer
    assert config['embed_subtitles'] is False     # Should be a boolean
    assert config['subtitle_languages'] == ['en', 'fr', 'de'] # Should be a list

@pytest.mark.parametrize("url, expected", [
    ("https://www.youtube.com/watch?v=dQw4w9WgXcQ", True),
    ("https://youtu.be/dQw4w9WgXcQ", True),
    ("https://music.youtube.com/watch?v=dQw4w9WgXcQ", True),
    ("http://www.youtube.com/shorts/xyz", True),
    ("www.youtube.com/watch?v=xyz", False), # Missing scheme
    ("https://vimeo.com/somevideo", False),   # Invalid domain
    ("not a url", False),
])
def test_url_validation(downloader, url, expected):
    """Tests the URL validation logic with various cases."""
    assert downloader._is_valid_url(url) == expected

def test_start_download_task_with_mocking(mocker, downloader):
    """Tests that start_download_task calls dependencies correctly."""
    mock_thread = mocker.patch('threading.Thread')
    mock_makedirs = mocker.patch('os.makedirs')
    mock_yt_dlp = mocker.patch('yt_dlp.YoutubeDL')
    
    config = DownloadConfig(url="https://www.youtube.com/watch?v=valid")
    download_id = "test-001"
    
    downloader.start_download_task(download_id, config)
    
    # Assert that directory creation was attempted
    mock_makedirs.assert_called_once_with(config.dest_folder, exist_ok=True)
    
    # Assert that a thread was created and started
    mock_thread.assert_called_once()
    mock_thread.return_value.start.assert_called_once()
