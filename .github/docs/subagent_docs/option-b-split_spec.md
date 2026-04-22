# Option B Split — Research & Specification

**Target**: Refactor shared modules to strict Option B (Common base + role additions).  
**No `lib.mkIf` guards gating content by role/feature inside shared modules.**  
**Roles express themselves entirely through their import list.**

---

## 1. Current State — Every Guard in Every Shared Module

### 1.1 `modules/system.nix`

| Guard | What it gates |
|-------|---------------|
| `lib.mkIf config.vexos.system.gaming { ... }` | `boot.kernelParams` gaming set (`preempt=full`, `split_lock_detect=off`, `quiet`, `splash`, `loglevel=3`), `boot.kernel.sysctl."vm.max_map_count" = 2147483642`, `systemd.tmpfiles.rules` (THP madvise) |
| `lib.mkIf (config.vexos.system.gaming && config.vexos.scx.enable) { ... }` | `services.scx = { enable = true; scheduler = "scx_lavd"; }` |
| `lib.mkIf config.vexos.swap.enable { ... }` | `swapDevices` (8 GiB swap file) — **KEEP: this is a feature toggle, not a role toggle** |
| `lib.mkIf config.vexos.btrfs.enable { ... }` | `services.btrfs.autoScrub`, `btrfs-assistant` + `btrfs-progs` packages — **KEEP: this is a feature toggle, not a role toggle** |

Custom options in `system.nix`:
- `vexos.btrfs.enable` — **KEEP** (feature toggle; vm.nix sets it false)
- `vexos.system.gaming` — **REMOVE** (replaced by import of `system-gaming.nix`)
- `vexos.scx.enable` — **REMOVE** (SCX is unconditional inside `system-gaming.nix`; VM overrides `services.scx.enable = lib.mkForce false`)
- `vexos.swap.enable` — **KEEP** (feature toggle; vm.nix sets it false)

---

### 1.2 `modules/gpu.nix`

| Guard | What it gates |
|-------|---------------|
| `hardware.graphics.extraPackages32 = lib.mkIf config.hardware.graphics.enable32Bit (...)` | 32-bit VA-API/Mesa packages (`pkgsi686Linux`) |
| `lib.optionals config.vexos.system.gaming [vulkan-tools mesa-demos]` | Gaming diagnostic tools in `environment.systemPackages` |

No custom `vexos.*` options declared here; uses `config.vexos.system.gaming` from `system.nix`.

---

### 1.3 `modules/branding.nix`

| Guard | What it gates |
|-------|---------------|
| `++ lib.optionals config.vexos.branding.hasDisplay [ vexosWallpapers ]` | `vexosWallpapers` derivation added to `environment.systemPackages` |
| `environment.etc = lib.mkIf config.vexos.branding.hasDisplay { ... }` | `/etc/vexos/gdm-logo.png` deployed via `environment.etc` |
| `programs.dconf.profiles.gdm = lib.mkIf config.vexos.branding.hasDisplay { ... }` | GDM dconf profile setting `org/gnome/login-screen.logo` |

Path selection in the `let` block uses `config.vexos.branding.role`:
```nix
role          = config.vexos.branding.role;
pixmapsDir    = ../files/pixmaps    + "/${role}";
bgLogosDir    = ../files/background_logos + "/${role}";
plymouthDir   = ../files/plymouth   + "/${role}";
wallpapersDir = ../wallpapers        + "/${role}";
```

`system.nixos.distroName` uses a role-based if/else chain.

Custom options:
- `vexos.branding.role` — **KEEP** (see Section 3.1 for full rationale)
- `vexos.branding.hasDisplay` — **REMOVE** (replaced by import of `branding-display.nix`)

---

### 1.4 `modules/network.nix`

| Guard | What it gates |
|-------|---------------|
| `lib.optionals config.vexos.branding.hasDisplay [samba]` | `samba` package in `environment.systemPackages` |

No custom `vexos.*` options declared here; uses `config.vexos.branding.hasDisplay` from `branding.nix`.

---

### 1.5 `modules/flatpak.nix`

| Guard | What it gates |
|-------|---------------|
| `lib.optionals (config.vexos.branding.role == "desktop") desktopOnlyApps` | Six desktop-only Flatpak app IDs merged into `appsToInstall` |

```nix
desktopOnlyApps = [
  "io.github.pol_rivero.github-desktop-plus"
  "org.onlyoffice.desktopeditors"
  "org.prismlauncher.PrismLauncher"
  "com.vysp3r.ProtonPlus"
  "net.lutris.Lutris"
  "com.ranfdev.DistroShelf"
];
```

Custom options in `flatpak.nix`:
- `vexos.flatpak.enable` — **KEEP**
- `vexos.flatpak.excludeApps` — **KEEP**
- `vexos.flatpak.extraApps` — **KEEP** (this is the correct mechanism for the split)

---

### 1.6 `modules/gnome.nix` (uses `vexos.branding.role` — out of main split scope)

`gnome.nix` uses `config.vexos.branding.role` in four places:

| Usage | What it controls |
|-------|-----------------|
| `accentColor` lookup | Maps role → dconf accent color (`blue`/`orange`/`yellow`/`teal`) |
| `enabledExtensions` conditional | Desktop adds `gamemodeshellextension@trsnaqe.com` |
| `environment.gnome.excludePackages` | Non-desktop roles exclude `papers` |
| `gnomeAppsToInstall` + service script | Desktop adds `gnomeDesktopOnlyApps`; service uninstalls them on non-desktop |

**Decision**: Since `vexos.branding.role` is retained (see §3.1), these usages are acceptable in the current pass. They are not guards on a flag being removed — they are data-driven lookups against the role value that remains valid. Splitting gnome.nix further (e.g. `gnome-desktop.nix`) is future work and out of scope for this refactor.

---

### 1.7 `modules/audio.nix`, `modules/packages-common.nix`, `modules/packages-desktop.nix`

No guards. No changes needed.

---

## 2. Decision for Each Module

### 2.1 `modules/system.nix` → split into `system.nix` + `system-gaming.nix`

**Universal base (`system.nix`):**
- Kernel: `boot.kernelPackages = linuxPackages_latest`
- Base `boot.kernelParams`: only `"elevator=kyber"`
- `boot.plymouth.enable = lib.mkDefault false`
- ZRAM swap (always-on)
- CPU frequency governor: `schedutil`
- Kernel sysctl tunables (BBR, swappiness, inotify limits, socket buffers, sysrq)
- `vexos.swap.enable` option + its `lib.mkIf` block (kept, feature toggle)
- `vexos.btrfs.enable` option + its `lib.mkIf` block (kept, feature toggle)
- **REMOVE**: `vexos.system.gaming` option declaration
- **REMOVE**: `vexos.scx.enable` option declaration
- **REMOVE**: both gaming `lib.mkIf` blocks

**Role addition (`system-gaming.nix`):**
- Gaming `boot.kernelParams` (`preempt=full`, `split_lock_detect=off`, `quiet`, `splash`, `loglevel=3`)
- `boot.kernel.sysctl."vm.max_map_count" = 2147483642`
- `systemd.tmpfiles.rules` for THP madvise
- `services.scx = { enable = true; scheduler = "scx_lavd"; }` (unconditional)
- **Imported by**: `configuration-desktop.nix` only
- VM override: `modules/gpu/vm.nix` adds `services.scx.enable = lib.mkForce false` (replaces the removed `vexos.scx.enable = false`)

---

### 2.2 `modules/gpu.nix` → split into `gpu.nix` + `gpu-gaming.nix`

**Universal base (`gpu.nix`):**
- `hardware.graphics.enable = true`
- `hardware.graphics.enable32Bit = lib.mkDefault false` — kept as a safe default; `gpu-gaming.nix` overrides it to `true`
- `hardware.graphics.extraPackages` (VA-API, VDPAU, Vulkan, iHD, Mesa — all builds)
- `environment.systemPackages = [ffmpeg-full libva-utils vulkan-loader]` — no optionals
- **REMOVE**: `hardware.graphics.extraPackages32 = lib.mkIf config.hardware.graphics.enable32Bit (...)`
- **REMOVE**: `lib.optionals config.vexos.system.gaming [vulkan-tools mesa-demos]`

**Role addition (`gpu-gaming.nix`):**
- `hardware.graphics.enable32Bit = true` (unconditional — replaces the inline setting in `configuration-desktop.nix`)
- `hardware.graphics.extraPackages32` with `pkgsi686Linux` packages (unconditional — 32-bit is always true when this file is imported)
- `environment.systemPackages = [vulkan-tools mesa-demos]`
- **Imported by**: `configuration-desktop.nix` only

**Side effect on `configuration-desktop.nix`**: remove the inline `hardware.graphics.enable32Bit = true` assignment (it moves to `gpu-gaming.nix`).

---

### 2.3 `modules/branding.nix` → split into `branding.nix` + `branding-display.nix`

**Universal base (`branding.nix`):**
- **KEEP**: `vexos.branding.role` option (for path selection — see §3.1)
- **REMOVE**: `vexos.branding.hasDisplay` option declaration
- `let` block: keep `pixmapsDir`, `bgLogosDir`, `plymouthDir`; **REMOVE** `wallpapersDir` and `vexosWallpapers` derivation
- `boot.plymouth.theme = lib.mkDefault "spinner"`
- `boot.plymouth.logo = plymouthDir + "/watermark.png"`
- `system.nixos.distroName` (role-based if/else chain — stays here)
- `system.nixos.label`, `distroId`, `vendorName`, `vendorId`, `extraOSReleaseArgs`
- `environment.systemPackages = [ vexosLogos vexosIcons ]` — **no wallpapers**
- Boot menu entry cleanup (`boot.loader.systemd-boot.extraInstallCommands`)
- **REMOVE**: `++ lib.optionals config.vexos.branding.hasDisplay [ vexosWallpapers ]`
- **REMOVE**: `environment.etc = lib.mkIf config.vexos.branding.hasDisplay { ... }`
- **REMOVE**: `programs.dconf.profiles.gdm = lib.mkIf config.vexos.branding.hasDisplay { ... }`

**Role addition (`branding-display.nix`):**
- Declares its own `let` block reusing `config.vexos.branding.role` for `pixmapsDir` + `wallpapersDir`
- `vexosWallpapers` derivation
- `environment.systemPackages = [ vexosWallpapers ]`
- `environment.etc."vexos/gdm-logo.png".source = pixmapsDir + "/fedora-gdm-logo.png"`
- `programs.dconf.profiles.gdm` block (unconditional — display roles always have GDM)
- **Imported by**: `configuration-desktop.nix`, `configuration-server.nix`, `configuration-htpc.nix`, `configuration-stateless.nix`
- **NOT imported by**: `configuration-headless-server.nix`

---

### 2.4 `modules/network.nix` → split into `network.nix` + `network-desktop.nix`

**Universal base (`network.nix`):**
- NetworkManager, Avahi, firewall, SSH, Tailscale, resolved
- `environment.systemPackages = [cifs-utils]` — no conditionals
- **REMOVE**: `++ lib.optionals config.vexos.branding.hasDisplay [samba]`

**Role addition (`network-desktop.nix`):**
- `environment.systemPackages = [samba]`
- **Imported by**: `configuration-desktop.nix`, `configuration-server.nix`, `configuration-htpc.nix`, `configuration-stateless.nix`
- **NOT imported by**: `configuration-headless-server.nix`

---

### 2.5 `modules/flatpak.nix` → base stays, add `modules/flatpak-desktop.nix`

**Strategy**: The `vexos.flatpak.extraApps` option already exists. The base module's `appsToInstall` already appends `config.vexos.flatpak.extraApps`. A `flatpak-desktop.nix` sets this option to the desktop-only list; the merge semantics of `listOf` concatenate it with any other assignments. No service logic changes needed.

**Changes to `flatpak.nix`:**
- **REMOVE**: `desktopOnlyApps` list definition from the `let` block
- **REMOVE**: `++ lib.optionals (config.vexos.branding.role == "desktop") desktopOnlyApps` from `appsToInstall`
- Everything else unchanged

**New file (`flatpak-desktop.nix`):**
- Sets `vexos.flatpak.extraApps = [ ... desktopOnlyApps ... ]`
- **Imported by**: `configuration-desktop.nix` only
- Other configs that already use `vexos.flatpak.extraApps` inline (htpc, stateless) are unaffected — list merging handles multiple sources

---

## 3. Decision on Each Custom Option

### 3.1 `vexos.branding.role` — **KEEP** (minimal, justified)

**Reason it cannot be expressed via an import:**

The path expressions in `branding.nix` are evaluated at Nix evaluation time:
```nix
pixmapsDir = ../files/pixmaps + "/${role}";
plymouthDir = ../files/plymouth + "/${role}";
```
Nix requires these to be concrete store paths at build time. There is no mechanism in the NixOS module system to "inject" a directory fragment via an import — the path must be computed from a value available during evaluation, and `config.vexos.branding.role` is the established mechanism for providing that value.

**Alternatives considered and rejected:**

- *Hardcode paths in role-specific branding files*: Would require 4 separate `branding-desktop.nix`, `branding-htpc.nix`, `branding-server.nix`, `branding-stateless.nix` files, each repeating the full derivation logic (`vexosLogos`, `vexosIcons`, `boot.plymouth.logo`, etc.) with only the path fragment differing. This duplicates ~80 lines of non-trivial derivation code per role.
- *Pass path as a module argument*: `specialArgs` can thread arbitrary values, but this would require the flake to know and pass role-specific paths — moving role knowledge up one level into `flake.nix`, which is worse.

**gnome.nix also uses `vexos.branding.role`**: for accent colors, extension lists, and Flatpak app management. Since the option is retained, these usages are valid. Splitting gnome.nix further is deferred as future work.

**What `vexos.branding.role` controls after this refactor:**
- Path selection for pixmaps, background logos, Plymouth watermark (in `branding.nix`)
- Path selection for wallpapers (in `branding-display.nix`)
- `system.nixos.distroName` if/else chain (in `branding.nix`)
- Accent color and extension selection in `gnome.nix` (retained as-is)

---

### 3.2 `vexos.branding.hasDisplay` — **REMOVE**

Replaced entirely by the presence/absence of `branding-display.nix` and `network-desktop.nix` in the import list. No module references it after the split.

---

### 3.3 `vexos.system.gaming` — **REMOVE**

Replaced entirely by importing `system-gaming.nix` and `gpu-gaming.nix`. No module references it after the split.

---

### 3.4 `vexos.scx.enable` — **REMOVE**

SCX is unconditionally enabled inside `system-gaming.nix`. The VM host (`modules/gpu/vm.nix`) must be updated to override via `services.scx.enable = lib.mkForce false` (replacing the current `vexos.scx.enable = false`). This is the correct NixOS pattern for a host-level override of an unconditionally-set service.

---

### 3.5 `vexos.btrfs.enable` — **KEEP**

Genuine feature toggle (auto-detects btrfs root; can be forced off for non-btrfs or VM). Not a role toggle. VM correctly overrides it to `false`.

---

### 3.6 `vexos.swap.enable` — **KEEP**

Genuine feature toggle (8 GiB swap file). VM correctly overrides it to `false`.

---

### 3.7 `vexos.flatpak.enable`, `vexos.flatpak.excludeApps`, `vexos.flatpak.extraApps` — **KEEP ALL**

These are functional configuration options, not role/display discriminators.

---

## 4. Complete New File Contents

### 4.1 `modules/system-gaming.nix` (NEW)

```nix
# modules/system-gaming.nix
# Gaming-optimised kernel parameters, vm.max_map_count, Transparent Huge Pages,
# and the SCX LAVD CPU scheduler.
#
# Import in any configuration that requires gaming-level kernel tuning.
# Do NOT import on VM guests or headless roles.
#
# If a specific host must disable SCX (e.g. a VM pinned to a kernel < 6.12
# that lacks sched_ext support), override in the host file:
#   services.scx.enable = lib.mkForce false;
{ ... }:
{
  boot.kernelParams = [
    # Full preemption — lowest desktop/gaming latency
    "preempt=full"

    # Disable split-lock detection for better Wine/Proton compatibility
    "split_lock_detect=off"

    # Clean boot experience (matches Bazzite)
    "quiet"
    "splash"
    "loglevel=3"
  ];

  # Maximum memory map areas per process — required by Proton/Wine anti-cheat
  # (EAC, BattlEye). 2147483642 is MAX_INT-5, the value set by SteamOS/Bazzite.
  boot.kernel.sysctl."vm.max_map_count" = 2147483642;

  # ── Transparent Huge Pages ────────────────────────────────────────────────
  # madvise: allocate THP only when applications explicitly request it.
  systemd.tmpfiles.rules = [
    "w /sys/kernel/mm/transparent_hugepage/enabled - - - - madvise"
    "w /sys/kernel/mm/transparent_hugepage/defrag   - - - - defer+madvise"
  ];

  # ── SCX LAVD CPU scheduler ────────────────────────────────────────────────
  # SteamOS/Bazzite scheduler — optimised for gaming desktops.
  # Requires sched_ext support (upstream 6.14+, zen 6.12+, lqx 6.12+).
  # Override with lib.mkForce false in the host file if running a kernel
  # older than 6.12 that lacks sched_ext (e.g. the VM 6.6 LTS pin).
  services.scx = {
    enable    = true;
    scheduler = "scx_lavd";
  };
}
```

---

### 4.2 `modules/gpu-gaming.nix` (NEW)

```nix
# modules/gpu-gaming.nix
# 32-bit GPU libraries (Steam/Proton) and gaming diagnostic tools.
# Sets hardware.graphics.enable32Bit = true unconditionally.
#
# Import in any configuration that runs Steam or Proton.
# Do NOT import on VM guests or headless roles.
{ pkgs, ... }:
{
  hardware.graphics.enable32Bit = true;

  # 32-bit VA-API and Mesa — required for Steam/Proton 32-bit graphics paths.
  hardware.graphics.extraPackages32 = with pkgs.pkgsi686Linux; [
    libva
    libva-vdpau-driver
    mesa
  ];

  environment.systemPackages = with pkgs; [
    vulkan-tools  # vulkaninfo — verify Vulkan driver and capabilities
    mesa-demos    # glxinfo, glxgears — OpenGL/Vulkan renderer diagnostics
  ];
}
```

---

### 4.3 `modules/branding-display.nix` (NEW)

```nix
# modules/branding-display.nix
# Display-role branding additions: wallpapers and GDM login-screen logo.
#
# Import in any configuration with a display manager (desktop, server, htpc, stateless).
# Do NOT import on headless-server or other roles without a display.
#
# Requires: modules/branding.nix (must be imported first to declare vexos.branding.role).
{ pkgs, lib, config, ... }:
let
  role          = config.vexos.branding.role;
  pixmapsDir    = ../files/pixmaps + "/${role}";
  wallpapersDir = ../wallpapers    + "/${role}";

  # Role-specific wallpapers deployed to a stable Nix store path so the system
  # dconf profile can reference them without relying on home-manager activation.
  # Path available immediately after nixos-rebuild switch, before any session starts.
  vexosWallpapers = pkgs.runCommand "vexos-wallpapers" {} ''
    mkdir -p $out/share/backgrounds/vexos
    cp ${wallpapersDir}/vex-bb-light.jxl $out/share/backgrounds/vexos/vex-bb-light.jxl
    cp ${wallpapersDir}/vex-bb-dark.jxl  $out/share/backgrounds/vexos/vex-bb-dark.jxl
  '';
in
{
  # Deploy wallpapers to the Nix store so dconf settings can reference a
  # stable path (/run/current-system/sw/share/backgrounds/vexos/).
  environment.systemPackages = [ vexosWallpapers ];

  # GDM login-screen logo — deployed to /etc/ first; Nix store paths change on
  # every rebuild so dconf must point to a stable /etc path instead.
  environment.etc."vexos/gdm-logo.png".source = pixmapsDir + "/fedora-gdm-logo.png";

  # Sets org.gnome.login-screen.logo in the GDM system dconf profile.
  # NOTE: Defining programs.dconf.profiles.gdm here overrides the GDM package's
  # built-in /share/dconf/profile/gdm. lib.mkDefault on enableUserDb prevents
  # an evaluation conflict if the GDM NixOS module sets this option in future.
  programs.dconf.profiles.gdm = {
    enableUserDb = lib.mkDefault false;  # GDM system account — no per-user db
    databases = [
      {
        settings = {
          "org/gnome/login-screen" = {
            logo = "/etc/vexos/gdm-logo.png";
          };
        };
      }
    ];
  };
}
```

---

### 4.4 `modules/network-desktop.nix` (NEW)

```nix
# modules/network-desktop.nix
# Display-role networking additions: samba CLI tools for SMB/CIFS browsing.
#
# Import in any configuration with a display (desktop, server, htpc, stateless).
# Do NOT import on headless-server.
{ pkgs, ... }:
{
  # samba: provides smbclient — browse and test SMB shares from the CLI.
  # GNOME Files (Nautilus) browses SMB shares natively via GVfs; smbclient
  # is the CLI companion tool. Client-only — no inbound firewall ports needed.
  environment.systemPackages = with pkgs; [
    samba  # smbclient — browse/test SMB shares; also provides nmblookup
  ];
}
```

---

### 4.5 `modules/flatpak-desktop.nix` (NEW)

```nix
# modules/flatpak-desktop.nix
# Desktop-role Flatpak additions: gaming, development, and productivity apps.
#
# Import only in configuration-desktop.nix.
# Requires: modules/flatpak.nix (declares vexos.flatpak.extraApps option).
#
# The vexos.flatpak.extraApps list option uses NixOS listOf merge semantics —
# multiple modules may set it and the values are concatenated automatically.
{ ... }:
{
  vexos.flatpak.extraApps = [
    "io.github.pol_rivero.github-desktop-plus"  # GitHub Desktop (community fork)
    "org.onlyoffice.desktopeditors"             # Office suite
    "org.prismlauncher.PrismLauncher"           # Minecraft launcher
    "com.vysp3r.ProtonPlus"                     # Proton/Wine version manager
    "net.lutris.Lutris"                          # Game manager / Wine frontend
    "com.ranfdev.DistroShelf"                   # Distribution browser
  ];
}
```

---

## 5. Modified Existing Files

### 5.1 `modules/system.nix` — changes required

**Remove** the `vexos.system.gaming` option block:
```nix
# DELETE this entire option block:
vexos.system.gaming = lib.mkOption {
  type        = lib.types.bool;
  default     = false;
  description = ''...gaming-optimised kernel parameters...''
};
```

**Remove** the `vexos.scx.enable` option block:
```nix
# DELETE this entire option block:
vexos.scx.enable = lib.mkOption {
  type    = lib.types.bool;
  default = true;
  description = ''...scx CPU scheduler...''
};
```

**Remove** the gaming `lib.mkIf` block (boot.kernelParams + vm.max_map_count + THP):
```nix
# DELETE:
(lib.mkIf config.vexos.system.gaming {
  boot.kernelParams = [ "preempt=full" ... ];
  boot.kernel.sysctl."vm.max_map_count" = 2147483642;
  systemd.tmpfiles.rules = [ ... ];
})
```

**Remove** the SCX `lib.mkIf` block:
```nix
# DELETE:
(lib.mkIf (config.vexos.system.gaming && config.vexos.scx.enable) {
  services.scx = { enable = true; scheduler = "scx_lavd"; };
})
```

Everything else in `system.nix` is unchanged.

---

### 5.2 `modules/gpu.nix` — changes required

**Remove** the `extraPackages32` guarded line:
```nix
# DELETE:
hardware.graphics.extraPackages32 = lib.mkIf config.hardware.graphics.enable32Bit
  (with pkgs.pkgsi686Linux; [ libva libva-vdpau-driver mesa ]);
```

**Remove** the gaming optionals from systemPackages:
```nix
# CHANGE FROM:
environment.systemPackages = with pkgs; [
  ffmpeg-full
  libva-utils
  vulkan-loader
] ++ lib.optionals config.vexos.system.gaming [
  vulkan-tools
  mesa-demos
];

# CHANGE TO:
environment.systemPackages = with pkgs; [
  ffmpeg-full
  libva-utils
  vulkan-loader
];
```

Everything else in `gpu.nix` is unchanged.

---

### 5.3 `modules/branding.nix` — changes required

**Remove** `vexos.branding.hasDisplay` option declaration:
```nix
# DELETE:
options.vexos.branding.hasDisplay = lib.mkOption {
  type        = lib.types.bool;
  default     = true;
  description = "Set false on headless roles (no display manager, no wallpapers, no GDM config).";
};
```

**Remove** `wallpapersDir` and `vexosWallpapers` from the `let` block:
```nix
# DELETE from let block:
wallpapersDir = ../wallpapers + "/${role}";

vexosWallpapers = pkgs.runCommand "vexos-wallpapers" {} ''
  mkdir -p $out/share/backgrounds/vexos
  cp ${wallpapersDir}/vex-bb-light.jxl $out/share/backgrounds/vexos/vex-bb-light.jxl
  cp ${wallpapersDir}/vex-bb-dark.jxl  $out/share/backgrounds/vexos/vex-bb-dark.jxl
'';
```

**Change** `environment.systemPackages` to remove wallpapers conditional:
```nix
# CHANGE FROM:
environment.systemPackages = [ vexosLogos vexosIcons ]
  ++ lib.optionals config.vexos.branding.hasDisplay [ vexosWallpapers ];

# CHANGE TO:
environment.systemPackages = [ vexosLogos vexosIcons ];
```

**Remove** the `environment.etc` guarded block:
```nix
# DELETE:
environment.etc = lib.mkIf config.vexos.branding.hasDisplay {
  "vexos/gdm-logo.png".source = pixmapsDir + "/fedora-gdm-logo.png";
};
```

**Remove** the `programs.dconf.profiles.gdm` guarded block:
```nix
# DELETE:
programs.dconf.profiles.gdm = lib.mkIf config.vexos.branding.hasDisplay {
  enableUserDb = lib.mkDefault false;
  databases = [ { settings = { "org/gnome/login-screen" = { logo = "/etc/vexos/gdm-logo.png"; }; }; } ];
};
```

---

### 5.4 `modules/network.nix` — changes required

**Change** `environment.systemPackages` to remove samba conditional:
```nix
# CHANGE FROM:
environment.systemPackages = with pkgs; [
  cifs-utils
] ++ lib.optionals config.vexos.branding.hasDisplay [
  samba
];

# CHANGE TO:
environment.systemPackages = with pkgs; [
  cifs-utils
];
```

---

### 5.5 `modules/flatpak.nix` — changes required

**Remove** `desktopOnlyApps` from the `let` block:
```nix
# DELETE:
desktopOnlyApps = [
  "io.github.pol_rivero.github-desktop-plus"
  "org.onlyoffice.desktopeditors"
  "org.prismlauncher.PrismLauncher"
  "com.vysp3r.ProtonPlus"
  "net.lutris.Lutris"
  "com.ranfdev.DistroShelf"
];
```

**Change** `appsToInstall` to remove the role conditional:
```nix
# CHANGE FROM:
appsToInstall = (lib.filter
  (a: !builtins.elem a config.vexos.flatpak.excludeApps)
  (defaultApps
    ++ lib.optionals (config.vexos.branding.role == "desktop") desktopOnlyApps))
++ config.vexos.flatpak.extraApps;

# CHANGE TO:
appsToInstall = (lib.filter
  (a: !builtins.elem a config.vexos.flatpak.excludeApps)
  defaultApps)
++ config.vexos.flatpak.extraApps;
```

---

### 5.6 `modules/gpu/vm.nix` — one line change

**Change** `vexos.scx.enable = false` to `services.scx.enable = lib.mkForce false`:
```nix
# CHANGE FROM:
# scx requires kernel >= 6.12; VM is pinned to 6.6 LTS — disable SCX scheduler.
vexos.scx.enable = false;

# CHANGE TO:
# scx requires kernel >= 6.12; VM is pinned to 6.6 LTS — disable SCX scheduler.
services.scx.enable = lib.mkForce false;
```

---

## 6. Complete New Import Lists for Each `configuration-*.nix`

### 6.1 `configuration-desktop.nix`

```nix
imports = [
  ./modules/gnome.nix
  ./modules/gaming.nix
  ./modules/audio.nix
  ./modules/gpu.nix
  ./modules/gpu-gaming.nix        # NEW — 32-bit libs, vulkan-tools, mesa-demos
  ./modules/flatpak.nix
  ./modules/flatpak-desktop.nix   # NEW — desktop-only Flatpak apps via extraApps
  ./modules/network.nix
  ./modules/network-desktop.nix   # NEW — samba CLI
  ./modules/packages-common.nix
  ./modules/packages-desktop.nix
  ./modules/development.nix
  ./modules/virtualization.nix
  ./modules/branding.nix
  ./modules/branding-display.nix  # NEW — wallpapers, GDM logo/dconf
  ./modules/system.nix
  ./modules/system-gaming.nix     # NEW — gaming kernel params, THP, SCX
];
```

**Also remove from `configuration-desktop.nix` body:**
```nix
# DELETE this line (now handled by gpu-gaming.nix):
hardware.graphics.enable32Bit = true;

# DELETE this line (now handled by system-gaming.nix):
vexos.system.gaming = true;
```

**Keep in `configuration-desktop.nix` body:**
```nix
vexos.branding.role  = "desktop";   # KEEP — path selection + gnome.nix role logic
boot.plymouth.enable = true;         # KEEP — display role enables plymouth
```

---

### 6.2 `configuration-headless-server.nix`

```nix
imports = [
  ./modules/gpu.nix
  ./modules/branding.nix
  ./modules/network.nix
  ./modules/packages-common.nix
  ./modules/system.nix
  ./modules/server
];
```

No changes to the import list itself. The key change is in the body:

**Remove from body:**
```nix
# DELETE this line (hasDisplay option is removed):
vexos.branding.hasDisplay = false;
```

**Keep in body:**
```nix
vexos.branding.role     = "server";   # KEEP — path selection
system.nixos.distroName = lib.mkOverride 500 "VexOS Headless Server";  # KEEP
```

---

### 6.3 `configuration-server.nix`

```nix
imports = [
  ./modules/gnome.nix
  ./modules/audio.nix
  ./modules/gpu.nix
  ./modules/branding.nix
  ./modules/branding-display.nix  # NEW — wallpapers, GDM logo/dconf
  ./modules/flatpak.nix
  ./modules/network.nix
  ./modules/network-desktop.nix   # NEW — samba CLI
  ./modules/packages-common.nix
  ./modules/packages-desktop.nix
  ./modules/system.nix
  ./modules/server
];
```

**Body**: no `vexos.branding.hasDisplay` was set here (it defaulted to `true`), so no removal needed. `vexos.branding.role = "server"` stays.

---

### 6.4 `configuration-htpc.nix`

```nix
imports = [
  ./modules/gnome.nix
  ./modules/audio.nix
  ./modules/gpu.nix
  ./modules/flatpak.nix
  ./modules/network.nix
  ./modules/network-desktop.nix   # NEW — samba CLI
  ./modules/packages-common.nix
  ./modules/packages-desktop.nix
  ./modules/branding.nix
  ./modules/branding-display.nix  # NEW — wallpapers, GDM logo/dconf
  ./modules/system.nix
];
```

**Body**: no gaming or hasDisplay flags to remove. `vexos.branding.role = "htpc"` stays.

---

### 6.5 `configuration-stateless.nix`

```nix
imports = [
  ./modules/gnome.nix
  ./modules/audio.nix
  ./modules/gpu.nix
  ./modules/flatpak.nix
  ./modules/network.nix
  ./modules/network-desktop.nix   # NEW — samba CLI
  ./modules/packages-common.nix
  ./modules/packages-desktop.nix
  ./modules/branding.nix
  ./modules/branding-display.nix  # NEW — wallpapers, GDM logo/dconf
  ./modules/system.nix
  ./modules/impermanence.nix
];
```

**Body**: `vexos.branding.role = "stateless"` stays. No gaming or hasDisplay flags to remove.

---

## 7. Summary of All Option Changes

| Option | Module | Action | Replacement |
|--------|--------|--------|-------------|
| `vexos.system.gaming` | `system.nix` | **REMOVE** declaration + both `mkIf` consumers | Import `system-gaming.nix` + `gpu-gaming.nix` |
| `vexos.scx.enable` | `system.nix` | **REMOVE** declaration + `mkIf` consumer | `services.scx.enable = lib.mkForce false` in `gpu/vm.nix` |
| `vexos.branding.hasDisplay` | `branding.nix` | **REMOVE** declaration + all 3 `mkIf` consumers | Import `branding-display.nix` + `network-desktop.nix` |
| `vexos.branding.role` | `branding.nix` | **KEEP** — path selection; cannot be expressed via import | (no replacement needed) |
| `vexos.btrfs.enable` | `system.nix` | **KEEP** — genuine feature toggle | (unchanged) |
| `vexos.swap.enable` | `system.nix` | **KEEP** — genuine feature toggle | (unchanged) |
| `vexos.flatpak.enable` | `flatpak.nix` | **KEEP** | (unchanged) |
| `vexos.flatpak.excludeApps` | `flatpak.nix` | **KEEP** | (unchanged) |
| `vexos.flatpak.extraApps` | `flatpak.nix` | **KEEP** — used as the mechanism for `flatpak-desktop.nix` | (unchanged) |

---

## 8. Files Modified, Files Created, Files Unchanged

### New files (5)
- `modules/system-gaming.nix`
- `modules/gpu-gaming.nix`
- `modules/branding-display.nix`
- `modules/network-desktop.nix`
- `modules/flatpak-desktop.nix`

### Modified files (8)
- `modules/system.nix` — remove 2 options + 2 mkIf blocks
- `modules/gpu.nix` — remove extraPackages32 guard + gaming optionals
- `modules/branding.nix` — remove hasDisplay option + wallpapersDir + vexosWallpapers + 3 mkIf blocks
- `modules/network.nix` — remove samba conditional
- `modules/flatpak.nix` — remove desktopOnlyApps + role conditional
- `modules/gpu/vm.nix` — replace `vexos.scx.enable = false` with `services.scx.enable = lib.mkForce false`
- `configuration-desktop.nix` — add 4 new imports; remove `vexos.system.gaming = true` + `hardware.graphics.enable32Bit = true`
- `configuration-headless-server.nix` — remove `vexos.branding.hasDisplay = false`
- `configuration-server.nix` — add `branding-display.nix` + `network-desktop.nix` imports
- `configuration-htpc.nix` — add `branding-display.nix` + `network-desktop.nix` imports
- `configuration-stateless.nix` — add `branding-display.nix` + `network-desktop.nix` imports

*(That's 10 modified files, not 8 — corrected above.)*

### Explicitly untouched files (per spec constraints)
- `modules/server/` — all server service modules
- `modules/gaming.nix`
- `modules/development.nix`
- `modules/virtualization.nix`
- `modules/asus.nix`
- `modules/impermanence.nix`
- `modules/gnome.nix` — uses retained `vexos.branding.role`; acceptable
- `modules/audio.nix`
- `modules/packages-common.nix`
- `modules/packages-desktop.nix`
- `hosts/` — all host files except `modules/gpu/vm.nix` which needs the scx fix
- `flake.nix`

---

## 9. Risks and Mitigations

### Risk 1: `branding-display.nix` + `branding.nix` both define dconf databases
**Risk**: `programs.dconf.profiles.gdm` is defined in `branding-display.nix`. If `modules/gnome.nix` or another module also sets `programs.dconf.profiles.gdm`, NixOS will throw an evaluation conflict.  
**Mitigation**: `branding.nix` already contained this block; its move to `branding-display.nix` is a 1:1 relocation. If a conflict surfaces, wrap with `lib.mkMerge` or split the databases list.

### Risk 2: `configuration-desktop.nix` removing `hardware.graphics.enable32Bit = true`
**Risk**: If `gpu-gaming.nix` is not imported (e.g. a future config copies the desktop config without knowing about the split), 32-bit GPU support silently disappears.  
**Mitigation**: The base `gpu.nix` keeps `hardware.graphics.enable32Bit = lib.mkDefault false` as the safe default. The name `gpu-gaming.nix` makes the intent obvious. Document in `gpu.nix` header that `gpu-gaming.nix` should be co-imported for gaming roles.

### Risk 3: `vexos.branding.role` path selection evaluates at Nix build time
**Risk**: If a configuration sets `vexos.branding.role` to a value for which the subdirectory doesn't exist in `files/pixmaps/`, `files/background_logos/`, `files/plymouth/`, or `wallpapers/`, `nix flake check` will succeed (path existence is not checked at evaluation) but the build will fail when copying files.  
**Mitigation**: No new roles are introduced by this refactor; the existing `[ "desktop" "htpc" "server" "stateless" ]` enum is unchanged. `headless-server` continues to reuse the `"server"` role subdirectory as before.

### Risk 4: `modules/gpu/vm.nix` must change `vexos.scx.enable` → `services.scx.enable`
**Risk**: If `gpu/vm.nix` is not updated, it will reference the removed `vexos.scx.enable` option and evaluation will fail.  
**Mitigation**: The implementation phase must update `gpu/vm.nix` as specified. This file is NOT in the do-not-touch list and the change is a straightforward single-line substitution. `nix flake check` will catch any missed reference.

### Risk 5: SCX enabled on VM via `system-gaming.nix` import
**Risk**: `configuration-desktop.nix` imports `system-gaming.nix`, which unconditionally enables SCX. `hosts/desktop-vm.nix` inherits `configuration-desktop.nix`. The VM kernel (6.6 LTS) lacks `sched_ext`, so `services.scx.enable = true` will fail.  
**Mitigation**: `modules/gpu/vm.nix` adds `services.scx.enable = lib.mkForce false`. This already runs on the VM — it just needs the option path changed from `vexos.scx.enable` to `services.scx.enable`. This is the exact purpose of the `lib.mkForce` override mechanism.

### Risk 6: `flatpak-desktop.nix` and `vexos.flatpak.extraApps` list merging
**Risk**: If any other configuration also uses `vexos.flatpak.extraApps`, values from `flatpak-desktop.nix` and that config are concatenated. This is the desired behavior but could cause unexpected installs if a non-desktop config somehow imports `flatpak-desktop.nix`.  
**Mitigation**: `flatpak-desktop.nix` is explicitly imported only by `configuration-desktop.nix`. The app IDs are clearly gaming/development tools that would be benign even if accidentally present on another role.

### Risk 7: `gnome.nix` guards (out-of-scope carveout)
**Risk**: `gnome.nix` continues to use `config.vexos.branding.role` for accent colors, extensions, and Flatpak app management. This is a retained carveout from strict Option B.  
**Mitigation**: Fully documented in §3.1. `vexos.branding.role` remains a legitimate option (path selection justifies retention). gnome.nix's role-discriminated logic is data-driven via a lookup, not a flag-gate. Future work: split gnome.nix into `gnome.nix` (base) + per-role dconf additions.

---

## 10. Implementation Checklist

The implementation subagent must complete all of the following in a single pass:

**Create (5 new files):**
- [ ] `modules/system-gaming.nix`
- [ ] `modules/gpu-gaming.nix`
- [ ] `modules/branding-display.nix`
- [ ] `modules/network-desktop.nix`
- [ ] `modules/flatpak-desktop.nix`

**Modify (10 existing files):**
- [ ] `modules/system.nix` — remove `vexos.system.gaming` + `vexos.scx.enable` options + 2 mkIf blocks
- [ ] `modules/gpu.nix` — remove extraPackages32 guard + gaming optionals
- [ ] `modules/branding.nix` — remove `vexos.branding.hasDisplay` option + wallpapersDir + vexosWallpapers + 3 mkIf blocks
- [ ] `modules/network.nix` — remove samba conditional
- [ ] `modules/flatpak.nix` — remove desktopOnlyApps + role conditional from appsToInstall
- [ ] `modules/gpu/vm.nix` — `vexos.scx.enable = false` → `services.scx.enable = lib.mkForce false`
- [ ] `configuration-desktop.nix` — add 4 imports; remove `vexos.system.gaming` + `hardware.graphics.enable32Bit` from body
- [ ] `configuration-headless-server.nix` — remove `vexos.branding.hasDisplay = false` from body
- [ ] `configuration-server.nix` — add `branding-display.nix` + `network-desktop.nix` to imports
- [ ] `configuration-htpc.nix` — add `branding-display.nix` + `network-desktop.nix` to imports
- [ ] `configuration-stateless.nix` — add `branding-display.nix` + `network-desktop.nix` to imports

**Validate:**
- [ ] `nix flake check` passes
- [ ] `sudo nixos-rebuild dry-build --flake .#vexos-desktop-amd` succeeds
- [ ] `sudo nixos-rebuild dry-build --flake .#vexos-desktop-nvidia` succeeds
- [ ] `sudo nixos-rebuild dry-build --flake .#vexos-desktop-vm` succeeds
- [ ] No reference to `vexos.system.gaming` remains in any module
- [ ] No reference to `vexos.scx.enable` remains in any module
- [ ] No reference to `vexos.branding.hasDisplay` remains in any module
- [ ] `lib.mkIf` blocks gating on role/gaming/display flags are gone from all shared modules
