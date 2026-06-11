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
    # triggered.
    #
    # Exit codes:
    #   0  — update applied (some fast local builds may have occurred)
    #   2  — heavy build blocked (flake.lock restored; system unchanged; retry later)
    #   1  — other error (bad variant, nix eval failure, etc.)
    #
    # Stdout protocol for Up:
    #   Lines prefixed "VEXOS_CACHE_BLOCK:"  → hard blocker; lock restored.
    #   Lines prefixed "VEXOS_LOCAL_BUILD:"  → informational; non-heavy local build proceeding.
    #   Legacy: "VEXOS_CACHE_LOCAL_OK:" was the prior allowed-list prefix (retired).
    #   Legacy: "VEXOS_CACHE_MISS:" was the original single-channel prefix (retired).
    #   All other lines are forwarded verbatim to the build log view.
    environment.systemPackages = [
      (pkgs.writeShellScriptBin "vexos-update" ''
        set -euo pipefail

        VARIANT=$(cat /etc/nixos/vexos-variant 2>/dev/null || true)
        if [ -z "$VARIANT" ]; then
          echo "error: /etc/nixos/vexos-variant not found. Run nixos-rebuild once first." >&2
          exit 1
        fi

        # ── Ensure /etc/nixos is a git repo (one-time migration for existing installs) ──
        # git+file:// URIs only copy tracked files; untracked secrets/ never enter the
        # world-readable Nix store.  New installs get this from the installer; existing
        # installs are migrated here on the first run of vexos-update after upgrading.
        if ! git -C /etc/nixos rev-parse --git-dir &>/dev/null 2>&1; then
          echo "Initializing /etc/nixos as a git repository (one-time setup)..."
          cat > /etc/nixos/.gitignore << 'GITIGNORE'
secrets/
hardware-configuration.nix
*.bak
vexos-variant
kernel-install-override.nix
stateless-user-override.nix
GITIGNORE
          git -C /etc/nixos init -q
          git -C /etc/nixos add .
          git -C /etc/nixos \
            -c user.email="vexos@localhost" \
            -c user.name="VexOS" \
            commit -q -m "chore: track /etc/nixos configuration"
          echo "Done — secrets/ is now excluded from the Nix store on all future rebuilds."
        fi

        # ── Kernel install override auto-clear ───────────────────────────────
        # The installer writes kernel-install-override.nix when target-kernel
        # packages were not in cache at install time.  On each update, check
        # whether the target packages are now cached; if so, remove the override
        # so the next rebuild upgrades to the intended kernel automatically.
        OVERRIDE_FILE="/etc/nixos/kernel-install-override.nix"
        if [ -f "$OVERRIDE_FILE" ]; then
          echo "Kernel install override detected — checking if target kernel is now cached..."
          rm "$OVERRIDE_FILE"
          DRY_CHECK=$(nixos-rebuild dry-build --flake git+file:///etc/nixos#"$VARIANT" 2>&1 || true)
          HEAVY_BUILD_REGEX='^(linux-[0-9][^/]*-modules|linux-[0-9][^/]*-modules-shrunk|NVIDIA-Linux-|nvidia-x11-|nvidia-settings-|openrazer-[0-9])'
          STILL_HEAVY=$(printf '%s\n' "$DRY_CHECK" \
            | awk '/will be built:/{p=1;next} /will be fetched:|^building |^[^ \t]/{p=0} p && /\/nix\/store\//{sub(/.*\/nix\/store\/[a-z0-9]+-/,""); print}' \
            | grep -E "$HEAVY_BUILD_REGEX" || true)
          if [ -n "$STILL_HEAVY" ]; then
            printf '%s\n' \
              '# Written by vexos-nix installer — fallback to channel-default kernel.' \
              '# Removed automatically by vexos-update once target kernel packages are cached.' \
              '# To upgrade manually: delete this file, then run: just update' \
              '{ lib, pkgs, ... }:' \
              '{' \
              '  boot.kernelPackages = lib.mkForce pkgs.linuxPackages;' \
              '}' > "$OVERRIDE_FILE"
            echo "Target kernel packages not yet cached — keeping channel-default kernel."
            echo "Run 'just update' again in 1-3 days to upgrade automatically."
          else
            echo "Target kernel packages are cached — override removed. Kernel will upgrade on this update."
          fi
        fi

        # Back up current lock before touching anything.
        cp /etc/nixos/flake.lock /etc/nixos/flake.lock.bak

        echo "Updating flake inputs..."
        nix --extra-experimental-features "nix-command flakes" \
          flake update --flake git+file:///etc/nixos

        echo "Checking for packages that require a local source build..."
        DRY=$(nixos-rebuild dry-build \
          --flake git+file:///etc/nixos#"$VARIANT" 2>&1 || true)

        # Known-heavy block engine — two paths:
        #
        #   HEAVY_BUILD_REGEX: Packages that take hours to compile because they
        #   must be built against the running kernel (kernel modules, NVIDIA driver,
        #   OpenRazer DKMS module). If any match → block, restore lock, exit 2.
        #
        #   Everything else (system glue, vexos scripts, Rust crates, GUI wrappers):
        #   build locally in seconds-to-minutes, proceed with update.
        #   Logged as VEXOS_LOCAL_BUILD: lines.
        #
        # VEXOS_UPDATE_STRICT=1: block on ALL local builds (strict environments).
        #
        # Legacy note: The three-class (A/B/C) engine with ALWAYS_LOCAL_REGEX and
        # KNOWN_SMALL_LOCAL_REGEX was retired. The new model requires no allowlist
        # maintenance — only the small, stable HEAVY_BUILD_REGEX list matters.

        HEAVY_BUILD_REGEX='^(linux-[0-9][^/]*-modules|linux-[0-9][^/]*-modules-shrunk|NVIDIA-Linux-|nvidia-x11-|nvidia-settings-|openrazer-[0-9])'

        # Extract all "will be built" derivation names.
        ALL_LOCAL=$(printf '%s\n' "$DRY" \
          | awk '/will be built:/{p=1;next} /will be fetched:|^building |^[^ \t]/{p=0} p && /\/nix\/store\//{sub(/.*\/nix\/store\/[a-z0-9]+-/,""); print}' \
          || true)

        # Partition: heavy (hours, block) vs non-heavy (fast, allow).
        HEAVY_BUILDS=$(printf '%s\n' "$ALL_LOCAL" \
          | grep -E  "$HEAVY_BUILD_REGEX" || true)
        NON_HEAVY_BUILDS=$(printf '%s\n' "$ALL_LOCAL" \
          | grep -Ev "$HEAVY_BUILD_REGEX" || true)

        # Strict mode: treat all local builds as heavy.
        if [ "''${VEXOS_UPDATE_STRICT:-0}" = "1" ]; then
          HEAVY_BUILDS="$ALL_LOCAL"
          NON_HEAVY_BUILDS=""
        fi

        if [ -n "$HEAVY_BUILDS" ]; then
          echo ""
          echo "VEXOS_CACHE_BLOCK: Update paused — kernel or NVIDIA packages require a"
          echo "VEXOS_CACHE_BLOCK: local source build (typically 1-3 days until Hydra caches them):"
          printf '%s\n' "$HEAVY_BUILDS" | grep '[^[:space:]]' | sed 's/^/VEXOS_CACHE_BLOCK:   /'
          echo "VEXOS_CACHE_BLOCK:"
          echo "VEXOS_CACHE_BLOCK: flake.lock restored. No changes were applied."
          echo "VEXOS_CACHE_BLOCK: Options:"
          echo "VEXOS_CACHE_BLOCK:   just deploy     — apply config changes without bumping nixpkgs"
          echo "VEXOS_CACHE_BLOCK:   just update     — retry in 1-3 days once Hydra has built them"
          echo "VEXOS_CACHE_BLOCK:   just update-all — force local compile now (may take hours)"
          cp /etc/nixos/flake.lock.bak /etc/nixos/flake.lock
          rm -f /etc/nixos/flake.lock.bak
          exit 2
        fi

        if [ -n "$NON_HEAVY_BUILDS" ]; then
          echo ""
          echo "VEXOS_LOCAL_BUILD: Some packages will build locally (system glue or custom scripts — fast):"
          printf '%s\n' "$NON_HEAVY_BUILDS" | grep '[^[:space:]]' | sed 's/^/VEXOS_LOCAL_BUILD:   /'
        fi

        rm -f /etc/nixos/flake.lock.bak
        echo "Applying update..."
        nixos-rebuild switch \
          --flake git+file:///etc/nixos#"$VARIANT" \
          --print-build-logs
      '')
    ];
  }; # end config
}
