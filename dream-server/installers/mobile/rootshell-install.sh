#!/bin/sh

set -eu

SCRIPT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
ROOT_DIR=$(CDPATH= cd -- "$SCRIPT_DIR/../.." && pwd)

MODEL_DIR="$ROOT_DIR/data/models/mobile"
MODEL_FILE="Qwen3-0.6B-Q4_0.gguf"
MODEL_URL="https://huggingface.co/ggml-org/Qwen3-0.6B-GGUF/resolve/main/Qwen3-0.6B-Q4_0.gguf"
MODEL_PATH="$MODEL_DIR/$MODEL_FILE"
WASM_BIN="$ROOT_DIR/mobile-runtime/ios-ashell/bin/llama-cli.wasm"
CONFIG_FILE="$ROOT_DIR/.dream-mobile.env"

DOWNLOAD_MODEL=true

if [ "${1:-}" = "--no-model-download" ]; then
    DOWNLOAD_MODEL=false
fi

mkdir -p "$MODEL_DIR"

if [ "$DOWNLOAD_MODEL" = "true" ] && [ ! -f "$MODEL_PATH" ]; then
    echo "[rootshell] Downloading $MODEL_FILE"
    curl -L --fail --progress-bar -C - -o "$MODEL_PATH" "$MODEL_URL"
fi

ENGINE="rules"
WASM_READY="false"
if command -v wasm >/dev/null 2>&1 && [ -f "$WASM_BIN" ]; then
    ENGINE="wasm"
    WASM_READY="true"
fi

rm -f "$CONFIG_FILE"
{
    echo "DREAM_MOBILE_PLATFORM=\"ios-rootshell\""
    echo "DREAM_MOBILE_MODE=\"ios-rootshell-preview\""
    echo "DREAM_MOBILE_ENGINE=\"$ENGINE\""
    echo "DREAM_MOBILE_MODEL_NAME=\"Qwen3-0.6B\""
    echo "DREAM_MOBILE_MODEL_FILE=\"$MODEL_FILE\""
    echo "DREAM_MOBILE_MODEL_PATH=\"$MODEL_PATH\""
    echo "DREAM_MOBILE_MODEL_DOWNLOADED=\"$( [ -f "$MODEL_PATH" ] && echo true || echo false )\""
    echo "DREAM_MOBILE_WASM_RUNNER=\"wasm\""
    echo "DREAM_MOBILE_WASM_BINARY=\"$WASM_BIN\""
    echo "DREAM_MOBILE_WASM_READY=\"$WASM_READY\""
    echo "DREAM_MOBILE_CONTEXT=\"1024\""
    echo "DREAM_MOBILE_REPLY_TOKENS=\"64\""
    echo "DREAM_MOBILE_CHAT_REPLY_TOKENS=\"128\""
    echo "DREAM_MOBILE_HISTORY_MESSAGES=\"5\""
} > "$CONFIG_FILE"

echo "[ok] Rootshell preview configured"
echo "Platform:  ios-rootshell"
echo "Engine:    $ENGINE"
echo "Model:     $MODEL_PATH"
echo "Wasm bin:  $WASM_BIN"
echo ""
echo "Next:"
echo "  sh ./installers/mobile/rootshell-cli.sh status"
echo "  sh ./installers/mobile/rootshell-cli.sh prompt \"oi\""
echo "  sh ./installers/mobile/rootshell-cli.sh chat"
