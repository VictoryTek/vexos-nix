# configuration-vanilla.nix
# Vanilla role: stock NixOS baseline for system restore.
# Intentionally minimal — mirrors what nixos-generate-config produces.
# Does NOT include: custom kernel, performance tuning, ZRAM, AppArmor,
# desktop environment, audio, gaming, Flatpak, branding, or custom packages.
{ config, pkgs, lib, ... }:

{
  imports = [
    ./modules/locale.nix
    ./modules/users.nix
    ./modules/nix.nix
    ./modules/asus-opt.nix
  ];

  # ---------- Bootloader ----------
  # systemd-boot with EFI — same as nixos-generate-config defaults.
  # lib.mkDefault allows hardware-configuration.nix to override for BIOS/GRUB.
  boot.loader.systemd-boot.enable      = lib.mkDefault true;
  boot.loader.efi.canTouchEfiVariables = lib.mkDefault true;

  # ---------- Networking ----------
  networking.hostName = lib.mkDefault "vexos";
  networking.networkmanager.enable = true;

  # ---------- State version ----------
  # Do NOT change after initial install.
  system.stateVersion = "25.11";
}
