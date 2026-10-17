#!/bin/bash
# Builds Graffle in release mode and wraps it in build/Graffle.app
set -euo pipefail
cd "$(dirname "$0")/.."

swift build -c release
BIN="$(swift build -c release --show-bin-path)/Graffle"

APP="build/Graffle.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN" "$APP/Contents/MacOS/Graffle"
cp Assets/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"

cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleName</key><string>Graffle</string>
  <key>CFBundleDisplayName</key><string>Graffle</string>
  <key>CFBundleIdentifier</key><string>mx.graffle.app</string>
  <key>CFBundleExecutable</key><string>Graffle</string>
  <key>CFBundleIconFile</key><string>AppIcon</string>
  <key>NSHumanReadableCopyright</key><string>Copyright © 2026 EVM. All rights reserved.</string>
  <key>LSApplicationCategoryType</key><string>public.app-category.graphics-design</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleShortVersionString</key><string>0.1</string>
  <key>CFBundleVersion</key><string>1</string>
  <key>LSMinimumSystemVersion</key><string>13.0</string>
  <key>NSHighResolutionCapable</key><true/>
  <key>NSPrincipalClass</key><string>NSApplication</string>
  <key>CFBundleDocumentTypes</key>
  <array>
    <dict>
      <key>CFBundleTypeName</key><string>Graffle Diagram</string>
      <key>CFBundleTypeRole</key><string>Editor</string>
      <key>LSItemContentTypes</key><array><string>mx.graffle.diagram</string></array>
      <key>CFBundleTypeExtensions</key><array><string>graf</string></array>
      <key>NSDocumentClass</key><string>GraffleDocument</string>
      <key>LSHandlerRank</key><string>Owner</string>
    </dict>
    <dict>
      <key>CFBundleTypeName</key><string>SVG Image</string>
      <key>CFBundleTypeRole</key><string>Viewer</string>
      <key>LSItemContentTypes</key><array><string>public.svg-image</string></array>
      <key>CFBundleTypeExtensions</key><array><string>svg</string></array>
      <key>NSDocumentClass</key><string>GraffleDocument</string>
      <key>LSHandlerRank</key><string>Alternate</string>
    </dict>
  </array>
  <key>UTExportedTypeDeclarations</key>
  <array>
    <dict>
      <key>UTTypeIdentifier</key><string>mx.graffle.diagram</string>
      <key>UTTypeDescription</key><string>Graffle Diagram</string>
      <key>UTTypeConformsTo</key><array><string>public.json</string></array>
      <key>UTTypeTagSpecification</key>
      <dict>
        <key>public.filename-extension</key><array><string>graf</string></array>
        <key>public.mime-type</key><string>application/x-graffle+json</string>
      </dict>
    </dict>
  </array>
</dict>
</plist>
PLIST

codesign --force --sign - "$APP" >/dev/null 2>&1 || true
touch "$APP"   # nudges Finder and the Dock to refresh the icon
echo "Built $APP"
