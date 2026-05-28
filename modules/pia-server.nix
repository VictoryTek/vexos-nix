{ pkgs, ... }:
{
  # PIA VPN — CLI-only support for server and headless-server roles
  # No GUI client; use piactl to connect, disconnect, and manage the daemon.
  # PIA is now managed via pkgs.vexos.pia-client-bin (binary repack).
  # No manual install required after a system rebuild.
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

  # ── PIA package ───────────────────────────────────────────────────────────
  # pkgs.vexos.pia-client-bin provides piactl and pia-daemon wrappers in
  # $out/bin with LD_LIBRARY_PATH already set. Version and hash are pinned
  # in pkgs/pia-client-bin/default.nix.
  environment.systemPackages = [
    pkgs.vexos.pia-client-bin
  ];
}
