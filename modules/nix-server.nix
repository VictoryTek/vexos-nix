# modules/nix-server.nix
# GC schedule for server and headless-server roles.
# Keeps generations for 14 days — a two-week rollback window, matching
# desktop/HTPC. Homelab servers often boot from small OS drives and are
# rebuilt frequently, so a longer window piles up old generations and eats
# disk (30 days kept ~21 GiB on a 128 GB drive).
{ ... }:
{
  nix.gc = {
    automatic = true;
    dates     = "weekly";
    options   = "--delete-older-than 14d";
  };
}
