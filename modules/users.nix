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
      "samba-wsdd"   # allows gvfsd-wsdd to connect to the system wsdd socket
                     # at /run/wsdd/wsdd.sock (dir mode 0750, socket mode 0775)
    ];
  };
}
