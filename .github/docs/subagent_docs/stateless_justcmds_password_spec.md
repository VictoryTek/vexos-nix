# Specification: Stateless Role — `just` Command Failure and Default Password Confusion

**Feature Name:** `stateless_justcmds_password`
**Date:** 2026-04-19
**Status:** READY FOR IMPLEMENTATION

---

## 1. Current State Analysis

### 1.1 Relevant Files

| File | Role |
|---|---|
| `modules/impermanence.nix` | Declares `/` as tmpfs, sets up `environment.persistence`, enforces `users.mutableUsers = false` |
| `configuration-stateless.nix` | Imports `impermanence.nix`, sets `initialPassword = "vexos"` for `nimda` user |
| `scripts/stateless-setup.sh` | Fresh install from NixOS ISO — formats disk, installs system |
| `scripts/migrate-to-stateless.sh` | In-place migration from working NixOS install to stateless layout |
| `justfile` | `_resolve-flake-dir`, `rebuild`, `update`, `switch`, `default` (role-specific info) |
| `template/etc-nixos-flake.nix` | The thin wrapper `flake.nix` that `/etc/nixos/flake.nix` is populated with |

### 1.2 Stateless Boot Sequence

On every boot of the stateless role:

1. Kernel loads from `/boot` (on the persistent EFI partition).
2. initrd mounts `/persistent` (`@persist` Btrfs subvolume, `neededForBoot = true`).
3. initrd mounts `/nix` (`@nix` Btrfs subvolume, `neededForBoot = true`).
4. `/` is mounted as `tmpfs` (size=25%, mode=755) — **completely fresh on every boot**.
5. The impermanence module (`nix-community/impermanence`) runs its bind-mount systemd units:
   - For every entry in `environment.persistence."/persistent".directories`, it bind-mounts `/persistent/<dir>` → `/<dir>`.
   - For every entry in `environment.persistence."/persistent".files`, it bind-mounts or symlinks `/persistent/<file>` → `/<file>`.
6. NixOS activation script runs, sets up `/etc` including `environment.etc.*` entries.
7. Display manager / services start.

### 1.3 What Currently Persists

`impermanence.nix` currently persists **only**:

```nix
directories = [ "/var/lib/nixos" ] ++ cfg.extraPersistDirs;
files       = [] ++ cfg.extraPersistFiles;
```

`/etc/nixos` is **not** in the persistence list. It is placed on the ephemeral `/` (tmpfs) on first boot by the NixOS activation script.

### 1.4 What `environment.etc` Does vs What Impermanence Needs

`environment.etc."nixos/vexos-variant"` creates **only** `/etc/nixos/vexos-variant` — a symlink into the Nix store, regenerated on every NixOS activation (boot + rebuild).

It does **not** create `/etc/nixos/flake.nix` or `/etc/nixos/hardware-configuration.nix`. Those are user-managed files that `/etc/nixos` happens to contain. After a stateless reboot, the fresh tmpfs `/` makes `/etc/nixos/` start empty. The `vexos-variant` file appears because it is written by `environment.etc` during activation. But `flake.nix` and `hardware-configuration.nix` are **gone**.

### 1.5 `_resolve-flake-dir` Candidate Lookup

The `justfile` `_resolve-flake-dir` recipe tries these directories in order:

1. `$FLAKE_OVERRIDE` (if provided)
2. The directory containing the `justfile` itself (repo clone location)
3. `/etc/nixos`
4. `$HOME/Projects/vexos-nix`

On the stateless role, on a clean reboot:

- The repo clone path varies per install and may not exist (stateless system is often installed from ISO, not cloned).
- `/etc/nixos/flake.nix` is gone.
- `$HOME/Projects/vexos-nix` does not exist (ephemeral home).

Therefore `_resolve-flake-dir` **always fails** on a stateless system after reboot unless a valid flake directory is found via one of those candidates.

---

## 2. Problem Definition

### 2.1 Bug 1: `just` Commands Unavailable After Stateless Reboot

**Symptom:** On the stateless role, after rebooting, running `just rebuild`, `just update`, or `just switch` fails with:

```
error: no flake provided target 'vexos-stateless-<variant>'
attempted directories:
  - <justfile dir>   # no flake.nix on tmpfs root
  - /etc/nixos       # flake.nix is gone (ephemeral root)
  - /home/nimda/Projects/vexos-nix   # doesn't exist
```

**Root cause:** `/etc/nixos/flake.nix` and `/etc/nixos/hardware-configuration.nix` live on the ephemeral tmpfs root and are wiped on every reboot. The impermanence module does not persist `/etc/nixos`. The NixOS activation script only recreates `vexos-variant`, not the flake files.

**Impact:** `just rebuild` and `just update` are completely broken on the stateless role after any reboot. Users cannot update the system without manually knowing the flake path.

**Note on `/etc/nixos/vexos-variant`:** This file IS recreated on every boot (via `environment.etc`). So `just variant` and `just rebuild` would find the variant name, but `rebuild` then fails at `_resolve-flake-dir` because `flake.nix` is absent.

### 2.2 Bug 2: User/sudo Password Fails After Stateless Reboot

**Symptom:** After first boot (fresh install or migration), users attempt to log in with whatever password they set during install, or expect their existing system password to carry over. Login fails.

**Root cause analysis:**

1. `configuration-stateless.nix` declares:
   ```nix
   users.users.nimda.initialPassword = "vexos";
   ```
2. `impermanence.nix` declares:
   ```nix
   users.mutableUsers = false;
   ```
3. With `users.mutableUsers = false`, `/etc/shadow` is **generated from the NixOS configuration on every boot**. Passwords changed at runtime via `passwd` are written to the ephemeral `/etc/shadow` on tmpfs. They do NOT survive a reboot.
4. Therefore, on every boot, the `nimda` user password resets to `vexos`.
5. Neither install script (`stateless-setup.sh` nor `migrate-to-stateless.sh`) informs users of this behavior or the default password.

**Specific failure scenarios:**
- **Fresh install via ISO:** The script offers `nixos-enter --root /mnt -- passwd` at the end, but doesn't say why or what the default is. Users who skip this step or set only the root password find they cannot log in as `nimda` after reboot (they had no existing password expectation).
- **Migration from existing system:** The existing user password is wiped on the first stateless reboot. Users expect their familiar password to work; it does not. The migration script gives no warning.

---

## 3. Research Findings

### Source 1: nix-community/impermanence README (GitHub)

URL: `https://github.com/nix-community/impermanence`

Key findings:
- `environment.persistence."/persistent".directories` takes a list of path strings; each is bind-mounted from `/persistent/<path>` → `/<path>`.
- If the source directory does not exist on the persistent volume, the impermanence module **automatically creates it** (with correct ownership/mode).
- `hideMounts = true` hides the bind mounts from file managers via `x-gvfs-hide`.
- Adding `/etc/nixos` to `directories` is a well-documented and recommended pattern for persisting system configuration.

### Source 2: NixOS Wiki — Impermanence

URL: `https://nixos.wiki/wiki/Impermanence`

Key findings:
- Quote from wiki: "Some files and folders should be persisted between reboots though (such as `/etc/nixos/`). This can be accomplished through bind mounts or by using the NixOS Impermanence module."
- The wiki explicitly lists `/etc/nixos/` as an example directory to persist.
- Warning note: "When setting up impermanence, make sure that you have declared password for your user to be able to log-in after the deployment as for example the nixos installer declares passwords imperatively."

### Source 3: NixOS Manual — User Management (nixos.org stable)

URL: `https://nixos.org/manual/nixos/stable/#sec-user-management`

Key findings:
- "If you set `users.mutableUsers` to false, then the contents of `/etc/passwd` and `/etc/group` will be congruent to your NixOS configuration... Also, imperative commands for managing users and groups, such as `useradd`, are no longer available."
- With `mutableUsers = false` and a tmpfs root: `/etc/shadow` is recreated from the declared `initialPassword` (or `hashedPassword`) on every boot.

### Source 4: NixOS Manual — Necessary System State (Impermanence section)

URL: `https://nixos.org/manual/nixos/stable/#necessary-system-state`

Key findings:
- NixOS's "Necessary system state" section explicitly addresses impermanent systems.
- States that `users.mutableUsers` should be `false` OR the shadow/passwd/group files should be persisted.
- Lists `/var/lib/nixos` as required for stable UID/GID tracking — already persisted in the current config.
- Does NOT require `/etc/nixos` to be persisted for the system to BOOT, but it is needed for `nixos-rebuild` to function.

### Source 5: NixOS Manual — Installation Guide

URL: `https://nixos.org/manual/nixos/stable/#sec-installation-manual-installing`

Key findings:
- `nixos-install --no-root-passwd` skips the root password prompt. This is already used in `stateless-setup.sh`.
- After install, `/mnt/etc/nixos/` contains the flake and hardware config used for the build.
- Quote: "If you have a user account declared in your configuration.nix and plan to log in using this user, set a password before rebooting, e.g. for the alice user: `# nixos-enter --root /mnt -c 'passwd alice'`"

### Source 6: etu's blog — NixOS on tmpfs as root

URL: `https://elis.nu/blog/2020/05/nixos-tmpfs-as-root/` (referenced by impermanence README)

Key findings:
- Standard practice is to add `/etc/nixos` to the persistence list so that the system configuration (including flake) survives reboots.
- The pattern recommended is exactly adding `/etc/nixos` as a directory in `environment.persistence`.

---

## 4. Proposed Solution Architecture

### 4.1 Bug 1 Fix: Persist `/etc/nixos` via Impermanence

**Step A — Nix module change (`modules/impermanence.nix`):**

Add `/etc/nixos` to the `directories` list in `environment.persistence."/persistent"`:

```nix
directories =
  [
    "/var/lib/nixos"
    "/etc/nixos"       # ← ADD THIS
  ]
  ++ cfg.extraPersistDirs;
```

**Effect:** On every boot, `/persistent/etc/nixos` is bind-mounted to `/etc/nixos`. The directory must exist on the persistent volume — it is pre-populated by the install/migration scripts (Steps B and C below).

**Ordering analysis:**
1. `/persistent` is mounted (neededForBoot = true).
2. Impermanence bind mounts `/persistent/etc/nixos` → `/etc/nixos`.
3. NixOS activation script writes `environment.etc."nixos/vexos-variant"` (a symlink) into `/etc/nixos/` — which now goes into `/persistent/etc/nixos/vexos-variant`. ✓
4. `just rebuild`/`update` find `flake.nix` at `/etc/nixos/flake.nix` → `_resolve-flake-dir` succeeds. ✓

**`environment.etc` + impermanence interaction:**
`environment.etc."nixos/vexos-variant"` creates a symlink at `/etc/nixos/vexos-variant` → `/nix/store/.../vexos-variant`. Since `/etc/nixos` is bind-mounted from `/persistent/etc/nixos`, this symlink is written into the persistent subvolume. This is harmless and desirable: `vexos-variant` will be present and correct on every boot.

No other files in `/etc/nixos` are managed by `environment.etc`. `flake.nix` and `hardware-configuration.nix` are user-managed files on the persistent volume.

**Step B — `stateless-setup.sh` change:**

After `nixos-install` completes but **before** the reboot prompt, add a step that copies the flake and hardware config to the persistent subvolume:

Insert between the end of nixos-install and the reboot offer:

```bash
# ---------- Populate /persistent/etc/nixos (survives stateless reboot) -------
echo ""
echo -e "${BOLD}Copying configuration to persistent storage...${RESET}"
sudo mkdir -p /mnt/persistent/etc/nixos
sudo cp /mnt/etc/nixos/flake.nix /mnt/persistent/etc/nixos/flake.nix
sudo cp /mnt/etc/nixos/hardware-configuration.nix /mnt/persistent/etc/nixos/hardware-configuration.nix
echo -e "${GREEN}  ✓ flake.nix and hardware-configuration.nix → /persistent/etc/nixos/${RESET}"
```

**Why `/mnt/persistent` is available:** disko mounted the @persist Btrfs subvolume at `/mnt/persistent` during the format-and-mount phase. This path is accessible throughout the install process.

**Also add the password warning:** After the completion banner and before the reboot prompt:

```bash
echo -e "${BOLD}${YELLOW}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${RESET}"
echo -e "${YELLOW}  IMPORTANT — STATELESS LOGIN PASSWORD${RESET}"
echo -e "${BOLD}${YELLOW}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${RESET}"
echo ""
echo -e "  The 'nimda' user password is set to: ${BOLD}vexos${RESET}"
echo ""
echo -e "  Because users.mutableUsers = false and / is a tmpfs:"
echo -e "  • Passwords changed at runtime DO NOT survive a reboot."
echo -e "  • On every boot, the password resets to 'vexos'."
echo ""
echo -e "  To change the default password permanently:"
echo -e "  Edit configuration-stateless.nix, change initialPassword or use"
echo -e "  hashedPassword, and rebuild."
echo ""
```

**Step C — `migrate-to-stateless.sh` change:**

The migration script already mounts the raw Btrfs at `${BTRFS_MOUNT}` at step 16 (the `/nix` → `@nix` sync). While the Btrfs is mounted at that point, also copy `/etc/nixos` to `@persist`:

Insert within the existing "Sync /nix → @nix" block, after the cp of `/nix`:

```bash
# ---------- Copy /etc/nixos → @persist/etc/nixos ----------------------------
echo ""
echo -e "${BOLD}Copying /etc/nixos to persistent storage...${RESET}"
sudo mkdir -p "${BTRFS_MOUNT}/@persist/etc/nixos"
sudo cp /etc/nixos/flake.nix "${BTRFS_MOUNT}/@persist/etc/nixos/flake.nix" 2>/dev/null || \
    echo -e "${YELLOW}  Warning: /etc/nixos/flake.nix not found — copy it manually after reboot${RESET}"
sudo cp /etc/nixos/hardware-configuration.nix "${BTRFS_MOUNT}/@persist/etc/nixos/hardware-configuration.nix" 2>/dev/null || \
    echo -e "${YELLOW}  Warning: /etc/nixos/hardware-configuration.nix not found${RESET}"
echo -e "${GREEN}  ✓ /etc/nixos/ → @persist/etc/nixos/${RESET}"
```

**Why this location and timing:** After `nixos-rebuild boot`, the hardware-configuration.nix has been updated with the stateless filesystem entries. The raw Btrfs is remounted at `${BTRFS_MOUNT}` for the `/nix` sync. We can write to `${BTRFS_MOUNT}/@persist/etc/nixos/` at this same time.

**Also add the password warning** to `migrate-to-stateless.sh` just before the reboot prompt:

```bash
echo -e "${BOLD}${YELLOW}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${RESET}"
echo -e "${YELLOW}  IMPORTANT — STATELESS LOGIN PASSWORD${RESET}"
echo -e "${BOLD}${YELLOW}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${RESET}"
echo ""
echo -e "  After rebooting into stateless mode, the 'nimda' user"
echo -e "  password will be reset to: ${BOLD}vexos${RESET}"
echo ""
echo -e "  Because users.mutableUsers = false and / is a tmpfs:"
echo -e "  • Your current password will NOT carry over."
echo -e "  • On every boot, the password resets to 'vexos'."
echo ""
echo -e "  To change the default password permanently:"
echo -e "  Edit configuration-stateless.nix, change initialPassword or use"
echo -e "  hashedPassword, and rebuild."
echo ""
```

### 4.2 Bug 2 Fix: Inform Users About Password Behavior

The password warning messages described in Steps B and C above cover Bug 2 for the install and migration paths.

Additionally, the `justfile` `default` recipe stateless section (see §4.3) will show a brief reminder to users already running the stateless role.

### 4.3 Justfile `default` Recipe — Stateless Section

Add an `elif` branch for the stateless role, analogous to the existing server role section:

```bash
elif [[ "$variant" == *stateless* ]]; then
    echo ""
    echo "Available recipes (stateless role):"
    echo "    switch               Rebuild and switch interactively"
    echo "    rebuild              Rebuild using current variant"
    echo "    update               Update flake inputs and rebuild"
    echo "    build <role> <gpu>   Dry-run build (no switch)"
    echo "    variant              Print current active variant"
    echo ""
    echo "Note: This is a stateless system."
    echo "      / is a fresh tmpfs on every reboot — runtime changes are NOT persisted."
    echo "      Login password resets to 'vexos' on every reboot."
fi
```

This should be placed as an `elif` after the existing `if [[ "$variant" == *server* ]]` block.

---

## 5. Implementation Steps

### File 1: `modules/impermanence.nix`

**Location:** Inside `environment.persistence."${cfg.persistentPath}"` → `directories` list

**Change:** Add `"/etc/nixos"` to the `directories` list between `/var/lib/nixos` and the `++ cfg.extraPersistDirs`.

**Exact diff intent:**
```nix
# Before:
directories =
  [
    "/var/lib/nixos"
  ]
  ++ cfg.extraPersistDirs;

# After:
directories =
  [
    "/var/lib/nixos"

    # Persist the NixOS configuration directory (flake.nix, hardware-configuration.nix).
    # Without this, just rebuild / just update fail on every reboot because
    # flake.nix is wiped with the ephemeral tmpfs root.
    # The install and migration scripts pre-populate /persistent/etc/nixos/
    # before the first stateless boot.
    "/etc/nixos"
  ]
  ++ cfg.extraPersistDirs;
```

### File 2: `scripts/stateless-setup.sh`

Two additions, both after the `nixos-install` success banner:

**Addition 1 — Populate persistent config:**

Insert after the line:
```bash
sudo nixos-install \
  --no-root-passwd \
  --flake "/mnt/etc/nixos#${FLAKE_TARGET}"
```

and before the completion echo block.

**Addition 2 — Password warning:**

Insert after the `✓ VexOS Stateless installation complete!` banner block, before the `Next steps:` block.

### File 3: `scripts/migrate-to-stateless.sh`

Two additions:

**Addition 1 — Copy /etc/nixos to @persist:**

Insert inside the "Sync /nix → @nix subvolume" block, after the `cp -a --reflink=always /nix/. "${BTRFS_MOUNT}/@nix/"` line and before the umount.

**Addition 2 — Password warning:**

Insert after the `✓ Migration to stateless complete!` banner, before the `Next steps:` block.

### File 4: `justfile`

**Change location:** Inside the `default` recipe's `#!/usr/bin/env bash` block, after the closing `fi` of the server role `if` block.

**Change:** Replace the bare `if` with `if ... elif ... fi` pattern to include the stateless branch.

---

## 6. Risks and Edge Cases

### 6.1 First-Boot Race: Impermanence Creates Empty `/persistent/etc/nixos/`

**Risk:** If `/persistent/etc/nixos` does not exist when the impermanence module runs on first boot, the module creates it as an empty directory. The bind mount succeeds, but `/etc/nixos/` is empty (no `flake.nix`).

**Mitigation:** The install/migration scripts (Steps B and C) pre-populate `/persistent/etc/nixos/` before the first stateless boot. This risk is only present if a user bypasses the scripts and manually sets up the system without copying the files.

**Residual risk:** Acceptable. Users who manually set up the system can copy the files themselves by following the error output of `_resolve-flake-dir`.

### 6.2 `environment.etc` Symlink Written to Persistent Storage

**Risk:** `environment.etc."nixos/vexos-variant"` writes a symlink into `/persistent/etc/nixos/vexos-variant`. This symlink points to a Nix store path that may change on rebuild.

**Mitigated by design:** The symlink is recreated on every NixOS activation (every boot + every rebuild). The symlink destination always points to the current generation's store path. The file `cat /etc/nixos/vexos-variant` correctly follows the symlink.

**Side effect (desirable):** The `vexos-variant` file now also persists on the persistent volume, meaning that even without a running NixOS activation, a future boot would still find the last-written variant file in `/persistent/etc/nixos/vexos-variant`. This is harmless.

### 6.3 `git -C /mnt/etc/nixos add .` in `stateless-setup.sh`

**Risk:** The post-install copy step adds files to `/mnt/persistent/etc/nixos/`. These are copied **after** nixos-install, so the git staging and narHash binding for nixos-install is not affected. The git repo at `/mnt/etc/nixos/.git` is not copied (`.gitignore` / shell `cp` default behavior).

**Mitigation:** We copy only `flake.nix` and `hardware-configuration.nix` explicitly, not the `.git` directory. After the first stateless reboot and impermanence binding, NixOS will use `/etc/nixos/flake.nix` as a plain file (not a git repo), which is the standard and correct thin-wrapper usage.

### 6.4 Permissions on `/persistent/etc/nixos`

**Risk:** impermanence creates directories with default permissions. `/etc/nixos` on a standard NixOS system is owned by `root:root` with mode `755`.

**Mitigation:** The impermanence module creates non-existent directories with default mode. The explicit `mkdir -p` in the scripts uses root (sudo), creating the directory as `root:root 755`. No special ownership override is needed.

### 6.5 `migrate-to-stateless.sh`: `/etc/nixos/flake.nix` May Not Exist

**Risk:** A user running the migration might not have the thin wrapper `flake.nix` in their current `/etc/nixos/`. They may be running their system configuration directly without the thin-wrapper pattern.

**Mitigation:** The copy step in `migrate-to-stateless.sh` uses `2>/dev/null || echo warning` to not abort on missing files. A warning is shown. The `flake.nix` can be manually placed at `/persistent/etc/nixos/flake.nix` after reboot if needed. This is an edge case — the migration script is documented as targeting VexOS systems that should already have the template flake in place.

### 6.6 Password Warning Is Informational Only

**Risk:** The password warning messages in the scripts do not enforce any password change. Users can still ignore them and be surprised after reboot.

**Mitigation:** The warning is placed prominently before the reboot prompt, with visual emphasis. The `justfile` `default` recipe also reminds users on every `just` invocation on the stateless role. Enforcing a mandatory password change would break the unattended install use case.

### 6.7 No New Dependencies

This feature adds no new Nix flake inputs, no new packages, and no new external dependencies. All changes are to existing Nix and shell script files.

---

## 7. Affected Files Summary

| File | Change Type | Description |
|---|---|---|
| `modules/impermanence.nix` | Edit | Add `/etc/nixos` to `environment.persistence."/persistent".directories` |
| `scripts/stateless-setup.sh` | Edit | Add post-install copy to `/mnt/persistent/etc/nixos/` + password warning |
| `scripts/migrate-to-stateless.sh` | Edit | Add copy of `/etc/nixos` to `@persist` + password warning |
| `justfile` | Edit | Add stateless role section in `default` recipe |

---

## 8. Files to Be Modified in Phase 2

1. `modules/impermanence.nix`
2. `scripts/stateless-setup.sh`
3. `scripts/migrate-to-stateless.sh`
4. `justfile`
