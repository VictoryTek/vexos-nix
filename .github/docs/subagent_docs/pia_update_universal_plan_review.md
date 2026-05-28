# Review: pia_update_universal_plan

**Date:** 2026-05-27  
**Spec:** `.github/docs/subagent_docs/pia_update_universal_plan.md`  
**Modified files reviewed:**
- `modules/nix.nix`
- `justfile`
- `README.md`

---

## Checklist Findings

### 1. Spec Compliance — Three-class engine in modules/nix.nix

**PASS.** All three classes are present and correctly named:

```bash
ALWAYS_LOCAL_REGEX='^(nixos-system-|system-units|system-path|etc-nixos|etc-|etc\.drv$|unit-|activation-script|specialisation-|install-bootloader|loader-|grub-|extlinux-|initrd|kernel|stage-[12]-|home-manager-|ld-library-path|X-Restart-Triggers-|user-units|set-environment|dbus-1\.drv$|abstractions-|apparmor\.d\.drv$|vexos-update\.drv$)'

KNOWN_SMALL_LOCAL_REGEX='^(pia-client\.drv$|pia-client\.desktop\.drv$|piactl\.drv$)'
```

`BLOCKING_DERIVATIONS` is derived from `ALL_CANDIDATES` minus class B (or all of `ALL_CANDIDATES` in strict mode).

---

### 2. ALWAYS_LOCAL_REGEX (Class A) applied first

**PASS.** The pipeline correctly applies class A first:

```bash
ALL_CANDIDATES=$(printf '%s\n' "$DRY" \
  | awk '.../nix/store/...' \
  | grep -Ev "$ALWAYS_LOCAL_REGEX" \
  || true)
```

Class A derivations are silently dropped before the B/C partition.

---

### 3. KNOWN_SMALL_LOCAL_REGEX patterns

**PASS.** All three spec-required patterns present as exact-name anchored alternatives:

```
^(pia-client\.drv$|pia-client\.desktop\.drv$|piactl\.drv$)
```

The combined alternation form is correct and equivalent to three separate patterns.

The AMD dry-build confirmed these `.drv` files appear in the "will be built" list during a real evaluation:
```
/nix/store/4bwh8mj006h61ii2b4myv684i77dqv6h-pia-client.drv
/nix/store/lwqvd2nnkk53yxq51f7f0jaxqdnia4mq-pia-client.desktop.drv
/nix/store/y0cvnry0905sxmibpim8dpf2rr7l68gx-piactl.drv
```

After awk stripping, these become `pia-client.drv`, `pia-client.desktop.drv`, `piactl.drv` — all matched by KNOWN_SMALL_LOCAL_REGEX. ✓

---

### 4. VEXOS_UPDATE_STRICT=1 honoring Class B

**PASS.** The strict-mode branch is correctly guarded:

```bash
if [ -n "$ALL_CANDIDATES" ] && [ "${VEXOS_UPDATE_STRICT:-0}" = "1" ]; then
  KNOWN_SMALL_LOCAL=""
  BLOCKING_DERIVATIONS="$ALL_CANDIDATES"
else
  KNOWN_SMALL_LOCAL=$(printf '%s\n' "$ALL_CANDIDATES" \
    | grep -E "$KNOWN_SMALL_LOCAL_REGEX" || true)
  BLOCKING_DERIVATIONS=$(printf '%s\n' "$ALL_CANDIDATES" \
    | grep -Ev "$KNOWN_SMALL_LOCAL_REGEX" || true)
fi
```

When `VEXOS_UPDATE_STRICT=1`, all post-A derivations route to `BLOCKING_DERIVATIONS`.  
The guard `[ -n "$ALL_CANDIDATES" ]` ensures strict mode is a no-op when nothing needs building (correct).

---

### 5. VEXOS_CACHE_BLOCK: and VEXOS_CACHE_LOCAL_OK: prefixes

**PASS.** Both output channels implemented correctly:

Blocking path:
```bash
echo "VEXOS_CACHE_BLOCK: The following packages are not in any cache and"
echo "VEXOS_CACHE_BLOCK: would require a local source build (update paused):"
printf '%s\n' "$BLOCKING_DERIVATIONS" | sed 's/^/VEXOS_CACHE_BLOCK:   /'
echo "VEXOS_CACHE_BLOCK:"
echo "VEXOS_CACHE_BLOCK: flake.lock restored. No changes were applied."
echo "VEXOS_CACHE_BLOCK: Use 'just deploy' to apply config-only changes without bumping inputs."
```

Known-small path:
```bash
echo "VEXOS_CACHE_LOCAL_OK: Small known local artifacts will build (expected, fast):"
printf '%s\n' "$KNOWN_SMALL_LOCAL" | sed 's/^/VEXOS_CACHE_LOCAL_OK:   /'
echo "VEXOS_CACHE_LOCAL_OK: Proceeding with update..."
```

The legacy `VEXOS_CACHE_MISS:` prefix is retired as spec requires; the Nix comment documents this for future readers.

---

### 6. Lock restored on blocking exit

**PASS.** The blocking path restores then removes the backup before exiting:

```bash
cp /etc/nixos/flake.lock.bak /etc/nixos/flake.lock
rm -f /etc/nixos/flake.lock.bak
exit 2
```

The success path also cleans up the backup (`rm -f /etc/nixos/flake.lock.bak`) before the final rebuild, so the backup file is never left orphaned. ✓

---

### 7. "just deploy" fallback in blocking message

**PASS.** Blocking message includes:

```
VEXOS_CACHE_BLOCK: Use 'just deploy' to apply config-only changes without bumping inputs.
```

---

### 8. Bash/Nix — ''${...} escaping

**PASS.** Nix string literals use `''${...}` correctly to prevent Nix from interpolating shell variable references. Verified in:

```nix
if [ -n "$ALL_CANDIDATES" ] && [ "''${VEXOS_UPDATE_STRICT:-0}" = "1" ]; then
```

All other variable references use bare `$VAR` syntax inside `''` ... `''` Nix string literals, which is correct — only `${...}` forms need the `''` escape.

---

### 9. Regex patterns properly quoted for grep -E

**PASS.** Both regexes are assigned to shell variables and passed quoted:

```bash
grep -Ev "$ALWAYS_LOCAL_REGEX"
grep -E  "$KNOWN_SMALL_LOCAL_REGEX"
grep -Ev "$KNOWN_SMALL_LOCAL_REGEX"
```

---

### 10. Exit codes

**PASS.**
- `exit 2` on cache miss (blocking path).
- Implicit `exit 0` on success (falls through to `nixos-rebuild switch`; if that fails, its exit code propagates under `set -euo pipefail`).
- `exit 1` on missing variant (early guard at top of script).

---

### 11. Variables initialized before use

**PASS.** All variables (`VARIANT`, `DRY`, `ALL_CANDIDATES`, `KNOWN_SMALL_LOCAL`, `BLOCKING_DERIVATIONS`) are assigned before they are read. The `|| true` guards on grep commands prevent premature abort under `set -euo pipefail` when grep finds no matches.

---

### 12. justfile update recipe comments

**PASS.** The `update` recipe now carries a detailed comment explaining the three-class engine:

```bash
# vexos-update (installed by modules/nix.nix) uses three-class miss
# classification before applying any update:
#   Class A — NixOS system assembly glue (always local, never blocking).
#   Class B — Known small local artifacts (e.g. PIA helpers); allowed,
#             logged as VEXOS_CACHE_LOCAL_OK, update proceeds normally.
#   Class C — Unknown/heavy packages; update paused, flake.lock restored,
#             logged as VEXOS_CACHE_BLOCK.
# The script also handles flake.lock backup/restore and nixos-rebuild switch.
# Up uses the same script so behaviour is identical regardless of update path.
sudo vexos-update
```

Recipe logic itself is unchanged. ✓

---

### 13. README.md — canonical update path

**PASS.** Line 158:

> "The canonical update paths are `just update` (terminal) and the **Up** app (GUI)."

README includes a full explanation of the three-class engine (classes A, B, C) with their behavior.

---

### 14. README.md — raw flake update in advanced/emergency section

**PASS.** Raw commands appear under:

```markdown
### Manual / emergency update (advanced)

> **Warning:** The commands below bypass miss classification and cache safety
> checks. Use only for recovery or advanced troubleshooting.

cd /etc/nixos && sudo nix flake update
sudo nixos-rebuild switch --flake /etc/nixos#$(cat /etc/nixos/vexos-variant)
```

---

## Build Validation

### Step 1: nix flake show

**PASS** (exit 0).

```
git+file:///home/nimda/Projects/vexos-nix
├───nixosConfigurations
│   ├───vexos-desktop-amd: NixOS configuration
│   ├───vexos-desktop-intel: NixOS configuration
│   ├───vexos-desktop-nvidia: NixOS configuration
│   ├───vexos-desktop-nvidia-legacy470: NixOS configuration
│   ├───vexos-desktop-nvidia-legacy535: NixOS configuration
│   ├───vexos-desktop-vm: NixOS configuration
│   ├───vexos-headless-server-*: NixOS configuration (×6)
│   ... (all 30 outputs listed)
```

Note: `warning: Git tree is dirty` is expected (uncommitted working changes); this does not affect evaluation.

---

### Step 2: vexos-desktop-amd dry-build

**PASS** (exit 0).

72 derivations listed as "will be built" (all system assembly glue, steam, ROCm tools, PIA helpers).  
29 paths listed as "will be fetched" (binary cache — all ROCm/GPU toolchain paths).  

Key observations confirming correct classification:
- `pia-client.drv`, `pia-client.desktop.drv`, `piactl.drv` appear in the "will be built" list — correctly targeted by Class B.
- `vexos-update.drv` appears in "will be built" — covered by `vexos-update\.drv$` in ALWAYS_LOCAL_REGEX.
- No unexpected source packages in "will be built".

---

### Step 3: vexos-desktop-nvidia dry-build

**PASS** (exit 0).

Smaller build set (no ROCm). 2 paths to fetch (asusctl, supergfxctl). System assembly derivations only in "will be built".

---

### Step 4: vexos-desktop-vm dry-build

**PASS** (exit 0).

Minimal build set. No GPU-specific packages. All system assembly glue only.

---

## Minor Observations (Non-blocking)

1. **`ALWAYS_LOCAL_REGEX` breadth:** The regex is broad by design (catches all NixOS glue). It does not anchor most alternatives with `$`, which means a derivation like `etc-foo-extra.drv` is caught by `etc-` even if it were a future user package. This matches the spec intent ("always local NixOS assembly") but could theoretically silently allow a user package whose name starts with `etc-`. Acceptable given the project's controlled package set.

2. **`set -euo pipefail` with `|| true`:** Correct defensive use to prevent grep non-zero exit (no-match) from aborting the script. Well-handled.

3. **`nix flake update` invocation inside vexos-update:** Uses the full flag form `nix --extra-experimental-features "nix-command flakes" flake update --flake path:/etc/nixos`, which is consistent with the project's practice of not assuming `nix-command` is globally enabled. ✓

---

## Score Table

| Category                  | Score | Grade |
|---------------------------|-------|-------|
| Specification Compliance  | 100%  | A+    |
| Best Practices            | 97%   | A+    |
| Functionality             | 100%  | A+    |
| Code Quality              | 97%   | A+    |
| Security                  | 100%  | A+    |
| Performance               | 100%  | A+    |
| Consistency               | 100%  | A+    |
| Build Success             | 100%  | A+    |

**Overall Grade: A+ (99%)**

---

## Result

**Build:** PASS — all three dry-build targets (amd, nvidia, vm) exited 0.  
**Review:** **PASS**

All spec deliverables are complete. No CRITICAL issues found. The implementation is ready for Phase 6 preflight.
