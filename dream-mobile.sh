#!/bin/sh

if [ -z "${BASH_VERSION:-}" ]; then
    if command -v bash >/dev/null 2>&1; then
        exec bash "$0" "$@"
    fi
    echo "[error] dream-mobile.sh requires bash." >&2
    exit 1
fi

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
INNER="$SCRIPT_DIR/dream-server/dream-mobile.sh"

if [[ ! -f "$INNER" ]]; then
    echo "Dream Server mobile wrapper not found: $INNER" >&2
    exit 1
fi

exec bash "$INNER" "$@"
