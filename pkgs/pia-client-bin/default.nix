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
{ lib, stdenvNoCC, fetchurl, makeWrapper, bash, libglvnd, fontconfig, freetype, xorg }:

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

    # Extract the makeself payload into a staging area.
    # --noexec prevents the installer script from running; --target sets the
    # extraction destination.  The archive layout has PIA's runtime files
    # under a piafiles/ subdirectory which mirrors the installed /opt/piavpn
    # structure (bin/, lib/, etc.).  We flatten that one level so the
    # conventional paths (bin/pia-client, lib/, lib/qt/plugins) work directly
    # under $out/share/pia-client.
    local stage="$TMPDIR/pia-stage"
    mkdir -p "$stage"
    bash ${src} --noexec --target "$stage"

    echo "--- PIA extraction layout (top 4 levels) ---"
    find "$stage" -maxdepth 4 | sort
    echo "--------------------------------------------"

    mkdir -p "$out/share/pia-client"
    if [ -d "$stage/piafiles" ]; then
      # Expected: piafiles/ contains the runtime tree (bin/, lib/, etc.)
      cp -r "$stage/piafiles/." "$out/share/pia-client/"
    elif [ -f "$stage/bin/pia-client" ]; then
      # Fallback: binaries are already at the top level
      cp -r "$stage/." "$out/share/pia-client/"
    else
      echo "ERROR: Could not locate PIA binaries.  See layout dump above."
      exit 1
    fi

    chmod -R u+rX "$out/share/pia-client"

    # ── Install real PIA icon ─────────────────────────────────────────────
    # The installer ships app-icon.png in installfiles/ alongside piafiles/.
    # Copy it to $out/share/pixmaps/piavpn.png so Icon=piavpn resolves.
    mkdir -p "$out/share/pixmaps"
    cp "$stage/installfiles/app-icon.png" "$out/share/pixmaps/piavpn.png"

    # ── Patch qt.conf hardcoded /opt/piavpn paths ─────────────────────────
    # The installer stores absolute paths to /opt/piavpn in qt.conf.
    # Rewrite them to point to the actual Nix store layout.
    sed -i \
      "s|Plugins=/opt/piavpn/plugins|Plugins=$out/share/pia-client/plugins|" \
      "$out/share/pia-client/bin/qt.conf"
    sed -i \
      "s|Libraries=/opt/piavpn/lib|Libraries=$out/share/pia-client/lib|" \
      "$out/share/pia-client/bin/qt.conf"
    sed -i \
      "s|Qml2Imports=/opt/piavpn/qml|Qml2Imports=$out/share/pia-client/qml|" \
      "$out/share/pia-client/bin/qt.conf"

    mkdir -p "$out/bin"

    # ── pia-client GUI wrapper ────────────────────────────────────────────
    # Prepend PIA's bundled Qt6 libs so PIA does not clash with system Qt.
    makeWrapper "$out/share/pia-client/bin/pia-client" "$out/bin/pia-client" \
      --set    NIX_LD_LIBRARY_PATH "/run/current-system/sw/share/nix-ld/lib" \
      --prefix LD_LIBRARY_PATH : "$out/share/pia-client/lib:${libglvnd}/lib:/run/opengl-driver/lib:${fontconfig.lib}/lib:${freetype}/lib:${xorg.libXau}/lib:${xorg.libXdmcp}/lib:/run/current-system/sw/share/nix-ld/lib" \
      --set    QT_PLUGIN_PATH "$out/share/pia-client/plugins" \
      --set    QML2_IMPORT_PATH "$out/share/pia-client/qml" \
      --set    XDG_SESSION_TYPE x11

    # ── piactl CLI wrapper ────────────────────────────────────────────────
    makeWrapper "$out/share/pia-client/bin/piactl" "$out/bin/piactl" \
      --set    NIX_LD_LIBRARY_PATH "/run/current-system/sw/share/nix-ld/lib" \
      --prefix LD_LIBRARY_PATH : "$out/share/pia-client/lib:/run/current-system/sw/share/nix-ld/lib"

    # ── pia-daemon wrapper ────────────────────────────────────────────────
    makeWrapper "$out/share/pia-client/bin/pia-daemon" "$out/bin/pia-daemon" \
      --set    NIX_LD_LIBRARY_PATH "/run/current-system/sw/share/nix-ld/lib" \
      --prefix LD_LIBRARY_PATH : "$out/share/pia-client/lib:/run/current-system/sw/share/nix-ld/lib"

    # ── Desktop entry ─────────────────────────────────────────────────────
    mkdir -p "$out/share/applications"
    cat > "$out/share/applications/pia-client.desktop" <<EOF
[Desktop Entry]
Type=Application
Name=Private Internet Access
Comment=Private Internet Access VPN client
Exec=$out/bin/pia-client %u
Icon=piavpn
Terminal=false
Categories=Network;
StartupWMClass=pia-client
MimeType=x-scheme-handler/piavpn;
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
