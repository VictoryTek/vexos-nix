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

  config = lib.mkMerge [
    # Always pin to docker_29 so any service that enables docker (without specifying
    # a package) doesn't fall through to the now-insecure nixpkgs default (docker_28).
    { virtualisation.docker.package = lib.mkDefault pkgs.docker_29; }

    (lib.mkIf cfg.enable {
      virtualisation.docker = {
        enable = true;
        autoPrune = {
          enable = true;
          dates = "weekly";
        };
      };

      users.users.${config.vexos.user.name}.extraGroups = [ "docker" ];

      environment.systemPackages = with pkgs; [
        docker-compose
        lazydocker
        nftables
      ];
    })
  ];
}
