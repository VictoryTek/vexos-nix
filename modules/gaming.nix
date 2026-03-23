# modules/gaming.nix
# Gaming stack: Steam, Proton, Lutris, Heroic, Bottles, MangoHud, Gamescope,
# GameMode, Wine/Proton tooling, OBS VkCapture, Distrobox, Input Remapper.
{ config, pkgs, lib, ... }:
{
  # ── Steam ─────────────────────────────────────────────────────────────────
  # programs.steam.enable also enables hardware.steam-hardware.enable automatically.
  programs.steam = {
    enable = true;
    remotePlay.openFirewall = true;
    dedicatedServer.openFirewall = false;
    gamescopeSession.enable = true; # Gamescope session for Steam gaming mode

    # Proton-GE as an additional compatibility tool (unfree)
    extraCompatPackages = with pkgs; [
      proton-ge-bin
    ];
  };

  # ── Gamescope micro-compositor (HDR, VRR, frame limiting) ─────────────────
  programs.gamescope = {
    enable = true;
    capSysNice = true; # lets gamescope renice itself for lower latency
  };

  # ── GameMode — performance daemon (CPU/GPU boost on game start) ───────────
  programs.gamemode = {
    enable = true;
    settings = {
      general = {
        renice = 10;
        inhibit_screensaver = 0; # avoids error log when no screensaver is installed
      };
      gpu = {
        apply_gpu_optimisations = "accept-responsibility";
        gpu_device = 0;
        amd_performance_level = "high";
      };
    };
  };

  # ── OBS Studio ───────────────────────────────────────────────────────────
  # Use programs.obs-studio to properly wire the OBS VkCapture plugin via NixOS.
  programs.obs-studio = {
    enable = true;
    plugins = [ pkgs.obs-studio-plugins.obs-vkcapture ];
  };

  # ── Gaming utilities ──────────────────────────────────────────────────────
  environment.systemPackages = with pkgs; [
    # Performance overlay — enable per-game with: mangohud %command% in Steam launch options
    mangohud

    # Game launchers
    lutris          # multi-platform launcher (Proton/Wine)
    heroic          # Epic / GOG / Amazon Games launcher
    bottles         # Wine prefix manager

    # Proton / Wine tooling
    protonup-qt     # GUI for managing Proton-GE and other runners
    protontricks    # winetricks wrapper for Steam games
    umu-launcher    # Proton launcher for non-Steam games

    # Display / overlay
    vkbasalt        # Vulkan post-processing layer (CAS, FXAA, etc.)

    # Wine (Staging + Wow64 multilib)
    wineWowPackages.stagingFull

    # Disk / prefix maintenance
    duperemove      # deduplicates Wine prefix content

    # Container tooling (Distrobox for running other distro environments)
    distrobox
    podman

    # Input remapping
    input-remapper
  ];

  # ── Input Remapper daemon ─────────────────────────────────────────────────
  # Use the NixOS service module instead of a manual systemd service definition
  # to avoid conflicts with the packaged service file.
  services.input-remapper.enable = true;
}
