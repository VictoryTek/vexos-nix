# home/bash-common.nix
# Common bash shell configuration shared across all roles.
# Role-specific aliases (if any) can be added in the role's home-*.nix file;
# Home Manager merges shellAliases from all imported modules.
{ ... }:
{
  programs.bash = {
    enable = true;
    shellAliases = {
      ll  = "ls -la";
      ".." = "cd ..";

      # Tailscale shortcuts
      ts   = "tailscale";
      tss  = "tailscale status";
      tsip = "tailscale ip";

      # System service shortcuts
      sshstatus = "systemctl status sshd";
    };
  };
}
