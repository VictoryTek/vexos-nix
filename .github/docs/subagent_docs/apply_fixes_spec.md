# apply_fixes_spec.md
# Research & Specification — Batch Fix Audit

**Date:** 2026-05-22  
**Researcher:** Phase 1 Research Subagent  
**Project:** vexos-nix (NixOS 25.11 Flake)

---

## Executive Summary

19 proposed fixes were audited against the current codebase.  
**1 fix is CONFIRMED** (assertion missing from zfs-server.nix).  
**9 fixes are ALREADY FIXED** (previously applied to the codebase).  
**9 fixes are N/A** (described problems do not exist in current code).

**Implementer action required: only Fix 1 (add assertion).**

---

## Fix Status Table

| # | Title | File | Status |
|---|-------|------|--------|
| 1 | zfs-server.nix — hostId assertion | modules/zfs-server.nix | CONFIRMED (assertion missing) |
| 2 | flake.nix — GPU wrapper double-declare virtualbox | flake.nix | N/A |
| 3 | server/proxmox.nix — bridge gets no IP | modules/server/proxmox.nix | N/A |
| 4 | gnome.nix — mkDefault for xserver.enable | modules/gnome.nix | ALREADY FIXED |
| 5 | system-gaming.nix — add systemd-oomd | modules/system-gaming.nix | ALREADY FIXED |
| 6 | zfs-server.nix — disable swap on ZFS hosts | modules/zfs-server.nix | ALREADY FIXED |
| 7 | gnome-htpc.nix — duplicate dconf power keys | modules/gnome-htpc.nix | N/A |
| 8 | home-htpc.nix — missing Wayland session variables | home-htpc.nix | ALREADY FIXED |
| 9 | home-htpc.nix — missing terminal utilities | home-htpc.nix | ALREADY FIXED |
| 10 | gnome-htpc.nix — stale system-update.desktop favourite | modules/gnome-htpc.nix | N/A |
| 11 | gnome-desktop.nix — dead virtualbox.desktop favourite | modules/gnome-desktop.nix | N/A |
| 12 | asus-opt.nix — option wrapper | modules/asus-opt.nix | ALREADY FIXED |
| 13 | gnome-{htpc,server,stateless}.nix — dead Flatpak cleanup loops | modules/gnome-*.nix | N/A |
| 14 | configuration-stateless.nix — dead gimp-hidden writeText | configuration-stateless.nix | N/A |
| 15 | gpu/nvidia.nix — unreachable abort branch | modules/gpu/nvidia.nix | N/A |
| 16 | branding.nix — nullglob guard on boot entries | modules/branding.nix | ALREADY FIXED |
| 17 | server/adguard.nix — open recursive DNS | modules/server/adguard.nix | ALREADY FIXED |
| 18 | server/syncthing.nix — GUI bound to 0.0.0.0 | modules/server/syncthing.nix | ALREADY FIXED |
| 19 | server/vaultwarden.nix — missing DOMAIN + ADMIN_TOKEN | modules/server/vaultwarden.nix | ALREADY FIXED |

---

## Detailed Findings

---

### FIX 1 — modules/zfs-server.nix (hostId assertion)

**Status:** CONFIRMED — assertion is MISSING; `lib.mkDefault "00000000"` is already in place

**Background:**  
The proposed fix description states "the current file reads hostId from /etc/machine-id at eval time." That problem does **not exist** in the current code — the module already uses `lib.mkDefault "00000000"` (a safe, always-evaluable placeholder). However, there is **no assertion** to catch a host deployment that forgets to set a real hostId.

**File:** `modules/zfs-server.nix`  
**Approximate line range:** Lines 57–67

**Current code (exact):**
```nix
  # ── networking.hostId ────────────────────────────────────────────────────
  # ZFS REQUIRES a stable, unique 8-hex-digit hostId per machine.
  # Do NOT read /etc/machine-id at eval time — that file belongs to the machine
  # running `nixos-rebuild`, not the target host.  When building a server
  # closure on a workstation every server would inherit the workstation's
  # hostId, causing ZFS to refuse pool import on next boot.
  #
  # Set networking.hostId explicitly in hosts/<role>-<gpu>.nix, e.g.:
  #   networking.hostId = "deadbeef";
  # Generate a value with:  head -c 8 /etc/machine-id
  networking.hostId = lib.mkDefault "00000000";
```

**What is missing:**  
A NixOS assertion that fires at evaluation time when `networking.hostId` is still the default placeholder `"00000000"`. This would catch a future operator who deploys a new server host file but forgets to set a real hostId.

**Proposed replacement (add assertion block immediately before or after the hostId line):**
```nix
  # ── networking.hostId ────────────────────────────────────────────────────
  # ZFS REQUIRES a stable, unique 8-hex-digit hostId per machine.
  # Do NOT read /etc/machine-id at eval time — that file belongs to the machine
  # running `nixos-rebuild`, not the target host.  When building a server
  # closure on a workstation every server would inherit the workstation's
  # hostId, causing ZFS to refuse pool import on next boot.
  #
  # Set networking.hostId explicitly in hosts/<role>-<gpu>.nix, e.g.:
  #   networking.hostId = "deadbeef";
  # Generate a value with:  head -c 8 /etc/machine-id
  networking.hostId = lib.mkDefault "00000000";

  assertions = [
    {
      assertion = config.networking.hostId != "00000000";
      message   = ''
        networking.hostId must be set to a unique 8-hex-digit value in
        hosts/<role>-<gpu>.nix for this ZFS host.
        Generate a value with:  head -c 8 /etc/machine-id
      '';
    }
  ];
```

**Hosts that import zfs-server.nix (via configuration-server.nix or configuration-headless-server.nix):**

`configuration-server.nix` imports `./modules/zfs-server.nix`  
`configuration-headless-server.nix` imports `./modules/zfs-server.nix`

**All current server/headless-server host files — hostId status:**

| Host file | networking.hostId value | Status |
|-----------|------------------------|--------|
| hosts/server-amd.nix | `"a0000001"` | Real value — assertion PASSES |
| hosts/server-nvidia.nix | `"a0000002"` | Real value — assertion PASSES |
| hosts/server-intel.nix | `"a0000003"` | Real value — assertion PASSES |
| hosts/server-vm.nix | `"a0000004"` | Real value — assertion PASSES |
| hosts/headless-server-amd.nix | `"b0000001"` | Real value — assertion PASSES |
| hosts/headless-server-nvidia.nix | `"b0000002"` | Real value — assertion PASSES |
| hosts/headless-server-intel.nix | `"b0000003"` | Real value — assertion PASSES |
| hosts/headless-server-vm.nix | `"b0000004"` | Real value — assertion PASSES |

Note: The legacy535/legacy470 nvidia variants in the flake (`vexos-server-nvidia-legacy535` etc.) reuse `hosts/server-nvidia.nix` (host file is keyed on role+gpu, not nvidiaVariant), so they also pass with `"a0000002"`.

**No TODO placeholders are needed.** All existing hosts already have real values. The assertion is a safety net for *future* host additions.

**Risk:** None. The assertion is non-destructive. All current builds pass with their existing real hostId values.

---

### FIX 2 — flake.nix (GPU wrapper double-declare virtualbox) — N/A

**Status:** N/A — the described double-declaration does not exist

The `nixosModules.gpuAmd`, `gpuNvidia`, `gpuIntel`, `gpuAmdHeadless`, `gpuNvidiaHeadless`, `gpuIntelHeadless`, and `gpuVm` wrappers in `flake.nix` are pure import delegates:

```nix
# In flake.nix nixosModules section:
gpuAmd = { ... }: {
  imports = [ ./modules/gpu/amd.nix ];
};
gpuNvidia = { ... }: {
  imports = [ ./modules/gpu/nvidia.nix ];
};
gpuIntel = { ... }: {
  imports = [ ./modules/gpu/intel.nix ];
};
```

`virtualisation.virtualbox.guest.enable = lib.mkForce false` is set **only** inside each underlying `modules/gpu/*.nix` file:
- `modules/gpu/amd.nix` — line 35
- `modules/gpu/nvidia.nix` — line 79
- `modules/gpu/intel.nix` — line 51
- `modules/gpu/amd-headless.nix` — line 38
- `modules/gpu/intel-headless.nix` — line 37

The flake.nix wrappers do NOT independently set this option. No double-declare. No action required.

---

### FIX 3 — modules/server/proxmox.nix (bridge gets no IP) — N/A

**Status:** N/A — the bridge already uses NetworkManager DHCP; dhcpcd is already disabled globally

`modules/server/proxmox.nix` creates `vmbr0` via `networking.networkmanager.ensureProfiles.profiles`:

```nix
networking.networkmanager.ensureProfiles.profiles = {
  "vmbr0-bridge" = {
    connection = {
      id             = "vmbr0 Bridge";
      type           = "bridge";
      interface-name = "vmbr0";
      autoconnect    = "true";
    };
    ipv4 = {
      method = "auto";   # NM obtains DHCP lease on vmbr0 directly
    };
    ...
  };
  ...
};
```

`modules/network.nix` globally disables dhcpcd:
```nix
networking.useDHCP = lib.mkForce false;
networking.dhcpcd.enable = lib.mkForce false;
```

NetworkManager is the sole DHCP client. `vmbr0` gets its IP via NM's internal DHCP client, not dhcpcd. There is no "bridge gets no IP" problem and no dhcpcd re-enable block is needed.

---

### FIX 4 — modules/gnome.nix (mkDefault for xserver.enable) — ALREADY FIXED

**Status:** ALREADY FIXED

**Current code (exact) in `modules/gnome.nix` approximately line 100:**
```nix
  services.xserver.enable = lib.mkDefault true;
```

The `lib.mkDefault` wrapper is already present. No action required.

---

### FIX 5 — modules/system-gaming.nix (add systemd-oomd) — ALREADY FIXED

**Status:** ALREADY FIXED

**Current code (exact) in `modules/system-gaming.nix` approximately lines 50–54:**
```nix
  # Enable oomd monitoring on user and root slices
  systemd.oomd = {
    enableRootSlice  = true;
    enableUserSlices = true;
  };
```

The `systemd.oomd` block is already present. No action required.

---

### FIX 6 — modules/zfs-server.nix (disable swap on ZFS hosts) — ALREADY FIXED

**Status:** ALREADY FIXED

**Current code (exact) in `modules/zfs-server.nix` approximately lines 69–82:**
```nix
  # ── Swap policy: disable disk-backed swap on ZFS hosts ───────────────────
  # Writing a swapfile to a ZFS dataset risks a kernel deadlock: ...
  #
  # lib.mkDefault (priority 1000) is weaker than a plain assignment (priority 100),
  # so a host operator can override this by setting:
  #   vexos.swap.enable = true;   # in hosts/<role>-<gpu>.nix
  # only if they have a confirmed non-ZFS swap partition or file.
  #
  # ZRAM swap (configured unconditionally in modules/system.nix) is unaffected
  # and continues to provide fast in-RAM compressed swap on all server roles.
  vexos.swap.enable = lib.mkDefault false;
```

`vexos.swap.enable` is declared in `modules/system.nix` (option type `bool`, default `true`). The `lib.mkDefault false` override is already in place. No action required.

---

### FIX 7 — modules/gnome-htpc.nix (duplicate dconf power keys) — N/A

**Status:** N/A — no power management dconf keys exist in gnome-htpc.nix

`modules/gnome-htpc.nix` sets only:
- `accent-color = "orange"`
- `enabled-extensions`
- `favorite-apps`
- `dash-to-dock` dock position/autohide/intellihide
- `app-folders` folder layout

There are no `org/gnome/settings-daemon/plugins/power` or similar power-management dconf keys in this file. Power settings live exclusively in `modules/system-nosleep.nix`. No duplicate. No action required.

---

### FIX 8 — home-htpc.nix (missing Wayland session variables) — ALREADY FIXED

**Status:** ALREADY FIXED

**Current code (exact) in `home-htpc.nix` (approx lines 136–142):**
```nix
  # ── Wayland session variables ─────────────────────────────────────────────
  # NIXOS_OZONE_WL: enables Wayland for Electron-based apps (ghostty, Brave).
  # MOZ_ENABLE_WAYLAND: forces Firefox/Zen to use the Wayland backend.
  # QT_QPA_PLATFORM: ensures Qt apps prefer Wayland with XCB as fallback.
  home.sessionVariables = {
    NIXOS_OZONE_WL     = "1";
    MOZ_ENABLE_WAYLAND = "1";
    QT_QPA_PLATFORM    = "wayland;xcb";
  };
```

Already present. No action required.

---

### FIX 9 — home-htpc.nix (missing terminal utilities) — ALREADY FIXED

**Status:** ALREADY FIXED

**Current code (exact) in `home-htpc.nix` (approx lines 144–158):**
```nix
  # ── User packages ──────────────────────────────────────────────────────────
  home.packages = with pkgs; [
    ghostty

    # Terminal utilities
    tree
    ripgrep
    fd
    bat
    eza
    fzf
    wl-clipboard  # Wayland clipboard CLI (wl-copy / wl-paste)

    # System utilities
    fastfetch
  ];
```

`ghostty`, `tree`, `ripgrep`, `fd`, `bat`, `eza`, `fzf`, `wl-clipboard`, and `fastfetch` are all present. No action required.

---

### FIX 10 — modules/gnome-htpc.nix (stale system-update.desktop favourite) — N/A

**Status:** N/A — "system-update.desktop" is not in the favourite-apps list

**Current favourite-apps in `modules/gnome-htpc.nix` (exact):**
```nix
favorite-apps = [
  "brave-browser.desktop"
  "app.zen_browser.zen.desktop"
  "plex-desktop.desktop"
  "io.freetubeapp.FreeTube.desktop"
  "org.gnome.Nautilus.desktop"
  "io.github.up.desktop"
  "com.mitchellh.ghostty.desktop"
];
```

No `system-update.desktop` entry. No action required.

---

### FIX 11 — modules/gnome-desktop.nix (dead virtualbox.desktop favourite) — N/A

**Status:** N/A — "virtualbox.desktop" is not in the favourite-apps list

**Current favourite-apps in `modules/gnome-desktop.nix` (exact):**
```nix
favorite-apps = [
  "brave-browser.desktop"
  "app.zen_browser.zen.desktop"
  "org.gnome.Nautilus.desktop"
  "com.mitchellh.ghostty.desktop"
  "io.github.up.desktop"
  "org.gnome.Boxes.desktop"
  "code.desktop"
];
```

No `virtualbox.desktop` entry. No action required.

---

### FIX 12 — modules/asus-opt.nix option wrapper — ALREADY FIXED / N/A

**Status:** ALREADY FIXED

- Exact filename: **`modules/asus-opt.nix`** (not `asus.nix`)
- `options.vexos.hardware.asus.enable` is already declared in this file:

```nix
options.vexos.hardware.asus = {
  enable = lib.mkEnableOption "ASUS ROG/TUF hardware support (asusd, supergfxctl, fan curves)";
  batteryChargeLimit = lib.mkOption { ... };
};
```

No action required.

---

### FIX 13 — gnome-{htpc,server,stateless}.nix (dead Flatpak cleanup loops) — N/A

**Status:** N/A — no Flatpak cleanup loops exist in any of these three files

All three files (`modules/gnome-htpc.nix`, `modules/gnome-server.nix`, `modules/gnome-stateless.nix`) end with:
```nix
  # ── GNOME default app Flatpaks (<role>) ─────────────────────────────────
  vexos.gnome.flatpakInstall.apps = [
    "org.gnome.TextEditor"
    "org.gnome.Loupe"
  ];
}
```

No `activation`, `postActivation`, shell loop, or `flatpak remove` commands are present in any of these files. No action required.

---

### FIX 14 — configuration-stateless.nix (dead gimp-hidden writeText derivation) — N/A

**Status:** N/A — no gimp-related writeText derivation exists in this file

`configuration-stateless.nix` system packages block (exact):
```nix
  environment.systemPackages = [
    pkgs.tor-browser
  ];
```

No `writeText`, no GIMP hiding derivation. The GIMP exclusion is handled by:
```nix
  vexos.flatpak.excludeApps = [
    "org.gimp.GIMP"
    ...
  ];
```

No action required.

---

### FIX 15 — modules/gpu/nvidia.nix (unreachable abort branch) — N/A

**Status:** N/A — no abort exists; all enum branches are reachable and correct

**Current driverPackage expression in `modules/gpu/nvidia.nix` (exact, lines 17–21):**
```nix
  driverPackage =
    if      variant == "latest"     then config.boot.kernelPackages.nvidiaPackages.stable
    else if variant == "legacy_535" then config.boot.kernelPackages.nvidiaPackages.legacy_535
    else                                 config.boot.kernelPackages.nvidiaPackages.legacy_470;
```

The option type is `lib.types.enum [ "latest" "legacy_535" "legacy_470" ]`. All three values are handled. The `else` branch maps the third valid value (`"legacy_470"`) to `nvidiaPackages.legacy_470` — this is **reachable**, not dead code, and there is no `abort`. No action required.

---

### FIX 16 — modules/branding.nix (nullglob guard on boot entries) — ALREADY FIXED

**Status:** ALREADY FIXED

**Current `extraInstallCommands` block in `modules/branding.nix` (exact):**
```nix
  boot.loader.systemd-boot.extraInstallCommands = lib.mkIf config.boot.loader.systemd-boot.enable ''
    set -eu
    shopt -s nullglob
    entries=(/boot/loader/entries/*.conf)
    [[ ''${#entries[@]} -gt 0 ]] || exit 0
    for f in "''${entries[@]}"; do
      ...
    done
  '';
```

Both guards are present:
1. `shopt -s nullglob` — prevents glob expansion to literal `*.conf` string when no files match
2. `[[ ${#entries[@]} -gt 0 ]] || exit 0` — exits cleanly when the array is empty

No action required.

---

### FIX 17 — modules/server/adguard.nix (open recursive DNS) — ALREADY FIXED

**Status:** ALREADY FIXED — DNS is loopback-only by default; explicit opt-in required

**Current default values in `modules/server/adguard.nix` (exact):**
```nix
dnsBindHosts = lib.mkOption {
  type = lib.types.listOf lib.types.str;
  default = [ "127.0.0.1" "::1" ];
  description = ''
    Addresses AdGuard Home will bind its DNS listener to.
    Default is loopback only. Set to [ "0.0.0.0" ] (and enable
    openDnsFirewall) to serve DNS on the LAN.
  '';
};

openDnsFirewall = lib.mkOption {
  type = lib.types.bool;
  default = false;
  ...
};
```

DNS is bound to loopback only. `openDnsFirewall = false` by default. The web UI (`http.address = "0.0.0.0:${toString cfg.port}"`) is open on all interfaces but does not expose DNS recursion. The combination is acceptable for a module where the firewall port for the web UI is still managed separately. No action required.

---

### FIX 18 — modules/server/syncthing.nix (GUI bound to 0.0.0.0) — ALREADY FIXED

**Status:** ALREADY FIXED — GUI binds to 127.0.0.1:8384 by default

**Current default in `modules/server/syncthing.nix` (exact):**
```nix
guiAddress = lib.mkOption {
  type = lib.types.str;
  default = "127.0.0.1:8384";
  description = ''
    Address the Syncthing GUI listens on. Default is loopback-only;
    access via SSH tunnel or a reverse proxy with auth. Set to
    "0.0.0.0:8384" (with openGuiFirewall = true) for direct LAN access —
    ensure a GUI password is configured first.
  '';
};
```

GUI defaults to loopback. `openGuiFirewall = false` by default. No action required.

---

### FIX 19 — modules/server/vaultwarden.nix (missing DOMAIN + ADMIN_TOKEN) — ALREADY FIXED

**Status:** ALREADY FIXED

**Current `services.vaultwarden` config block (exact):**
```nix
services.vaultwarden = {
  enable = true;
  config = {
    ROCKET_PORT    = cfg.port;
    ROCKET_ADDRESS = "127.0.0.1";
    SIGNUPS_ALLOWED = false;
    DOMAIN         = cfg.domain;
    # To enable the admin panel, set ADMIN_TOKEN via environmentFile:
    #   services.vaultwarden.environmentFile = "/run/secrets/vaultwarden-env";
    # where the file contains: ADMIN_TOKEN=<argon2id-hash>
  };
};
```

`DOMAIN` is set from `cfg.domain`. An assertion prevents deployment with the placeholder:
```nix
assertions = [
  {
    assertion = cfg.domain != "https://vault.example.com";
    message = ''
      vexos.server.vaultwarden.domain must be set to the actual public URL ...
    '';
  }
];
```

`ADMIN_TOKEN` is documented as an opt-in via `environmentFile` — the secure pattern for NixOS secrets. No action required.

---

## Implementation Instructions

### Only Fix 1 requires code changes.

**File:** `modules/zfs-server.nix`  
**Action:** Add an `assertions` block immediately after the `networking.hostId` line.

**Exact edit — replace this block:**
```nix
  networking.hostId = lib.mkDefault "00000000";
```

**With this block:**
```nix
  networking.hostId = lib.mkDefault "00000000";

  assertions = [
    {
      assertion = config.networking.hostId != "00000000";
      message   = ''
        networking.hostId must be set to a unique 8-hex-digit value in
        hosts/<role>-<gpu>.nix for this ZFS host.
        Generate a value with:  head -c 8 /etc/machine-id
      '';
    }
  ];
```

The module requires `config` in its argument list, which it already has (`{ config, lib, pkgs, ... }:`).

### No other files need to be modified.

---

## Validation Requirements

After applying Fix 1:

1. `nix flake show` — must list all 34 outputs without errors
2. `sudo nixos-rebuild dry-build --flake .#vexos-server-amd` — must succeed (hostId = "a0000001" passes assertion)
3. `sudo nixos-rebuild dry-build --flake .#vexos-headless-server-amd` — must succeed (hostId = "b0000001" passes assertion)
4. `sudo nixos-rebuild dry-build --flake .#vexos-server-vm` — must succeed (hostId = "a0000004" passes assertion)

---

## Files Read During Research

- `/home/nimda/Projects/vexos-nix/flake.nix`
- `/home/nimda/Projects/vexos-nix/modules/zfs-server.nix`
- `/home/nimda/Projects/vexos-nix/modules/server/proxmox.nix` — EXISTS
- `/home/nimda/Projects/vexos-nix/modules/gnome.nix`
- `/home/nimda/Projects/vexos-nix/modules/system-gaming.nix`
- `/home/nimda/Projects/vexos-nix/modules/gnome-htpc.nix`
- `/home/nimda/Projects/vexos-nix/modules/gnome-server.nix`
- `/home/nimda/Projects/vexos-nix/modules/gnome-stateless.nix`
- `/home/nimda/Projects/vexos-nix/modules/gnome-desktop.nix`
- `/home/nimda/Projects/vexos-nix/home-htpc.nix`
- `/home/nimda/Projects/vexos-nix/modules/asus-opt.nix` — EXISTS (not asus.nix)
- `/home/nimda/Projects/vexos-nix/modules/gpu/nvidia.nix`
- `/home/nimda/Projects/vexos-nix/modules/gpu/amd.nix`
- `/home/nimda/Projects/vexos-nix/modules/gpu/intel.nix`
- `/home/nimda/Projects/vexos-nix/modules/gpu/vm.nix`
- `/home/nimda/Projects/vexos-nix/configuration-stateless.nix`
- `/home/nimda/Projects/vexos-nix/modules/branding.nix`
- `/home/nimda/Projects/vexos-nix/modules/server/adguard.nix` — EXISTS
- `/home/nimda/Projects/vexos-nix/modules/server/syncthing.nix` — EXISTS
- `/home/nimda/Projects/vexos-nix/modules/server/vaultwarden.nix` — EXISTS
- `/home/nimda/Projects/vexos-nix/modules/network.nix`
- `/home/nimda/Projects/vexos-nix/modules/system-nosleep.nix`
- `/home/nimda/Projects/vexos-nix/modules/system.nix`
- `/home/nimda/Projects/vexos-nix/hosts/server-amd.nix`
- `/home/nimda/Projects/vexos-nix/hosts/server-nvidia.nix`
- All 8 server/headless-server host files (via grep)

`modules/server/` contents listed — all files present including proxmox.nix, adguard.nix, syncthing.nix, vaultwarden.nix.
