# modules/nix.nix
# Nix daemon configuration: flakes, binary caches, GC, store optimisation,
# and daemon scheduling. Applies to all roles.
{ lib, ... }:
{
  nix.settings = {
    experimental-features = [ "nix-command" "flakes" ];

    # Trust wheel group users to use additional substituters and caches
    trusted-users = [ "root" "@wheel" ];

    # Deduplicate identical files in the store (saves significant disk space)
    auto-optimise-store = true;

    # Binary caches — fetch pre-built derivations instead of compiling locally.
    substituters = [
      "https://cache.nixos.org"
    ];
    trusted-public-keys = [
      "cache.nixos.org-1:6NCHdD59X431o0gWypbMrAURkbJ16ZPMQFGspcDShjY="
    ];

    # Build concurrency — 1 job at a time, each using all available cores.
    # Prevents OOM on low-RAM machines; raise max-jobs on beefy hardware.
    max-jobs = lib.mkDefault 1;
    cores = 0; # 0 = auto-detect (uses all cores for the single active job)

    # Automatically free store space during builds:
    #   min-free: start GC when free store space drops below this (bytes)
    #   max-free: stop GC once free store space reaches this
    min-free = 1073741824;   # 1 GiB
    max-free = 5368709120;   # 5 GiB

    # Larger download buffer — prevents "download buffer is full" warnings
    # on slow or unstable connections during large fetches.
    download-buffer-size = 524288000; # 500 MiB

    # Download only — do not keep build-time deps or .drv files after install
    keep-outputs = false;
    keep-derivations = false;
  };

  # Run builds at lower CPU and I/O priority so the system stays usable
  # during a nixos-rebuild.
  nix.daemonCPUSchedPolicy = "idle";
  nix.daemonIOSchedClass = "idle";

  # Required for Steam, NVIDIA drivers, proton-ge-bin, etc.
  nixpkgs.config.allowUnfree = true;
}
