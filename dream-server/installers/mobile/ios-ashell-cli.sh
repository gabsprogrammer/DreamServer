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
  sh ./dream-mobile.sh act "enviar email para alguem sobre algo"
  sh ./dream-mobile.sh prompt "abrir safari no github"

Commands:
  install      Set up the iOS preview files and Shortcut examples
  status       Show engine/runtime status
  doctor       Explain why local Qwen chat is or is not ready
  apps         List the stable app IDs exposed for Shortcuts
  intent       Return JSON for Apple Shortcuts
  intent-text  Return pipe-delimited text for simple Shortcut parsing
  act          Perform supported actions directly in a-Shell when possible
  prompt       Legacy-fast one-shot prompt for iPhone shell use
  chat         Legacy-fast interactive model chat
  chat-agent   Smart shell chat with direct action routing
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

url_encode() {
    text=$(printf '%s' "$1" | tr '\r\n' '  ')
    text=$(printf '%s' "$text" | sed \
        -e 's/%/%25/g' \
        -e 's/ /%20/g' \
        -e 's/#/%23/g' \
        -e 's/&/%26/g' \
        -e 's/+/%2B/g' \
        -e 's/,/%2C/g' \
        -e 's/;/%3B/g' \
        -e 's/?/%3F/g')
    printf '%s\n' "$text"
}

build_mailto_url() {
    email_to="$1"
    email_subject="$2"
    email_body="$3"

    encoded_to=$(url_encode "$email_to")
    encoded_subject=$(url_encode "$email_subject")
    encoded_body=$(url_encode "$email_body")
    printf 'mailto:%s?subject=%s&body=%s\n' "$encoded_to" "$encoded_subject" "$encoded_body"
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

extract_email_address() {
    printf '%s\n' "$1" \
        | tr ' <>()[]{}"' '\n' \
        | sed -n '/@/p' \
        | head -n 1 \
        | sed 's/[.,;:!?]*$//'
}

extract_email_subject() {
    raw="$1"
    subject=$(printf '%s' "$raw" | sed -n 's/.*[Aa]ssunto[[:space:]:-]*//p' | head -n 1)
    subject=$(printf '%s' "$subject" | sed 's/[[:space:]]\{1,\}\([Tt]exto\|[Mm]ensagem\|[Cc]orpo\|[Dd]izendo\|[Ss]obre\)[[:space:]:-].*$//')
    subject=$(trim_text "$subject")
    printf '%s\n' "$subject"
}

extract_email_body() {
    raw="$1"
    body=""

    for pattern in \
        '.*[Cc]orpo[[:space:]:-]*' \
        '.*[Tt]exto[[:space:]:-]*' \
        '.*[Mm]ensagem[[:space:]:-]*' \
        '.*[Dd]izendo[[:space:]:-]*'
    do
        body=$(printf '%s' "$raw" | sed -n "s/$pattern//p" | head -n 1)
        body=$(trim_text "$body")
        if [ -n "$body" ]; then
            printf '%s\n' "$body"
            return 0
        fi
    done

    printf '%s\n' ""
}

extract_email_topic() {
    raw="$1"
    topic=$(printf '%s' "$raw" | sed -n 's/.*[Ss]obre[[:space:]:-]*//p' | head -n 1)
    topic=$(trim_text "$topic")
    printf '%s\n' "$topic"
}

is_probably_portuguese() {
    case "$(normalize_text "$1")" in
        *enviar*|*email*|*e-mail*|*assunto*|*texto*|*mensagem*|*sobre*|*reuniao*|*amanha*|*obrigado*|*oi*|*ola*|*para*)
            return 0
            ;;
        *)
            return 1
            ;;
    esac
}

generate_email_draft_from_topic() {
    raw_request="$1"
    topic_hint="$2"

    topic=$(trim_text "$topic_hint")
    [ -n "$topic" ] || topic=$(trim_text "$raw_request")

    if is_probably_portuguese "$raw_request"; then
        subject="Sobre $topic"
        body="Oi! Estou entrando em contato sobre $topic. Quando puder, me avise. Obrigado!"
    else
        subject="About $topic"
        body="Hi! I'm reaching out about $topic. When you have a moment, please let me know. Thanks!"
    fi

    printf '%s\t%s\n' "$subject" "$body"
}

looks_like_email_request() {
    case "$(normalize_text "$1")" in
        *email*|*e-mail*|*mail*|*gmail*|*envia*|*enviar*|*manda*|*mandar*|*escreve\ um\ email*|*redige\ um\ email*|*responde\ por\ email*)
            return 0
            ;;
        *)
            return 1
            ;;
    esac
}

remove_email_address_from_text() {
    raw="$1"
    email_to="$2"
    if [ -n "$email_to" ]; then
        printf '%s' "$raw" | sed "s/$email_to//g"
    else
        printf '%s' "$raw"
    fi
}

clean_email_request_topic() {
    raw="$1"
    email_to="$2"
    cleaned=$(remove_email_address_from_text "$raw" "$email_to")
    cleaned=$(printf '%s' "$cleaned" | sed \
        -e 's/[Pp]ara[[:space:]]\+/ /g' \
        -e 's/[Ee]nviar[[:space:]]\+[Ee]mail/ /g' \
        -e 's/[Ee]nviar[[:space:]]\+[Uu]m[[:space:]]\+[Ee]mail/ /g' \
        -e 's/[Mm]andar[[:space:]]\+[Ee]mail/ /g' \
        -e 's/[Mm]anda[[:space:]]\+[Uu]m[[:space:]]\+[Ee]mail/ /g' \
        -e 's/[Ee]screve[[:space:]]\+[Uu]m[[:space:]]\+[Ee]mail/ /g' \
        -e 's/[Rr]edige[[:space:]]\+[Uu]m[[:space:]]\+[Ee]mail/ /g' \
        -e 's/[Pp]or[[:space:]]\+[Ee]mail/ /g' \
        -e 's/[Gg]mail/ /g' \
        -e 's/[Mm]ail/ /g' \
        -e 's/[Ee]-[Mm]ail/ /g' \
        -e 's/[Ee]mail/ /g')
    cleaned=$(trim_text "$cleaned")
    printf '%s\n' "$cleaned"
}

generate_email_draft_with_model() {
    raw_request="$1"
    email_to="$2"
    topic_hint="$3"

    if ! local_wasm_ready; then
        generate_email_draft_from_topic "$raw_request" "$topic_hint"
        return 0
    fi

    prompt_request="$topic_hint"
    [ -n "$prompt_request" ] || prompt_request=$(clean_email_request_topic "$raw_request" "$email_to")
    prompt_request=$(trim_text "$prompt_request")
    [ -n "$prompt_request" ] || prompt_request="$raw_request"

    draft_prompt=$(cat <<EOF
Escreva um email curto, natural e util no mesmo idioma do pedido.
Responda com exatamente duas linhas:
SUBJECT: <assunto curto>
BODY: <corpo do email em um unico paragrafo>

Destinatario: $email_to
Pedido: $prompt_request
EOF
)

    output=$(generate_model_text "$draft_prompt" 2>/dev/null || true)
    output=$(printf '%s' "$output" | tr -d '\r')
    subject=$(printf '%s\n' "$output" | sed -n 's/^SUBJECT:[[:space:]]*//p' | head -n 1)
    body=$(printf '%s\n' "$output" | sed -n 's/^BODY:[[:space:]]*//p' | head -n 1)
    subject=$(trim_text "$subject")
    body=$(trim_text "$body")

    if [ -n "$subject" ] && [ -n "$body" ]; then
        printf '%s\t%s\n' "$subject" "$body"
        return 0
    fi

    generate_email_draft_from_topic "$raw_request" "$topic_hint"
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
    tab_char=$(printf '\t')

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

    if [ "$action_type" = "compose_email" ]; then
        email_to=${action_value%%"$tab_char"*}
        if [ "$email_to" = "$action_value" ]; then
            email_subject=""
            email_body=""
        else
            remainder=${action_value#*"$tab_char"}
            email_subject=${remainder%%"$tab_char"*}
            if [ "$email_subject" = "$remainder" ]; then
                email_body=""
            else
                email_body=${remainder#*"$tab_char"}
            fi
        fi
        mailto_url=$(build_mailto_url "$email_to" "$email_subject" "$email_body")
        printf '{'
        printf '"ok":true,'
        printf '"engine":"%s",' "$(json_escape "${DREAM_MOBILE_ENGINE:-rules}")"
        printf '"mode":"ios-shortcuts-preview",'
        printf '"action":{"type":"compose_email","to":"%s","subject":"%s","body":"%s","mailto_url":"%s"},' \
            "$(json_escape "$email_to")" "$(json_escape "$email_subject")" "$(json_escape "$email_body")" "$(json_escape "$mailto_url")"
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

open_url_direct() {
    target_url="$1"
    command -v open >/dev/null 2>&1 || fail "The 'open' command is not available in this shell."
    open "$target_url"
}

run_shortcut_direct() {
    shortcut_name="$1"
    encoded_name=$(url_encode "$shortcut_name")
    open_url_direct "shortcuts://x-callback-url/run-shortcut?name=$encoded_name"
}

run_shortcut_direct_with_text() {
    shortcut_name="$1"
    shortcut_text="$2"
    encoded_name=$(url_encode "$shortcut_name")
    encoded_text=$(url_encode "$shortcut_text")
    open_url_direct "shortcuts://x-callback-url/run-shortcut?name=$encoded_name&input=text&text=$encoded_text"
}

build_email_shortcut_payload_json() {
    email_to="$1"
    email_subject="$2"
    email_body="$3"
    printf '{'
    printf '"to":"%s",' "$(json_escape "$email_to")"
    printf '"subject":"%s",' "$(json_escape "$email_subject")"
    printf '"body":"%s"' "$(json_escape "$email_body")"
    printf '}\n'
}

perform_action() {
    action_type="$1"
    action_value="$2"
    spoken="$3"
    tab_char=$(printf '\t')

    case "$action_type" in
        compose_email)
            email_to=${action_value%%"$tab_char"*}
            remainder=${action_value#*"$tab_char"}
            email_subject=${remainder%%"$tab_char"*}
            email_body=${remainder#*"$tab_char"}
            if [ -n "${DREAM_MOBILE_EMAIL_SHORTCUT_NAME:-}" ]; then
                payload=$(build_email_shortcut_payload_json "$email_to" "$email_subject" "$email_body")
                run_shortcut_direct_with_text "${DREAM_MOBILE_EMAIL_SHORTCUT_NAME}" "$payload"
                success "Envio delegando ao atalho ${DREAM_MOBILE_EMAIL_SHORTCUT_NAME}."
                return 0
            fi
            open_url_direct "$(build_mailto_url "$email_to" "$email_subject" "$email_body")"
            success "$spoken"
            ;;
        open_url)
            open_url_direct "$action_value"
            success "$spoken"
            ;;
        run_shortcut)
            run_shortcut_direct "$action_value"
            success "$spoken"
            ;;
        reply)
            printf '%s\n' "$spoken"
            ;;
        open_app)
            fail "Direct app opening still needs Apple Shortcuts for action type open_app."
            ;;
        *)
            fail "Unsupported action type: $action_type"
            ;;
    esac
}

intent_core() {
    raw_input="$1"
    tab_char=$(printf '\t')
    normalized=$(normalize_text "$raw_input")
    app_id=$(match_app_id "$normalized")
    url=$(extract_url "$normalized")
    email_to=$(extract_email_address "$raw_input")

    if [ -n "$email_to" ] && printf '%s' "$normalized" | grep -Eq 'email|e-mail|mail|gmail|enviar'; then
        email_subject=$(extract_email_subject "$raw_input")
        email_body=$(extract_email_body "$raw_input")
        email_topic=$(extract_email_topic "$raw_input")
        [ -n "$email_topic" ] || email_topic=$(clean_email_request_topic "$raw_input" "$email_to")

        if [ -z "$email_body" ] || [ -n "$email_topic" ]; then
            generated=$(generate_email_draft_from_topic "$raw_input" "$email_topic")
            if [ -n "$generated" ]; then
                email_subject=${generated%%"$tab_char"*}
                if [ "$email_subject" = "$generated" ]; then
                    email_body=""
                else
                    email_body=${generated#*"$tab_char"}
                fi
            fi
        fi

        [ -n "$email_subject" ] || email_subject="Mensagem do Dream Server"
        [ -n "$email_body" ] || email_body="Oi! Estou te enviando esta mensagem criada no Dream Server."

        ACTION_TYPE="compose_email"
        ACTION_VALUE=$(printf '%s\t%s\t%s' "$email_to" "$email_subject" "$email_body")
        SPOKEN="Preparei um rascunho de email para $email_to."
        CONFIDENCE="0.86"
        return 0
    fi

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
    ACTION_VALUE="Ainda nao consegui mapear essa intencao com confianca. Tente comandos como abrir calculadora, abrir safari no github, enviar email para alguem, ou pesquisar algo."
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
    echo "Prompt tok:${DREAM_MOBILE_REPLY_TOKENS:-48}"
    echo "Chat tok:  ${DREAM_MOBILE_CHAT_REPLY_TOKENS:-64}"
    echo "History:   ${DREAM_MOBILE_HISTORY_MESSAGES:-1} turns"
    echo "Email sc.: ${DREAM_MOBILE_EMAIL_SHORTCUT_NAME:-<draft-mode>}"
    echo "Downloaded:${DREAM_MOBILE_MODEL_DOWNLOADED}"
    echo "Wasm bin:  ${DREAM_MOBILE_WASM_BINARY}"
    echo "Wasm ready:${DREAM_MOBILE_WASM_READY}"
    echo "Profile:   legacy-fast chat default, chat-agent optional"
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

act_once() {
    load_config
    [ $# -gt 0 ] || fail "Provide a prompt after 'act'."
    intent_core "$*"
    perform_action "$ACTION_TYPE" "$ACTION_VALUE" "$SPOKEN"
}

prompt_once() {
    load_config
    [ $# -gt 0 ] || fail "Provide a prompt after 'prompt'."

    if local_wasm_ready; then
        "${DREAM_MOBILE_WASM_RUNNER}" "${DREAM_MOBILE_WASM_BINARY}" \
            -m "${DREAM_MOBILE_MODEL_PATH}" \
            -c "${DREAM_MOBILE_CONTEXT:-2048}" \
            -n "${DREAM_MOBILE_REPLY_TOKENS:-48}" \
            --fast-prompt \
            -p "$*"
        return 0
    fi

    intent_core "$*"
    print_json_reply "$ACTION_TYPE" "$ACTION_VALUE" "$SPOKEN" "$CONFIDENCE"
}

generate_model_text() {
    model_prompt="$1"
    "${DREAM_MOBILE_WASM_RUNNER}" "${DREAM_MOBILE_WASM_BINARY}" \
        -m "${DREAM_MOBILE_MODEL_PATH}" \
        -c "${DREAM_MOBILE_CONTEXT:-2048}" \
        -n "${DREAM_MOBILE_CHAT_REPLY_TOKENS:-64}" \
        --fast-prompt \
        -p "$model_prompt"
}

cleanup_model_reply() {
    printf '%s' "$1" \
        | tr -d '\r' \
        | sed '/^<think>/d; /^<\/think>/d; s/^Assistant:[[:space:]]*//; s/^assistant>[[:space:]]*//'
}

build_agent_prompt() {
    last_user="$1"
    last_assistant="$2"
    current_user="$3"
    cat <<EOF
Voce e um assistente util no iPhone.
Responda no mesmo idioma do usuario.
Seja curto, direto e natural.
Nao mostre raciocinio interno.

Ultima troca:
User: $last_user
Assistant: $last_assistant

User: $current_user
Assistant:
EOF
}

handle_chat_email_turn() {
    user_input="$1"
    tab_char=$(printf '\t')

    if [ -n "${CHAT_PENDING_EMAIL_TO:-}" ]; then
        topic_hint="$user_input"
        generated=$(generate_email_draft_with_model "$user_input" "$CHAT_PENDING_EMAIL_TO" "$topic_hint")
        email_subject=${generated%%"$tab_char"*}
        if [ "$email_subject" = "$generated" ]; then
            email_body=""
        else
            email_body=${generated#*"$tab_char"}
        fi
        [ -n "$email_subject" ] || email_subject="Mensagem do Dream Server"
        [ -n "$email_body" ] || email_body="Oi! Estou te enviando esta mensagem criada no Dream Server."

        ACTION_TYPE="compose_email"
        ACTION_VALUE=$(printf '%s\t%s\t%s' "$CHAT_PENDING_EMAIL_TO" "$email_subject" "$email_body")
        SPOKEN="Preparei um rascunho de email para $CHAT_PENDING_EMAIL_TO."
        CHAT_PENDING_EMAIL_TO=""
        CHAT_PENDING_MODE=""
        return 0
    fi

    if ! looks_like_email_request "$user_input"; then
        return 1
    fi

    email_to=$(extract_email_address "$user_input")
    if [ -z "$email_to" ]; then
        CHAT_PENDING_MODE="email_to"
        CHAT_PENDING_EMAIL_TO=""
        ACTION_TYPE="reply"
        ACTION_VALUE="Qual email do destinatario?"
        SPOKEN="$ACTION_VALUE"
        return 0
    fi

    email_subject=$(extract_email_subject "$user_input")
    email_body=$(extract_email_body "$user_input")
    email_topic=$(extract_email_topic "$user_input")

    if [ -z "$email_body" ] && [ -z "$email_topic" ]; then
        CHAT_PENDING_MODE="email_body"
        CHAT_PENDING_EMAIL_TO="$email_to"
        ACTION_TYPE="reply"
        ACTION_VALUE="O que voce quer que eu escreva no email para $email_to?"
        SPOKEN="$ACTION_VALUE"
        return 0
    fi

    generated=$(generate_email_draft_with_model "$user_input" "$email_to" "$email_topic")
    if [ -n "$generated" ]; then
        email_subject=${generated%%"$tab_char"*}
        if [ "$email_subject" = "$generated" ]; then
            email_body=""
        else
            email_body=${generated#*"$tab_char"}
        fi
    fi

    [ -n "$email_subject" ] || email_subject="Mensagem do Dream Server"
    [ -n "$email_body" ] || email_body="Oi! Estou te enviando esta mensagem criada no Dream Server."

    ACTION_TYPE="compose_email"
    ACTION_VALUE=$(printf '%s\t%s\t%s' "$email_to" "$email_subject" "$email_body")
    SPOKEN="Preparei um rascunho de email para $email_to."
    return 0
}

interactive_chat_agent() {
    load_config
    if ! local_wasm_ready; then
        fail "Interactive chat on iOS still needs a linked wasm runtime at ${DREAM_MOBILE_WASM_BINARY:-<unset>}. Run 'sh ./dream-mobile.sh doctor' for the current blocker and host build helper."
    fi

    last_user=""
    last_assistant=""
    CHAT_PENDING_MODE=""
    CHAT_PENDING_EMAIL_TO=""

    printf '%s\n' "Dream Server smart chat. Type /exit to leave."
    printf '%s\n' "Action requests like 'manda um email...' will be routed automatically."

    while true; do
        printf 'you> '
        IFS= read -r user_input || break
        user_input=$(trim_text "$user_input")
        [ -n "$user_input" ] || continue

        case "$user_input" in
            /exit|exit|quit)
                break
                ;;
        esac

        if [ "${CHAT_PENDING_MODE:-}" = "email_to" ]; then
            maybe_email=$(extract_email_address "$user_input")
            if [ -z "$maybe_email" ]; then
                printf 'assistant> %s\n' "Ainda preciso do email do destinatario."
                continue
            fi
            CHAT_PENDING_MODE="email_body"
            CHAT_PENDING_EMAIL_TO="$maybe_email"
            printf 'assistant> %s\n' "Certo. O que voce quer que eu escreva para $maybe_email?"
            continue
        fi

        if handle_chat_email_turn "$user_input"; then
            case "$ACTION_TYPE" in
                compose_email|open_url|run_shortcut)
                    perform_action "$ACTION_TYPE" "$ACTION_VALUE" "$SPOKEN"
                    last_user="$user_input"
                    last_assistant="$SPOKEN"
                    ;;
                reply)
                    printf 'assistant> %s\n' "$SPOKEN"
                    last_user="$user_input"
                    last_assistant="$SPOKEN"
                    ;;
            esac
            continue
        fi

        intent_core "$user_input"
        case "$ACTION_TYPE" in
            compose_email|open_url|run_shortcut)
                perform_action "$ACTION_TYPE" "$ACTION_VALUE" "$SPOKEN"
                last_user="$user_input"
                last_assistant="$SPOKEN"
                continue
                ;;
        esac

        agent_prompt=$(build_agent_prompt "$last_user" "$last_assistant" "$user_input")
        raw_reply=$(generate_model_text "$agent_prompt")
        clean_reply=$(cleanup_model_reply "$raw_reply")
        clean_reply=$(trim_text "$clean_reply")
        [ -n "$clean_reply" ] || clean_reply="Nao consegui responder direito agora. Tente reformular em uma frase curta."

        printf 'assistant> %s\n' "$clean_reply"
        last_user="$user_input"
        last_assistant="$clean_reply"
    done
}

interactive_chat_raw() {
    load_config
    if ! local_wasm_ready; then
        fail "Interactive chat on iOS still needs a linked wasm runtime at ${DREAM_MOBILE_WASM_BINARY:-<unset>}. Run 'sh ./dream-mobile.sh doctor' for the current blocker and host build helper."
    fi

    exec "${DREAM_MOBILE_WASM_RUNNER}" "${DREAM_MOBILE_WASM_BINARY}" \
        -m "${DREAM_MOBILE_MODEL_PATH}" \
        -c "${DREAM_MOBILE_CONTEXT:-2048}" \
        -n "${DREAM_MOBILE_CHAT_REPLY_TOKENS:-64}" \
        --history "${DREAM_MOBILE_HISTORY_MESSAGES:-1}" \
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
        -n "${DREAM_MOBILE_CHAT_REPLY_TOKENS:-64}" \
        --history "${DREAM_MOBILE_HISTORY_MESSAGES:-1}" \
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
    act)
        shift
        act_once "$@"
        ;;
    prompt)
        shift
        prompt_once "$@"
        ;;
    chat)
        shift
        interactive_chat_raw "$@"
        ;;
    chat-agent)
        shift
        interactive_chat_agent "$@"
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
