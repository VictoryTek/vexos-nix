# pkgs/cockpit-identities/default.nix
# 45Drives Cockpit Identities — user and group management plugin for
# the Cockpit web admin UI.  Ships as pure static JS/HTML/CSS built by
# upstream CI; we extract the pre-built assets from the official Focal
# release package rather than attempting a Yarn Berry + Vite monorepo
# build (infeasible in the Nix sandbox — same reason cockpit-zfs was
# deferred in Phase B; see nas_phase_b_cockpit_zfs_spec.md).
#
# Note: upstream only publishes a Focal (Ubuntu 20.04) .deb — no Bookworm
# variant. Because the package is arch:all (pure static assets) and we
# only use dpkg-deb -x to extract file contents, the host OS of the .deb
# is irrelevant for our purposes.
#
# Installed to $out/share/cockpit/identities/ so Cockpit's XDG_DATA_DIRS
# scan discovers the plugin's manifest.json automatically (same pattern as
# cockpit-navigator and cockpit-file-sharing).
{ lib, stdenvNoCC, fetchurl, dpkg }:

stdenvNoCC.mkDerivation rec {
  pname = "cockpit-identities";
  version = "0.1.12";
  release = "1";

  src = fetchurl {
    url = "https://github.com/45Drives/cockpit-identities/releases/download/v${version}/cockpit-identities_${version}-${release}focal_all.deb";
    hash = "sha256-hdFBLaIQyG0OutNWJPxRLYlf1S8J7gqGKcwbw70Oglo=";
  };

  nativeBuildInputs = [ dpkg ];

  dontUnpack = true;
  dontConfigure = true;
  dontBuild = true;

  installPhase = ''
    runHook preInstall
    dpkg-deb -x "$src" extracted
    mkdir -p "$out/share/cockpit"
    cp -r extracted/usr/share/cockpit/identities "$out/share/cockpit/"
    runHook postInstall
  '';

  meta = with lib; {
    description = "User and group management plugin for the Cockpit web admin UI (45Drives)";
    homepage = "https://github.com/45Drives/cockpit-identities";
    license = licenses.gpl3Plus;
    platforms = platforms.linux;
    maintainers = [ ];
  };
}
