import calendar
import importlib.util
import json
import os
import socket
import tempfile
import unittest
from unittest import mock
from urllib.parse import parse_qs

from yt_dlp import YoutubeDL
from yt_dlp.extractor.common import InfoExtractor
from yt_dlp.extractor.zoom import ZoomIE as BaseZoomIE
from yt_dlp.utils import ExtractorError

PLUGIN_PATH = os.path.join(
    os.path.dirname(__file__),
    "..",
    "..",
    "Resources",
    "YtDlpPlugins",
    "zoomfix",
    "yt_dlp_plugins",
    "extractor",
    "zoom_share_passcode.py",
)

SHARE_URL = "https://example.zoom.us/rec/share/TOKEN.ABC"
BASE = "https://example.zoom.us/"


def setUpModule():
    def refuse(*args, **kwargs):
        raise AssertionError("plugin tests must never open a network connection")

    patcher = mock.patch.object(socket.socket, "connect", refuse)
    patcher.start()
    unittest.addModuleCleanup(patcher.stop)


def load_plugin():
    spec = importlib.util.spec_from_file_location("zoom_share_passcode_under_test", PLUGIN_PATH)
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


def page(data):
    return f"<html><script>window.__data__ = {json.dumps(data)};</script></html>"


class FakeZoom:
    def __init__(
        self,
        plugin,
        passcode="secret",
        share_info=None,
        component=None,
        validation=None,
        share_page=None,
    ):
        self.share_page = share_page
        self.calls = []
        self.bodies = {}
        self.share_info = share_info or {
            "componentName": "need-password",
            "meetingId": "MEET",
            "redirectUrl": "/rec/component-page",
            "accessLevel": "meeting",
        }
        self.component = component or {
            "meeting_id": "ENC",
            "fileId": "",
            "action": "viewdetailpage",
            "useWhichPasswd": "meeting",
            "sharelevel": "meeting",
            "needRecaptcha": False,
        }
        self.validation = {"status": True} if validation is None else validation
        self.share_info_count = 0
        params = {"quiet": True, "no_warnings": True}
        if passcode is not None:
            params["videopassword"] = passcode
        self.ie = plugin.ZoomIE(YoutubeDL(params))
        self.ie._download_webpage = self.download_webpage
        self.ie._download_json = self.download_json

    def url_of(self, request):
        return getattr(request, "url", request)

    def download_webpage(self, request, video_id, note=None, headers=None, **kwargs):
        url = self.url_of(request)
        self.calls.append(url)
        if url == SHARE_URL:
            return self.share_page or page({"meetingId": "MEET"})
        if "component-page" in url:
            return page(self.component)
        if "csrf_js" in url:
            return "ZOOM-CSRFTOKEN:TOKEN-1234"
        raise AssertionError(f"unexpected webpage request {url}")

    def download_json(self, url, video_id, note=None, data=None, headers=None, **kwargs):
        self.calls.append(url)
        if "share-info" in url:
            self.share_info_count += 1
            if self.share_info_count == 1:
                return {"result": self.share_info}
            return {"result": {"redirectUrl": "/rec/play/FILE?accessLevel=meeting"}}
        if "validate-context" in url:
            return {"status": True}
        if "validate-meeting-passwd" in url:
            self.bodies["passwd"] = parse_qs(data.decode())
            return self.validation
        raise AssertionError(f"unexpected json request {url}")

    def count(self, fragment):
        return sum(1 for call in self.calls if fragment in call)


class PacingTests(unittest.TestCase):
    def setUp(self):
        self.plugin = load_plugin()
        self.state = tempfile.NamedTemporaryFile(delete=False)
        self.state.close()
        self.addCleanup(os.unlink, self.state.name)
        self.sleeps = []
        self.clock = [1000.0]

    def pace(self):
        self.plugin._pace(
            now=lambda: self.clock[0],
            sleep=lambda seconds: (self.sleeps.append(seconds), self._advance(seconds)),
            path=self.state.name,
            gap=5.0,
        )

    def _advance(self, seconds):
        self.clock[0] += seconds

    def test_second_request_with_no_gap_sleeps_five_seconds(self):
        self.pace()
        self.pace()
        self.assertEqual(self.sleeps, [5.0])

    def test_request_after_the_gap_does_not_sleep(self):
        self.pace()
        self.clock[0] += 6.0
        self.pace()
        self.assertEqual(self.sleeps, [])

    def test_recorded_time_in_the_future_sleeps_at_most_the_gap(self):
        with open(self.state.name, "w") as handle:
            handle.write(repr(self.clock[0] + 3600))
        self.pace()
        self.assertEqual(self.sleeps, [5.0])

    def test_unreadable_state_counts_as_never(self):
        with open(self.state.name, "w") as handle:
            handle.write("not a number")
        self.pace()
        self.assertEqual(self.sleeps, [])

    def test_real_clock_calls_are_never_closer_than_the_gap(self):
        stamps = []
        import time as real_time

        for _ in range(3):
            self.plugin._pace(path=self.state.name, gap=0.2)
            stamps.append(real_time.time())
        gaps = [later - earlier for earlier, later in zip(stamps, stamps[1:])]
        self.assertTrue(all(gap >= 0.19 for gap in gaps), gaps)

    def test_every_extractor_request_is_paced_before_it_is_sent(self):
        order = []
        for extractor in (self.plugin.ZoomIE, self.plugin.ZoomClipsIE):
            with (
                mock.patch.object(self.plugin, "_pace", lambda: order.append("pace")),
                mock.patch.object(
                    InfoExtractor, "_request_webpage", lambda *args, **kwargs: order.append("send")
                ),
            ):
                extractor(YoutubeDL({"quiet": True}))._request_webpage(
                    "https://example.zoom.us/x", "id"
                )
        self.assertEqual(order, ["pace", "send", "pace", "send"])


class ShareFlowTests(unittest.TestCase):
    def setUp(self):
        self.plugin = load_plugin()

    def test_missing_passcode_raises_the_stock_sentence_without_validating(self):
        fake = FakeZoom(self.plugin, passcode=None)
        with self.assertRaisesRegex(ExtractorError, "protected by a passcode"):
            fake.ie._real_extract(SHARE_URL)
        self.assertEqual(fake.count("validate-meeting-passwd"), 0)

    def test_rejected_passcode_raises_once_and_sends_one_attempt(self):
        fake = FakeZoom(self.plugin, validation={"status": False})
        with self.assertRaisesRegex(ExtractorError, "Zoom rejected the passcode"):
            fake.ie._real_extract(SHARE_URL)
        self.assertEqual(fake.count("validate-meeting-passwd"), 1)

    def test_captcha_page_raises_before_any_passcode_is_sent(self):
        component = {
            "meeting_id": "ENC",
            "fileId": "",
            "action": "viewdetailpage",
            "useWhichPasswd": "meeting",
            "sharelevel": "meeting",
            "needRecaptcha": True,
        }
        fake = FakeZoom(self.plugin, component=component)
        with self.assertRaisesRegex(ExtractorError, "confirm you're not a bot"):
            fake.ie._real_extract(SHARE_URL)
        self.assertEqual(fake.count("validate-meeting-passwd"), 0)

    def test_accepted_passcode_hands_the_play_url_to_the_stock_extractor(self):
        fake = FakeZoom(self.plugin)
        with mock.patch.object(
            BaseZoomIE, "_real_extract", return_value={"id": "file-id"}
        ) as stock:
            info = fake.ie._real_extract(SHARE_URL)
        stock.assert_called_once_with("https://example.zoom.us/rec/play/FILE?accessLevel=meeting")
        self.assertEqual(info["id"], "TOKEN.ABC")

    def _extract_with_formats(self, *file_names):
        fake = FakeZoom(self.plugin)
        formats = [
            {
                "url": f"https://ssrweb.zoom.us/cmr/replay/2026/10/31/ABC/{name}.mp4?data=1&s=2",
                "preference": rank,
            }
            for rank, name in enumerate(file_names)
        ]
        stock_info = {"id": "file-id", "title": "Product & Brand Management", "formats": formats}
        with mock.patch.object(BaseZoomIE, "_real_extract", return_value=stock_info):
            return fake.ie._real_extract(SHARE_URL)

    def test_title_and_timestamp_come_from_the_zoom_file_name(self):
        info = self._extract_with_formats("GMT20261031-105457_Recording_1760x900")
        self.assertEqual(info["title"], "GMT20261031-105457_Recording_1760x900")
        self.assertEqual(info["timestamp"], calendar.timegm((2026, 10, 31, 10, 54, 57)))

    def test_the_best_ranked_format_names_the_recording(self):
        info = self._extract_with_formats(
            "GMT20261031-105457_Recording_1760x900",
            "GMT20261031-105457_Recording_gallery_1920x1080",
        )
        self.assertEqual(info["title"], "GMT20261031-105457_Recording_gallery_1920x1080")

    def test_a_file_name_without_the_zoom_pattern_keeps_the_topic_title(self):
        info = self._extract_with_formats("something-else")
        self.assertEqual(info["title"], "Product & Brand Management")
        self.assertNotIn("timestamp", info)

    def test_passcode_with_leading_dash_and_space_is_sent_unchanged(self):
        fake = FakeZoom(self.plugin, passcode="-ab c+")
        with mock.patch.object(BaseZoomIE, "_real_extract", return_value={"id": "x"}):
            fake.ie._real_extract(SHARE_URL)
        self.assertEqual(fake.bodies["passwd"]["passwd"], ["-ab c+"])

    def test_zoom_error_page_for_a_missing_recording_says_no_longer_available(self):
        error_page = (
            '<html><head><title>Error - Zoom</title></head><body><div class="error-container">'
            '<span class="error-message"> This recording does not exist. (3,301) '
            "</span></div></body></html>"
        )
        fake = FakeZoom(self.plugin, share_page=error_page)
        with self.assertRaisesRegex(ExtractorError, "This Zoom recording is no longer available"):
            fake.ie._real_extract(SHARE_URL)
        self.assertEqual(fake.count("share-info"), 0)

    def test_other_zoom_error_page_quotes_zoom_without_the_code(self):
        error_page = (
            '<html><span class="error-message"> Something odd happened. (9,999) </span></html>'
        )
        fake = FakeZoom(self.plugin, share_page=error_page)
        with self.assertRaisesRegex(
            ExtractorError, r"^Zoom could not show this recording: Something odd happened\.$"
        ):
            fake.ie._real_extract(SHARE_URL)

    def test_page_with_no_data_and_no_error_message_says_zoom_changed(self):
        fake = FakeZoom(self.plugin, share_page="<html><body>nothing useful</body></html>")
        with self.assertRaisesRegex(ExtractorError, "Zoom changed how its recordings work"):
            fake.ie._real_extract(SHARE_URL)

    def test_non_share_url_goes_straight_to_the_stock_extractor(self):
        fake = FakeZoom(self.plugin)
        with mock.patch.object(BaseZoomIE, "_real_extract", return_value={"id": "play"}) as stock:
            fake.ie._real_extract("https://example.zoom.us/rec/play/ABC")
        stock.assert_called_once()
        self.assertEqual(fake.calls, [])


if __name__ == "__main__":
    unittest.main()
