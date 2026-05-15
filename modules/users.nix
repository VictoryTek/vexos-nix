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
      description = "Primary user account name for this system. Auto-detected from the first isNormalUser account.";
    };
  };

  config = {
    # Auto-detect the primary user from the first isNormalUser = true account.
    # lib.mkDefault allows hosts to override explicitly if needed.
    # Only isNormalUser is checked (not extraGroups) to avoid circular evaluation,
    # since other modules append extraGroups via config.vexos.user.name.
    vexos.user.name = lib.mkDefault (
      let normalUsers = builtins.filter
        (n: config.users.users.${n}.isNormalUser or false)
        (builtins.attrNames config.users.users);
      in
        if normalUsers == [] then
          builtins.throw "vexos: no isNormalUser account found — declare a user with isNormalUser = true"
        else
          builtins.head normalUsers
    );

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
