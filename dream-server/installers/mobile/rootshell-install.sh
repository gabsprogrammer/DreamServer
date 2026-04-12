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
MODEL_DOWNLOADED=false

if [ "${1:-}" = "--no-model-download" ]; then
    DOWNLOAD_MODEL=false
fi

mkdir -p "$MODEL_DIR"

if [ "$DOWNLOAD_MODEL" = "true" ]; then
    if [ ! -f "$MODEL_PATH" ]; then
        echo "[rootshell] Downloading $MODEL_FILE"
        curl -L --fail --progress-bar -C - -o "$MODEL_PATH" "$MODEL_URL"
    fi
fi

if [ -f "$MODEL_PATH" ]; then
    MODEL_DOWNLOADED=true
fi

ENGINE="rules"
WASM_READY="false"
if command -v wasm >/dev/null 2>&1; then
    if [ -f "$WASM_BIN" ]; then
        ENGINE="wasm"
        WASM_READY="true"
    fi
fi

rm -f "$CONFIG_FILE"
printf '%s\n' "DREAM_MOBILE_PLATFORM=\"ios-rootshell\"" > "$CONFIG_FILE"
printf '%s\n' "DREAM_MOBILE_MODE=\"ios-rootshell-preview\"" >> "$CONFIG_FILE"
printf '%s\n' "DREAM_MOBILE_ENGINE=\"$ENGINE\"" >> "$CONFIG_FILE"
printf '%s\n' "DREAM_MOBILE_MODEL_NAME=\"Qwen3-0.6B\"" >> "$CONFIG_FILE"
printf '%s\n' "DREAM_MOBILE_MODEL_FILE=\"$MODEL_FILE\"" >> "$CONFIG_FILE"
printf '%s\n' "DREAM_MOBILE_MODEL_PATH=\"$MODEL_PATH\"" >> "$CONFIG_FILE"
printf '%s\n' "DREAM_MOBILE_MODEL_DOWNLOADED=\"$MODEL_DOWNLOADED\"" >> "$CONFIG_FILE"
printf '%s\n' "DREAM_MOBILE_WASM_RUNNER=\"wasm\"" >> "$CONFIG_FILE"
printf '%s\n' "DREAM_MOBILE_WASM_BINARY=\"$WASM_BIN\"" >> "$CONFIG_FILE"
printf '%s\n' "DREAM_MOBILE_WASM_READY=\"$WASM_READY\"" >> "$CONFIG_FILE"
printf '%s\n' "DREAM_MOBILE_CONTEXT=\"1024\"" >> "$CONFIG_FILE"
printf '%s\n' "DREAM_MOBILE_REPLY_TOKENS=\"64\"" >> "$CONFIG_FILE"
printf '%s\n' "DREAM_MOBILE_CHAT_REPLY_TOKENS=\"128\"" >> "$CONFIG_FILE"
printf '%s\n' "DREAM_MOBILE_HISTORY_MESSAGES=\"5\"" >> "$CONFIG_FILE"

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
