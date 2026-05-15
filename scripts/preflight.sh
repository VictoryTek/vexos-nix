#!/usr/bin/env bash
# =============================================================================
# preflight.sh — vexos-nix Pre-Push Validation Script
# Project: vexos-nix — Personal NixOS Flake (NixOS 25.11)
# Purpose: Validate flake structure, system closure, git hygiene, and code
#          quality before pushing changes to GitHub.
# Usage:   Run from repository root: bash scripts/preflight.sh
#
# Stages:
#   [0/7] Nix + jq availability
#   [1/7] nix flake check
#   [2/7] Dry-build all variants (30 outputs)
#   [3/7] hardware-configuration.nix not tracked
#   [4/7] system.stateVersion (all 5 configuration-*.nix files)
#   [5/7] flake.lock validation (committed, pinned, freshness)
#   [6/7] Nix formatting
#   [7/7] Secret scan
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
# ---------- CHECK 0: Nix + jq availability (HARD for nix, WARN for jq) ------
echo "[0/7] Checking for required tools..."
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

# Check for jq — required for flake.lock validation stages
HAS_JQ=0
if command -v jq &>/dev/null; then
  HAS_JQ=1
  pass "jq $(jq --version 2>/dev/null)"
else
  warn "jq not found — flake.lock pinning and freshness checks will be skipped"
fi
echo ""
# ---------- CHECK 1: nix flake check (HARD / WARN if no hw-config) ----------
# --impure is required because hardware-configuration.nix is intentionally
# kept at /etc/nixos/ (generated per-host, not tracked in this repo).
# If the host has not yet run nixos-generate-config the check is downgraded to
# a warning so the preflight can still pass on fresh dev machines.
echo "[1/7] Validating flake structure..."
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
echo "[2/7] Verifying system closures (dry-build all variants)..."

# Dynamically enumerate all nixosConfigurations output names.
# --impure is required because hardware-configuration.nix lives at /etc/nixos/.
TARGETS=""
if [ -f /etc/nixos/hardware-configuration.nix ]; then
  TARGETS=$(nix eval --impure --json '.#nixosConfigurations' --apply builtins.attrNames 2>/dev/null \
    | jq -r '.[]' 2>/dev/null || true)
fi

# Fallback: hardcoded list if dynamic enumeration failed or jq unavailable.
if [ -z "$TARGETS" ]; then
  TARGETS="vexos-desktop-amd vexos-desktop-nvidia vexos-desktop-nvidia-legacy535 vexos-desktop-nvidia-legacy470 vexos-desktop-intel vexos-desktop-vm
vexos-htpc-amd vexos-htpc-nvidia vexos-htpc-nvidia-legacy535 vexos-htpc-nvidia-legacy470 vexos-htpc-intel vexos-htpc-vm
vexos-server-amd vexos-server-nvidia vexos-server-nvidia-legacy535 vexos-server-nvidia-legacy470 vexos-server-intel vexos-server-vm
vexos-headless-server-amd vexos-headless-server-nvidia vexos-headless-server-nvidia-legacy535 vexos-headless-server-nvidia-legacy470 vexos-headless-server-intel vexos-headless-server-vm
vexos-stateless-amd vexos-stateless-nvidia vexos-stateless-nvidia-legacy535 vexos-stateless-nvidia-legacy470 vexos-stateless-intel vexos-stateless-vm
vexos-vanilla-amd vexos-vanilla-nvidia vexos-vanilla-intel vexos-vanilla-vm"
fi

TARGET_COUNT=$(echo "$TARGETS" | wc -w)
echo "  Discovered ${TARGET_COUNT} nixosConfigurations outputs"

if [ ! -f /etc/nixos/hardware-configuration.nix ]; then
  warn "Skipping dry-build — /etc/nixos/hardware-configuration.nix not found."
  warn "Run 'sudo nixos-generate-config' on the target host and retry."
elif command -v nixos-rebuild &>/dev/null && sudo -n true 2>/dev/null; then
  DRY_FAIL=0
  for TARGET in $TARGETS; do
    if sudo nixos-rebuild dry-build --flake ".#${TARGET}" 2>&1; then
      pass "nixos-rebuild dry-build .#${TARGET} passed"
    else
      fail "nixos-rebuild dry-build .#${TARGET} failed"
      DRY_FAIL=1
    fi
  done
  if [ "$DRY_FAIL" -ne 0 ]; then
    EXIT_CODE=1
  fi
else
  # nixos-rebuild not available or sudo not functional (e.g. developing on a
  # non-NixOS host, or running in a container/CI without sudo).
  # Fall back to nix build --dry-run which evaluates the full closure without sudo.
  if command -v nixos-rebuild &>/dev/null; then
    warn "sudo not available — falling back to 'nix build --dry-run' for each variant"
  else
    warn "nixos-rebuild not found — falling back to 'nix build --dry-run' for each variant"
  fi
  DRY_FAIL=0
  for TARGET in $TARGETS; do
    if nix build --dry-run --impure ".#nixosConfigurations.${TARGET}.config.system.build.toplevel" 2>&1; then
      pass "nix build --dry-run .#${TARGET} passed"
    else
      fail "nix build --dry-run .#${TARGET} failed"
      DRY_FAIL=1
    fi
  done
  if [ "$DRY_FAIL" -ne 0 ]; then
    EXIT_CODE=1
  fi
fi
echo ""

# ---------- CHECK 3: hardware-configuration.nix not tracked (HARD) -----------
echo "[3/7] Checking hardware-configuration.nix is not tracked in git..."
if git ls-files hardware-configuration.nix | grep -q .; then
  fail "hardware-configuration.nix is tracked in git — remove it immediately"
  EXIT_CODE=1
else
  pass "hardware-configuration.nix is not tracked"
fi
echo ""

# ---------- CHECK 4: system.stateVersion present (HARD) ----------------------
echo "[4/7] Verifying system.stateVersion in all configuration files..."
STATEVER_FAIL=0
for CFG in \
  configuration-desktop.nix \
  configuration-htpc.nix \
  configuration-server.nix \
  configuration-headless-server.nix \
  configuration-stateless.nix \
  configuration-vanilla.nix; do
  if [ ! -f "$CFG" ]; then
    fail "$CFG does not exist"
    STATEVER_FAIL=1
  elif grep -q 'system\.stateVersion' "$CFG"; then
    pass "system.stateVersion is present in $CFG"
  else
    fail "system.stateVersion is missing from $CFG"
    STATEVER_FAIL=1
  fi
done
if [ "$STATEVER_FAIL" -ne 0 ]; then
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

# ---------- CHECK 5: flake.lock validation (WARN / HARD for pinning) ---------
echo "[5/7] Validating flake.lock..."
echo "  --- 5a: flake.lock committed ---"
if ! test -f flake.lock; then
  warn "flake.lock does not exist — run: nix flake lock"
elif git ls-files flake.lock | grep -q .; then
  pass "flake.lock is tracked in git"
else
  warn "flake.lock exists but is not tracked by git — run: git add flake.lock"
fi

echo "  --- 5b: flake.lock pinned inputs ---"
if [ "$HAS_JQ" -eq 1 ] && [ -f flake.lock ]; then
  # Every non-root node that has a "locked" field must also have "locked.rev".
  UNPINNED=$(jq -r '
    .nodes | to_entries[]
    | select(.key != "root")
    | select(.value.locked != null)
    | select(.value.locked.rev == null)
    | .key
  ' flake.lock 2>/dev/null || true)
  if [ -n "$UNPINNED" ]; then
    fail "Unpinned inputs found in flake.lock (missing locked.rev):"
    echo "$UNPINNED" | while read -r name; do
      echo "    - $name"
    done
    EXIT_CODE=1
  else
    pass "All flake.lock inputs have pinned revisions"
  fi
elif [ "$HAS_JQ" -eq 0 ]; then
  warn "Skipping flake.lock pinning check — jq not available"
else
  warn "Skipping flake.lock pinning check — flake.lock not found"
fi

echo "  --- 5c: flake.lock freshness ---"
# Configurable thresholds (days).
FRESHNESS_WARN_DAYS=${PREFLIGHT_FRESHNESS_WARN:-30}
FRESHNESS_ERROR_DAYS=${PREFLIGHT_FRESHNESS_ERROR:-90}

if [ "$HAS_JQ" -eq 1 ] && [ -f flake.lock ]; then
  NOW_EPOCH=$(date +%s)
  STALE_WARN=""
  STALE_ERR=""

  # Check lastModified of each direct input (root's inputs).
  DIRECT_INPUTS=$(jq -r '.nodes.root.inputs | .[] | if type == "array" then .[] else . end' flake.lock 2>/dev/null | sort -u || true)

  for INPUT_NAME in $DIRECT_INPUTS; do
    LAST_MOD=$(jq -r --arg n "$INPUT_NAME" '.nodes[$n].locked.lastModified // empty' flake.lock 2>/dev/null || true)
    [ -n "$LAST_MOD" ] || continue
    AGE_DAYS=$(( (NOW_EPOCH - LAST_MOD) / 86400 ))
    if [ "$AGE_DAYS" -gt "$FRESHNESS_ERROR_DAYS" ]; then
      STALE_ERR="${STALE_ERR}    - ${INPUT_NAME}: ${AGE_DAYS} days old\n"
    elif [ "$AGE_DAYS" -gt "$FRESHNESS_WARN_DAYS" ]; then
      STALE_WARN="${STALE_WARN}    - ${INPUT_NAME}: ${AGE_DAYS} days old\n"
    fi
  done

  if [ -n "$STALE_ERR" ]; then
    warn "Inputs older than ${FRESHNESS_ERROR_DAYS} days (consider 'nix flake update'):"
    echo -e "$STALE_ERR"
  fi
  if [ -n "$STALE_WARN" ]; then
    warn "Inputs older than ${FRESHNESS_WARN_DAYS} days:"
    echo -e "$STALE_WARN"
  fi
  if [ -z "$STALE_ERR" ] && [ -z "$STALE_WARN" ]; then
    pass "All direct inputs updated within ${FRESHNESS_WARN_DAYS} days"
  fi
elif [ "$HAS_JQ" -eq 0 ]; then
  warn "Skipping flake.lock freshness check — jq not available"
else
  warn "Skipping flake.lock freshness check — flake.lock not found"
fi
echo ""

# ---------- CHECK 6: Nix formatting (WARN) -----------------------------------
echo "[6/7] Checking Nix formatting..."
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
echo "[7/7] Scanning tracked .nix files for hardcoded secrets..."
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
