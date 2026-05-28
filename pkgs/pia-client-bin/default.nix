# pkgs/pia-client-bin/default.nix
# Pre-built PIA Linux client binary package (binary repack — no compilation).
# Source: https://www.privateinternetaccess.com/download/linux-vpn
#
# The installer is a makeself self-extracting archive. We run it with
# --noexec --target to extract the payload into the Nix store without
# actually executing the installer script.
#
# To update to a newer version:
#   1. Find the new installer URL on the PIA download page.
#   2. Compute the SRI hash:
#        nix hash to-sri --type sha256 \
#          $(nix-prefetch-url https://installers.privateinternetaccess.com/download/pia-linux-<VER>.run)
#   3. Update `version` and `hash` below.
{ lib, stdenvNoCC, fetchurl, makeWrapper, bash }:

stdenvNoCC.mkDerivation rec {
  pname   = "pia-client-bin";
  version = "3.7.2-08420";

  src = fetchurl {
    url  = "https://installers.privateinternetaccess.com/download/pia-linux-${version}.run";
    hash = "sha256-CKiK8ERiqeB4ru9SsmvNtW8Kmwh6D7dgb5i363m7Pdk=";
  };

  nativeBuildInputs = [ makeWrapper bash ];

  # The source is a makeself .run file, not a standard archive — skip unpack.
  dontUnpack = true;

  installPhase = ''
    runHook preInstall

    # Extract the makeself payload. --noexec prevents the installer from
    # running; --target sets the extraction destination.
    mkdir -p $out/share/pia-client
    bash ${src} --noexec --target $out/share/pia-client

    chmod -R u+rX $out/share/pia-client
    mkdir -p $out/bin

    # ── pia-client GUI wrapper ────────────────────────────────────────────
    # Prepend PIA's bundled Qt6 libs so PIA does not clash with system Qt.
    makeWrapper $out/share/pia-client/bin/pia-client $out/bin/pia-client \
      --set    NIX_LD_LIBRARY_PATH "/run/current-system/sw/share/nix-ld/lib" \
      --prefix LD_LIBRARY_PATH : "$out/share/pia-client/lib:/run/current-system/sw/share/nix-ld/lib" \
      --set    QT_PLUGIN_PATH "$out/share/pia-client/lib/qt/plugins"

    # ── piactl CLI wrapper ────────────────────────────────────────────────
    makeWrapper $out/share/pia-client/bin/piactl $out/bin/piactl \
      --set    NIX_LD_LIBRARY_PATH "/run/current-system/sw/share/nix-ld/lib" \
      --prefix LD_LIBRARY_PATH : "$out/share/pia-client/lib:/run/current-system/sw/share/nix-ld/lib"

    # ── pia-daemon wrapper ────────────────────────────────────────────────
    makeWrapper $out/share/pia-client/bin/pia-daemon $out/bin/pia-daemon \
      --set    NIX_LD_LIBRARY_PATH "/run/current-system/sw/share/nix-ld/lib" \
      --prefix LD_LIBRARY_PATH : "$out/share/pia-client/lib:/run/current-system/sw/share/nix-ld/lib"

    # ── Desktop entry ─────────────────────────────────────────────────────
    mkdir -p $out/share/applications
    cat > $out/share/applications/pia-client.desktop <<EOF
[Desktop Entry]
Type=Application
Name=Private Internet Access
GenericName=VPN Client
Comment=Connect using Private Internet Access
Exec=$out/bin/pia-client
Icon=network-vpn
Terminal=false
Categories=Network;Security;
EOF

    runHook postInstall
  '';

  meta = {
    description = "Private Internet Access VPN client";
    homepage    = "https://www.privateinternetaccess.com/";
    license     = lib.licenses.unfree;
    platforms   = [ "x86_64-linux" ];
    maintainers = [];
  };
}
