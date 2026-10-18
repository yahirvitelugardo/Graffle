#!/bin/bash
# Builds the Quick Look preview extension and installs it into an app bundle:
#   scripts/build-quicklook.sh build/Graffle.app
# The extension reuses the app's own drawing code, so it is compiled from those sources directly.
set -euo pipefail
cd "$(dirname "$0")/.."

APP="${1:?usage: build-quicklook.sh path/to/Graffle.app}"
VERSION="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$APP/Contents/Info.plist")"
BUILD="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' "$APP/Contents/Info.plist")"
EXT="$APP/Contents/PlugIns/GraffleQuickLook.appex"

rm -rf "$EXT"
mkdir -p "$EXT/Contents/MacOS"

# Only the model and drawing code: no windows, inspector or menus.
SOURCES=(
  Sources/Graffle/Model.swift
  Sources/Graffle/Render.swift
  Sources/Graffle/PathEditing.swift
  Sources/Graffle/StyleLibrary.swift
  Sources/Graffle/SVGImport.swift
  Sources/Graffle/SVGExport.swift
  Sources/Graffle/CanvasView.swift
  Sources/Graffle/DiagramPreview.swift
  QuickLookExtension/PreviewProvider.swift
)

# -e _NSExtensionMain makes this an app extension (it starts the extension machinery instead of main()).
swiftc -O -wmo -swift-version 5 \
  -target "$(uname -m)-apple-macos13.0" \
  -parse-as-library -application-extension \
  -module-name GraffleQuickLook \
  -framework AppKit -framework QuickLookUI -framework UniformTypeIdentifiers \
  -Xlinker -e -Xlinker _NSExtensionMain \
  -o "$EXT/Contents/MacOS/GraffleQuickLook" \
  "${SOURCES[@]}" 2>&1 | grep -vE "warning|^\s|^\[#|note:" || true
[ -x "$EXT/Contents/MacOS/GraffleQuickLook" ] || { echo "Quick Look extension failed to build" >&2; exit 1; }

sed -e "s/__VERSION__/$VERSION/" -e "s/__BUILD__/$BUILD/" QuickLookExtension/Info.plist > "$EXT/Contents/Info.plist"

# Extensions must be signed, with the sandbox entitlement, before the app that contains them is.
codesign --force --sign - --entitlements QuickLookExtension/QuickLook.entitlements "$EXT" >/dev/null
echo "Built $EXT"
