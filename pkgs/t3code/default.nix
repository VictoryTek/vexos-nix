# pkgs/t3code/default.nix
# T3 Code — official pre-built AppImage from GitHub releases.
# Source: https://github.com/pingdotgg/t3code
#
# Why not nixpkgs: pkgs.t3code lags upstream (stable 0.0.24, unstable 0.1.2 vs
# upstream 0.1.5 at the time of writing). Why not Flatpak: upstream publishes none and
# Flathub has no listing.
#
# Packaged via appimageTools.wrapType2, which extracts the AppImage into the Nix store
# at build time. At runtime this runs as a normal wrapped binary — no appimage-run/FUSE
# involved, unlike raw AppImages run through modules/appimage.nix.
#
# Tracks the latest *stable* release (not the several-per-day nightlies).
# `version` and `hash` below are bumped automatically by
# .github/workflows/update-t3code-weekly-saturday.yml (weekly, plus manual
# workflow_dispatch). Prefer that over editing by hand — it builds the result before
# committing. To update manually anyway:
#   1. Update `version` below (latest non-prerelease at
#      https://github.com/pingdotgg/t3code/releases).
#   2. Run:
#        HASH=$(nix-prefetch-url https://github.com/pingdotgg/t3code/releases/download/v<VER>/T3-Code-<VER>-x86_64.AppImage)
#        nix hash convert --hash-algo sha256 --to sri "$HASH"
#   3. Replace `hash` with the new SRI string.
{ lib, appimageTools, fetchurl }:

let
  pname = "t3code";
  version = "0.1.6";

  src = fetchurl {
    url = "https://github.com/pingdotgg/t3code/releases/download/v${version}/T3-Code-${version}-x86_64.AppImage";
    hash = "sha256-CeJQcgjHeTCbOWvoRq6h2UUUS9eAYGiZwvSByW3fNNA=";
  };

  # Pulls the AppImage's own .desktop file and hicolor icon set out at build time so
  # neither has to be hand-authored.
  appimageContents = appimageTools.extractType2 { inherit pname version src; };
in
appimageTools.wrapType2 {
  inherit pname version src;

  extraInstallCommands = ''
    install -m 444 -D ${appimageContents}/t3code.desktop \
      $out/share/applications/t3code.desktop
    substituteInPlace $out/share/applications/t3code.desktop \
      --replace-fail 'Exec=AppRun %U' 'Exec=${pname} %U'

    for size in 16 22 24 32 48 64 128 256 512; do
      install -m 444 -D \
        ${appimageContents}/usr/share/icons/hicolor/''${size}x''${size}/apps/t3code.png \
        $out/share/icons/hicolor/''${size}x''${size}/apps/t3code.png
    done
  '';

  meta = {
    description = "T3 Code — desktop app for coding agents";
    homepage = "https://t3.codes";
    license = lib.licenses.mit;
    platforms = [ "x86_64-linux" ];
    maintainers = [ ];
    mainProgram = "t3code";
  };
}
