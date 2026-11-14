#!/bin/zsh
set -euo pipefail
PROJECT_ROOT="$(cd -- "$(dirname -- "$0")/.." && pwd)"
cd "$PROJECT_ROOT"
swift build --configuration release
BIN_DIR="$(swift build --configuration release --show-bin-path)"
APP_PATH="${1:-$PROJECT_ROOT/dist/截录暂存.app}"
APP_IDENTIFIER="local.jackson.light-recorder"
if [[ "${2:-}" == "--trial" ]]; then
    APP_IDENTIFIER="local.jackson.light-recorder.floating-trial"
fi
mkdir -p "$APP_PATH/Contents/MacOS" "$APP_PATH/Contents/Resources"
cp "$BIN_DIR/LightRecorder" "$APP_PATH/Contents/MacOS/LightRecorder"
cp Resources/Info.plist "$APP_PATH/Contents/Info.plist"
if [[ "${2:-}" == "--trial" ]]; then
    /usr/libexec/PlistBuddy -c "Set CFBundleIdentifier $APP_IDENTIFIER" \
        -c 'Set CFBundleName 轻录试用' -c 'Set CFBundleDisplayName 轻录试用' "$APP_PATH/Contents/Info.plist"
fi
swift scripts/make-icon.swift .build/AppIcon.iconset
iconutil --convert icns .build/AppIcon.iconset --output "$APP_PATH/Contents/Resources/AppIcon.icns"
codesign --force --sign - --identifier "$APP_IDENTIFIER" "$APP_PATH"
codesign --verify --deep --strict "$APP_PATH"
printf '\n应用已生成：%s\n' "$APP_PATH"
