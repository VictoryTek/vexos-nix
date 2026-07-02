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
*.bak
vexos-variant
GITIGNORE
          git -C /etc/nixos init -q
          git -C /etc/nixos add .
          git -C /etc/nixos \
            -c user.email="vexos@localhost" \
            -c user.name="VexOS" \
            commit -q -m "chore: track /etc/nixos configuration"
          echo "Done — secrets/ is now excluded from the Nix store on all future rebuilds."
        fi

        # ── Auto-heal stale thin wrapper: ensure features.nix is loaded ──────
        # /etc/nixos/flake.nix is written once at install time from
        # template/etc-nixos-flake.nix and is never resynced by this script —
        # only the vexos-nix flake input gets bumped above, not the wrapper's
        # own text. Older wrappers predate the fix that wires
        # /etc/nixos/features.nix into the module list, so every feature
        # toggle silently reverts to disabled on every update. Self-heal here
        # (same patch `just fix-flake` applies manually) so already-installed
        # hosts pick this up automatically. Not applicable to
        # stateless/headless-server/vanilla — those roles never wire in
        # featuresModule.
        if [[ "$VARIANT" != *stateless* && "$VARIANT" != *headless* && "$VARIANT" != *vanilla* ]]; then
          if ! grep -q "features\.nix" /etc/nixos/flake.nix 2>/dev/null; then
            echo "Wrapper does not load features.nix — patching automatically..."
            if grep -q '] ++ modules;' /etc/nixos/flake.nix; then
              sed -i \
                's|] ++ modules;|] ++ modules\n          ++ (if builtins.pathExists ./features.nix then [ ./features.nix ] else []);|' \
                /etc/nixos/flake.nix
              echo "✓ Wrapper patched (old-style)."
            elif grep -q 'lib\.optional hasKernelOverride' /etc/nixos/flake.nix; then
              sed -i \
                '0,/lib\.optional hasKernelOverride/s|++ lib\.optional hasKernelOverride|++ (if builtins.pathExists ./features.nix then [ ./features.nix ] else [])\n          ++ lib.optional hasKernelOverride|' \
                /etc/nixos/flake.nix
              echo "✓ Wrapper patched (current-style)."
            else
              echo "warning: could not auto-patch wrapper — run 'just fix-flake' manually." >&2
            fi
          fi
        fi

        # ── Repair repos initialised with old gitignore ──────────────────────
        # Earlier versions of this migration excluded hardware-configuration.nix,
        # kernel-install-override.nix, and stateless-user-override.nix from git,
        # which caused git+file:// builds to fail (file absent from store).
        # server-services.nix is created by `just enable` after the initial git
        # init, so it is typically untracked.  git+file:// silently excludes
        # untracked files, which drops ALL enabled services after every update.
        # Force-add all host-local config files so they are tracked regardless of
        # when they were created.  flake.nix is included here too so a wrapper
        # patched by the auto-heal step above is committed before the
        # git+file:// dry-build/switch below.
        for _f in hardware-configuration.nix kernel-install-override.nix stateless-user-override.nix server-services.nix features.nix flake.nix; do
          if [ -f "/etc/nixos/$_f" ]; then
            git -C /etc/nixos add -f "$_f" 2>/dev/null || true
          fi
        done
        # Commit any newly staged files so git+file:// sees their current content.
        # (git+file:// reads committed state; staged-but-uncommitted changes are
        # invisible to it, which would silently use the old HEAD version.)
        if ! git -C /etc/nixos diff --cached --quiet 2>/dev/null; then
          git -C /etc/nixos \
            -c user.email="vexos@localhost" \
            -c user.name="VexOS" \
            commit -q -m "chore: track /etc/nixos config files" 2>/dev/null || true
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
          KERNEL_BLOCK_REGEX='^(linux-[0-9][^/]*-modules|linux-[0-9][^/]*-modules-shrunk)'
          STILL_HEAVY=$(printf '%s\n' "$DRY_CHECK" \
            | awk '/will be built:/{p=1;next} /will be fetched:|^building |^[^ \t]/{p=0} p && /\/nix\/store\//{sub(/.*\/nix\/store\/[a-z0-9]+-/,""); print}' \
            | grep -E "$KERNEL_BLOCK_REGEX" || true)
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

        # Three-way local-build classifier:
        #
        #   HEAVY_BUILD_REGEX: kernel modules — cacheable but hours to compile.
        #   If any match → block, restore lock, exit 2. Retry in 1-3 days.
        #
        #   UNAVOIDABLE_REGEX: unfree NVIDIA userspace (nvidia-x11 / .run /
        #   settings / persistenced) and locally-patched openrazer — Hydra NEVER
        #   caches these (unfree/non-redistributable or patched derivation hash).
        #   Blocking on them permanently breaks `just update` for all NVIDIA hosts.
        #   Proceed; log as VEXOS_LOCAL_BUILD: with an explanation.
        #
        #   Everything else (system glue, vexos scripts, Rust crates, etc.):
        #   fast local build; proceed; log as VEXOS_LOCAL_BUILD:.
        #
        # VEXOS_UPDATE_STRICT=1: block on ALL local builds (strict environments).

        HEAVY_BUILD_REGEX='^(linux-[0-9][^/]*-modules|linux-[0-9][^/]*-modules-shrunk)'
        UNAVOIDABLE_REGEX='^(NVIDIA-Linux-|nvidia-x11-|nvidia-settings-|nvidia-persistenced-|openrazer-[0-9])'

        # Extract all "will be built" derivation names.
        ALL_LOCAL=$(printf '%s\n' "$DRY" \
          | awk '/will be built:/{p=1;next} /will be fetched:|^building |^[^ \t]/{p=0} p && /\/nix\/store\//{sub(/.*\/nix\/store\/[a-z0-9]+-/,""); print}' \
          || true)

        # Partition into three groups.
        HEAVY_BUILDS=$(printf '%s\n' "$ALL_LOCAL" \
          | grep -E  "$HEAVY_BUILD_REGEX" || true)
        UNAVOIDABLE_BUILDS=$(printf '%s\n' "$ALL_LOCAL" \
          | grep -E  "$UNAVOIDABLE_REGEX" || true)
        NON_HEAVY_BUILDS=$(printf '%s\n' "$ALL_LOCAL" \
          | grep -Ev "$HEAVY_BUILD_REGEX|$UNAVOIDABLE_REGEX" || true)

        # Strict mode: treat all local builds as heavy.
        if [ "''${VEXOS_UPDATE_STRICT:-0}" = "1" ]; then
          HEAVY_BUILDS="$ALL_LOCAL"
          UNAVOIDABLE_BUILDS=""
          NON_HEAVY_BUILDS=""
        fi

        if [ -n "$HEAVY_BUILDS" ]; then
          echo ""
          echo "VEXOS_CACHE_BLOCK: Update paused — kernel packages require a"
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

        if [ -n "$UNAVOIDABLE_BUILDS" ]; then
          echo ""
          echo "VEXOS_LOCAL_BUILD: NVIDIA userspace driver and/or patched OpenRazer will build locally."
          echo "VEXOS_LOCAL_BUILD: These are never in the binary cache (unfree/patched). This is expected."
          echo "VEXOS_LOCAL_BUILD: Estimated build time: ~10-15 min for NVIDIA userspace; seconds for OpenRazer."
          printf '%s\n' "$UNAVOIDABLE_BUILDS" | grep '[^[:space:]]' | sed 's/^/VEXOS_LOCAL_BUILD:   /'
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
