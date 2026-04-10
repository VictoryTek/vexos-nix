{ config, pkgs, lib, ... }:

{
  imports = [
    # TODO: flesh out HTPC-specific modules (e.g. media apps, Kodi, codecs)
    ./modules/gnome.nix
    ./modules/audio.nix
    ./modules/gpu.nix
    ./modules/flatpak.nix
    ./modules/network.nix
    ./modules/packages.nix
    ./modules/branding.nix
    ./modules/system.nix
  ];

  # ---------- Bootloader ----------
  networking.hostName = lib.mkDefault "vexos-htpc";

  # ---------- Time / Locale ----------
  time.timeZone = "America/Chicago";
  i18n.defaultLocale = "en_US.UTF-8";

  # ---------- Users ----------
  users.users.nimda = {
    isNormalUser = true;
    description = "nimda";
    extraGroups = [
      "wheel"
      "networkmanager"
      "audio"
    ];
  };

  # ---------- Nix settings ----------
  nix.settings = {
    experimental-features = [ "nix-command" "flakes" ];
    trusted-users = [ "root" "@wheel" ];
    auto-optimise-store = true;
    substituters = [
      "https://cache.nixos.org"
    ];
    trusted-public-keys = [
      "cache.nixos.org-1:6NCHdD59X431o0gWypbMrAURkbJ16ZPMQFGspcDShjY="
    ];
    max-jobs = 1;
    cores = 0;
    min-free = 1073741824;   # 1 GiB
    max-free = 5368709120;   # 5 GiB
  };

  # ---------- HTPC role placeholder ----------
  # This configuration is intentionally minimal. Add media centre services,
  # codec support, remote control input, and display configuration here
  # when fleshing out.
}
