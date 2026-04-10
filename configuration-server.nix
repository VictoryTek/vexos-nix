{ config, pkgs, lib, ... }:

{
  imports = [
    # TODO: flesh out server-specific modules (e.g. services, hardening)
    ./modules/network.nix
    ./modules/packages.nix
    ./modules/system.nix
  ];

  # ---------- Bootloader ----------
  networking.hostName = lib.mkDefault "vexos-server";

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

  # ---------- Server role placeholder ----------
  # This configuration is intentionally minimal. Add server-specific
  # services, firewall rules, and hardening here when fleshing out.
}
