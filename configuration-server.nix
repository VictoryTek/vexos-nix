{ config, pkgs, lib, ... }:

{
  imports = [
    ./modules/gnome.nix
    ./modules/gnome-server.nix
    ./modules/audio.nix
    ./modules/gpu.nix
    ./modules/branding.nix
    ./modules/branding-display.nix  # wallpapers, GDM logo/dconf
    ./modules/flatpak.nix
    ./modules/network.nix
    ./modules/network-desktop.nix   # samba CLI
    ./modules/packages-common.nix
    ./modules/packages-desktop.nix
    ./modules/system.nix
    ./modules/system-nosleep.nix    # disable sleep/suspend/hibernate on server
    ./modules/security.nix          # AppArmor MAC baseline (all roles)
    ./modules/security-server.nix   # auditd + server audit ruleset
    ./modules/server       # Optional server services (vexos.server.*.enable)
    ./modules/zfs-server.nix
    ./modules/nix.nix
    ./modules/nix-server.nix        # 30-day GC retention (production server standard)
    ./modules/locale.nix
    ./modules/users.nix
  ];

  # ---------- Branding ----------
  # Override branding.nix's lib.mkDefault "VexOS Desktop" (priority 1000).
  system.nixos.distroName = lib.mkOverride 500 "VexOS Server";
  vexos.branding.role  = "server";
  boot.plymouth.enable = true;   # graphical boot splash

  # ---------- State version ----------
  # Set once at install time — do not change after initial deployment.
  system.stateVersion = "25.11";

  # ---------- Flatpak ----------
  # GIMP is not desired on a server role.
  vexos.flatpak.excludeApps = [
    "org.gimp.GIMP"
  ];

  # ---------- Server role placeholder ----------
  # This configuration is intentionally minimal. Add server-specific
  # services, firewall rules, and hardening here when fleshing out.
}
