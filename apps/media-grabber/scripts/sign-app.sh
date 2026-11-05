#!/bin/bash
# Signs Sparkle's nested helpers, then the framework, then the app. Ad-hoc unless an identity is passed.
set -euo pipefail

app="${1:?app bundle}"
identity="${2:--}"

framework="$app/Contents/Frameworks/Sparkle.framework"
test -d "$framework" || { echo "Sparkle.framework missing in $app" >&2; exit 1; }

sign() {
  codesign --force --sign "$identity" --timestamp=none "$1"
}

version_dir="$(cd "$framework/Versions" && find . -mindepth 1 -maxdepth 1 -type d ! -name Current | head -1)"
version_dir="${version_dir#./}"
root="$framework/Versions/$version_dir"

if [ -d "$root/XPCServices" ]; then
  find "$root/XPCServices" -name '*.xpc' -type d -print0 | while IFS= read -r -d '' service; do
    sign "$service"
  done
fi
if [ -e "$root/Autoupdate" ]; then
  sign "$root/Autoupdate"
fi
if [ -d "$root/Updater.app" ]; then
  sign "$root/Updater.app"
fi
sign "$framework"
sign "$app"
codesign --verify --strict "$app"
