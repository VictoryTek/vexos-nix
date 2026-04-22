# Headless Server Role — Implementation Specification

**Project:** vexos-nix  
**Date:** 2026-04-22  
**Status:** DRAFT — Ready for Implementation

---

## 1. Current State Analysis

### 1.1 GUI Server Role (`configuration-server.nix`)

`configuration-server.nix` imports the following modules:

| Module | Purpose |
|--------|---------|
| `./modules/gnome.nix` | Full GNOME desktop: GDM, Wayland compositor, GNOME Shell, XDG portals, dconf, GNOME Shell extensions, display manager |
| `./modules/audio.nix` | PipeWire + WirePlumber audio stack (ALSA/PulseAudio/JACK compat, Bluetooth codecs, rtkit real-time scheduling) |
| `./modules/gpu.nix` | Hardware graphics base: `hardware.graphics`, VA-API/VDPAU, Vulkan tools, ffmpeg |
| `./modules/branding.nix` | OS identity (distroName, distroId, os-release), Plymouth boot splash, pixmaps logos, GDM login logo |
| `./modules/flatpak.nix` | Flatpak daemon + first-boot app installer (installs GUI apps from Flathub) |
| `./modules/network.nix` | SSH, NetworkManager, Tailscale, Avahi/mDNS, firewall, systemd-resolved, SMB client |
| `./modules/packages.nix` | Base system packages: brave, just, btop, inxi, git, curl, wget |
| `./modules/system.nix` | Kernel, boot params, ZRAM, SCX scheduler, swap, btrfs, performance tunables |
| `./modules/server/` | Umbrella import for all optional server service modules (`vexos.server.*.enable`) |

In addition, the GUI server role in `flake.nix` uses `serverModules` which wires in:
- `minimalModules` (hardware-config, unstableOverlay, Up app)
- `serverHomeManagerModule` (imports `home-server.nix`)
- `serverServicesModule` (conditionally loads `/etc/nixos/server-services.nix`)

### 1.2 `home-server.nix`

`home-server.nix` provides the Home Manager configuration for the GUI server role. It includes:

| Section | Content |
|---------|---------|
| Imports | `./home/gnome-common.nix` — GTK theming, Bibata cursors, kora icon theme, GNOME dconf base |
| `home.packages` | ghostty (GUI terminal), tree, ripgrep, fd, bat, eza, fzf, wl-clipboard (Wayland), fastfetch, blivet-gui (GUI disk manager) |
| `programs.bash` | Shell config + aliases |
| `programs.starship` | Prompt + config file |
| `programs.tmux` | Terminal multiplexer |
| `home.file` | justfile, template/server-services.nix |
| `xdg.desktopEntries` | Hides GNOME app grid entries (Extensions, xterm, uxterm) |
| `home.sessionVariables` | `NIXOS_OZONE_WL`, `MOZ_ENABLE_WAYLAND`, `QT_QPA_PLATFORM` — Wayland hints |
| `home.file` (wallpapers) | Copies wallpaper JXL files into `~/Pictures/Wallpapers/` |
| `dconf.settings` | Full GNOME shell config: enabled-extensions, favorite-apps, app-folders, accent color, wallpaper |

### 1.3 Existing Host Files

The GUI server host files (`hosts/server-{amd,nvidia,intel,vm}.nix`) each:
- Import `../configuration-server.nix` + their GPU module
- Set `virtualisation.virtualbox.guest.enable = lib.mkForce false` (bare-metal variants)
- Override `system.nixos.distroName` (e.g. `"VexOS Server AMD"`)
- The VM variant sets `networking.hostName` instead

### 1.4 Existing flake.nix Outputs

The flake currently defines:
- `nixosConfigurations.vexos-server-{amd,nvidia,intel,vm}` using `serverModules`
- `nixosModules.serverBase` — reusable module for the GUI server stack
- `serverModules` = `minimalModules ++ [ serverHomeManagerModule ] ++ serverServicesModule`

---

## 2. Problem Definition

The GUI server role (`configuration-server.nix`) imports `modules/gnome.nix`, `modules/audio.nix`, and `modules/flatpak.nix`. These pull in:

- **GNOME desktop stack** — GDM display manager, Wayland compositor (mutter), GNOME Shell, GNOME session, GNOME settings daemon, XDG portal, GNOME Shell extensions, bibata-cursors, kora-icon-theme, and a dconf system database
- **PipeWire audio stack** — pipewire, wireplumber, ALSA/PulseAudio/JACK compatibility layers, rtkit real-time scheduling, Bluetooth audio codecs
- **Flatpak infrastructure** — Flatpak daemon, Flathub remote, first-boot installer (installs ~18 GUI apps including browsers, office suite, extension managers)
- **Home Manager GNOME config** — GTK theming, cursor/icon theme packages, dconf settings, Wayland environment variables, wallpaper files, GNOME app-folder configuration

On a **headless server** — accessed exclusively via SSH, no physical display, no monitor — all of the above is unnecessary and increases:
- System closure size (GNOME stack + Flatpak runtimes = several GiB)
- Attack surface (GDM listens on VT7; PipeWire adds socket/service exposure)
- Boot time (GDM waits for display; Flatpak services start at login)
- Maintenance overhead (GNOME and Flatpak updates unrelated to server workloads)

A headless server role should provide only: SSH access, networking (including Tailscale), hardware GPU drivers (for transcoding services), optional server services, system utilities, and a clean shell environment.

---

## 3. Proposed Solution Architecture

### 3.1 Overview

Create a new `headless-server` role by:

1. Deriving `configuration-headless-server.nix` from `configuration-server.nix` — removing the three DE modules and adding headless-appropriate overrides.
2. Deriving `home-headless-server.nix` from `home-server.nix` — removing all GNOME/Wayland-specific sections.
3. Adding four host files in `hosts/` (`headless-server-{amd,nvidia,intel,vm}.nix`).
4. Adding `headlessServerModules` + `headlessServerHomeManagerModule` in `flake.nix`.
5. Adding four `nixosConfigurations.vexos-headless-server-*` outputs in `flake.nix`.
6. Adding a `nixosModules.headlessServerBase` reusable module in `flake.nix`.
7. Updating `justfile` switch recipe to include `headless-server` as option 5.
8. Updating `scripts/preflight.sh` CHECK 2 to cover all server and headless-server variants.

### 3.2 Naming Conventions

- Configuration file: `configuration-headless-server.nix` (matches `configuration-{role}.nix` pattern)
- Home file: `home-headless-server.nix` (matches `home-{role}.nix` pattern)
- Host files: `hosts/headless-server-{amd,nvidia,intel,vm}.nix` (matches `hosts/{role}-{variant}.nix` pattern)
- Flake outputs: `vexos-headless-server-{amd,nvidia,intel,vm}` (matches `vexos-{role}-{variant}` pattern)
- flake.nix module set: `headlessServerModules` (matches `serverModules`, `htpcModules` pattern)
- flake.nix HM module: `headlessServerHomeManagerModule` (matches `serverHomeManagerModule` pattern)
- nixosModule key: `headlessServerBase` (matches `serverBase`, `htpcBase` pattern)
- Branding role: `"server"` (reuse existing enum value — no new branding assets needed)
- distroName: `"VexOS Headless Server"` / `"VexOS Headless Server AMD"` etc.

**Do NOT** add `"headless-server"` to `modules/branding.nix`'s `vexos.branding.role` enum — the `"server"` role already has all required branding assets in `files/pixmaps/server/`, `files/background_logos/server/`, `files/plymouth/server/`, and `wallpapers/server/`. The `system.nixos.distroName` override is sufficient to distinguish the two roles in boot menus and `hostnamectl`.

---

## 4. Include vs. Exclude Table

### 4.1 System Modules (`configuration-headless-server.nix`)

| Module / Option | GUI Server | Headless Server | Reason |
|-----------------|-----------|-----------------|--------|
| `modules/gnome.nix` | ✅ | ❌ Excluded | Entire GNOME desktop stack — GDM, Wayland, GNOME Shell, XDG portals |
| `modules/audio.nix` | ✅ | ❌ Excluded | PipeWire audio — no audio device or graphical session on headless server |
| `modules/flatpak.nix` | ✅ | ❌ Excluded | GUI application installer — no graphical apps needed on a headless server |
| `modules/gpu.nix` | ✅ | ✅ Included | VA-API / hardware transcoding support — used by Jellyfin, Plex, etc. |
| `modules/branding.nix` | ✅ | ✅ Included | OS identity (distroName, os-release, Plymouth theme) — still meaningful headless |
| `modules/network.nix` | ✅ | ✅ Included | SSH, NetworkManager, Tailscale, firewall — essential for any server |
| `modules/packages.nix` | ✅ | ✅ Included | System utilities (btop, git, curl, wget, just) — all applicable headless |
| `modules/system.nix` | ✅ | ✅ Included (overrides) | Kernel, ZRAM, swap, btrfs — core system config; override SCX and Plymouth |
| `modules/server/` | ✅ | ✅ Included | All optional server service modules — reason for the role's existence |
| `serverServicesModule` | ✅ | ✅ Included | `/etc/nixos/server-services.nix` opt-in — shared with GUI server |
| `boot.plymouth.enable` | `true` (via system.nix) | `lib.mkForce false` | No graphical display — Plymouth serves no purpose headless |
| `hardware.graphics.enable32Bit` | `true` (via gpu.nix) | `lib.mkForce false` | No Steam/Proton 32-bit on a server |
| `vexos.scx.enable` | `true` (default) | `false` | `scx_lavd` is a gaming CPU scheduler — not appropriate for server workloads |
| `vexos.branding.role` | `"server"` | `"server"` | Reuse existing server branding assets |
| `system.nixos.distroName` | `"VexOS Server"` (mkOverride 500) | `"VexOS Headless Server"` (mkOverride 500) | Distinguish from GUI server in boot menus and hostnamectl |
| `nixpkgs.config.allowUnfree` | ✅ | ✅ | Required for NVIDIA proprietary drivers via gpu/nvidia.nix |

### 4.2 Home Manager (`home-headless-server.nix`)

| Section | GUI Server | Headless Server | Reason |
|---------|-----------|-----------------|--------|
| `imports = [ ./home/gnome-common.nix ]` | ✅ | ❌ Excluded | GTK theming, Bibata cursors, kora icons, GNOME dconf — no GNOME headless |
| `home.packages: ghostty` | ✅ | ❌ Excluded | GUI terminal emulator — requires a graphical session |
| `home.packages: wl-clipboard` | ✅ | ❌ Excluded | Wayland clipboard CLI — no Wayland compositor headless |
| `home.packages: blivet-gui` | ✅ | ❌ Excluded | GUI disk partitioning tool — requires graphical session |
| `home.packages: tree, ripgrep, fd, bat, eza, fzf` | ✅ | ✅ Included | CLI utilities — all applicable over SSH |
| `home.packages: fastfetch` | ✅ | ✅ Included | Terminal system info — useful headless |
| `programs.bash` | ✅ | ✅ Included | Shell config and aliases — essential |
| `programs.starship` | ✅ | ✅ Included | Shell prompt — useful headless |
| `programs.tmux` | ✅ | ✅ Included | Terminal multiplexer — especially important for SSH sessions |
| `home.file: justfile` | ✅ | ✅ Included | Build tooling |
| `home.file: template/server-services.nix` | ✅ | ✅ Included | Service toggle template — shared with GUI server |
| `xdg.desktopEntries` | ✅ | ❌ Excluded | GNOME app-grid entry masking — no GNOME headless |
| `home.sessionVariables` (Wayland vars) | ✅ | ❌ Excluded | `NIXOS_OZONE_WL`, `MOZ_ENABLE_WAYLAND`, `QT_QPA_PLATFORM` — no Wayland headless |
| `home.file: wallpapers` | ✅ | ❌ Excluded | Desktop background images — no GNOME desktop headless |
| `dconf.settings` | ✅ | ❌ Excluded | Full GNOME configuration block — no GNOME headless |

---

## 5. Exact File Contents

### 5.1 `configuration-headless-server.nix` (new file at repo root)

```nix
{ config, pkgs, lib, ... }:

{
  imports = [
    ./modules/gpu.nix
    ./modules/branding.nix
    ./modules/network.nix
    ./modules/packages.nix
    ./modules/system.nix
    ./modules/server       # Optional server services (vexos.server.*.enable)
  ];

  # ---------- Hostname ----------
  networking.hostName = lib.mkDefault "vexos";

  # ---------- Time / Locale ----------
  time.timeZone = "America/Chicago";
  i18n.defaultLocale = "en_US.UTF-8";

  # ---------- Branding ----------
  # Reuse the "server" role to pick up existing server/ branding assets
  # (pixmaps, background logos, Plymouth watermark, wallpapers).
  # Override distroName to distinguish from the GUI server role.
  vexos.branding.role = "server";
  system.nixos.distroName = lib.mkOverride 500 "VexOS Headless Server";

  # ---------- Headless overrides ----------
  # No graphical boot splash on a headless system (system.nix enables Plymouth
  # unconditionally; lib.mkForce overrides it here).
  boot.plymouth.enable = lib.mkForce false;

  # Disable 32-bit graphics support (no Steam/Proton on a headless server;
  # gpu.nix sets enable32Bit = true for desktop gaming use).
  hardware.graphics.enable32Bit = lib.mkForce false;

  # Disable the SCX LAVD gaming CPU scheduler — scx_lavd is tuned for
  # low-latency desktop/gaming workloads; a throughput-oriented server
  # should use the kernel's default CFS scheduler.
  vexos.scx.enable = false;

  # ---------- Users ----------
  users.users.nimda = {
    isNormalUser = true;
    description  = "nimda";
    extraGroups  = [
      "wheel"
      "networkmanager"
    ];
  };

  # ---------- Nix settings ----------
  nix.settings = {
    experimental-features = [ "nix-command" "flakes" ];
    trusted-users         = [ "root" "@wheel" ];
    auto-optimise-store   = true;
    substituters = [
      "https://cache.nixos.org"
    ];
    trusted-public-keys = [
      "cache.nixos.org-1:6NCHdD59X431o0gWypbMrAURkbJ16ZPMQFGspcDShjY="
    ];
    max-jobs    = 1;
    cores       = 0;
    min-free    = 1073741824;   # 1 GiB
    max-free    = 5368709120;   # 5 GiB

    download-buffer-size = 524288000; # 500 MiB

    keep-outputs     = false;
    keep-derivations = false;
  };

  nix.daemonCPUSchedPolicy = "idle";
  nix.daemonIOSchedClass   = "idle";

  nix.gc = {
    automatic = true;
    dates     = "weekly";
    options   = "--delete-older-than 7d";
  };

  nix.optimise = {
    automatic = true;
    dates     = [ "weekly" ];
  };

  # ---------- Nixpkgs ----------
  # allowUnfree required for NVIDIA proprietary drivers via modules/gpu/nvidia.nix.
  nixpkgs.config.allowUnfree = true;

  # ---------- State version ----------
  # Set once at install time — do not change after initial deployment.
  system.stateVersion = "25.11";
}
```

### 5.2 `home-headless-server.nix` (new file at repo root)

```nix
# home-headless-server.nix
# Home Manager configuration for user "nimda" — Headless Server role.
# Shell environment and sysadmin utilities only.
# No GNOME, no Wayland, no GUI apps — accessed exclusively via SSH.
{ config, pkgs, lib, inputs, ... }:
{
  home.username    = "nimda";
  home.homeDirectory = "/home/nimda";

  # ── User packages ──────────────────────────────────────────────────────────
  home.packages = with pkgs; [
    # Terminal utilities
    tree
    ripgrep
    fd
    bat
    eza
    fzf
    # NOTE: just is installed system-wide via modules/packages.nix.

    # System utilities
    fastfetch
    # NOTE: btop and inxi are installed system-wide via modules/packages.nix.
  ];

  # ── Shell ──────────────────────────────────────────────────────────────────
  programs.bash = {
    enable = true;
    shellAliases = {
      ll   = "ls -la";
      ".." = "cd ..";

      # Tailscale shortcuts
      ts   = "tailscale";
      tss  = "tailscale status";
      tsip = "tailscale ip";

      # System service shortcuts
      sshstatus = "systemctl status sshd";
      smbstatus = "systemctl status smbd";
    };
  };

  # ── Starship prompt ────────────────────────────────────────────────────────
  programs.starship = {
    enable = true;
    enableBashIntegration = true;
  };

  xdg.configFile."starship.toml".source = ./files/starship.toml;

  # ── Tmux terminal multiplexer ──────────────────────────────────────────────
  # Essential for persistent SSH sessions: detach and reattach without losing work.
  programs.tmux = {
    enable       = true;
    mouse        = true;
    terminal     = "tmux-256color";
    prefix       = "C-a";
    baseIndex    = 1;
    escapeTime   = 0;
    historyLimit = 10000;
    keyMode      = "vi";
  };

  # ── Justfile ───────────────────────────────────────────────────────────────
  home.file."justfile".source = ./justfile;
  home.file."template/server-services.nix".source = ./template/server-services.nix;

  home.stateVersion = "24.05";
}
```

### 5.3 `hosts/headless-server-amd.nix` (new file)

```nix
# hosts/headless-server-amd.nix
# vexos — Headless Server AMD GPU build.
# Rebuild: sudo nixos-rebuild switch --flake .#vexos-headless-server-amd
{ lib, ... }:
{
  imports = [
    ../configuration-headless-server.nix
    ../modules/gpu/amd.nix
  ];

  virtualisation.virtualbox.guest.enable = lib.mkForce false;
  system.nixos.distroName = "VexOS Headless Server AMD";
}
```

### 5.4 `hosts/headless-server-nvidia.nix` (new file)

```nix
# hosts/headless-server-nvidia.nix
# vexos — Headless Server NVIDIA GPU build.
# Rebuild: sudo nixos-rebuild switch --flake .#vexos-headless-server-nvidia
{ lib, ... }:
{
  imports = [
    ../configuration-headless-server.nix
    ../modules/gpu/nvidia.nix
  ];

  virtualisation.virtualbox.guest.enable = lib.mkForce false;
  system.nixos.distroName = "VexOS Headless Server NVIDIA";
}
```

### 5.5 `hosts/headless-server-intel.nix` (new file)

```nix
# hosts/headless-server-intel.nix
# vexos — Headless Server Intel GPU build (integrated iGPU or Arc A-series discrete).
# Rebuild: sudo nixos-rebuild switch --flake .#vexos-headless-server-intel
{ lib, ... }:
{
  imports = [
    ../configuration-headless-server.nix
    ../modules/gpu/intel.nix
  ];

  virtualisation.virtualbox.guest.enable = lib.mkForce false;
  system.nixos.distroName = "VexOS Headless Server Intel";
}
```

### 5.6 `hosts/headless-server-vm.nix` (new file)

```nix
# hosts/headless-server-vm.nix
# vexos — Headless Server VM guest build (QEMU/KVM + VirtualBox).
# Rebuild: sudo nixos-rebuild switch --flake .#vexos-headless-server-vm
{ lib, ... }:
{
  imports = [
    ../configuration-headless-server.nix
    ../modules/gpu/vm.nix
  ];

  networking.hostName = lib.mkDefault "vexos";

  system.nixos.distroName = "VexOS Headless Server VM";
}
```

---

## 6. `flake.nix` Changes

All changes are **additions only** — no existing lines are modified or removed.

### 6.1 Add `headlessServerHomeManagerModule` and `headlessServerModules` in the `let` block

**Insert location:** After the `serverModules` definition (approximately after `serverModules = minimalModules ++ [ serverHomeManagerModule ] ++ serverServicesModule;`), before the closing `in`.

```nix
    # Home Manager: Headless Server-specific user environment (shell tools only, no GNOME).
    headlessServerHomeManagerModule = {
      imports = [ home-manager.nixosModules.home-manager ];
      home-manager = {
        useGlobalPkgs    = true;
        useUserPackages  = true;
        extraSpecialArgs = { inherit inputs; };
        users.nimda      = import ./home-headless-server.nix;
        backupFileExtension = "backup";
      };
    };

    # Modules for headless server role — minimal + headless-server-specific home-manager.
    # Reuses serverServicesModule so /etc/nixos/server-services.nix opt-in services
    # work identically on both the GUI server and headless server roles.
    headlessServerModules = minimalModules ++ [ headlessServerHomeManagerModule ] ++ serverServicesModule;
```

### 6.2 Add four `nixosConfigurations` outputs

**Insert location:** After the `vexos-server-vm` nixosConfiguration block (after the Server VM build comment block), before the HTPC AMD build comment.

```nix
    # ── Headless Server AMD build ──────────────────────────────────────────────
    # sudo nixos-rebuild switch --flake .#vexos-headless-server-amd
    nixosConfigurations.vexos-headless-server-amd = nixpkgs.lib.nixosSystem {
      inherit system;
      modules = headlessServerModules ++ [ ./hosts/headless-server-amd.nix ];
      specialArgs = { inherit inputs; };
    };

    # ── Headless Server NVIDIA build ───────────────────────────────────────────
    # sudo nixos-rebuild switch --flake .#vexos-headless-server-nvidia
    nixosConfigurations.vexos-headless-server-nvidia = nixpkgs.lib.nixosSystem {
      inherit system;
      modules = headlessServerModules ++ [ ./hosts/headless-server-nvidia.nix ];
      specialArgs = { inherit inputs; };
    };

    # ── Headless Server Intel build ────────────────────────────────────────────
    # sudo nixos-rebuild switch --flake .#vexos-headless-server-intel
    nixosConfigurations.vexos-headless-server-intel = nixpkgs.lib.nixosSystem {
      inherit system;
      modules = headlessServerModules ++ [ ./hosts/headless-server-intel.nix ];
      specialArgs = { inherit inputs; };
    };

    # ── Headless Server VM build ───────────────────────────────────────────────
    # sudo nixos-rebuild switch --flake .#vexos-headless-server-vm
    nixosConfigurations.vexos-headless-server-vm = nixpkgs.lib.nixosSystem {
      inherit system;
      modules = headlessServerModules ++ [ ./hosts/headless-server-vm.nix ];
      specialArgs = { inherit inputs; };
    };
```

### 6.3 Add `headlessServerBase` to `nixosModules`

**Insert location:** After the `serverBase` entry in the `nixosModules` attrset.

```nix
      # Headless server stack: no GUI, no audio, no Flatpak.
      # Suitable for production servers accessed via SSH.
      headlessServerBase = { ... }: {
        imports = [
          home-manager.nixosModules.home-manager
          ./configuration-headless-server.nix
        ];
        home-manager = {
          useGlobalPkgs    = true;
          useUserPackages  = true;
          extraSpecialArgs = { inherit inputs; };
          users.nimda      = import ./home-headless-server.nix;
          backupFileExtension = "backup";
        };
        nixpkgs.overlays = [
          (final: prev: {
            unstable = import nixpkgs-unstable {
              inherit (final) config;
              inherit (final.stdenv.hostPlatform) system;
            };
          })
        ];
        environment.systemPackages = [ up.packages.x86_64-linux.default ];
      };
```

---

## 7. `justfile` Changes

The `switch` recipe's interactive menu must be extended to offer `headless-server` as option 5.

### 7.1 Update role selection menu (in `switch` recipe)

**Old:**
```bash
    echo "  1) desktop"
    echo "  2) stateless"
    echo "  3) htpc"
    echo "  4) server"
    echo ""
    while [ -z "$ROLE" ]; do
        printf "Choice [1-4] or name: "
        read -r INPUT
        case "${INPUT,,}" in
            1|desktop) ROLE="desktop" ;;
            2|stateless) ROLE="stateless" ;;
            3|htpc)    ROLE="htpc"    ;;
            4|server)  ROLE="server"  ;;
            *) echo "Invalid — enter 1-4 or desktop/stateless/htpc/server" ;;
        esac
    done
```

**New:**
```bash
    echo "  1) desktop"
    echo "  2) stateless"
    echo "  3) htpc"
    echo "  4) server"
    echo "  5) headless-server"
    echo ""
    while [ -z "$ROLE" ]; do
        printf "Choice [1-5] or name: "
        read -r INPUT
        case "${INPUT,,}" in
            1|desktop)         ROLE="desktop"         ;;
            2|stateless)       ROLE="stateless"       ;;
            3|htpc)            ROLE="htpc"            ;;
            4|server)          ROLE="server"          ;;
            5|headless-server) ROLE="headless-server" ;;
            *) echo "Invalid — enter 1-5 or desktop/stateless/htpc/server/headless-server" ;;
        esac
    done
```

No changes are required to the `default` recipe — its `[[ "$variant" == *server* ]]` test already matches `headless-server` variants because the string "server" appears in "headless-server".

No changes are required to the `build` recipe — it accepts `role` and `variant` as positional arguments and constructs `vexos-${role}-${variant}`, so `just build headless-server amd` works without modification.

---

## 8. `scripts/preflight.sh` Changes

The preflight script's **CHECK 2** currently only dry-builds `vexos-desktop-*` and `vexos-stateless-*` variants. It does not test any server (GUI or headless) variants.

### 8.1 Add server and headless-server targets to CHECK 2

**Find the `for TARGET in` loop in CHECK 2** and extend the target list:

**Old:**
```bash
  for TARGET in vexos-desktop-amd vexos-desktop-nvidia vexos-desktop-vm vexos-desktop-intel vexos-stateless-amd vexos-stateless-nvidia vexos-stateless-intel vexos-stateless-vm; do
```

**New:**
```bash
  for TARGET in \
    vexos-desktop-amd vexos-desktop-nvidia vexos-desktop-vm vexos-desktop-intel \
    vexos-stateless-amd vexos-stateless-nvidia vexos-stateless-intel vexos-stateless-vm \
    vexos-server-amd vexos-server-nvidia vexos-server-vm \
    vexos-headless-server-amd vexos-headless-server-nvidia vexos-headless-server-vm; do
```

> **Note:** Intel variants for server and headless-server are excluded from the default preflight run because `modules/gpu/intel.nix` pulls in `intel-compute-runtime` (a large derivation) and server hardware rarely uses Intel dGPUs. They can be added when needed or tested on demand with `just build headless-server intel`.

The same change must be applied to the `nix build --dry-run` fallback loop immediately below (the one that executes when `nixos-rebuild` is not available).

---

## 9. Risks and Mitigations

| Risk | Severity | Mitigation |
|------|----------|------------|
| `modules/branding.nix` sets `programs.dconf.profiles.gdm` — this configures a dconf profile for GDM even though GDM is not installed in the headless role | Low | Harmless: NixOS creates the dconf profile file but GDM never starts, so the profile is never loaded. No evaluation error. |
| `modules/branding.nix` sets `boot.plymouth.logo` and `boot.plymouth.theme` even though Plymouth is disabled via `lib.mkForce false` | Low | Harmless: NixOS evaluates but does not activate Plymouth when `enable = false`. Setting `theme` and `logo` on a disabled Plymouth daemon produces no error and no effect. |
| `modules/gpu/nvidia.nix` sets `services.xserver.videoDrivers = [ "nvidia" ]` — this references X server config even though no display manager is enabled | Low | Correct and required: NixOS uses `xserver.videoDrivers` to select the DRM/KMS kernel module regardless of whether X11 is running. NVIDIA needs this for KMS, Wayland (if ever enabled), and `nvidia-smi` to function. |
| `modules/gpu.nix` installs Vulkan tools and mesa-demos which are display-oriented | Low | These are small packages. `vulkaninfo` and `vainfo` are actually useful for diagnosing GPU transcoding issues on a headless server. Acceptable overhead. |
| `vexos.branding.role = "server"` is shared with the GUI server role — if branding.nix adds role-specific logic for `"server"` in the future, it will affect both roles | Medium | Document the shared role in code comments. If role-specific divergence becomes necessary, add `"headless-server"` to the `branding.nix` enum at that time and create `files/pixmaps/headless-server/` etc. as copies of the server assets. |
| `home-headless-server.nix` does not set `home.sessionVariables` with Wayland hints | None | Correct: there is no Wayland compositor on a headless server. SSH sessions use the terminal emulator on the *client*, not the server. |
| New variants not tested in preflight before this spec is implemented | Medium | The preflight.sh change in Section 8 must be implemented as part of this feature. Do not mark the task complete until `nix flake check` and dry-builds for all new variants pass. |
| `serverServicesModule` is shared — `/etc/nixos/server-services.nix` enables services for both GUI server and headless server | Intentional | The service modules themselves (Jellyfin, Nextcloud, etc.) are DE-agnostic and work identically headless. Sharing the toggle file is correct. If different service sets are needed per role, the operator can use two separate service files by overriding `serverServicesModule` in the host file. |

---

## 10. Summary of New Files

| File | Action | Based On |
|------|--------|----------|
| `configuration-headless-server.nix` | Create | `configuration-server.nix` minus gnome/audio/flatpak, plus headless overrides |
| `home-headless-server.nix` | Create | `home-server.nix` minus GNOME/Wayland/GUI sections |
| `hosts/headless-server-amd.nix` | Create | `hosts/server-amd.nix` pattern |
| `hosts/headless-server-nvidia.nix` | Create | `hosts/server-nvidia.nix` pattern |
| `hosts/headless-server-intel.nix` | Create | `hosts/server-intel.nix` pattern |
| `hosts/headless-server-vm.nix` | Create | `hosts/server-vm.nix` pattern |
| `flake.nix` | Modify (additions only) | New let-bindings, 4 nixosConfigurations, 1 nixosModule |
| `justfile` | Modify (switch recipe) | Add option 5 and case for `headless-server` |
| `scripts/preflight.sh` | Modify (CHECK 2 targets) | Add server + headless-server dry-build targets |

**Total new files:** 6  
**Modified files:** 3 (`flake.nix`, `justfile`, `scripts/preflight.sh`)  
**No changes to:** `modules/branding.nix`, `modules/system.nix`, `modules/gpu/*.nix`, `modules/network.nix`, `modules/packages.nix`, `modules/server/*`, `home/gnome-common.nix`
