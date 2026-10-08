#!/bin/sh
# Render the brand SVGs in assets/brand/ to the PNGs the app ships with:
# iOS app icon (light / dark / tinted), Android icons, and the
# wordmark the Flutter splash animates. Needs Google Chrome + ImageMagick.
# Run from apps/mobile: sh tool/brand.sh
set -e
CHROME="${CHROME:-/Applications/Google Chrome.app/Contents/MacOS/Google Chrome}"
SRC=assets/brand
TMP=$(mktemp -d)
IOS=ios/Runner/Assets.xcassets
RES=android/app/src/main/res

# render <svg> <width> <height> <out.png>: transparent background.
render() {
  cat > "$TMP/r.html" <<HTML
<!doctype html><meta charset="utf-8"><style>html,body{margin:0;background:transparent}img{display:block;width:$2px;height:$3px}</style><img src="file://$PWD/$SRC/$1">
HTML
  # Headless windows come out a bit short: ask for more, crop to size.
  "$CHROME" --headless=new --disable-gpu --hide-scrollbars --force-device-scale-factor=1 \
    --default-background-color=00000000 --window-size="$2,$(($3 + 200))" \
    --screenshot="$TMP/shot.png" "file://$TMP/r.html" >/dev/null 2>&1
  magick "$TMP/shot.png" -crop "$2x$3+0+0" +repage "$4"
}

# iOS app icon: single 1024 size, light is flattened (the store rejects alpha).
ICON="$IOS/AppIcon.appiconset"
render icon-light.svg 1024 1024 "$TMP/light.png"
magick "$TMP/light.png" -background '#FFD84D' -alpha remove -alpha off "$ICON/AppIcon-1024.png"
render icon-dark.svg 1024 1024 "$ICON/AppIcon-1024-dark.png"
render icon-tinted.svg 1024 1024 "$TMP/tinted.png"
magick "$TMP/tinted.png" -background black -alpha remove -alpha off "$ICON/AppIcon-1024-tinted.png"
# Luma Dev (flavor dev): the tinted variant, so it never passes for Luma.
cp "$ICON/AppIcon-1024-tinted.png" "$IOS/AppIcon-dev.appiconset/AppIcon-dev-1024.png"

# Android: legacy square icons + the adaptive foreground (432 = 108dp @4x).
for d in mdpi:48 hdpi:72 xhdpi:96 xxhdpi:144 xxxhdpi:192; do
  magick "$ICON/AppIcon-1024.png" -resize "${d#*:}x${d#*:}" "$RES/mipmap-${d%%:*}/ic_launcher.png"
done
render icon-android-fg.svg 432 432 "$RES/mipmap-xxxhdpi/ic_launcher_foreground.png"

# Wordmark for the Flutter splash: black alpha, tinted at runtime (3x of 103.6).
render wordmark.svg 622 223 assets/brand/wordmark.png
rm -rf "$TMP"
