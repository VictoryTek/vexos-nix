{ config, pkgs, lib, ... }:

{
  imports = [
    ./modules/gnome.nix
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
  ];

  # ---------- Bootloader ----------
  networking.hostName = lib.mkDefault "vexos";

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
  # Enable Widevine CDM for Brave (DRM-protected streaming: Netflix, Prime, Disney+).
  nixpkgs.config.chromium.enableWidevineCdm = true;

  # ---------- State version ----------
  # Set once at install time — do not change after initial deployment.
  system.stateVersion = "25.11";

  # ---------- Flatpak ----------
  # Exclude apps that are desktop/creative tools or extension management
  # utilities with no place in a media-centre role.
  vexos.flatpak.excludeApps = [
    "org.gimp.GIMP"
    "org.onlyoffice.desktopeditors"  # desktop-only app; clean up if left over from pre-split config
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

  # ---------- Icons ----------
  # Install Kora icon theme system-wide and set it as the default via a
  # system-level dconf database so GNOME picks it up without home-manager.
  environment.systemPackages = with pkgs; [
    bibata-cursors
    kora-icon-theme
    ghostty
    unstable.plex-desktop  # Plex media client (nixpkgs-unstable)
  ];
  programs.dconf.profiles.user.databases = [
    {
      settings."org/gnome/desktop/interface" = {
        cursor-theme = "Bibata-Modern-Classic";
        cursor-size  = lib.gvariant.mkInt32 24;
        icon-theme   = "kora";
        clock-format = "12h";
        color-scheme = "prefer-dark";
        accent-color = "orange";
      };
      # Enable GNOME Shell extensions at the system level (no home-manager on HTPC).
      # gamemode-shell-extension is omitted — programs.gamemode is not enabled here.
      settings."org/gnome/shell" = {
        enabled-extensions = [
          "appindicatorsupport@rgcjonas.gmail.com"
          # "dash-to-dock@micxgx.gmail.com"  # disabled: autohide broken
          "AlphabeticalAppGrid@stuarthayhurst"
          "gnome-ui-tune@itstime.tech"
          "nothing-to-say@extensions.gnome.wouter.bolsterl.ee"
          "steal-my-focus-window@steal-my-focus-window"
          "tailscale-status@maxgallup.github.com"
          "caffeine@patapon.info"
          "restartto@tiagoporsch.github.io"
          "blur-my-shell@aunetx"
          "background-logo@fedorahosted.org"
        ];
        favorite-apps = [
          "brave-browser.desktop"
          "app.zen_browser.zen.desktop"
          "plex-desktop.desktop"  # unstable.plex-desktop nixpkgs package
          "io.freetubeapp.FreeTube.desktop"
          "com.mitchellh.ghostty.desktop"
          "org.gnome.Nautilus.desktop"
          "io.github.up.desktop"
        ];
      };
    }
  ];

}
