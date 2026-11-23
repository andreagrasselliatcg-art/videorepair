#!/bin/bash
# Scarica ffmpeg e ffprobe statici (Intel x86_64; su Apple Silicon girano con Rosetta)
# e verifica che funzionino su macOS 11 Big Sur.
set -euo pipefail
DEST="${1:-vendor/bin}"
MAX_MINOS="11.0"
mkdir -p "$DEST"
TMP="$(mktemp -d)"

minos() {
  otool -l "$1" | awk '
    /LC_BUILD_VERSION/ {b=1} b && /minos/ {print $2; exit}
    /LC_VERSION_MIN_MACOSX/ {v=1} v && /version/ {print $2; exit}'
}

ok_for_bigsur() {
  local m; m="$(minos "$1")"
  echo "INFO: $(basename "$1"): minos=$m archs=$(lipo -archs "$1" 2>&1)"
  [ -n "$m" ] && python3 -c "import sys;v=lambda s:tuple(map(int,s.split('.')));sys.exit(0 if v('$m')<=v('$MAX_MINOS') else 1)" \
    && lipo -archs "$1" | grep -q x86_64
}

try_source() {
  local name="$1" url_ffmpeg="$2" url_ffprobe="$3"
  echo "▶︎ Provo ${name}..."
  rm -rf "$TMP"/*
  mkdir -p "$TMP/a" "$TMP/b"
  curl -fsSL --retry 3 -o "$TMP/ffmpeg.zip"  "$url_ffmpeg"  || { echo "INFO: $name: download ffmpeg fallito"; return 1; }
  curl -fsSL --retry 3 -o "$TMP/ffprobe.zip" "$url_ffprobe" || { echo "INFO: $name: download ffprobe fallito"; return 1; }
  echo "INFO: $name: $(file -b "$TMP/ffmpeg.zip" | head -c 80)"
  unzip -oq "$TMP/ffmpeg.zip"  -d "$TMP/a" && unzip -oq "$TMP/ffprobe.zip" -d "$TMP/b" || { echo "INFO: $name: unzip fallito"; return 1; }
  local f p
  f="$(find "$TMP/a" -type f -name ffmpeg  | head -1)"
  p="$(find "$TMP/b" -type f -name ffprobe | head -1)"
  [ -n "$f" ] && [ -n "$p" ] || { echo "INFO: $name: binari non trovati: $(find "$TMP" -type f | head -5 | tr '\n' ' ')"; return 1; }
  chmod +x "$f" "$p"
  ok_for_bigsur "$f" && ok_for_bigsur "$p" || { echo "    non compatibile con Big Sur"; return 1; }
  cp "$f" "$p" "$DEST/"
  "$DEST/ffmpeg" -hide_banner -version | head -1
  echo "✅ ffmpeg da $name"
}

try_source "evermeet.cx" \
  "https://evermeet.cx/ffmpeg/getrelease/zip" \
  "https://evermeet.cx/ffmpeg/getrelease/ffprobe/zip" ||
try_source "martin-riedl.de" \
  "https://ffmpeg.martin-riedl.de/redirect/latest/macos/amd64/release/ffmpeg.zip" \
  "https://ffmpeg.martin-riedl.de/redirect/latest/macos/amd64/release/ffprobe.zip" ||
{ echo "❌ Nessun ffmpeg statico compatibile con macOS 11 trovato"; exit 1; }
