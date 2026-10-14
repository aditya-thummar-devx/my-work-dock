#!/usr/bin/env bash
# Build Release and package build/MyWorkDock-<version>.dmg: app + Applications shortcut, Peek icon on the mounted volume.
#
#   scripts/make-dmg.sh
#
# Ad-hoc signed, so it only opens cleanly on this Mac. Other Macs need Developer ID signing + notarization.
set -euo pipefail
cd "$(dirname "$0")/.."

xcodebuild -project MyWorkDock.xcodeproj -scheme MyWorkDock -configuration Release -derivedDataPath build build -quiet
APP=build/Build/Products/Release/MyWorkDock.app
VER=$(/usr/libexec/PlistBuddy -c "Print :CFBundleShortVersionString" "$APP/Contents/Info.plist")
DMG=build/MyWorkDock-$VER.dmg
RW=build/rw.dmg
SRC=build/dmg-src
ICONSET=build/AppIcon.iconset

rm -rf "$DMG" "$RW" "$SRC" "$ICONSET"
mkdir -p "$SRC" "$ICONSET"
# The catalog PNGs already use iconset names, so the volume icon is built from them (no separate .icns to keep).
cp MyWorkDock/Resources/Assets.xcassets/AppIcon.appiconset/*.png "$ICONSET"
iconutil -c icns "$ICONSET" -o "$SRC/.VolumeIcon.icns"
cp -R "$APP" "$SRC/"
ln -s /Applications "$SRC/Applications"

hdiutil create -quiet -volname MyWorkDock -srcfolder "$SRC" -format UDRW "$RW"
MNT=$(hdiutil attach "$RW" -nobrowse | awk -F'\t' '/\/Volumes\// {print $NF}')
SetFile -a C "$MNT"   # custom-icon flag: Finder uses .VolumeIcon.icns
hdiutil detach -quiet "$MNT"
hdiutil convert -quiet "$RW" -format UDZO -o "$DMG"
rm -rf "$RW" "$SRC" "$ICONSET"
echo "$DMG"
