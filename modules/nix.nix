# modules/nix.nix
# Nix daemon configuration: flakes, binary caches, GC, store optimisation,
# and daemon scheduling. Applies to all roles.
#
# Also installs /run/current-system/sw/bin/vexos-update (pkgs/vexos-update/) —
# the canonical cache-safe update script used by both `just update` and the
# Up GUI app. Both tools run the same logic so the behaviour is identical
# regardless of how the user triggers an update.
{ config, pkgs, lib, ... }:
let
  cfg = config.vexos.attic;
in
{
  # ── Attic client options ──────────────────────────────────────────────────
  # Configure the project's own Attic binary cache as a substituter so that
  # every host fetches pre-built custom packages (portbook, cockpit-navigator,
  # cockpit-file-sharing, etc.) instead of rebuilding them locally.
  #
  # Usage in a host or server-services.nix:
  #   vexos.attic.cacheUrl  = "http://myserver:8400/vexos";
  #   vexos.attic.publicKey = "vexos-attic:AbCdEf...==";
  #
  # Retrieve the public key from the server with:
  #   attic cache info vexos
  options.vexos.attic = {
    cacheUrl = lib.mkOption {
      type = lib.types.nullOr lib.types.str;
      default = null;
      example = "http://attic.local:8400/vexos";
      description = ''
        URL of the Attic binary cache (including cache name).
        When set, every host uses it as an additional substituter.
        Leave null to disable (default).
      '';
    };

    publicKey = lib.mkOption {
      type = lib.types.str;
      default = "";
      example = "vexos-attic:AbCdEf1234567890AAAAAAA==";
      description = ''
        Ed25519 public key for the Attic cache, as printed by `attic cache info`.
        Required when vexos.attic.cacheUrl is set.
      '';
    };
  };

  config = {
    assertions = lib.mkIf (cfg.cacheUrl != null) [
      {
        assertion = cfg.publicKey != "";
        message = ''
          vexos.attic.publicKey must be set when vexos.attic.cacheUrl is configured.
          Retrieve it from the server with: attic cache info vexos
        '';
      }
    ];

    nix.settings = {
      experimental-features = [ "nix-command" "flakes" ];

      # Trust wheel group users to use additional substituters and caches.
      # Security note: trusted-users can specify arbitrary --substituters on the
      # nix CLI, including untrusted third-party caches. This is acceptable in
      # single-operator and homelab scenarios where every wheel user is the owner.
      # On multi-tenant servers (shared hosting, CI builders) consider restricting
      # to just "root" and managing caches declaratively via nix.settings.substituters:
      #   nix.settings.trusted-users = lib.mkForce [ "root" ];
      trusted-users = [ "root" "@wheel" ];

      # Deduplicate identical files in the store (saves significant disk space)
      auto-optimise-store = true;

      # Binary caches — fetch pre-built derivations instead of compiling locally.
      substituters = [
        "https://cache.nixos.org"
      ] ++ lib.optional (cfg.cacheUrl != null) cfg.cacheUrl;
      trusted-public-keys = [
        "cache.nixos.org-1:6NCHdD59X431o0gWypbMrAURkbJ16ZPMQFGspcDShjY="
      ] ++ lib.optional (cfg.publicKey != "") cfg.publicKey;

      # Build concurrency — 1 job at a time, each using all available cores.
      # Prevents OOM on low-RAM machines; raise max-jobs on beefy hardware.
      max-jobs = lib.mkDefault 1;
      cores = 0; # 0 = auto-detect (uses all cores for the single active job)

      # Automatically free store space during builds:
      #   min-free: start GC when free store space drops below this (bytes)
      #   max-free: stop GC once free store space reaches this
      min-free = 1073741824; # 1 GiB
      max-free = 5368709120; # 5 GiB

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

    # ── vexos-update ─────────────────────────────────────────────────────────
    # Cache-safe update script installed system-wide.  Both `just update` and
    # the Up GUI app call this instead of raw `nix flake update && nixos-rebuild`
    # so the hold/rollback logic is identical regardless of how the update is
    # triggered.  Implementation lives in pkgs/vexos-update/ (writeShellApplication
    # shellchecks it at build time) rather than embedded here.
    environment.systemPackages = [
      pkgs.vexos.vexos-update
    ];
  }; # end config
}
