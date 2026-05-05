# modules/nix-stateless.nix
# GC schedule for the stateless role.
# Keeps generations for 7 days — short retention is appropriate because the
# OS user-space state resets on every reboot (impermanence); old NixOS
# generations have little practical rollback value beyond the current week.
{ ... }:
{
  nix.gc = {
    automatic = true;
    dates     = "weekly";
    options   = "--delete-older-than 7d";
  };
}
