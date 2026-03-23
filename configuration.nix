{ config, pkgs, ... }:

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
  # networking.networkmanager is managed in modules/network.nix

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
      "audio"     # for raw ALSA access (optional alongside PipeWire)
      "input"     # for controller/udev hidraw access
      "plugdev"   # for USB device access (gamepads, peripherals)
    ];
  };

  # ---------- System packages (base) ----------
  environment.systemPackages = with pkgs; [
    vim
    git
    curl
    wget
    htop
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

  # ---------- Unfree packages (required for Steam, NVIDIA, proton-ge-bin) ----------
  nixpkgs.config.allowUnfree = true;

  # ---------- State version ----------
  # This value determines the NixOS release from which the default
  # settings for stateful data (like file locations) were taken.
  # Do NOT change this after initial install — it stays at the version
  # NixOS was first installed with, regardless of nixpkgs channel upgrades.
  system.stateVersion = "24.11";
}
