#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
if [[ ! -f native/Resources/dictionary.sqlite ]]; then
 python3 scripts/build-dictionary.py
fi
export CLANG_MODULE_CACHE_PATH="$PWD/native/.build/module-cache"
swift build --package-path native --disable-sandbox --cache-path "$PWD/native/.build/cache" -c release
APP="$PWD/native/build/PressTrans.app"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp native/.build/release/PressTrans "$APP/Contents/MacOS/PressTrans"
cp native/Resources/* "$APP/Contents/Resources/"
cat > "$APP/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleExecutable</key><string>PressTrans</string>
<key>CFBundleIdentifier</key><string>com.presstrans.mac</string>
<key>CFBundleName</key><string>PressTrans</string>
<key>CFBundleVersion</key><string>1</string>
<key>CFBundleShortVersionString</key><string>0.2.0</string>
<key>CFBundlePackageType</key><string>APPL</string>
<key>LSUIElement</key><true/>
<key>LSMinimumSystemVersion</key><string>14.0</string>
<key>NSHighResolutionCapable</key><true/>
</dict></plist>
PLIST
# Only the path to the ignored local config is embedded in development builds.
if [[ "${PRESSTRANS_DEV_CONFIG:-0}" == "1" ]]; then
 /usr/libexec/PlistBuddy -c "Add :PressTransDevelopmentConfig string $PWD/.env" "$APP/Contents/Info.plist"
fi
codesign --force --sign - "$APP"
printf 'Built: %s\n' "$APP"
