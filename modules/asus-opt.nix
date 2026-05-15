# modules/asus-opt.nix
# Hardware-agnostic wrapper for asus.nix. Import in all configuration-*.nix files.
#
# Opt-in ASUS ROG/TUF hardware support available to all roles.
#
# Set `vexos.hardware.asus.enable = true` in the relevant hosts/*.nix file
# for any machine built on ASUS ROG / TUF hardware.
#
# This module is imported by every configuration-*.nix so the option is
# always declared regardless of role.  Only host files for physical ASUS
# machines should set the option.
#
# Architecture note: the lib.mkIf guard below is a hardware-enable-flag gate,
# NOT a role gate.  This is valid under the project's Option B architecture —
# a dedicated hardware module may gate its own content on a hardware flag.
# Do NOT replicate this pattern in role configuration files.
#
# VM guests: do NOT set vexos.hardware.asus.enable = true on vm variants.
# asusd and supergfxd have no ASUS platform devices to manage in a VM.
{ config, lib, pkgs, ... }:
{
  options.vexos.hardware.asus = {
    enable = lib.mkEnableOption "ASUS ROG/TUF hardware support (asusd, supergfxctl, fan curves)";
  };

  config = lib.mkIf config.vexos.hardware.asus.enable {
    # asusd: ASUS ROG daemon — fan curves, battery charge limit, power/thermal profiles,
    # keyboard backlight (Aura), GPU MUX switching, Anime Matrix LED.
    # Enabling this also enables services.supergfxd via lib.mkDefault (see nixpkgs source).
    services.asusd = {
      enable = true;
      enableUserService = true;  # asusd-user: per-user Aura LED profile control
    };

    # supergfxd: GPU switching daemon (integrated / hybrid / VFIO / dedicated modes).
    # Explicitly set to ensure it's always enabled regardless of asusd's mkDefault.
    # The supergfxd module auto-installs pkgs.supergfxctl into environment.systemPackages.
    services.supergfxd.enable = true;

    # asusctl CLI tool + rog-control-center GUI (bundled in the same package).
    # supergfxctl is already added to systemPackages by the supergfxd NixOS module.
    environment.systemPackages = with pkgs; [
      asusctl  # CLI: asusctl; GUI: rog-control-center (both included in this package)
    ];
  };
}
