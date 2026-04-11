#!/bin/sh

if [ -z "${BASH_VERSION:-}" ]; then
    SCRIPT_DIR="$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)"
    INNER="$SCRIPT_DIR/dream-server/dream-mobile.sh"
    exec sh "$INNER" "$@"
fi

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
INNER="$SCRIPT_DIR/dream-server/dream-mobile.sh"

if [[ ! -f "$INNER" ]]; then
    echo "Dream Server mobile wrapper not found: $INNER" >&2
    exit 1
fi

exec bash "$INNER" "$@"
