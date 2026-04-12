#!/bin/bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$ROOT_DIR"

echo "[smoke] mobile dispatch and docs"
grep -q "android-termux" installers/common.sh
grep -q "ios-ashell" installers/common.sh
grep -q "mobile/install-mobile.sh" installers/dispatch.sh
grep -q "Android / Termux" docs/MOBILE-SHELL-QUICKSTART.md
grep -q "iOS / a-Shell" docs/MOBILE-SHELL-QUICKSTART.md
grep -q "IOS-ASHELL-SHORTCUTS.md" docs/MOBILE-SHELL-QUICKSTART.md
grep -q "ios-ashell-install.sh" installers/mobile/install-mobile.sh
grep -q "intent" installers/mobile/ios-ashell-cli.sh
grep -q "open_app" installers/mobile/ios-ashell-cli.sh
grep -q "mailto_url" installers/mobile/ios-ashell-cli.sh
grep -q "act" installers/mobile/ios-ashell-cli.sh
grep -q "One-tap Email Shortcut" docs/IOS-ASHELL-SHORTCUTS.md

echo "[smoke] PASS mobile-dispatch"
