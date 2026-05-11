# modules/server/nas.nix
# Umbrella option for the full NAS stack.
#
# Setting `vexos.server.nas.enable = true` is the "just make it a NAS"
# shortcut. It enables Cockpit plus all four 45Drives management plugins:
#   • cockpit-navigator   — file browser
#   • cockpit-file-sharing — Samba + NFS share management
#   • cockpit-identities  — user/group/password management
#
# Each sub-option is set via lib.mkDefault, so the operator can still
# override individual sub-options without having to touch nas.enable:
#
#   vexos.server.nas.enable = true;
#   vexos.server.cockpit.navigator.enable = false;  # this wins — lib.mkDefault loses
#
# cockpit-zfs is intentionally excluded: it requires a ZFS pool to already
# be configured on the host and has its own default auto-enable logic.
# When cockpit-zfs becomes packageable (upstream nixpkgs or a self-contained
# lockfile), adding it here is a one-line addition to this file.
{ config, lib, ... }:
let
  cfg = config.vexos.server.nas;
in
{
  options.vexos.server.nas = {
    enable = lib.mkEnableOption "full NAS stack (Cockpit web UI + navigator + file-sharing + identities plugins)";
  };

  config = lib.mkIf cfg.enable {
    vexos.server.cockpit.enable             = lib.mkDefault true;
    vexos.server.cockpit.navigator.enable   = lib.mkDefault true;
    vexos.server.cockpit.fileSharing.enable = lib.mkDefault true;
    vexos.server.cockpit.identities.enable  = lib.mkDefault true;
  };
}
