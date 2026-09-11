# modules/nix-noctalia-cache.nix
# Noctalia binary cache.
#
# Imported only by configuration-desktop.nix — the role that can build the
# Noctalia shell (see home/noctalia.nix, itself gated on
# vexos.desktop.environment == "hyprland"). The noctalia input deliberately
# does NOT follow this flake's nixpkgs (flake.nix, inputs.noctalia), because
# overriding it changes the derivation hash and misses this cache entirely —
# which would mean compiling a Qt/C++/Quickshell shell from source on every
# rebuild that touches it.
#
# Harmless on GNOME/COSMIC desktop hosts: a substituter that is never queried
# for a path it does not have costs nothing.
#
# Install-time coverage (the first `nixos-rebuild boot`, before this module is
# applied) is handled separately by the nixConfig block in flake.nix.
#
# nix.settings.substituters / trusted-public-keys are list options that merge by
# concatenation, so this appends to the entries in modules/nix.nix.
{ ... }:
{
  nix.settings = {
    substituters        = [ "https://noctalia.cachix.org" ];
    trusted-public-keys = [ "noctalia.cachix.org-1:pCOR47nnMEo5thcxNDtzWpOxNFQsBRglJzxWPp3dkU4=" ];
  };
}
