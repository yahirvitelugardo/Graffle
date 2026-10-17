#!/bin/bash
# Builds the installer: build/Graffle-<version>.dmg
#
# The disk image opens to a window with Graffle.app and a shortcut to /Applications on a custom background,
# so installing is a single drag. The Finder layout is set through AppleScript; if macOS refuses that
# (Automation permission), the DMG is still produced, just without the custom window layout.
set -euo pipefail
cd "$(dirname "$0")/.."

VOL="Graffle"
./scripts/bundle.sh >/dev/null
APP="build/Graffle.app"
VERSION="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$APP/Contents/Info.plist")"
FINAL="build/Graffle-$VERSION.dmg"
RW="build/Graffle-rw.dmg"
STAGE="build/dmg-staging"

echo "Staging…"
rm -rf "$STAGE" "$RW" "$FINAL"
mkdir -p "$STAGE/.background"
cp -R "$APP" "$STAGE/Graffle.app"
ln -s /Applications "$STAGE/Applications"
[ -f Assets/dmg-background.png ] || swift scripts/make-dmg-background.swift "$PWD"
cp Assets/dmg-background.png "$STAGE/.background/background.png"

# Make sure no earlier image is still mounted under the same name.
hdiutil detach "/Volumes/$VOL" -force >/dev/null 2>&1 || true

echo "Creating the disk image…"
SIZE_MB=$(( $(du -sm "$STAGE" | cut -f1) + 20 ))
hdiutil create -srcfolder "$STAGE" -volname "$VOL" -fs HFS+ -format UDRW -size "${SIZE_MB}m" -ov "$RW" >/dev/null
hdiutil attach "$RW" -readwrite -noverify -noautoopen >/dev/null
MNT="/Volumes/$VOL"

echo "Laying out the window…"
if osascript <<OSA >/dev/null 2>&1
tell application "Finder"
  tell disk "$VOL"
    open
    set current view of container window to icon view
    set toolbar visible of container window to false
    set statusbar visible of container window to false
    set the bounds of container window to {200, 120, 860, 548}
    set opts to the icon view options of container window
    set arrangement of opts to not arranged
    set icon size of opts to 104
    set text size of opts to 13
    set background picture of opts to file ".background:background.png"
    set position of item "Graffle.app" of container window to {170, 200}
    set position of item "Applications" of container window to {490, 200}
    update without registering applications
    delay 2
    close
  end tell
end tell
OSA
then
  echo "  layout applied"
else
  echo "  Finder didn't allow the layout (grant Automation access to Finder for your terminal to get the custom window)"
fi

# The volume's own icon. It is added only after Finder has finished with the window: the layout step removes it
# if it is already there, and hdiutil drops it when building from a folder. Flagging the volume needs SetFile
# from the Command Line Tools; without it the icon is just not shown.
cp Assets/AppIcon.icns "$MNT/.VolumeIcon.icns"
SetFile -a C "$MNT" 2>/dev/null || echo "  (SetFile not available: the volume keeps the default icon)"

rm -rf "$MNT/.fseventsd" 2>/dev/null || true
sync
sleep 1
hdiutil detach "$MNT" >/dev/null 2>&1 || { sleep 2; hdiutil detach "$MNT" -force >/dev/null; }

echo "Compressing…"
hdiutil convert "$RW" -format UDZO -imagekey zlib-level=9 -o "$FINAL" >/dev/null
rm -rf "$RW" "$STAGE"

hdiutil verify "$FINAL" >/dev/null

# Mount the finished image read-only and make sure everything the installer window relies on is really there.
hdiutil attach "$FINAL" -readonly -noverify -noautoopen >/dev/null
MISSING=""
for f in "Graffle.app/Contents/MacOS/Graffle" "Applications" ".background/background.png" ".VolumeIcon.icns" ".DS_Store"; do
  [ -e "$MNT/$f" ] || [ -L "$MNT/$f" ] || MISSING="$MISSING $f"
done
codesign -v "$MNT/Graffle.app" 2>/dev/null || MISSING="$MISSING (valid app signature)"
hdiutil detach "$MNT" >/dev/null 2>&1 || true
if [ -n "$MISSING" ]; then echo "The DMG is missing:$MISSING" >&2; exit 1; fi
echo "Verified: app, Applications link, background, volume icon, window layout"
( cd build && shasum -a 256 "$(basename "$FINAL")" > "$(basename "$FINAL").sha256" )
echo "Built $FINAL ($(du -h "$FINAL" | cut -f1))"
cat "$FINAL.sha256"
