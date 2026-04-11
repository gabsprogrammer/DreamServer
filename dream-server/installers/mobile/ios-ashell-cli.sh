#!/bin/sh
# ============================================================================
# Dream Server iOS / a-Shell CLI + Shortcuts Preview
# ============================================================================

set -eu

ROOT_DIR="$(CDPATH= cd -- "$(dirname -- "$0")/../.." && pwd)"
CONFIG_FILE="$ROOT_DIR/.dream-mobile.env"
INSTALLER="$ROOT_DIR/installers/mobile/ios-ashell-install.sh"

RED='[0;31m'
GREEN='[0;32m'
YELLOW='[1;33m'
CYAN='[0;36m'
NC='[0m'

log()     { printf '%s[dream-ios]%s %s\n' "$CYAN" "$NC" "$1"; }
success() { printf '%s[ok]%s %s\n' "$GREEN" "$NC" "$1"; }
warn()    { printf '%s[warn]%s %s\n' "$YELLOW" "$NC" "$1"; }
fail()    { printf '%s[error]%s %s\n' "$RED" "$NC" "$1" >&2; exit 1; }

usage() {
    cat <<'EOF'
Dream Server iOS / a-Shell Preview

Usage:
  sh ./dream-mobile.sh install
  sh ./dream-mobile.sh status
  sh ./dream-mobile.sh doctor
  sh ./dream-mobile.sh apps
  sh ./dream-mobile.sh intent "abrir calculadora"
  sh ./dream-mobile.sh prompt "abrir safari no github"

Commands:
  install      Set up the iOS preview files and Shortcut examples
  status       Show engine/runtime status
  doctor       Explain why local Qwen chat is or is not ready
  apps         List the stable app IDs exposed for Shortcuts
  intent       Return JSON for Apple Shortcuts
  intent-text  Return pipe-delimited text for simple Shortcut parsing
  prompt       Fast one-shot prompt for iPhone shell use
  chat         Fast interactive chat for iPhone shell use
  chat-safe    Slower but more structured interactive chat
EOF
}

load_config() {
    [ -f "$CONFIG_FILE" ] || fail "iOS preview is not installed yet. Run 'sh ./dream-mobile.sh install' first."
    # shellcheck disable=SC1090
    . "$CONFIG_FILE"
}

require_config_var() {
    var_name="$1"
    eval "var_value=\${$var_name-}"
    [ -n "$var_value" ] || fail "iOS preview config is incomplete: missing $var_name. Run 'sh ./install.sh' again."
}

json_escape() {
    printf '%s' "$1" | sed 's/\\/\\\\/g; s/"/\\"/g'
}

normalize_text() {
    printf '%s' "$1" \
        | tr '[:upper:]' '[:lower:]' \
        | sed 'y/áàâãäéèêëíìîïóòôõöúùûüç/aaaaaeeeeiiiiooooouuuuc/' \
        | tr '\n' ' '
}

trim_text() {
    printf '%s' "$1" | sed 's/^[[:space:]]*//; s/[[:space:]]*$//'
}

extract_url() {
    text="$1"
    first=""
    first=$(printf '%s\n' "$text" | grep -Eo 'https?://[^ ]+|www\.[^ ]+' | head -n 1 || true)
    if [ -n "$first" ]; then
        case "$first" in
            www.*) printf 'https://%s\n' "$first" ;;
            *) printf '%s\n' "$first" ;;
        esac
        return 0
    fi

    case "$text" in
        *github*) printf '%s\n' "https://github.com" ;;
        *google*) printf '%s\n' "https://www.google.com" ;;
        *youtube*) printf '%s\n' "https://www.youtube.com" ;;
        *openai*) printf '%s\n' "https://openai.com" ;;
        *wikipedia*) printf '%s\n' "https://www.wikipedia.org" ;;
        *) printf '%s\n' "" ;;
    esac
}

app_label() {
    case "$1" in
        calculator) printf '%s\n' "Calculadora" ;;
        camera) printf '%s\n' "Camera" ;;
        clock) printf '%s\n' "Relogio" ;;
        notes) printf '%s\n' "Notas" ;;
        safari) printf '%s\n' "Safari" ;;
        settings) printf '%s\n' "Ajustes" ;;
        files) printf '%s\n' "Arquivos" ;;
        app_store) printf '%s\n' "App Store" ;;
        music) printf '%s\n' "Musica" ;;
        calendar) printf '%s\n' "Calendario" ;;
        reminders) printf '%s\n' "Lembretes" ;;
        phone) printf '%s\n' "Telefone" ;;
        messages) printf '%s\n' "Mensagens" ;;
        mail) printf '%s\n' "Mail" ;;
        *) printf '%s\n' "$1" ;;
    esac
}

match_app_id() {
    case "$1" in
        *calculadora*|*calculator*) printf '%s\n' "calculator" ;;
        *camera*|*foto*|*selfie*) printf '%s\n' "camera" ;;
        *relogio*|*clock*|*timer*|*alarme*) printf '%s\n' "clock" ;;
        *nota*|*notes*) printf '%s\n' "notes" ;;
        *safari*|*browser*|*navegador*) printf '%s\n' "safari" ;;
        *ajustes*|*configuracao*|*configuracoes*|*settings*) printf '%s\n' "settings" ;;
        *arquivos*|*files*) printf '%s\n' "files" ;;
        *app\ store*|*loja*) printf '%s\n' "app_store" ;;
        *musica*|*music*) printf '%s\n' "music" ;;
        *calendario*|*calendar*) printf '%s\n' "calendar" ;;
        *lembrete*|*reminders*) printf '%s\n' "reminders" ;;
        *telefone*|*ligacao*|*phone*) printf '%s\n' "phone" ;;
        *mensagem*|*messages*|*imessage*) printf '%s\n' "messages" ;;
        *mail*|*email*|*e-mail*) printf '%s\n' "mail" ;;
        *) printf '%s\n' "" ;;
    esac
}

list_apps() {
    cat <<'EOF'
calculator | Calculadora
camera | Camera
clock | Relogio
notes | Notas
safari | Safari
settings | Ajustes
files | Arquivos
app_store | App Store
music | Musica
calendar | Calendario
reminders | Lembretes
phone | Telefone
messages | Mensagens
mail | Mail
EOF
}

build_search_url() {
    query="$1"
    case "$query" in
        *buscar*)
            query=$(printf '%s' "$query" | sed 's/.*buscar[[:space:]]*//')
            ;;
        *pesquisar*)
            query=$(printf '%s' "$query" | sed 's/.*pesquisar[[:space:]]*//')
            ;;
        *search*)
            query=$(printf '%s' "$query" | sed 's/.*search[[:space:]]*//')
            ;;
    esac
    query=$(trim_text "$query")
    [ -n "$query" ] || query="$1"
    encoded=$(printf '%s' "$query" | sed 's/ /+/g')
    printf 'https://www.google.com/search?q=%s\n' "$encoded"
}

print_json_reply() {
    action_type="$1"
    action_value="$2"
    spoken="$3"
    confidence="$4"

    if [ "$action_type" = "open_app" ]; then
        label=$(app_label "$action_value")
        printf '{'
        printf '"ok":true,'
        printf '"engine":"%s",' "$(json_escape "${DREAM_MOBILE_ENGINE:-rules}")"
        printf '"mode":"ios-shortcuts-preview",'
        printf '"action":{"type":"open_app","app_id":"%s","app_label":"%s"},' \
            "$(json_escape "$action_value")" "$(json_escape "$label")"
        printf '"spoken_response":"%s",' "$(json_escape "$spoken")"
        printf '"confidence":%s' "$confidence"
        printf '}\n'
        return 0
    fi

    if [ "$action_type" = "open_url" ]; then
        printf '{'
        printf '"ok":true,'
        printf '"engine":"%s",' "$(json_escape "${DREAM_MOBILE_ENGINE:-rules}")"
        printf '"mode":"ios-shortcuts-preview",'
        printf '"action":{"type":"open_url","url":"%s"},' "$(json_escape "$action_value")"
        printf '"spoken_response":"%s",' "$(json_escape "$spoken")"
        printf '"confidence":%s' "$confidence"
        printf '}\n'
        return 0
    fi

    if [ "$action_type" = "run_shortcut" ]; then
        printf '{'
        printf '"ok":true,'
        printf '"engine":"%s",' "$(json_escape "${DREAM_MOBILE_ENGINE:-rules}")"
        printf '"mode":"ios-shortcuts-preview",'
        printf '"action":{"type":"run_shortcut","shortcut_name":"%s"},' "$(json_escape "$action_value")"
        printf '"spoken_response":"%s",' "$(json_escape "$spoken")"
        printf '"confidence":%s' "$confidence"
        printf '}\n'
        return 0
    fi

    printf '{'
    printf '"ok":true,'
    printf '"engine":"%s",' "$(json_escape "${DREAM_MOBILE_ENGINE:-rules}")"
    printf '"mode":"ios-shortcuts-preview",'
    printf '"action":{"type":"reply","message":"%s"},' "$(json_escape "$action_value")"
    printf '"spoken_response":"%s",' "$(json_escape "$spoken")"
    printf '"confidence":%s' "$confidence"
    printf '}\n'
}

print_text_reply() {
    action_type="$1"
    action_value="$2"
    spoken="$3"
    confidence="$4"
    printf '%s|%s|%s|%s\n' "$action_type" "$action_value" "$spoken" "$confidence"
}

intent_core() {
    raw_input="$1"
    normalized=$(normalize_text "$raw_input")
    app_id=$(match_app_id "$normalized")
    url=$(extract_url "$normalized")

    if [ -n "$app_id" ] && printf '%s' "$normalized" | grep -Eq 'abrir|open|launch|mostrar|ir para'; then
        label=$(app_label "$app_id")
        ACTION_TYPE="open_app"
        ACTION_VALUE="$app_id"
        SPOKEN="Abrindo $label."
        CONFIDENCE="0.98"
        return 0
    fi

    if [ -n "$url" ] && printf '%s' "$normalized" | grep -Eq 'abrir|open|site|website|web|navegador|browser'; then
        ACTION_TYPE="open_url"
        ACTION_VALUE="$url"
        SPOKEN="Abrindo $url."
        CONFIDENCE="0.90"
        return 0
    fi

    if printf '%s' "$normalized" | grep -Eq 'buscar|pesquisar|search'; then
        ACTION_TYPE="open_url"
        ACTION_VALUE=$(build_search_url "$normalized")
        SPOKEN="Abrindo uma busca na web."
        CONFIDENCE="0.82"
        return 0
    fi

    if printf '%s' "$normalized" | grep -Eq 'atalho|shortcut'; then
        shortcut_name=$(printf '%s' "$raw_input" | sed 's/.*[Aa]talho[[:space:]]*//; s/.*[Ss]hortcut[[:space:]]*//')
        shortcut_name=$(trim_text "$shortcut_name")
        [ -n "$shortcut_name" ] || shortcut_name="Dream Server"
        ACTION_TYPE="run_shortcut"
        ACTION_VALUE="$shortcut_name"
        SPOKEN="Rodando o atalho $shortcut_name."
        CONFIDENCE="0.70"
        return 0
    fi

    ACTION_TYPE="reply"
    ACTION_VALUE="Ainda nao consegui mapear essa intencao com confianca. Tente comandos como abrir calculadora, abrir safari no github, ou pesquisar algo."
    SPOKEN="$ACTION_VALUE"
    CONFIDENCE="0.35"
}

local_wasm_ready() {
    load_config
    [ "${DREAM_MOBILE_WASM_READY:-false}" = "true" ] || return 1
    command -v "${DREAM_MOBILE_WASM_RUNNER:-wasm}" >/dev/null 2>&1 || return 1
    [ -f "${DREAM_MOBILE_WASM_BINARY:-}" ] || return 1
    [ -f "${DREAM_MOBILE_MODEL_PATH:-}" ] || return 1
    return 0
}

print_wasm_followup() {
    [ -n "${DREAM_MOBILE_WASM_BUILD_HELPER:-}" ] && echo "Wasm builder: ${DREAM_MOBILE_WASM_BUILD_HELPER}"
    [ -n "${DREAM_MOBILE_WASM_BUILD_DOC:-}" ] && echo "Wasm notes: ${DREAM_MOBILE_WASM_BUILD_DOC}"
}

status() {
    load_config
    require_config_var DREAM_MOBILE_PLATFORM
    require_config_var DREAM_MOBILE_MODE
    require_config_var DREAM_MOBILE_ENGINE
    require_config_var DREAM_MOBILE_MODEL_NAME
    require_config_var DREAM_MOBILE_MODEL_PATH

    echo "Platform:  ${DREAM_MOBILE_PLATFORM}"
    echo "Mode:      ${DREAM_MOBILE_MODE}"
    echo "Engine:    ${DREAM_MOBILE_ENGINE}"
    echo "Model:     ${DREAM_MOBILE_MODEL_NAME}"
    echo "Model file:${DREAM_MOBILE_MODEL_PATH}"
    echo "Context:   ${DREAM_MOBILE_CONTEXT}"
    echo "Prompt tok:${DREAM_MOBILE_REPLY_TOKENS:-64}"
    echo "Chat tok:  ${DREAM_MOBILE_CHAT_REPLY_TOKENS:-128}"
    echo "History:   ${DREAM_MOBILE_HISTORY_MESSAGES:-5} messages"
    echo "Downloaded:${DREAM_MOBILE_MODEL_DOWNLOADED}"
    echo "Wasm bin:  ${DREAM_MOBILE_WASM_BINARY}"
    echo "Wasm ready:${DREAM_MOBILE_WASM_READY}"
    echo "Shortcut doc: ${DREAM_MOBILE_SHORTCUTS_DOC}"
    print_wasm_followup
    success "iOS preview config loaded"
}

doctor() {
    status

    if local_wasm_ready; then
        success "The local wasm runtime is present, so 'prompt' and 'chat' can talk to the model."
        return 0
    fi

    warn "The Qwen GGUF can be downloaded on iOS today, but chat still needs a linked wasm runtime at ${DREAM_MOBILE_WASM_BINARY}."
    warn "The iOS / a-Shell runtime now needs the custom exceptions-enabled wasi-sdk helper plus the linked wasm binary in the repo path above."
    echo "Host helpers:"
    echo "  runtime build: ${DREAM_MOBILE_WASM_BUILD_HELPER}"
    echo "  sdk build:     ${ROOT_DIR}/installers/mobile/build-ios-ashell-wasm-sdk.sh"
    echo "Current notes:"
    echo "  ${DREAM_MOBILE_WASM_BUILD_DOC}"
}

intent_json() {
    load_config
    [ $# -gt 0 ] || fail "Provide a prompt after 'intent'."
    intent_core "$*"
    print_json_reply "$ACTION_TYPE" "$ACTION_VALUE" "$SPOKEN" "$CONFIDENCE"
}

intent_text() {
    load_config
    [ $# -gt 0 ] || fail "Provide a prompt after 'intent-text'."
    intent_core "$*"
    print_text_reply "$ACTION_TYPE" "$ACTION_VALUE" "$SPOKEN" "$CONFIDENCE"
}

prompt_once() {
    load_config
    [ $# -gt 0 ] || fail "Provide a prompt after 'prompt'."

    if local_wasm_ready; then
        "${DREAM_MOBILE_WASM_RUNNER}" "${DREAM_MOBILE_WASM_BINARY}" \
            -m "${DREAM_MOBILE_MODEL_PATH}" \
            -c "${DREAM_MOBILE_CONTEXT:-2048}" \
            -n "${DREAM_MOBILE_REPLY_TOKENS:-64}" \
            --fast-prompt \
            -p "$*"
        return 0
    fi

    intent_core "$*"
    print_json_reply "$ACTION_TYPE" "$ACTION_VALUE" "$SPOKEN" "$CONFIDENCE"
}

interactive_chat() {
    load_config
    if ! local_wasm_ready; then
        fail "Interactive chat on iOS still needs a linked wasm runtime at ${DREAM_MOBILE_WASM_BINARY:-<unset>}. Run 'sh ./dream-mobile.sh doctor' for the current blocker and host build helper."
    fi

    exec "${DREAM_MOBILE_WASM_RUNNER}" "${DREAM_MOBILE_WASM_BINARY}" \
        -m "${DREAM_MOBILE_MODEL_PATH}" \
        -c "${DREAM_MOBILE_CONTEXT:-2048}" \
        -n "${DREAM_MOBILE_CHAT_REPLY_TOKENS:-128}" \
        --history "${DREAM_MOBILE_HISTORY_MESSAGES:-5}" \
        --fast-chat \
        -i
}

interactive_chat_safe() {
    load_config
    if ! local_wasm_ready; then
        fail "Interactive chat on iOS still needs a linked wasm runtime at ${DREAM_MOBILE_WASM_BINARY:-<unset>}. Run 'sh ./dream-mobile.sh doctor' for the current blocker and host build helper."
    fi

    exec "${DREAM_MOBILE_WASM_RUNNER}" "${DREAM_MOBILE_WASM_BINARY}" \
        -m "${DREAM_MOBILE_MODEL_PATH}" \
        -c "${DREAM_MOBILE_CONTEXT:-2048}" \
        -n "${DREAM_MOBILE_CHAT_REPLY_TOKENS:-128}" \
        --history "${DREAM_MOBILE_HISTORY_MESSAGES:-5}" \
        -i
}

cmd="${1:-status}"
case "$cmd" in
    install)
        shift
        exec sh "$INSTALLER" "$@"
        ;;
    status)
        shift
        status "$@"
        ;;
    doctor)
        shift
        doctor "$@"
        ;;
    apps)
        shift
        list_apps "$@"
        ;;
    intent)
        shift
        intent_json "$@"
        ;;
    intent-text)
        shift
        intent_text "$@"
        ;;
    prompt)
        shift
        prompt_once "$@"
        ;;
    chat)
        shift
        interactive_chat "$@"
        ;;
    chat-safe)
        shift
        interactive_chat_safe "$@"
        ;;
    -h|--help|help)
        usage
        ;;
    *)
        fail "Unknown command: $cmd"
        ;;
esac
