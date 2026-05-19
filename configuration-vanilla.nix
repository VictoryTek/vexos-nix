# configuration-vanilla.nix
# Vanilla role: stock NixOS baseline for system restore.
# Intentionally minimal — mirrors what a default nixos-generate-config +
# GNOME desktop selection produces.
# Does NOT include: custom kernel, performance tuning, ZRAM, AppArmor,
# gaming, Flatpak, branding, or custom packages.
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

  # ---------- GNOME desktop (stock NixOS default) ----------
  # Mirrors the desktop environment a standard NixOS GNOME install provides.
  # No custom extensions, overlays, or vexos-specific packages.
  services.xserver.enable = true;
  services.displayManager.gdm.enable   = true;
  services.desktopManager.gnome.enable = true;

  # ---------- Audio ----------
  # PipeWire — same default NixOS uses for GNOME installs.
  services.pipewire = {
    enable            = true;
    alsa.enable       = true;
    alsa.support32Bit = true;
    pulse.enable      = true;
  };

  # ---------- State version ----------
  # Do NOT change after initial install.
  system.stateVersion = "25.11";
}
