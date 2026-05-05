# modules/users.nix
# Primary user account. Applies to all roles.
# Role-specific groups are appended by service modules (audio.nix, gaming.nix,
# virtualization.nix, etc.) via NixOS list merging.
{ ... }:
{
  users.users.nimda = {
    isNormalUser = true;
    description  = "nimda";
    extraGroups  = [
      "wheel"
      "networkmanager"
    ];
  };
}
