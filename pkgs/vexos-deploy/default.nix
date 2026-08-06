# pkgs/vexos-deploy/default.nix
# vexos-deploy — config-only deploy used by `just deploy`.  Pulls the latest
# vexos-nix commit from GitHub and holds every other flake input at the
# revision already in /etc/nixos/flake.lock, so a deploy never drags in a
# nixpkgs bump (and therefore never triggers a heavy source build).
#
# Why this needs a script rather than a one-liner in the justfile:
# /etc/nixos/flake.nix declares `nixpkgs.follows = "vexos-nix/nixpkgs"` — there
# is no independent nixpkgs pin on the host.  `nix flake update vexos-nix`
# therefore re-locks vexos-nix's transitive nodes from the *new* upstream
# flake.lock, and since vexos-nix carries a daily lock-bump bot, every new
# upstream commit moves nixpkgs.  The fix is to update vexos-nix and then put
# every other node's `locked` revision back.
#
# Only `locked` is restored, never `original`.  `original` is the declared ref
# (the tracked branch); `locked` is the resolved revision.  Holding `locked`
# while leaving `original` alone means "same input, same branch, held where we
# already are" — which is exactly what deploy promises, and unlike a CLI
# `--override-input` it is not sticky: the next `vexos-update` advances the
# input from its unchanged `original` as normal.
#
# Nodes are matched between the old and new lock by byte-identical `original`,
# not by node key.  Nix dedups and suffixes node keys (this repo's own lock
# resolves root input `nixpkgs` to node key `nixpkgs_2`), so keys are not
# stable across a re-lock and pairing by key alone could pin the wrong
# revision onto the wrong input.
#
# runtimeInputs is used only for jq, which is not present on every role
# (modules/development.nix is feature-gated).  writeShellApplication prepends
# to PATH rather than replacing it, so nix / nixos-rebuild still resolve from
# the ambient system PATH, same as vexos-update.
#
# Exit codes:
#   0  — config deployed
#   1  — error (bad variant, update failed, or the nixpkgs pin could not be
#         held; flake.lock restored in every case)
{ writeShellApplication, jq }:

writeShellApplication {
  name = "vexos-deploy";
  runtimeInputs = [ jq ];
  text = ''
    FLAKE_DIR=/etc/nixos
    LOCK="$FLAKE_DIR/flake.lock"
    BAK="$FLAKE_DIR/flake.lock.bak"

    VARIANT=$(cat "$FLAKE_DIR/vexos-variant" 2>/dev/null || true)
    if [ -z "$VARIANT" ]; then
      echo "error: /etc/nixos/vexos-variant not found. Run 'just switch' first." >&2
      exit 1
    fi

    # The nixpkgs that actually builds the system, reached through vexos-nix.
    nixpkgs_rev() {
      jq -r '
        .nodes[.root].inputs["vexos-nix"] as $vex
        | .nodes[$vex].inputs["nixpkgs"] as $np
        | .nodes[$np].locked.rev // "unknown"
      ' "$1"
    }

    restore_lock() {
      cp "$BAK" "$LOCK"
      rm -f "$BAK"
    }

    if [ "$(jq -r '.nodes[.root].inputs["vexos-nix"] // "null"' "$LOCK")" = "null" ]; then
      echo "error: $LOCK has no vexos-nix input — this host's wrapper flake is not" >&2
      echo "       a vexos-nix thin wrapper. Refusing to touch the lock file." >&2
      exit 1
    fi

    cp "$LOCK" "$BAK"
    PINNED_REV=$(nixpkgs_rev "$BAK")

    echo ""
    echo "Pulling latest vexos-nix config (nixpkgs unchanged)..."
    if ! nix --extra-experimental-features "nix-command flakes" \
         flake update vexos-nix --flake "path:$FLAKE_DIR"; then
      echo "error: could not update the vexos-nix input — restoring flake.lock." >&2
      restore_lock
      exit 1
    fi

    # Put every node except vexos-nix itself back to its pre-update revision.
    #
    # Nodes are paired between the two locks by their canonicalised `original`
    # (declared ref), never by node key: Nix renumbers keys when the input
    # graph changes shape, so after an update the live nixpkgs can land on
    # `nixpkgs_2` while a stale `nixpkgs` node lingers.  Keying off `original`
    # is immune to that.  `original` is canonicalised by sorting its keys
    # because jq's tojson preserves insertion order, which is not stable
    # between the two files.
    #
    # An `original` that appears in the old lock under two different `locked`
    # revisions is ambiguous and is skipped rather than guessed at.
    TMP=$(mktemp "$LOCK.tmp.XXXXXX")
    if ! jq --slurpfile old "$BAK" '
          def canon: to_entries | sort_by(.key) | from_entries | tojson;

          .nodes[.root].inputs["vexos-nix"] as $vex
          | $old[0] as $o
          | ( $o.nodes[$o.root].inputs["vexos-nix"] ) as $oldvex
          | ( [ $o.nodes | to_entries[]
                | select(.key != $o.root and .key != $oldvex)
                | select(.value.original != null and .value.locked != null)
                | { k: (.value.original | canon), v: .value.locked } ]
              | group_by(.k)
              | map(select((map(.v | canon) | unique | length) == 1))
              | map({ key: .[0].k, value: .[0].v })
              | from_entries
            ) as $byorig
          | reduce (.nodes | keys[]) as $k (.;
              if $k == .root or $k == $vex then .
              elif .nodes[$k].original == null then .
              else ( .nodes[$k].original | canon ) as $orig
                | if $byorig[$orig] != null
                  then .nodes[$k].locked = $byorig[$orig]
                  else . end
              end)
        ' "$LOCK" > "$TMP"; then
      echo "error: could not rewrite flake.lock — restoring." >&2
      rm -f "$TMP"
      restore_lock
      exit 1
    fi
    chmod 0644 "$TMP"
    mv "$TMP" "$LOCK"

    # The promise this script exists to keep.  Fail loudly rather than let an
    # unnoticed nixpkgs bump start a multi-hour source build.
    NEW_REV=$(nixpkgs_rev "$LOCK")
    if [ "$NEW_REV" != "$PINNED_REV" ]; then
      echo "error: nixpkgs moved from $PINNED_REV to $NEW_REV despite pinning." >&2
      echo "       flake.lock restored. No changes were applied." >&2
      echo "       Use 'just update' (cache-safe) or 'just update-all' (force) instead." >&2
      restore_lock
      exit 1
    fi

    echo ""
    echo "Switching to: $VARIANT"
    nixos-rebuild switch --impure --flake "path:$FLAKE_DIR#$VARIANT"
    rm -f "$BAK"
  '';
}
