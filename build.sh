#!/bin/bash
# Compila VideoRepair.app Universal (Intel x86_64 + Apple Silicon arm64), macOS 11+
# Requisiti: Xcode o Command Line Tools
set -euo pipefail
cd "$(dirname "$0")"

APP=VideoRepair
MIN_MACOS=11.0
VERSION="${VERSION:-1.0}"
SDK="$(xcrun --sdk macosx --show-sdk-path)"

rm -rf build
mkdir -p build

for ARCH in x86_64 arm64; do
  echo "▶︎ Compilo per $ARCH…"
  xcrun swiftc -O -swift-version 5 -parse-as-library \
    -target "${ARCH}-apple-macos${MIN_MACOS}" \
    -sdk "$SDK" \
    Sources/*.swift \
    -o "build/${APP}-${ARCH}"
done

APPDIR="build/${APP}.app"
mkdir -p "$APPDIR/Contents/MacOS" "$APPDIR/Contents/Resources"
lipo -create "build/${APP}-x86_64" "build/${APP}-arm64" -output "$APPDIR/Contents/MacOS/$APP"
cp Info.plist "$APPDIR/Contents/Info.plist"
plutil -replace CFBundleShortVersionString -string "$VERSION" "$APPDIR/Contents/Info.plist"
[ -f Resources/AppIcon.icns ] && cp Resources/AppIcon.icns "$APPDIR/Contents/Resources/"

# Includi ffmpeg/ffprobe/untrunc nell'app:  FFMPEG_DIR=/cartella ./build.sh
if [ -n "${FFMPEG_DIR:-}" ]; then
  mkdir -p "$APPDIR/Contents/Resources/bin"
  for t in ffmpeg ffprobe untrunc; do
    if [ -x "$FFMPEG_DIR/$t" ]; then
      cp "$FFMPEG_DIR/$t" "$APPDIR/Contents/Resources/bin/"
      codesign --force --sign - "$APPDIR/Contents/Resources/bin/$t"
      echo "  incluso $t"
    fi
  done
fi

codesign --force --sign - "$APPDIR"
rm -f "build/${APP}-x86_64" "build/${APP}-arm64"

lipo -info "$APPDIR/Contents/MacOS/$APP"
echo "✅ Pronto: $APPDIR"
