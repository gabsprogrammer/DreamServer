#!/bin/sh
# Lightweight shell wrapper for Dream Server mobile preview.

if [ -z "${BASH_VERSION:-}" ]; then
    SCRIPT_DIR="$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)"
    CONFIG_FILE="$SCRIPT_DIR/.dream-mobile.env"
    if [ -f "$CONFIG_FILE" ] && grep -q 'DREAM_MOBILE_PLATFORM="ios-ashell"' "$CONFIG_FILE" 2>/dev/null; then
        exec sh "$SCRIPT_DIR/installers/mobile/ios-ashell-cli.sh" "$@"
    fi
    if [ "${TERM_PROGRAM:-}" = "a-Shell" ] || [ "${TERM_PROGRAM:-}" = "a-Shell mini" ] || [ -n "${ASHELL:-}" ]; then
        exec sh "$SCRIPT_DIR/installers/mobile/ios-ashell-cli.sh" "$@"
    fi
    case "$SCRIPT_DIR" in
        /private/var/mobile/Containers/Data/Application/*|/var/mobile/Containers/Data/Application/*)
            exec sh "$SCRIPT_DIR/installers/mobile/ios-ashell-cli.sh" "$@"
            ;;
    esac
    case "${HOME:-}" in
        /private/var/mobile/Containers/Data/Application/*|/var/mobile/Containers/Data/Application/*)
            exec sh "$SCRIPT_DIR/installers/mobile/ios-ashell-cli.sh" "$@"
            ;;
    esac
    if [ "$(uname -s 2>/dev/null || echo unknown)" = "Darwin" ] && [ -d /private/var/mobile/Containers/Data/Application ]; then
        exec sh "$SCRIPT_DIR/installers/mobile/ios-ashell-cli.sh" "$@"
    fi
    if command -v bash >/dev/null 2>&1; then
        exec bash "$0" "$@"
    fi
    echo "[error] dream-mobile.sh requires bash." >&2
    exit 1
fi

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONFIG_FILE="$SCRIPT_DIR/.dream-mobile.env"
INSTALLER="$SCRIPT_DIR/installers/mobile/install-mobile.sh"

RED='\033[0;31m'
GREEN='\033[0;32m'
CYAN='\033[0;36m'
NC='\033[0m'

log()     { echo -e "${CYAN}[dream-mobile]${NC} $1"; }
success() { echo -e "${GREEN}[ok]${NC} $1"; }
fail()    { echo -e "${RED}[error]${NC} $1" >&2; exit 1; }

usage() {
    cat <<'EOF'
Dream Server Mobile Shell Preview

Usage:
  ./dream-mobile.sh install
  ./dream-mobile.sh status
  ./dream-mobile.sh chat
  ./dream-mobile.sh prompt "sua pergunta"

Commands:
  install    Build the mobile runtime and download the preview model
  status     Show the current mobile runtime status
  chat       Open an interactive shell chat with the installed model
  prompt     Send one prompt and print the answer
EOF
}

load_config() {
    [[ -f "$CONFIG_FILE" ]] || fail "Mobile preview is not installed yet. Run ./dream-mobile.sh install first."
    # shellcheck disable=SC1090
    source "$CONFIG_FILE"
}

require_runtime() {
    load_config
    [[ -x "${DREAM_MOBILE_LLAMA_CLI:-}" ]] || fail "llama-cli was not found at ${DREAM_MOBILE_LLAMA_CLI:-<unset>}"
    [[ -f "${DREAM_MOBILE_MODEL_PATH:-}" ]] || fail "Model file was not found at ${DREAM_MOBILE_MODEL_PATH:-<unset>}"
}

status() {
    require_runtime

    echo "Platform: ${DREAM_MOBILE_PLATFORM}"
    echo "Model:    ${DREAM_MOBILE_MODEL_NAME}"
    echo "File:     ${DREAM_MOBILE_MODEL_FILE}"
    echo "Context:  ${DREAM_MOBILE_CONTEXT}"
    echo "Threads:  ${DREAM_MOBILE_THREADS}"
    echo "CLI:      ${DREAM_MOBILE_LLAMA_CLI}"
    echo "Path:     ${DREAM_MOBILE_MODEL_PATH}"
    success "Runtime looks ready"
}

interactive_chat() {
    require_runtime
    exec "${DREAM_MOBILE_LLAMA_CLI}" \
        -m "${DREAM_MOBILE_MODEL_PATH}" \
        -c "${DREAM_MOBILE_CONTEXT}" \
        -t "${DREAM_MOBILE_THREADS}" \
        -ngl 0 \
        -i \
        -cnv \
        --color
}

one_prompt() {
    require_runtime
    [[ $# -gt 0 ]] || fail "Provide a prompt after 'prompt'."

    "${DREAM_MOBILE_LLAMA_CLI}" \
        -m "${DREAM_MOBILE_MODEL_PATH}" \
        -c "${DREAM_MOBILE_CONTEXT}" \
        -t "${DREAM_MOBILE_THREADS}" \
        -ngl 0 \
        -cnv \
        -n 512 \
        -p "$*"
}

cmd="${1:-status}"
case "$cmd" in
    install)
        shift
        exec bash "$INSTALLER" "$@"
        ;;
    status)
        shift
        status "$@"
        ;;
    chat)
        shift
        interactive_chat "$@"
        ;;
    prompt)
        shift
        one_prompt "$@"
        ;;
    -h|--help|help)
        usage
        ;;
    *)
        fail "Unknown command: $cmd"
        ;;
esac
