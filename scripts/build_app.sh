#!/usr/bin/env bash
# Builds build/SlokaWords.app from the Swift package in app/.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
APP="$ROOT/build/SlokaWords.app"

# The Command Line Tools toolchain can't start the new SwiftPM build system,
# so fall back to the native one when it fails.
SWIFT_FLAGS=(-c release --package-path "$ROOT/app")
if ! swift build "${SWIFT_FLAGS[@]}" 2>/dev/null; then
    SWIFT_FLAGS+=(--build-system native)
    swift build "${SWIFT_FLAGS[@]}"
fi
BIN="$(swift build "${SWIFT_FLAGS[@]}" --show-bin-path)"

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN/SlokaWords" "$APP/Contents/MacOS/SlokaWords"
cp "$ROOT/app/Sources/SlokaWords/Resources/words.json" "$APP/Contents/Resources/words.json"

cat > "$APP/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleName</key><string>Sloka Words</string>
    <key>CFBundleDisplayName</key><string>Sloka Words</string>
    <key>CFBundleIdentifier</key><string>com.venkatacrc.slokawords</string>
    <key>CFBundleExecutable</key><string>SlokaWords</string>
    <key>CFBundlePackageType</key><string>APPL</string>
    <key>CFBundleShortVersionString</key><string>0.1.0</string>
    <key>CFBundleVersion</key><string>1</string>
    <key>LSMinimumSystemVersion</key><string>14.0</string>
    <key>LSApplicationCategoryType</key><string>public.app-category.education</string>
    <key>NSHighResolutionCapable</key><true/>
</dict>
</plist>
PLIST

codesign --force --sign - "$APP" >/dev/null 2>&1 || true
echo "Built $APP"
