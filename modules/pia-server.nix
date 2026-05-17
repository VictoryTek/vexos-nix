{ pkgs, ... }:
{
  # PIA VPN — CLI-only support for server and headless-server roles
  # No GUI client; use piactl to connect, disconnect, and manage the daemon.
  # Install the client with: just pia-install
  # Control with: piactl connect, piactl disconnect, piactl get connectionstate

  # ── nix-ld: ELF interpreter shim ─────────────────────────────────────────
  # PIA bundles FHS-expecting binaries.  nix-ld installs a shim at
  # /lib64/ld-linux-x86-64.so.2 so the kernel can load PIA's daemon and
  # CLI binaries without a "No such file or directory" error.
  programs.nix-ld.enable = true;
  programs.nix-ld.libraries = with pkgs; [
    stdenv.cc.cc.lib
    glibc
    openssl
    libnl
    libcap
    zlib
    expat
  ];

  # ── Kernel modules ────────────────────────────────────────────────────────
  boot.kernelModules = [ "wireguard" "tun" ];

  # ── iproute2 routing table ────────────────────────────────────────────────
  # PIA's routing daemon reads /etc/iproute2/rt_tables to look up named policy
  # routing tables when setting up the kill switch and split-tunnel rules.
  environment.etc."iproute2/rt_tables".source =
    "${pkgs.iproute2}/share/iproute2/rt_tables";

  # ── Wrapper script ────────────────────────────────────────────────────────
  # Prepend /opt/piavpn/lib to LD_LIBRARY_PATH so piactl and the PIA daemon
  # load their bundled libraries rather than system ones.
  environment.systemPackages = [
    (pkgs.writeShellScriptBin "piactl" ''
      export LD_LIBRARY_PATH=/opt/piavpn/lib''${LD_LIBRARY_PATH:+:''${LD_LIBRARY_PATH}}
      exec /opt/piavpn/bin/piactl "$@"
    '')
  ];
}
