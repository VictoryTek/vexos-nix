# Role-Based Module Split — Specification

**Feature**: `role-split`  
**Date**: 2026-04-22  
**Status**: READY FOR IMPLEMENTATION

---

## 1. Problem Definition

Several shared NixOS modules import desktop-specific packages, kernel tuning
parameters, and GPU settings that have no business on headless-server, server
(GUI), HTPC, or stateless roles. The primary victims are:

| Problem | Affected roles |
|---------|---------------|
| `brave` (GUI browser) lands on headless-server via `packages.nix` | headless-server |
| `boot.plymouth.enable = true` (graphical boot splash) always on | headless-server |
| Gaming kernel params (`preempt=full`, `split_lock_detect=off`, `vm.max_map_count=2147483642`) hit all roles | headless-server, server, htpc, stateless |
| `quiet splash loglevel=3` suppresses boot messages on server | headless-server, server |
| `hardware.graphics.enable32Bit = true` (Steam/Proton 32-bit) hits headless-server — manually force-overridden at the role level | headless-server |
| SCX LAVD gaming scheduler hits headless-server — manually disabled by override | headless-server |
| Wallpapers deployed to headless-server (no GNOME consumer) | headless-server |
| GDM dconf profile declared on headless-server (GDM not installed) | headless-server |
| Gaming/dev Flatpak apps (`Lutris`, `ProtonPlus`, `PrismLauncher`, etc.) in `defaultApps` — excluded by a negative list on non-desktop roles (backwards design) | server, htpc, stateless |
| `samba` (full SMB server+client) installed everywhere via `network.nix` | headless-server |

The headless-server config already manually patches two of these leaks with
`lib.mkForce false` overrides. The goal is to eliminate the leaks at the
source so no force-overrides are needed.

---

## 2. Current State Analysis

### 2.1 Module import matrix (before change)

| Module | desktop | headless-server | server (GUI) | htpc | stateless |
|--------|:-------:|:---------------:|:------------:|:----:|:---------:|
| `gnome.nix` | ✓ | — | ✓ | ✓ | ✓ |
| `gaming.nix` | ✓ | — | — | — | — |
| `audio.nix` | ✓ | — | ✓ | ✓ | ✓ |
| `gpu.nix` | ✓ | ✓ | ✓ | ✓ | ✓ |
| `flatpak.nix` | ✓ | — | ✓ | ✓ | ✓ |
| `network.nix` | ✓ | ✓ | ✓ | ✓ | ✓ |
| `packages.nix` | ✓ | ✓ | ✓ | ✓ | ✓ |
| `development.nix` | ✓ | — | — | — | — |
| `virtualization.nix` | ✓ | — | — | — | — |
| `branding.nix` | ✓ | ✓ | ✓ | ✓ | ✓ |
| `system.nix` | ✓ | ✓ | ✓ | ✓ | ✓ |
| `impermanence.nix` | — | — | — | — | ✓ |
| `modules/server/` | — | ✓ | ✓ | — | — |

### 2.2 Content categorisation per module

#### `modules/packages.nix`

| Package | Classification | Justification |
|---------|---------------|---------------|
| `brave` | **desktop** | GUI browser; requires a display server; useless on headless |
| `just` | **common** | Task runner; useful everywhere |
| `btop` | **common** | Terminal process monitor; useful everywhere |
| `inxi` | **common** | System info; useful everywhere |
| `git` | **common** | VCS; useful everywhere |
| `curl` | **common** | HTTP CLI; useful everywhere |
| `wget` | **common** | File downloader; useful everywhere |

#### `modules/system.nix`

| Setting | Classification | Justification |
|---------|---------------|---------------|
| `boot.kernelPackages = linuxPackages_latest` | **common** | Latest stable kernel for all roles |
| `zramSwap` | **common** | Memory compression; beneficial everywhere |
| `powerManagement.cpuFreqGovernor = "schedutil"` | **common** | Balanced governor; fine everywhere |
| BBR sysctl (`fq`/`bbr`) | **common** | TCP improvements; valuable on servers too |
| `vm.swappiness = 10` | **common** | Reduce swap aggressiveness; fine everywhere |
| `vm.dirty_ratio/background_ratio` | **common** | I/O tuning; fine everywhere |
| `fs.inotify.max_user_watches/instances` | **common** | File watch limits; useful everywhere |
| `net.core.rmem_max/wmem_max = 16777216` | **common** | Socket buffers; fine for server streaming too |
| `kernel.sysrq = 1` | **common** | Emergency recovery; fine everywhere |
| `vexos.btrfs.enable` + scrub | **common** | Auto-detects from `fileSystems`; role-agnostic |
| `vexos.swap.enable` + swap file | **common** | Useful everywhere including servers |
| `boot.plymouth.enable = true` | **desktop** | Graphical boot splash; headless server has no display |
| `preempt=full` kernel param | **desktop** | Gaming latency; wrong for throughput-oriented servers |
| `split_lock_detect=off` kernel param | **desktop** | Wine/Proton compat only |
| `elevator=kyber` kernel param | **common** | Low-latency NVMe I/O; acceptable everywhere |
| `quiet splash loglevel=3` kernel params | **desktop** | Hides boot messages; servers should show them |
| `vm.max_map_count = 2147483642` | **desktop** | Proton/Wine anti-cheat; gaming only |
| THP madvise rules | **desktop** | Gaming memory allocation; no benefit on server |
| `vexos.scx.enable` + SCX LAVD | **desktop** | Gaming CPU scheduler; wrong for server workloads |

#### `modules/gpu.nix`

| Setting | Classification | Justification |
|---------|---------------|---------------|
| `hardware.graphics.enable = true` | **common** | Required for GPU on any role with display |
| `hardware.graphics.enable32Bit = true` | **desktop** | Steam/Proton 32-bit only; headless already force-overrides |
| `libva`, `libva-vdpau-driver`, `libvdpau-va-gl` | **common** | VA-API/VDPAU; useful for server transcoding too |
| `intel-media-driver` | **common** | Harmless on non-Intel; improves compat |
| `mesa` | **common** | Base drivers; required everywhere |
| `libva` / `libva-vdpau-driver` / `mesa` (32-bit) | **desktop** | 32-bit gaming paths only |
| `ffmpeg-full` | **common** | Media transcoding; useful on server/htpc |
| `libva-utils` | **common** | Diagnostic; minor, acceptable everywhere |
| `vulkan-tools` | **desktop** | `vulkaninfo`; desktop debugging tool |
| `vulkan-loader` | **common** | Required by Vulkan apps; fine everywhere |
| `mesa-demos` | **desktop** | `glxinfo`/`glxgears`; display diagnostics only |

#### `modules/branding.nix`

| Setting | Classification | Justification |
|---------|---------------|---------------|
| Plymouth theme + logo | **display** | Requires Plymouth enabled; headless shouldn't use |
| OS identity (`distroName`, `distroId`, etc.) | **common** | OS labelling applies everywhere |
| `vexosLogos` + `vexosIcons` packages | **common** | System identity; useful in all roles (neofetch, etc.) |
| `vexosWallpapers` package | **display** | No GNOME on headless; wasteful deployment |
| `environment.etc."vexos/gdm-logo.png"` | **display** | GDM not installed on headless |
| `programs.dconf.profiles.gdm` | **display** | GDM not installed on headless |

#### `modules/flatpak.nix` — `defaultApps` list

| App | Classification | Justification |
|-----|---------------|---------------|
| `com.bitwarden.desktop` | **common (display)** | Password manager; all display roles |
| `com.github.tchx84.Flatseal` | **common (display)** | Flatpak permissions; all display roles |
| `it.mijorus.gearlever` | **common (display)** | AppImage manager; all display roles |
| `io.missioncenter.MissionCenter` | **common (display)** | System monitor; all display roles |
| `com.simplenote.Simplenote` | **common (display)** | Notes; all display roles |
| `io.github.flattool.Warehouse` | **common (display)** | Flatpak manager; all display roles |
| `app.zen_browser.zen` | **common (display)** | Browser; all display roles |
| `com.mattjakeman.ExtensionManager` | **common (display)** | GNOME extensions; all GNOME roles |
| `com.rustdesk.RustDesk` | **common (display)** | Remote desktop; all display roles |
| `io.github.kolunmi.Bazaar` | **common (display)** | App discovery; all display roles |
| `org.pulseaudio.pavucontrol` | **common (display)** | Audio control; all display roles |
| `org.gnome.World.PikaBackup` | **common (display)** | Backup tool; all display roles |
| `io.github.pol_rivero.github-desktop-plus` | **desktop** | Dev tool; excluded by server/htpc/stateless |
| `org.onlyoffice.desktopeditors` | **desktop** | Office suite; excluded by server/htpc/stateless |
| `org.prismlauncher.PrismLauncher` | **desktop** | Minecraft launcher; excluded by server/htpc/stateless |
| `com.vysp3r.ProtonPlus` | **desktop** | Proton/Wine manager; excluded by server/htpc/stateless |
| `net.lutris.Lutris` | **desktop** | Gaming launcher; excluded by server/htpc/stateless |
| `com.ranfdev.DistroShelf` | **desktop** | Distro container tool; excluded by server/htpc/stateless |

Note: `org.gimp.GIMP` is excluded by all non-desktop roles but is NOT in the default list (GIMP is installed via other means and explicitly banned). The exclusion logic in non-desktop configs handles GIMP correctly.

#### `modules/network.nix`

| Setting | Classification | Justification |
|---------|---------------|---------------|
| `networking.networkmanager.enable` | **common** | All roles need networking |
| `services.avahi` | **common** | mDNS for `.local` resolution; useful everywhere |
| `networking.firewall` | **common** | Security baseline; all roles |
| `services.openssh` | **common** | SSH access; all roles |
| `services.tailscale` | **common** | VPN; all roles |
| `services.resolved` | **common** | DNS; all roles |
| `cifs-utils` | **common** | SMB mount client; useful on all roles |
| `samba` | **desktop/display** | Full SMB stack; mainly needed on desktop/server for `smbclient`; overkill on headless |

---

## 3. Proposed File Structure

### 3.1 New files to create

| File | Purpose |
|------|---------|
| `modules/packages-common.nix` | CLI tools safe for all roles: `just`, `btop`, `inxi`, `git`, `curl`, `wget` |
| `modules/packages-desktop.nix` | GUI packages for display roles: `brave` |

### 3.2 Files to modify

| File | Change summary |
|------|---------------|
| `modules/packages.nix` | **DELETE** — replaced by `packages-common.nix` + `packages-desktop.nix` |
| `modules/system.nix` | Add `vexos.system.gaming` boolean option (default `false`); gate gaming kernel params + SCX behind it; change `boot.plymouth.enable` to `lib.mkDefault false` |
| `modules/gpu.nix` | Change `enable32Bit` from `true` to `lib.mkDefault false`; move `vulkan-tools` and `mesa-demos` behind `lib.mkIf config.vexos.system.gaming`; move `extraPackages32` behind `lib.mkIf config.hardware.graphics.enable32Bit` |
| `modules/branding.nix` | Add `vexos.branding.hasDisplay` boolean option (default `true`); gate `vexosWallpapers`, `environment.etc."vexos/gdm-logo.png"`, and `programs.dconf.profiles.gdm` behind `lib.mkIf config.vexos.branding.hasDisplay` |
| `modules/flatpak.nix` | Extract gaming/dev-only apps from `defaultApps` into a `desktopOnlyApps` list; include them via `lib.optionals (config.vexos.branding.role == "desktop")` |
| `modules/network.nix` | Gate `samba` package behind `lib.mkIf config.vexos.branding.hasDisplay` |
| `configuration-desktop.nix` | Set `vexos.system.gaming = true`; `boot.plymouth.enable = true`; `hardware.graphics.enable32Bit = true`; replace `./modules/packages.nix` → `packages-common.nix` + `packages-desktop.nix` |
| `configuration-headless-server.nix` | Replace `./modules/packages.nix` → `./modules/packages-common.nix`; set `vexos.branding.hasDisplay = false`; remove now-redundant `hardware.graphics.enable32Bit = lib.mkForce false` and `vexos.scx.enable = false` |
| `configuration-server.nix` | Replace `./modules/packages.nix` → `packages-common.nix` + `packages-desktop.nix`; set `boot.plymouth.enable = true` |
| `configuration-htpc.nix` | Same replacements as server |
| `configuration-stateless.nix` | Same replacements; set `boot.plymouth.enable = true` |

### 3.3 Files unchanged

| File | Reason |
|------|--------|
| `modules/gnome.nix` | Already only imported by display roles; already role-conditions gamemode extension |
| `modules/gaming.nix` | Already only imported by desktop |
| `modules/audio.nix` | Already only imported by display roles |
| `modules/development.nix` | Already only imported by desktop |
| `modules/virtualization.nix` | Already only imported by desktop |
| `modules/asus.nix` | Already only imported by desktop-amd host |
| `modules/impermanence.nix` | Already only imported by stateless |
| `modules/stateless-disk.nix` | Stateless-only |
| `modules/gpu/amd.nix` | Brand-specific; no role leak |
| `modules/gpu/nvidia.nix` | Brand-specific; no role leak |
| `modules/gpu/intel.nix` | Brand-specific; no role leak |
| `modules/gpu/vm.nix` | Brand-specific; no role leak |
| `modules/server/` | Server-only |
| `flake.nix` | No changes required |
| `hosts/*.nix` | No changes required (host files don't set the affected options) |

---

## 4. Detailed Content Mapping

### 4.1 `modules/packages-common.nix` (NEW)

```nix
# modules/packages-common.nix
# CLI tools safe for all roles (desktop, server, htpc, headless-server, stateless).
{ pkgs, ... }:
{
  environment.systemPackages = with pkgs; [
    just    # Command runner (justfile)
    btop    # Terminal process viewer
    inxi    # System information tool
    git     # Version control
    curl    # HTTP / transfer CLI
    wget    # File downloader
  ];
}
```

### 4.2 `modules/packages-desktop.nix` (NEW)

```nix
# modules/packages-desktop.nix
# GUI packages for roles with a display server (desktop, server, htpc, stateless).
# Do NOT import on headless-server.
{ pkgs, ... }:
{
  environment.systemPackages = with pkgs; [
    brave  # Chromium-based browser
  ];
}
```

### 4.3 `modules/system.nix` (MODIFIED)

Changes:
1. Add new option `vexos.system.gaming` (type `bool`, default `false`).
2. Wrap the following block in `lib.mkIf config.vexos.system.gaming { ... }`:
   - `preempt=full` kernel param
   - `split_lock_detect=off` kernel param
   - `quiet splash loglevel=3` kernel params (move from unconditional `kernelParams` list)
   - `vm.max_map_count = 2147483642` sysctl
   - THP madvise `systemd.tmpfiles.rules`
   - `vexos.scx.enable` option declaration + `lib.mkIf config.vexos.scx.enable { services.scx ... }` block
3. Change `boot.plymouth.enable = true;` to `boot.plymouth.enable = lib.mkDefault false;`
4. Keep `elevator=kyber` in the unconditional params block (acceptable everywhere).

**Unconditional `boot.kernelParams` after change:**
```nix
boot.kernelParams = [
  "elevator=kyber"
];
```

**Gaming-gated `boot.kernelParams`:**
```nix
(lib.mkIf config.vexos.system.gaming {
  boot.kernelParams = [
    "preempt=full"
    "split_lock_detect=off"
    "quiet"
    "splash"
    "loglevel=3"
  ];
  boot.kernel.sysctl."vm.max_map_count" = 2147483642;
  systemd.tmpfiles.rules = [
    "w /sys/kernel/mm/transparent_hugepage/enabled - - - - madvise"
    "w /sys/kernel/mm/transparent_hugepage/defrag   - - - - defer+madvise"
  ];
})
```

The `vexos.scx` option declaration and its `lib.mkIf config.vexos.scx.enable` block remain as-is, but the entire scx section moves inside `lib.mkIf config.vexos.system.gaming`. This means on non-gaming roles, `vexos.scx.enable` is not declared and SCX is completely absent.

### 4.4 `modules/gpu.nix` (MODIFIED)

Changes:
1. Change `enable32Bit = true` → `enable32Bit = lib.mkDefault false`
2. Move `extraPackages32` block to be conditional: `lib.mkIf config.hardware.graphics.enable32Bit { hardware.graphics.extraPackages32 = ...; }`
3. Move `vulkan-tools` and `mesa-demos` out of unconditional `environment.systemPackages` and gate behind `lib.mkIf config.vexos.system.gaming`.

**After change, unconditional systemPackages in gpu.nix:**
```nix
environment.systemPackages = with pkgs; [
  ffmpeg-full      # Full codec support
  libva-utils      # vainfo — verify VA-API acceleration
  vulkan-loader    # Vulkan runtime loader
] ++ lib.optionals config.vexos.system.gaming [
  vulkan-tools     # vulkaninfo — desktop diagnostic
  mesa-demos       # glxinfo, glxgears — OpenGL/Vulkan renderer info
];
```

Note: `vulkan-loader` stays unconditional because it is a runtime dependency of applications compiled against Vulkan, not a diagnostic.

### 4.5 `modules/branding.nix` (MODIFIED)

Add new option:
```nix
options.vexos.branding.hasDisplay = lib.mkOption {
  type        = lib.types.bool;
  default     = true;
  description = "Set false on headless roles (no display manager, no wallpapers, no GDM config).";
};
```

Gate the following behind `lib.mkIf config.vexos.branding.hasDisplay`:
- `vexosWallpapers` package (and its inclusion in `environment.systemPackages`)
- `environment.etc."vexos/gdm-logo.png"` block
- `programs.dconf.profiles.gdm` block

The following remain unconditional (safe everywhere):
- `boot.plymouth.theme` and `boot.plymouth.logo` — harmless when Plymouth is disabled (settings are evaluated but Plymouth won't be active)
- `system.nixos.distroName`, `distroId`, `vendorName`, `vendorId`, `label`
- `system.nixos.extraOSReleaseArgs`
- `environment.systemPackages = [ vexosLogos vexosIcons ]` — logos useful in all roles

### 4.6 `modules/flatpak.nix` (MODIFIED)

Extract gaming/development-only apps into a `desktopOnlyApps` list and add conditionally:

```nix
# Apps installed on every display role.
defaultApps = [
  "com.bitwarden.desktop"
  "com.github.tchx84.Flatseal"
  "it.mijorus.gearlever"
  "io.missioncenter.MissionCenter"
  "com.simplenote.Simplenote"
  "io.github.flattool.Warehouse"
  "app.zen_browser.zen"
  "com.mattjakeman.ExtensionManager"
  "com.rustdesk.RustDesk"
  "io.github.kolunmi.Bazaar"
  "org.pulseaudio.pavucontrol"
  "org.gnome.World.PikaBackup"
];

# Apps installed only on the desktop role.
desktopOnlyApps = [
  "io.github.pol_rivero.github-desktop-plus"
  "org.onlyoffice.desktopeditors"
  "org.prismlauncher.PrismLauncher"
  "com.vysp3r.ProtonPlus"
  "net.lutris.Lutris"
  "com.ranfdev.DistroShelf"
];

appsToInstall = (lib.filter
  (a: !builtins.elem a config.vexos.flatpak.excludeApps)
  (defaultApps
    ++ lib.optionals (config.vexos.branding.role == "desktop") desktopOnlyApps))
++ config.vexos.flatpak.extraApps;
```

**Consequence**: The `vexos.flatpak.excludeApps` lists in `configuration-server.nix`, `configuration-htpc.nix`, and `configuration-stateless.nix` can be reduced or removed entirely, since the desktop-only apps are no longer in `defaultApps`. Specifically:
- Remove from server `excludeApps`: `com.ranfdev.DistroShelf`, `com.vysp3r.ProtonPlus`, `net.lutris.Lutris`, `org.prismlauncher.PrismLauncher`, `io.github.pol_rivero.github-desktop-plus`, `org.onlyoffice.desktopeditors` (all 6 entries — GIMP stays if present elsewhere)
- Remove from htpc `excludeApps`: same 6 entries (GIMP handled separately)
- Remove from stateless `excludeApps`: only `org.gimp.GIMP` remains (unchanged)

### 4.7 `modules/network.nix` (MODIFIED)

Gate `samba` behind `lib.mkIf config.vexos.branding.hasDisplay`:

```nix
environment.systemPackages = with pkgs; [
  cifs-utils  # mount.cifs — useful on all roles that may mount NFS/SMB
] ++ lib.optionals config.vexos.branding.hasDisplay [
  samba       # smbclient — useful on desktop/HTPC/server; overkill on headless
];
```

---

## 5. Exact New Import Lists per `configuration-*.nix`

### `configuration-desktop.nix`

```nix
imports = [
  ./modules/gnome.nix
  ./modules/gaming.nix
  ./modules/audio.nix
  ./modules/gpu.nix
  ./modules/flatpak.nix
  ./modules/network.nix
  ./modules/packages-common.nix       # ← NEW (replaces packages.nix)
  ./modules/packages-desktop.nix      # ← NEW
  ./modules/development.nix
  ./modules/virtualization.nix
  ./modules/branding.nix
  ./modules/system.nix
];
```

New settings to add in `configuration-desktop.nix`:
```nix
vexos.system.gaming            = true;   # Enable gaming kernel tuning
boot.plymouth.enable           = true;   # Graphical boot splash
hardware.graphics.enable32Bit  = true;   # Steam/Proton 32-bit
```

### `configuration-headless-server.nix`

```nix
imports = [
  ./modules/gpu.nix
  ./modules/branding.nix
  ./modules/network.nix
  ./modules/packages-common.nix       # ← NEW (replaces packages.nix)
  ./modules/system.nix
  ./modules/server
];
```

New/changed settings:
```nix
vexos.branding.hasDisplay = false;  # ← NEW — disables wallpapers, GDM dconf
# REMOVE: hardware.graphics.enable32Bit = lib.mkForce false;  (no longer needed)
# REMOVE: vexos.scx.enable = false;                           (SCX not declared on non-gaming roles)
```

### `configuration-server.nix` (GUI server)

```nix
imports = [
  ./modules/gnome.nix
  ./modules/audio.nix
  ./modules/gpu.nix
  ./modules/branding.nix
  ./modules/flatpak.nix
  ./modules/network.nix
  ./modules/packages-common.nix       # ← NEW (replaces packages.nix)
  ./modules/packages-desktop.nix      # ← NEW
  ./modules/system.nix
  ./modules/server
];
```

New/changed settings:
```nix
boot.plymouth.enable = true;   # ← ADD — display role wants graphical boot
# REMOVE: vexos.flatpak.excludeApps = [ <6 gaming/dev apps> ... ];
# RETAIN: vexos.flatpak.excludeApps = [ "org.gimp.GIMP" ];  if GIMP exclusion desired
```

### `configuration-htpc.nix`

```nix
imports = [
  ./modules/gnome.nix
  ./modules/audio.nix
  ./modules/gpu.nix
  ./modules/flatpak.nix
  ./modules/network.nix
  ./modules/packages-common.nix       # ← NEW (replaces packages.nix)
  ./modules/packages-desktop.nix      # ← NEW
  ./modules/branding.nix
  ./modules/system.nix
];
```

New/changed settings:
```nix
boot.plymouth.enable = true;   # ← ADD — display role wants graphical boot
# REMOVE: vexos.flatpak.excludeApps = [ <6 gaming/dev apps> ... ];
# RETAIN: vexos.flatpak.excludeApps = [ "org.gimp.GIMP" ];  if desired
```

### `configuration-stateless.nix`

```nix
imports = [
  ./modules/gnome.nix
  ./modules/audio.nix
  ./modules/gpu.nix
  ./modules/flatpak.nix
  ./modules/network.nix
  ./modules/packages-common.nix       # ← NEW (replaces packages.nix)
  ./modules/packages-desktop.nix      # ← NEW
  ./modules/branding.nix
  ./modules/system.nix
  ./modules/impermanence.nix
];
```

New/changed settings:
```nix
boot.plymouth.enable = true;   # ← ADD — display role wants graphical boot
# vexos.flatpak.excludeApps = [ "org.gimp.GIMP" ]; unchanged
```

---

## 6. Impact Summary After Changes

### What headless-server LOSES (correctly removed):

| Was receiving | Fixed by |
|--------------|---------|
| `brave` browser | `packages.nix` → `packages-common.nix` (no brave) |
| `boot.plymouth.enable = true` | `system.nix`: Plymouth now `lib.mkDefault false` |
| `preempt=full`, `split_lock_detect=off`, `quiet splash loglevel=3` | `system.nix`: gated behind `vexos.system.gaming` |
| `vm.max_map_count = 2147483642` | `system.nix`: gated behind `vexos.system.gaming` |
| THP madvise rules | `system.nix`: gated behind `vexos.system.gaming` |
| `vexos.scx.enable` option + SCX service | `system.nix`: scx block inside gaming gate |
| `hardware.graphics.enable32Bit = true` (now force-overridden) | `gpu.nix`: defaults to `false` |
| `vulkan-tools`, `mesa-demos` | `gpu.nix`: gated behind `vexos.system.gaming` |
| 32-bit graphics packages | `gpu.nix`: conditional on `enable32Bit` |
| Wallpapers deployment | `branding.nix`: gated on `hasDisplay` |
| GDM dconf profile | `branding.nix`: gated on `hasDisplay` |
| `samba` package | `network.nix`: gated on `hasDisplay` |

### What headless-server RETAINS (appropriate):

- `hardware.graphics.enable = true` — GPU still needed for compute/display outputs
- `ffmpeg-full`, `libva`, `libva-utils`, `vulkan-loader` — transcoding/compute tools
- Plymouth theme/logo settings — harmless when Plymouth is disabled
- OS identity branding (logos, icons) — useful in `neofetch`, `inxi`, `hostnamectl`
- NetworkManager, Avahi, SSH, Tailscale, firewall — all needed
- `cifs-utils` — useful for mounting SMB shares
- `just`, `btop`, `inxi`, `git`, `curl`, `wget` — CLI tools

### Overrides that become obsolete in headless-server config:

| Line | Reason now redundant |
|------|---------------------|
| `hardware.graphics.enable32Bit = lib.mkForce false;` | `gpu.nix` defaults to `false` |
| `vexos.scx.enable = false;` | SCX no longer declared on non-gaming roles |

### What server/htpc/stateless GAIN (corrections):

| Role | Was receiving incorrectly | Fixed by |
|------|--------------------------|---------|
| server, htpc, stateless | Gaming kernel params (preempt, split_lock, max_map_count) | `vexos.system.gaming` gate in `system.nix` |
| server, htpc, stateless | `vm.max_map_count = 2147483642` | same |
| server, htpc, stateless | THP madvise rules | same |
| server, htpc, stateless | SCX LAVD gaming scheduler | same |
| server, htpc, stateless | `vulkan-tools`, `mesa-demos` | `gpu.nix` gaming gate |
| server, htpc, stateless | `hardware.graphics.enable32Bit = true` (Proton 32-bit) | `gpu.nix` defaults to `false` |
| server, htpc, stateless | Gaming/dev Flatpak apps in negative-exclusion list | `flatpak.nix` additive redesign |

---

## 7. Risks and Mitigations

| Risk | Mitigation |
|------|-----------|
| Removing `vexos.scx.enable` option from non-gaming configs means any existing non-desktop config that sets `vexos.scx.enable = false` will get an "undefined option" evaluation error | After moving SCX into the gaming gate, remove `vexos.scx.enable = false;` from `configuration-headless-server.nix` in the same commit |
| Changing `enable32Bit` from `true` to `lib.mkDefault false` could break builds if any GPU brand module (e.g., `gpu/nvidia.nix`) force-sets `enable32Bit = true` | Check all `modules/gpu/*.nix` files; if they set `enable32Bit`, that will override `lib.mkDefault false` correctly via priority. Verify no brand module uses `enable32Bit = lib.mkForce true`. |
| `boot.plymouth.enable = lib.mkDefault false` means all display configs must explicitly set `boot.plymouth.enable = true` — forgetting to set it in one role silently disables Plymouth | Document clearly; verify all five display-role configs set it. Use `nix flake check` to catch evaluation errors. |
| Removing gaming/dev apps from `flatpak.nix` defaultApps may cause them to not be uninstalled if already present on non-desktop roles (no removal trigger for apps not in excludeApps) | Keep apps that were previously excluded by non-desktop roles in `excludeApps` for one rebuild cycle, or rely on the unconditional removal loop for "banned" apps; document migration path. Alternatively, add removed apps to the "banned" list for non-desktop roles for one release. |
| `vexos.branding.hasDisplay` option must be defined before `configuration-headless-server.nix` sets it | Since `branding.nix` is imported before the option is set (imports are merged), this is fine — options are declared in the module, values set in configuration files. Standard NixOS pattern. |
| `configuration-stateless.nix` currently has `vexos.flatpak.excludeApps = [ "org.gimp.GIMP" ]` — after the split, desktop-only apps are no longer in `defaultApps`, so this exclusion line is still valid (GIMP exclusion is separate from the gaming app exclusion) | Keep the GIMP exclusion in stateless; only remove the 6 gaming/dev app entries from server/htpc/stateless excludeApps lists. |
| `modules/packages.nix` is deleted — any future host or module that imports it will fail at evaluation | Verify all import sites are updated. Grep the repo for `./modules/packages.nix` imports across all config files. |

---

## 8. Implementation Order

Implement in this order to keep the flake evaluable after each step:

1. **Create** `modules/packages-common.nix` and `modules/packages-desktop.nix`
2. **Modify** all `configuration-*.nix` to replace `packages.nix` import with the two new files
3. **Delete** `modules/packages.nix`
4. **Modify** `modules/system.nix` — add `vexos.system.gaming` option + gaming gate; change Plymouth default
5. **Modify** `configuration-desktop.nix` — add `vexos.system.gaming = true` and `boot.plymouth.enable = true`
6. **Modify** remaining display configs — add `boot.plymouth.enable = true`
7. **Modify** `configuration-headless-server.nix` — add `vexos.branding.hasDisplay = false`; remove force-overrides
8. **Modify** `modules/gpu.nix` — change `enable32Bit` default; gate 32-bit packages; gate vulkan-tools/mesa-demos
9. **Modify** `configuration-desktop.nix` — add `hardware.graphics.enable32Bit = true`
10. **Modify** `modules/branding.nix` — add `vexos.branding.hasDisplay` option; gate wallpapers/GDM
11. **Modify** `modules/flatpak.nix` — split `defaultApps` / `desktopOnlyApps`
12. **Modify** server/htpc/stateless configs — clean up now-redundant `excludeApps` entries
13. **Modify** `modules/network.nix` — gate `samba` behind `hasDisplay`
14. **Run** `nix flake check` and dry-build all targets

---

## 9. Files Modified / Created Reference

| File | Action |
|------|--------|
| `modules/packages-common.nix` | CREATE |
| `modules/packages-desktop.nix` | CREATE |
| `modules/packages.nix` | DELETE |
| `modules/system.nix` | MODIFY |
| `modules/gpu.nix` | MODIFY |
| `modules/branding.nix` | MODIFY |
| `modules/flatpak.nix` | MODIFY |
| `modules/network.nix` | MODIFY |
| `configuration-desktop.nix` | MODIFY |
| `configuration-headless-server.nix` | MODIFY |
| `configuration-server.nix` | MODIFY |
| `configuration-htpc.nix` | MODIFY |
| `configuration-stateless.nix` | MODIFY |
