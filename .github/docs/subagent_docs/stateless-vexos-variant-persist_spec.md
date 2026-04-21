# Specification: Persist `/etc/nixos/vexos-variant` Across Reboots

**Feature Name:** `stateless-vexos-variant-persist`  
**Date:** 2026-04-20  
**Status:** Draft — awaiting implementation  

---

## 1. Current State Analysis

### 1.1 Impermanence Persistence Configuration

**File:** `modules/impermanence.nix`

The module declares the following `environment.persistence` block when `vexos.impermanence.enable = true`:

```nix
environment.persistence."${cfg.persistentPath}" = {
  hideMounts = true;

  directories = [
    "/var/lib/nixos"
    "/etc/nixos"           # ← entire /etc/nixos directory is bind-mounted
                           #   from /persistent/etc/nixos on every boot
  ] ++ cfg.extraPersistDirs;

  files = [
    # /etc/machine-id is intentionally NOT persisted
    # "/etc/machine-id"
  ] ++ cfg.extraPersistFiles;
};
```

**Key observation:** `/etc/nixos` is persisted as a **directory** bind-mount from
`/persistent/etc/nixos`. Any file that exists in `/persistent/etc/nixos/` at boot time
will be visible at `/etc/nixos/` after the bind-mount is established.
`/etc/nixos/vexos-variant` is **not** listed separately in the `files` section.

### 1.2 Activation Script for `vexos-variant`

**File:** `modules/impermanence.nix` (lines ~230–242)

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

**Condition:** Only fires when `config.vexos.variant != ""`.

**Host configuration setting this option:**

```nix
# hosts/stateless-amd.nix
vexos.variant = "vexos-stateless-amd";

# hosts/stateless-nvidia.nix
vexos.variant = "vexos-stateless-nvidia";
# (and so on for all stateless-* hosts)
```

**Thin-wrapper path** (`template/etc-nixos-flake.nix`, `mkStatelessVariant`):

```nix
{
  system.activationScripts.vexosVariant = ''
    PERSIST_DIR="/persistent/etc/nixos"
    mkdir -p "$PERSIST_DIR"
    printf '%s' '${variant}' > "$PERSIST_DIR/vexos-variant"
  '';
}
```

The thin wrapper defines its own inline activation script. `vexos.variant` (the Nix option)
is **never set** in thin-wrapper builds; the `lib.mkIf (config.vexos.variant != "")` condition
in `modules/impermanence.nix` therefore evaluates to **false** — that script does not execute.
Only the thin wrapper's inline script runs.

### 1.3 Files Explicitly Persisted to the Btrfs `@persist` Subvolume by Setup Scripts

#### `scripts/stateless-setup.sh` (post-`nixos-install` copy block)

```bash
sudo mkdir -p /mnt/persistent/etc/nixos
sudo cp /mnt/etc/nixos/hardware-configuration.nix /mnt/persistent/etc/nixos/ 2>/dev/null || true
sudo cp /mnt/etc/nixos/flake.nix                  /mnt/persistent/etc/nixos/ 2>/dev/null || true
sudo cp /mnt/etc/nixos/flake.lock                 /mnt/persistent/etc/nixos/ 2>/dev/null || true
sudo cp /mnt/etc/nixos/stateless-user-override.nix /mnt/persistent/etc/nixos/ 2>/dev/null || true
# ← vexos-variant is NOT copied here
```

#### `scripts/migrate-to-stateless.sh` (post-`nixos-rebuild boot` copy block)

```bash
mkdir -p "${BTRFS_MOUNT}/@persist/etc/nixos"
cp /etc/nixos/flake.nix                  "${BTRFS_MOUNT}/@persist/etc/nixos/" ...
cp /etc/nixos/flake.lock                 "${BTRFS_MOUNT}/@persist/etc/nixos/" ...
cp /etc/nixos/hardware-configuration.nix "${BTRFS_MOUNT}/@persist/etc/nixos/" ...
cp /etc/nixos/stateless-user-override.nix "${BTRFS_MOUNT}/@persist/etc/nixos/" ...
# ← vexos-variant is NOT copied here either
```

---

## 2. Problem Definition

### 2.1 Root Cause

The `/etc/nixos/vexos-variant` file is written by `system.activationScripts.vexosVariant`
on each activation (every boot or `nixos-rebuild switch`). This relies on:

1. `/persistent` being mounted (satisfied — `neededForBoot = true`).
2. The `VARIANT` variable being known (satisfied — hardcoded in the activation script per host).

**The gap is the FIRST BOOT after a fresh installation:**

During `nixos-install` (ISO path) the activation scripts run **inside a chroot at `/mnt`**.
NixOS's `nixos-install` only bind-mounts `/nix`, `/dev`, `/dev/pts`, `/proc`, and `/sys`
into the chroot. The `/persistent` mount is **not** bind-mounted into this chroot.

Consequently, when the `vexosVariant` activation script executes during `nixos-install`:

```bash
PERSIST_DIR="/persistent/etc/nixos"
mkdir -p "$PERSIST_DIR"   # creates /persistent/etc/nixos on the CHROOT'S TMPFS
printf '%s' '...' > "$PERSIST_DIR/vexos-variant"  # written to tmpfs, then DISCARDED
```

The file is written to the **ephemeral** chroot tmpfs path, never reaching the actual
Btrfs `@persist` subvolume mounted at `/mnt/persistent`. After `nixos-install` exits and
the chroot is dismounted, the file is gone.

`stateless-setup.sh` then explicitly copies surviving files to `/mnt/persistent/etc/nixos/`
but does **not** include `vexos-variant` in that list — because the file doesn't exist at
`/mnt/etc/nixos/vexos-variant` either (it was only ever written inside the isolated chroot).

**After the first real boot**, `nixos-activation.service` runs the activation scripts with
`/persistent` properly mounted, and the file is created. From that point the file persists
across subsequent reboots via the `/etc/nixos` directory bind-mount.

**For the migration path** (`migrate-to-stateless.sh`), `nixos-rebuild boot` is used (not
`switch`). Activation scripts do **not** run during `nixos-rebuild boot`; they run only on
the next boot. The migration script's `@persist` copy block runs before that reboot but does
not include `vexos-variant`. Result: the file is absent on the first stateless boot in cases
where there was no previous `vexos-variant` in `/etc/nixos/`.

### 2.2 Practical Impact

- Tools that read `/etc/nixos/vexos-variant` before the very first `nixos-rebuild switch`
  (e.g., `vexos-updater`, `just rebuild`, `just update`) may fail on the first post-install boot.
- On any fresh install via `stateless-setup.sh`, the updater tool cannot determine the
  correct rebuild target on first boot because `vexos-variant` does not yet exist.
- The migration path has the same gap on the first stateless boot.

### 2.3 Why "Add to `files` List" Would Not Work

The natural first instinct is to add `"/etc/nixos/vexos-variant"` to the `files` list in
`modules/impermanence.nix`. This is **incorrect** because:

- `/etc/nixos` is already in the `directories` persistence list, creating a bind-mount:
  `/etc/nixos` → `/persistent/etc/nixos`.
- Adding a separate `files` entry for `/etc/nixos/vexos-variant` → `/persistent/etc/nixos/vexos-variant`
  would instruct `nix-community/impermanence` to create a **second** systemd mount unit
  targetting a path that already resolves through the directory bind-mount — effectively
  binding a path to itself. This causes a systemd mount conflict on boot.

---

## 3. Proposed Solution

### 3.1 Approach: Explicit Write in Setup Scripts

Both setup scripts already know the target variant at their point of execution (the `VARIANT`
variable is user-selected). Both already have a shell block that explicitly copies named files
to the persistent Btrfs subvolume. The fix is to add `vexos-variant` to both of those blocks.

This is the minimal, zero-risk change — no impermanence configuration is altered, no existing
boot-time behaviour changes. The file simply exists in `@persist` from day one, and the
existing activation-script mechanism continues to maintain it on every subsequent activation.

### 3.2 Exact Changes Required

#### `scripts/stateless-setup.sh`

In the **"Persisting NixOS config files to /persistent"** block (after `nixos-install`),
add one line to write the variant to the persistent path:

```bash
# EXISTING block (preserve all existing lines):
sudo mkdir -p /mnt/persistent/etc/nixos
sudo cp /mnt/etc/nixos/hardware-configuration.nix /mnt/persistent/etc/nixos/ 2>/dev/null || true
sudo cp /mnt/etc/nixos/flake.nix                  /mnt/persistent/etc/nixos/ 2>/dev/null || true
sudo cp /mnt/etc/nixos/flake.lock                 /mnt/persistent/etc/nixos/ 2>/dev/null || true
sudo cp /mnt/etc/nixos/stateless-user-override.nix /mnt/persistent/etc/nixos/ 2>/dev/null || true

# ADD this line immediately after the existing copies:
printf '%s' "vexos-stateless-${VARIANT}" | sudo tee /mnt/persistent/etc/nixos/vexos-variant > /dev/null
```

`VARIANT` is the shell variable already set (e.g., `"amd"`, `"nvidia"`, `"intel"`, `"vm"`)
so the resulting file content is `vexos-stateless-amd` (to match what the activation script
and host configuration produce).

#### `scripts/migrate-to-stateless.sh`

In the **"Persisting NixOS config files to @persist"** block, add one line:

```bash
# EXISTING block (preserve all existing lines):
mkdir -p "${BTRFS_MOUNT}/@persist/etc/nixos"
cp /etc/nixos/flake.nix                  "${BTRFS_MOUNT}/@persist/etc/nixos/" ...
cp /etc/nixos/flake.lock                 "${BTRFS_MOUNT}/@persist/etc/nixos/" ...
cp /etc/nixos/hardware-configuration.nix "${BTRFS_MOUNT}/@persist/etc/nixos/" ...
cp /etc/nixos/stateless-user-override.nix "${BTRFS_MOUNT}/@persist/etc/nixos/" ...

# ADD this line immediately after the existing copies:
printf '%s' "vexos-stateless-${VARIANT}" > "${BTRFS_MOUNT}/@persist/etc/nixos/vexos-variant"
echo -e "  ${GREEN}✓ vexos-variant persisted${RESET}"
```

`VARIANT` is already set by the user prompt at the top of `migrate-to-stateless.sh`.

---

## 4. Implementation Steps

1. **Open `scripts/stateless-setup.sh`**.  
   Locate the `"Persisting NixOS config files to /persistent"` block (after `nixos-install` completes).  
   Insert the `printf ... | sudo tee` line immediately after the last `sudo cp` line in that block.

2. **Open `scripts/migrate-to-stateless.sh`**.  
   Locate the `"Persisting NixOS config files to @persist"` block (after `nixos-rebuild boot` and the `@nix` rsync).  
   Insert the `printf ... > "${BTRFS_MOUNT}/@persist/etc/nixos/vexos-variant"` line and the corresponding `echo` status message immediately after the last `cp ... || true` line in that block.

3. **No changes to `modules/impermanence.nix`** — the existing activation script correctly
   maintains the file on every subsequent activation. The impermanence directory mount for
   `/etc/nixos` already ensures it persists. The only gap was the initial creation during setup.

4. **No changes to `flake.nix`, `template/etc-nixos-flake.nix`, or any host file** — all
   existing mechanisms remain intact and complement this fix.

5. **Validation after implementation:**
   - Run `nix flake check --no-build --impure` — must pass.
   - Run `sudo nixos-rebuild dry-build --flake .#vexos-stateless-amd` — must pass.
   - Inspect `scripts/stateless-setup.sh` for the new line and verify `VARIANT` is in scope.
   - Inspect `scripts/migrate-to-stateless.sh` for the new line and verify `VARIANT` and
     `BTRFS_MOUNT` are both in scope at the insertion point.

---

## 5. Files to Be Modified

| File | Change |
|------|--------|
| `scripts/stateless-setup.sh` | Add `vexos-variant` write after the existing persistent-copy block |
| `scripts/migrate-to-stateless.sh` | Add `vexos-variant` write after the existing `@persist` copy block |

**Files NOT modified:**
- `modules/impermanence.nix` — no change needed; directory mount + activation script is correct
- `flake.nix` — no change needed
- `template/etc-nixos-flake.nix` — no change needed
- Any `hosts/stateless-*.nix` — no change needed

---

## 6. Risks and Mitigations

| Risk | Likelihood | Mitigation |
|------|------------|------------|
| `VARIANT` variable out of scope at insertion point | Low | Verified — `VARIANT` is set early in both scripts and remains in scope through the setup/migration completion block |
| Content mismatch between `printf`-written file and activation-script-written file | Low | Both write `vexos-stateless-${VARIANT}` — format matches exactly what the activation script writes for all host variants |
| `printf` failing due to permissions | Very Low | In `stateless-setup.sh`, all operations in that block are `sudo`; `tee` is used for the write. In `migrate-to-stateless.sh`, the script already requires `root`. |
| Redundant file in future if activation script is removed | Negligible | If the activation script were removed, the setup-script write still ensures first-boot availability; the file would simply not be refreshed on each boot (which is fine — the content is stable per-variant). |
| Flake check or dry-build failure | Very Low | These are shell script changes only (not Nix expressions); they have no effect on flake evaluation or NixOS closure builds. |

---

## 7. Spec File Path

`/home/nimda/Projects/vexos-nix/.github/docs/subagent_docs/stateless-vexos-variant-persist_spec.md`
