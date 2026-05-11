# pkgs/cockpit-navigator/default.nix
# 45Drives Cockpit Navigator — file-browser plugin for the Cockpit
# web admin UI. Static JS/HTML/CSS only; no daemon, no compilation.
# Drops files into $out/share/cockpit/navigator so Cockpit's
# XDG_DATA_DIRS scan finds them when this package is in
# environment.systemPackages.
#
# Upstream layout (verified for v0.5.12): the source `navigator/`
# directory at the repo root contains manifest.json and all runtime
# assets. Upstream's makefile install target is simply
#   cp -rpf navigator $(DESTDIR)/usr/share/cockpit
# which we mirror below — no build step required.
{ lib, stdenvNoCC, fetchFromGitHub }:

stdenvNoCC.mkDerivation rec {
  pname = "cockpit-navigator";
  version = "0.5.12";

  src = fetchFromGitHub {
    owner = "45Drives";
    repo = "cockpit-navigator";
    rev = "v${version}";
    hash = "sha256-1CRTTMyKdRQGwIdEVCwDH4nS4t6YzebNEUYRogWwpTc=";
  };

  dontConfigure = true;
  dontBuild = true;

  installPhase = ''
    runHook preInstall
    mkdir -p "$out/share/cockpit"
    cp -r navigator "$out/share/cockpit/"
    runHook postInstall
  '';

  meta = with lib; {
    description = "File browser plugin for the Cockpit web admin UI (45Drives)";
    homepage = "https://github.com/45Drives/cockpit-navigator";
    license = licenses.gpl3Only;
    platforms = platforms.linux;
    maintainers = [ ];
  };
}
