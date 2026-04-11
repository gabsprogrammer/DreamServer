#!/bin/sh

# Root wrapper for Dream Server mobile preview.
# Delegate to the inner wrapper using POSIX sh so iOS / a-Shell never falls
# through a bash-only path at the repo root.

SCRIPT_DIR="$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)"
INNER="$SCRIPT_DIR/dream-server/dream-mobile.sh"

if [ ! -f "$INNER" ]; then
    echo "Dream Server mobile wrapper not found: $INNER" >&2
    exit 1
fi

exec sh "$INNER" "$@"
