#!/usr/bin/env bash
#
# Creates a self-signed code-signing certificate ("WhisperType Self-Signed")
# in a dedicated keychain. This gives the app a STABLE signing identity so the
# macOS Accessibility (TCC) permission grant survives rebuilds — an ad-hoc
# signature changes hash every build and forces re-approval each time.
#
# Safe to re-run: it recreates the keychain from scratch.
#
set -euo pipefail

CERT_NAME="WhisperType Self-Signed"
KEYCHAIN="$HOME/Library/Keychains/whispertype-signing.keychain-db"
KC_PASS="whispertype"
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

echo "Generating private key + self-signed code-signing certificate..."
openssl req -x509 -newkey rsa:2048 -nodes \
  -keyout "$WORK/wt.key" -out "$WORK/wt.crt" -days 3650 \
  -subj "/CN=$CERT_NAME" \
  -addext "basicConstraints=critical,CA:false" \
  -addext "keyUsage=critical,digitalSignature" \
  -addext "extendedKeyUsage=critical,codeSigning"

# macOS Security framework needs the legacy PKCS#12 encoding (OpenSSL 3.x
# defaults to PBE algorithms that `security import` cannot read).
echo "Packaging as PKCS#12 (legacy encoding for macOS)..."
openssl pkcs12 -export -legacy \
  -inkey "$WORK/wt.key" -in "$WORK/wt.crt" \
  -out "$WORK/wt.p12" -passout "pass:$KC_PASS" -name "$CERT_NAME" \
  -macalg sha1 -keypbe PBE-SHA1-3DES -certpbe PBE-SHA1-3DES

echo "Importing into dedicated keychain $KEYCHAIN ..."
security delete-keychain "$KEYCHAIN" 2>/dev/null || true
security create-keychain -p "$KC_PASS" "$KEYCHAIN"
security set-keychain-settings "$KEYCHAIN"             # disable auto-lock timeout
security unlock-keychain -p "$KC_PASS" "$KEYCHAIN"
security import "$WORK/wt.p12" -k "$KEYCHAIN" -P "$KC_PASS" \
  -T /usr/bin/codesign -T /usr/bin/security
# Allow codesign to use the private key without an interactive prompt.
security set-key-partition-list -S apple-tool:,apple:,codesign: -s -k "$KC_PASS" "$KEYCHAIN" >/dev/null

# Add to the user keychain search list so codesign/Xcode can find the identity.
EXISTING="$(security list-keychains -d user | sed 's/[" ]//g' | tr '\n' ' ')"
# shellcheck disable=SC2086
security list-keychains -d user -s "$KEYCHAIN" $EXISTING

echo ""
echo "Done. Codesigning identities:"
security find-identity -p codesigning | grep "$CERT_NAME" || true
echo ""
echo "Now (re)build the app and grant Accessibility once — it will persist."
