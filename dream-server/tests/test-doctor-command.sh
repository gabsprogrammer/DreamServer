#!/usr/bin/env bash
# Test suite for dream doctor command

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"

RED='\033[0;31m'
GREEN='\033[0;32m'
BLUE='\033[0;34m'
NC='\033[0m'

PASSED=0
FAILED=0

pass() { echo -e "${GREEN}✓${NC} $1"; ((PASSED++)) || true; }
fail() { echo -e "${RED}✗${NC} $1"; ((FAILED++)) || true; }

echo -e "${BLUE}━━━ Dream Doctor Command Tests ━━━${NC}"
echo ""

# Test 1: cmd_doctor function exists
if grep -q "^cmd_doctor()" "$ROOT_DIR/dream-cli"; then
    pass "cmd_doctor function defined"
else
    fail "cmd_doctor not found"
fi

# Test 2: doctor command registered
if grep -q "doctor|diag|d)" "$ROOT_DIR/dream-cli"; then
    pass "doctor command registered"
else
    fail "doctor not registered"
fi

# Test 3: --json flag support
if grep -q "json_mode" "$ROOT_DIR/dream-cli"; then
    pass "--json flag implemented"
else
    fail "--json not found"
fi

# Test 4: Python parsing
if grep -q "python3.*report_file" "$ROOT_DIR/dream-cli"; then
    pass "Python JSON parsing"
else
    fail "parsing not found"
fi

# Test 5: Exit code handling
if grep -q "exit_code=\|return \$exit_code" "$ROOT_DIR/dream-cli"; then
    pass "exit code handling"
else
    fail "exit codes missing"
fi

# Test 6: Runtime checks display
if grep -q "Runtime Environment" "$ROOT_DIR/dream-cli"; then
    pass "runtime checks display"
else
    fail "runtime display missing"
fi

# Test 7: Preflight checks display
if grep -q "Preflight Checks" "$ROOT_DIR/dream-cli"; then
    pass "preflight checks display"
else
    fail "preflight display missing"
fi

# Test 8: Autofix hints display
if grep -q "Suggested Fixes" "$ROOT_DIR/dream-cli"; then
    pass "autofix hints display"
else
    fail "hints display missing"
fi

# Test 9: Help text updated
if grep -q "doctor.*diagnostics" "$ROOT_DIR/dream-cli"; then
    pass "help text updated"
else
    fail "help not updated"
fi

# Test 10: dream-doctor.sh exists
if [[ -f "$ROOT_DIR/scripts/dream-doctor.sh" ]]; then
    pass "dream-doctor.sh exists"
else
    fail "script not found"
fi

# Test 11: Bash syntax valid
if bash -n "$ROOT_DIR/dream-cli" 2>/dev/null; then
    pass "bash syntax valid"
else
    fail "syntax errors"
fi

# Test 12: Report file configurable
if grep -q "report_file=" "$ROOT_DIR/dream-cli"; then
    pass "report file configurable"
else
    fail "not configurable"
fi

echo ""
echo -e "${BLUE}━━━ Test Summary ━━━${NC}"
echo ""
echo -e "  ${GREEN}Passed:${NC} $PASSED"
[[ $FAILED -gt 0 ]] && echo -e "  ${RED}Failed:${NC} $FAILED"
echo ""

if [[ $FAILED -eq 0 ]]; then
    echo -e "${GREEN}✓ All tests passed${NC}"
    exit 0
else
    echo -e "${RED}✗ Some tests failed${NC}"
    exit 1
fi
