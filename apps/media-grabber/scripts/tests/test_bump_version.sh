#!/usr/bin/env bash
# Tests for bump-version.sh.
# Run: apps/media-grabber/scripts/tests/test_bump_version.sh

set -euo pipefail

SCRIPT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/bump-version.sh"
fails=0

ok_case() {
    local name="$1" current="$2" bump="$3" expected="$4" actual
    actual="$("$SCRIPT" "$current" "$bump")"
    if [ "$actual" = "$expected" ]; then
        printf 'ok   - %s\n' "$name"
    else
        printf 'FAIL - %s\n      expected: %s\n      actual:   %s\n' "$name" "$expected" "$actual"
        fails=$((fails + 1))
    fi
}

rejects() {
    local name="$1"; shift
    if "$SCRIPT" "$@" >/dev/null 2>&1; then
        printf 'FAIL - %s (expected non-zero exit)\n' "$name"
        fails=$((fails + 1))
    else
        printf 'ok   - %s\n' "$name"
    fi
}

ok_case "patch mid-range"        0.4.2 patch 0.4.3
ok_case "minor mid-range"        0.4.2 minor 0.5.0
ok_case "major mid-range"        0.4.2 major 1.0.0
ok_case "patch from 0.0.0"       0.0.0 patch 0.0.1
ok_case "minor from 0.0.0"       0.0.0 minor 0.1.0
ok_case "major from 0.0.0"       0.0.0 major 1.0.0
ok_case "minor zeroes patch"     3.7.9 minor 3.8.0
ok_case "major zeroes minor+patch" 3.7.9 major 4.0.0
ok_case "two-digit components"   9.10.11 patch 9.10.12

rejects "too few parts"          1.2 patch
rejects "too many parts"         1.2.3.4 patch
rejects "v prefix"               v1.2.3 patch
rejects "non-numeric component"  1.2.x patch
rejects "unknown bump word"      1.2.3 sideways
rejects "missing bump arg"       1.2.3
rejects "empty current"          "" patch

if [ "$fails" -ne 0 ]; then
    printf '\n%d test(s) failed\n' "$fails"
    exit 1
fi
printf '\nall tests passed\n'
