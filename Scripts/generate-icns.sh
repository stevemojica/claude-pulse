#!/bin/bash
# Generate AppIcon.icns from a 1024x1024 PNG source image.
# Usage: ./Scripts/generate-icns.sh path/to/icon-1024.png
#
# This creates AppIcon.iconset/ with all required sizes and then
# converts to AppIcon.icns using iconutil.

set -e

INPUT="${1:?Usage: $0 <path-to-1024x1024.png>}"
ICONSET="AppIcon.iconset"

if [ ! -f "$INPUT" ]; then
    echo "Error: File not found: $INPUT"
    exit 1
fi

rm -rf "$ICONSET"
mkdir "$ICONSET"

# Generate all required sizes
sips -z 16 16     "$INPUT" --out "$ICONSET/icon_16x16.png"      >/dev/null
sips -z 32 32     "$INPUT" --out "$ICONSET/icon_16x16@2x.png"   >/dev/null
sips -z 32 32     "$INPUT" --out "$ICONSET/icon_32x32.png"      >/dev/null
sips -z 64 64     "$INPUT" --out "$ICONSET/icon_32x32@2x.png"   >/dev/null
sips -z 128 128   "$INPUT" --out "$ICONSET/icon_128x128.png"    >/dev/null
sips -z 256 256   "$INPUT" --out "$ICONSET/icon_128x128@2x.png" >/dev/null
sips -z 256 256   "$INPUT" --out "$ICONSET/icon_256x256.png"    >/dev/null
sips -z 512 512   "$INPUT" --out "$ICONSET/icon_256x256@2x.png" >/dev/null
sips -z 512 512   "$INPUT" --out "$ICONSET/icon_512x512.png"    >/dev/null
sips -z 1024 1024 "$INPUT" --out "$ICONSET/icon_512x512@2x.png" >/dev/null

iconutil -c icns "$ICONSET" -o AppIcon.icns

echo "Generated AppIcon.icns successfully!"
echo "Icon set saved to $ICONSET/"
rm -rf "$ICONSET"
