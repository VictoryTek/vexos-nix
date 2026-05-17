# modules/server/papermc.nix
# PaperMC Minecraft server — high-performance Spigot fork (unstable channel).
{ config, lib, pkgs, ... }:
let
  cfg = config.vexos.server.papermc;
in
{
  options.vexos.server.papermc = {
    enable = lib.mkEnableOption "PaperMC Minecraft server";

    acceptEula = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = "Set to true only after reading and accepting the Mojang EULA: https://www.minecraft.net/en-us/eula";
    };

    memory = lib.mkOption {
      type = lib.types.str;
      default = "2G";
      description = "JVM heap size for the Minecraft server (e.g. 2G, 4G).";
    };
  };

  config = lib.mkIf cfg.enable {
    assertions = [
      {
        assertion = cfg.acceptEula;
        message = "vexos.server.papermc.acceptEula must be set to true when vexos.server.papermc.enable = true. Read https://www.minecraft.net/en-us/eula before enabling.";
      }
    ];

    services.minecraft-server = {
      enable = true;
      eula = cfg.acceptEula;
      package = pkgs.unstable.papermc;
      openFirewall = true;
      declarative = false; # Allow server.properties to be managed by PaperMC
      jvmOpts = "-Xms${cfg.memory} -Xmx${cfg.memory}";
    };
  };
}
