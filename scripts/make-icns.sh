#!/usr/bin/env bash
# Regenerates assets/AppIcon.icns from scripts/make-icon.swift.
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
A="$ROOT/assets"
swift "$ROOT/scripts/make-icon.swift" "$A"
SET="$(mktemp -d)/AppIcon.iconset"; mkdir -p "$SET"
for s in 16 32 128 256 512; do
    sips -z $s $s           "$A/AppIcon-1024.png" --out "$SET/icon_${s}x${s}.png"    >/dev/null
    sips -z $((s*2)) $((s*2)) "$A/AppIcon-1024.png" --out "$SET/icon_${s}x${s}@2x.png" >/dev/null
done
iconutil -c icns "$SET" -o "$A/AppIcon.icns"
echo "==> $A/AppIcon.icns"
