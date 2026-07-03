{ config, pkgs, lib, ... }:

{
  imports = [
    ./modules/gnome.nix
    ./modules/gnome-desktop.nix
    ./modules/remote-desktop.nix    # auto-configures grdctl RDP credentials from /etc/nixos/secrets/rdp-password
    ./modules/gaming.nix             # optional: vexos.features.gaming.enable (bundles gpu-gaming + system-gaming)
    ./modules/development.nix        # optional: vexos.features.development.enable
    ./modules/3d-print.nix           # optional: vexos.features.print3d.enable
    ./modules/virtualization.nix     # optional: vexos.features.virtualization.enable
    ./modules/audio.nix
    ./modules/gpu.nix
    ./modules/flatpak.nix
    ./modules/flatpak-desktop.nix   # desktop-only Flatpak apps via extraApps
    ./modules/network.nix
    ./modules/network-desktop.nix   # samba CLI
    ./modules/packages-common.nix
    ./modules/packages-desktop.nix
    ./modules/branding.nix
    ./modules/branding-display.nix  # wallpapers, GDM logo/dconf
    ./modules/system.nix
    ./modules/system-latest-kernel.nix  # Linux 7.x (linuxPackages_latest)
    ./modules/system-nosleep.nix    # disable sleep/suspend/hibernate on desktop
    ./modules/security.nix          # AppArmor MAC baseline (all roles)
    ./modules/nix.nix
    ./modules/notify.nix
    ./modules/nix-desktop.nix       # 14-day GC retention (workstation standard)
    ./modules/locale.nix
    ./modules/users.nix
    ./modules/appimage.nix
    ./modules/asus-opt.nix
    ./modules/boot-discovery.nix
    ./modules/network-killswitch-service.nix  # toggleable VPN kill switch (just enable-kill-switch)
  ];

  # ---------- Branding ----------
  vexos.branding.role          = "desktop";
  boot.plymouth.enable         = true;   # graphical boot splash

  # ---------- Desktop-only tools ----------
  # gnome-boxes: virtual machine manager — useful on a full desktop, not on HTPC/server.
  # popsicle: USB ISO flasher — desktop-specific, not needed on HTPC/server roles.
  environment.systemPackages = with pkgs; [
    gnome-boxes
    popsicle
  ];

  # ---------- State version ----------
  # This value determines the NixOS release from which the default
  # settings for stateful data (like file locations) were taken.
  # Do NOT change this after initial install — it stays at the version
  # NixOS was first installed with, regardless of nixpkgs channel upgrades.
  system.stateVersion = "25.11";
}
