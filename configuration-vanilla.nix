# configuration-vanilla.nix
# Vanilla role: stock NixOS baseline for system restore.
# Intentionally minimal by default — mirrors what a default nixos-generate-config +
# GNOME desktop selection produces. Does NOT include, by default: custom kernel,
# performance tuning, ZRAM, AppArmor, gaming, Flatpak, branding, or custom packages.
# Optional features (gaming, development, print3d, virtualization, sunshine) are
# available via /etc/nixos/features.nix — see `just enable-feature` — but none are
# enabled unless explicitly opted into; vanilla stays stock until then.
{ config, pkgs, lib, ... }:

{
  imports = [
    ./modules/locale.nix
    ./modules/users.nix
    ./modules/nix.nix
    ./modules/notify.nix
    ./modules/asus-opt.nix
    ./modules/boot-discovery.nix
    ./modules/flatpak.nix            # required by gaming.nix / 3d-print.nix's managedApps declarations below
    ./modules/gaming.nix             # optional: vexos.features.gaming.enable (bundles gpu-gaming + system-gaming)
    ./modules/development.nix        # optional: vexos.features.development.enable
    ./modules/3d-print.nix           # optional: vexos.features.print3d.enable
    ./modules/virtualization.nix     # optional: vexos.features.virtualization.enable
    ./modules/sunshine.nix           # optional: vexos.features.sunshine.enable
  ];

  # Stub option: gaming.nix (imported above) sets vexos.gnome.extraExtensions to
  # auto-enable a GNOME Shell tray extension. That option is normally declared
  # AND consumed by modules/gnome.nix / gnome-desktop.nix (extension-list merge
  # into dconf enabled-extensions) — vanilla deliberately doesn't import those
  # (its own minimal, hand-rolled GNOME setup, no custom extensions by design).
  # Declaring the option here only satisfies evaluation; nothing on vanilla
  # reads it, so this is an intentional no-op. The GameMode package itself
  # (pkgs.gnomeExtensions.gamemode-shell-extension) is still installed via
  # gaming.nix's environment.systemPackages and can be enabled manually through
  # the GNOME Extensions app if desired.
  options.vexos.gnome.extraExtensions = lib.mkOption {
    type    = lib.types.listOf lib.types.str;
    default = [];
  };

  config = {
    # ---------- Bootloader ----------
    # systemd-boot with EFI — same as nixos-generate-config defaults.
    # lib.mkDefault allows hardware-configuration.nix to override for BIOS/GRUB.
    boot.loader.systemd-boot.enable      = lib.mkDefault true;
    boot.loader.efi.canTouchEfiVariables = lib.mkDefault true;

    # ---------- Networking ----------
    networking.hostName = lib.mkDefault "vexos";
    networking.networkmanager.enable = true;

    # ---------- Optional features (off by default — see imports above) ----------
    # modules/flatpak.nix is imported only because gaming.nix / 3d-print.nix
    # reference vexos.flatpak.managedApps — it defaults vexos.flatpak.enable to
    # true, which would silently start installing Flatpak apps on a role that's
    # supposed to stay stock. Override back to false here so vanilla remains
    # stock until a user explicitly opts in. Note: enabling e.g. gaming without
    # also setting vexos.flatpak.enable = true installs its regular packages
    # (Steam, Proton, GameMode, ...) but not its Flatpak-managed extras (Lutris,
    # ProtonPlus, PrismLauncher) — both toggles are needed for those.
    vexos.flatpak.enable = lib.mkDefault false;

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
  };
}
