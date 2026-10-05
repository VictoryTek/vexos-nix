# /etc/nixos/local.nix
# Free-form configuration for this machine only: extra packages, udev rules,
# services, tweaks — anything that is not a feature toggle (features.nix) or
# another side-file. It is an ordinary NixOS module, loaded when present by
# /etc/nixos/flake.nix, and never overwritten by the installer or updater.
#
# Prefer a VexOS option (vexos.*) when one exists. After editing, run
# `just rebuild` to apply; `just rollback` undoes the last rebuild.
{ config, pkgs, lib, ... }:
{
  # environment.systemPackages = with pkgs; [ htop ];
}
