{ config, pkgs, lib, ... }:

{
  imports = [
    ./modules/gnome.nix
    ./modules/gnome-htpc.nix
    ./modules/audio.nix
    ./modules/gpu.nix
    ./modules/flatpak.nix
    ./modules/network.nix
    ./modules/network-desktop.nix   # samba CLI
    ./modules/packages-common.nix
    ./modules/packages-desktop.nix
    ./modules/packages-htpc.nix     # GStreamer codecs, VLC, mpv, libcec
    ./modules/branding.nix
    ./modules/branding-display.nix  # wallpapers, GDM logo/dconf
    ./modules/system.nix
    ./modules/system-nosleep.nix    # disable sleep/suspend/hibernate on HTPC
    ./modules/security.nix          # AppArmor MAC baseline (all roles)
    ./modules/nix.nix
    ./modules/nix-desktop.nix       # 14-day GC retention (workstation standard)
    ./modules/locale.nix
    ./modules/users.nix
    ./modules/asus-opt.nix
  ];

  # ---------- State version ----------
  # Set once at install time — do not change after initial deployment.
  system.stateVersion = "25.11";

  # ---------- Flatpak ----------
  # Exclude apps that are desktop/creative tools or extension management
  # utilities with no place in a media-centre role.
  vexos.flatpak.excludeApps = [
    "org.gimp.GIMP"
    "org.onlyoffice.desktopeditors"  # desktop-only app; clean up if left over from pre-split config
    "tv.plex.PlexDesktop"            # Flatpak version; nixpkgs plex-desktop is used instead
  ];

  vexos.flatpak.extraApps = [
    "io.freetubeapp.FreeTube"          # Privacy-respecting YouTube client
    "com.github.unrud.VideoDownloader" # Video downloader
  ];

  # ---------- Branding ----------
  # Override branding.nix's lib.mkDefault "VexOS Desktop" (priority 1000).
  # Using mkOverride 500 so host files can still use plain assignments (priority 100)
  # to set more specific names like "VexOS HTPC AMD" when needed.
  system.nixos.distroName = lib.mkOverride 500 "VexOS HTPC";
  vexos.branding.role  = "htpc";
  boot.plymouth.enable = true;   # graphical boot splash

  # ---------- HTPC-specific packages ----------
  environment.systemPackages = with pkgs; [
    ghostty
    unstable.plex-desktop  # Plex media client (nixpkgs-unstable)
  ];

}
