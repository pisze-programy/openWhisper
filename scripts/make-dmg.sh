#!/bin/bash
# Rebuild OpenWhisper (macOS) as Release and generate an installable DMG.
# Usage: ./scripts/make-dmg.sh
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SCHEME="openWhisperMac"
APP_NAME="OpenWhisper"
OUT="$HOME/Desktop/${APP_NAME}.dmg"
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

echo "==> Staging…"
mkdir -p "$TMP/stage" "$TMP/volume_icon.iconset"
cp -R "$APP" "$TMP/stage/"
cp "$ROOT/openWhisperMac/Assets.xcassets/AppIcon.appiconset/AppIcon.png" "$TMP/icon.png"

# Volume icon (standard iconutil iconset layout)
sips -z 16 16 "$TMP/icon.png" --out "$TMP/volume_icon.iconset/icon_16x16.png" >/dev/null 2>&1
sips -z 32 32 "$TMP/icon.png" --out "$TMP/volume_icon.iconset/icon_16x16@2x.png" >/dev/null 2>&1
sips -z 32 32 "$TMP/icon.png" --out "$TMP/volume_icon.iconset/icon_32x32.png" >/dev/null 2>&1
sips -z 64 64 "$TMP/icon.png" --out "$TMP/volume_icon.iconset/icon_32x32@2x.png" >/dev/null 2>&1
sips -z 128 128 "$TMP/icon.png" --out "$TMP/volume_icon.iconset/icon_128x128.png" >/dev/null 2>&1
sips -z 256 256 "$TMP/icon.png" --out "$TMP/volume_icon.iconset/icon_128x128@2x.png" >/dev/null 2>&1
sips -z 256 256 "$TMP/icon.png" --out "$TMP/volume_icon.iconset/icon_256x256.png" >/dev/null 2>&1
sips -z 512 512 "$TMP/icon.png" --out "$TMP/volume_icon.iconset/icon_256x256@2x.png" >/dev/null 2>&1
sips -z 512 512 "$TMP/icon.png" --out "$TMP/volume_icon.iconset/icon_512x512.png" >/dev/null 2>&1
sips -z 1024 1024 "$TMP/icon.png" --out "$TMP/volume_icon.iconset/icon_512x512@2x.png" >/dev/null 2>&1
iconutil -c icns "$TMP/volume_icon.iconset" -o "$TMP/volume_icon.icns"

# Background (gradient + icon + arrow)
python3 - "$TMP" <<'PYEOF'
import sys
from PIL import Image, ImageDraw, ImageFont
TMP = sys.argv[1]
W, H = 660, 400
img = Image.new("RGB", (W, H))
px = img.load()
top, bot = (45, 52, 66), (20, 22, 30)
for y in range(H):
    t = y / H
    r = int(top[0] + (bot[0]-top[0])*t); g = int(top[1] + (bot[1]-top[1])*t); b = int(top[2] + (bot[2]-top[2])*t)
    for x in range(0, W, 4):
        for dx in range(4):
            px[x+dx, y] = (r, g, b)
def font(size, bold=False):
    try: return ImageFont.truetype("/System/Library/Fonts/SFNS-Bold.ttf" if bold else "/System/Library/Fonts/SFNS.ttf", size)
    except: return ImageFont.load_default()
icon = Image.open(f"{TMP}/icon.png").convert("RGBA").resize((128, 128), Image.LANCZOS)
img.paste(icon, (150, 120), icon)
d = ImageDraw.Draw(img)
t1, t2 = "Drag to Applications", "to install"
f1, f2 = font(34, True), font(22)
w1 = d.textlength(t1, font=f1); w2 = d.textlength(t2, font=f2)
d.text((330, 140), t1, fill=(255,255,255), font=f1)
d.text((330 + (w1-w2)//2, 190), t2, fill=(190,196,208), font=f2)
ax, ay = 470, 260
d.line([(ax, ay), (ax, ay+40)], fill=(140,150,170), width=5)
d.polygon([(ax-10, ay+38), (ax+10, ay+38), (ax, ay+52)], fill=(140,150,170))
at = "Applications"; fa = font(16); wa = d.textlength(at, font=fa)
d.text((ax - wa//2, ay+56), at, fill=(150,160,175), font=fa)
img.save(f"{TMP}/background.png")
print("background ok")
PYEOF

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
background = "$TMP/background.png"
icon_locations = {"$APP_NAME.app": (200, 200), "Applications": (450, 200)}
icon = "$TMP/volume_icon.icns"
PYEOF

cd "$TMP/stage"
dmgbuild -s ../settings.py "$APP_NAME" "$OUT" 2>&1 || dmgbuild -s ../settings.py "$APP_NAME" "$TMP/out.dmg"

echo "==> DMG: $OUT"
ls -lh "$OUT"
