# modules/branding-display.nix
# Display-role branding additions: wallpapers and GDM login-screen logo.
#
# Import in any configuration with a display manager (desktop, server, htpc, stateless).
# Do NOT import on headless-server or other roles without a display.
#
# Requires: modules/branding.nix (must be imported first to declare vexos.branding.role).
{ pkgs, lib, config, ... }:
let
  role          = config.vexos.branding.role;
  pixmapsDir    = ../files/pixmaps + "/${role}";
  wallpapersDir = ../wallpapers    + "/${role}";

  # Role-specific wallpapers deployed to a stable Nix store path so the system
  # dconf profile can reference them without relying on home-manager activation.
  # Path available immediately after nixos-rebuild switch, before any session starts.
  vexosWallpapers = pkgs.runCommand "vexos-wallpapers" {} ''
    mkdir -p $out/share/backgrounds/vexos
    cp ${wallpapersDir}/vex-bb-light.jxl $out/share/backgrounds/vexos/vex-bb-light.jxl
    cp ${wallpapersDir}/vex-bb-dark.jxl  $out/share/backgrounds/vexos/vex-bb-dark.jxl
  '';
in
{
  # Deploy wallpapers to the Nix store so dconf settings can reference a
  # stable path (/run/current-system/sw/share/backgrounds/vexos/).
  environment.systemPackages = [ vexosWallpapers ];

  # GDM login-screen logo — deployed to /etc/ first; Nix store paths change on
  # every rebuild so dconf must point to a stable /etc path instead.
  environment.etc."vexos/gdm-logo.png".source = pixmapsDir + "/fedora-gdm-logo.png";

  # Sets org.gnome.login-screen.logo in the GDM system dconf profile.
  # NOTE: Defining programs.dconf.profiles.gdm here overrides the GDM package's
  # built-in /share/dconf/profile/gdm. lib.mkDefault on enableUserDb prevents
  # an evaluation conflict if the GDM NixOS module sets this option in future.
  programs.dconf.profiles.gdm = {
    enableUserDb = lib.mkDefault false;  # GDM system account — no per-user db
    databases = [
      {
        settings = {
          "org/gnome/login-screen" = {
            logo = "/etc/vexos/gdm-logo.png";
          };
        };
      }
    ];
  };
}
