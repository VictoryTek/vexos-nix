# modules/asus.nix
# ASUS ROG/TUF laptop hardware support: asusd daemon, ROG Control Center GUI,
# supergfxctl GPU switching. Mirrors Bazzite's ASUS feature set.
#
# Safe on non-ASUS hardware: asusd and supergfxd exit gracefully when ASUS
# platform drivers are absent. No kernel module additions required — ASUS
# drivers (asus-nb-wmi, asus-wmi, platform_profile) are auto-loaded by udev.
#
# User permissions: managed via polkit + D-Bus. No extra groups required;
# the nimda user's existing 'wheel' membership grants full polkit admin access.
#
# DO NOT import in hosts/vm.nix — not applicable in VM guests.
{ config, pkgs, lib, ... }:
{
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

  # asusctl CLI tool + rog-control-center GUI (bundled in the same package, v6.1.12).
  # supergfxctl is already added to systemPackages by the supergfxd NixOS module.
  environment.systemPackages = with pkgs; [
    asusctl  # CLI: asusctl; GUI: rog-control-center (both included in this package)
  ];
}
