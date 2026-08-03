#!/bin/bash
# Rebuild OpenWhisper (macOS) as Release and produce a plain installable DMG
# (app + Applications symlink) in release/ — ready to upload to GitHub Releases.
# Usage: ./scripts/make-dmg.sh
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SCHEME="openWhisperMac"
APP_NAME="OpenWhisper"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

echo "==> Building Release…"
xcodebuild -project "$ROOT/openWhisper.xcodeproj" \
  -scheme "$SCHEME" -configuration Release \
  -destination 'platform=macOS' \
  -derivedDataPath "$TMP/derived" \
  build | xcpretty -s 2>/dev/null || \
  xcodebuild -project "$ROOT/openWhisper.xcodeproj" \
  -scheme "$SCHEME" -configuration Release \
  -destination 'platform=macOS' \
  -derivedDataPath "$TMP/derived" \
  build >/dev/null

APP="$TMP/derived/Build/Products/Release/${APP_NAME}.app"
[ -d "$APP" ] || { echo "ERROR: $APP not found"; exit 1; }

VERSION="$(/usr/libexec/PlistBuddy -c 'Print CFBundleShortVersionString' "$APP/Contents/Info.plist")"
RELEASE_DIR="$ROOT/release"
OUT="$RELEASE_DIR/${APP_NAME}-${VERSION}.dmg"
mkdir -p "$RELEASE_DIR"
rm -f "$OUT"

echo "==> Staging…"
mkdir -p "$TMP/stage"
cp -R "$APP" "$TMP/stage/"

echo "==> Building DMG…"
cat > "$TMP/settings.py" <<PYEOF
application = "$APP_NAME.app"
files = ["$APP_NAME.app"]
symlinks = {"Applications": "/Applications"}
volume_name = "$APP_NAME"
format = "UDBZ"
size = "100M"
window_rect = ((200, 120), (660, 400))
icon_size = 96
icon_locations = {"$APP_NAME.app": (200, 200), "Applications": (450, 200)}
PYEOF

cd "$TMP/stage"
dmgbuild -s ../settings.py "$APP_NAME" "$OUT"

echo "==> DMG: $OUT"
ls -lh "$OUT"
