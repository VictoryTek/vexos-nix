# modules/nix-desktop.nix
# GC schedule for desktop and HTPC roles.
# Keeps generations for 14 days — provides a 2-week rollback window, which
# is the widely-accepted workstation standard: long enough to notice a
# regression after a weekly update, short enough to avoid runaway store growth.
{ ... }:
{
  nix.gc = {
    automatic = true;
    dates     = "weekly";
    options   = "--delete-older-than 14d";
  };
}
