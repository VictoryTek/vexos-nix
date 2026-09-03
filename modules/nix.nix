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
  cfg  = config.vexos.attic;
  hcfg = config.vexos.harmonia;
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

  # ── Harmonia client options ───────────────────────────────────────────────
  # Same purpose as vexos.attic above, for a Harmonia cache host
  # (modules/server/harmonia.nix). Kept as a separate option pair rather than
  # generalised into one list because vexos.attic.* is already referenced by
  # deployed /etc/nixos files — renaming it would be a breaking change.
  #
  # Unlike Attic, a Harmonia URL has no cache-name path segment: Harmonia
  # serves the host's store at the root.
  #
  # Opt-in, like vexos.attic: both default to off. A Harmonia cache is only
  # useful once a host actually runs the server (vexos.server.harmonia.enable)
  # and is reachable — enabling it fleet-wide by default just makes every
  # rebuild retry an unresolvable substituter.
  #
  # To consume a cache, set BOTH values on the hosts that should use it
  # (host config or server-services.nix):
  #   vexos.harmonia.cacheUrl  = "http://cache:5000";
  #   vexos.harmonia.publicKey = "cache-1:AbCdEf...=";
  #
  # "cache" is a Tailscale MagicDNS name pointed at whichever host currently
  # runs Harmonia; both values are printed by `just harmonia-info` on that host.
  options.vexos.harmonia = {
    cacheUrl = lib.mkOption {
      type = lib.types.nullOr lib.types.str;
      default = null;
      example = "http://cache:5000";
      description = ''
        URL of the Harmonia binary cache (no path segment — Harmonia serves the
        host's store at the root). Resolved over Tailscale MagicDNS, so it works
        from any machine on the tailnet regardless of physical network.
        Leave null to disable (default).
      '';
    };

    publicKey = lib.mkOption {
      type = lib.types.str;
      default = "";
      example = "cache-1:AbCdEf1234567890AAAAAAA==";
      description = ''
        Ed25519 public key for the Harmonia cache, as printed by
        `just harmonia-info` (or read from <signKeyPath>.pub on the cache host).
        Required when vexos.harmonia.cacheUrl is set. Not a secret — safe to
        commit alongside the matching cacheUrl on the hosts that opt in.
      '';
    };
  };

  config = {
    assertions =
      lib.optional (cfg.cacheUrl != null) {
        assertion = cfg.publicKey != "";
        message = ''
          vexos.attic.publicKey must be set when vexos.attic.cacheUrl is configured.
          Retrieve it from the server with: attic cache info vexos
        '';
      }
      ;

    # Harmonia deliberately does NOT assert here. cacheUrl ships with a working
    # default so no host needs configuring, but publicKey can only be filled in
    # after the cache host has generated its key — an assertion would make a
    # fresh checkout unbuildable until then. Instead the substituter is simply
    # not added until the key is present (an unverifiable cache is useless), and
    # the situation is surfaced as a warning.
    warnings = lib.optional (hcfg.cacheUrl != null && hcfg.publicKey == "") ''
      vexos.harmonia.cacheUrl is set to "${hcfg.cacheUrl}" but
      vexos.harmonia.publicKey is empty, so the cache is being ignored.
      Custom kernels and other locally-built packages will be compiled from
      source instead of downloaded.
      Fix: run `just harmonia-info` on the cache host and commit the printed
      publicKey into modules/nix.nix.
    '';

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
      ] ++ lib.optional (cfg.cacheUrl != null) cfg.cacheUrl
        # Only trust Harmonia once its public key is known — see warnings above.
        ++ lib.optional (hcfg.cacheUrl != null && hcfg.publicKey != "") hcfg.cacheUrl;
      trusted-public-keys = [
        "cache.nixos.org-1:6NCHdD59X431o0gWypbMrAURkbJ16ZPMQFGspcDShjY="
      ] ++ lib.optional (cfg.publicKey != "") cfg.publicKey
        ++ lib.optional (hcfg.publicKey != "") hcfg.publicKey;

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

    # ── vexos-update / vexos-deploy ──────────────────────────────────────────
    # Cache-safe update script installed system-wide.  Both `just update` and
    # the Up GUI app call this instead of raw `nix flake update && nixos-rebuild`
    # so the hold/rollback logic is identical regardless of how the update is
    # triggered.  Implementation lives in pkgs/vexos-update/ (writeShellApplication
    # shellchecks it at build time) rather than embedded here.  Called directly
    # via callPackage (not through the pkgs.vexos overlay namespace) so this
    # universal module — applied to every role, including vanilla, which does
    # not include customPkgsOverlayModule — stays overlay-independent.
    #
    # vexos-deploy is the config-only counterpart called by `just deploy` — it
    # pulls the latest vexos-nix commit while holding every other flake input
    # at its current revision, which is the escape hatch vexos-update points at
    # when it reports VEXOS_CACHE_BLOCK.  Same packaging rationale as above.
    environment.systemPackages = [
      (pkgs.callPackage ../pkgs/vexos-update { })
      (pkgs.callPackage ../pkgs/vexos-deploy { })
    ];
  }; # end config
}
