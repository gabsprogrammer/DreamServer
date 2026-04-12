#!/bin/sh

# Root wrapper for Dream Server mobile preview.
# On iOS / a-Shell, jump straight to the dedicated CLI to avoid extra wrapper
# layers and shell-specific quirks.

SCRIPT_DIR="$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)"
IOS_CLI="$SCRIPT_DIR/dream-server/installers/mobile/ios-ashell-cli.sh"
INNER="$SCRIPT_DIR/dream-server/dream-mobile.sh"

if [ -f "$IOS_CLI" ]; then
    exec sh "$IOS_CLI" "$@"
fi

if [ ! -f "$INNER" ]; then
    echo "Dream Server mobile wrapper not found: $INNER" >&2
    exit 1
fi

exec sh "$INNER" "$@"
