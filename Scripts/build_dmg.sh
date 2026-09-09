#!/bin/zsh
set -euo pipefail

SCRIPT_DIR=${0:A:h}
PROJECT_DIR=${SCRIPT_DIR:h}
APP_NAME=FeatherStats
DIST_DIR="$PROJECT_DIR/dist"
APP_DIR="$DIST_DIR/$APP_NAME.app"
CONTENTS_DIR="$APP_DIR/Contents"
ICONSET_DIR="$DIST_DIR/AppIcon.iconset"
STAGING_DIR="$DIST_DIR/dmg-root"

cd "$PROJECT_DIR"
swift build -c release --arch arm64

mkdir -p "$CONTENTS_DIR/MacOS" "$CONTENTS_DIR/Resources" "$ICONSET_DIR" "$STAGING_DIR"
cp ".build/arm64-apple-macosx/release/$APP_NAME" "$CONTENTS_DIR/MacOS/$APP_NAME"
cp "App/Info.plist" "$CONTENTS_DIR/Info.plist"

swift "Scripts/make_icon.swift" "$DIST_DIR/AppIcon-1024.png"
for pixels in 16 32 128 256 512; do
    sips -z "$pixels" "$pixels" "$DIST_DIR/AppIcon-1024.png" --out "$ICONSET_DIR/icon_${pixels}x${pixels}.png" >/dev/null
    double=$((pixels * 2))
    sips -z "$double" "$double" "$DIST_DIR/AppIcon-1024.png" --out "$ICONSET_DIR/icon_${pixels}x${pixels}@2x.png" >/dev/null
done
iconutil -c icns "$ICONSET_DIR" -o "$CONTENTS_DIR/Resources/AppIcon.icns"

codesign --force --deep --sign - "$APP_DIR"

rm -rf "$STAGING_DIR"
mkdir -p "$STAGING_DIR"
cp -R "$APP_DIR" "$STAGING_DIR/"
ln -s /Applications "$STAGING_DIR/Applications"

rm -f "$DIST_DIR/$APP_NAME.dmg"
hdiutil create -volname "$APP_NAME" -srcfolder "$STAGING_DIR" -ov -format UDZO "$DIST_DIR/$APP_NAME.dmg" >/dev/null

printf '%s\n' "$DIST_DIR/$APP_NAME.dmg"
