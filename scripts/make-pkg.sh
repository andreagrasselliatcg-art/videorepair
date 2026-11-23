#!/bin/bash
# Crea l'installer VideoRepair-<versione>.pkg che installa l'app in /Applicazioni
set -euo pipefail
cd "$(dirname "$0")/.."
VERSION="${VERSION:-1.0}"
APP="build/VideoRepair.app"
[ -d "$APP" ] || { echo "Esegui prima ./build.sh"; exit 1; }

ROOT="build/pkgroot"
rm -rf "$ROOT" build/component.plist build/VideoRepair-component.pkg
mkdir -p "$ROOT/Applications"
cp -R "$APP" "$ROOT/Applications/"

# Installa sempre in /Applications (niente "rilocazione" su copie esistenti)
pkgbuild --analyze --root "$ROOT" build/component.plist
plutil -replace 0.BundleIsRelocatable -bool NO build/component.plist

pkgbuild --root "$ROOT" \
  --component-plist build/component.plist \
  --identifier it.videorepair.pkg \
  --version "$VERSION" \
  --install-location / \
  --scripts pkg-scripts \
  build/VideoRepair-component.pkg

cat > build/distribution.xml <<XML
<?xml version="1.0" encoding="utf-8"?>
<installer-gui-script minSpecVersion="2">
    <title>VideoRepair</title>
    <welcome file="welcome.txt"/>
    <options customize="never" require-scripts="false" hostArchitectures="x86_64,arm64"/>
    <allowed-os-versions><os-version min="11.0"/></allowed-os-versions>
    <choices-outline><line choice="default"/></choices-outline>
    <choice id="default" title="VideoRepair"><pkg-ref id="it.videorepair.pkg"/></choice>
    <pkg-ref id="it.videorepair.pkg" version="$VERSION" onConclusion="none">VideoRepair-component.pkg</pkg-ref>
</installer-gui-script>
XML

mkdir -p build/resources
cat > build/resources/welcome.txt <<TXT
VideoRepair $VERSION

Ripara i video corrotti (MP4, MOV, M4V, MKV, AVI, MTS…).
Funziona su Mac Intel e Apple Silicon con macOS 11 Big Sur o successivo.
ffmpeg è già incluso: non serve installare altro.

L'app verrà installata nella cartella Applicazioni.
TXT

productbuild --distribution build/distribution.xml \
  --resources build/resources \
  --package-path build \
  "build/VideoRepair-$VERSION.pkg"

rm -f build/VideoRepair-component.pkg
echo "✅ Installer: build/VideoRepair-$VERSION.pkg"
