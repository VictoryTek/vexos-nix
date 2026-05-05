{ config, pkgs, lib, ... }:

{
  imports = [
    ./modules/gnome.nix
    ./modules/gnome-desktop.nix
    ./modules/gaming.nix
    ./modules/audio.nix
    ./modules/gpu.nix
    ./modules/gpu-gaming.nix        # 32-bit libs, vulkan-tools, mesa-demos
    ./modules/flatpak.nix
    ./modules/flatpak-desktop.nix   # desktop-only Flatpak apps via extraApps
    ./modules/network.nix
    ./modules/network-desktop.nix   # samba CLI
    ./modules/packages-common.nix
    ./modules/packages-desktop.nix
    ./modules/development.nix
    ./modules/virtualization.nix
    ./modules/branding.nix
    ./modules/branding-display.nix  # wallpapers, GDM logo/dconf
    ./modules/system.nix
    ./modules/system-gaming.nix     # gaming kernel params, THP, SCX
    ./modules/system-nosleep.nix    # disable sleep/suspend/hibernate on desktop
    ./modules/security.nix          # AppArmor MAC baseline (all roles)
    ./modules/nix.nix
    ./modules/nix-desktop.nix       # 14-day GC retention (workstation standard)
    ./modules/locale.nix
    ./modules/users.nix
  ];

  # ---------- Branding ----------
  vexos.branding.role          = "desktop";
  boot.plymouth.enable         = true;   # graphical boot splash

  # ---------- Desktop-only tools ----------
  # gnome-boxes: virtual machine manager — useful on a full desktop, not on HTPC/server.
  # popsicle: USB ISO flasher — desktop-specific, not needed on HTPC/server roles.
  environment.systemPackages = with pkgs; [
    unstable.gnome-boxes
    popsicle
  ];

  # ---------- State version ----------
  # This value determines the NixOS release from which the default
  # settings for stateful data (like file locations) were taken.
  # Do NOT change this after initial install — it stays at the version
  # NixOS was first installed with, regardless of nixpkgs channel upgrades.
  system.stateVersion = "25.11";
}
