# modules/server/docker.nix
# Docker container runtime with compose and management tools.
{ config, lib, pkgs, ... }:
let
  cfg = config.vexos.server.docker;
in
{
  options.vexos.server.docker = {
    enable = lib.mkEnableOption "Docker container runtime";
  };

  config = lib.mkIf cfg.enable {
    virtualisation.docker = {
      enable = true;
      autoPrune = {
        enable = true;
        dates = "weekly";
      };
    };

    users.users.nimda.extraGroups = [ "docker" ];

    environment.systemPackages = with pkgs; [
      docker-compose
      lazydocker
    ];
  };
}
