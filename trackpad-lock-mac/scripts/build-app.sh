#!/bin/zsh
set -euo pipefail
cd -- "${0:A:h:h}"
app="${1:-$PWD/dist/触控板锁.app}"
mkdir -p "$app/Contents/MacOS" "$app/Contents/Resources" .build
cp Resources/Info.plist "$app/Contents/Info.plist"
xcrun clang -O2 -Wall -Wextra -Werror -mmacosx-version-min=13.0 Sources/TrackpadGuard.c -o "$app/Contents/MacOS/TrackpadGuard" -framework CoreFoundation -framework IOKit
MACOSX_DEPLOYMENT_TARGET=13.0 xcrun swiftc -O -warnings-as-errors Sources/TrackpadControl.swift Sources/KeyboardControl.swift Sources/main.swift -o "$app/Contents/MacOS/TrackpadLock"
xcrun swift scripts/make-icon.swift .build/AppIcon.iconset
iconutil -c icns .build/AppIcon.iconset -o "$app/Contents/Resources/AppIcon.icns"
codesign --force --sign - --identifier local.jackson.trackpad-lock.guard "$app/Contents/MacOS/TrackpadGuard"
codesign --force --sign - --identifier local.jackson.trackpad-lock "$app"
codesign --verify --deep --strict "$app"
printf '%s\n' "$app"
