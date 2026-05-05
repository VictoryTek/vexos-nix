# modules/nix-server.nix
# GC schedule for server and headless-server roles.
# Keeps generations for 30 days — provides a full-month rollback window,
# which is the standard for production/homelab servers: enough time to
# detect a regression across a real workload cycle before the store is pruned.
{ ... }:
{
  nix.gc = {
    automatic = true;
    dates     = "weekly";
    options   = "--delete-older-than 30d";
  };
}
