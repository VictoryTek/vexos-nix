# modules/system-latest-kernel.nix
# Latest kernel track — uses linuxPackages_latest (currently Linux 7.0).
# Import this in configuration-*.nix files for roles that want the newest kernel
# (desktop, stateless). The NVIDIA stable driver (580.142) builds and runs on
# Linux 7.x; the open kernel module is fetched from the binary cache and the
# proprietary userspace builds locally (it is never cached — unfree).
# Stability-focused roles (server, headless-server, htpc) use system-lts-kernel.nix.
{ pkgs, ... }:
{
  boot.kernelPackages = pkgs.linuxPackages_latest;
}
