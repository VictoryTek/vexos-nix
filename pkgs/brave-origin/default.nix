# pkgs/brave-origin/default.nix
# Brave Origin — pre-built binary package (not yet in nixpkgs).
# Source: https://brave.com/origin/linux/
#
# To update to a new version:
#   1. Update `version` below.
#   2. Run:
#        HASH=$(nix-prefetch-url --unpack \
#          https://github.com/brave/brave-browser/releases/download/v<VER>/brave-origin-<VER>-linux-amd64.zip)
#        nix hash to-sri --type sha256 "$HASH"
#   3. Replace `hash` with the new SRI string.
{ lib
, stdenv
, fetchzip
, autoPatchelfHook
, makeWrapper
, bash
, alsa-lib
, at-spi2-core
, cairo
, cups
, dbus
, expat
, fontconfig
, freetype
, gdk-pixbuf
, glib
, gtk3
, gtk4
, libdrm
, libglvnd
, libpulseaudio
, libva
, libxkbcommon
, mesa
, nspr
, nss
, pango
, pipewire
, qt6
, snappy
, systemdLibs
, wayland
, libx11
, libxcomposite
, libxcursor
, libxdamage
, libxext
, libxfixes
, libxi
, libxrandr
, libxrender
, libxscrnsaver
, libxshmfence
, libxtst
, libxcb
, zlib
, krb5
}:

stdenv.mkDerivation rec {
  pname   = "brave-origin";
  version = "1.91.171";

  src = fetchzip {
    url    = "https://github.com/brave/brave-browser/releases/download/v${version}/brave-origin-${version}-linux-amd64.zip";
    hash   = "sha256-hg1ogGswGK+GxNQT/SmQ0ewJ2uRa6bLzIAH1yNI46Kw=";
    # The zip extracts to a flat directory (no top-level subdirectory).
    stripRoot = false;
  };

  nativeBuildInputs = [
    autoPatchelfHook
    makeWrapper
  ];

  buildInputs = [
    alsa-lib
    at-spi2-core
    cairo
    cups.lib
    dbus.lib
    expat
    fontconfig.lib
    freetype
    gdk-pixbuf
    glib
    gtk3
    gtk4
    libdrm
    libglvnd
    libpulseaudio
    libva
    libxkbcommon
    mesa
    nspr
    nss
    pango
    pipewire
    qt6.qtbase
    snappy
    systemdLibs
    wayland
    libx11
    libxcomposite
    libxcursor
    libxdamage
    libxext
    libxfixes
    libxi
    libxrandr
    libxrender
    libxscrnsaver
    libxshmfence
    libxtst
    libxcb
    zlib
    krb5.lib
  ];

  dontBuild     = true;
  dontConfigure = true;

  installPhase = ''
    runHook preInstall

    local appdir="$out/opt/brave.com/brave-origin"
    mkdir -p "$appdir" "$out/bin"

    # Copy the full binary bundle.
    cp -r . "$appdir/"

    # Remove distro-specific files that have no meaning on NixOS.
    rm -rf "$appdir/apparmor.d" "$appdir/cron"

    # Fix the bash shebang in the upstream wrapper script.
    substituteInPlace "$appdir/brave-origin" \
      --replace-fail "#!/bin/bash" "#!${bash}/bin/bash"

    chmod 755 "$appdir/brave-origin"

    # Symlink the wrapper into $out/bin.
    ln -s "$appdir/brave-origin" "$out/bin/brave-origin"

    # Install icons into the standard hicolor tree.
    for size in 16 24 32 48 64 128 256; do
      install -Dm644 "$appdir/product_logo_''${size}.png" \
        "$out/share/icons/hicolor/''${size}x''${size}/apps/brave-origin.png"
    done

    # Install a .desktop file (the zip ships none).
    mkdir -p "$out/share/applications"
    cat > "$out/share/applications/brave-origin.desktop" <<EOF
[Desktop Entry]
Version=1.0
Name=Brave Origin
GenericName=Web Browser
Comment=Access the Internet with Brave Origin
Exec=$out/bin/brave-origin %U
StartupNotify=true
Terminal=false
Icon=brave-origin
Type=Application
Categories=Network;WebBrowser;
MimeType=application/pdf;application/xhtml+xml;text/html;text/xml;x-scheme-handler/http;x-scheme-handler/https;
EOF

    runHook postInstall
  '';

  # Tell autoPatchelfHook to also search the bundle directory for the
  # bundled shared libs (libEGL.so, libGLESv2.so, libvk_swiftshader.so, etc.).
  preFixup = ''
    addAutoPatchelfSearchPath "$out/opt/brave.com/brave-origin"
  '';

  meta = {
    description = "Brave Origin — standalone desktop browser from Brave";
    homepage    = "https://brave.com/origin/linux/";
    license     = lib.licenses.mpl20;
    platforms   = [ "x86_64-linux" ];
    maintainers = [];
    mainProgram = "brave-origin";
  };
}
