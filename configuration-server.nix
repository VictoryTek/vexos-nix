{ config, pkgs, lib, ... }:

{
  imports = [
    ./modules/gnome.nix
    ./modules/audio.nix
    ./modules/gpu.nix
    ./modules/branding.nix
    ./modules/flatpak.nix
    ./modules/network.nix
    ./modules/packages.nix
    ./modules/system.nix
    ./modules/server       # Optional server services (vexos.server.*.enable)
  ];

  # ---------- Bootloader ----------
  networking.hostName = lib.mkDefault "vexos";

  # ---------- Time / Locale ----------
  time.timeZone = "America/Chicago";
  i18n.defaultLocale = "en_US.UTF-8";

  # ---------- Branding ----------
  # Override branding.nix's lib.mkDefault "VexOS Desktop" (priority 1000).
  system.nixos.distroName = lib.mkOverride 500 "VexOS Server";
  vexos.branding.role = "server";

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

    download-buffer-size = 524288000; # 500 MiB

    keep-outputs = false;
    keep-derivations = false;
  };

  nix.daemonCPUSchedPolicy = "idle";
  nix.daemonIOSchedClass = "idle";

  nix.gc = {
    automatic = true;
    dates = "weekly";
    options = "--delete-older-than 7d";
  };

  nix.optimise = {
    automatic = true;
    dates = [ "weekly" ];
  };

  # ---------- Nixpkgs ----------
  nixpkgs.config.allowUnfree = true;

  # ---------- State version ----------
  # Set once at install time — do not change after initial deployment.
  system.stateVersion = "25.11";

  # ---------- Flatpak ----------
  # Exclude apps that are desktop/gaming/creative tools with no place
  # in a server role.
  vexos.flatpak.excludeApps = [
    "org.gimp.GIMP"
    "com.ranfdev.DistroShelf"
    "com.mattjakeman.ExtensionManager"
    "com.vysp3r.ProtonPlus"
    "net.lutris.Lutris"
    "org.prismlauncher.PrismLauncher"
    "io.github.pol_rivero.github-desktop-plus"
    "org.onlyoffice.desktopeditors"
  ];

  # ---------- Server role placeholder ----------
  # This configuration is intentionally minimal. Add server-specific
  # services, firewall rules, and hardening here when fleshing out.
}
