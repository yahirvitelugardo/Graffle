#!/bin/bash
# Regenerates Assets/AppIcon.icns from Assets/AppIcon-source.jpg.
set -euo pipefail
cd "$(dirname "$0")/.."
swift scripts/make-icon.swift "$PWD"
iconutil -c icns Assets/AppIcon.iconset -o Assets/AppIcon.icns
cp Assets/AppIcon.iconset/icon_512x512@2x.png Assets/AppIcon-preview.png
rm -rf Assets/AppIcon.iconset
echo "Built Assets/AppIcon.icns"
