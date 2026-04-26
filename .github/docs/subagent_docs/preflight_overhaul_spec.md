# Preflight Overhaul — Specification

**Feature:** preflight_overhaul
**Date:** 2026-04-26
**Status:** DRAFT

---

## 1. Current State Analysis

### Stage-by-Stage Breakdown of `scripts/preflight.sh`

| Stage | Lines | Purpose | Shortcoming |
|-------|-------|---------|-------------|
| 0 (CHECK 0) | 39–56 | Verifies `nix` binary is in PATH | None — functioning correctly |
| 1 (CHECK 1) | 57–72 | Runs `nix flake check --no-build --impure` | None — correctly downgrades to WARN when `/etc/nixos/hardware-configuration.nix` absent |
| 2 (CHECK 2) | 74–105 | Dry-builds system closures via `nixos-rebuild dry-build` (with `nix build --dry-run` fallback) | **B10**: Only lists 14 of 30 flake outputs. Missing all 6 HTPC variants, 8 NVIDIA legacy variants (2 desktop, 2 stateless, 2 server, 2 headless-server), and 2 Intel variants (server-intel, headless-server-intel). |
| 3 (CHECK 3) | 107–115 | Asserts `hardware-configuration.nix` is not tracked in git | None — functioning correctly |
| 4 (CHECK 4) | 117–124 | Asserts `system.stateVersion` is present in `configuration-desktop.nix` | **B11**: Only checks 1 of 5 `configuration-*.nix` files. |
| 5 (CHECK 5) | 132–146 | Checks flake.lock freshness | **C8**: Uses `git log -1 --format="%ct" -- flake.lock` (git commit timestamp), not actual lock content timestamps. A `git commit --amend` or `git rebase` resets the "age" to zero without updating lock content. |
| 6 (CHECK 6) | 148–158 | Checks Nix formatting via `nixpkgs-fmt` | None — functioning correctly (WARN-only) |
| 7 (CHECK 7) | 160–177 | Scans `.nix` files for hardcoded secrets | None — functioning correctly (WARN-only) |
| 8 (CHECK 8) | 179–188 | Verifies `flake.lock` is committed | None — functioning correctly (WARN-only) |
| — | 190–198 | Summary banner; exits with `EXIT_CODE` | None |

**Missing stage:** No validation that all flake inputs have pinned revisions in `flake.lock` (**C6**).

### Output Coverage Gap

Current list (14 outputs — lines 80–83 and 96–99):
```
vexos-desktop-amd  vexos-desktop-nvidia  vexos-desktop-vm  vexos-desktop-intel
vexos-stateless-amd  vexos-stateless-nvidia  vexos-stateless-intel  vexos-stateless-vm
vexos-server-amd  vexos-server-nvidia  vexos-server-vm
vexos-headless-server-amd  vexos-headless-server-nvidia  vexos-headless-server-vm
```

Full authoritative list from `flake.nix` `hostList` (30 outputs):
```
vexos-desktop-amd              vexos-desktop-nvidia
vexos-desktop-nvidia-legacy535 vexos-desktop-nvidia-legacy470
vexos-desktop-intel            vexos-desktop-vm

vexos-stateless-amd              vexos-stateless-nvidia
vexos-stateless-nvidia-legacy535 vexos-stateless-nvidia-legacy470
vexos-stateless-intel            vexos-stateless-vm

vexos-server-amd              vexos-server-nvidia
vexos-server-nvidia-legacy535 vexos-server-nvidia-legacy470
vexos-server-intel            vexos-server-vm

vexos-headless-server-amd              vexos-headless-server-nvidia
vexos-headless-server-nvidia-legacy535 vexos-headless-server-nvidia-legacy470
vexos-headless-server-intel            vexos-headless-server-vm

vexos-htpc-amd              vexos-htpc-nvidia
vexos-htpc-nvidia-legacy535 vexos-htpc-nvidia-legacy470
vexos-htpc-intel            vexos-htpc-vm
```

16 outputs are currently uncovered.

### Current stateVersion Check Scope

Only `configuration-desktop.nix` is checked (line 122). The following are unvalidated:
- `configuration-htpc.nix` (stateVersion at line 30)
- `configuration-server.nix` (stateVersion at line 31)
- `configuration-headless-server.nix` (stateVersion at line 47)
- `configuration-stateless.nix` (stateVersion at line 89)

All five files currently declare `system.stateVersion = "25.11";`.

### Current Freshness Check

Uses `git log -1 --format="%ct" -- flake.lock` which measures when the lock file was last *committed*, not when the locked inputs were actually fetched or updated. This is unreliable across rebases, amended commits, or cherry-picks.

---

## 2. Problem Definition

| Audit ID | Finding | Severity | Gap |
|----------|---------|----------|-----|
| **B10** | Dry-build covers only 14 of 30 flake outputs | HIGH | Missing all HTPC variants (6), all NVIDIA legacy variants (8), server-intel, headless-server-intel |
| **B11** | `system.stateVersion` validated for 1 of 5 configuration files | MEDIUM | 4 configuration files unchecked — a stateVersion deletion in any of them would pass preflight silently |
| **C6** | No assertion that all flake.lock entries have `locked.rev` | MEDIUM | An unpinned input (e.g. a `path:` or `git:` reference without a rev) would go undetected |
| **C8** | Lock freshness uses git mtime, not lock content timestamps | LOW | Misleading "N days old" report; rebase/amend resets the clock |

---

## 3. Proposed Solution Architecture

### Stage Map

| Stage | Name | Severity | Change |
|-------|------|----------|--------|
| 0 | Nix binary availability | HARD | **No change** |
| 0.5 | `jq` availability | HARD | **NEW** — required for stages 5b and 5c |
| 1 | `nix flake check` | HARD/WARN | **No change** |
| 2 | Dry-build all variants | HARD/WARN | **MODIFIED** — dynamically enumerate all 30 outputs |
| 3 | `hardware-configuration.nix` not tracked | HARD | **No change** |
| 4 | `system.stateVersion` present | HARD | **MODIFIED** — loop over all 5 `configuration-*.nix` |
| 5a | `flake.lock` committed | WARN | **MOVED** — was CHECK 8; logically groups with lock checks |
| 5b | `flake.lock` pinned inputs | HARD | **NEW** — validates `locked.rev` exists for every non-root node |
| 5c | `flake.lock` freshness | WARN | **MODIFIED** — uses `jq` to read `lastModified` from lock file directly |
| 6 | Nix formatting | WARN | **No change** |
| 7 | Secret scan | WARN | **No change** |
| — | Summary | — | **No change** |

Total checks renumbered: `[0/8]` through `[8/8]` (the jq check is embedded in stage 0 as a sub-check, not separately numbered — see Implementation Steps).

### Dynamic vs. Hardcoded Output Enumeration — Decision

**Decision: Dynamic enumeration via `nix eval`.**

Approach: `nix eval --impure --json '.#nixosConfigurations' --apply builtins.attrNames`

Rationale:
- `nix eval ... --apply builtins.attrNames` only needs to evaluate the flake to the point of extracting attribute names, NOT fully evaluating each system closure. This is significantly faster than `nix flake show --json` which evaluates every output.
- Self-maintaining: new outputs added to `hostList` are automatically picked up.
- Avoids the 30+ second penalty of `nix flake show`.
- Requires `--impure` (same as the existing `nix flake check` invocation) because `hardware-configuration.nix` is referenced via an impure path.
- If the eval itself fails (e.g. missing `hardware-configuration.nix`), fall back to a hardcoded list as a safety net.

Fallback hardcoded list: embedded in the script as a `FALLBACK_TARGETS` variable, kept as a last-resort if `nix eval` fails.

### Stages Preserved (No Changes)

- Stage 0: Nix binary check — identical logic and output.
- Stage 1: `nix flake check` — identical logic and output.
- Stage 3: `hardware-configuration.nix` git check — identical logic and output.
- Stage 6: Nix formatting — identical logic and output.
- Stage 7: Secret scan — identical logic and output.

---

## 4. Implementation Steps

### Step 1: Add `jq` Dependency Check (inside Stage 0)

Insert after the existing `nix` check, before the first stage that needs `jq`.

```bash
# Check for jq — required for flake.lock validation stages
HAS_JQ=0
if command -v jq &>/dev/null; then
  HAS_JQ=1
  pass "jq $(jq --version 2>/dev/null)"
else
  warn "jq not found — flake.lock pinning and freshness checks will be skipped"
fi
```

`HAS_JQ` is a flag consumed by stages 5b and 5c. Its absence is a WARN (not HARD) so that the rest of preflight can still run.

### Step 2: Modify Stage 2 — Dynamic Output Enumeration

Replace the hardcoded `for TARGET in ...` lists with dynamic discovery:

```bash
echo "[2/8] Verifying system closures (dry-build all variants)..."

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
vexos-stateless-amd vexos-stateless-nvidia vexos-stateless-nvidia-legacy535 vexos-stateless-nvidia-legacy470 vexos-stateless-intel vexos-stateless-vm"
fi

TARGET_COUNT=$(echo "$TARGETS" | wc -w)
echo "  Discovered ${TARGET_COUNT} nixosConfigurations outputs"

if [ ! -f /etc/nixos/hardware-configuration.nix ]; then
  warn "Skipping dry-build — /etc/nixos/hardware-configuration.nix not found."
  warn "Run 'sudo nixos-generate-config' on the target host and retry."
elif command -v nixos-rebuild &>/dev/null; then
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
  warn "nixos-rebuild not found — falling back to 'nix build --dry-run' for each variant"
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
```

### Step 3: Modify Stage 4 — All 5 Configuration Files

Replace the single-file check with a loop:

```bash
echo "[4/8] Verifying system.stateVersion in all configuration files..."
STATEVER_FAIL=0
for CFG in \
  configuration-desktop.nix \
  configuration-htpc.nix \
  configuration-server.nix \
  configuration-headless-server.nix \
  configuration-stateless.nix; do
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
```

### Step 4: Reorganize Lock Checks — New Stages 5a, 5b, 5c

#### Stage 5a: `flake.lock` committed (moved from old CHECK 8)

```bash
echo "[5/8] Validating flake.lock..."
echo "  --- 5a: flake.lock committed ---"
if ! test -f flake.lock; then
  warn "flake.lock does not exist — run: nix flake lock"
elif git ls-files flake.lock | grep -q .; then
  pass "flake.lock is tracked in git"
else
  warn "flake.lock exists but is not tracked by git — run: git add flake.lock"
fi
```

#### Stage 5b: `flake.lock` pinned inputs (NEW — addresses C6)

```bash
echo "  --- 5b: flake.lock pinned inputs ---"
if [ "$HAS_JQ" -eq 1 ] && [ -f flake.lock ]; then
  # Every non-root node that has an "original" field must also have "locked.rev".
  # The root node has no "locked" — that is expected.
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
```

#### Stage 5c: `flake.lock` freshness (MODIFIED — addresses C8)

```bash
echo "  --- 5c: flake.lock freshness ---"
# Configurable thresholds (days).
FRESHNESS_WARN_DAYS=${PREFLIGHT_FRESHNESS_WARN:-30}
FRESHNESS_ERROR_DAYS=${PREFLIGHT_FRESHNESS_ERROR:-90}

if [ "$HAS_JQ" -eq 1 ] && [ -f flake.lock ]; then
  NOW_EPOCH=$(date +%s)
  STALE_WARN=""
  STALE_ERR=""

  # Check lastModified of each direct input (root's inputs).
  DIRECT_INPUTS=$(jq -r '.nodes.root.inputs | values | if type == "array" then .[] else . end' flake.lock 2>/dev/null | sort -u || true)

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
```

**Note:** Freshness is always WARN-level, never HARD failure. The `FRESHNESS_ERROR_DAYS` threshold uses `warn`, not `fail`, because stale locks are a maintenance signal, not a correctness issue. Environment variables `PREFLIGHT_FRESHNESS_WARN` and `PREFLIGHT_FRESHNESS_ERROR` allow CI or user override.

### Step 5: Renumber Remaining Stages

With the reorganization:
- Stage 0: Nix + jq availability
- Stage 1: `nix flake check`
- Stage 2: Dry-build all variants
- Stage 3: `hardware-configuration.nix` not tracked
- Stage 4: `system.stateVersion` (all 5 files)
- Stage 5: `flake.lock` validation (5a committed, 5b pinned, 5c freshness)
- Stage 6: Nix formatting
- Stage 7: Secret scan

The header counters become `[0/7]` through `[7/7]`. The old CHECK 8 (`flake.lock` committed) is absorbed into stage 5a.

### Step 6: Preserve Early Exit

The early-exit gate after CHECK 4 (line 127–131 in current script) remains between stage 4 and stage 5. Stages 5–7 are advisory (WARN) and run only if no HARD failures occurred in stages 0–4.

### Step 7: Update Header Comment

Update the stage count in the header comment and adjust the `NixOS 25.11` reference to remain accurate.

---

## 5. Backward Compatibility

| Scenario | Behavior |
|----------|----------|
| Machine WITH `/etc/nixos/hardware-configuration.nix` | Full execution: flake check + all 30 dry-builds + all lock checks |
| Machine WITHOUT `/etc/nixos/hardware-configuration.nix` | Stage 1: WARN (skip flake check). Stage 2: WARN (skip dry-build). Dynamic enumeration falls back to hardcoded list (but list is unused since dry-build is skipped). All other stages run normally. |
| CI without `sudo` | Stage 2 falls back to `nix build --dry-run` (no sudo required). This is the existing behavior and is preserved. |
| Machine without `jq` | Stages 5b and 5c emit WARN and skip. All other stages run. `HAS_JQ` flag prevents any `jq` invocation. |
| Machine without `nixos-rebuild` | Stage 2 falls back to `nix build --dry-run --impure`. This is the existing behavior and is preserved. |
| Machine without `nixpkgs-fmt` | Stage 6: WARN and skip. Existing behavior preserved. |

---

## 6. Dependencies

| Dependency | Required? | Used By | Fallback |
|------------|-----------|---------|----------|
| `nix` | YES (HARD) | Stages 0–2 | Script exits immediately if absent |
| `jq` | Recommended (WARN) | Stages 2 (dynamic enum), 5b, 5c | Stage 2 falls back to hardcoded list; 5b/5c skip with WARN |
| `git` | YES (implicit) | Stages 3, 5a, 7 | Already implicitly required; repo context assumed |
| `sudo` | Optional | Stage 2 (`nixos-rebuild`) | Falls back to `nix build --dry-run` |
| `nixos-rebuild` | Optional | Stage 2 | Falls back to `nix build --dry-run` |
| `nixpkgs-fmt` | Optional | Stage 6 | WARN and skip |
| `grep`, `date`, `wc` | YES (POSIX) | Various | Standard POSIX tools; always available on NixOS |

The script checks for `jq` availability at stage 0 and sets `HAS_JQ=0|1`. No `jq` invocation occurs when `HAS_JQ=0`.

---

## 7. Risks and Mitigations

| Risk | Impact | Likelihood | Mitigation |
|------|--------|------------|------------|
| `nix eval --apply builtins.attrNames` still triggers partial evaluation and is slow if flake has eval errors | Stage 2 takes 15–30s instead of instant | Medium | Hardcoded fallback list ensures stage 2 always has a target list; timeout via `|| true` prevents hang |
| `jq` not installed on a minimal NixOS system | Stages 5b/5c silently skip | Low (jq is in most NixOS profiles) | `HAS_JQ` flag with WARN message; user instructed to install jq |
| Dynamic enumeration returns fewer outputs than expected (partial eval error) | Some outputs not validated | Low | Script prints `TARGET_COUNT` so discrepancy is immediately visible; fallback list covers all 30 |
| `nix flake metadata --json` is slow | N/A — not used | N/A | Avoided by reading `flake.lock` directly with `jq` instead |
| `flake.lock` format changes in future Nix versions | `jq` queries break | Very Low | Lock file format v7 is stable; queries are defensive with `// empty` fallback |
| `lastModified` epoch values differ between inputs | False staleness warnings | Low | Only direct inputs (root's inputs) are checked; transitive inputs ignored |
| Running 30 dry-builds in sequence takes a long time | Preflight wall-clock ~10–15 min | High | This is inherent to validating all closures; could be parallelized in future but out of scope |

---

## 8. Out of Scope

- Creating or modifying CI/CD workflows (GitHub Actions / GitLab CI).
- Modifying `flake.nix`, `flake.lock`, or any Nix module file.
- Adding `nixpkgs-fmt` or `alejandra` as a hard dependency (the lint stage remains WARN-only).
- Parallelizing dry-builds (future optimization).
- Adding new preflight stages beyond those specified (e.g. disk space checks, network reachability).

---

## 9. Validation Plan

### Pre-deployment Testing

1. **Output coverage**: Run the new script and verify it prints `Discovered 30 nixosConfigurations outputs` (or the expected count at time of testing).
2. **All 30 dry-builds attempted**: Confirm output contains a PASS or FAIL line for each of the 30 output names listed in Section 1.
3. **stateVersion validation**: Verify 5 PASS lines, one per `configuration-*.nix` file.
4. **flake.lock pinning**: Verify PASS (all current inputs have `locked.rev`).
5. **flake.lock freshness**: Verify per-input age reporting using `lastModified`, not git mtime.
6. **jq-absent mode**: Temporarily move `jq` out of PATH and confirm stages 5b/5c emit WARN and the script completes.
7. **No-hardware-config mode**: Rename `/etc/nixos/hardware-configuration.nix` temporarily and confirm stages 1 and 2 emit WARN and the script completes with exit 0 (assuming no other HARD failures).

### Regression Checks

- Stages 0, 1, 3, 6, 7 output should be byte-identical to current script output under normal conditions.
- Exit code behavior: any HARD failure still results in non-zero exit; WARN-only runs still exit 0.
- The early-exit gate after stage 4 still triggers if any HARD failure occurred in stages 0–4.
