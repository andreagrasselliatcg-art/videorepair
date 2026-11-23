#!/bin/bash
# Compila ffmpeg + ffprobe statici per Mac Intel x86_64, compatibili con macOS 11 Big Sur
# (con libx264 e accelerazione hardware VideoToolbox). Funziona anche su runner Apple Silicon.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
DEST="$ROOT/${1:-vendor/bin}"
PREFIX="$ROOT/vendor/prefix"
SRC="$ROOT/vendor/src"
MIN=11.0
FFVER=7.1.1
FLAGS="-arch x86_64 -mmacosx-version-min=${MIN}"
JOBS="$(sysctl -n hw.ncpu)"
export MACOSX_DEPLOYMENT_TARGET="$MIN"
export PKG_CONFIG_LIBDIR="$PREFIX/lib/pkgconfig"   # ignora le librerie Homebrew

mkdir -p "$DEST" "$PREFIX" "$SRC"
command -v nasm >/dev/null || brew install nasm
command -v pkg-config >/dev/null || brew install pkgconf

echo "== x264 =="
cd "$SRC"
[ -d x264 ] || git clone --depth 1 https://code.videolan.org/videolan/x264.git
cd x264
CC=clang ./configure --prefix="$PREFIX" --host=x86_64-apple-darwin \
  --enable-static --disable-cli --enable-pic \
  --extra-cflags="$FLAGS" --extra-ldflags="$FLAGS"
make -j"$JOBS"
make install

echo "== ffmpeg ${FFVER} =="
cd "$SRC"
[ -d "ffmpeg-${FFVER}" ] || curl -fsSL "https://ffmpeg.org/releases/ffmpeg-${FFVER}.tar.xz" | tar xJ
cd "ffmpeg-${FFVER}"
./configure --prefix="$PREFIX" \
  --arch=x86_64 --target-os=darwin --enable-cross-compile \
  --cc="clang -arch x86_64" --cxx="clang++ -arch x86_64" \
  --extra-cflags="$FLAGS -I$PREFIX/include" \
  --extra-ldflags="$FLAGS -L$PREFIX/lib" \
  --pkg-config=pkg-config --pkg-config-flags=--static \
  --disable-autodetect \
  --enable-gpl --enable-libx264 \
  --enable-videotoolbox --enable-audiotoolbox \
  --enable-zlib --enable-bzlib \
  --enable-static --disable-shared \
  --disable-ffplay --disable-doc --disable-debug
make -j"$JOBS"
cp ffmpeg ffprobe "$DEST/"

echo "== Verifica =="
for b in ffmpeg ffprobe; do
  lipo -archs "$DEST/$b"
  otool -l "$DEST/$b" | grep -A4 LC_BUILD_VERSION | grep minos
  otool -L "$DEST/$b" | grep -v -E '/usr/lib/|/System/Library/' | tail -n +2 && { echo "dipendenze non di sistema!"; exit 1; } || true
done
echo "OK"
