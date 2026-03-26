#!/usr/bin/env bash
# =============================================================================
# preflight.sh — vexos-nix Pre-Push Validation Script
# Project: vexos-nix — Personal NixOS Flake (NixOS 25.11)
# Purpose: Validate flake structure, system closure, git hygiene, and code
#          quality before pushing changes to GitHub.
# Usage:   Run from repository root: bash scripts/preflight.sh
#
# NOTE (Windows users): This script must be made executable on the NixOS host.
#   Option A — chmod:
#     chmod +x scripts/preflight.sh
#   Option B — mark executable in git before committing:
#     git update-index --chmod=+x scripts/preflight.sh
# =============================================================================

set -uo pipefail

# ---------- Color helpers ----------------------------------------------------
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
RESET='\033[0m'

pass() { echo -e "${GREEN}✓ PASS${RESET}  $1"; }
fail() { echo -e "${RED}✗ FAIL${RESET}  $1"; }
warn() { echo -e "${YELLOW}⚠ WARN${RESET}  $1"; }

EXIT_CODE=0

# ---------- Header -----------------------------------------------------------
echo ""
echo "========================================================"
echo "  vexos-nix Preflight Validation"
echo "  $(date '+%Y-%m-%d %H:%M:%S')"
echo "========================================================"
echo ""

# ---------- CHECK 1: nix flake check (HARD) ----------------------------------
echo "[1/8] Validating flake structure..."
if nix flake check 2>&1; then
  pass "nix flake check passed"
else
  fail "nix flake check failed"
  EXIT_CODE=1
fi
echo ""

# ---------- CHECK 2: nixos-rebuild dry-build (HARD) --------------------------
echo "[2/8] Verifying system closures (dry-build all variants)..."
for TARGET in vexos-amd vexos-nvidia vexos-vm vexos-intel; do
  if sudo nixos-rebuild dry-build --flake ".#${TARGET}" 2>&1; then
    pass "nixos-rebuild dry-build .#${TARGET} passed"
  else
    fail "nixos-rebuild dry-build .#${TARGET} failed"
    EXIT_CODE=1
  fi
done
echo ""

# ---------- CHECK 3: hardware-configuration.nix not tracked (HARD) -----------
echo "[3/8] Checking hardware-configuration.nix is not tracked in git..."
if git ls-files hardware-configuration.nix | grep -q .; then
  fail "hardware-configuration.nix is tracked in git — remove it immediately"
  EXIT_CODE=1
else
  pass "hardware-configuration.nix is not tracked"
fi
echo ""

# ---------- CHECK 4: system.stateVersion present (HARD) ----------------------
echo "[4/8] Verifying system.stateVersion in configuration.nix..."
if grep -q 'system\.stateVersion' configuration.nix; then
  pass "system.stateVersion is present in configuration.nix"
else
  fail "system.stateVersion is missing from configuration.nix"
  EXIT_CODE=1
fi
echo ""

# ---------- Early exit if any hard check failed ------------------------------
if [ "$EXIT_CODE" -ne 0 ]; then
  echo "========================================================"
  echo -e "${RED}Preflight FAILED — resolve hard failures before pushing.${RESET}"
  echo "========================================================"
  echo ""
  exit "$EXIT_CODE"
fi

# ---------- CHECK 5: flake.lock freshness (WARN) -----------------------------
echo "[5/8] Checking flake.lock freshness..."
LOCK_HISTORY=$(git log -1 --format="%ct" -- flake.lock 2>/dev/null || true)
if [ -z "$LOCK_HISTORY" ]; then
  warn "flake.lock has no git history — commit it with: git add flake.lock"
else
  LOCK_EPOCH="$LOCK_HISTORY"
  NOW_EPOCH=$(date +%s)
  AGE_DAYS=$(( (NOW_EPOCH - LOCK_EPOCH) / 86400 ))
  if [ "$AGE_DAYS" -gt 30 ]; then
    warn "flake.lock is ${AGE_DAYS} days old — consider running: nix flake update"
  else
    pass "flake.lock updated ${AGE_DAYS} day(s) ago"
  fi
fi
echo ""

# ---------- CHECK 6: Nix formatting (WARN) -----------------------------------
echo "[6/8] Checking Nix formatting..."
if command -v nixpkgs-fmt &>/dev/null; then
  if nixpkgs-fmt --check . 2>&1; then
    pass "Nix formatting OK"
  else
    warn "Nix formatting issues found — run nixpkgs-fmt . to fix"
  fi
else
  warn "nixpkgs-fmt not installed — skipping format check"
fi
echo ""

# ---------- CHECK 7: No hardcoded secrets (WARN) -----------------------------
echo "[7/8] Scanning tracked .nix files for hardcoded secrets..."
TRACKED_NIX=$(git ls-files '*.nix' 2>/dev/null || true)
if [ -z "$TRACKED_NIX" ]; then
  warn "No tracked .nix files found — skipping secret scan"
else
  SECRET_MATCHES=$(echo "$TRACKED_NIX" | xargs grep -rEn \
    'password[[:space:]]*=[[:space:]]*"[^"]+"|privateKey[[:space:]]*=[[:space:]]*"[^"]+"|AKIA[0-9A-Z]{16}|[aA][pP][iI][-_]?[kK][eE][yY][[:space:]]*=[[:space:]]*"[^"]+"|secret[[:space:]]*=[[:space:]]*"[^"]+"|token[[:space:]]*=[[:space:]]*"[^"]+"' \
    2>/dev/null || true)
  if [ -n "$SECRET_MATCHES" ]; then
    warn "Possible hardcoded secrets found — review the following matches:"
    echo "$SECRET_MATCHES"
  else
    pass "No hardcoded secret patterns found"
  fi
fi
echo ""

# ---------- CHECK 8: flake.lock committed (WARN) -----------------------------
echo "[8/8] Verifying flake.lock is committed..."
if ! test -f flake.lock; then
  warn "flake.lock does not exist — run: nix flake lock"
elif git ls-files flake.lock | grep -q .; then
  pass "flake.lock is tracked in git"
else
  warn "flake.lock exists but is not tracked by git — run: git add flake.lock"
fi
echo ""

# ---------- Summary ----------------------------------------------------------
echo "========================================================"
if [ "$EXIT_CODE" -eq 0 ]; then
  echo -e "${GREEN}Preflight PASSED — safe to push.${RESET}"
else
  echo -e "${RED}Preflight FAILED — resolve issues before pushing.${RESET}"
fi
echo "========================================================"
echo ""

exit "$EXIT_CODE"
