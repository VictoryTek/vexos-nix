# pkgs/tmog/default.nix
# TMOG (TaskManagerOG) — pre-built AppImage (not in nixpkgs, no GitHub releases feed).
# Source: https://tmog.org/
#
# Packaged via appimageTools.wrapType2, which extracts the AppImage into the Nix store
# at build time. At runtime this runs as a normal wrapped binary — no appimage-run/FUSE
# involved, unlike raw AppImages run through modules/appimage.nix.
#
# `version` and `hash` below are bumped automatically by
# .github/workflows/update-tmog-weekly-friday.yml (weekly, plus manual workflow_dispatch).
# Prefer that over editing by hand — it builds the result before committing. To update
# manually anyway:
#   1. Update `version` below (check https://tmog.org/ for the current AppImage filename).
#   2. Run:
#        HASH=$(nix-prefetch-url https://tmog.org/downloads/TaskManagerOG-<VER>-x86_64.AppImage)
#        nix hash convert --hash-algo sha256 --to sri "$HASH"
#   3. Replace `hash` with the new SRI string.
{ lib, appimageTools, fetchurl }:

let
  pname = "tmog";
  version = "1.0.0";

  src = fetchurl {
    url = "https://tmog.org/downloads/TaskManagerOG-${version}-x86_64.AppImage";
    hash = "sha256-7jd6c5SfiQhju8+tCd02tgugR28Me8vQ0Os0NeKQKpY=";
  };

  # Pulls the AppImage's own .desktop file and hicolor icon set out at build time so
  # neither has to be hand-authored (unlike brave-origin, whose upstream zip ships
  # neither).
  appimageContents = appimageTools.extractType2 { inherit pname version src; };
in
appimageTools.wrapType2 {
  inherit pname version src;

  extraInstallCommands = ''
    install -m 444 -D ${appimageContents}/com.tmog.taskmanager.desktop \
      $out/share/applications/com.tmog.taskmanager.desktop
    substituteInPlace $out/share/applications/com.tmog.taskmanager.desktop \
      --replace-fail 'Exec=tmog-task-manager' 'Exec=${pname}'

    for size in 32 48 64 128 256 512; do
      install -m 444 -D \
        ${appimageContents}/usr/share/icons/hicolor/''${size}x''${size}/apps/tmog-task-manager.png \
        $out/share/icons/hicolor/''${size}x''${size}/apps/tmog-task-manager.png
    done
  '';

  meta = {
    description = "Native cross-platform system monitor and task manager (TMOG) by Dave Plummer";
    homepage = "https://tmog.org";
    license = lib.licenses.unfree;
    platforms = [ "x86_64-linux" ];
    maintainers = [ ];
    mainProgram = "tmog";
  };
}
