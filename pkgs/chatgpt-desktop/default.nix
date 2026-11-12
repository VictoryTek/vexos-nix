# pkgs/chatgpt-desktop/default.nix
# ChatGPT desktop app for Linux (includes Codex) — official pre-built Electron app.
# Source: https://developers.openai.com/codex/app (Linux preview, Aug 2026).
#
# Why a custom package: OpenAI ships it only as .deb/.rpm (plus an Arch install
# script). No Flatpak, no AppImage, not in nixpkgs. The binary is unfree.
#
# The "latest" download URLs OpenAI documents are unversioned, so a hash pinned
# against them would break the moment a new build is published. The .deb's own
# signed apt repository keeps versioned files under pool/, so this pins that
# instead (the same file `latest` points at):
#   https://persistent.oaistatic.com/codex-app-prod/linux/deb/pool/main/c/chatgpt/chatgpt_<VER>_amd64.deb
# The apt `Packages` index publishes each file's SHA256, so the update workflow
# never has to download the ~560 MB .deb to find the new hash.
#
# `version` and `hash` below are bumped automatically by
# .github/workflows/update-chatgpt-desktop-weekly-sunday.yml (weekly, plus manual
# workflow_dispatch). Prefer that over editing by hand — it builds the result before
# committing. To update manually anyway:
#   1. Read the current version and SHA256 from
#        https://persistent.oaistatic.com/codex-app-prod/linux/deb/dists/stable/main/binary-amd64/Packages
#   2. Set `version` below to that Version.
#   3. Convert the SHA256 and replace `hash`:
#        nix hash convert --hash-algo sha256 --to sri <SHA256>
#
# Layout inside the .deb: /usr/lib/chatgpt/ChatGPT (Electron), resources/codex (the
# bundled Codex CLI), resources/app.asar (not an ELF, left untouched). Wayland support
# is experimental upstream; the app uses XWayland by default. For native Wayland run
# `chatgpt --ozone-platform=wayland`.
{ lib
, stdenv
, fetchurl
, dpkg
, autoPatchelfHook
, makeWrapper
, alsa-lib
, at-spi2-atk
, at-spi2-core
, cairo
, cups
, dbus
, expat
, gdk-pixbuf
, glib
, gtk3
, libdrm
, libglvnd
, libnotify
, libpulseaudio
, libusb1
, libxkbcommon
, mesa
, nspr
, nss
, openssl
, pango
, systemdLibs
, tpm2-tss
, vulkan-loader
, xdg-utils
, xz
, zlib
, libx11
, libxcb
, libxcomposite
, libxdamage
, libxext
, libxfixes
, libxrandr
}:

stdenv.mkDerivation rec {
  pname   = "chatgpt-desktop";
  version = "26.1106.51428";

  src = fetchurl {
    url  = "https://persistent.oaistatic.com/codex-app-prod/linux/deb/pool/main/c/chatgpt/chatgpt_${version}_amd64.deb";
    hash = "sha256-g1anghkwsTW3QTR/rMvEPhaStEJMPqtxCpr1bAvrsTU=";
  };

  nativeBuildInputs = [
    dpkg
    autoPatchelfHook
    makeWrapper
  ];

  buildInputs = [
    alsa-lib
    at-spi2-atk
    at-spi2-core
    cairo
    cups.lib
    dbus.lib
    expat
    gdk-pixbuf
    glib
    gtk3
    libdrm
    libglvnd
    libnotify
    libpulseaudio
    libusb1
    libxkbcommon
    mesa
    nspr
    nss
    openssl
    pango
    systemdLibs
    tpm2-tss
    vulkan-loader
    xz
    zlib
    libx11
    libxcb
    libxcomposite
    libxdamage
    libxext
    libxfixes
    libxrandr
  ];

  # Libraries Electron/Chromium load with dlopen() at run time; autoPatchelfHook
  # cannot see those, so they go on the RPATH explicitly.
  runtimeDependencies = [
    libglvnd
    libnotify
    libpulseaudio
    libxkbcommon
    systemdLibs
    vulkan-loader
  ];

  # The bundled Qt shims (libqt5_shim.so, libqt6_shim.so) are dlopened optionally
  # for native file dialogs; Chromium falls back to GTK if they cannot load.
  autoPatchelfIgnoreMissingDeps = [
    "libQt5Core.so.5" "libQt5Gui.so.5" "libQt5Widgets.so.5"
    "libQt6Core.so.6" "libQt6Gui.so.6" "libQt6Widgets.so.6"
  ];

  dontConfigure  = true;
  dontBuild      = true;
  dontWrapQtApps = true;
  # ~1.8 GB of binaries: stripping is slow and the Electron/Codex binaries do not need it.
  dontStrip      = true;

  unpackPhase = ''
    runHook preUnpack
    dpkg-deb -x "$src" .
    runHook postUnpack
  '';

  installPhase = ''
    runHook preInstall

    mkdir -p "$out/lib" "$out/bin" "$out/share/applications" "$out/share/pixmaps"
    cp -r usr/lib/chatgpt "$out/lib/chatgpt"

    # Node addons ship musl-libc prebuilds next to the glibc ones (node-hid,
    # serialport). Their loader picks the glibc build here, and musl's libc does not
    # exist on NixOS, so they would only fail autoPatchelfHook.
    find "$out/lib/chatgpt" -iname '*musl*' -prune -exec rm -rf {} +

    # Call the Electron binary directly (the upstream codex-launcher is just a
    # /bin/sh exec of it). xdg-utils is a declared dependency of the .deb.
    makeWrapper "$out/lib/chatgpt/ChatGPT" "$out/bin/chatgpt" \
      --prefix PATH : ${lib.makeBinPath [ xdg-utils ]}

    install -Dm644 usr/share/pixmaps/chatgpt.png "$out/share/pixmaps/chatgpt.png"

    # Upstream's .desktop claims http/https and several document types, which would
    # make this app a candidate default browser/office handler. Keep only the codex://
    # scheme it needs for sign-in and deep links.
    sed -E 's|^MimeType=.*|MimeType=x-scheme-handler/codex;|' \
      usr/share/applications/chatgpt.desktop \
      > "$out/share/applications/chatgpt.desktop"

    runHook postInstall
  '';

  # Bundled libEGL.so, libGLESv2.so, libvk_swiftshader.so, libvulkan.so.1 live next
  # to the binary; let autoPatchelfHook resolve against them.
  preFixup = ''
    addAutoPatchelfSearchPath "$out/lib/chatgpt"
  '';

  meta = {
    description    = "ChatGPT desktop app for Linux, with Codex (official preview build)";
    homepage       = "https://developers.openai.com/codex/app";
    license        = lib.licenses.unfree;
    sourceProvenance = [ lib.sourceTypes.binaryNativeCode ];
    platforms      = [ "x86_64-linux" ];
    maintainers    = [ ];
    mainProgram    = "chatgpt";
  };
}
