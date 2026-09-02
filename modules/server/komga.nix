# modules/server/komga.nix
# Komga — self-hosted comics and manga server with a web reader.
# Default port: 8080 — adjust if it conflicts with other services.
{ config, lib, pkgs, ... }:
let
  cfg = config.vexos.server.komga;
  storageMounts = import ../lib/storage-mount-ordering.nix { inherit lib; };
in
{
  options.vexos.server.komga = {
    enable = lib.mkEnableOption "Komga comics and manga server";

    mediaMounts = storageMounts.mediaMountsOption;
  };

  config = lib.mkIf cfg.enable {
    vexos.server.backup.servicePaths.komga = [ "/var/lib/komga" ];

    services.komga = {
      enable = true;
      port = 8090; # Using 8090 to avoid common 8080 conflicts
      openFirewall = true;
    };

    # Order Komga after its library storage is ready — local (mergerfs/ZFS)
    # or remote (storage-remote.nix, automount-based). See mediaMounts above.
    systemd.services.komga.unitConfig = storageMounts.requiresMountsFor cfg.mediaMounts;

    users.users.${config.vexos.user.name}.extraGroups = [ "komga" ];
  };
}
