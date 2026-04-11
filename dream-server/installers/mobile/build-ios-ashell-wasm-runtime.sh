#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
CACHE_DIR="$ROOT_DIR/.cache/ios-wasm"
LLAMA_DIR="$CACHE_DIR/llama.cpp"
RUNNER_TEMPLATE_DIR="$ROOT_DIR/installers/mobile/ios-wasm-runner"
RUNNER_DIR="$CACHE_DIR/runner"
BUILD_DIR="$CACHE_DIR/build"
LOG_DIR="$CACHE_DIR/logs"
OUT_DIR="$ROOT_DIR/mobile-runtime/ios-ashell/bin"
OUT_BIN="$OUT_DIR/llama-cli.wasm"

DOCKER_IMAGE="ghcr.io/webassembly/wasi-sdk:wasi-sdk-24"
LLAMA_REF="a29e4c0b7b23e020107058480dabbe03b7cba6e1"
RECLONE=false
DRY_RUN=false

log() {
    printf '[ios-wasm-build] %s\n' "$1"
}

fail() {
    printf '[error] %s\n' "$1" >&2
    exit 1
}

usage() {
    cat <<EOF
Build the experimental Dream Server iOS / a-Shell wasm runtime.

Usage:
  bash installers/mobile/build-ios-ashell-wasm-runtime.sh

Options:
  --llama-ref REF      Pin llama.cpp to a different git ref
  --docker-image IMG   Override the wasi-sdk image
  --reclone            Delete the cached llama.cpp clone and re-fetch it
  --dry-run            Print what would run without executing it
  -h, --help           Show this help

Output:
  $OUT_BIN
EOF
}

run_cmd() {
    if [ "$DRY_RUN" = "true" ]; then
        printf '[dry-run]'
        for arg in "$@"; do
            printf ' %s' "$arg"
        done
        printf '\n'
        return 0
    fi

    "$@"
}

parse_args() {
    while [ $# -gt 0 ]; do
        case "$1" in
            --llama-ref)
                LLAMA_REF="${2:-}"
                shift 2
                ;;
            --docker-image)
                DOCKER_IMAGE="${2:-}"
                shift 2
                ;;
            --reclone)
                RECLONE=true
                shift
                ;;
            --dry-run)
                DRY_RUN=true
                shift
                ;;
            -h|--help)
                usage
                exit 0
                ;;
            *)
                fail "Unknown option: $1"
                ;;
        esac
    done
}

require_cmd() {
    command -v "$1" >/dev/null 2>&1 || fail "Missing required command: $1"
}

prepare_dirs() {
    run_cmd mkdir -p "$CACHE_DIR" "$RUNNER_DIR" "$BUILD_DIR" "$LOG_DIR" "$OUT_DIR"
}

prepare_llama_source() {
    if [ "$RECLONE" = "true" ]; then
        run_cmd rm -rf "$LLAMA_DIR"
    fi

    if [ ! -d "$LLAMA_DIR/.git" ]; then
        log "Cloning llama.cpp into $LLAMA_DIR"
        run_cmd git clone --quiet https://github.com/ggml-org/llama.cpp.git "$LLAMA_DIR"
    fi

    log "Checking out llama.cpp ref $LLAMA_REF"
    if [ "$DRY_RUN" = "true" ]; then
        printf '[dry-run] git -C %s fetch --depth 1 origin %s\n' "$LLAMA_DIR" "$LLAMA_REF"
        printf '[dry-run] git -C %s checkout --detach %s\n' "$LLAMA_DIR" "$LLAMA_REF"
        return 0
    fi

    git -C "$LLAMA_DIR" fetch --quiet --depth 1 origin "$LLAMA_REF"
    git -C "$LLAMA_DIR" -c advice.detachedHead=false checkout --quiet --detach "$LLAMA_REF"
}

prepare_runner_template() {
    log "Refreshing the local WASI runner template"
    run_cmd mkdir -p "$RUNNER_DIR"
    run_cmd cp "$RUNNER_TEMPLATE_DIR/CMakeLists.txt" "$RUNNER_DIR/CMakeLists.txt"
    run_cmd cp "$RUNNER_TEMPLATE_DIR/main.cpp" "$RUNNER_DIR/main.cpp"
}

docker_run_build() {
    local log_file="$LOG_DIR/build.log"
    local user_args=()

    if command -v id >/dev/null 2>&1; then
        user_args=(--user "$(id -u):$(id -g)")
    fi

    if [ "$DRY_RUN" = "true" ]; then
        printf '[dry-run] docker run %s -e DREAM_LLAMA_CPP_SOURCE=/src -v %s:/src -v %s:/runner -v %s:/build %s ...\n' \
            "${user_args[*]:-}" "$LLAMA_DIR" "$RUNNER_DIR" "$BUILD_DIR" "$DOCKER_IMAGE"
        return 0
    fi

    rm -rf "$BUILD_DIR"
    mkdir -p "$BUILD_DIR"

    docker run --rm \
        "${user_args[@]}" \
        -e DREAM_LLAMA_CPP_SOURCE=/src \
        -v "$LLAMA_DIR:/src" \
        -v "$RUNNER_DIR:/runner" \
        -v "$BUILD_DIR:/build" \
        "$DOCKER_IMAGE" \
        sh -lc '
            cmake -S /runner -B /build -G Ninja \
                -DCMAKE_BUILD_TYPE=Release \
                -DCMAKE_TOOLCHAIN_FILE=/opt/wasi-sdk/share/cmake/wasi-sdk-pthread.cmake \
                -DTHREADS_PREFER_PTHREAD_FLAG=ON \
                -DThreads_FOUND=TRUE \
                -DCMAKE_THREAD_LIBS_INIT=-pthread &&
            cmake --build /build --target dream-llama-wasi -j2
        ' >"$log_file" 2>&1 || return 1
}

copy_artifact() {
    if [ "$DRY_RUN" = "true" ]; then
        printf '[dry-run] cp %s %s\n' "$BUILD_DIR/dream-llama-wasi" "$OUT_BIN"
        return 0
    fi

    [ -f "$BUILD_DIR/dream-llama-wasi" ] || fail "Build finished without producing $BUILD_DIR/dream-llama-wasi"
    run_cmd cp "$BUILD_DIR/dream-llama-wasi" "$OUT_BIN"
    log "Copied runtime to $OUT_BIN"
}

print_failure_help() {
    local log_file="$LOG_DIR/build.log"
    echo ""
    echo "Build log:"
    echo "  $log_file"

    if grep -Eq '__cxa_allocate_exception|__wasm_lpad_context|_Unwind_CallPersonality' "$log_file"; then
        echo ""
        echo "Current blocker:"
        echo "  The published wasi-sdk image can compile the Dream Server runner and most of llama.cpp,"
        echo "  but it still does not provide the full C++ exception runtime symbols that current llama.cpp"
        echo "  needs on wasm32-wasi-threads."
        echo ""
        echo "Missing symbols seen in this path include:"
        echo "  __cxa_allocate_exception"
        echo "  __cxa_throw"
        echo "  __wasm_lpad_context"
        echo "  _Unwind_CallPersonality"
        echo ""
        echo "See:"
        echo "  $ROOT_DIR/docs/IOS-ASHELL-WASM-RUNTIME.md"
        exit 2
    fi

    exit 1
}

main() {
    parse_args "$@"
    require_cmd docker
    require_cmd git
    prepare_dirs
    prepare_llama_source
    prepare_runner_template

    log "Building the experimental wasm runtime with $DOCKER_IMAGE"
    if ! docker_run_build; then
        print_failure_help
    fi

    copy_artifact
    echo ""
    echo "Next step:"
    echo "  Push or copy $OUT_BIN into the repo state that your iPhone will pull."
    echo "  Then re-run 'sh ./install.sh' or 'sh ./dream-mobile.sh status' in a-Shell."
}

main "$@"
