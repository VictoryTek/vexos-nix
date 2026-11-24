# modules/gliff.nix
# gliff — remote desktop over SSH (VictoryTek fork with a GNOME backend). The
# project's remote-access solution (GNOME Remote Desktop/RDP has been removed;
# see modules/gnome.nix). Replaces Sunshine/Moonlight.
#
# On by default on every role that imports this file — it's the project's
# remote-access story, not an optional extra. Opt out on a per-host basis via
# /etc/nixos/features.nix:
#   vexos.features.gliff.enable = false;
# Toggle with `just feature enable gliff` / `just feature disable gliff`.
#
# Imported unconditionally by: configuration-desktop.nix, configuration-server.nix,
# configuration-htpc.nix, configuration-vanilla.nix (matching modules/gaming.nix's
# precedent — the import is unconditional, the config below is gated by the feature
# option). vanilla overrides the default back to false in its own config to preserve
# its "stays stock" contract — see configuration-vanilla.nix.
# NOT imported by: configuration-stateless.nix, configuration-headless-server.nix
#
# gliff needs no firewall ports: the viewer reaches gliff-server over SSH
# (services.openssh, modules/network.nix). It mirrors a logged-in, unlocked
# session — a locked screen blocks capture.
#
# The programs.gliff option tree comes from the gliff flake's NixOS module,
# imported via gliffModule in flake.nix (`imports` cannot reference `inputs`).
{ config, lib, ... }:
let
  cfg = config.vexos.features.gliff;
in
{
  imports = [
    (lib.mkRemovedOptionModule [ "vexos" "features" "sunshine" "enable" ]
      "Sunshine and Moonlight were replaced by gliff (vexos.features.gliff.enable); delete the vexos.features.sunshine line from /etc/nixos/features.nix.")
  ];

  options.vexos.features.gliff.enable =
    lib.mkEnableOption "gliff (remote desktop over SSH)" // { default = true; };

  config = lib.mkIf cfg.enable {
    programs.gliff.enable = true;
  };
}
