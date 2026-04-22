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
