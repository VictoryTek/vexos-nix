# pkgs/cockpit-file-sharing/default.nix
# 45Drives cockpit-file-sharing — Samba + NFS share management plugin for
# the Cockpit web admin UI.  Ships as pure static JS/HTML/CSS built by
# upstream CI; we extract the pre-built assets from the official Debian
# Bookworm release package rather than attempting a Yarn Berry v4 monorepo
# build (which is infeasible in the Nix sandbox — same reason cockpit-zfs
# was deferred in Phase B; see nas_phase_b_cockpit_zfs_spec.md).
#
# Installed to $out/share/cockpit/file-sharing/ so Cockpit's XDG_DATA_DIRS
# scan discovers the plugin's manifest.json automatically (same pattern as
# cockpit-navigator; see Phase A spec for details).
#
# Python venv (awscurl, for S3 management) is deliberately skipped —
# Samba + NFS tabs work via shell commands (net conf, exportfs) only.
{ lib, stdenvNoCC, fetchurl, dpkg }:

stdenvNoCC.mkDerivation rec {
  pname = "cockpit-file-sharing";
  version = "4.5.6";
  release = "1";

  src = fetchurl {
    url = "https://github.com/45Drives/cockpit-file-sharing/releases/download/v${version}-${release}/cockpit-file-sharing_${version}-${release}bookworm_all.deb";
    hash = "sha256-Jxcp4ucfUbX5BtsMBWvGfeHZBsxl5Yh52CKpuiUQolQ=";
  };

  nativeBuildInputs = [ dpkg ];

  dontUnpack = true;
  dontConfigure = true;
  dontBuild = true;

  installPhase = ''
    runHook preInstall
    dpkg-deb -x "$src" extracted
    mkdir -p "$out/share/cockpit"
    cp -r extracted/usr/share/cockpit/file-sharing "$out/share/cockpit/"
    runHook postInstall
  '';

  meta = with lib; {
    description = "Samba and NFS share management plugin for the Cockpit web admin UI (45Drives)";
    homepage = "https://github.com/45Drives/cockpit-file-sharing";
    license = licenses.gpl3Plus;
    platforms = platforms.linux;
    maintainers = [ ];
  };
}
