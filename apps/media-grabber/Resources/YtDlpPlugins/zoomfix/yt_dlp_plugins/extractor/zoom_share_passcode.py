import calendar
import fcntl
import os
import re
import tempfile
import time
from datetime import datetime

from yt_dlp.extractor.zoom import ZoomClipsIE as BaseZoomClipsIE
from yt_dlp.extractor.zoom import ZoomIE as BaseZoomIE
from yt_dlp.networking import Request
from yt_dlp.utils import (
    ExtractorError,
    js_to_json,
    update_url_query,
    url_basename,
    urlencode_postdata,
    urljoin,
)

PACING_SECONDS = 5.0
_PACING_STATE = os.path.join(tempfile.gettempdir(), "mediagrabber-zoom-pacing")


def _pace(now=time.time, sleep=time.sleep, path=_PACING_STATE, gap=PACING_SECONDS):
    with open(path, "a+") as handle:
        fcntl.flock(handle, fcntl.LOCK_EX)
        handle.seek(0)
        try:
            last = float(handle.read() or 0)
        except ValueError:
            last = 0.0
        wait = min(gap, last + gap - now())
        if wait > 0:
            sleep(wait)
        handle.seek(0)
        handle.truncate()
        handle.write(repr(now()))
        handle.flush()


def _first_object_after(html, marker):
    start = html.find(marker)
    start = html.find("{", start) if start >= 0 else -1
    if start < 0:
        return None
    depth, in_string, escaped, quote = 0, False, False, ""
    for index in range(start, len(html)):
        char = html[index]
        if in_string:
            if escaped:
                escaped = False
            elif char == "\\":
                escaped = True
            elif char == quote:
                in_string = False
        elif char in "\"'":
            in_string, quote = True, char
        elif char == "{":
            depth += 1
        elif char == "}":
            depth -= 1
            if depth == 0:
                return html[start : index + 1]
    return None


_GONE_PHRASES = ("does not exist", "expired", "deleted", "removed")


def _error_message(html):
    match = re.search(r'class="error-message"[^>]*>\s*([^<]*?)\s*</span>', html)
    if not match:
        return None
    return re.sub(r"\s*\(\d+(?:,\d+)*\)\s*$", "", match.group(1)).strip()


def _unreadable_share_page_error(html):
    message = _error_message(html)
    if message is None:
        return ExtractorError(
            "Zoom changed how its recordings work, so this link can't be read. "
            "MediaGrabber needs an update.",
            expected=True,
        )
    if any(phrase in message.lower() for phrase in _GONE_PHRASES):
        return ExtractorError("This Zoom recording is no longer available.", expected=True)
    return ExtractorError(f"Zoom could not show this recording: {message}", expected=True)


_ZOOM_FILE_NAME = re.compile(r"^(GMT(\d{8})-(\d{6})_[^/?#]+)\.mp4$")


# Every session of a course shares one meeting topic, so Zoom's own file name
# (unique per recording) names the file.
def _named_after_zoom_file(info):
    best = None
    for fmt in info.get("formats") or []:
        match = _ZOOM_FILE_NAME.match(url_basename(fmt.get("url") or ""))
        if match and (
            best is None or (fmt.get("preference") or 0) > (best[0].get("preference") or 0)
        ):
            best = (fmt, match)
    if best is None:
        return info
    info["title"] = best[1].group(1)
    try:
        started = datetime.strptime(best[1].group(2) + best[1].group(3), "%Y%m%d%H%M%S")
        info["timestamp"] = calendar.timegm(started.timetuple())
    except ValueError:
        pass
    return info


class _PacedMixin:
    def _request_webpage(self, *args, **kwargs):
        _pace()
        return super()._request_webpage(*args, **kwargs)


class ZoomClipsIE(_PacedMixin, BaseZoomClipsIE):
    pass


# Stock yt-dlp's zoom extractor can't pass Zoom's current passcode page,
# so share links are handled here.
class ZoomIE(_PacedMixin, BaseZoomIE):
    def _component_data(self, webpage, video_id):
        text = _first_object_after(webpage, "window.__data__")
        if not text:
            raise ExtractorError("Unable to extract passcode page data")
        return self._parse_json(text, video_id, transform_source=js_to_json)

    def _csrf_token(self, base_url, video_id):
        body = self._download_webpage(
            Request(f"{base_url}csrf_js?t_x_zm_rid=1", data=b"", headers={"FETCH-CSRF-TOKEN": "1"}),
            video_id,
            note="Downloading CSRF token",
        )
        return self._search_regex(r"ZOOM-CSRFTOKEN:([\w-]+)", body, "CSRF token")

    def _share_info(self, base_url, meeting_id, video_id, note):
        domain = base_url.split("//", 1)[1].strip("/")
        return self._download_json(
            f"{base_url}nws/recording/1.0/play/share-info/{meeting_id}"
            f"?originDomain={domain}&accessLevel=meeting",
            video_id,
            note=note,
            headers={"X-Requested-With": "XMLHttpRequest"},
        )["result"]

    def _redirect_url(self, base_url, result, origin_url=None):
        redirect = urljoin(base_url, result["redirectUrl"])
        if "?" in redirect:
            return redirect
        query = {
            key: value
            for key, value in result.items()
            if isinstance(value, str) and key != "redirectUrl"
        }
        if origin_url:
            query["originRequestUrl"] = origin_url
        return update_url_query(redirect, query)

    def _unlock_with_passcode(self, base_url, share_url, result, video_id):
        passcode = self.get_param("videopassword")
        if not passcode:
            raise ExtractorError(
                "This video is protected by a passcode, use the --video-password option",
                expected=True,
            )
        component_url = self._redirect_url(base_url, result, origin_url=share_url)
        component = self._download_webpage(
            component_url,
            video_id,
            note="Downloading passcode page",
            headers={"Referer": share_url},
        )
        data = self._component_data(component, video_id)
        if data.get("needRecaptcha"):
            raise ExtractorError(
                "Zoom is asking to confirm you're not a bot. "
                "Open the link in your browser once, then try again.",
                expected=True,
            )
        headers = {
            "zoom-csrftoken": self._csrf_token(base_url, video_id),
            "X-Requested-With": "XMLHttpRequest",
            "Referer": component_url,
        }
        self._download_json(
            f"{base_url}nws/recording/1.0/validate-context",
            video_id,
            note="Validating context",
            data=urlencode_postdata(
                {
                    "meetingId": data["meeting_id"],
                    "fileId": data["fileId"],
                    "useWhichPasswd": data["useWhichPasswd"],
                    "sharelevel": data["sharelevel"],
                    "iet": "",
                }
            ),
            headers=headers,
        )
        validation = self._download_json(
            f"{base_url}nws/recording/1.0/validate-meeting-passwd",
            video_id,
            note="Validating passcode",
            data=urlencode_postdata(
                {
                    "id": data["meeting_id"],
                    "passwd": passcode,
                    "action": data["action"],
                    "recaptcha": "",
                }
            ),
            headers=headers,
        )
        if not validation.get("status"):
            self.write_debug(f"validate-meeting-passwd response keys: {sorted(validation)}")
            raise ExtractorError("Zoom rejected the passcode", expected=True)
        return data["meeting_id"]

    def _real_extract(self, url):
        base_url, url_type, video_id = self._match_valid_url(url).group("base_url", "type", "id")
        if url_type != "share":
            return _named_after_zoom_file(super()._real_extract(url))

        webpage = self._download_webpage(url, video_id, note="Downloading share webpage")
        try:
            meeting_id = self._get_page_data(webpage, video_id)["meetingId"]
        except ExtractorError:
            raise _unreadable_share_page_error(webpage) from None
        result = self._share_info(base_url, meeting_id, video_id, "Downloading share info JSON")
        if result.get("componentName") == "need-password":
            meeting_id = self._unlock_with_passcode(base_url, url, result, video_id)
            result = self._share_info(base_url, meeting_id, video_id, "Downloading share info JSON")

        info = super()._real_extract(self._redirect_url(base_url, result))
        info["id"] = video_id
        return _named_after_zoom_file(info)
