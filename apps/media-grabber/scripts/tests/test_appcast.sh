#!/usr/bin/env bash
# Tests for appcast.py — run: apps/media-grabber/scripts/tests/test_appcast.sh [python]

set -euo pipefail

PY="${1:-python3}"
SCRIPT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/appcast.py"
work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT
fails=0

check() {
    local name="$1"; shift
    if "$@" >/dev/null 2>&1; then
        printf 'ok   - %s\n' "$name"
    else
        printf 'FAIL - %s\n' "$name"
        fails=$((fails + 1))
    fi
}

"$PY" "$SCRIPT" --existing "$work/none.xml" --version 0.1.0 \
    --url https://example.com/MediaGrabber-0.1.0.dmg --signature sig1 --length 100 \
    --notes https://example.com/notes/0.1.0 --out "$work/first.xml"
"$PY" "$SCRIPT" --existing "$work/first.xml" --version 0.2.0 \
    --url https://example.com/MediaGrabber-0.2.0.dmg --signature sig2 --length 200 \
    --notes https://example.com/notes/0.2.0 --out "$work/second.xml"

feed="$work/second.xml"
check "feed is well-formed xml" xmllint --noout "$feed"
check "two items" test "$(grep -c '<item>' "$feed")" = 2
check "newest item first" test "$(grep -o '<sparkle:version>[^<]*' "$feed" | head -1)" = '<sparkle:version>0.2.0'
check "older item kept second" test "$(grep -o '<sparkle:version>[^<]*' "$feed" | tail -1)" = '<sparkle:version>0.1.0'
check "new enclosure url" grep -q 'enclosure url="https://example.com/MediaGrabber-0.2.0.dmg"' "$feed"
check "new enclosure signature" grep -q 'sparkle:edSignature="sig2"' "$feed"
check "new enclosure length" grep -q 'length="200"' "$feed"
check "minimum system version" grep -q '<sparkle:minimumSystemVersion>14.0</sparkle:minimumSystemVersion>' "$feed"
check "release notes link" grep -q '<sparkle:releaseNotesLink>https://example.com/notes/0.2.0<' "$feed"
check "self-test" "$PY" "$SCRIPT" --self-test

exit "$fails"
