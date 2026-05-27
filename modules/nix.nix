# modules/nix.nix
# Nix daemon configuration: flakes, binary caches, GC, store optimisation,
# and daemon scheduling. Applies to all roles.
#
# Also installs /run/current-system/sw/bin/vexos-update — the canonical
# cache-safe update script used by both `just update` and the Up GUI app.
# Both tools run the same logic so the behaviour is identical regardless of
# how the user triggers an update.
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
      type    = lib.types.nullOr lib.types.str;
      default = null;
      example = "http://attic.local:8400/vexos";
      description = ''
        URL of the Attic binary cache (including cache name).
        When set, every host uses it as an additional substituter.
        Leave null to disable (default).
      '';
    };

    publicKey = lib.mkOption {
      type    = lib.types.str;
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

  # ── vexos-update ─────────────────────────────────────────────────────────
  # Cache-safe update script installed system-wide.  Both `just update` and
  # the Up GUI app call this instead of raw `nix flake update && nixos-rebuild`
  # so the hold/rollback logic is identical regardless of how the update is
  # triggered.
  #
  # Exit codes:
  #   0  — update applied successfully (all packages were in binary cache)
  #   2  — cache miss (flake.lock restored; system unchanged; retry later)
  #   1  — other error (bad variant, nix eval failure, etc.)
  #
  # Stdout protocol for Up:
  #   Lines prefixed "VEXOS_CACHE_MISS:" → cache miss; list the blocked pkgs.
  #   All other lines are forwarded verbatim to the build log view.
  environment.systemPackages = [
    (pkgs.writeShellScriptBin "vexos-update" ''
      set -euo pipefail

      VARIANT=$(cat /etc/nixos/vexos-variant 2>/dev/null || true)
      if [ -z "$VARIANT" ]; then
        echo "error: /etc/nixos/vexos-variant not found. Run nixos-rebuild once first." >&2
        exit 1
      fi

      # Back up current lock before touching anything.
      cp /etc/nixos/flake.lock /etc/nixos/flake.lock.bak

      echo "Updating flake inputs..."
      nix --extra-experimental-features "nix-command flakes" \
        flake update --flake path:/etc/nixos

      echo "Checking binary cache for new packages..."
      DRY=$(nixos-rebuild dry-build \
        --flake path:/etc/nixos#"$VARIANT" 2>&1 || true)

      # Extract names from the "will be built:" section of dry-build output.
      # Strip the /nix/store/<hash>- prefix so names are readable.
      # Filter out NixOS system-level derivations that are ALWAYS built locally
      # and take under a second (symlink forest, activation scripts, unit files,
      # bootloader config, initrd, kernel, home-manager glue, AppArmor profile
      # directories, /etc population, environment files, etc.) — these are not
      # source compiles; they're local assembly that cascades from real builds.
      SOURCE_BUILDS=$(printf '%s\n' "$DRY" \
        | awk '/will be built:/{p=1;next} /will be fetched:|^building |^[^ \t]/{p=0} p && /\/nix\/store\//{sub(/.*\/nix\/store\/[a-z0-9]+-/,""); print}' \
        | grep -Ev '^(nixos-system-|system-units|system-path|etc-nixos|etc-|etc\.drv$|unit-|activation-script|specialisation-|install-bootloader|loader-|grub-|extlinux-|initrd|kernel|stage-[12]-|home-manager-|ld-library-path|X-Restart-Triggers-|user-units|set-environment|dbus-1\.drv$|abstractions-|apparmor\.d\.drv$)' \
        || true)

      if [ -n "$SOURCE_BUILDS" ]; then
        echo ""
        echo "VEXOS_CACHE_MISS: The following packages are not yet in the binary cache"
        echo "VEXOS_CACHE_MISS: and would need to be compiled from source:"
        printf '%s\n' "$SOURCE_BUILDS" | sed 's/^/VEXOS_CACHE_MISS:   /'
        echo "VEXOS_CACHE_MISS:"
        echo "VEXOS_CACHE_MISS: flake.lock restored. Run vexos-update again in a few"
        echo "VEXOS_CACHE_MISS: hours once cache.nixos.org has built these packages."
        cp /etc/nixos/flake.lock.bak /etc/nixos/flake.lock
        rm -f /etc/nixos/flake.lock.bak
        exit 2
      fi

      rm -f /etc/nixos/flake.lock.bak
      echo "All packages available in binary cache — applying update..."
      nixos-rebuild switch \
        --flake path:/etc/nixos#"$VARIANT" \
        --print-build-logs
    '')
  ];
  }; # end config
}
