#!/usr/bin/env bash
# Usage: bump-version.sh <current N.N.N> <patch|minor|major>  -> prints next bare version

set -euo pipefail

current="${1:-}"
bump="${2:-}"

die() { echo "bump-version: $1" >&2; exit 1; }

case "$current" in
    [0-9]*.[0-9]*.[0-9]*) ;;
    *) die "current version must be N.N.N, got: '${current}'" ;;
esac

IFS=. read -r major minor patch extra <<EOF
$current
EOF

[ -z "$extra" ] || die "current version must be N.N.N, got: '${current}'"

for part in "$major" "$minor" "$patch"; do
    case "$part" in
        ''|*[!0-9]*) die "current version must be N.N.N, got: '${current}'" ;;
    esac
done

case "$bump" in
    patch) patch=$((patch + 1)) ;;
    minor) minor=$((minor + 1)); patch=0 ;;
    major) major=$((major + 1)); minor=0; patch=0 ;;
    *) die "bump must be patch|minor|major, got: '${bump}'" ;;
esac

printf '%s.%s.%s\n' "$major" "$minor" "$patch"
