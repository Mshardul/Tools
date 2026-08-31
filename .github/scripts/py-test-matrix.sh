#!/usr/bin/env bash
# Emit a JSON array of Python leaf dirs that changed between two git refs and
# have a tests/ directory. Used by the python-clis workflow to build its test
# matrix. With no refs (or BASE==HEAD) it emits every testable Python leaf.
#
# Usage: py-test-matrix.sh [BASE_REF] [HEAD_REF]
# Output (stdout): ["cli/base64-tool","apps/claude-session-archive"]

set -euo pipefail

BASE_REF="${1:-}"
HEAD_REF="${2:-HEAD}"

# Every Python leaf that ships tests. Keep this list in sync with the tree;
# a leaf without tests/ is skipped automatically below.
roots=(cli apps)

is_testable() {
    local dir="$1"
    [ -d "$dir/tests" ] || return 1
    compgen -G "$dir/*.py" >/dev/null
}

all_testable() {
    local root dir
    for root in "${roots[@]}"; do
        for dir in "$root"/*/; do
            dir="${dir%/}"
            if is_testable "$dir"; then
                printf '%s\n' "$dir"
            fi
        done
    done
    return 0
}

changed_testable() {
    local changed dir
    changed="$(git diff --name-only "$BASE_REF" "$HEAD_REF")"
    while read -r dir; do
        if grep -q "^${dir}/" <<<"$changed"; then
            printf '%s\n' "$dir"
        fi
    done < <(all_testable)
    return 0
}

if [ -z "$BASE_REF" ] || [ "$BASE_REF" = "$HEAD_REF" ]; then
    dirs="$(all_testable)"
else
    dirs="$(changed_testable)"
fi

# Fold newline list into a compact JSON array.
if [ -z "$dirs" ]; then
    printf '[]\n'
else
    printf '%s\n' "$dirs" | sort | awk 'BEGIN{printf "["} {printf "%s\"%s\"", (NR>1?",":""), $0} END{print "]"}'
fi
