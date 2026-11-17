#!/usr/bin/env bash
# Tests for fetch-tools.sh — run: apps/media-grabber/scripts/tests/test_fetch_tools.sh

set -euo pipefail

SCRIPT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/fetch-tools.sh"
work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT

printf 'not a real tool\n' > "$work/yt-dlp_macos"
printf 'yt-dlp 1.0 file://%s %s\n' "$work/yt-dlp_macos" "$(printf '0%.0s' {1..64})" > "$work/tools.lock"

if MG_TOOLS_LOCK="$work/tools.lock" MG_TOOLS_OUT="$work/out" "$SCRIPT" >/dev/null 2>&1; then
    echo "FAIL - wrong checksum must make fetch-tools.sh exit non-zero"
    exit 1
fi
echo "ok   - wrong checksum exits non-zero"

if [ -n "$(find "$work/out/Resources/Tools" -type f 2>/dev/null)" ]; then
    echo "FAIL - nothing may be left in Resources/Tools after a checksum mismatch"
    exit 1
fi
echo "ok   - nothing left in Resources/Tools"
