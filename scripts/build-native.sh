#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
if [[ ! -f native/Resources/dictionary.sqlite ]]; then
 python3 scripts/build-dictionary.py
fi
export CLANG_MODULE_CACHE_PATH="$PWD/native/.build/module-cache"
if [[ ! -f native/Resources/PressTrans.icns || scripts/make-native-icon.swift -nt native/Resources/PressTrans.icns ]]; then
 swift scripts/make-native-icon.swift native/.build/PressTrans.iconset
 iconutil -c icns native/.build/PressTrans.iconset -o native/Resources/PressTrans.icns
fi
if [[ "${PRESSTRANS_CAPTURE_ACCEPTANCE:-0}" == 1 ]]; then
 swift build --package-path native --disable-sandbox --cache-path "$PWD/native/.build/cache" -c release -Xswiftc -D -Xswiftc CAPTURE_ACCEPTANCE
else
 swift build --package-path native --disable-sandbox --cache-path "$PWD/native/.build/cache" -c release
fi
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
<key>CFBundleVersion</key><string>2</string>
<key>CFBundleIconFile</key><string>PressTrans</string>
<key>CFBundleShortVersionString</key><string>0.2.0</string>
<key>CFBundlePackageType</key><string>APPL</string>
<key>LSUIElement</key><true/>
<key>LSMinimumSystemVersion</key><string>14.0</string>
<key>NSHighResolutionCapable</key><true/>
</dict></plist>
PLIST
python3 scripts/sign-native.py "$APP"
printf 'Built: %s\n' "$APP"
