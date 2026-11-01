# pkgs/curseforge/default.nix
# CurseForge app — official pre-built AppImage from Overwolf.
# Source: https://www.curseforge.com/download/app
#
# Why not nixpkgs: no CurseForge package exists there. The documented download
# URL (curseforge-latest-linux.AppImage) is unversioned and changes under a fixed
# hash, so this pins the versioned file from the same CDN instead
# (verified byte-identical to the "latest" download for 1.325.0-41594).
#
# Packaged via appimageTools.wrapType2 (extracted at build time, no FUSE at runtime).
# Proprietary (Overwolf), so unfree; nixpkgs.config.allowUnfree is already set.
#
# To update:
#   1. Read the current version from
#      https://curseforge.overwolf.com/electron/linux/latest-linux.yml
#   2. Set `version` below (format: <semver>-<build>, e.g. 1.325.0-41594).
#   3. Run:
#        HASH=$(nix-prefetch-url https://curseforge.overwolf.com/electron/linux/CurseForge-<VER>.AppImage)
#        nix hash convert --hash-algo sha256 --to sri "$HASH"
#   4. Replace `hash` with the new SRI string.
{ lib, appimageTools, fetchurl }:

let
  pname = "curseforge";
  version = "1.325.0-41594";

  src = fetchurl {
    url = "https://curseforge.overwolf.com/electron/linux/CurseForge-${version}.AppImage";
    hash = "sha256-vJpsXJabVyp6Ge+NPRwoy7yNUtlsO5xG7I1MrqUW7zc=";
  };

  appimageContents = appimageTools.extractType2 { inherit pname version src; };
in
appimageTools.wrapType2 {
  inherit pname version src;

  extraInstallCommands = ''
    install -m 444 -D ${appimageContents}/curseforge.desktop \
      $out/share/applications/curseforge.desktop
    substituteInPlace $out/share/applications/curseforge.desktop \
      --replace-fail 'Exec=AppRun --no-sandbox %U' 'Exec=${pname} --no-sandbox %U'

    for size in 16 32 48 64 128 256 512; do
      install -m 444 -D \
        ${appimageContents}/usr/share/icons/hicolor/''${size}x''${size}/apps/curseforge.png \
        $out/share/icons/hicolor/''${size}x''${size}/apps/curseforge.png
    done
  '';

  meta = {
    description = "CurseForge — game mod and addon manager";
    homepage = "https://www.curseforge.com/download/app";
    license = lib.licenses.unfree;
    platforms = [ "x86_64-linux" ];
    maintainers = [ ];
    mainProgram = "curseforge";
  };
}
