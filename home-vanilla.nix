# home-vanilla.nix
# Home Manager configuration for user "nimda" — Vanilla role.
# Absolute minimum: bash shell and git for managing the flake repo.
{ config, pkgs, lib, inputs, ... }:
{
  imports = [ ./home/bash-common.nix ];

  home.username      = "nimda";
  home.homeDirectory = "/home/nimda";

  # Minimal packages — git is required to manage the flake repository.
  home.packages = with pkgs; [
    git
    just
  ];

  # Deploy the justfile for 'just' commands from home dir.
  home.file."justfile".source = ./justfile;

  home.stateVersion = "24.05";
}
