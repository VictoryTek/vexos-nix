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
    ./modules/notify.nix
    ./modules/asus-opt.nix
    ./modules/boot-discovery.nix
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

  # ---------- Remote Desktop ----------
  # Receive: GNOME Remote Desktop exposes RDP on port 3389.
  # The NixOS GNOME module sets this via mkDefault true; we declare it
  # explicitly and open the port. After deploy: GNOME Settings → System →
  # Remote Desktop to set credentials.
  services.gnome.gnome-remote-desktop.enable = true;
  networking.firewall.allowedTCPPorts = [ 3389 ];
  # Send: Remmina as RDP/VNC client.
  environment.systemPackages = [ pkgs.remmina ];

  # ---------- GNOME theme defaults (locked) ----------
  # Force GNOME to use the stock Adwaita cursor and icon theme.
  # Without this, stale dconf values from a previous role (e.g. Bibata cursor
  # from the desktop role) persist in the user's ~/.config/dconf/user after
  # switching to vanilla.  Bibata is not installed here, so GNOME renders no
  # cursor.  A dconf lock ensures these keys override whatever the user db
  # contains, regardless of prior session history.
  # Vanilla is an intentional stock NixOS baseline; locking to Adwaita is
  # correct behaviour — switch to a different role for custom theming.
  programs.dconf.profiles.user.databases = [
    {
      settings."org/gnome/desktop/interface" = {
        cursor-theme = "Adwaita";
        icon-theme   = "Adwaita";
      };
      locks = [
        "/org/gnome/desktop/interface/cursor-theme"
        "/org/gnome/desktop/interface/icon-theme"
      ];
    }
  ];

  # ---------- State version ----------
  # Do NOT change after initial install.
  system.stateVersion = "25.11";
}
