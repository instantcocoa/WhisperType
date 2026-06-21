#!/usr/bin/env bash
#
# Builds WhisperType with Swift Package Manager and assembles a signed
# `build/WhisperType.app` bundle around the resulting executable.
#
# WhisperKit is linked in-process. By default the Whisper CoreML model + matching
# tokenizer are downloaded at build time (scripts/fetch-model.sh) and bundled into
# the .app, so the app runs fully offline from first launch. Set
# WHISPERTYPE_BUNDLE_MODEL=0 to skip bundling and let WhisperKit download the
# model on demand on first run instead (smaller .app, needs network once).
#
# Usage:
#   ./scripts/build-app.sh [debug|release] [output-app-path]
# Defaults: config=release, output=build/WhisperType.app
# (The CMake build calls this with its own binary dir as the output path.)
#
set -euo pipefail

CONFIG="${1:-release}"
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APP_NAME="WhisperType"
BUNDLE_ID="com.whispertype.app"
APP="${2:-$ROOT/build/$APP_NAME.app}"
MODEL_CACHE="$ROOT/build/model-cache"
MODEL_VARIANT="openai_whisper-base.en"
BUNDLE_MODEL="${WHISPERTYPE_BUNDLE_MODEL:-1}"

cd "$ROOT"

echo "==> Building ($CONFIG) with Swift Package Manager…"
swift build -c "$CONFIG"
BIN_DIR="$(swift build -c "$CONFIG" --show-bin-path)"

echo "==> Assembling $APP"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"

cp "$BIN_DIR/$APP_NAME" "$APP/Contents/MacOS/$APP_NAME"
cp "$ROOT/Info.plist"   "$APP/Contents/Info.plist"

# Bundle the model + tokenizer so the app works offline from first launch.
if [ "$BUNDLE_MODEL" != "0" ]; then
    "$ROOT/scripts/fetch-model.sh" "$MODEL_CACHE" "$MODEL_VARIANT"
    echo "==> Bundling model into Resources/models/"
    mkdir -p "$APP/Contents/Resources/models"
    cp -R "$MODEL_CACHE/$MODEL_VARIANT"           "$APP/Contents/Resources/models/"
    cp -R "$MODEL_CACHE/${MODEL_VARIANT}-tokenizer" "$APP/Contents/Resources/models/"
else
    echo "==> WHISPERTYPE_BUNDLE_MODEL=0 — model will be downloaded on demand at runtime."
fi

# Copy any SwiftPM resource bundles (e.g. WhisperKit / its deps) so Bundle.module
# resolves at runtime. Harmless if there are none.
shopt -s nullglob
for b in "$BIN_DIR"/*.bundle; do
    echo "    bundling resource: $(basename "$b")"
    cp -R "$b" "$APP/Contents/Resources/"
done
shopt -u nullglob

# ----------------------------------------------------------------------------
#  Code signing
#
#  A *stable* identity (not ad-hoc) matters: macOS keys the Accessibility (TCC)
#  grant on the signature, so an ad-hoc binary whose hash changes every build
#  forces re-approval each time. Use the dedicated self-signed identity if it
#  exists (see scripts/create-signing-cert.sh); otherwise fall back to ad-hoc.
# ----------------------------------------------------------------------------
IDENTITY="WhisperType Self-Signed"
if ! security find-identity -p codesigning 2>/dev/null | grep -q "$IDENTITY"; then
    echo "==> Stable signing identity not found — using ad-hoc signing."
    echo "    (Accessibility permission will reset on each rebuild; run"
    echo "     ./scripts/create-signing-cert.sh to create a stable identity.)"
    IDENTITY="-"
else
    echo "==> Signing with stable identity '$IDENTITY'"
fi

# Sign nested resource bundles first, then seal the whole app.
shopt -s nullglob
for b in "$APP/Contents/Resources"/*.bundle; do
    codesign --force --sign "$IDENTITY" "$b"
done
shopt -u nullglob
codesign --force --sign "$IDENTITY" --identifier "$BUNDLE_ID" "$APP"

echo "==> Done: $APP"
echo "    Launch with:  open \"$APP\""
