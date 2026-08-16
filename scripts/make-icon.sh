#!/bin/bash
# Usage: make-icon.sh <icon-tool-binary> <out.icns>
# If Resources/AppIcon-1024.png exists it is used as the artwork (scaled + clipped to the macOS
# rounded-square shape); otherwise the built-in whale-on-blue default is rendered.
set -euo pipefail
TOOL="$1"; OUT="$2"; TMP="$(mktemp -d)"
SRC="$(dirname "$0")/../Resources/AppIcon-1024.png"
if [ -f "$SRC" ]; then "$TOOL" "$TMP/icon_1024.png" "$SRC" >/dev/null; echo "icon: using Resources/AppIcon-1024.png"; else "$TOOL" "$TMP/icon_1024.png" >/dev/null; fi
mkdir -p "$TMP/AppIcon.iconset"
for s in 16 32 128 256 512; do
  sips -z $s $s "$TMP/icon_1024.png" --out "$TMP/AppIcon.iconset/icon_${s}x${s}.png" >/dev/null
  d=$((s*2)); sips -z $d $d "$TMP/icon_1024.png" --out "$TMP/AppIcon.iconset/icon_${s}x${s}@2x.png" >/dev/null
done
iconutil -c icns "$TMP/AppIcon.iconset" -o "$OUT"
rm -rf "$TMP"
echo "icon: $OUT"
