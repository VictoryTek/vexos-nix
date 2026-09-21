#!/usr/bin/env bash
# =============================================================================
# upgrade-wrapper.sh — migrate a legacy /etc/nixos/flake.nix to the side-file
# layout (bootloader.nix, hardware-local.nix, host.nix).
#
# Older wrappers carried three inline blocks (bootloaderModule, hardwareModule,
# hostModule) that install.sh and the justfile rewrote with awk/sed. The current
# template (template/etc-nixos-flake.nix) has none of them: those settings live
# in small optional files instead. The wrapper is written once and never
# resynced, so already-installed machines keep the old layout until this runs.
#
# Idempotent: exits 0 without touching anything unless the wrapper still has an
# inline hardwareModule/bootloaderModule definition. Fail-closed: everything is
# extracted and validated first; on any problem the wrapper is left untouched.
#
# Usage: bash scripts/upgrade-wrapper.sh [path/to/etc-nixos-flake.nix]
#   Template defaults to the local checkout's template/, else is fetched pinned
#   to $VEXOS_REV (main if unset) — same convention as the installer scripts.
# =============================================================================
set -euo pipefail

DIR="/etc/nixos"
FLAKE="$DIR/flake.nix"

[ -f "$FLAKE" ] || exit 0

# Legacy = an UNCOMMENTED inline block. The old template's header comment quotes
# the same identifiers, so commented lines must not count.
grep -qE '^[[:space:]]*(hardwareModule|bootloaderModule)[[:space:]]*=' "$FLAKE" || exit 0

die() {
  echo "error: wrapper upgrade aborted — $1" >&2
  echo "       $FLAKE was NOT modified." >&2
  exit 1
}

WORK="$(mktemp -d "${TMPDIR:-/tmp}/vexos-upgrade.XXXXXX")"
trap 'rm -rf "$WORK"' EXIT

echo "Legacy /etc/nixos/flake.nix detected (inline bootloader/hardware/host blocks)."
echo "Upgrading it to the side-file layout..."

# ---------- New template -----------------------------------------------------
TEMPLATE="${1:-}"
if [ -z "$TEMPLATE" ]; then
  if [ -n "${BASH_SOURCE[0]:-}" ] && [ -f "$(dirname "${BASH_SOURCE[0]}")/../template/etc-nixos-flake.nix" ]; then
    TEMPLATE="$(dirname "${BASH_SOURCE[0]}")/../template/etc-nixos-flake.nix"
  else
    TEMPLATE="$WORK/template.nix"
    curl -fsSL -o "$TEMPLATE" \
      "https://raw.githubusercontent.com/VictoryTek/vexos-nix/${VEXOS_REV:-main}/template/etc-nixos-flake.nix" \
      || die "could not download the current template."
  fi
fi
[ -f "$TEMPLATE" ] || die "template not found at $TEMPLATE."
grep -q 'hasBootloader' "$TEMPLATE" || die "$TEMPLATE is not the side-file template."

# ---------- Extract the settings worth keeping -------------------------------
CODE="$WORK/code.nix"
grep -vE '^[[:space:]]*#' "$FLAKE" > "$CODE" || true

VANILLA=false
case "$(cat "$DIR/vexos-variant" 2>/dev/null || true)" in
  vexos-vanilla-*) VANILLA=true ;;
esac

BL="$(sed -nE 's/.*vexos\.bootloader[[:space:]]*=[[:space:]]*"([a-z-]+)".*/\1/p' "$CODE" | head -n1)"
GD="$(sed -nE 's/.*vexos\.grub\.device[[:space:]]*=[[:space:]]*"([^"]+)".*/\1/p' "$CODE" | head -n1)"
if [ -z "$BL" ] && grep -q 'boot\.loader\.grub' "$CODE"; then
  # Hand-written GRUB stanza from the old header comment.
  BL="grub"
  GD="$(sed -nE 's/^[[:space:]]*device[[:space:]]*=[[:space:]]*"([^"]+)".*/\1/p' "$CODE" | head -n1)"
fi
if [ "$BL" = "grub" ] && [ -z "$GD" ]; then
  die "GRUB is configured but its target disk could not be determined."
fi
case "$BL" in ""|systemd-boot|grub|limine) ;; *) die "unrecognised bootloader '$BL'." ;; esac

# Hex-only pattern: the unsubstituted XXXXXXXX placeholder never matches.
HOST_ID="$(sed -nE 's/.*networking\.hostId[[:space:]]*=[[:space:]]*"([0-9a-fA-F]{8})".*/\1/p' "$CODE" | head -n1)"

# Right-hand side of `hardwareModule = <expr>;`, up to the ';' at brace depth 0.
HW="$(awk '
  !started && /^[[:space:]]*hardwareModule[[:space:]]*=/ {
    sub(/^[[:space:]]*hardwareModule[[:space:]]*=[[:space:]]*/, "")
    started = 1
  }
  started {
    out = ""
    for (i = 1; i <= length($0); i++) {
      c = substr($0, i, 1)
      if (c == "{") depth++
      else if (c == "}") depth--
      else if (c == ";" && depth == 0) { print out; exit }
      out = out c
    }
    print out
  }
' "$CODE")"
HW_COMPACT="$(printf '%s' "$HW" | tr -d '[:space:]')"

# ---------- Render side-files into WORK and validate -------------------------
if [ -n "$BL" ] && [ "$BL" != "systemd-boot" ]; then
  {
    echo "# /etc/nixos/bootloader.nix"
    echo "# Carried over from the legacy flake.nix by scripts/upgrade-wrapper.sh."
    if [ "$BL" = "grub" ] && [ "$VANILLA" = "true" ]; then
      # vanilla never imports modules/system.nix, so vexos.bootloader is not
      # declared there; it sets systemd-boot with mkDefault, so this wins.
      echo "{"
      echo "  boot.loader.systemd-boot.enable = false;"
      echo "  boot.loader.grub = {"
      echo "    enable     = true;"
      echo "    efiSupport = false;"
      echo "    device     = \"$GD\";"
      echo "  };"
      echo "}"
    elif [ "$BL" = "grub" ]; then
      echo "{"
      echo "  vexos.bootloader  = \"grub\";"
      echo "  vexos.grub.device = \"$GD\";"
      echo "}"
    else
      echo "{"
      echo "  vexos.bootloader = \"$BL\";"
      echo "}"
    fi
  } > "$WORK/bootloader.nix"
fi

if [ -n "$HOST_ID" ]; then
  cat > "$WORK/host.nix" <<EOF
# /etc/nixos/host.nix
# ZFS host identity. Carried over from the legacy flake.nix by
# scripts/upgrade-wrapper.sh. Must not change once ZFS pools exist.
{
  networking.hostId = "$HOST_ID";
}
EOF
fi

if [ -n "$HW_COMPACT" ] && [ "$HW_COMPACT" != "{...}:{}" ]; then
  {
    echo "# /etc/nixos/hardware-local.nix"
    echo "# Carried over from the legacy flake.nix's hardwareModule by"
    echo "# scripts/upgrade-wrapper.sh."
    printf '%s\n' "$HW"
  } > "$WORK/hardware-local.nix"
  command -v nix-instantiate >/dev/null 2>&1 \
    || die "nix-instantiate is unavailable, so the extracted hardware block cannot be validated."
  nix-instantiate --parse "$WORK/hardware-local.nix" >/dev/null 2>&1 \
    || die "the hardwareModule block could not be extracted cleanly."
fi

# ---------- Commit: backup, new template, side-files -------------------------
sudo cp -pf "$FLAKE" "$FLAKE.legacy.bak"
sudo install -m 644 "$TEMPLATE" "$FLAKE"
for f in bootloader.nix hardware-local.nix host.nix; do
  # Never clobber a side-file that already exists.
  if [ -f "$WORK/$f" ] && [ ! -e "$DIR/$f" ]; then
    sudo install -m 644 "$WORK/$f" "$DIR/$f"
    echo "  ✓ carried over $f"
  fi
done

# Best effort: git+file:// only sees tracked files.
if command -v git >/dev/null 2>&1 && sudo git -C "$DIR" rev-parse --git-dir >/dev/null 2>&1; then
  for f in flake.nix bootloader.nix hardware-local.nix host.nix; do
    [ -f "$DIR/$f" ] && sudo git -C "$DIR" add -f "$f" 2>/dev/null || true
  done
fi

echo "✓ /etc/nixos/flake.nix upgraded. Previous version kept at $FLAKE.legacy.bak"
echo "  Only bootloader, hostId and hardwareModule contents are carried over;"
echo "  any other hand edits to the old wrapper remain in the backup only."
