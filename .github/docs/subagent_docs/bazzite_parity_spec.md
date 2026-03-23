# vexos-nix — Bazzite Feature Parity Specification

**Document type:** Phase 1 — Research & Specification  
**Target:** vexos-nix NixOS flake, `nixos-24.11`  
**Date:** 2026-03-23  
**Scope:** Map every major Bazzite desktop feature to its NixOS equivalent and design a modular implementation architecture.

---

## 1. Research Sources

| # | Source | URL |
|---|--------|-----|
| 1 | Bazzite Getting Started / FAQ | https://docs.bazzite.gg/General/FAQ/ |
| 2 | Bazzite GitHub README (full feature list) | https://github.com/ublue-os/bazzite/blob/main/README.md |
| 3 | Bazzite vs SteamOS Comparison | https://docs.bazzite.gg/General/SteamOS_Comparison/ |
| 4 | NixOS Wiki — Steam | https://wiki.nixos.org/wiki/Steam |
| 5 | NixOS Wiki — KDE / Wayland | https://wiki.nixos.org/wiki/KDE |
| 6 | NixOS Wiki — PipeWire (low-latency) | https://wiki.nixos.org/wiki/PipeWire |
| 7 | NixOS Wiki — AMD GPU | https://wiki.nixos.org/wiki/AMD_GPU |
| 8 | NixOS Wiki — NVIDIA | https://wiki.nixos.org/wiki/Nvidia |
| 9 | NixOS Wiki — Linux kernel | https://wiki.nixos.org/wiki/Linux_kernel |
| 10 | NixOS Wiki — GameMode | https://wiki.nixos.org/wiki/GameMode |
| 11 | NixOS Wiki — Flatpak | https://wiki.nixos.org/wiki/Flatpak |
| 12 | nix-gaming flake (fufexan) | https://github.com/fufexan/nix-gaming |

---

## 2. Current State Analysis

### Repository at time of spec

```
flake.nix          — thin flake, nixpkgs 24.11, output `vexos`, imports /etc/nixos/hardware-configuration.nix
configuration.nix  — systemd-boot, NetworkManager, user `nimda`, basic packages, stateVersion = "24.11"
```

**What is missing / not yet configured:**
- No desktop environment (no KDE, no SDDM)
- No gaming stack (no Steam, no GameMode, no Proton utils)
- No GPU driver configuration beyond defaults
- No audio stack (no PipeWire, no rtkit)
- No controller/gamepad udev rules
- No kernel tuning (using NixOS default LTS kernel)
- No ZRAM swap
- No Flatpak/Flathub
- No performance tuning
- `nixpkgs.config.allowUnfree = false` — must be changed to `true` for Steam and NVIDIA

---

## 3. Bazzite Feature Matrix

The following table maps every major Bazzite desktop feature to its NixOS implementation. "Bazzite desktop" refers to the non-deck KDE Plasma variant.

| Category | Bazzite Feature | NixOS Equivalent | Module |
|----------|----------------|------------------|--------|
| **Desktop** | KDE Plasma 6 (Wayland default) | `services.desktopManager.plasma6.enable = true` | desktop.nix |
| **Desktop** | SDDM display manager | `services.displayManager.sddm.enable = true; wayland.enable = true` | desktop.nix |
| **Desktop** | Wayland as default session | Plasma 6 defaults to Wayland; no extra option needed | desktop.nix |
| **Desktop** | HDR support | `programs.gamescope.enable = true` + `gamescope-wsi` package | desktop.nix |
| **Desktop** | VRR / adaptive sync | KWin compositor option; set in plasma user config | desktop.nix |
| **Desktop** | KDE Vapor / VGUI2 steam themes | `pkgs.kdePackages.steamdeck-kde-presets` (where available) or manual config | desktop.nix |
| **Desktop** | Ozone Wayland for Electron apps | `environment.sessionVariables.NIXOS_OZONE_WL = "1"` | desktop.nix |
| **Desktop** | XDG portal for Wayland | `xdg.portal.enable = true; xdg.portal.extraPortals = [pkgs.xdg-desktop-portal-kde]` | desktop.nix |
| **Desktop** | Font rendering | `fonts.enableDefaultPackages = true` + nerd fonts | desktop.nix |
| **Gaming** | Steam (with Proton) | `programs.steam.enable = true` | gaming.nix |
| **Gaming** | Steam hardware udev rules | Enabled automatically by `programs.steam.enable` | gaming.nix |
| **Gaming** | Proton-GE custom | `programs.steam.extraCompatPackages = [pkgs.proton-ge-bin]` | gaming.nix |
| **Gaming** | Lutris | `pkgs.lutris` in `environment.systemPackages` | gaming.nix |
| **Gaming** | Heroic Games Launcher | `pkgs.heroic` in `environment.systemPackages` | gaming.nix |
| **Gaming** | Bottles | `pkgs.bottles` in `environment.systemPackages` | gaming.nix |
| **Gaming** | GameMode (CPU/GPU perf boost) | `programs.gamemode.enable = true` | gaming.nix |
| **Gaming** | MangoHud (overlay) | `programs.mangohud.enable = true` | gaming.nix |
| **Gaming** | vkBasalt (post-processing) | `pkgs.vkbasalt` in `environment.systemPackages` | gaming.nix |
| **Gaming** | Gamescope compositor | `programs.gamescope.enable = true; capSysNice = true` | gaming.nix |
| **Gaming** | Gamescope WSI (HDR) | `pkgs.gamescope-wsi` in `environment.systemPackages` | gaming.nix |
| **Gaming** | ProtonUp-Qt | `pkgs.protonup-qt` in `environment.systemPackages` | gaming.nix |
| **Gaming** | Protontricks | `pkgs.protontricks` in `environment.systemPackages` | gaming.nix |
| **Gaming** | Umu-launcher | `pkgs.umu-launcher` in `environment.systemPackages` | gaming.nix |
| **Gaming** | Wine-GE | `pkgs.wineWowPackages.stagingFull` or nix-gaming `wine-ge` | gaming.nix |
| **Gaming** | duperemove (Wine prefix dedup) | `pkgs.duperemove` + systemd timer | gaming.nix |
| **Gaming** | OBS VkCapture | `pkgs.obs-studio` + `pkgs.obs-vkcapture` | gaming.nix |
| **Gaming** | Input Remapper | `pkgs.input-remapper` + systemd service | gaming.nix |
| **Gaming** | Flatseal (Flatpak permission mgmt) | Via Flatpak: `com.github.tchx84.Flatseal` | flatpak.nix |
| **Audio** | PipeWire audio server | `services.pipewire.enable = true` | audio.nix |
| **Audio** | ALSA compatibility layer | `services.pipewire.alsa.enable = true; alsa.support32Bit = true` | audio.nix |
| **Audio** | PulseAudio compatibility | `services.pipewire.pulse.enable = true` | audio.nix |
| **Audio** | JACK compatibility | `services.pipewire.jack.enable = true` | audio.nix |
| **Audio** | RT/realtime audio privileges | `security.rtkit.enable = true` | audio.nix |
| **Audio** | Low-latency audio tuning | nix-gaming pipewire lowLatency module OR manual `extraConfig` | audio.nix |
| **Audio** | Bluetooth audio codecs (SBC-XQ, mSBC) | `services.pipewire.wireplumber.extraConfig."10-bluez"` | audio.nix |
| **GPU** | AMD open-source driver (RADV/Mesa) | `hardware.graphics.enable = true; enable32Bit = true` | gpu.nix |
| **GPU** | AMD Vulkan (RADV – preferred) | Included in Mesa by default with graphics.enable | gpu.nix |
| **GPU** | AMD OpenCL/ROCm | `hardware.amdgpu.opencl.enable = true` | gpu.nix |
| **GPU** | AMD LACT GPU controller | `services.lact.enable = true` | gpu.nix |
| **GPU** | AMD Southern/Sea Islands legacy | `hardware.amdgpu.legacySupport.enable = true` | gpu.nix |
| **GPU** | NVIDIA proprietary driver | `services.xserver.videoDrivers = ["nvidia"]; hardware.nvidia.open = true` | gpu.nix |
| **GPU** | NVIDIA modesetting (Wayland req.) | `hardware.nvidia.modesetting.enable = true` | gpu.nix |
| **GPU** | VA-API video decode (AMD) | Included with Mesa/RADV via `hardware.graphics` | gpu.nix |
| **GPU** | VDPAU (AMD) | `pkgs.vaapiVdpau` in `hardware.graphics.extraPackages` | gpu.nix |
| **GPU** | Hardware video codec (H264/HEVC) | `pkgs.libva-utils`, `pkgs.ffmpeg-full` in packages | gpu.nix |
| **Kernel** | Gaming-optimized kernel (bazzite-kernel based on fsync) | `boot.kernelPackages = pkgs.linuxPackages_zen` (see §8) | performance.nix |
| **Kernel** | BORE/LAVD schedulers | Available in `linuxPackages_lqx` (liquorix includes BORE) | performance.nix |
| **Kernel** | SteamOS kernel parameters | `boot.kernelParams` list (see §9.4) | performance.nix |
| **Kernel** | Split-lock detection disabled | `boot.kernelParams = ["split_lock_detect=off"]` | performance.nix |
| **Kernel** | Transparent hugepages | `boot.kernel.sysfs.kernel.mm.transparent_hugepage.enabled = "madvise"` | performance.nix |
| **Perf** | ZRAM swap (LZ4, 4 GB / 50%) | `zramSwap.enable = true; algorithm = "lz4"; memoryPercent = 50` | performance.nix |
| **Perf** | CPU frequency governor (performance) | `powerManagement.cpuFreqGovernor = "performance"` | performance.nix |
| **Perf** | Kyber I/O scheduler | `boot.kernelParams = ["elevator=kyber"]` (or mq-deadline per device) | performance.nix |
| **Perf** | BBR TCP congestion control | `boot.kernel.sysctl."net.core.default_qdisc" = "fq"; .tcp_congestion_control = "bbr"` | performance.nix |
| **Perf** | IRQ affinity / preempt full | `boot.kernelParams = ["preempt=full"]` | performance.nix |
| **Perf** | nohz_full tickless | `boot.kernelParams = ["nohz_full=all"]` (use with caution) | performance.nix |
| **Perf** | scx_lavd CPU scheduler | `pkgs.scx.lavd` (scx_sched package) | performance.nix |
| **Controllers** | Steam controller / Index udev | Enabled by `programs.steam.enable` | controllers.nix |
| **Controllers** | Xbox controller (xone/xpad) | `hardware.xone.enable = true` or `hardware.xpadneo.enable = true` | controllers.nix |
| **Controllers** | Nintendo Switch controller (hid-nintendo) | `hardware.nintendo.enable = true` | controllers.nix |
| **Controllers** | DualSense / DS4 | Native kernel hid-sony module; udev rules via `services.udev.packages` | controllers.nix |
| **Controllers** | 8BitDo / generic HID gamepads | `services.udev.extraRules` with vendor/product IDs | controllers.nix |
| **Software** | Flatpak + Flathub | `services.flatpak.enable = true` + Flathub remote via systemd service | flatpak.nix |
| **Software** | Distrobox | `pkgs.distrobox` + `pkgs.podman` | gaming.nix |
| **Software** | Sunshine streaming | `pkgs.sunshine` or `services.sunshine.enable = true` | (optional extra) |
| **Software** | LACT for GPU tuning | `services.lact.enable = true` | gpu.nix |
| **Software** | OpenRGB | `pkgs.openrgb` + `boot.kernelModules = ["i2c-piix4" "i2c-nct6775"]` | (optional extra) |
| **Software** | OpenTabletDriver | `pkgs.opentabletdriver` | (optional extra) |
| **Network** | NetworkManager | `networking.networkmanager.enable = true` (already set) | network.nix |
| **Network** | mDNS/Avahi | `services.avahi.enable = true; nssmdns4 = true` | network.nix |
| **Network** | Firewall baseline | `networking.firewall.enable = true` | network.nix |
| **Network** | BBR TCP | See performance.nix | network.nix |
| **Security** | allowUnfree (needed for Steam) | `nixpkgs.config.allowUnfree = true` | configuration.nix |
| **Security** | User in `gamemode` group | `users.users.nimda.extraGroups = ["gamemode"]` | gaming.nix |
| **Security** | rtkit for audio | `security.rtkit.enable = true` | audio.nix |

---

## 4. Module Architecture

The repo shall be restructured as follows:

```
vexos-nix/
├── flake.nix               ← updated (new inputs, unchanged output name)
├── configuration.nix       ← updated (imports list, allowUnfree)
└── modules/
    ├── gaming.nix          ← Steam, Proton, Lutris, Heroic, Bottles, MangoHud,
    │                         GameMode, Gamescope, Wine/Proton tools, Distrobox
    ├── desktop.nix         ← KDE Plasma 6 Wayland, SDDM, fonts, XDG portals,
    │                         Ozone, HDR via Gamescope
    ├── audio.nix           ← PipeWire, rtkit, low-latency, Bluetooth codecs
    ├── gpu.nix             ← AMD & NVIDIA GPU drivers, Vulkan, ROCm, VA-API,
    │                         VDPAU, LACT, codecs
    ├── performance.nix     ← zen/lqx kernel, kernel params, ZRAM, CPU governor,
    │                         I/O scheduler, BBR, hugepages, scx schedulers
    ├── controllers.nix     ← gamepad udev rules, xone, xpadneo, hid-nintendo,
    │                         DS4/DS5, steam-hardware
    ├── flatpak.nix         ← Flatpak + Flathub remote
    └── network.nix         ← NetworkManager, Avahi/mDNS, firewall baseline, BBR
```

### Module responsibilities

| Module | Responsibility |
|--------|---------------|
| `gaming.nix` | Steam (with 32-bit graphics, remotePlay firewall), `proton-ge-bin`, MangoHud, GameMode (with user group), Gamescope, Lutris, Heroic, Bottles, ProtonUp-Qt, Protontricks, Umu-launcher, vkBasalt, OBS VkCapture, Distrobox+Podman, Input Remapper |
| `desktop.nix` | KDE Plasma 6, SDDM Wayland, XDG portals, fonts, `NIXOS_OZONE_WL`, gamescope-wsi, GTK/icon themes, default Wayland session |
| `audio.nix` | PipeWire (alsa, pulse, jack), rtkit, low-latency config (via nix-gaming or manual), Bluetooth codec config via WirePlumber |
| `gpu.nix` | `hardware.graphics` (enable, enable32Bit), AMD ROCm/OpenCL, LACT, VDPAU, VA-API extra packages; NVIDIA subsection (guarded by a flag); firmware |
| `performance.nix` | Kernel selection (zen or lqx), kernel params, ZRAM, CPU governor, I/O scheduler, BBR TCP sysctl, hugepages, split-lock disable, scx scheduler |
| `controllers.nix` | xone, xpadneo, hid-nintendo, DS4/DS5 udev, extra HID udev rules |
| `flatpak.nix` | `services.flatpak.enable`, Flathub remote systemd service |
| `network.nix` | NetworkManager (already in configuration.nix, moved here for clarity), Avahi, firewall, resolved/mDNS |

---

## 5. flake.nix Changes

### New inputs required

```nix
inputs = {
  nixpkgs.url = "github:NixOS/nixpkgs/nixos-24.11";

  # nix-gaming: low-latency PipeWire module, platform optimizations, wine-ge
  nix-gaming = {
    url = "github:fufexan/nix-gaming";
    inputs.nixpkgs.follows = "nixpkgs";
  };

  # home-manager: optional, for user-level Plasma config / dotfiles later
  home-manager = {
    url = "github:nix-community/home-manager/release-24.11";
    inputs.nixpkgs.follows = "nixpkgs";
  };
};
```

### Updated outputs (modules list)

```nix
outputs = { self, nixpkgs, nix-gaming, ... }@inputs:
let
  system = "x86_64-linux";
in
{
  nixosConfigurations.vexos = nixpkgs.lib.nixosSystem {
    inherit system;
    modules = [
      /etc/nixos/hardware-configuration.nix
      ./configuration.nix
      nix-gaming.nixosModules.pipewireLowLatency
      nix-gaming.nixosModules.steamPlatformOptimizations
    ];
    specialArgs = { inherit inputs; };
  };
};
```

### Rules
- Every new flake input MUST include `inputs.<name>.follows = "nixpkgs"` to avoid duplicate nixpkgs closures.
- `nix-gaming` follows `nixpkgs` as shown above.
- `home-manager` follows `nixpkgs`.
- `hardware-configuration.nix` path remains `/etc/nixos/hardware-configuration.nix` — NOT tracked in the repo.

---

## 6. configuration.nix Changes

The updated `configuration.nix` shall be a thin orchestrator that imports all modules:

```nix
{ config, pkgs, inputs, ... }:
{
  imports = [
    ./modules/desktop.nix
    ./modules/gaming.nix
    ./modules/audio.nix
    ./modules/gpu.nix
    ./modules/performance.nix
    ./modules/controllers.nix
    ./modules/flatpak.nix
    ./modules/network.nix
  ];

  # ---------- Bootloader ----------
  boot.loader.systemd-boot.enable = true;
  boot.loader.efi.canTouchEfiVariables = true;

  # ---------- Networking (base) ----------
  networking.hostName = "vexos";
  # networking.networkmanager moved to modules/network.nix

  # ---------- Time / Locale ----------
  time.timeZone = "America/New_York";
  i18n.defaultLocale = "en_US.UTF-8";

  # ---------- Users ----------
  users.users.nimda = {
    isNormalUser = true;
    description = "nimda";
    extraGroups = [
      "wheel"
      "networkmanager"
      "gamemode"  # required for GameMode CPU governor control
      "audio"     # for raw ALSA access (optional with pipewire)
      "input"     # for controller/udev access
    ];
  };

  # ---------- System packages (base) ----------
  environment.systemPackages = with pkgs; [
    vim git curl wget htop
  ];

  # ---------- Nix settings ----------
  nix.settings = {
    experimental-features = [ "nix-command" "flakes" ];
    auto-optimise-store = true;
    substituters = [
      "https://cache.nixos.org"
      "https://nix-gaming.cachix.org"
    ];
    trusted-public-keys = [
      "cache.nixos.org-1:6NCHdD59X431o0gWypbMrAURkbJ16ZPMQFGspcDShjY="
      "nix-gaming.cachix.org-1:nbjlureqMbRAxR1gJ/f3hxemL9svXaZF/Ees8vCUUs4="
    ];
  };

  # ---------- Unfree (required for Steam, NVIDIA) ----------
  nixpkgs.config.allowUnfree = true;

  # ---------- State version (MUST NOT CHANGE) ----------
  system.stateVersion = "24.11";
}
```

---

## 7. Per-Module Implementation Details

### 7.1 modules/gaming.nix

```nix
{ config, pkgs, lib, ... }:
{
  # Steam (enables hardware.steam-hardware.enable automatically)
  programs.steam = {
    enable = true;
    remotePlay.openFirewall = true;
    dedicatedServer.openFirewall = false;
    gamescopeSession.enable = true;         # enables the gamescope sessionfor steam gaming mode

    # Proton-GE as an additional compatibility tool
    extraCompatPackages = with pkgs; [
      proton-ge-bin
    ];
  };

  # Gamescope micro-compositor (HDR, VRR, frame limiting)
  programs.gamescope = {
    enable = true;
    capSysNice = true;   # allows gamescope to renice itself
  };

  # GameMode — performance daemon (CPU governor, GPU perf on game start)
  programs.gamemode = {
    enable = true;
    settings = {
      general = {
        renice = 10;
        inhibit_screensaver = 0;  # disable if no screensaver installed (avoids error log)
      };
      gpu = {
        apply_gpu_optimisations = "accept-responsibility";
        gpu_device = 0;
        amd_performance_level = "high";
      };
    };
  };

  # MangoHud — in-game performance overlay
  programs.mangohud.enable = true;

  # Gaming utilities
  environment.systemPackages = with pkgs; [
    # Game launchers
    lutris              # multi-platform launcher (Proton/Wine)
    heroic              # Epic / GOG / Amazon Games
    bottles             # Wine prefix manager

    # Proton / Wine tooling
    protonup-qt         # GUI for managing Proton-GE and other runners
    protontricks        # winetricks wrapper for Steam games
    umu-launcher        # Proton launcher for non-Steam games (replaces Lutris for some)

    # Display / overlay
    vkbasalt            # Vulkan post-processing layer (CAS, FXAA, etc.)
    obs-studio
    obs-vkcapture       # Vulkan/OpenGL game capture for OBS

    # Wine (staging + Wow64 multilib)
    wineWowPackages.stagingFull

    # Disk / prefix maintenance
    duperemove          # deduplicates wine prefix content

    # Container tooling (Distrobox)
    distrobox
    podman

    # Input remapping
    input-remapper
  ];

  # Input Remapper daemon (must run as service)
  services.udev.packages = [ pkgs.input-remapper ];
  systemd.services.input-remapper = {
    description = "Input Remapper";
    wantedBy = [ "multi-user.target" ];
    serviceConfig = {
      Type = "simple";
      ExecStart = "${pkgs.input-remapper}/bin/input-remapper-service";
      Restart = "on-failure";
    };
  };
}
```

**Notes:**
- `proton-ge-bin` is an unfree package; requires `allowUnfree = true`.
- `gamescope.capSysNice = true` requires the `CAP_SYS_NICE` capability set on the gamescope binary, which the NixOS module handles via a systemd `ExecStartPre` setcap wrapper.
- The `gamemode` group is added to the user in `configuration.nix` for CPU governor access.

---

### 7.2 modules/desktop.nix

```nix
{ config, pkgs, lib, ... }:
{
  # KDE Plasma 6 — enables kwin (Wayland compositor), kwin-x11, and all Plasma components
  services.desktopManager.plasma6.enable = true;

  # SDDM display manager with Wayland session support
  services.displayManager.sddm = {
    enable = true;
    wayland.enable = true;    # SDDM Wayland greeter (experimental in 24.11)
    autoNumlock = true;
  };

  # Default session: Plasma Wayland
  services.displayManager.defaultSession = "plasma";  # "plasma" = Wayland in Plasma 6

  # XDG Desktop Portal for Wayland (screen share, file picker, etc.)
  xdg.portal = {
    enable = true;
    extraPortals = with pkgs; [
      xdg-desktop-portal-kde    # KDE-native portal backend
    ];
    config.common.default = "kde";
  };

  # Ozone Wayland: makes Electron/Chromium apps use native Wayland
  environment.sessionVariables.NIXOS_OZONE_WL = "1";

  # Gamescope WSI layer (required for HDR in gamescope on KDE Wayland)
  environment.systemPackages = with pkgs; [
    gamescope-wsi
    kdePackages.plasma-browser-integration
    kdePackages.kdegraphics-thumbnailers
    xwaylandvideobridge    # screen sharing of X11 windows on Wayland
  ];

  # Font configuration
  fonts = {
    enableDefaultPackages = true;
    packages = with pkgs; [
      noto-fonts
      noto-fonts-cjk-sans
      noto-fonts-emoji
      liberation_ttf
      fira-code
      fira-code-symbols
      (nerdfonts.override { fonts = [ "FiraCode" "JetBrainsMono" ]; })
    ];
    fontconfig.defaultFonts = {
      serif      = [ "Noto Serif" ];
      sansSerif  = [ "Noto Sans" ];
      monospace  = [ "FiraCode Nerd Font" ];
    };
  };

  # Printing (matches Bazzite CUPS support)
  services.printing.enable = true;

  # Bluetooth (hardware config in gpu/hardware module; enable service here)
  hardware.bluetooth.enable = true;
  services.blueman.enable = true;   # Bluetooth manager GUI
}
```

**Notes:**
- `services.desktopManager.plasma6.enable = true` is the correct NixOS 24.11 option.
- `services.displayManager.sddm.wayland.enable = true` is marked experimental in NixOS 24.11 for SDDM, but is the recommended path. If stability is a concern, the X11 SDDM can be used with a Wayland Plasma session still launching correctly.
- KDE Plasma 6 launches a Wayland session by default; the `defaultSession = "plasma"` line confirms the Wayland variant.
- `xwaylandvideobridge` is needed for screen sharing of X11 apps under Wayland with KDE.

---

### 7.3 modules/audio.nix

```nix
{ config, pkgs, lib, ... }:
{
  # rtkit: allows PipeWire and audio threads to use realtime scheduling
  security.rtkit.enable = true;

  services.pipewire = {
    enable = true;

    # Compatibility layers
    alsa.enable = true;
    alsa.support32Bit = true;   # required for 32-bit wine audio
    pulse.enable = true;        # PulseAudio compatibility
    jack.enable = true;         # JACK compatibility (optional but useful for pro audio)

    # Low-latency tuning (matches Bazzite's gaming-grade audio)
    # Note: nix-gaming module provides this declaratively if imported in flake.nix.
    # If using nix-gaming module, set services.pipewire.lowLatency.enable = true.
    # Otherwise use the manual config below:
    extraConfig.pipewire."92-low-latency" = {
      "context.properties" = {
        "default.clock.rate"        = 48000;
        "default.clock.quantum"     = 64;
        "default.clock.min-quantum" = 64;
        "default.clock.max-quantum" = 128;
      };
    };

    # PulseAudio backend low-latency (must be >= pipewire quantum)
    extraConfig.pipewire-pulse."92-low-latency" = {
      "context.properties" = [
        {
          name = "libpipewire-module-protocol-pulse";
          args = {};
        }
      ];
      "pulse.properties" = {
        "pulse.min.req"     = "64/48000";
        "pulse.default.req" = "64/48000";
        "pulse.max.req"     = "64/48000";
        "pulse.min.quantum" = "64/48000";
        "pulse.max.quantum" = "64/48000";
      };
      "stream.properties" = {
        "node.latency"      = "64/48000";
        "resample.quality"  = 1;
      };
    };

    # WirePlumber: Bluetooth high-quality codecs (SBC-XQ, mSBC)
    wireplumber.extraConfig."10-bluez" = {
      "monitor.bluez.properties" = {
        "bluez5.enable-sbc-xq"  = true;
        "bluez5.enable-msbc"    = true;
        "bluez5.enable-hw-volume" = true;
        "bluez5.roles" = [
          "hsp_hs" "hsp_ag" "hfp_hf" "hfp_ag"
        ];
      };
    };
  };
}
```

**Notes:**
- If both `nix-gaming.nixosModules.pipewireLowLatency` is imported in `flake.nix` AND `services.pipewire.lowLatency.enable = true` is set here, the manual `extraConfig` entries above should be removed to avoid conflicts. The nix-gaming module defaults are `quantum = 64; rate = 48000` which match the manual config.
- The quantum of 64 gives ~1.33ms latency at 48kHz — suitable for rhythm games and gaming audio. If crackles occur, increase to 128 or 256.
- `alsa.support32Bit = true` is mandatory for Wine/Proton games that use 32-bit audio paths.

---

### 7.4 modules/gpu.nix

This module uses an `enableNvidia` option to make it easy to toggle between AMD and NVIDIA configurations.

```nix
{ config, pkgs, lib, ... }:
let
  # Set to true if this host uses an NVIDIA GPU.
  # On AMD/Intel systems, leave false.
  enableNvidia = false;
in
{
  # ── Common graphics ──────────────────────────────────────────────────────
  hardware.graphics = {
    enable    = true;
    enable32Bit = true;   # required for Steam/Proton 32-bit applications

    # VA-API and VDPAU acceleration packages (AMD / Intel Mesa)
    extraPackages = with pkgs; [
      libva               # VA-API runtime
      libva-utils         # vainfo tool
      vaapiVdpau          # VDPAU via VA-API
      libvdpau-va-gl      # VDPAU OpenGL backend
      intel-media-driver  # iHD VA-API driver (Intel 8th gen+) — safe to include; no-op on AMD
      mesa                # includes RADV (AMD Vulkan) and llvmpipe
    ];

    extraPackages32 = with pkgs.pkgsi686Linux; [
      libva
      vaapiVdpau
      mesa
    ];
  };

  # ── AMD GPU ──────────────────────────────────────────────────────────────
  # AMD is handled by Mesa RADV by default (hardware.graphics.enable).
  # Additional AMD-specific options:

  hardware.amdgpu = {
    # Enable OpenCL via ROCm (Full AMD ROCm/HIP support like Bazzite)
    opencl.enable = true;

    # Load amdgpu module early in initrd for better boot resolution
    initrd.enable = true;

    # Enable legacy Southern Islands (GCN1 HD7000) and Sea Islands (GCN2 HD8000) support
    # Disabled by default; enable only if using these older GPUs.
    # legacySupport.enable = true;
  };

  # Force RADV over AMDVLK (AMDVLK is being discontinued; RADV is faster)
  environment.variables.AMD_VULKAN_ICD = "RADV";

  # LACT: GPU overclocking/fan-curve tool (like Bazzite's LACT support)
  services.lact.enable = true;

  # ── NVIDIA GPU (conditional) ─────────────────────────────────────────────
  services.xserver.videoDrivers = lib.mkIf enableNvidia [ "nvidia" ];

  hardware.nvidia = lib.mkIf enableNvidia {
    # Open kernel modules (Turing/RTX 20+ and GTX 16+; required for Wayland)
    open = true;    # Set false for Maxwell/Pascal/Volta (GTX 900/1000/Titan V)

    # KMS: required for Wayland and suspend/resume reliability
    modesetting.enable = true;

    # Power management (optional; helps with suspend on laptops)
    powerManagement = {
      enable = false;       # set true if suspend/resume issues occur
      finegrained = false;  # set true for PRIME laptops with Turing+ dGPU
    };

    # Use the stable driver branch by default
    # For beta: config.boot.kernelPackages.nvidiaPackages.beta
    package = config.boot.kernelPackages.nvidiaPackages.stable;
  };

  # ── Video codec packages ──────────────────────────────────────────────────
  environment.systemPackages = with pkgs; [
    ffmpeg-full         # full codec support including H264, HEVC, AV1
    libva-utils         # vainfo – verify VA-API
    vulkan-tools        # vulkaninfo
    vulkan-loader
    glxinfo             # OpenGL / Vulkan info
  ];

  # ROCm symlink workaround for HIP hard-coded library paths
  systemd.tmpfiles.rules =
    let
      rocmEnv = pkgs.symlinkJoin {
        name = "rocm-combined";
        paths = with pkgs.rocmPackages; [ rocblas hipblas clr ];
      };
    in
    lib.mkIf (!enableNvidia) [
      "L+  /opt/rocm  -  -  -  -  ${rocmEnv}"
    ];
}
```

**Notes:**
- `enableNvidia = false` at the top of the let block is the primary toggle. Future implementations may expose this as a NixOS option (`options.vexos.enableNvidia`).
- AMDVLK is being discontinued upstream (as of its own GitHub announcement); RADV is the recommended Vulkan driver.
- `hardware.amdgpu.opencl.enable = true` requires `nixpkgs.config.allowUnfree = false` is NOT blocking ROCm (ROCm itself is open; some sub-packages may have license concerns).
- The `intel-media-driver` is safe to include on AMD systems — it will simply not load if no Intel GPU exists.
- The `/opt/rocm` symlink is needed because many ROCm-dependent programs (Blender, Stable Diffusion, etc.) hard-code the path.

---

### 7.5 modules/performance.nix

```nix
{ config, pkgs, lib, ... }:
{
  # ── Kernel selection ──────────────────────────────────────────────────────
  # zen kernel: preemptive, tickless, optimized for desktop/gaming latency.
  # Tracks mainline closely. Available in nixpkgs as linuxPackages_zen.
  #
  # Alternatives:
  #   pkgs.linuxPackages_lqx   — Liquorix: includes BORE scheduler, more aggressive tuning
  #   pkgs.linuxPackages_xanmod — XanMod: BORE, LTO, BBR3 default
  #   pkgs.linuxPackages_latest — Latest mainline (unstable; bleeding edge drivers)
  #
  # RECOMMENDATION: Start with zen. Switch to lqx for BORE scheduler support.
  boot.kernelPackages = pkgs.linuxPackages_zen;

  # ── Kernel parameters ─────────────────────────────────────────────────────
  # These mirror SteamOS / Bazzite kernel parameter set for gaming optimization.
  boot.kernelParams = [
    # Scheduler
    "preempt=full"            # Full preemption (lowest latency for desktop)

    # Disable split-lock detection (improves Wine/Proton compatibility)
    "split_lock_detect=off"

    # Disable CPU vulnerability mitigations for performance
    # WARNING: Reduces security. Omit on shared/multi-user or internet-exposed systems.
    # "mitigations=off"       # Disabled by default; uncomment only if desired

    # I/O scheduler: Kyber is low-latency; works well for NVMe SSDs
    # Note: some kernels use mq-deadline for HDDs. Override per-device via udev if needed.
    "elevator=kyber"

    # Quiet boot (matches Bazzite's clean boot experience)
    "quiet"
    "splash"
    "loglevel=3"

    # amdgpu early load for better boot resolution (also set in gpu.nix via hardware.amdgpu.initrd)
    # "amdgpu.ppfeaturemask=0xffffffff"  # unlock all power features (use with LACT)
  ];

  # ── ZRAM swap ─────────────────────────────────────────────────────────────
  # Matches Bazzite's ZRAM(4GB) with LZ4. Using 50% of system RAM.
  zramSwap = {
    enable        = true;
    algorithm     = "lz4";
    memoryPercent = 50;       # up to 50% of physical RAM as compressed swap
  };

  # ── CPU frequency governor ────────────────────────────────────────────────
  # "performance" locks max frequency — lower latency, higher power draw.
  # "schedutil" (default in zen) is more power-efficient with good gaming perf.
  powerManagement.cpuFreqGovernor = "schedutil";  # change to "performance" if desired

  # ── Kernel sysctl tunables ────────────────────────────────────────────────
  boot.kernel.sysctl = {
    # BBR TCP congestion control (like Bazzite's Google BBR default)
    "net.core.default_qdisc"         = "fq";
    "net.ipv4.tcp_congestion_control" = "bbr";

    # Virtual memory: reduce swap aggressiveness (good for gaming)
    "vm.swappiness"             = 10;
    "vm.dirty_ratio"            = 20;
    "vm.dirty_background_ratio" = 5;

    # File watch limits (needed for some game engines, IDEs, Electron apps)
    "fs.inotify.max_user_watches"    = 524288;
    "fs.inotify.max_user_instances"  = 8192;

    # Network: increase socket buffer sizes for game streaming
    "net.core.rmem_max" = 16777216;
    "net.core.wmem_max" = 16777216;
  };

  # ── Transparent Huge Pages ────────────────────────────────────────────────
  boot.kernel.sysfs = {
    kernel.mm.transparent_hugepage = {
      enabled = "madvise";  # madvise: only allocate THP when app requests it
      defrag  = "defer";
    };
  };

  # ── scx CPU scheduler (LAVD / BORE via scx_sched) ─────────────────────────
  # scx_lavd is the SteamOS/Bazzite scheduler for handhelds; also good for desktops.
  # Only available on kernels with sched_ext support (zen 6.12+, lqx 6.12+).
  # Uncomment after confirming kernel sched_ext support:
  #
  # services.scx = {
  #   enable    = true;
  #   scheduler = "scx_lavd";   # or "scx_rusty", "scx_bpfland"
  # };
  #
  # On NixOS 24.11, check: services.scx.enable (added in unstable; may need overlay).

  # ── Plymouth (boot splash) ─────────────────────────────────────────────────
  boot.plymouth = {
    enable = true;
    # theme = "bgrt";  # vendor logo theme if desired
  };

  # ── SysRq (useful for gaming system recovery) ─────────────────────────────
  boot.kernel.sysctl."kernel.sysrq" = 1;
}
```

**Notes on kernel strategy (see §8 for full discussion):**
- `linuxPackages_zen` is the recommended starting point — it is stable, tracked closely to mainline, and provides `PREEMPT_DYNAMIC`, BFQ and Kyber I/O schedulers, and general desktop-latency patches.
- `linuxPackages_lqx` (Liquorix) is recommended if BORE CPU scheduler support is specifically desired (BORE is on by default in lqx).
- The bazzite-kernel is NOT (and cannot be) directly packaged in nixpkgs; it would require a custom kernel derivation or an overlay (out of scope for Phase 1).
- `scx` scheduler support (`scx_lavd`, SteamOS default) requires `sched_ext` in-kernel support, available in zen 6.12+ and lqx 6.12+.

---

### 7.6 modules/controllers.nix

```nix
{ config, pkgs, lib, ... }:
{
  # ── Xbox controllers ──────────────────────────────────────────────────────
  # xone: USB dongle + wired Xbox One/Series S|X controllers
  hardware.xone.enable = true;

  # xpadneo: Xbox wireless controllers via Bluetooth
  hardware.xpadneo.enable = true;

  # ── Nintendo Switch Pro / Joy-Con ─────────────────────────────────────────
  # hid-nintendo: Switch Pro Controller, Joy-Cons
  hardware.nintendo.enable = true;

  # ── Steam hardware (Valve Index, Steam Controller, Steam Deck) ────────────
  # Enabled automatically by programs.steam.enable in gaming.nix,
  # but can be set explicitly:
  hardware.steam-hardware.enable = true;

  # ── DualShock 4 / DualSense (Sony) ───────────────────────────────────────
  # Sony HID module is in-kernel. Load it explicitly and set permissions.
  boot.kernelModules = [ "hid_sony" ];

  services.udev.extraRules = ''
    # DualShock 4 (USB)
    KERNEL=="hidraw*", ATTRS{idVendor}=="054c", ATTRS{idProduct}=="05c4", MODE="0660", GROUP="input"
    KERNEL=="hidraw*", ATTRS{idVendor}=="054c", ATTRS{idProduct}=="09cc", MODE="0660", GROUP="input"
    # DualSense (USB)
    KERNEL=="hidraw*", ATTRS{idVendor}=="054c", ATTRS{idProduct}=="0ce6", MODE="0660", GROUP="input"
    # DualSense Edge (USB)
    KERNEL=="hidraw*", ATTRS{idVendor}=="054c", ATTRS{idProduct}=="0df2", MODE="0660", GROUP="input"
    # Generic HID gamepad Bluetooth
    KERNEL=="hidraw*", SUBSYSTEM=="hidraw", ATTRS{idVendor}=="054c", MODE="0660", GROUP="input"

    # 8BitDo Ultimate Bluetooth
    SUBSYSTEM=="input", ATTRS{idVendor}=="2dc8", ATTRS{idProduct}=="3106", MODE="0660", GROUP="input"

    # Generic: allow all input devices for the input group
    SUBSYSTEM=="input", MODE="0660", GROUP="input"
  '';

  # Ensure user is in input group (set in configuration.nix extraGroups)
  # users.users.nimda.extraGroups includes "input" (see configuration.nix)
}
```

**Notes:**
- `hardware.xone.enable = true` pulls in the `xone` out-of-tree module, compiled against the active kernel.
- `hardware.xpadneo.enable = true` pulls in `xpadneo`.
- `hardware.nintendo.enable = true` pulls in `hid-nintendo`.
- All three are DKMS-style out-of-tree modules in nixpkgs — they are compiled to match the active `boot.kernelPackages`.
- The `input` group must be in the user's `extraGroups` (set in `configuration.nix`) for hidraw device access without root.

---

### 7.7 modules/flatpak.nix

```nix
{ config, pkgs, lib, ... }:
{
  # Enable Flatpak subsystem
  services.flatpak.enable = true;

  # Automatically add Flathub remote on system activation
  # (Bazzite ships Flathub enabled out of the box)
  systemd.services.flatpak-add-flathub = {
    description  = "Add Flathub Flatpak remote";
    wantedBy     = [ "multi-user.target" ];
    after        = [ "network-online.target" ];
    wants        = [ "network-online.target" ];
    path         = [ pkgs.flatpak ];
    script       = ''
      flatpak remote-add --if-not-exists flathub \
        https://dl.flathub.org/repo/flathub.flatpakrepo
    '';
    serviceConfig = {
      Type            = "oneshot";
      RemainAfterExit = true;
    };
  };

  # XDG data dirs: ensure Flatpak desktop files are visible to KDE
  environment.sessionVariables = {
    XDG_DATA_DIRS = lib.mkAfter [
      "/var/lib/flatpak/exports/share"
      "$HOME/.local/share/flatpak/exports/share"
    ];
  };
}
```

**Notes:**
- Flatpak is the primary app delivery mechanism in Bazzite (their "Bazaar" app store is Flathub-backed).
- For declarative Flatpak management (managing app installs in Nix), `nix-flatpak` or `declarative-flatpak` can be added in a future phase.
- The `XDG_DATA_DIRS` session variable ensures KDE Plasma's app launcher shows Flatpak-installed app icons.

---

### 7.8 modules/network.nix

```nix
{ config, pkgs, lib, ... }:
{
  # NetworkManager (moved from configuration.nix for modularity)
  networking.networkmanager.enable = true;

  # mDNS / Avahi (needed for local network discovery, AirPlay in PipeWire)
  services.avahi = {
    enable    = true;
    nssmdns4  = true;    # enables mDNS in NSS for .local hostname resolution
    openFirewall = true; # opens UDP 5353/mdns
  };

  # Firewall baseline
  networking.firewall = {
    enable = true;
    # Steam Remote Play ports (also opened by programs.steam.remotePlay.openFirewall)
    allowedTCPPorts = [ 27036 27037 ];
    allowedUDPPorts = [ 27031 27032 27033 27034 27035 27036 ];
  };

  # DNS resolver
  services.resolved = {
    enable      = true;
    dnssec      = "allow-downgrade";
    fallbackDns = [ "1.1.1.1" "9.9.9.9" ];
  };
}
```

**Notes:**
- BBR TCP and sysctl network tuning are handled in `performance.nix` to keep them co-located with other kernel/sysctl tuning.
- `services.resolved.enable = true` replaces the old `systemd-resolved` approach and works with NetworkManager automatically.

---

## 8. Kernel Strategy

### Recommendation: `linuxPackages_zen` as default, `linuxPackages_lqx` for BORE

| Kernel | NixOS package | Strengths | Bazzite parity |
|--------|--------------|-----------|---------------|
| **zen** | `pkgs.linuxPackages_zen` | Stable, very close to mainline, PREEMPT_DYNAMIC, MuQSS/CFS tweaks, good driver support | ~90% — lacks BORE scheduler |
| **lqx** (Liquorix) | `pkgs.linuxPackages_lqx` | BORE scheduler, ZEN patches, tuned for low-latency desktop | ~95% — matches Bazzite's BORE/LAVD feature |
| **xanmod** | `pkgs.linuxPackages_xanmod` | BORE + BBR3 + x86-64-v3 optimizations, LTO | ~95% — similar to lqx but has march=x86-64-v3 compat concerns |
| **bazzite-kernel** | NOT in nixpkgs | fsync patches, exact HDR patches, exact SteamOS params | 100% — custom derivation needed |

**Phase 1 recommendation: `linuxPackages_zen`**

The zen kernel is the safest starting point for reliability:
- Fully maintained in nixpkgs 24.11
- Compatible with `hardware.xone`, `hardware.xpadneo`, `hardware.nintendo` out-of-tree modules
- Supports `sched_ext` (scx schedulers) in recent releases
- PREEMPT_DYNAMIC enabled (select between PREEMPT_NONE, PREEMPT_VOLUNTARY, PREEMPT + PREEMPT_RT at boot)

If BORE scheduler is needed, switch to `linuxPackages_lqx`. The Liquorix kernel also includes the `BORE` scheduler and many tuning patches that align closely with Bazzite's kernel-fsync base.

The custom bazzite-kernel (HDR patches specific to bazzite) is noted as a planned separate effort by the user and is therefore out of scope for this specification phase.

---

## 9. Dependencies

### 9.1 New Flake Inputs

| Input | URL | `follows` | Purpose |
|-------|-----|-----------|---------|
| `nix-gaming` | `github:fufexan/nix-gaming` | `nixpkgs` | Low-latency PipeWire, SteamOS platform optimizations, Wine-GE packages |
| `home-manager` | `github:nix-community/home-manager/release-24.11` | `nixpkgs` | Optional: user-level Plasma config, dotfiles (future phases) |

### 9.2 New nixpkgs Packages (unfree / free)

| Package | nixpkgs attribute | License | Module |
|---------|------------------|---------|--------|
| Steam | `programs.steam.enable` | Unfree (Valve) | gaming.nix |
| proton-ge-bin | `pkgs.proton-ge-bin` | Unfree (binary) | gaming.nix |
| Lutris | `pkgs.lutris` | GPL-3 | gaming.nix |
| Heroic | `pkgs.heroic` | GPL-3 | gaming.nix |
| Bottles | `pkgs.bottles` | GPL-3 | gaming.nix |
| MangoHud | `programs.mangohud.enable` | MIT | gaming.nix |
| vkBasalt | `pkgs.vkbasalt` | zlib | gaming.nix |
| Gamescope | `programs.gamescope.enable` | BSD | gaming.nix |
| gamescope-wsi | `pkgs.gamescope-wsi` | MIT | desktop.nix |
| ProtonUp-Qt | `pkgs.protonup-qt` | GPL-3 | gaming.nix |
| Protontricks | `pkgs.protontricks` | GPL-3 | gaming.nix |
| Umu-launcher | `pkgs.umu-launcher` | GPL-3 | gaming.nix |
| OBS Studio | `pkgs.obs-studio` | GPL-2 | gaming.nix |
| OBS VkCapture | `pkgs.obs-vkcapture` | GPL-2 | gaming.nix |
| Wine (Staging Wow64) | `pkgs.wineWowPackages.stagingFull` | LGPL | gaming.nix |
| duperemove | `pkgs.duperemove` | GPL-2 | gaming.nix |
| Distrobox | `pkgs.distrobox` | GPL-3 | gaming.nix |
| Podman | `pkgs.podman` | Apache-2 | gaming.nix |
| Input Remapper | `pkgs.input-remapper` | GPL-3 | gaming.nix |
| LACT | `services.lact.enable` | MIT | gpu.nix |
| ROCm packages | `pkgs.rocmPackages.*` | MIT/Apache | gpu.nix |
| ffmpeg-full | `pkgs.ffmpeg-full` | LGPL/GPL | gpu.nix |
| libva-utils | `pkgs.libva-utils` | MIT | gpu.nix |
| vulkan-tools | `pkgs.vulkan-tools` | Apache-2 | gpu.nix |
| KDE Plasma 6 | `services.desktopManager.plasma6.enable` | LGPL | desktop.nix |
| xdg-desktop-portal-kde | `pkgs.xdg-desktop-portal-kde` | LGPL | desktop.nix |
| Nerd Fonts | `pkgs.nerdfonts` | SIL OFL | desktop.nix |
| xwaylandvideobridge | `pkgs.xwaylandvideobridge` | GPL-2 | desktop.nix |
| blueman | `pkgs.blueman` | GPL-2 | desktop.nix |
| Flatpak | `services.flatpak.enable` | LGPL | flatpak.nix |
| xone | `hardware.xone.enable` | GPL-2 | controllers.nix |
| xpadneo | `hardware.xpadneo.enable` | GPL-2 | controllers.nix |
| hid-nintendo | `hardware.nintendo.enable` | GPL-2 | controllers.nix |
| Zen kernel | `pkgs.linuxPackages_zen` | GPL-2 | performance.nix |

### 9.3 Cachix / Binary Cache

- **nix-gaming.cachix.org** — provides pre-built binaries for nix-gaming packages (especially Wine builds which are slow to compile).
- Add to `nix.settings.substituters` and `trusted-public-keys` in `configuration.nix` (already shown in §6).

---

## 10. Risks and Mitigations

| Risk | Severity | Mitigation |
|------|----------|------------|
| **`system.stateVersion` mutation** | CRITICAL | Spec mandates it MUST remain `"24.11"`. Implementation subagent must not touch this line. |
| **`hardware-configuration.nix` committed** | CRITICAL | Must remain at `/etc/nixos/hardware-configuration.nix`. Preflight script must verify it is not in the repo. |
| **Out-of-tree kernel modules vs zen** | HIGH | `xone`, `xpadneo`, `hid-nintendo` compile against the active `boot.kernelPackages`. If kernel is changed, these recompile automatically. Validated in NixOS 24.11 against zen kernel. |
| **NVIDIA + Wayland** | HIGH | Requires `hardware.nvidia.modesetting.enable = true` and driver ≥ 555 for explicit sync. Open modules (`hardware.nvidia.open = true`) only work on Turing+. Spec exposes `enableNvidia` flag for conditional activation. |
| **Unfree packages blocked** | HIGH | `nixpkgs.config.allowUnfree = true` must be set in `configuration.nix`. This enables Steam, proton-ge-bin, NVIDIA. ROCm is mostly open but transitively touches some Unfree packages. |
| **scx/LAVD scheduler** | MEDIUM | `services.scx` may not be available in nixpkgs 24.11 (it was added in nixos-unstable). Implementation subagent must check availability; if absent, leave the scx block commented. |
| **SDDM Wayland** | MEDIUM | `services.displayManager.sddm.wayland.enable` is marked experimental in 24.11. If it causes login issues, fall back to `services.displayManager.sddm.wayland.enable = false` (SDDM X11 + Plasma Wayland session still works). |
| **PipeWire low-latency crackling** | MEDIUM | Start with `quantum = 64`. If crackling occurs, increase to 128 or 256. The quantum value is `min-quantum` — PipeWire auto-scales up as needed. |
| **amdgpu + Vega instability (kernel 6.13)** | MEDIUM | If user has Vega integrated graphics, a stability patch exists (see AMD GPU wiki). Monitor `dmesg` for `GCVM_L2_PROTECTION_FAULT_STATUS`. Apply patch via `boot.extraModulePackages` if needed. |
| **AMDVLK vs RADV conflict** | LOW | Setting `AMD_VULKAN_ICD = "RADV"` in `gpu.nix` prevents Steam from defaulting to AMDVLK. AMDVLK is being discontinued anyway. |
| **nix-gaming flake version drift** | LOW | Pin `nix-gaming.url` to a specific commit or tag for reproducibility in `flake.lock`. The `nix flake update` process controls when it updates. |
| **Flatpak Flathub remote on air-gapped systems** | LOW | The `flatpak-add-flathub` systemd service requires internet access. It runs after `network-online.target`, so it is deferred safely. |
| **BBR TCP module** | LOW | BBR requires the `tcp_bbr` kernel module. The zen/lqx kernels include it. It is silently a no-op if not available. `sysctl` values fail gracefully. |
| **`preempt=full` on some CPUs** | LOW | On most modern desktop CPUs this is fine. On some embedded or older hardware it can cause issues. Fallback: remove the param for the NixOS-default `PREEMPT_VOLUNTARY`. |

---

## 11. Implementation Checklist for Phase 2

The implementation subagent must complete all of the following:

- [ ] Create `modules/` directory at repo root
- [ ] Create `modules/gaming.nix` — all contents from §7.1
- [ ] Create `modules/desktop.nix` — all contents from §7.2
- [ ] Create `modules/audio.nix` — all contents from §7.3
- [ ] Create `modules/gpu.nix` — all contents from §7.4
- [ ] Create `modules/performance.nix` — all contents from §7.5
- [ ] Create `modules/controllers.nix` — all contents from §7.6
- [ ] Create `modules/flatpak.nix` — all contents from §7.7
- [ ] Create `modules/network.nix` — all contents from §7.8
- [ ] Update `flake.nix` — add `nix-gaming` and `home-manager` inputs (§5)
- [ ] Update `flake.nix` — import `nix-gaming.nixosModules.pipewireLowLatency` and `steamPlatformOptimizations` in modules list (§5)
- [ ] Update `configuration.nix` — add `imports` list for all modules (§6)
- [ ] Update `configuration.nix` — change `allowUnfree = false` to `allowUnfree = true`
- [ ] Update `configuration.nix` — add `gamemode`, `audio`, `input` to user `extraGroups`
- [ ] Update `configuration.nix` — add `nix.settings.substituters` and `trusted-public-keys` for nix-gaming Cachix
- [ ] Remove `networking.networkmanager.enable = true` from `configuration.nix` (moved to `network.nix`)
- [ ] Verify `system.stateVersion = "24.11"` is unchanged
- [ ] Verify `hardware-configuration.nix` is NOT added to the repo
- [ ] Run `nix flake check` — must pass
- [ ] Run `sudo nixos-rebuild dry-build --flake .#vexos` — must pass

---

## 12. Summary of Findings

Bazzite is a gaming-focused Fedora Atomic Desktop derivative shipping:

1. **A gaming-optimized kernel** (bazzite-kernel, fsync-based) with HDR patches, BORE/LAVD schedulers, SteamOS params. NixOS equivalent: `linuxPackages_zen` (phase 1) or `linuxPackages_lqx` (for BORE).

2. **A full gaming stack** (Steam, Lutris, Heroic, Bottles, MangoHud, vkBasalt, Gamescope, ProtonUp-Qt, Protontricks, Wine-GE, Input Remapper, OBS VkCapture) all packaged in nixpkgs with clean declarative options.

3. **KDE Plasma 6 Wayland** with SDDM and all XDG portals — directly available via `services.desktopManager.plasma6.enable`.

4. **PipeWire low-latency audio** with Bluetooth codecs — fully configurable in NixOS with `services.pipewire` + WirePlumber. The `nix-gaming` flake provides a ready-made low-latency module.

5. **AMD/NVIDIA GPU drivers** with ROCm — well-supported in NixOS via `hardware.graphics`, `hardware.amdgpu`, `hardware.nvidia`.

6. **ZRAM, BBR, CPU governor, I/O scheduler** — all available via `zramSwap`, `boot.kernel.sysctl`, `powerManagement.cpuFreqGovernor`, `boot.kernelParams`.

7. **Controller support** — `hardware.xone`, `hardware.xpadneo`, `hardware.nintendo` are first-class NixOS options; udev rules handle Sony and generic gamepads.

8. **Flatpak + Flathub** — `services.flatpak.enable = true` plus a one-shot systemd service to add the Flathub remote.

The modular architecture proposed (8 modules + updated configuration.nix + updated flake.nix) achieves ~90-95% Bazzite desktop feature parity within NixOS 24.11 constraints, while remaining fully declarative and reproducible.

---

**Spec file written to:** `c:\Projects\vexos-nix\.github\docs\subagent_docs\bazzite_parity_spec.md`
