# modules/ai.nix
# VexOS AI assistant: Claude Code and OpenCode, taught how VexOS works and
# fenced off from applying changes. The agent edits /etc/nixos side-files and
# dry-builds; the user runs `just rebuild`.
#
# Enable on a per-host basis via /etc/nixos/features.nix:
#   vexos.features.ai.enable = true;
#
# This module is only the toggle. The assistant itself (launcher, skills, agent
# deny policy, user services) lives in the vexos-ai flake input
# (github:VictoryTek/vexos-ai); its NixOS module is imported by flake.nix as
# vexosAiModule, same split as vpn.nix / vex-vpn.
{ config, lib, pkgs, ... }:
let
  cfg = config.vexos.features.ai;
in
{
  options.vexos.features.ai.enable = lib.mkEnableOption "AI assistant (Claude Code or OpenCode) that can change and troubleshoot VexOS";

  config = lib.mkMerge [
    (lib.mkIf cfg.enable {
      programs.vexos-ai = {
        enable = true;
        # unstable: agent CLIs move weekly
        claudePackage = pkgs.unstable.claude-code;
        opencodePackage = pkgs.unstable.opencode;
        claudeAcpPackage = pkgs.unstable.claude-agent-acp;
      };
    })

    # The vexos-ai module only installs the panel's Shell extension; this turns
    # it on by appending its uuid to the enabled-extensions default (see
    # vexos.gnome.extraExtensions in modules/gnome.nix).
    (lib.mkIf (config.programs.vexos-ai.enable && config.programs.vexos-ai.enablePanelExtension) {
      vexos.gnome.extraExtensions = [ "vexos-assistant@victorytek.github.io" ];
    })
  ];
}
