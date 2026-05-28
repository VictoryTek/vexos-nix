{ lib, pkgs, ... }:
{
  # PIA VPN — declarative package + nix-ld shim so PIA's official Linux client runs on NixOS
  # PIA is now managed via pkgs.vexos.pia-client-bin (binary repack in pkgs/pia-client-bin/).
  # No manual install required after a system rebuild.
  # Control with piactl or the pia-client GUI, or use: just pia
  #
  # Migration note: /opt/piavpn was the legacy mutable install path; it is no longer used
  # by this module. The piaRuntimeUnitCleanup activation script below handles the transition.

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

  # ── PIA package ───────────────────────────────────────────────────────────
  # pkgs.vexos.pia-client-bin provides pia-client, piactl, and pia-daemon
  # wrappers in $out/bin with LD_LIBRARY_PATH already set, plus a desktop
  # entry at $out/share/applications/pia-client.desktop.
  # Version and hash are pinned in pkgs/pia-client-bin/default.nix.
  environment.systemPackages = [
    pkgs.vexos.pia-client-bin
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
  # Declare the piavpn service here so `systemctl start piavpn` works on
  # NixOS (where /etc/systemd/system is read-only).
  # ExecStart and library paths point to the Nix store package.
  systemd.services.piavpn = {
    description = "Private Internet Access daemon";
    after = [ "syslog.target" "network.target" ];
    wantedBy = [ ];   # not auto-started; user starts it manually via `just pia`
    serviceConfig = {
      Environment = [
        "NIX_LD_LIBRARY_PATH=/run/current-system/sw/share/nix-ld/lib"
        "LD_LIBRARY_PATH=${pkgs.vexos.pia-client-bin}/share/pia-client/lib:/run/current-system/sw/share/nix-ld/lib"
      ];
      ExecStart   = "${pkgs.vexos.pia-client-bin}/share/pia-client/bin/pia-daemon";
      Restart     = "always";
    };
  };

  # ── Cleanup stale runtime fallback unit ───────────────────────────────────
  # `just pia` can create /run/systemd/system/piavpn.service as a temporary
  # fallback before the declarative unit is available. Once this module is
  # active, remove the runtime fallback so rebuilds always use the declarative
  # unit (which has the current environment and library paths).
  system.activationScripts.piaRuntimeUnitCleanup = {
    deps = [ "etc" ];
    text = ''
      if [ -e /etc/systemd/system/piavpn.service ] && [ -e /run/systemd/system/piavpn.service ]; then
        rm -f /run/systemd/system/piavpn.service
        ${pkgs.systemd}/bin/systemctl daemon-reload >/dev/null 2>&1 || true
        ${pkgs.systemd}/bin/systemctl reset-failed piavpn >/dev/null 2>&1 || true
      fi
    '';
  };
}
