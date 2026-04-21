# Review: `stateless-vexos-variant-persist`

**Date:** 2026-04-20  
**Reviewer:** Review Subagent  
**Spec:** `.github/docs/subagent_docs/stateless-vexos-variant-persist_spec.md`  
**Status:** PASS

---

## 1. Critical Question Answers

### 1.1 Activation Script in `modules/impermanence.nix`

**Is there an activation script that writes `vexos-variant`? What does it write?**

Yes. The script is:

```nix
system.activationScripts.vexosVariant = lib.mkIf (config.vexos.variant != "") {
  deps = [ "etc" ];
  text = ''
    PERSIST_DIR="${cfg.persistentPath}/etc/nixos"
    ${pkgs.coreutils}/bin/mkdir -p "$PERSIST_DIR"
    ${pkgs.coreutils}/bin/printf '%s' '${config.vexos.variant}' \
      > "$PERSIST_DIR/vexos-variant"
  '';
};
```

Confirmed via `nix eval --impure .#nixosConfigurations.vexos-stateless-amd.config.system.activationScripts` — the evaluated activation text is:

```
PERSIST_DIR="/persistent/etc/nixos"
/nix/store/...coreutils.../bin/mkdir -p "$PERSIST_DIR"
/nix/store/...coreutils.../bin/printf '%s' 'vexos-stateless-amd' \
  > "$PERSIST_DIR/vexos-variant"
```

The string `vexos-stateless-amd` is baked into the Nix store at evaluation time (not a runtime variable). The write target is `/persistent/etc/nixos/vexos-variant` — using fully qualified Nix store paths for all binaries (correct for activation scripts).

**Is `/etc/nixos` persisted as a directory or individual files?**

As a **directory**:

```nix
environment.persistence."${cfg.persistentPath}" = {
  hideMounts = true;
  directories = [
    "/var/lib/nixos"
    "/etc/nixos"          # ← bind-mounted from /persistent/etc/nixos
  ] ++ cfg.extraPersistDirs;

  files = [ ] ++ cfg.extraPersistFiles;   # ← vexos-variant is NOT here
};
```

`/etc/nixos/vexos-variant` is covered by the directory bind-mount. Adding it separately to the `files` list would cause a systemd mount conflict (as the spec correctly noted).

**Does the activation script write to `/persistent/etc/nixos/vexos-variant` or to `/etc/nixos/vexos-variant`?**

It writes to **`/persistent/etc/nixos/vexos-variant`** — the raw persistent path, not the bind-mounted path. This is the correct approach, and is explicitly noted in the code comment:

> "bypassing the timing race between the NixOS etc activation and the impermanence bind mount for /etc/nixos"

**Is there an ordering issue where the activation script could run before the bind mount?**

No ordering issue exists. The impermanence bind-mount for `/etc/nixos` is set up as a **systemd mount unit**, which runs **after** the full activation script completes. The execution order in the evaluated activation script is:

```
stdio → binsh → users → groups → createPersistentStorageDirs →
specialfs → etc → hashes → modprobe → persist-files → udevd →
usrbinenv → var → vexosVariant
```

`vexosVariant` is the **last** custom activation step. It runs after `etc` (as declared by `deps = ["etc"]`). By design, the write target is `/persistent/etc/nixos/vexos-variant` — directly to the Btrfs `@persist` subvolume which is `neededForBoot = true` and mounted in initrd, guaranteed available before any activation script runs.

The bind-mount (`/etc/nixos` → `/persistent/etc/nixos`) is established **afterward** by systemd, so `vexos-variant` is accessible at `/etc/nixos/vexos-variant` once the system is fully up.

---

### 1.2 Most Important: Would the File Survive Reboots on an Already-Running Stateless System?

**Boot sequence for an established stateless system:**

1. **initrd**: `/persistent` is mounted (Btrfs `@persist` subvolume — `neededForBoot = true`). `/nix` is mounted (`@nix` subvolume). Tmpfs `/` is fresh and empty.

2. **Stage 2 activation** (`nixos-activation.service`): Activation scripts execute in dep order. `vexosVariant` runs near the end and writes `vexos-stateless-amd` directly to `/persistent/etc/nixos/vexos-variant`. This is a **write to persistent Btrfs storage**, not to the ephemeral tmpfs.

3. **systemd target sequencing**: Impermanence systemd `.mount` units fire (`persistent-etc-nixos.mount` or similar). The bind-mount establishes `/etc/nixos` → `/persistent/etc/nixos` on the tmpfs root. `/etc/nixos/vexos-variant` is now accessible to userspace.

4. **Result per boot**: The file always exists at `/persistent/etc/nixos/vexos-variant` because the activation script writes it unconditionally on every activation. Even if it were somehow deleted from persistent storage, the next `nixos-rebuild switch` or reboot would recreate it.

**Verdict**: **YES, the file survives all subsequent reboots.** The activation script is not a one-shot setup; it runs on every activation, making per-boot loss impossible as long as `/persistent` mounts correctly.

---

### 1.3 Do Setup Script Changes Fix Ongoing Per-Boot Loss or Only First-Install?

**The setup script changes fix the first-install case.** The ongoing per-boot case was already handled by the activation script running on every boot.

The problem was specifically:
- During `nixos-install`, activation scripts run inside a chroot at `/mnt`. NixOS only bind-mounts `/nix`, `/dev`, `/proc`, and `/sys` into that chroot. The `@persist` Btrfs subvolume (mounted at `/mnt/persistent` on the host) may not be visible inside the chroot as `/persistent`. Any write to `/persistent/etc/nixos/vexos-variant` inside the chroot may silently miss the actual persistent subvolume.
- The setup script's explicit post-install copy block (writing to `/mnt/persistent/etc/nixos/`) bypasses this entirely.

The `stateless-setup.sh` fix:
```bash
printf '%s' "vexos-stateless-${VARIANT}" | sudo tee /mnt/persistent/etc/nixos/vexos-variant > /dev/null
```
**Confirmed present** at the correct location in the script (after `nixos-install`, inside the "Persisting NixOS config files" block, while the host's `/mnt/persistent` is still accessible).

The `migrate-to-stateless.sh` fix:
```bash
printf '%s' "vexos-stateless-${VARIANT}" > "${BTRFS_MOUNT}/@persist/etc/nixos/vexos-variant"
echo -e "  ${GREEN}✓ vexos-variant persisted${RESET}"
```
**Confirmed present** in the "@persist" copy block. `${BTRFS_MOUNT}` is the raw Btrfs mount (subvolid=5), and `@persist` is the Btrfs subvolume that becomes `/persistent`. The write goes directly to persistent storage before the first stateless boot.

---

### 1.4 Is the Fix Incomplete? What Additional Changes Are Needed?

**No additional changes are needed to `modules/impermanence.nix`.**

The activation script in `modules/impermanence.nix` writes to `/persistent/etc/nixos/vexos-variant` on every boot — this is the complete and correct per-boot fix. The first-install gaps in both setup scripts have been filled. The thin-wrapper path (`template/etc-nixos-flake.nix` → `mkStatelessVariant`) also has its own inline activation script that handles thin-wrapper users.

No further implementation changes are required.

---

## 2. Build Validation Results

### `nix flake check --impure`

```
checking flake output 'nixosModules'...
✓ nixosModules.base
✓ nixosModules.statelessBase
✓ nixosModules.gpuAmd
✓ nixosModules.gpuNvidia
✓ nixosModules.gpuIntel
✓ nixosModules.gpuVm
✓ nixosModules.statelessGpuVm
✓ nixosModules.asus
✓ nixosModules.htpcBase
✓ nixosModules.serverBase

checking flake output 'nixosConfigurations'...
ERROR: vexos-desktop-amd — "Failed assertions: You must set the option
'boot.loader.grub.devices'..." (boot.loader not set)
```

**Analysis**: The `nixosConfigurations` check fails because the flake's `commonModules` includes `/etc/nixos/hardware-configuration.nix` as an absolute path. On the dev machine (non-NixOS or no generated hardware config), this file is absent and the bootloader is unconfigured — a pre-existing constraint of the repo design, **not caused by this change**.

The `preflight.sh` script handles this correctly by checking for the hardware-configuration.nix before running `nix flake check`:
```bash
if [ ! -f /etc/nixos/hardware-configuration.nix ]; then
  warn "Skipping nix flake check — /etc/nixos/hardware-configuration.nix not found."
```

**The stateless configuration evaluates correctly.** Confirmed via:
```
nix eval --impure .#nixosConfigurations.vexos-stateless-amd.config.system.activationScripts
```
The `vexosVariant` activation script is present, correctly ordered, and contains the expected content.

### `hardware-configuration.nix` in repo check

```
git ls-files | grep hardware-configuration.nix
(no output)
```
**PASS** — `hardware-configuration.nix` is not tracked in the repo.

### `system.stateVersion` check

```
configuration-stateless.nix:126:  system.stateVersion = "25.11";
```
**PASS** — `system.stateVersion` is `"25.11"`, unchanged.

---

## 3. Implementation Correctness Analysis

### `modules/impermanence.nix` — Activation Script

| Check | Result |
|-------|--------|
| Writes to `/persistent/etc/nixos/vexos-variant` (persistent storage, not bind-mount path) | ✅ |
| Uses Nix store paths for `mkdir` and `printf` (no PATH dependency) | ✅ |
| `deps = ["etc"]` — runs after etc activation (correct ordering) | ✅ |
| `lib.mkIf (config.vexos.variant != "")` — guarded for safety | ✅ |
| `vexos.variant` set in all `hosts/stateless-*.nix` | ✅ |
| Activation confirmed in `nix eval` output | ✅ |

### `scripts/stateless-setup.sh` — First-Install Fix

| Check | Result |
|-------|--------|
| `printf '%s' "vexos-stateless-${VARIANT}" | sudo tee /mnt/persistent/etc/nixos/vexos-variant` present | ✅ |
| Runs after `nixos-install` (post-install copy block) | ✅ |
| `VARIANT` variable is in scope at insertion point | ✅ |
| Target path `/mnt/persistent/etc/nixos/` is the correct Btrfs `@persist` subvolume | ✅ |
| `mkdir -p /mnt/persistent/etc/nixos` runs before the write | ✅ |

### `scripts/migrate-to-stateless.sh` — Migration Fix

| Check | Result |
|-------|--------|
| `printf '%s' "vexos-stateless-${VARIANT}" > "${BTRFS_MOUNT}/@persist/etc/nixos/vexos-variant"` present | ✅ |
| Runs in the `@persist` copy block (after `nixos-rebuild boot`, before reboot) | ✅ |
| `VARIANT` and `BTRFS_MOUNT` are in scope at insertion point | ✅ |
| Target `${BTRFS_MOUNT}/@persist/etc/nixos/` is the raw Btrfs subvolume (correct) | ✅ |
| Echo confirmation message present | ✅ |

### `template/etc-nixos-flake.nix` — Thin-Wrapper Path

| Check | Result |
|-------|--------|
| `mkStatelessVariant` includes inline `vexosVariant` activation script | ✅ |
| Writes to `/persistent/etc/nixos/vexos-variant` directly | ✅ |
| `${variant}` is Nix string interpolation (baked into store, not shell variable) | ✅ |
| No dependency conflict with `modules/impermanence.nix` (thin-wrapper never sets `vexos.variant`) | ✅ |

---

## 4. Score Table

| Category | Score | Grade |
|----------|-------|-------|
| Specification Compliance | 100% | A+ |
| Best Practices | 90% | A |
| Functionality | 95% | A |
| Code Quality | 90% | A |
| Security | 90% | A |
| Performance | 95% | A |
| Consistency | 95% | A |
| Build Success | 80% | B+ |

**Overall Grade: A (91%)**

Build grade is B+ because `nix flake check` produces an error for `nixosConfigurations` (missing host hardware-configuration.nix). This is a pre-existing repo constraint documented in `preflight.sh`, not caused by this change. All `nixosModules` exports pass cleanly. The stateless configuration evaluates correctly in isolation.

---

## 5. Findings Summary

### First-Install Case (nixos-install chroot path)
The fix is **complete**. `stateless-setup.sh` now explicitly writes `vexos-variant` to `/mnt/persistent/etc/nixos/vexos-variant` after `nixos-install` completes, bypassing the chroot restriction.

### Migration Case (migrate-to-stateless.sh path)
The fix is **complete**. The migration script now writes `vexos-variant` to `${BTRFS_MOUNT}/@persist/etc/nixos/vexos-variant` directly into the raw Btrfs subvolume before the first stateless boot.

### Ongoing Per-Boot Case (already-running stateless system)
The ongoing case is **fully handled** by the `vexosVariant` activation script in `modules/impermanence.nix`. This script:
1. Runs on **every** `nixos-activation` (every boot and every `nixos-rebuild switch`)
2. Writes to `/persistent/etc/nixos/vexos-variant` **directly** (persistent Btrfs storage)
3. The impermanence bind-mount then makes the file accessible at `/etc/nixos/vexos-variant`

Per-boot loss is structurally impossible while this activation script is present.

---

## 6. Verdict

**PASS**

The implementation correctly addresses both the first-install case (setup script changes) and the ongoing per-boot case (activation script running on every boot). No additional changes are needed to `modules/impermanence.nix` or any other file.

The `vexos-variant` file will always be present at `/etc/nixos/vexos-variant` after the system fully boots on any stateless configuration, for both the direct-repo flake path and the thin-wrapper path.
