# modules/flatpak-desktop.nix
# Desktop-role Flatpak additions: gaming, development, and productivity apps.
#
# Import only in configuration-desktop.nix.
# Requires: modules/flatpak.nix (declares vexos.flatpak.extraApps option).
#
# The vexos.flatpak.extraApps list option uses NixOS listOf merge semantics —
# multiple modules may set it and the values are concatenated automatically.
#
# Also sets vexos.flatpak.bundles (declared in modules/flatpak-bundles.nix) for
# apps that upstream ships only as release-asset .flatpak files.
{ pkgs, ... }:
let
  craft = pkgs.vexos.craft-apps;
  # pkgs.vexos.craft-apps.<name> → { appId; version; bundle; }
  asBundle = app: { id = app.appId; inherit (app) version; src = app.bundle; };
in
{
  vexos.flatpak.extraApps = [
    "org.onlyoffice.desktopeditors"             # Office suite
    "com.ranfdev.DistroShelf"                   # Distribution browser
    "org.gimp.GIMP"                             # GIMP — required by home/photogimp.nix's overlay
  ];

  vexos.flatpak.bundles = map asBundle [
    craft.wordcraft                             # Word processor   → Office folder
    craft.gridcraft                             # Spreadsheet      → Office folder
    craft.pdfcraft                              # PDF reader/editor → Office folder
    craft.photocraft                            # Photo editor     → Graphics folder (with PhotoGIMP)
  ];
}
