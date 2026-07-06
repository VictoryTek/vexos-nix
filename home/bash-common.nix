# home/bash-common.nix
# Common bash shell configuration shared across all roles.
# Role-specific aliases (if any) can be added in the role's home-*.nix file;
# Home Manager merges shellAliases from all imported modules.
{ lib, osConfig, ... }:
{
  # ── Git identity & preferences ─────────────────────────────────────────────
  # userName defaults to the system user name. userEmail is intentionally left
  # unset (not blank) so git's own identity-detection fallback and warning
  # apply — set it here or override in the role's home-*.nix.
  programs.git = {
    enable   = true;
    settings = {
      user = {
        name = lib.mkDefault osConfig.vexos.user.name;
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

      # Tailscale shortcuts
      ts   = "tailscale";
      tss  = "tailscale status";
      tsip = "tailscale ip";

      # System service shortcuts
      sshstatus = "systemctl status sshd";
    }
    # Always resolve the vexos justfile from /etc/nixos so `just` works
    # regardless of the current working directory (critical on stateless
    # where ~ is a tmpfs and contains no justfile). Only set when
    # modules/packages-common.nix has actually deployed the file — the
    # vanilla role deliberately doesn't import it, so `just` isn't
    # installed there either and the alias would otherwise be dead.
    // lib.optionalAttrs (osConfig.environment.etc ? "nixos/justfile") {
      just = "just --justfile /etc/nixos/justfile --working-directory /etc/nixos";
    };
  };
}
