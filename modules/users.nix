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
    # builtins.pathExists guard: evaluates against the nix store path of the fetched
    # flake — only applies if authorized_keys is committed to the upstream repo.
    # For runtime SSH access, use `just enable-ssh` which writes to
    # ~/.ssh/authorized_keys (persists across rebuilds, no repo commit required).
    openssh.authorizedKeys.keyFiles =
      lib.optional (builtins.pathExists ../authorized_keys) ../authorized_keys;
  };
}
