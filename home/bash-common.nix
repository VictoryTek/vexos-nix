# home/bash-common.nix
# Common bash shell configuration shared across all roles.
# Role-specific aliases (if any) can be added in the role's home-*.nix file;
# Home Manager merges shellAliases from all imported modules.
{ lib, osConfig, ... }:
{
  # ── Git identity & preferences ─────────────────────────────────────────────
  # userName defaults to the system user name. userEmail is intentionally left
  # blank — fill it in here or override in the role's home-*.nix.
  programs.git = {
    enable   = true;
    settings = {
      user = {
        name  = lib.mkDefault osConfig.vexos.user.name;
        email = lib.mkDefault "";
      };
      init.defaultBranch   = "main";
      pull.rebase          = true;
      push.autoSetupRemote = true;
    };
  };

  programs.bash = {
    enable = true;
    shellAliases = {
      ll  = "ls -la";
      ".." = "cd ..";

      # Always resolve the vexos justfile from /etc/nixos so `just` works
      # regardless of the current working directory (critical on stateless
      # where ~ is a tmpfs and contains no justfile).
      just = "just --justfile /etc/nixos/justfile --working-directory /etc/nixos";

      # Tailscale shortcuts
      ts   = "tailscale";
      tss  = "tailscale status";
      tsip = "tailscale ip";

      # System service shortcuts
      sshstatus = "systemctl status sshd";
    };
  };
}
