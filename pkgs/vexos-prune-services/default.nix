# pkgs/vexos-prune-services/default.nix
# vexos-prune-services — report or remove entries in a host's
# /etc/nixos/server-services.nix that name a server service which no longer
# exists in vexos-nix.
#
# server-services.nix is host-owned and never resynced by an update, but the
# option names in it are owned by this repo. Deleting a service module used to
# make every host still listing it fail evaluation, blocking the very update
# that delivered the removal.
#
# The valid names come from lib/server-service-names.nix, which derives them
# from the option declarations, so removing a service needs no bookkeeping
# anywhere. `serviceNames` is baked in at build time from the same revision the
# host is deploying — there is no runtime nix evaluation here.
#
# Exposed as a flake app so it runs without a rebuild first:
#   nix run github:VictoryTek/vexos-nix#prune-services -- --apply
# That is what keeps it usable on a host whose installed tooling predates the
# removal it needs to clean up.
#
# Exit codes:
#   0 — nothing to do
#   1 — dead entries found (--check only)
#   2 — file cannot be parsed safely (nested vexos.server = { ... } form)
#   3 — usage or environment error
{ lib, writeShellApplication, writeText, gawk, serviceNames }:

let
  pruneAwk = writeText "prune-services.awk" (builtins.readFile ./prune.awk);
in
writeShellApplication {
  name = "vexos-prune-services";
  runtimeInputs = [ gawk ];
  text = ''
    VALID="${lib.concatStringsSep " " serviceNames}"
    MODE="check"
    FILE="/etc/nixos/server-services.nix"

    while [ "$#" -gt 0 ]; do
      case "$1" in
        --check) MODE="check" ;;
        --apply) MODE="apply" ;;
        -h|--help)
          echo "usage: vexos-prune-services [--check|--apply] [path]"
          echo
          echo "  --check  list entries naming a service that no longer exists (default)"
          echo "  --apply  remove those entries, keeping a .bak alongside the file"
          echo
          echo "With no path, operates on /etc/nixos/server-services.nix."
          exit 0
          ;;
        -*) echo "error: unknown option '$1' (try --help)" >&2; exit 3 ;;
        *)  FILE="$1" ;;
      esac
      shift
    done

    # A derivation that produced nothing would mark every entry dead and wipe
    # the file. Refuse rather than trust an empty list.
    if [ -z "$VALID" ]; then
      echo "error: built with an empty service list — refusing to touch $FILE" >&2
      echo "This is a bug in lib/server-service-names.nix, not in your config." >&2
      exit 3
    fi

    if [ ! -f "$FILE" ]; then
      echo "No $FILE on this host — nothing to prune."
      exit 0
    fi

    # Textual removal is only safe for the flat form that `just enable` writes
    # (vexos.server.<name>.<attr> = ...;). Refuse on a hand-written nested set
    # rather than risk mangling it.
    if grep -qE '^[[:space:]]*vexos(\.server)?[[:space:]]*=[[:space:]]*\{' "$FILE"; then
      echo "error: $FILE uses the nested 'vexos.server = { ... }' form." >&2
      echo "This tool only rewrites the flat 'vexos.server.<name>... = ...;' form." >&2
      echo "Remove any entries for services that no longer exist by hand." >&2
      exit 2
    fi

    DEAD=$(mktemp)
    OUT=$(mktemp)
    trap 'rm -f "$DEAD" "$OUT"' EXIT

    awk -v valid="$VALID" -v deadfile="$DEAD" -f ${pruneAwk} "$FILE" > "$OUT"

    if [ ! -s "$DEAD" ]; then
      echo "$FILE is clean — no entries for removed services."
      exit 0
    fi

    COUNT=$(wc -l < "$DEAD" | tr -d ' ')
    echo "$FILE configures $COUNT service(s) that no longer exist in vexos-nix:"
    while read -r name was_enabled; do
      if [ "$was_enabled" = "true" ]; then
        echo "  $name  (was set enable = true — this service is not running)"
      else
        echo "  $name"
      fi
    done < "$DEAD"
    echo
    echo "If one of these is a typo rather than a removed service, fix the name"
    echo "instead — 'just enable' rejects names that are not real services."

    if [ "$MODE" = "check" ]; then
      echo
      echo "Remove them with: just prune-services"
      exit 1
    fi

    cp -- "$FILE" "$FILE.bak"
    cat -- "$OUT" > "$FILE"
    echo
    echo "Removed. Previous contents saved to $FILE.bak"
  '';
}
