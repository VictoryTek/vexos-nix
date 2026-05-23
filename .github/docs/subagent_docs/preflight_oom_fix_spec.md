# Spec: preflight.sh OOM Fix — Three Surgical Changes

**Feature:** `preflight_oom_fix`
**Date:** 2026-05-22
**Author:** Research Subagent
**Status:** READY FOR IMPLEMENTATION

---

## 1. Problem Statement

`scripts/preflight.sh` currently contains two constructs that can exhaust all 32 GB
of RAM on the development machine:

| Stage | Problematic command | Why it OOMs |
|-------|---------------------|-------------|
| [1/7] | `nix flake check --no-build --impure --show-trace` | Evaluates **all 30+ nixosConfigurations** in parallel, loading a full nixpkgs closure per variant into RAM. |
| [2/7] | `nixos-rebuild dry-build` / `nix build --dry-run` loop over all 30 variants | Even run sequentially, 30 full closure evaluations fills 32 GB and takes 30+ minutes. |

In addition, the Stages header comment in the file banner still describes the old behaviour
and will mislead future contributors unless it is updated.

---

## 2. Source File

`scripts/preflight.sh` — read in full on 2026-05-22.

Total occurrences of the string `nix flake check` in the file: **6**, all in Stage 1 or
the Stage 1 separator comment:

| Line | Content |
|------|---------|
| 11   | `#   [1/7] nix flake check` ← CHANGE 3 covers this |
| 78   | `# ---------- CHECK 1: nix flake check (HARD / WARN if no hw-config) ----------` ← **out-of-scope residual** |
| 85   | `  warn "Skipping nix flake check — ..."` ← inside CHANGE 1 block |
| 88   | `  if nix flake check --no-build --impure --show-trace 2>&1; then` ← inside CHANGE 1 block |
| 89   | `    pass "nix flake check passed"` ← inside CHANGE 1 block |
| 91   | `    fail "nix flake check failed"` ← inside CHANGE 1 block |

Lines 85, 88, 89, 91 are all eliminated by CHANGE 1.  
Line 11 is corrected by CHANGE 3.  
**Line 78 is not covered by the three specified changes** — see Section 5 (Risks).

---

## 3. Changes

### CHANGE 1 — Stage 1: Replace `nix flake check` with `nix flake show`

#### Current text (lines 83–95)

```bash
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
```

#### Replacement text (lines 83–95, same line count ±1)

```bash
echo "[1/7] Validating flake structure..."
# NOTE: nix flake check is FORBIDDEN in this project — it evaluates all 30+
# nixosConfigurations in parallel and exhausts all 32GB of RAM.
# nix flake show is the safe alternative: it lists outputs without evaluating them.
if nix flake show --json > /dev/null 2>&1; then
  OUTPUT_COUNT=$(nix flake show --json 2>/dev/null | jq '.nixosConfigurations | length' 2>/dev/null || echo "unknown")
  pass "nix flake show passed — ${OUTPUT_COUNT} nixosConfigurations listed"
else
  fail "nix flake show failed — flake structure is invalid"
  EXIT_CODE=1
fi
echo ""
```

#### Notes

- The `hardware-configuration.nix` guard (`if [ ! -f /etc/nixos/... ]`) is removed because
  `nix flake show` does **not** evaluate NixOS closures and therefore does not require the
  host-generated hardware config to be present.
- `jq` is already verified in Stage 0 (`HAS_JQ` variable); the inline `|| echo "unknown"`
  fallback is belt-and-suspenders for environments where jq is absent despite Stage 0.
- `--json` output is piped to `/dev/null` on the pass-check invocation to avoid polluting
  the preflight log; a second invocation extracts the count.
- `--impure` is **not** required for `nix flake show`.

---

### CHANGE 2 — Stage 2: Replace full 30-variant dry-build loop with single-variant check

#### Current text (lines 98–158)

```bash
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
```

*(The separator comment on line 97 — `# ---------- CHECK 2: nixos-rebuild dry-build (HARD / WARN if no hw-config) ---` — sits
one line above the `echo "[2/7]..."` and is outside the replacement boundary. See Section 5.)*

#### Replacement text (lines 98–158, replaces entire block)

```bash
echo "[2/7] Verifying system closure (dry-build current machine variant)..."
# NOTE: Dry-building all 30 variants in a loop is FORBIDDEN in this project.
# Each evaluation loads a full nixpkgs closure into RAM. Running 30 sequentially
# still risks OOM on a 32GB machine and takes 30+ minutes.
#
# SAFE APPROACH: dry-build only the variant matching the currently running machine.
# Full multi-variant validation is delegated to GitHub Actions CI (see .github/workflows/ci.yml)
# which runs on dedicated infrastructure with sufficient RAM.

if [ ! -f /etc/nixos/vexos-variant ]; then
  warn "Skipping dry-build — /etc/nixos/vexos-variant not found."
  warn "This file is written by the VexOS installer. On a fresh machine, skip is expected."
elif [ ! -f /etc/nixos/hardware-configuration.nix ]; then
  warn "Skipping dry-build — /etc/nixos/hardware-configuration.nix not found."
  warn "Run 'sudo nixos-generate-config' on the target host and retry."
else
  CURRENT_VARIANT=$(cat /etc/nixos/vexos-variant 2>/dev/null || true)
  if [ -z "$CURRENT_VARIANT" ]; then
    warn "Skipping dry-build — /etc/nixos/vexos-variant is empty."
  else
    echo "  Dry-building current machine variant: ${CURRENT_VARIANT}"
    if sudo nixos-rebuild dry-build --flake ".#${CURRENT_VARIANT}" 2>&1; then
      pass "nixos-rebuild dry-build .#${CURRENT_VARIANT} passed"
    else
      fail "nixos-rebuild dry-build .#${CURRENT_VARIANT} failed"
      EXIT_CODE=1
    fi
  fi
fi
```

#### Notes

- `/etc/nixos/vexos-variant` is written by the VexOS installer (`scripts/install.sh`).
  On a brand-new dev machine that has never run the installer the file will not exist and
  the stage gracefully warns and skips — the preflight still passes for that stage.
- `sudo` is not conditionally detected; the replacement always uses `sudo nixos-rebuild`.
  If `sudo` is unavailable the command will fail loudly, which is the correct behaviour
  (silent skip of the only safety check is worse than an explicit failure).
- The `nix build --dry-run --impure` fallback branch is intentionally removed. That branch
  also evaluated all 30 variants and was equally OOM-prone. CI handles cross-variant coverage.
- The `TARGETS` variable, the dynamic enumeration via `nix eval --impure`, the hardcoded
  fallback list, and `TARGET_COUNT` are all eliminated — they are no longer needed.

---

### CHANGE 3 — Update Stages header comment

#### Current text (lines 11–12)

```bash
#   [1/7] nix flake check
#   [2/7] Dry-build all variants (30 outputs)
```

#### Replacement text

```bash
#   [1/7] nix flake show (structure validation — safe, low RAM)
#   [2/7] Dry-build current machine variant only (full CI validation handled by GitHub Actions)
```

#### Notes

- This is a pure comment change; no logic is affected.
- The surrounding lines (10 and 13) do not change:
  - Line 10: `#   [0/7] Nix + jq availability`
  - Line 13: `#   [3/7] hardware-configuration.nix not tracked`

---

## 4. Implementation Order

Changes are independent and may be applied in any order. Recommended order:

1. CHANGE 3 (header comment — trivial, zero-risk, confirms the intent)
2. CHANGE 1 (Stage 1 code block)
3. CHANGE 2 (Stage 2 code block — largest change)

---

## 5. Risks and Out-of-Scope Residuals

### Risk 1 — Line 78 separator comment still references `nix flake check`

**Current text (line 78):**
```
# ---------- CHECK 1: nix flake check (HARD / WARN if no hw-config) ----------
```

This line is **not** replaced by any of the three specified changes.
After CHANGE 1 is applied the separator comment will be stale.

**Recommended additional fix (outside scope of these three changes):**
```
# ---------- CHECK 1: nix flake show (structure validation — safe, low RAM) ---
```

Similarly, lines 79–82 (the `--impure` preamble comment below the separator) will
be orphaned since `nix flake show` does not require `--impure` or `hardware-configuration.nix`.
Those lines can be deleted or replaced with a single-line note, but this is editorial.

### Risk 2 — `/etc/nixos/vexos-variant` may not exist on all hosts

Addressed in the replacement: the outer `if [ ! -f /etc/nixos/vexos-variant ]` guard
skips with a `warn` (not `fail`), so the preflight still passes on machines that have
not been installed via the VexOS installer. The dry-build is best-effort on dev machines.

### Risk 3 — Stage 2 `echo ""` trailer (line 159)

Line 159 (`echo ""`) sits **after** the closing `fi` of the Stage 2 block but is not
inside the replacement boundary. It will remain in place after the replacement, which
is correct — the blank separator line between stages is preserved.

### Risk 4 — `jq` dependency in CHANGE 1 OUTPUT_COUNT line

The `nix flake show --json | jq ...` pipeline in CHANGE 1 relies on `jq` being present.
Stage 0 already validates `jq` availability and sets `HAS_JQ`. The replacement does not
guard on `HAS_JQ`, but the `|| echo "unknown"` fallback means the `pass` message will
display "unknown" rather than a count — the stage still passes. Low risk.

---

## 6. Verification Steps (for Review Subagent)

After implementation:

1. `grep -n "nix flake check" scripts/preflight.sh` — must return **only line 78** (the
   stale separator comment). Lines 85, 88, 89, 91 must be gone.
2. `grep -n "nix flake show" scripts/preflight.sh` — must return at least lines in the
   new Stage 1 block.
3. `grep -n "TARGETS\|DRY_FAIL\|TARGET_COUNT" scripts/preflight.sh` — must return **zero
   matches** (all removed by CHANGE 2).
4. `bash scripts/preflight.sh` from the repo root — must exit 0.
5. `nix flake show --json > /dev/null` — must pass independently.

---

## 7. File to Modify

| File | Lines changed |
|------|---------------|
| `scripts/preflight.sh` | 11–12 (CHANGE 3), 83–95 (CHANGE 1), 98–158 (CHANGE 2) |
