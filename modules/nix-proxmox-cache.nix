# modules/nix-proxmox-cache.nix
# SaumonNet proxmox-nixos binary cache.
#
# Imported only by configuration-server.nix and configuration-headless-server.nix
# — the roles that build Proxmox packages (see flake.nix proxmoxBase). The
# proxmox-nixos input deliberately does NOT follow this flake's nixpkgs
# (flake.nix:45-48), so proxmox-ve and its large Perl dependency tree would
# otherwise be compiled from source on every rebuild.
#
# Install-time coverage (the first `nixos-rebuild boot`, before this module is
# applied) is handled separately by the nixConfig block in flake.nix.
#
# nix.settings.substituters / trusted-public-keys are list options that merge by
# concatenation, so this appends to the entries in modules/nix.nix.
{ ... }:
{
  nix.settings = {
    substituters        = [ "https://cache.saumon.network/proxmox-nixos" ];
    trusted-public-keys = [ "proxmox-nixos:D9RYSWpQQC/msZUWphOY2I5RLH5Dd6yQcaHIuug7dWM=" ];
  };
}
