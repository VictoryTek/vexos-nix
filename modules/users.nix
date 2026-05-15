# modules/users.nix
# Primary user account. Applies to all roles.
# Role-specific groups are appended by service modules (audio.nix, gaming.nix,
# virtualization.nix, etc.) via NixOS list merging.
{ config, lib, ... }:
let
  cfg = config.vexos.user;
in
{
  options.vexos.user = {
    name = lib.mkOption {
      type        = lib.types.str;
      description = "Primary user account name for this system. Defaults to \"nimda\"; override per-host if needed.";
    };
  };

  config = {
    # Simple default — modules that append extraGroups use `config.vexos.user.name`
    # as an attrset key, which the NixOS module system must resolve before it can
    # enumerate `users.users` attribute names.  Auto-detecting from
    # `config.users.users` would create an infinite-recursion cycle, so the
    # default is a plain string.  Override in host files if needed.
    vexos.user.name = lib.mkDefault "nimda";

    users.users.nimda = {
      isNormalUser = true;
      description  = cfg.name;
      uid          = 1000;
      extraGroups  = [
        "wheel"
        "networkmanager"
      ];
    };
  };
}
