#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
root="$(pwd)"
lock="$root/scripts/tools.lock"
cache="$root/build/tool-src"
tools="$root/Resources/Tools"
shield="$root/Resources/Shield"
mkdir -p "$cache" "$tools" "$shield"

field() {
  awk -v name="$1" '$1 == name { print $2 }' "$lock"
}
url_of() {
  awk -v name="$1" '$1 == name { print $3 }' "$lock"
}
sha_of() {
  awk -v name="$1" '$1 == name { print $4 }' "$lock"
}

fetch() {
  local name="$1" dest="$2"
  local url sha
  url="$(url_of "$name")"
  sha="$(sha_of "$name")"
  if [ ! -f "$dest" ] || ! printf '%s  %s\n' "$sha" "$dest" | shasum -a 256 -c - >/dev/null 2>&1; then
    curl -fL --retry 3 -o "$dest.partial" "$url"
    mv "$dest.partial" "$dest"
  fi
  printf '%s  %s\n' "$sha" "$dest" | shasum -a 256 -c -
}

fetch yt-dlp "$cache/yt-dlp_macos"
cp "$cache/yt-dlp_macos" "$tools/yt-dlp"
chmod 755 "$tools/yt-dlp"

fetch node "$cache/node.tar.gz"
if [ ! -x "$tools/node" ] || [ "$cache/node.tar.gz" -nt "$tools/node" ]; then
  rm -rf "$cache/node"
  mkdir -p "$cache/node"
  tar -xzf "$cache/node.tar.gz" -C "$cache/node" --strip-components=1
  cp "$cache/node/bin/node" "$tools/node"
  chmod 755 "$tools/node"
fi

fetch shield-plugin "$shield/plugin.zip"

stamp="$tools/.ffmpeg-source"
ffmpeg_sha="$(sha_of ffmpeg)"
if [ ! -x "$tools/ffmpeg" ] || [ ! -x "$tools/ffprobe" ] || [ "$(cat "$stamp" 2>/dev/null || true)" != "$ffmpeg_sha" ]; then
  fetch lame "$cache/lame.tar.gz"
  fetch ffmpeg "$cache/ffmpeg.tar.xz"
  rm -rf "$cache/lame-src" "$cache/ffmpeg-src" "$cache/lame-prefix"
  mkdir -p "$cache/lame-src" "$cache/ffmpeg-src" "$cache/lame-prefix"
  tar -xzf "$cache/lame.tar.gz" -C "$cache/lame-src" --strip-components=1
  tar -xJf "$cache/ffmpeg.tar.xz" -C "$cache/ffmpeg-src" --strip-components=1
  (
    cd "$cache/lame-src"
    ./configure --disable-shared --enable-static --prefix="$cache/lame-prefix"
    make -j"$(sysctl -n hw.ncpu)"
    make install
  )
  (
    cd "$cache/ffmpeg-src"
    ./configure \
      --disable-gpl \
      --disable-nonfree \
      --disable-shared \
      --enable-static \
      --disable-x86asm \
      --enable-libmp3lame \
      --pkg-config-flags=--static \
      --extra-cflags="-I$cache/lame-prefix/include" \
      --extra-ldflags="-L$cache/lame-prefix/lib" \
      --prefix="$cache/ffmpeg-prefix"
    make -j"$(sysctl -n hw.ncpu)"
  )
  cp "$cache/ffmpeg-src/ffmpeg" "$tools/ffmpeg"
  cp "$cache/ffmpeg-src/ffprobe" "$tools/ffprobe"
  chmod 755 "$tools/ffmpeg" "$tools/ffprobe"
  printf '%s\n' "$ffmpeg_sha" > "$stamp"
fi

if [ ! -f "$shield/server/build/main.js" ]; then
  fetch shield-source "$cache/shield.tar.gz"
  rm -rf "$cache/shield-src"
  mkdir -p "$cache/shield-src"
  tar -xzf "$cache/shield.tar.gz" -C "$cache/shield-src" --strip-components=1
  export PATH="$cache/node/bin:$PATH"
  (
    cd "$cache/shield-src/server"
    npm ci
    npx tsc
  )
  mkdir -p "$shield/server"
  rm -rf "$shield/server/build"
  cp -R "$cache/shield-src/server/build" "$shield/server/build"
fi
