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

    # A user who already has their own enabled-extensions list ignores the
    # system default above, so append the uuid to that list once. Runs after
    # vexos-init-extensions (home-*.nix) so a brand-new user's fixed list is
    # written first. An empty or unset list is left alone: the system default
    # applies there, and no stamp is written so a later login can still run.
    # The stamp means a user who turns the extension off is not overridden.
    # To redo: delete ~/.local/share/vexos/.vexos-ai-extension-enabled
    (lib.mkIf (config.programs.vexos-ai.enable
               && config.programs.vexos-ai.enablePanelExtension
               && config.services.desktopManager.gnome.enable) {
      systemd.user.services.vexos-ai-enable-extension = {
        description = "VexOS: enable the AI assistant GNOME extension in the user's list (once)";
        after       = [ "graphical-session.target" "vexos-init-extensions.service" ];
        partOf      = [ "graphical-session.target" ];
        wantedBy    = [ "graphical-session.target" ];
        serviceConfig = {
          Type            = "oneshot";
          RemainAfterExit = true;
          # The uuid is fixed here and reaches the script only as $1.
          ExecStart = "${pkgs.writeShellScript "vexos-ai-enable-extension" ''
            set -eu
            uuid="$1"
            key=/org/gnome/shell/enabled-extensions
            stamp="$HOME/.local/share/vexos/.vexos-ai-extension-enabled"
            [ -f "$stamp" ] && exit 0

            cur=$(${pkgs.dconf}/bin/dconf read "$key")
            case "$cur" in
              \[*\]) ;;
              *) exit 0 ;;   # unset, or not a list
            esac
            [ "$cur" = "[]" ] && exit 0

            case "$cur" in
              *"'$uuid'"*) ;;   # already listed
              *) ${pkgs.dconf}/bin/dconf write "$key" "''${cur%]}, '$uuid']" ;;
            esac

            ${pkgs.coreutils}/bin/mkdir -p "$HOME/.local/share/vexos"
            ${pkgs.coreutils}/bin/touch "$stamp"
          ''} vexos-assistant@victorytek.github.io";
        };
      };
    })
  ];
}
