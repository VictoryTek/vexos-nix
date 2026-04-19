# modules/server/papermc.nix
# PaperMC Minecraft server — high-performance Spigot fork (unstable channel).
{ config, lib, pkgs, ... }:
let
  cfg = config.vexos.server.papermc;
in
{
  options.vexos.server.papermc = {
    enable = lib.mkEnableOption "PaperMC Minecraft server";

    memory = lib.mkOption {
      type = lib.types.str;
      default = "2G";
      description = "JVM heap size for the Minecraft server (e.g. 2G, 4G).";
    };
  };

  config = lib.mkIf cfg.enable {
    services.minecraft-server = {
      enable = true;
      eula = true;
      package = pkgs.unstable.papermc;
      openFirewall = true;
      declarative = false; # Allow server.properties to be managed by PaperMC
      jvmOpts = "-Xms${cfg.memory} -Xmx${cfg.memory}";
    };
  };
}
