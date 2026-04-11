#!/bin/bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$ROOT_DIR"

echo "[smoke] mobile dispatch and docs"
grep -q "android-termux" installers/common.sh
grep -q "ios-ashell" installers/common.sh
grep -q "mobile/install-mobile.sh" installers/dispatch.sh
grep -q "Android / Termux" docs/MOBILE-SHELL-QUICKSTART.md

echo "[smoke] PASS mobile-dispatch"
