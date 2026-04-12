#!/bin/sh

set -eu

SCRIPT_DIR=$(dirname "$0")
SCRIPT_DIR=$(cd "$SCRIPT_DIR" && pwd)
ROOT_DIR=$(cd "$SCRIPT_DIR/../.." && pwd)
CONFIG_FILE="$ROOT_DIR/.dream-mobile.env"

if [ ! -f "$CONFIG_FILE" ]; then
    echo "[error] Rootshell preview not installed yet."
    echo "Run: sh ./installers/mobile/rootshell-install.sh"
    exit 1
fi

. "$CONFIG_FILE"

CMD="${1:-status}"

if [ "$CMD" = "status" ]; then
    echo "Platform:  $DREAM_MOBILE_PLATFORM"
    echo "Mode:      $DREAM_MOBILE_MODE"
    echo "Engine:    $DREAM_MOBILE_ENGINE"
    echo "Model:     $DREAM_MOBILE_MODEL_NAME"
    echo "Model file:$DREAM_MOBILE_MODEL_PATH"
    echo "Context:   $DREAM_MOBILE_CONTEXT"
    echo "Prompt tok:$DREAM_MOBILE_REPLY_TOKENS"
    echo "Chat tok:  $DREAM_MOBILE_CHAT_REPLY_TOKENS"
    echo "History:   $DREAM_MOBILE_HISTORY_MESSAGES"
    echo "Downloaded:$DREAM_MOBILE_MODEL_DOWNLOADED"
    echo "Wasm bin:  $DREAM_MOBILE_WASM_BINARY"
    echo "Wasm ready:$DREAM_MOBILE_WASM_READY"
    exit 0
fi

if [ "$DREAM_MOBILE_WASM_READY" != "true" ]; then
    echo "[error] wasm runtime not available in Rootshell."
    echo "Check: command -v wasm"
    exit 1
fi

if [ ! -f "$DREAM_MOBILE_MODEL_PATH" ]; then
    echo "[error] model not found: $DREAM_MOBILE_MODEL_PATH"
    exit 1
fi

if [ $# -gt 0 ]; then
    shift
fi

if [ "$CMD" = "prompt" ]; then
    if [ $# -eq 0 ]; then
        echo "[error] provide a prompt"
        exit 1
    fi
    exec "$DREAM_MOBILE_WASM_RUNNER" "$DREAM_MOBILE_WASM_BINARY" \
        -m "$DREAM_MOBILE_MODEL_PATH" \
        -c "$DREAM_MOBILE_CONTEXT" \
        -n "$DREAM_MOBILE_REPLY_TOKENS" \
        --fast-prompt \
        -p "$*"
fi

if [ "$CMD" = "chat" ]; then
    exec "$DREAM_MOBILE_WASM_RUNNER" "$DREAM_MOBILE_WASM_BINARY" \
        -m "$DREAM_MOBILE_MODEL_PATH" \
        -c "$DREAM_MOBILE_CONTEXT" \
        -n "$DREAM_MOBILE_CHAT_REPLY_TOKENS" \
        --history "$DREAM_MOBILE_HISTORY_MESSAGES" \
        --fast-chat \
        -i
fi

echo "[error] unknown command: $CMD"
echo "Use: status | prompt | chat"
exit 1
