#!/usr/bin/env bash
# ============================================================================
# Dream Server Windows doctor command tests
# ============================================================================
# Static checks for the Windows dream.ps1 "doctor" command wiring.
# ============================================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
DREAM_PS1="$ROOT_DIR/installers/windows/dream.ps1"
DOCTOR_LIB="$ROOT_DIR/installers/windows/lib/doctor.ps1"

GREEN='\033[0;32m'
RED='\033[0;31m'
NC='\033[0m'
PASS=0
FAIL=0

pass() { echo -e "  ${GREEN}PASS${NC} $1"; PASS=$((PASS + 1)); }
fail() { echo -e "  ${RED}FAIL${NC} $1"; FAIL=$((FAIL + 1)); }

echo ""
echo "=== Windows doctor command tests ==="
echo ""

[[ -f "$DREAM_PS1" ]] && pass "dream.ps1 exists" || fail "dream.ps1 missing"
[[ -f "$DOCTOR_LIB" ]] && pass "doctor.ps1 exists" || fail "doctor.ps1 missing"

grep -q "doctor.ps1" "$DREAM_PS1" && pass "dream.ps1 sources doctor library" || fail "dream.ps1 missing doctor library source"
grep -q '\[switch\]\$Json' "$DREAM_PS1" && pass "dream.ps1 accepts -Json/--json" || fail "top-level Json switch missing"
grep -q '\[string\]\$Report' "$DREAM_PS1" && pass "dream.ps1 accepts -Report/--report" || fail "top-level Report parameter missing"
grep -q "function Invoke-DoctorCommand" "$DREAM_PS1" && pass "Invoke-DoctorCommand exists" || fail "Invoke-DoctorCommand missing"
grep -q '"doctor".*Invoke-DoctorCommand' "$DREAM_PS1" && pass "doctor command dispatch exists" || fail "doctor dispatch missing"
grep -q '"diag".*Invoke-DoctorCommand' "$DREAM_PS1" && pass "diag alias dispatch exists" || fail "diag alias missing"
grep -q "Run readiness diagnostics" "$DREAM_PS1" && pass "help text includes doctor command" || fail "help text missing doctor command"

grep -q "function New-DreamDoctorReport" "$DOCTOR_LIB" && pass "doctor report builder exists" || fail "doctor report builder missing"
grep -q "function Invoke-DreamDoctor" "$DOCTOR_LIB" && pass "doctor command function exists" || fail "doctor command function missing"
grep -q "Test-DreamDockerImage" "$DOCTOR_LIB" && pass "doctor validates Docker images" || fail "docker image check missing"
grep -q "Test-DreamTcpPort" "$DOCTOR_LIB" && pass "doctor checks ports" || fail "port check missing"
grep -q "missing_required_keys" "$DOCTOR_LIB" && pass "doctor checks .env required keys" || fail ".env key check missing"
grep -q "models_dir_writable" "$DOCTOR_LIB" && pass "doctor checks model directory permissions" || fail "permissions check missing"

echo ""
echo "Result: $PASS passed, $FAIL failed"
[[ $FAIL -eq 0 ]]
