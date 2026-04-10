# Impermanence for VexOS Privacy Role — Implementation Specification

**Feature name:** `impermanence`
**Target role:** Privacy (`configuration-privacy.nix`, `hosts/privacy-*.nix`)
**NixOS version:** 25.11
**Date:** 2026-04-10
**Status:** RESEARCH COMPLETE — READY FOR IMPLEMENTATION

---

## 1. Current State Analysis

### 1.1 Privacy role structure

The project defines four privacy builds, all sharing one base configuration:

| Flake output | Host file | GPU module |
|---|---|---|
| `vexos-privacy-amd` | `hosts/privacy-amd.nix` | `modules/gpu/amd.nix` |
| `vexos-privacy-nvidia` | `hosts/privacy-nvidia.nix` | `modules/gpu/nvidia.nix` |
| `vexos-privacy-intel` | `hosts/privacy-intel.nix` | `modules/gpu/intel.nix` |
| `vexos-privacy-vm` | `hosts/privacy-vm.nix` | `modules/gpu/vm.nix` |

All four import `configuration-privacy.nix`, which imports:
- `modules/gnome.nix`
- `modules/audio.nix`
- `modules/gpu.nix`
- `modules/flatpak.nix`
- `modules/network.nix`
- `modules/packages.nix`
- `modules/branding.nix`
- `modules/system.nix`

### 1.2 What is currently NOT present

- No tmpfs root or Btrfs rollback configuration
- No `nix-community/impermanence` flake input or module
- No ephemerality guarantees — state persists across reboots as on any standard NixOS system
- No declared set of persistent vs ephemeral paths
- Swap file enabled by default (`vexos.swap.enable = true` in `modules/system.nix`); this writes to `/var/lib/swapfile` which cannot survive a tmpfs root without redirection

### 1.3 Existing relevant infrastructure

- `modules/system.nix` provides `vexos.btrfs.enable` and `vexos.swap.enable` options — the swap option must be force-disabled for privacy builds
- `flake.nix` already passes `specialArgs = { inherit inputs; }` to all configurations, which means any module can receive `inputs` and import flake-provided modules
- `configuration-privacy.nix` sets `networking.hostName = lib.mkDefault "vexos-privacy"` and includes only the non-gaming/non-dev module subset — privacy-appropriate
- The user is `nimda`; no password is currently set declaratively (mutable users are the default)

---

## 2. Problem Definition

The vexos privacy role is intended to behave like a **privacy-first live system** — similar to Tails Linux or a Deep Freeze / bilibop-style locked filesystem — where:

1. **Nothing outside of explicitly declared locations persists between reboots.** All session activity (browsing history, downloaded files, GNOME settings, temporary files, logs, crash dumps) is discarded when the system powers off or reboots.
2. **The underlying Nix store remains intact** so the system boots fully functional without a network connection.
3. **Optional encrypted persistent storage** is available for users who need to retain specific data (GPG keys, SSH identities, VPN configurations) in a LUKS-encrypted volume.
4. **Both AMD and NVIDIA GPU drivers work correctly.** All GPU firmware and kernel modules are in `/nix/store` and are unaffected by root ephemerality.

Without this, the privacy role is functionally identical to a standard desktop installation — state accumulates in `/etc`, `/var`, and user home directories and persists indefinitely.

---

## 3. Approaches Considered

### 3.1 Approach A — tmpfs root (RECOMMENDED)

Mount `/` as `tmpfs` (RAM-backed). Only `/boot` and `/nix` live on physical disk. An optional LUKS-encrypted `/persistent` subvolume holds any declared persistent state managed by the impermanence module.

**Pros:**
- Simplest conceptual model — nothing outside `/nix` and `/boot` ever touches disk
- No forensic disk artifacts from session activity (files never written to NAND/HDD)
- No initrd rollback scripts required — tmpfs is wiped automatically on power loss
- Fully compatible with both AMD and NVIDIA (drivers live in `/nix/store`)
- Works with LUKS — the nix + persist partitions sit behind dm-crypt
- Small RAM overhead: `/` on a running NixOS system contains mostly symlinks and a few small configuration files; actual package binaries all reside in `/nix/store`

**Cons:**
- RAM constraint: large runtime writes to `/tmp` or `/var/tmp` consume RAM
- If the system crashes mid-session, in-progress work is lost (same as Tails)
- Requires the user to partition their disk correctly before first install (documented below)

**RAM requirements:**
- Minimum recommended: 8 GB physical RAM
- tmpfs `/` will use a configured percentage (default: `25%`) — at 8 GB this is 2 GB, which is ample for the `/` namespace (symlinks, /etc, /var, /run, /tmp)
- `/nix/store` is NOT in tmpfs; it is on the encrypted disk

### 3.2 Approach B — Btrfs subvolume rollback

The root subvolume `/` is mounted from a Btrfs volume. During `boot.initrd.postResumeCommands`, the current root subvolume is renamed/archived and a fresh subvolume is created from a blank snapshot.

**Pros:**
- Does not consume RAM for `/`
- Old roots are retained on disk for a configurable window (e.g., 30 days) — useful for recovery after a bad configuration
- Compatible with LUKS on the Btrfs volume

**Cons:**
- More complex initrd scripting required; must handle nested subvolumes (systemd creates subvolumes under `/var/lib/machines`, `/var/lib/portables`)
- Session data DOES touch physical disk before rollback — creates forensic artifacts recoverable until the next GC/TRIM
- Disk space is consumed by ephemeral session state and old roots
- Less "pure" from a privacy standpoint

### 3.3 Approach C — ZFS rollback (grahamc's method)

Create a ZFS dataset for `/`, snapshot it blank, and roll back on each boot via `boot.initrd.postDeviceCommands`.

**Pros:**
- Battle-tested; widely documented
- `zfs diff` allows auditing what state was created in a session

**Cons:**
- ZFS is not the existing filesystem strategy in this project — `modules/system.nix` auto-detects Btrfs
- ZFS requires additional kernel module (`zfs`) and `boot.supportedFilesystems = ["zfs"]`
- ZFS licensing complexity with Linux kernel (CDDL vs GPL)
- More complex than tmpfs for a privacy-focused use case

### 3.4 Approach D — EROFS/SquashFS overlay

Mount a compressed read-only root image with an overlay tmpfs layer.

**Cons:**
- Requires pre-built root image; incompatible with standard NixOS activation
- Not supported natively by nixpkgs NixOS modules
- Does not compose with the impermanence module
- **Rejected**

### 3.5 Decision

**Use Approach A (tmpfs root)** with the `nix-community/impermanence` module for declarative persistence management.

Rationale:
- Maximum privacy: session files never touch physical storage
- Simplest implementation: no initrd rollback scripts
- Fully composable with the existing flake and module structure
- The impermanence module's `enable` flag allows the same `modules/impermanence.nix` to be imported by all privacy builds without breaking non-privacy builds if ever added to commonModules

---

## 4. Architecture Design

### 4.1 Disk layout (hardware-configuration.nix — user-managed)

The user must partition their disk and create the following:

```
/dev/sdX1   512 MB   vfat     EFI System Partition  → /boot
/dev/sdX2   rest     LUKS     Encrypted Btrfs volume containing:
                                  subvol @nix       → /nix        (required)
                                  subvol @persist   → /persistent (optional, for persistent state)
```

`/` is not a disk partition — it is a tmpfs.

LUKS encryption commands (run during install):
```bash
cryptsetup --verify-passphrase -v luksFormat /dev/sdX2
cryptsetup open /dev/sdX2 cryptroot

mkfs.btrfs /dev/mapper/cryptroot

mount /dev/mapper/cryptroot /mnt
btrfs subvolume create /mnt/@nix
btrfs subvolume create /mnt/@persist
umount /mnt

# Mount for install
mount -t tmpfs -o size=25%,mode=755 none /mnt
mkdir -p /mnt/{boot,nix,persistent}
mount -o subvol=@nix,compress=zstd,noatime /dev/mapper/cryptroot /mnt/nix
mount -o subvol=@persist,compress=zstd,noatime /dev/mapper/cryptroot /mnt/persistent
mount /dev/sdX1 /mnt/boot

nixos-generate-config --root /mnt
```

### 4.2 hardware-configuration.nix additions (user-managed)

The following must be present in the host's `/etc/nixos/hardware-configuration.nix`. This is a template; the user substitutes real UUIDs:

```nix
# Ephemeral root — wiped on every reboot
fileSystems."/" = {
  device = "none";
  fsType = "tmpfs";
  options = [ "defaults" "size=25%" "mode=755" ];
};

# LUKS device — unlocked at initrd stage
boot.initrd.luks.devices."cryptroot" = {
  device = "/dev/disk/by-uuid/XXXXXXXX-XXXX-XXXX-XXXX-XXXXXXXXXXXX";
  allowDiscards = true;  # Enable TRIM for SSDs
};

# Nix store — persistent, inside LUKS
fileSystems."/nix" = {
  device = "/dev/disk/by-uuid/YYYYYYYY-YYYY-YYYY-YYYY-YYYYYYYYYYYY";  # UUID of /dev/mapper/cryptroot
  fsType = "btrfs";
  options = [ "subvol=@nix" "compress=zstd" "noatime" ];
  neededForBoot = true;
};

# Optional persistent state — inside LUKS (only if user wants persistent storage)
fileSystems."/persistent" = {
  device = "/dev/disk/by-uuid/YYYYYYYY-YYYY-YYYY-YYYY-YYYYYYYYYYYY";
  fsType = "btrfs";
  options = [ "subvol=@persist" "compress=zstd" "noatime" ];
  neededForBoot = true;  # REQUIRED for impermanence bind mounts to work
};

# EFI boot partition
fileSystems."/boot" = {
  device = "/dev/disk/by-uuid/ZZZZ-ZZZZ";
  fsType = "vfat";
};
```

> **IMPORTANT:** The persistent partition's `neededForBoot = true` is required by the impermanence module. Without it, bind mounts will fail during early userspace initialization.

### 4.3 Module: `modules/impermanence.nix` (new file)

This module is imported by `configuration-privacy.nix`. It:

1. Declares the `vexos.impermanence.enable` option (default: `false`)
2. Declares the `vexos.impermanence.persistentPath` option (default: `"/persistent"`)
3. When `enable = true`:
   - Imports `inputs.impermanence.nixosModules.impermanence`
   - Forces `vexos.swap.enable = false` (no swapfile on tmpfs root)
   - Sets `users.mutableUsers = false` (declarative password required)
   - Configures `environment.persistence.<path>` with the minimal required entries
   - Disables persistent systemd journal (journal stored in RAM)
   - Sets `security.sudo.extraConfig` to suppress the sudo lecture (resets on each reboot otherwise)
   - Disables Nix store GC on privacy builds (or redirects to acceptable behavior)
   - Provides an assertion that the persistent path exists in `config.fileSystems` with `neededForBoot = true`

### 4.4 Changes to `configuration-privacy.nix`

1. Add `./modules/impermanence.nix` to the `imports` list
2. Set `vexos.impermanence.enable = true`
3. Set `users.users.nimda.initialPassword = "vexos"` (documented as default session password — changes do not persist)
4. Remove unnecessary Nix store GC that conflicts with impermanence (the GC config is fine since `/nix` is persistent)

### 4.5 Changes to `flake.nix`

Add the `impermanence` input:

```nix
impermanence = {
  url = "github:nix-community/impermanence";
  inputs.nixpkgs.follows = "nixpkgs";
  inputs.home-manager.follows = "home-manager";
};
```

Update the `outputs` declaration to destructure `impermanence`:

```nix
outputs = { self, nixpkgs, nixpkgs-unstable, nix-gaming, home-manager, impermanence, ... }@inputs:
```

Pass `impermanence` through `inputs` (already available via `specialArgs = { inherit inputs; }`). No changes to individual privacy host entries are required.

### 4.6 Changes to `hosts/privacy-*.nix`

**No changes required.** The impermanence module is imported and enabled at the `configuration-privacy.nix` level, which is shared by all four privacy host files.

---

## 5. New File: `modules/impermanence.nix` — Full Implementation

```nix
# modules/impermanence.nix
# Filesystem impermanence for the VexOS privacy role.
#
# This module implements a tmpfs-rooted NixOS system where everything
# outside of /nix and /persistent is wiped on every reboot, providing
# Tails-like ephemeral behavior.
#
# PREREQUISITES (in host's hardware-configuration.nix):
#   fileSystems."/" = { device = "none"; fsType = "tmpfs"; options = [...]; };
#   fileSystems."/nix" = { ...; neededForBoot = true; };
#   fileSystems."/persistent" = { ...; neededForBoot = true; };
#
# See the impermanence_spec.md for full disk partitioning and
# hardware-configuration.nix instructions.
{ config, lib, inputs, pkgs, ... }:

let
  cfg = config.vexos.impermanence;
in
{
  imports = lib.optionals cfg.enable [
    inputs.impermanence.nixosModules.impermanence
  ];

  options.vexos.impermanence = {
    enable = lib.mkOption {
      type    = lib.types.bool;
      default = false;
      description = ''
        Enable tmpfs-rooted impermanence for the privacy role.
        When true, / is expected to be tmpfs and all state outside
        /nix is ephemeral unless declared under environment.persistence.
        Requires hardware-configuration.nix to mount / as tmpfs and
        /persistent as a neededForBoot persistent volume.
      '';
    };

    persistentPath = lib.mkOption {
      type    = lib.types.str;
      default = "/persistent";
      description = ''
        Absolute path to the persistent storage volume.
        Must be declared in hardware-configuration.nix with neededForBoot = true.
      '';
    };
  };

  config = lib.mkIf cfg.enable {

    # ── Assertion: persistent path must be mounted early ─────────────────
    assertions = [
      {
        assertion =
          (config.fileSystems ? "${cfg.persistentPath}") &&
          (config.fileSystems."${cfg.persistentPath}".neededForBoot or false);
        message = ''
          vexos.impermanence.enable = true requires fileSystems."${cfg.persistentPath}"
          to be declared in hardware-configuration.nix with neededForBoot = true.
          Impermanence bind mounts will silently fail without this.
        '';
      }
      {
        assertion = (config.fileSystems ? "/") &&
          (config.fileSystems."/".fsType == "tmpfs");
        message = ''
          vexos.impermanence.enable = true requires fileSystems."/" to be of
          type "tmpfs" in hardware-configuration.nix.
        '';
      }
    ];

    # ── Disable disk-backed swap (incompatible with tmpfs root) ──────────
    # Swapfile at /var/lib/swapfile cannot survive tmpfs root.
    # ZRAM provides compressed in-RAM swap (configured in modules/system.nix).
    vexos.swap.enable = lib.mkForce false;

    # ── Declarative user management (passwords must be in config) ────────
    # With tmpfs root, /etc/shadow is recreated from the Nix configuration
    # on every boot. Users must be declared with a password or initialPassword.
    users.mutableUsers = false;

    # ── Disable persistent systemd journal ───────────────────────────────
    # Keep journal in RAM only. Logs do not survive reboot.
    services.journald.extraConfig = ''
      Storage=volatile
      RuntimeMaxUse=64M
    '';

    # ── Suppress sudo lecture (resets on each reboot otherwise) ─────────
    security.sudo.extraConfig = ''
      Defaults lecture = never
    '';

    # ── Impermanence: declare what must persist across reboots ───────────
    # MINIMAL set — only what is strictly required for a functional
    # NixOS privacy system. Everything else is ephemeral.
    environment.persistence."${cfg.persistentPath}" = {
      hideMounts = true;  # Hide bind mounts from GNOME Files / file managers

      directories = [
        # NixOS user/group database — required when users.mutableUsers = false
        # is NOT used, but safe to keep here; NixOS needs it on first activation.
        "/var/lib/nixos"

        # NetworkManager: omitted intentionally for privacy.
        # WiFi passwords are NOT persisted — must be re-entered each session.
        # To persist connections, uncomment:
        # "/etc/NetworkManager/system-connections"

        # Bluetooth device pairings: omitted for privacy.
        # Devices must be re-paired each session.
        # "/var/lib/bluetooth"
      ];

      files = [
        # machine-id: used by systemd for boot-scoped log correlation.
        # PRIVACY NOTE: persisting machine-id allows correlation of boots.
        # Uncomment only if persistent journald boot tracking is needed.
        # "/etc/machine-id"

        # SSH host keys: omitted for privacy — regenerated each boot.
        # Clients will see key-changed warnings. Uncomment if SSH must be stable:
        # "/etc/ssh/ssh_host_ed25519_key"
        # "/etc/ssh/ssh_host_ed25519_key.pub"
        # "/etc/ssh/ssh_host_rsa_key"
        # "/etc/ssh/ssh_host_rsa_key.pub"
      ];

      # ── Optional user-level persistence (nimda) ─────────────────────────
      # Disabled by default. The nimda user's home is completely ephemeral.
      # Uncomment specific entries to selectively persist user data.
      users.nimda = {
        directories = [
          # { directory = ".gnupg";                    mode = "0700"; }
          # { directory = ".ssh";                      mode = "0700"; }
          # { directory = ".local/share/keyrings";     mode = "0700"; }
          # ".config/vpn"
        ];
        files = [
          # ".config/monitors.xml"  # Persist monitor layout across sessions
        ];
      };
    };
  };
}
```

---

## 6. Complete Persistence Decision Table

### 6.1 System-level paths

| Path | Decision | Rationale |
|---|---|---|
| `/nix` | **PERSIST** (via disk mount) | Nix store — required for system to function |
| `/boot` | **PERSIST** (via disk mount) | Bootloader — required |
| `/persistent` | **PERSIST** (via disk mount) | Persistent storage volume itself |
| `/var/lib/nixos` | **PERSIST** (via impermanence) | NixOS user/group UID tracking database |
| `/etc/machine-id` | **EPHEMERAL** (privacy default) | Regenerated each boot; persisting enables boot correlation |
| `/var/log` | **EPHEMERAL** | Logs do not survive reboot (privacy) |
| `/var/lib/bluetooth` | **EPHEMERAL** | Devices re-paired each session |
| `/etc/NetworkManager/system-connections` | **EPHEMERAL** | VPN/WiFi credentials not saved (privacy) |
| `/var/lib/systemd/coredump` | **EPHEMERAL** | Crash dumps cleared on reboot |
| `/var/lib/systemd/timers` | **EPHEMERAL** | Timer state regenerated |
| `/tmp` | **EPHEMERAL** | Lives in tmpfs `/` |
| `/var/tmp` | **EPHEMERAL** | Lives in tmpfs `/` |
| `/var/lib/gdm` | **EPHEMERAL** | GDM session data cleared |
| `/var/lib/nixos-hardware` | **EPHEMERAL** | Hardware scan cache regenerated |
| `/etc/ssh/ssh_host_*` | **EPHEMERAL** (privacy default) | Host keys regenerated; clients see key-changed warning |

### 6.2 User-level paths (`/home/nimda/`)

| Path | Decision | Rationale |
|---|---|---|
| `~/.config/` | **EPHEMERAL** | GNOME settings, app configs reset per session |
| `~/.local/share/` | **EPHEMERAL** | App data (recent files, etc.) reset per session |
| `~/.cache/` | **EPHEMERAL** | Cache cleared per session |
| `~/Downloads/` | **EPHEMERAL** | Downloaded files cleared per session |
| `~/.bash_history` | **EPHEMERAL** | Shell history not retained |
| `~/.gnupg/` | **EPHEMERAL** (privacy default) | GPG keys not retained; import each session |
| `~/.ssh/` | **EPHEMERAL** (privacy default) | SSH identity not retained; import each session |

---

## 7. GPU Driver Compatibility

### 7.1 AMD (`modules/gpu/amd.nix`)

AMD drivers (`amdgpu`) are kernel modules distributed as part of the Linux kernel package which resides entirely in `/nix/store`. Firmware blobs (`linux-firmware`) are also in `/nix/store` and loaded via `/run/current-system/firmware` (symlink into `/nix/store`). No GPU state is written outside `/nix` or `/run`.

**Verdict: Fully compatible with tmpfs root. No changes required.**

### 7.2 NVIDIA (`modules/gpu/nvidia.nix`)

NVIDIA closed-source drivers are packaged as a kernel module and userspace libraries in `/nix/store`. The NVIDIA persistence daemon (`nvidia-persistenced`) writes state to `/var/lib/nvidia-persistenced/`, which lives on tmpfs `/` — this is ephemeral and acceptable (the daemon reinitializes on each boot).

**Verdict: Fully compatible with tmpfs root. No changes required.**

### 7.3 VM guests (`modules/gpu/vm.nix`)

VirtIO / QXL / SPICE drivers are kernel modules in `/nix/store`. No persistent state required.

**Verdict: Fully compatible.**

---

## 8. Hardware Requirements and Constraints

| Requirement | Minimum | Recommended |
|---|---|---|
| RAM | 8 GB | 16 GB |
| tmpfs `/` size | 25% of RAM (default) | 25% (configurable in hardware-configuration.nix) |
| Nix partition | 40 GB | 80–120 GB |
| Persistent partition | 0 (optional) | 10–20 GB if used |
| CPU | Any x86_64 with AES-NI | AES-NI recommended for LUKS performance |
| Boot mode | UEFI or BIOS | UEFI recommended |

**ZRAM:** Already configured in `modules/system.nix` (`zramSwap.enable = true`, `algorithm = "lz4"`, `memoryPercent = 50`). On a 16 GB RAM system this provides up to 8 GB of compressed swap in RAM, eliminating the need for disk swap.

---

## 9. LUKS Encryption Setup Guidance

LUKS2 is recommended (default in modern `cryptsetup`). Encrypt the data partition before the Btrfs filesystem is created:

```bash
# Format with LUKS2, Argon2id KDF (more memory-hard than PBKDF2)
cryptsetup luksFormat --type luks2 --pbkdf argon2id /dev/sdX2

# Open the LUKS container
cryptsetup open /dev/sdX2 cryptroot

# Create and structure Btrfs inside LUKS
mkfs.btrfs /dev/mapper/cryptroot
mount /dev/mapper/cryptroot /mnt
btrfs subvolume create /mnt/@nix
btrfs subvolume create /mnt/@persist
umount /mnt
```

In `hardware-configuration.nix`, declare the LUKS device:

```nix
boot.initrd.luks.devices."cryptroot" = {
  device = "/dev/disk/by-uuid/<LUKS_PARTITION_UUID>";
  allowDiscards = true;    # TRIM pass-through for SSD health
  bypassWorkqueues = true; # Lower latency on NVMe (kernel 5.9+)
};
```

Retrieve the LUKS partition UUID with:
```bash
blkid /dev/sdX2
```

The opened `/dev/mapper/cryptroot` device UUID (used for Btrfs subvolume mounts) is retrieved with:
```bash
blkid /dev/mapper/cryptroot
```

---

## 10. `configuration-privacy.nix` Changes

Add `./modules/impermanence.nix` to `imports` and enable the feature:

```nix
# In the imports list:
./modules/impermanence.nix

# New settings:
vexos.impermanence.enable = true;

# Declarative user password (required when users.mutableUsers = false)
# This is a session-only default password — it does not persist if changed.
users.users.nimda.initialPassword = "vexos";
```

No other changes to `configuration-privacy.nix` are required. The impermanence module forces `vexos.swap.enable = false` internally.

---

## 11. `flake.nix` Changes

### 11.1 Add input

In the `inputs` block:

```nix
impermanence = {
  url = "github:nix-community/impermanence";
  inputs.nixpkgs.follows = "nixpkgs";
  inputs.home-manager.follows = "home-manager";
};
```

### 11.2 Update outputs destructuring

```nix
outputs = { self, nixpkgs, nixpkgs-unstable, nix-gaming, home-manager, impermanence, ... }@inputs:
```

`impermanence` is automatically available in all modules via `inputs.impermanence` because `specialArgs = { inherit inputs; }` is set on every `nixosSystem` call. No per-host changes needed.

---

## 12. Summary of Files to Create/Modify

| File | Action | Description |
|---|---|---|
| `modules/impermanence.nix` | **CREATE** | New module: options, impermanence config, swap disable, journal config |
| `configuration-privacy.nix` | **MODIFY** | Add impermanence module import, set `enable = true`, set `initialPassword` |
| `flake.nix` | **MODIFY** | Add `impermanence` input; update outputs destructuring |
| `hosts/privacy-*.nix` | **NO CHANGE** | All changes cascade from configuration-privacy.nix |

---

## 13. Boot Flow After Implementation

```
Power on
  │
  ▼
initrd: unlock LUKS (cryptroot), mount /nix (neededForBoot), /persistent (neededForBoot)
  │
  ▼
mount / as tmpfs (empty, RAM-backed)
  │
  ▼
NixOS activation: recreate /etc, /var, /run from /nix/store
  │
  ▼
impermanence module: bind mount /persistent/var/lib/nixos → /var/lib/nixos
  │
  ▼
systemd starts userspace services (all state in RAM except bind-mounted paths)
  │
  ▼
GDM → GNOME session (all user config in tmpfs)
  │
  ▼
User session (all writes to / go to RAM only, /nix/store read-only)
  │
  ▼
Power off / reboot
  │
  ▼
tmpfs contents discarded — system returns to clean state
```

---

## 14. Risks and Mitigations

| Risk | Severity | Mitigation |
|---|---|---|
| User forgets to set `neededForBoot = true` on `/persistent` | HIGH | `assertions` block in the module will fail `nixos-rebuild` with a clear error message |
| User forgets to set `/` to tmpfs | HIGH | `assertions` block validates `fileSystems."/".fsType == "tmpfs"` |
| OOM if user writes large files to tmpfs `/`  | MEDIUM | tmpfs size cap (25% of RAM). ZRAM provides additional overflow. Document warning clearly. |
| NVIDIA persistence daemon fails without `/var/lib/nvidia-persistenced` | LOW | On tmpfs, the directory is created by systemd-tmpfiles on each boot; no persistent data needed |
| Nix GC removes live packages on small `/nix` partition | LOW | GC runs weekly (inherited from `configuration-privacy.nix`); `/nix` is on persistent disk |
| SSH clients see host key changed warning on each boot | LOW | Expected Tails-like behavior; documented as intentional. Users can persist host keys if needed. |
| LUKS decrypt on each boot adds latency | LOW | Acceptable for a privacy system; Argon2id tuning can be adjusted |
| `users.mutableUsers = false` locks out user if `initialPassword` not set | HIGH | `configuration-privacy.nix` explicitly sets `initialPassword = "vexos"` |
| Btrfs auto-scrub enabled by `vexos.btrfs.enable` on /nix partition | LOW | Scrub is beneficial for `/nix`; no conflict with tmpfs root |

---

## 15. NixOS 25.11 Compatibility Notes

- `boot.initrd.luks.devices` is stable API in NixOS 25.x
- `environment.persistence` (impermanence module) is not in nixpkgs core; it is provided by the flake input and is compatible with all NixOS releases
- `services.journald.extraConfig` with `Storage=volatile` is supported on all systemd versions included in NixOS 25.x
- `users.mutableUsers = false` requires that ALL users with login capabilities have a `password`, `hashedPassword`, `initialPassword`, or `passwordFile` set — enforced by NixOS module system
- `impermanence.inputs.nixpkgs.follows = "nixpkgs"` and `impermanence.inputs.home-manager.follows = "home-manager"` are valid flake follows semantics; they reuse the already-pinned nixpkgs and home-manager from the flake lock
- The `neededForBoot` assertion added to the impermanence module was introduced upstream in the impermanence project approximately 3 months before this spec (per the commit log) and is active in the current `master` branch

---

## 16. Research Sources

1. `nix-community/impermanence` GitHub repository — README.org, module options documentation (Context7: `/nix-community/impermanence`)
2. Graham Christensen, "Erase your darlings" — https://grahamc.com/blog/erase-your-darlings (ZFS rollback strategy, concept of ephemeral roots)
3. mt-caret blog, "Encrypted Btrfs Root with Opt-in State on NixOS" — https://mt-caret.github.io/blog/posts/2020-06-29-optin-state.html (Btrfs subvolume rollback with LUKS)
4. NixOS Wiki, "Impermanence" — https://nixos.wiki/wiki/Impermanence (tmpfs root configuration, module usage examples)
5. Impermanence module README — https://github.com/nix-community/impermanence (flake integration, `environment.persistence` options)
6. elis.nu, "NixOS tmpfs as root" — https://elis.nu/blog/2020/05/nixos-tmpfs-as-root/ (tmpfs root installation walkthrough)
7. willbush.dev, "Impermanent NixOS" — https://willbush.dev/blog/impermanent-nixos/ (LUKS + tmpfs + flakes integration)
8. NixOS source: `modules/system.nix` vexos options, `configuration-privacy.nix` current state, `flake.nix` input and output structure (read directly from workspace)
