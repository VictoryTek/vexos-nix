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

  # ── Gaming utilities ──────────────────────────────────────────────────────
  environment.systemPackages = with pkgs; [
    # Performance overlay — enable per-game with: mangohud %command% in Steam launch options
    ## mangohud

    # Proton / Wine tooling
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

    # NOTE: lutris and ProtonPlus are installed via Flatpak
    # (net.lutris.Lutris and com.vysp3r.ProtonPlus in modules/flatpak.nix).
  ];

  # ── Input Remapper daemon ─────────────────────────────────────────────────
  # Use the NixOS service module instead of a manual systemd service definition
  # to avoid conflicts with the packaged service file.
  ##services.input-remapper.enable = true;

  # ── Controllers ───────────────────────────────────────────────────────────
  # Gamepad and controller support: Xbox (xone/xpadneo), Nintendo Switch,
  # Sony DualShock/DualSense, and generic HID udev rules.

  # Xbox One / Series S|X USB dongle and wired controllers
  hardware.xone.enable = true;
  # Xbox wireless controllers via Bluetooth
  hardware.xpadneo.enable = true;

  # Nintendo Switch Pro Controller / Joy-Cons; Sony controllers (kernel drivers)
  boot.kernelModules = [ "hid_nintendo" "hid_sony" ];

  services.udev.extraRules = ''
    # ── Sony DualShock 4 (USB) ──
    KERNEL=="hidraw*", ATTRS{idVendor}=="054c", ATTRS{idProduct}=="05c4", MODE="0660", GROUP="input"
    KERNEL=="hidraw*", ATTRS{idVendor}=="054c", ATTRS{idProduct}=="09cc", MODE="0660", GROUP="input"
    # ── Sony DualSense (USB) ──
    KERNEL=="hidraw*", ATTRS{idVendor}=="054c", ATTRS{idProduct}=="0ce6", MODE="0660", GROUP="input"
    # ── Sony DualSense Edge (USB) ──
    KERNEL=="hidraw*", ATTRS{idVendor}=="054c", ATTRS{idProduct}=="0df2", MODE="0660", GROUP="input"
    # ── Sony controllers via Bluetooth ──
    KERNEL=="hidraw*", SUBSYSTEM=="hidraw", ATTRS{idVendor}=="054c", MODE="0660", GROUP="input"
    # ── 8BitDo Ultimate Bluetooth ──
    SUBSYSTEM=="input", ATTRS{idVendor}=="2dc8", ATTRS{idProduct}=="3106", MODE="0660", GROUP="input"
    # ── Generic: allow all input devices for the input group ──
    SUBSYSTEM=="input", MODE="0660", GROUP="input"
  '';
}
