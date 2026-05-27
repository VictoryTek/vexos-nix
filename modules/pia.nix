{ lib, pkgs, ... }:
{
  # PIA VPN — nix-ld shim + wrapper scripts so PIA's official Linux client runs on NixOS
  # Install the client with: just pia-install
  # Control with piactl or the pia-client GUI

  # ── nix-ld: ELF interpreter shim ─────────────────────────────────────────
  # PIA bundles FHS-expecting binaries with an ELF interpreter path of
  # /lib64/ld-linux-x86-64.so.2.  nix-ld installs a shim at that path so
  # the kernel can load PIA's binaries without the "No such file or directory"
  # error from the missing interpreter.
  programs.nix-ld.enable = true;
  programs.nix-ld.libraries = with pkgs; [
    stdenv.cc.cc.lib
    glibc
    glib
    xorg.libX11
    xorg.libXext
    xorg.libXrender
    xorg.libXrandr
    xorg.libXcomposite
    xorg.libXdamage
    xorg.libXfixes
    xorg.libxcb
    xorg.libXi
    wayland
    libxkbcommon
    dbus
    openssl
    libnl
    libcap
    zlib
    expat
    fontconfig
    freetype
  ];

  # ── Kernel modules ────────────────────────────────────────────────────────
  boot.kernelModules = [ "wireguard" "tun" ];

  # ── iproute2 routing table ────────────────────────────────────────────────
  # PIA's routing daemon reads /etc/iproute2/rt_tables to look up named policy
  # routing tables when setting up the kill switch and split-tunnel rules.
  # NixOS does not create this file unless explicitly configured.
  environment.etc."iproute2/rt_tables".source =
    "${pkgs.iproute2}/share/iproute2/rt_tables";

  # ── Wrapper scripts ───────────────────────────────────────────────────────
  # Prepend /opt/piavpn/lib to LD_LIBRARY_PATH so PIA loads its own bundled
  # Qt6 rather than pulling in system Qt6 (version mismatches crash the GUI).
  environment.systemPackages = [
    (pkgs.writeShellScriptBin "pia-client" ''
      export NIX_LD_LIBRARY_PATH=/run/current-system/sw/share/nix-ld/lib
      export LD_LIBRARY_PATH=/opt/piavpn/lib:/run/current-system/sw/share/nix-ld/lib''${LD_LIBRARY_PATH:+:''${LD_LIBRARY_PATH}}
      export QT_PLUGIN_PATH=/opt/piavpn/lib/qt/plugins''${QT_PLUGIN_PATH:+:''${QT_PLUGIN_PATH}}
      exec /opt/piavpn/bin/pia-client "$@"
    '')
    (pkgs.writeShellScriptBin "piactl" ''
      export NIX_LD_LIBRARY_PATH=/run/current-system/sw/share/nix-ld/lib
      export LD_LIBRARY_PATH=/opt/piavpn/lib:/run/current-system/sw/share/nix-ld/lib''${LD_LIBRARY_PATH:+:''${LD_LIBRARY_PATH}}
      exec /opt/piavpn/bin/piactl "$@"
    '')
  ];

  # ── Preserve NIX_LD_LIBRARY_PATH through sudo ────────────────────────────
  # The nix-ld shim reads NIX_LD_LIBRARY_PATH to resolve libraries for
  # FHS-expecting binaries. sudo strips it by default, so PIA's bundled
  # utilities (date, rm, etc.) inside the installer can't find libatomic and
  # other GCC runtime libs — causing the installer to exit non-zero.
  security.sudo.extraConfig = lib.mkAfter ''
    Defaults env_keep += "NIX_LD_LIBRARY_PATH"
  '';

  # ── systemd service ───────────────────────────────────────────────────────
  # PIA's installer normally writes this file, but on NixOS /etc/systemd/system
  # is read-only. Declare it here so `systemctl start piavpn` works after the
  # PIA binaries have been installed to /opt/piavpn via `just pia`.
  systemd.services.piavpn = {
    description = "Private Internet Access daemon";
    after = [ "syslog.target" "network.target" ];
    wantedBy = [ ];   # not auto-started; user starts it manually via `just pia`
    serviceConfig = {
      Environment = [
        "NIX_LD_LIBRARY_PATH=/run/current-system/sw/share/nix-ld/lib"
        "LD_LIBRARY_PATH=/opt/piavpn/lib:/run/current-system/sw/share/nix-ld/lib"
      ];
      ExecStart   = "/opt/piavpn/bin/pia-daemon";
      Restart     = "always";
    };
  };
}
