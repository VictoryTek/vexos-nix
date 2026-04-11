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
# ---------- CHECK 0: Nix binary availability (HARD) -------------------------
echo "[0/9] Checking for Nix installation..."
if ! command -v nix &>/dev/null; then
  echo ""
  fail "nix is not installed or not in PATH"
  echo ""
  echo "  Nix is required to run this preflight script."
  echo "  On WSL2 Ubuntu (or any Linux), install Nix via Determinate Systems:"
  echo ""
  echo "    curl --proto '=https' --tlsv1.2 -sSf -L \\"
  echo "      https://install.determinate.systems/nix | sh -s -- install"
  echo ""
  echo "  After installation, restart your terminal or run:"
  echo "    . /nix/var/nix/profiles/default/etc/profile.d/nix-daemon.sh"
  echo ""
  echo "  GitHub Actions CI runs this check automatically via cachix/install-nix-action."
  echo "  See: .github/workflows/ci.yml"
  echo ""
  exit 1
fi
pass "nix $(nix --version 2>/dev/null | head -1 | sed 's/nix (Nix) //')"
echo ""
# ---------- CHECK 1: nix flake check (HARD / WARN if no hw-config) ----------
# --impure is required because hardware-configuration.nix is intentionally
# kept at /etc/nixos/ (generated per-host, not tracked in this repo).
# If the host has not yet run nixos-generate-config the check is downgraded to
# a warning so the preflight can still pass on fresh dev machines.
echo "[1/9] Validating flake structure..."
if [ ! -f /etc/nixos/hardware-configuration.nix ]; then
  warn "Skipping nix flake check — /etc/nixos/hardware-configuration.nix not found."
  warn "Run 'sudo nixos-generate-config' on the target host and retry."
else
  if nix flake check --no-build --impure --show-trace 2>&1; then
    pass "nix flake check passed"
  else
    fail "nix flake check failed"
    EXIT_CODE=1
  fi
fi
echo ""

# ---------- CHECK 2: nixos-rebuild dry-build (HARD / WARN if no hw-config) ---
echo "[2/9] Verifying system closures (dry-build all variants)..."
if [ ! -f /etc/nixos/hardware-configuration.nix ]; then
  warn "Skipping dry-build — /etc/nixos/hardware-configuration.nix not found."
  warn "Run 'sudo nixos-generate-config' on the target host and retry."
elif command -v nixos-rebuild &>/dev/null; then
  for TARGET in vexos-desktop-amd vexos-desktop-nvidia vexos-desktop-vm vexos-desktop-intel vexos-stateless-amd vexos-stateless-nvidia vexos-stateless-intel vexos-stateless-vm; do
    if sudo nixos-rebuild dry-build --flake ".#${TARGET}" 2>&1; then
      pass "nixos-rebuild dry-build .#${TARGET} passed"
    else
      fail "nixos-rebuild dry-build .#${TARGET} failed"
      EXIT_CODE=1
    fi
  done
else
  # nixos-rebuild not available (e.g. developing on a non-NixOS host).
  # Fall back to nix build --dry-run which evaluates the full closure without sudo.
  warn "nixos-rebuild not found — falling back to 'nix build --dry-run' for each variant"
  for TARGET in vexos-desktop-amd vexos-desktop-nvidia vexos-desktop-vm vexos-desktop-intel vexos-stateless-amd vexos-stateless-nvidia vexos-stateless-intel vexos-stateless-vm vexos-stateless-amd vexos-stateless-nvidia vexos-stateless-intel vexos-stateless-vm; do
    if nix build --dry-run --impure ".#nixosConfigurations.${TARGET}.config.system.build.toplevel" 2>&1; then
      pass "nix build --dry-run .#${TARGET} passed"
    else
      fail "nix build --dry-run .#${TARGET} failed"
      EXIT_CODE=1
    fi
  done
fi
echo ""

# ---------- CHECK 3: hardware-configuration.nix not tracked (HARD) -----------
echo "[3/9] Checking hardware-configuration.nix is not tracked in git..."
if git ls-files hardware-configuration.nix | grep -q .; then
  fail "hardware-configuration.nix is tracked in git — remove it immediately"
  EXIT_CODE=1
else
  pass "hardware-configuration.nix is not tracked"
fi
echo ""

# ---------- CHECK 4: system.stateVersion present (HARD) ----------------------
echo "[4/9] Verifying system.stateVersion in configuration.nix..."
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
echo "[5/9] Checking flake.lock freshness..."
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
echo "[6/9] Checking Nix formatting..."
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
echo "[7/9] Scanning tracked .nix files for hardcoded secrets..."
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
echo "[8/9] Verifying flake.lock is committed..."
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
