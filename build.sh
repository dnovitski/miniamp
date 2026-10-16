#!/bin/zsh
# Builds "build/Miniamp.app" (used by CI). For development, `./build.sh --install` also copies it to ~/Applications.
# VERSION=1.2.3 stamps the version into Info.plist.
set -e
cd "${0:A:h}"
VERSION=${VERSION:-0.0.0-dev}
APP="build/Miniamp.app"

rm -rf build && mkdir build
swiftc -swift-version 5 -O -target arm64-apple-macos14.0 Sources/*.swift -o build/Miniamp
swift tools/icon.swift build/AppIcon.iconset
iconutil -c icns build/AppIcon.iconset -o build/AppIcon.icns

mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp Info.plist "$APP/Contents/"
/usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString $VERSION" \
  -c "Set :CFBundleVersion ${BUILD_NUMBER:-1}" "$APP/Contents/Info.plist"
cp build/Miniamp "$APP/Contents/MacOS/"
cp build/AppIcon.icns "$APP/Contents/Resources/"
codesign --force --sign - "$APP"
echo "Built: $APP ($VERSION)"

if [[ $1 == --install ]]; then
  pkill -x Miniamp || true
  rm -rf ~/Applications/"Miniamp.app"
  cp -R "$APP" ~/Applications/
  echo "Installed: ~/Applications/Miniamp.app"
fi
