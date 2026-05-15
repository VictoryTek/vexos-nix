# modules/server/komga.nix
# Komga — self-hosted comics and manga server with a web reader.
# Default port: 8080 — adjust if it conflicts with other services.
{ config, lib, pkgs, ... }:
let
  cfg = config.vexos.server.komga;
in
{
  options.vexos.server.komga = {
    enable = lib.mkEnableOption "Komga comics and manga server";
  };

  config = lib.mkIf cfg.enable {
    services.komga = {
      enable = true;
      port = 8090; # Using 8090 to avoid common 8080 conflicts
      openFirewall = true;
    };

    users.users.${config.vexos.user.name}.extraGroups = [ "komga" ];
  };
}
