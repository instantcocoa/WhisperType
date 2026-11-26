#!/usr/bin/env bash
#
# Writes a single-item Sparkle appcast for a release DMG, EdDSA-signing the DMG.
#
# Usage: SPARKLE_ED_PRIVATE_KEY=<key> ./scripts/make-appcast.sh <dmg> <version> <build> <out.xml>
#   needs Sparkle's `sign_update` on PATH or in $SPARKLE_BIN.
#
set -euo pipefail
DMG="$1"; VERSION="$2"; BUILD="$3"; OUT="$4"
REPO="${GITHUB_REPOSITORY:-instantcocoa/WhisperType}"
SIGN="${SPARKLE_BIN:-}${SPARKLE_BIN:+/}sign_update"

KEYFILE="$(mktemp)"; trap 'rm -f "$KEYFILE"' EXIT
printf '%s' "$SPARKLE_ED_PRIVATE_KEY" > "$KEYFILE"
# Prints: sparkle:edSignature="…" length="…"
ATTRS="$("$SIGN" --ed-key-file "$KEYFILE" "$DMG")"
URL="https://github.com/$REPO/releases/download/v$VERSION/$(basename "$DMG")"

cat > "$OUT" <<XML
<?xml version="1.0" encoding="utf-8"?>
<rss version="2.0" xmlns:sparkle="http://www.andymatuschak.org/xml-namespaces/sparkle">
  <channel>
    <title>WhisperType</title>
    <item>
      <title>Version $VERSION</title>
      <sparkle:version>$BUILD</sparkle:version>
      <sparkle:shortVersionString>$VERSION</sparkle:shortVersionString>
      <sparkle:minimumSystemVersion>13.0</sparkle:minimumSystemVersion>
      <sparkle:releaseNotesLink>https://github.com/$REPO/releases/tag/v$VERSION</sparkle:releaseNotesLink>
      <enclosure url="$URL" type="application/x-apple-diskimage" $ATTRS/>
    </item>
  </channel>
</rss>
XML
echo "==> Wrote $OUT"
