#!/bin/zsh
# Builds build/MelonBerry.app.  Pass --install to also copy it to /Applications and launch it.
set -euo pipefail
cd "${0:A:h}"

swift build -c release

app=build/MelonBerry.app
rm -rf $app
mkdir -p $app/Contents/MacOS $app/Contents/Resources
cp .build/release/MelonBerry $app/Contents/MacOS/
cp Support/Info.plist $app/Contents/

# icon: render once at 1024px, then downsample into an .icns
iconset=build/AppIcon.iconset
rm -rf $iconset && mkdir -p $iconset
swift Support/make-icon.swift build/icon-1024.png 2>/dev/null
for s in 16 32 128 256 512; do
  sips -z $s $s build/icon-1024.png --out $iconset/icon_${s}x${s}.png >/dev/null
  sips -z $((s*2)) $((s*2)) build/icon-1024.png --out $iconset/icon_${s}x${s}@2x.png >/dev/null
done
iconutil -c icns $iconset -o $app/Contents/Resources/AppIcon.icns

codesign --force --sign - $app
echo "built $app"

if [[ "${1:-}" == "--install" ]]; then
  pkill -x MelonBerry 2>/dev/null || true
  rm -rf /Applications/MelonBerry.app
  cp -R $app /Applications/
  open /Applications/MelonBerry.app
  echo "installed to /Applications and launched"
fi
