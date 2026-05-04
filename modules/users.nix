# modules/users.nix
# Primary user account. Applies to all roles.
# Role-specific groups are appended by service modules (audio.nix, gaming.nix,
# virtualization.nix, etc.) via NixOS list merging.
{ lib, ... }:
{
  users.users.nimda = {
    isNormalUser = true;
    description  = "nimda";
    extraGroups  = [
      "wheel"
      "networkmanager"
    ];

    # Declarative SSH authorized keys.
    # The authorized_keys file at the repo root is populated by `just enable-ssh`.
    # builtins.pathExists guard: the build succeeds on fresh checkouts where the
    # file has not yet been created.
    openssh.authorizedKeys.keyFiles =
      lib.optional (builtins.pathExists ../authorized_keys) ../authorized_keys;
  };
}
