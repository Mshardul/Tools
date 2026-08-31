#!/usr/bin/env bash
# Usage: py-test-matrix.sh [BASE_REF] [HEAD_REF]
# Prints a JSON array of testable Python leaf dirs changed in BASE..HEAD (all of them with no refs). Feeds the python-clis test matrix.

set -euo pipefail

BASE_REF="${1:-}"
HEAD_REF="${2:-HEAD}"

# Leaves are found by their tests/ dir; one whose parent has no top-level *.py is skipped.
roots=(cli apps extensions)

all_testable() {
    local testsdir dir
    while IFS= read -r testsdir; do
        dir="${testsdir%/tests}"
        if compgen -G "$dir/*.py" >/dev/null; then
            printf '%s\n' "$dir"
        fi
    done < <(find "${roots[@]}" -type d -name tests -prune 2>/dev/null | sort)
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

# Fold into a compact JSON array.
if [ -z "$dirs" ]; then
    printf '[]\n'
else
    printf '%s\n' "$dirs" | sort | awk 'BEGIN{printf "["} {printf "%s\"%s\"", (NR>1?",":""), $0} END{print "]"}'
fi
