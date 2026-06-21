#!/usr/bin/env bash
#
# Downloads a WhisperKit CoreML model variant AND its matching tokenizer so the
# app can be shipped with the model and run fully offline (no first-launch
# download). Files are placed under <dest>/ as:
#
#   <dest>/<variant>/             CoreML model  (argmaxinc/whisperkit-coreml)
#   <dest>/<variant>-tokenizer/   tokenizer     (openai/<tokenizer-repo>)
#
# WhisperKit fetches the tokenizer from the *original* OpenAI repo (not the
# CoreML repo), so we grab both. Only stdlib tools are used: curl + python3.
#
# Usage:
#   ./scripts/fetch-model.sh <dest-dir> [variant] [tokenizer-repo]
# Defaults: variant=openai_whisper-base.en  tokenizer-repo=openai/whisper-base.en
#
set -euo pipefail

DEST="${1:?usage: fetch-model.sh <dest-dir> [variant] [tokenizer-repo]}"
VARIANT="${2:-openai_whisper-base.en}"
TOK_REPO="${3:-openai/whisper-base.en}"
MODEL_REPO="argmaxinc/whisperkit-coreml"

MODEL_DIR="$DEST/$VARIANT"
TOK_DIR="$DEST/${VARIANT}-tokenizer"

dl() { # <repo> <path-in-repo> <output-file>
    local out="$3"
    mkdir -p "$(dirname "$out")"
    curl -fL -sS --retry 3 --retry-delay 1 -o "$out" \
        "https://huggingface.co/$1/resolve/main/$2"
}

list_variant_files() { # <repo> <prefix>  -> rfilenames under prefix
    export PRE="$2"
    curl -fsSL "https://huggingface.co/api/models/$1" | python3 -c "
import sys, json, os
pre = os.environ['PRE']
data = json.load(sys.stdin)
for f in data['siblings']:
    if f['rfilename'].startswith(pre):
        print(f['rfilename'])
"
}

# Skip the (slow) download if a usable model is already cached here.
if [ -f "$MODEL_DIR/config.json" ] && [ -f "$TOK_DIR/tokenizer.json" ]; then
    echo "==> Model already cached at $MODEL_DIR (skipping download)"
    exit 0
fi

echo "==> Fetching CoreML model: $MODEL_REPO / $VARIANT"
list_variant_files "$MODEL_REPO" "$VARIANT/" | while read -r f; do
    rel="${f#"$VARIANT"/}"
    echo "    $rel"
    dl "$MODEL_REPO" "$f" "$MODEL_DIR/$rel"
done

if [ ! -f "$MODEL_DIR/config.json" ]; then
    echo "ERROR: model download produced no files for variant '$VARIANT'." >&2
    exit 1
fi

echo "==> Fetching tokenizer: $TOK_REPO"
# tokenizer.json is required; the rest are loaded if present.
for f in tokenizer.json tokenizer_config.json config.json generation_config.json \
         special_tokens_map.json added_tokens.json vocab.json merges.txt; do
    if dl "$TOK_REPO" "$f" "$TOK_DIR/$f" 2>/dev/null; then
        echo "    $f"
    fi
done

if [ ! -f "$TOK_DIR/tokenizer.json" ]; then
    echo "ERROR: tokenizer.json not found in '$TOK_REPO'." >&2
    exit 1
fi

echo "==> Done: $MODEL_DIR  +  $TOK_DIR"
