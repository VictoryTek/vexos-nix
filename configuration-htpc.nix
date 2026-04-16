{ config, pkgs, lib, ... }:

{
  imports = [
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

  # ---------- State version ----------
  # Set once at install time — do not change after initial deployment.
  system.stateVersion = "25.11";

  # ---------- Flatpak ----------
  # Exclude apps that are desktop/creative tools or extension management
  # utilities with no place in a media-centre role.
  vexos.flatpak.excludeApps = [
    "org.gimp.GIMP"
    "com.ranfdev.DistroShelf"
    "com.mattjakeman.ExtensionManager"  # puzzle-piece icon; not needed on HTPC
    "com.vysp3r.ProtonPlus"             # Wine/Proton manager; no gaming role on HTPC
    "net.lutris.Lutris"                 # gaming launcher; not applicable on a streaming HTPC
    "org.prismlauncher.PrismLauncher"   # Minecraft launcher; not needed
    "io.github.pol_rivero.github-desktop-plus" # Desktop Plus; not useful for streaming HTPC
    "com.github.wwmm.easyeffects" # removed — not needed
  ];

  vexos.flatpak.extraApps = [
    "io.freetubeapp.FreeTube"          # Privacy-respecting YouTube client
    "tv.plex.PlexDesktop"              # Plex media client
    "com.github.unrud.VideoDownloader" # Video downloader
  ];

  # ---------- Branding ----------
  # Override branding.nix's lib.mkDefault "VexOS Desktop" (priority 1000).
  # Using mkOverride 500 so host files can still use plain assignments (priority 100)
  # to set more specific names like "VexOS HTPC AMD" when needed.
  system.nixos.distroName = lib.mkOverride 500 "VexOS HTPC";

  # ---------- Icons ----------
  # Install Kora icon theme system-wide and set it as the default via a
  # system-level dconf database so GNOME picks it up without home-manager.
  environment.systemPackages = with pkgs; [
    kora-icon-theme
    ghostty
  ];
  programs.dconf.profiles.user.databases = [
    {
      settings."org/gnome/desktop/interface" = {
        icon-theme   = "kora";
        clock-format = "12h";
      };
      # Enable GNOME Shell extensions at the system level (no home-manager on HTPC).
      # gamemode-shell-extension is omitted — programs.gamemode is not enabled here.
      settings."org/gnome/shell" = {
        enabled-extensions = [
          "appindicatorsupport@rgcjonas.gmail.com"
          "dash-to-dock@micxgx.gmail.com"
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
          "app.zen_browser.zen.desktop"
          "brave-browser.desktop"
          "tv.plex.PlexDesktop.desktop"
          "io.freetubeapp.FreeTube.desktop"
          "com.mitchellh.ghostty.desktop"
          "org.gnome.Nautilus.desktop"
          "io.github.up.desktop"
        ];
      };
    }
  ];

  # ---------- HTPC role placeholder ----------
  # This configuration is intentionally minimal. Add media centre services,
  # codec support, remote control input, and display configuration here
  # when fleshing out.
}
