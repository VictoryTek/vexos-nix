{ config, pkgs, lib, ... }:

{
  imports = [
    ./modules/gpu.nix
    ./modules/branding.nix
    ./modules/network.nix
    ./modules/packages-common.nix
    ./modules/system.nix
    ./modules/server       # Optional server services (vexos.server.*.enable)
  ];

  # ---------- Hostname ----------
  networking.hostName = lib.mkDefault "vexos";

  # ---------- Time / Locale ----------
  time.timeZone = "America/Chicago";
  i18n.defaultLocale = "en_US.UTF-8";

  # ---------- Console ----------
  # Load the console font in stage 1 (initrd) before the GPU driver takes over
  # the EFI framebuffer.  Without earlySetup, the DRM framebuffer console
  # initialises at a native resolution with no font loaded, producing a black
  # screen with only a blinking hardware cursor on any attached display.
  console.earlySetup = true;

  # ---------- Branding ----------
  # Reuse the "server" role to pick up existing server/ branding assets
  # (pixmaps, background logos, Plymouth watermark, wallpapers).
  # Override distroName to distinguish from the GUI server role.
  vexos.branding.role     = "server";
  system.nixos.distroName = lib.mkOverride 500 "VexOS Headless Server";

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
