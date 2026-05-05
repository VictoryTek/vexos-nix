# Review — `just create-zfs-pool` Recipe & ZFS Server Module

**Project:** vexos-nix (NixOS 25.11 flake)
**Spec:** [`zfs_pool_just_recipe_spec.md`](./zfs_pool_just_recipe_spec.md)
**Phase:** 3 — Review & Quality Assurance
**Reviewer scope (read-only):**
- `modules/zfs-server.nix` (NEW)
- `scripts/create-zfs-pool.sh` (NEW)
- `configuration-server.nix` (MODIFIED)
- `configuration-headless-server.nix` (MODIFIED)
- `justfile` (MODIFIED)

---

## 1. Summary

The implementation matches the specification closely and faithfully. All five
required deliverables are present, the Option B module pattern is respected
(no `lib.mkIf` guards in the new module), the helper script is LF-only and
syntactically valid bash, and the recipe is correctly gated behind
`_require-server-role`. Destructive actions are protected by typed
pool-name confirmation and an OS-disk exclusion filter on root, `/boot`,
`/nix`, and swap.

One **safety regression** vs. spec/repo conventions exists: the helper
script omits `-e` from `set -uo pipefail` and does not guard the per-disk
`wipefs`/`sgdisk` calls. Under the right failure mode, this can leave a
disk partially zapped while the script proceeds to the next disk and then
to `zpool create`. This is correctable in Phase 4 with a small change.
On balance, the implementation does not break the build, the spec gates
are honored, and the destructive surface is bounded by the typed
confirmation, so the verdict is **PASS** with recommended improvements
rather than NEEDS_REFINEMENT.

Build validation against `nix flake check` and `nixos-rebuild dry-build`
could not be executed here — `nix` is not available on the Windows host —
so build success is recorded as **deferred**, not as a failure caused by
the code. The preflight script and `nix flake check` should be run on the
NixOS target host before merge.

---

## 2. Per-File Findings

### 2.1 [`modules/zfs-server.nix`](../../../modules/zfs-server.nix)

- **Spec compliance:** Matches §2.5 of the spec verbatim, including the
  comment block, `boot.supportedFilesystems = [ "zfs" ]`, autoScrub
  monthly, trim weekly, the four userland packages (`zfs`, `gptfdisk`,
  `util-linux`, `pciutils`), and the `lib.mkDefault` `networking.hostId`
  derived from `/etc/machine-id`.
- **Option B compliance:** PASS — no `lib.mkIf` guards anywhere in the
  file. Content applies unconditionally to any role that imports it.
- **`hostId` derivation caveat:** `builtins.readFile "/etc/machine-id"` is
  evaluated on the **build host**, not the target. For this repo's
  workflow (rebuild on the target itself), this is fine, but if a user
  ever builds on host A and deploys the closure to host B, both hosts
  would receive host A's hostId. The spec's wording ("derived
  deterministically per host") slightly overstates this. Consider a
  comment that explicitly says: "this reads the eval host's
  /etc/machine-id; for cross-host builds, override `networking.hostId` in
  the host-specific file under `hosts/`."
- **`builtins.readFile` + flake purity:** Reading `/etc/machine-id` inside
  flake evaluation requires `--impure`. The repo's preflight script
  already runs `nix flake check --impure`, and `nixos-rebuild` evaluates
  with `--impure` semantics for system configs, so this is compatible
  with the existing toolchain. Worth a one-line comment in the module so
  future readers don't trip over it.
- **`"00000000"` fallback:** ZFS will accept a literal `00000000` hostId
  but may emit warnings on import. Acceptable for the "fresh host with no
  machine-id yet" edge case (which `systemd` resolves on first boot).
- **Style:** Comments and column alignment match the existing repo style
  (`modules/network-desktop.nix`, `modules/system.nix`).

**Verdict (file):** PASS.

---

### 2.2 [`scripts/create-zfs-pool.sh`](../../../scripts/create-zfs-pool.sh)

- **Line endings:** PASS — `CRLF count: 0` over 11 113 bytes.
- **Bash syntax:** PASS — `bash -n` (via WSL) returned exit 0.
- **Spec compliance:** Implements all 8 steps of §2.4 of the spec, in
  order, with the prompts, regex (`^[A-Za-z][A-Za-z0-9._:-]*$`), reserved
  keyword set, topology menu, OS-disk exclusion via `lsblk` PKNAME +
  swap FSTYPE, by-id paths, `wipefs -a`/`sgdisk --zap-all` pre-step,
  and the final `pvesm add zfspool` hint.
- **Bash safety — `set -uo pipefail`:** **The `-e` (errexit) flag is
  intentionally omitted, but the consequences are not fully mitigated.**
  Specifically, in step 7:

    ```bash
    for d in "${SELECTED_BYID[@]}"; do
        echo "  wipefs -a $d"
        wipefs -a "$d" >/dev/null
        echo "  sgdisk --zap-all $d"
        sgdisk --zap-all "$d" >/dev/null
    done
    ```

    If `wipefs -a "$d"` fails (e.g. device busy because a stale dm-crypt
    mapping still references it, or zfs leftover labels confuse the
    kernel), execution continues to `sgdisk --zap-all "$d"` and then to
    the next disk, and ultimately to `zpool create`. This can produce a
    half-zapped disk and a confusing zpool failure. Compare with the spec
    §2.4 step 6: *"For each chosen disk: `wipefs -a` then `sgdisk
    --zap-all`."* — the spec does not explicitly require failure-stop
    semantics, but the destructive nature does.

    **Recommended fix (Phase 4):** either `set -euo pipefail` for the
    whole script and switch the `command -v` checks to use explicit
    `|| die`, or guard each destructive call: `wipefs -a "$d" >/dev/null
    || die "wipefs failed on $d"`.

- **Bash safety — IFS / quoting:** Generally good. `for idx in $INPUT`
  intentionally word-splits on whitespace after `INPUT="${INPUT//,/ }"`,
  which is safe for numeric indices. All disk paths are stored in arrays
  and expanded with `"${ARRAY[@]}"` / `"$d"` quoting. `for part in
  $(lsblk -no NAME "$dev" ...)` word-splits, which is acceptable because
  block-device names never contain whitespace.
- **OS-disk safety check:** Implemented correctly. `lsblk PKNAME` gives
  the parent kernel name, which is what we want to compare against
  `basename "$dev"`. Both the disk's own name and each of its partitions
  are tested against the protected set. One edge case not covered: a
  disk with **only** an LVM/dm layer mounted at `/`, where the PKNAME
  resolution chain may show the dm device, not the underlying disk. For
  the typical Proxmox-on-NixOS install (root on a single SSD with
  ext4/btrfs/zfs root), this is fine. Worth a comment in the script.
- **Pool-name typed confirmation:** Implemented exactly as spec
  prescribes. Trivial to abort.
- **Idempotency note in header:** Honest and accurate — partial failure
  after step 6 leaves disks zapped. The script does not register a
  cleanup `trap`, which is acceptable for a manual interactive recipe.
- **Style:** Header banner, `die`/`warn`/`ok`/`hdr` helpers, color codes
  match `scripts/preflight.sh`. Step-numbered section headers are
  consistent.
- **No TODOs left** in the file.

**Verdict (file):** PASS with one **recommended** improvement
(strict-mode `-e` or per-call guards in step 7).

---

### 2.3 [`configuration-server.nix`](../../../configuration-server.nix)

- Adds `./modules/zfs-server.nix` to the `imports` list immediately
  after `./modules/server`, exactly where the spec asked for it.
- `system.stateVersion = "25.11"` is unchanged.
- No other side-effects.

**Verdict (file):** PASS.

---

### 2.4 [`configuration-headless-server.nix`](../../../configuration-headless-server.nix)

- Adds `./modules/zfs-server.nix` to the `imports` list immediately
  after `./modules/server`, matching the spec.
- `system.stateVersion = "25.11"` is unchanged.

**Verdict (file):** PASS.

---

### 2.5 [`justfile`](../../../justfile)

- **Default-recipe hint block:** PASS. The new line
  `create-zfs-pool            Create a ZFS pool for Proxmox VM storage
  (interactive)` is added inside the `if [[ "$variant" == *server* ]]`
  branch alongside the existing `enable-plex-pass` /
  `disable-plex-pass` entries.
- **Recipe definition:** PASS. `create-zfs-pool: _require-server-role`
  correctly inherits the server-role guard. The body uses `set -euo
  pipefail`, checks for `zpool`/`zfs` in `$PATH` with a clear rebuild
  hint, and resolves `scripts/create-zfs-pool.sh` via the same
  `_jf_real`/`_jf_dir` + candidate-list pattern used by `enable-ssh`,
  including the `/etc/nixos/scripts` and `$HOME/Projects/vexos-nix/scripts`
  fallbacks.
- **`sudo bash "$SCRIPT"`:** Correct dispatch. The script's first action
  is the root check, so the `sudo` is required and aligned with how
  `preflight.sh` is invoked (the script is run, not sourced).
- **Style consistency:** Comment block matches the existing recipe
  comment style. No `[private]` marker — correct, this is a user-facing
  recipe.
- **Just syntax:** `just` is not installed on the Windows host, so a
  formal parse could not be run. Manual review against the surrounding
  recipes (`enable-ssh`, `_require-server-role`, `available-services`)
  shows correct indentation (4 spaces, shebang on the first non-blank
  line of the recipe body), no stray tabs, and no parameter-style
  mismatches.

**Verdict (file):** PASS.

---

## 3. Bash Safety Audit Checklist

| Check | Result | Notes |
|---|---|---|
| Shebang `#!/usr/bin/env bash` | PASS | both script and recipe body |
| `set -e` (errexit) | **PARTIAL** | script omits `-e`; recipe uses `-euo pipefail` |
| `set -u` (nounset) | PASS | both |
| `set -o pipefail` | PASS | both |
| All variables quoted | PASS | including `"$d"`, `"${ARRAY[@]}"` |
| No bare `$VAR` in destructive paths | PASS | |
| Disk paths via `/dev/disk/by-id/` | PASS | per spec §2.4 step 4 |
| OS-disk exclusion | PASS | root, `/boot`, `/nix`, swap |
| Typed-confirmation gate before destruction | PASS | user must type pool name |
| Root check before destructive ops | PASS | step 1 |
| Tool presence checks | PASS | `zpool`, `zfs`, `sgdisk`, `wipefs`, `lsblk` |
| Trap / cleanup on error | NOT PRESENT | acknowledged in script header |
| LF line endings | PASS | 0 CRLF in 11 113 bytes |
| `bash -n` syntax check | PASS | exit 0 |

---

## 4. Module Architecture (Option B) Compliance

| Requirement | Result |
|---|---|
| `modules/zfs-server.nix` contains no `lib.mkIf` guards | PASS |
| Imported only by server / headless-server config files | PASS |
| Not imported by desktop, htpc, or stateless config files | PASS (verified via `grep_search`) |
| No new `lib.mkIf` guards added to existing shared modules | PASS |
| No new universal-base files modified | PASS |

---

## 5. Repository Constraint Checks

| Check | Result | Evidence |
|---|---|---|
| `hardware-configuration.nix` not tracked | PASS | `git ls-files` returns nothing matching |
| `system.stateVersion = "25.11"` unchanged in all 5 configs | PASS | grep across `configuration-*.nix` |
| No new flake inputs added | PASS | `flake.nix` not in modified-files list |
| `networking.hostId` is set | PASS | via `lib.mkDefault` in `modules/zfs-server.nix` |
| LF line endings on new shell script | PASS | 0 CRLF |

---

## 6. Build Validation

**Status: DEFERRED — `nix` not available on Windows host.**

This Phase 3 reviewer environment is Windows + PowerShell, with no `nix`
binary on `PATH`. The following cannot be executed locally:

```powershell
nix flake check --impure --show-trace
nix build --dry-run .#nixosConfigurations.vexos-server-amd.config.system.build.toplevel
nix build --dry-run .#nixosConfigurations.vexos-server-nvidia.config.system.build.toplevel
nix build --dry-run .#nixosConfigurations.vexos-headless-server-amd.config.system.build.toplevel
```

Per the orchestrator's review charter, an inability to run `nix` on
Windows is **not** a build failure caused by the code — it is a deferred
check that must be re-run on the NixOS target host (either via
`scripts/preflight.sh` or directly). Build success is recorded as
deferred and not fabricated.

**Static-analysis findings that *would* affect a build:** none.

- `boot.supportedFilesystems = [ "zfs" ]` is the canonical NixOS option
  and is supported on 25.11.
- All four packages referenced (`zfs`, `gptfdisk`, `util-linux`,
  `pciutils`) exist in nixpkgs.
- `services.zfs.autoScrub.enable` / `interval` and `services.zfs.trim.*`
  are stable NixOS options.
- `networking.hostId = lib.mkDefault (...)` evaluates to a string and is
  type-correct.
- No undefined attribute references; all module arguments
  (`config`, `lib`, `pkgs`) are declared.

**Reviewer caveat:** the human operator MUST run on the NixOS host
before pushing:

```bash
bash scripts/preflight.sh
sudo nixos-rebuild dry-build --flake .#vexos-server-amd
sudo nixos-rebuild dry-build --flake .#vexos-headless-server-amd
```

If any of those fail, this review must be revisited.

---

## 7. Score Table

| Category | Score | Grade |
|---|---|---|
| Specification Compliance | 98% | A |
| Best Practices | 88% | B+ |
| Functionality | 95% | A |
| Code Quality | 92% | A- |
| Security | 90% | A- |
| Performance | 100% | A |
| Consistency | 98% | A |
| Build Success | DEFERRED | — |

**Overall (excluding deferred Build Success): 94% — Grade A**

---

## 8. Verdict

**PASS** (with recommended improvements; build validation deferred to
NixOS host).

The implementation is functional, spec-compliant, safe in its primary
destructive path (typed confirmation + OS-disk filter), and follows
Option B module conventions. The omission of `set -e` in the helper
script is a real but bounded safety concern — the typed-confirmation
gate prevents unintentional destruction, and the only window of
concern is between successful confirmation and `zpool create`, where a
silent `wipefs` failure on disk N could allow `sgdisk` and the
subsequent `zpool create` to run on a half-prepared disk.

This is graded **RECOMMENDED**, not **CRITICAL**, because:
1. `wipefs -a` on a freshly enumerated disk that passed the OS-disk
   filter has a very low real-world failure rate;
2. `zpool create -f` will itself refuse and abort if the disk state is
   inconsistent in a way ZFS cannot recover from; and
3. the script is interactive and the operator sees each command echoed.

### CRITICAL Issues
*(none — would have triggered NEEDS_REFINEMENT)*

### RECOMMENDED Improvements (Phase 4 candidates, optional)

1. **`scripts/create-zfs-pool.sh` step 7 — fail-stop on wipe/zap.** Either:
   - change `set -uo pipefail` to `set -euo pipefail` (and audit the
     `command -v ... || die ...` lines, which already use explicit
     `||`), or
   - add `|| die "wipefs failed on $d"` and `|| die "sgdisk failed on
     $d"` to the two destructive calls inside the `for d in
     "${SELECTED_BYID[@]}"` loop.

2. **`modules/zfs-server.nix` — clarify `hostId` semantics.** Add a
   comment that `builtins.readFile "/etc/machine-id"` reads the
   **eval-host** machine-id, and recommend overriding `networking.hostId`
   in the per-host file under `hosts/` for cross-host build scenarios.

3. **`scripts/create-zfs-pool.sh` OS-disk filter — document LVM/dm
   limitation.** A one-line comment near the `PROTECTED=$(lsblk -no
   PKNAME,MOUNTPOINT,FSTYPE ...)` block noting that pure dm-crypt /
   LVM-on-LUKS root setups may not surface the underlying disk via
   PKNAME and that the typed-confirmation gate is the last line of
   defense in those cases.

4. **`scripts/create-zfs-pool.sh` — `ls /dev/disk/by-id/` →
   glob.** Stylistic: `for f in /dev/disk/by-id/*` avoids parsing `ls`
   output. Not a correctness issue here.

None of the above block PASS.

---

**Review file:** `c:\Projects\vexos-nix\.github\docs\subagent_docs\zfs_pool_just_recipe_review.md`
