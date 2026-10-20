# pkgs/craft-apps/default.nix
# storytold "Crafting Apps" (Wordcraft, GridCraft, PdfCraft, PhotoCraft, …) —
# upstream distributes them only as `.flatpak` bundles attached to GitHub releases
# (no Flatpak remote), so they are fetched here and installed by
# modules/flatpak-bundles.nix with `flatpak install --bundle`.
#
# Versions and hashes live in pins.json and are bumped automatically by
# .github/workflows/update-craft-apps-daily.yml. To add another Craft app, add its
# repo name to pins.json with any version/hash (the workflow corrects them) — the
# repo name must match the release asset prefix (<name>-<ver>-linux-x86_64.flatpak)
# and the app ID (ai.storyteller.<name>). Apps outside the storytold org (SolidCraft
# lives at tangency-labs) set an optional "owner" in their pin.
#
# To update an entry manually:
#   HASH=$(nix-prefetch-url \
#     https://github.com/storytold/<name>/releases/download/v<VER>/<name>-<VER>-linux-x86_64.flatpak)
#   nix hash convert --hash-algo sha256 --to sri "$HASH"
{ lib, fetchurl }:
let
  pins = builtins.fromJSON (builtins.readFile ./pins.json);
in
lib.mapAttrs (name: pin: {
  appId   = "ai.storyteller.${name}";
  version = pin.version;
  bundle  = fetchurl {
    url  = "https://github.com/${pin.owner or "storytold"}/${name}/releases/download/v${pin.version}/${name}-${pin.version}-linux-x86_64.flatpak";
    hash = pin.hash;
  };
}) pins
