# modules/server/kernel-builder.nix
# Custom kernel build service — builds the kernels listed in pkgs/kernels/ and
# pins them so Harmonia can serve them to the rest of the fleet.
#
# Device-agnostic: enable this on whichever host runs Harmonia. Nothing here is
# tied to a particular machine.
#
# Why this exists: custom kernels are not on cache.nixos.org, and desktop hosts
# should never spend hours compiling one. A single host builds each kernel
# once; every other machine substitutes it from Harmonia.
#
# How a build is triggered:
#   - nightly by systemd timer (vexos.server.kernelBuilder.schedule)
#   - manually with `just kernel-build-now [name]`
#
# The service is a no-op when the currently-pinned kernel is already built, so
# running it often is cheap. It deliberately evaluates *what the repo currently
# asks for* rather than tracking upstream tags: a kernel's store path depends
# on both the pinned tag AND the nixpkgs revision, and the daily flake.lock
# update changes the latter. Tag-tracking would silently miss those bumps and
# leave every desktop compiling locally.
#
# Kernel version pins live in pkgs/kernels/<name>/version.json and are bumped
# by .github/workflows/update-kernels-nightly.yml — never by hand.
{ config, lib, pkgs, ... }:
let
  cfg = config.vexos.server.kernelBuilder;
in
{
  options.vexos.server.kernelBuilder = {
    enable = lib.mkEnableOption "custom kernel build service (builds kernels for Harmonia to serve)";

    kernels = lib.mkOption {
      type    = lib.types.listOf lib.types.str;
      default = [ "ogc" ];
      example = [ "ogc" ];
      description = ''
        Which kernels from the pkgs/kernels/ registry to build. Each name must
        match a flake output packages.<system>.kernel-<name>.
      '';
    };

    schedule = lib.mkOption {
      type    = lib.types.str;
      default = "*-*-* 01:00:00";
      description = ''
        systemd OnCalendar expression for the nightly build. Builds are long
        and unattended; the timer is skipped while a previous run is still
        active, so a build that overruns the interval cannot stack up.
      '';
    };

    repoPath = lib.mkOption {
      type    = lib.types.str;
      default = "/etc/nixos";
      description = "Path to the vexos-nix checkout to pull and build from.";
    };

    gcRootDir = lib.mkOption {
      type    = lib.types.path;
      default = "/var/lib/harmonia/roots";
      description = ''
        Directory holding GC roots for built kernels. Without these,
        nix.settings min-free/max-free (modules/nix.nix) garbage-collects the
        kernel out from under Harmonia and clients silently rebuild it.
      '';
    };

    keepGenerations = lib.mkOption {
      type    = lib.types.ints.positive;
      default = 3;
      description = ''
        How many previously-built kernels to keep pinned per kernel name.
        Older generations stay served, so a host that has not rebuilt yet — or
        one rolling back to a previous generation — still finds its kernel in
        the cache.
      '';
    };
  };

  config = lib.mkIf cfg.enable {
    assertions = [
      {
        assertion = config.vexos.server.harmonia.enable;
        message = ''
          vexos.server.kernelBuilder requires vexos.server.harmonia.enable = true.
          The builder only puts kernels into this host's /nix/store; Harmonia is
          what serves that store to the rest of the fleet. Building without
          serving accomplishes nothing.
          Fix: just enable harmonia
        '';
      }
    ];

    systemd.services = lib.genAttrs
      (map (k: "kernel-build-${k}") cfg.kernels)
      (unitName:
        let kernel = lib.removePrefix "kernel-build-" unitName;
        in {
          description = "Build the ${kernel} kernel and pin it for Harmonia";
          # Network-dependent: pulls the repo and fetches kernel source.
          after    = [ "network-online.target" ];
          wants    = [ "network-online.target" ];
          path     = [ pkgs.git config.nix.package pkgs.coreutils pkgs.findutils ];
          serviceConfig = {
            Type = "oneshot";
            # Kernel builds are long; do not let systemd kill them.
            TimeoutStartSec = "infinity";
            # Builds are heavy — stay out of the way of anything interactive.
            Nice = 19;
            IOSchedulingClass = "idle";
          };
          script = ''
            set -euo pipefail

            REPO="${cfg.repoPath}"
            KERNEL="${kernel}"
            ROOTS="${cfg.gcRootDir}"

            mkdir -p "$ROOTS"

            echo "==> Updating $REPO"
            git -C "$REPO" pull --ff-only

            echo "==> Evaluating kernel-$KERNEL"
            # --impure: the flake reads /etc/nixos/* host files at eval time.
            DRV=$(nix eval --impure --raw "path:$REPO#kernel-$KERNEL.drvPath")
            OUT=$(nix eval --impure --raw "path:$REPO#kernel-$KERNEL.outPath")
            echo "    drv: $DRV"
            echo "    out: $OUT"

            if [ -e "$OUT" ]; then
              echo "==> Already built — nothing to do."
            else
              echo "==> Building (this takes hours; safe to leave running)"
              nix build --impure --no-link "path:$REPO#kernel-$KERNEL"
              echo "==> Build complete"
            fi

            # Pin it so min-free/max-free GC cannot reclaim it while Harmonia
            # is still advertising it.
            VERSION=$(nix eval --impure --raw "path:$REPO#kernel-$KERNEL.version")
            ROOT="$ROOTS/$KERNEL-$VERSION"
            nix-store --add-root "$ROOT" --indirect --realise "$OUT" >/dev/null
            echo "==> Pinned GC root: $ROOT"

            # Keep only the newest N roots for this kernel; older ones are
            # unlinked so their store paths become collectable naturally.
            ls -1dt "$ROOTS/$KERNEL-"* 2>/dev/null \
              | tail -n +${toString (cfg.keepGenerations + 1)} \
              | while read -r old; do
                  echo "==> Unpinning old generation: $old"
                  rm -f "$old"
                done

            echo "==> Done. Harmonia is now serving $KERNEL $VERSION."
          '';
        });

    systemd.timers = lib.genAttrs
      (map (k: "kernel-build-${k}") cfg.kernels)
      (_: {
        description = "Nightly custom kernel build";
        wantedBy    = [ "timers.target" ];
        timerConfig = {
          OnCalendar = cfg.schedule;
          # Catch up if the machine was powered off at the scheduled time.
          Persistent = true;
          # Spread load if several kernels are configured.
          RandomizedDelaySec = "10m";
        };
      });
  };
}
