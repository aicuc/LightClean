#!/bin/zsh
set -euo pipefail
cd "${0:A:h}/.."
swift build -c release
APP="$PWD/dist/轻舟清理.app"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
BIN_DIR="$(swift build -c release --show-bin-path)"
cp "$BIN_DIR/LightClean" "$APP/Contents/MacOS/LightClean"
cat > "$APP/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleExecutable</key><string>LightClean</string>
<key>CFBundleIdentifier</key><string>local.lightclean.mac</string>
<key>CFBundleName</key><string>轻舟清理</string>
<key>CFBundleDisplayName</key><string>轻舟清理</string>
<key>CFBundlePackageType</key><string>APPL</string>
<key>CFBundleShortVersionString</key><string>1.2.0</string>
<key>CFBundleVersion</key><string>3</string>
<key>LSMinimumSystemVersion</key><string>14.0</string>
<key>NSHighResolutionCapable</key><true/>
<key>NSPrincipalClass</key><string>NSApplication</string>
</dict></plist>
PLIST
ICONSET="$PWD/dist/AppIcon.iconset"
mkdir -p "$ICONSET"
swift scripts/icon.swift "$PWD/dist/icon.png"
for size in 16 32 128 256 512; do
    sips -z "$size" "$size" "$PWD/dist/icon.png" --out "$ICONSET/icon_${size}x${size}.png" >/dev/null
    double=$((size * 2))
    sips -z "$double" "$double" "$PWD/dist/icon.png" --out "$ICONSET/icon_${size}x${size}@2x.png" >/dev/null
done
iconutil -c icns "$ICONSET" -o "$APP/Contents/Resources/AppIcon.icns"
/usr/libexec/PlistBuddy -c "Add :CFBundleIconFile string AppIcon" "$APP/Contents/Info.plist"
codesign --force --deep --sign - "$APP"
echo "$APP"
