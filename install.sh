#!/bin/sh
# Dream Server Root Installer
# Delegates to dream-server/install.sh

if [ -z "${BASH_VERSION:-}" ]; then
    SCRIPT_DIR="$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)"
    if [ ! -d "$SCRIPT_DIR/dream-server" ]; then
        echo "Error: dream-server directory not found" >&2
        echo "Expected: $SCRIPT_DIR/dream-server" >&2
        exit 1
    fi
    exec sh "$SCRIPT_DIR/dream-server/install.sh" "$@"
fi

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Colors
CYAN='\033[0;36m'
NC='\033[0m'

echo -e "${CYAN}Dream Server Installer${NC}"
echo ""

# Check if dream-server directory exists
if [ ! -d "$SCRIPT_DIR/dream-server" ]; then
    echo "Error: dream-server directory not found"
    echo "Expected: $SCRIPT_DIR/dream-server"
    exit 1
fi

# Delegate to dream-server installer
cd "$SCRIPT_DIR/dream-server"
exec ./install.sh "$@"
