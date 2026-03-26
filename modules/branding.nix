# modules/branding.nix
# Custom vexos branding: Plymouth boot watermark and system pixmaps logos.
# Optionally sets the GDM login-screen logo via dconf.
#
# Plymouth enable is deliberately kept in modules/performance.nix.
# This module only sets the theme and logo (branding concerns).
{ pkgs, lib, ... }:
let
  vexosLogos = pkgs.runCommand "vexos-logos" {} ''
    mkdir -p $out/share/pixmaps

    # Primary brand logo (deployed under two names)
    cp ${../files/pixmaps/vex.png}                   $out/share/pixmaps/vex.png
    cp ${../files/pixmaps/vex.png}                   $out/share/pixmaps/distributor-logo.png

    # White variant (dark-background logo — used by GDM and GNOME About dialog)
    cp ${../files/pixmaps/system-logo-white.png}     $out/share/pixmaps/system-logo-white.png

    # Size/format variants — renamed from fedora- to vex- at install time.
    # Source files retain their original names in git (preserving origin context).
    cp ${../files/pixmaps/fedora-gdm-logo.png}       $out/share/pixmaps/vex-gdm-logo.png
    cp ${../files/pixmaps/fedora-logo-small.png}     $out/share/pixmaps/vex-logo-small.png
    cp ${../files/pixmaps/fedora-logo-sprite.png}    $out/share/pixmaps/vex-logo-sprite.png
    cp ${../files/pixmaps/fedora-logo-sprite.svg}    $out/share/pixmaps/vex-logo-sprite.svg
    cp ${../files/pixmaps/fedora-logo.png}           $out/share/pixmaps/vex-logo.png
    cp ${../files/pixmaps/fedora_logo_med.png}       $out/share/pixmaps/vex-logo-med.png
    cp ${../files/pixmaps/fedora_whitelogo_med.png}  $out/share/pixmaps/vex-whitelogo-med.png

    # Background Logo extension — light and dark SVG variants
    cp ${../files/background_logos/fedora_lightbackground.svg} $out/share/pixmaps/vex-background-logo.svg
    cp ${../files/background_logos/fedora_darkbackground.svg}  $out/share/pixmaps/vex-background-logo-dark.svg
  '';

  # Hicolor icon entries for the "vexos-logo" icon name.
  # /etc/os-release is patched below to set LOGO=vexos-logo, so GNOME
  # Settings resolves the About-page logo by looking up "vexos-logo" in
  # the GTK icon theme.  Using a unique name avoids any conflict with the
  # nixos-icons package (which owns "nix-snowflake").
  vexosIcons = pkgs.runCommand "vexos-icons" {
    nativeBuildInputs = [ pkgs.gtk3 ];
  } ''
    # Scalable SVG — GTK4 prefers scalable for icon-name lookups
    mkdir -p $out/share/icons/hicolor/scalable/apps
    cp ${../files/pixmaps/fedora-logo-sprite.svg} \
       $out/share/icons/hicolor/scalable/apps/vexos-logo.svg

    # Raster PNGs at common sizes
    for size in 16 24 32 48 64 72 96 128 256 512 1024; do
      dir=$out/share/icons/hicolor/''${size}x''${size}/apps
      mkdir -p "$dir"
      cp ${../files/pixmaps/fedora-logo-sprite.png} "$dir/vexos-logo.png"
    done

    # index.theme is required by gtk-update-icon-cache
    cp ${pkgs.hicolor-icon-theme}/share/icons/hicolor/index.theme \
       $out/share/icons/hicolor/index.theme

    gtk-update-icon-cache -f -t $out/share/icons/hicolor
  '';
in
{
  # ── Plymouth boot splash ──────────────────────────────────────────────────
  # Switch from bgrt (ACPI firmware splash, does not display boot.plymouth.logo)
  # to spinner (displays boot.plymouth.logo as a centered watermark).
  # lib.mkDefault allows a host-level override, e.g. in hosts/vm.nix:
  #   boot.plymouth.theme = lib.mkForce "text";
  boot.plymouth.theme = lib.mkDefault "spinner";
  boot.plymouth.logo  = ../files/plymouth/watermark.png;

  # ── GNOME About-page logo ─────────────────────────────────────────────────
  # NixOS sets LOGO=nix-snowflake in /etc/os-release by default; GNOME
  # Settings reads that field and resolves the icon via the GTK icon-theme.
  # We override it to "vexos-logo" — a name owned exclusively by vexosIcons —
  # so there is no collision with the nixos-icons package.
  system.nixos.extraOSReleaseArgs.LOGO = "vexos-logo";

  # ── System pixmaps logos ──────────────────────────────────────────────────
  # Deploys branding files into /run/current-system/sw/share/pixmaps/.
  # XDG_DATA_DIRS includes /run/current-system/sw/share on NixOS, so all
  # GLib/GTK applications find these via standard g_get_system_data_dirs().
  environment.systemPackages = [ vexosLogos vexosIcons ];

  # ── GDM login-screen logo (optional) ─────────────────────────────────────
  # Nix store paths change on every rebuild; a dconf string value must point
  # to a stable path. Deploy the logo to /etc/ first, then reference it.
  environment.etc."vexos/gdm-logo.png".source = ../files/pixmaps/fedora-gdm-logo.png;

  # Sets org.gnome.login-screen.logo in the GDM system dconf profile.
  # If nix flake check reports a conflict with an existing gdm dconf profile
  # (set by the GNOME NixOS module), remove this block and use a
  # programs.dconf.packages entry or defer to home-manager instead.
  programs.dconf.profiles.gdm = {
    enableUserDb = false;  # GDM system account — no per-user preferences
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
