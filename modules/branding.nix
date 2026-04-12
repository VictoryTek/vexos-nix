# modules/branding.nix
# Custom vexos branding: Plymouth boot watermark and system pixmaps logos.
# Optionally sets the GDM login-screen logo via dconf.
#
# Plymouth enable is deliberately kept in modules/performance.nix.
# This module only sets the theme and logo (branding concerns).
{ pkgs, lib, config, ... }:
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

  # ── OS identity (os-release, GRUB/systemd-boot labels, hostnamectl) ────────
  # distroName: overrides NAME= and PRETTY_NAME= in /etc/os-release AND the
  # primary label in both GRUB and systemd-boot boot menu entries.
  # Marked internal=true in NixOS but fully supported for override.
  system.nixos.distroName = lib.mkDefault "VexOS Desktop";
  system.nixos.label      = "25.11";

  # distroId: overrides ID= in /etc/os-release.  When set to anything other
  # than "nixos", NixOS automatically adds ID_LIKE=nixos — correct for a
  # NixOS-based derivative — and sets DEFAULT_HOSTNAME= to this value.
  system.nixos.distroId = "vexos";

  # vendorName/vendorId: sets VENDOR_NAME= and appears in CPE_NAME=.
  system.nixos.vendorName = "VexOS";
  system.nixos.vendorId   = "vexos";

  # HOME_URL, ANSI_COLOR, SUPPORT_URL, and BUG_REPORT_URL are only emitted by
  # NixOS when distroId == "nixos"; they must be set explicitly here.
  # LOGO is set here (was previously a standalone line) to consolidate all
  # os-release customisations in one block.
  system.nixos.extraOSReleaseArgs = {
    LOGO           = "vexos-logo";
    HOME_URL       = "https://github.com/vexos-nix";
    SUPPORT_URL    = "https://github.com/vexos-nix/issues";
    BUG_REPORT_URL = "https://github.com/vexos-nix/issues";
    ANSI_COLOR     = "1;35"; # purple, matching VexOS brand
  };

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
  # GDM login-screen logo via the NixOS dconf profiles API.
  # NOTE: Defining programs.dconf.profiles.gdm here overrides the GDM
  # package's built-in /share/dconf/profile/gdm (which includes user-db:user
  # and a file-db pointing to greeter-dconf-defaults).  lib.mkDefault on
  # enableUserDb prevents an evaluation conflict if the GDM NixOS module ever
  # sets this option explicitly in a future nixpkgs release.
  programs.dconf.profiles.gdm = {
    enableUserDb = lib.mkDefault false;  # GDM system account — no per-user db
    databases = [
      # TODO: Re-include GDM's own greeter defaults (auto-suspend, a11y, etc.)
      # once the correct passthru attribute for the pre-compiled db is confirmed.
      # Candidates: pkgs.gdm.dconfDb or pkgs.gdm (verify against nixpkgs source).
      # Omitting for now — the primary branding goal (logo) is preserved below.
      {
        settings = {
          "org/gnome/login-screen" = {
            logo = "/etc/vexos/gdm-logo.png";
          };
        };
      }
    ];
  };

  # ── Boot menu entry cleanup ───────────────────────────────────────────────
  # Post-process systemd-boot .conf entries after each rebuild to shorten the
  # verbose auto-generated title.
  # Auto-generated: "VexOS Desktop VM (Generation N VexOS Desktop VM Xantusia 25.11 (Linux 6.6.132))"
  # Trimmed to:     "VexOS Desktop VM (Generation N Xantusia 25.11)"
  boot.loader.systemd-boot.extraInstallCommands = ''
    for f in /boot/loader/entries/*.conf; do
      [ -f "$f" ] || continue
      # Strip ", built on YYYY-MM-DD" date suffix
      ${pkgs.gnused}/bin/sed -i 's/, built on [0-9]\{4\}-[0-9]\{2\}-[0-9]\{2\}//' "$f"
      # Strip "(Linux X.X.X)" kernel version from generation description
      ${pkgs.gnused}/bin/sed -i 's/ (Linux [0-9][0-9]*\.[0-9][0-9]*\.[0-9][0-9]*)//' "$f"
      # Normalise outer title label to the current host distroName (fixes old
      # entries that were built before per-host distroName was set).
      # Matches "title VexOS <Role> <anything-not-a-paren>(Generation" and
      # replaces the outer label with the current host's distroName.
      ${pkgs.gnused}/bin/sed -i 's/^title VexOS [^(]*(Generation/title ${config.system.nixos.distroName} (Generation/' "$f"
      # Remove redundant "VexOS <Role> <Variant>" from inside generation parens
      # (new format — distroName includes the variant, e.g. "VexOS Desktop VM").
      ${pkgs.gnused}/bin/sed -i -E 's/\(Generation ([0-9]+) VexOS [A-Za-z]+ (AMD|NVIDIA|Intel|VM) ([A-Za-z]+ [0-9]+\.[0-9]+)\)/(Generation \1 \3)/' "$f"
      # Remove redundant "VexOS <Role>" from inside generation parens
      # (old format — no variant suffix in the inner label).
      ${pkgs.gnused}/bin/sed -i -E 's/\(Generation ([0-9]+) VexOS [A-Za-z]+ ([A-Za-z]+ [0-9]+\.[0-9]+)\)/(Generation \1 \2)/' "$f"
    done
  '';
}
