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
    ./modules/branding.nix
    ./modules/branding-display.nix  # wallpapers, GDM logo/dconf
    ./modules/system.nix
    ./modules/impermanence.nix
  ];

  # ---------- Bootloader ----------
  # NOT configured here — bootloader is host-specific hardware configuration.
  # Set it once in your local /etc/nixos/flake.nix using the bootloaderModule
  # section provided in the template (template/etc-nixos-flake.nix).

  # ---------- Networking (base) ----------
  networking.hostName = lib.mkDefault "vexos";
  # networking.networkmanager is managed in modules/network.nix

  # ---------- Time / Locale ----------
  time.timeZone = "America/Chicago";
  i18n.defaultLocale = "en_US.UTF-8";

  # ---------- Branding ----------
  vexos.branding.role  = "stateless";
  boot.plymouth.enable = true;   # graphical boot splash

  # ---------- Users ----------
  users.users.nimda = {
    isNormalUser    = true;
    description     = "nimda";
    # Fallback password — only used when no stateless-user-override.nix exists in
    # /etc/nixos.  migrate-to-stateless.sh reads the pre-migration hash from
    # /etc/shadow and writes it to that override file so the original password
    # carries forward.  stateless-setup.sh prompts for one.  "vexos" is only
    # seen on a completely unconfigured first run where neither script ran.
    initialPassword = "vexos";
    extraGroups = [
      "wheel"
      "networkmanager"
      "audio"     # for raw ALSA access (optional alongside PipeWire)
    ];
  };

  # ---------- Impermanence ----------
  # Enable tmpfs-rooted ephemeral filesystem for the stateless role.
  # / is wiped on every reboot; only /nix and /persistent survive.
  # Filesystem impermanence: / is mounted as tmpfs by this module.
  # Run scripts/stateless-setup.sh to format the disk before first deploy.
  vexos.impermanence.enable = true;

  # ---------- Nix settings ----------
  nix.settings = {
    experimental-features = [ "nix-command" "flakes" ];

    # Trust wheel group users to use additional substituters and caches
    trusted-users = [ "root" "@wheel" ];

    # Deduplicate identical files in the store (saves significant disk space)
    auto-optimise-store = true;

    # Binary caches — fetch pre-built derivations instead of compiling locally.
    # Declaring caches here (trusted system config) avoids the interactive
    # "do you want to allow this substituter?" prompt that nixConfig in a flake
    # triggers. The flake's nixConfig block has been removed; these settings
    # cover the same caches unconditionally.
    substituters = [
      "https://cache.nixos.org"          # Official NixOS cache — always required
    ];
    trusted-public-keys = [
      "cache.nixos.org-1:6NCHdD59X431o0gWypbMrAURkbJ16ZPMQFGspcDShjY="
    ];

    # Build concurrency — 1 job at a time, each using half the available cores.
    # Prevents OOM on low-RAM machines; raise max-jobs on beefy hardware.
    max-jobs = 1;
    cores = 0; # 0 = auto-detect (uses all cores for the single active job)

    # Nix daemon process priorities — keeps the system responsive during builds
    # without killing the build on RAM-constrained hosts.
    # (requires systemd; ignored on non-Linux)

    # Automatically free store space during builds:
    #   min-free: start GC when free store space drops below this (bytes)
    #   max-free: stop GC once free store space reaches this
    min-free = 1073741824;   # 1 GiB
    max-free = 5368709120;   # 5 GiB

    # Larger download buffer — prevents "download buffer is full" warnings
    # on slow or unstable connections during large fetches (e.g. Steam).
    download-buffer-size = 524288000; # 500 MiB

    # Download only — do not keep build-time deps or .drv files after install
    keep-outputs = false;
    keep-derivations = false;
  };

  # Nix daemon: run builds at lower CPU and I/O priority so the
  # desktop stays usable during a nixos-rebuild.
  nix.daemonCPUSchedPolicy = "idle";
  nix.daemonIOSchedClass = "idle";

  # Automatic store garbage-collection: weekly, remove generations older than 7 days.
  nix.gc = {
    automatic = true;
    dates = "weekly";
    options = "--delete-older-than 7d";
  };

  # Hard-link identical files in the store after every build
  # (complements auto-optimise-store for any files added between GC runs).
  nix.optimise = {
    automatic = true;
    dates = [ "weekly" ];
  };

  # ---------- Unfree packages (required for Steam, NVIDIA, proton-ge-bin) ----------
  nixpkgs.config.allowUnfree = true;

  # ---------- System packages ----------
  # tor-browser: installed system-wide (not via Home Manager) so torbrowser.desktop
  # lands in /run/current-system/sw/share/applications/ and is always visible to
  # GNOME regardless of Home Manager activation timing on the fresh tmpfs home.
  #
  # gimp-hidden: a minimal NoDisplay=true desktop entry for org.gimp.GIMP.
  # Placed in the Nix system profile share dir, which XDG_DATA_DIRS searches
  # BEFORE /var/lib/flatpak/exports/share (added via lib.mkAfter in flatpak.nix).
  # The first match in the search path wins, so GNOME hides the GIMP Flatpak
  # from the app grid immediately at session start — before Home Manager writes
  # its own ~/.local/share/applications override.
  environment.systemPackages = [
    pkgs.tor-browser
    (pkgs.writeTextFile {
      name        = "gimp-hidden";
      destination = "/share/applications/org.gimp.GIMP.desktop";
      text        = ''
        [Desktop Entry]
        Name=GIMP
        Type=Application
        NoDisplay=true
      '';
    })
  ];

  # ---------- Flatpak ----------
  # Prevent GIMP from being installed on stateless. It is never in
  # defaultApps but may be present from a manual install or prior session.
  # Desktop-role extras are also excluded so they are actively uninstalled
  # if this machine was previously running the desktop configuration and
  # /var/lib/flatpak (persisted by impermanence) carries stale installs.
  vexos.flatpak.excludeApps = [
    "org.gimp.GIMP"
    # Desktop-role gaming / utility flatpaks
    "org.prismlauncher.PrismLauncher"
    "com.vysp3r.ProtonPlus"
    "net.lutris.Lutris"
    # Desktop-role dev / misc flatpaks
    "io.github.pol_rivero.github-desktop-plus"
    "com.ranfdev.DistroShelf"
  ];

  # ---------- State version ----------
  # This value determines the NixOS release from which the default
  # settings for stateful data (like file locations) were taken.
  # Do NOT change this after initial install — it stays at the version
  # NixOS was first installed with, regardless of nixpkgs channel upgrades.
  system.stateVersion = "25.11";
}
