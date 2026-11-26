#!/usr/bin/env bash
#
# Packages WhisperType.app into a drag-to-install .dmg.
#
# Usage: ./scripts/make-dmg.sh [path/to/WhisperType.app] [output.dmg]
# Defaults: build/WhisperType.app → build/WhisperType.dmg
# If SIGN_IDENTITY is set the dmg itself is signed too.
#
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APP="${1:-$ROOT/build/WhisperType.app}"
DMG="${2:-$ROOT/build/WhisperType.dmg}"
VOLNAME="WhisperType"

[ -d "$APP" ] || { echo "error: $APP not found (run scripts/build-app.sh first)" >&2; exit 1; }

STAGE="$(mktemp -d)"
trap 'rm -rf "$STAGE"' EXIT
cp -R "$APP" "$STAGE/"
ln -s /Applications "$STAGE/Applications"

rm -f "$DMG"
echo "==> Creating $DMG"
hdiutil create -volname "$VOLNAME" -srcfolder "$STAGE" -ov -format UDZO -fs HFS+ "$DMG" >/dev/null

if [ -n "${SIGN_IDENTITY:-}" ]; then
    codesign --force --timestamp --sign "$SIGN_IDENTITY" "$DMG"
fi
echo "==> Done: $DMG ($(du -h "$DMG" | cut -f1))"
