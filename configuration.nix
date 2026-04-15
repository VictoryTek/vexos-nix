{ config, pkgs, lib, ... }:

{
  imports = [
    ./modules/gnome.nix
    ./modules/gaming.nix
    ./modules/audio.nix
    ./modules/gpu.nix
    ./modules/flatpak.nix
    ./modules/network.nix
    ./modules/development.nix
    ./modules/virtualization.nix
    ./modules/branding.nix
    ./modules/system.nix
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

  # ---------- Users ----------
  users.users.nimda = {
    isNormalUser = true;
    description = "nimda";
    extraGroups = [
      "wheel"
      "networkmanager"
      "gamemode"  # required for GameMode CPU governor control
      "audio"     # for raw ALSA access (optional alongside PipeWire)
      "input"     # for controller/udev hidraw access
      "plugdev"   # for USB device access (gamepads, peripherals)
    ];
  };

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

  # ---------- Permitted insecure packages ----------
  # electron: required by Heroic Games Launcher; permit until nixpkgs ships a newer version.
  nixpkgs.config.permittedInsecurePackages = [
    "electron-36.9.5"
  ];

  # ---------- Desktop-only tools ----------
  # gnome-boxes: virtual machine manager — useful on a full desktop, not on HTPC/server.
  environment.systemPackages = with pkgs; [
    unstable.gnome-boxes
  ];

  # ---------- State version ----------
  # This value determines the NixOS release from which the default
  # settings for stateful data (like file locations) were taken.
  # Do NOT change this after initial install — it stays at the version
  # NixOS was first installed with, regardless of nixpkgs channel upgrades.
  system.stateVersion = "25.11";
}
