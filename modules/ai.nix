# modules/ai.nix
# VexOS AI assistant: Claude Code and OpenCode, taught how VexOS works and
# fenced off from applying changes. The agent edits /etc/nixos side-files and
# dry-builds; the user runs `just rebuild`. See
# .github/docs/subagent_docs/vexos_ai_assistant_spec.md.
#
# Enable on a per-host basis via /etc/nixos/features.nix:
#   vexos.features.ai.enable = true;
#
# What it installs:
#   - claude-code + opencode (unstable: agent CLIs move weekly)
#   - vexos-ai (pkgs/vexos-ai): launcher, first-run picker, Claude accounts
#     and usage warnings, theme sync, "diagnose with AI"
#   - the VexOS skills (files/ai/skills) at /etc/vexos/ai/skills, linked into
#     ~/.claude/skills, which both Claude Code and OpenCode read
#   - system-wide (managed) agent policy denying switch/boot/rebuild
#   - user services: crash watcher, usage timer, theme watcher, welcome
{ config, lib, pkgs, ... }:
let
  cfg = config.vexos.features.ai;

  # Commands that apply a configuration, or evaluate every output at once.
  # Agents must hand these to the user. Rules match the command text the
  # agent writes, so they are a guardrail; the real gate is that applying
  # needs root and the agent has no terminal to answer sudo with.
  appliers = [
    "nixos-rebuild switch" "nixos-rebuild boot" "nixos-rebuild test"
    "just rebuild" "just switch" "just update" "just update-all"
    "nix flake check"
  ];
  privileged = cmd: [ cmd "sudo ${cmd}" "pkexec ${cmd}" ];
  denied = lib.concatMap privileged appliers;

  skills = [ "vexos" "vexos-diagnose" ];

  # The system profile on PATH: these services launch claude/opencode, the
  # terminal (xdg-terminal-exec) and vexos-ai itself by name.
  userService = description: script: {
    inherit description;
    partOf   = [ "graphical-session.target" ];
    after    = [ "graphical-session.target" ];
    wantedBy = [ "graphical-session.target" ];
    path     = [ "/run/current-system/sw" ];
    serviceConfig.ExecStart = "${pkgs.vexos.vexos-ai}/bin/vexos-ai ${script}";
  };
in
{
  options.vexos.features.ai.enable = lib.mkEnableOption "AI assistant (Claude Code or OpenCode) that can change and troubleshoot VexOS";

  config = lib.mkIf cfg.enable {
    environment.systemPackages = [
      pkgs.unstable.claude-code
      pkgs.unstable.opencode
      pkgs.vexos.vexos-ai
    ];

    # ── Skills ───────────────────────────────────────────────────────────────
    environment.etc."vexos/ai/skills".source = ../files/ai/skills;

    # One link per skill (not the whole directory) so the user's own skills in
    # ~/.claude/skills are left alone. L+ only replaces the link itself.
    systemd.user.tmpfiles.rules = map
      (s: "L+ %h/.claude/skills/${s} - - - - /etc/vexos/ai/skills/${s}")
      skills;

    # ── Agent policy ─────────────────────────────────────────────────────────
    # Claude Code: a managed-settings.d drop-in, so it merges with any other
    # admin policy instead of owning managed-settings.json. Managed values
    # cannot be overridden by user or project settings.
    environment.etc."claude-code/managed-settings.d/50-vexos.json".text = builtins.toJSON {
      permissions.deny = map (c: "Bash(${c} *)") denied;
    };

    # OpenCode: system-wide managed config, merged above the user's own.
    # Deny entries only, so the user's own permission defaults still apply.
    environment.etc."opencode/opencode.json".text = builtins.toJSON {
      "$schema" = "https://opencode.ai/config.json";
      autoupdate = false; # updated by Nix with the rest of the system
      permission.bash = lib.genAttrs (map (c: "${c}*") denied) (_: "deny");
    };

    # ── User services ────────────────────────────────────────────────────────
    systemd.user.services.vexos-ai-crash-watch = userService "Offer AI diagnosis when a program crashes" "crash-watch";
    systemd.user.services.vexos-ai-theme-watch = userService "Keep the AI assistant's theme in sync with the desktop" "theme-watch";
    # Simple, not oneshot: it waits on the notification for as long as the
    # user leaves it, which would trip a oneshot's start timeout.
    systemd.user.services.vexos-ai-welcome = userService "Invite the user to set up the AI assistant" "welcome";

    systemd.user.services.vexos-ai-usage = {
      description = "Check Claude subscription usage and warn near a limit";
      path = [ "/run/current-system/sw" ];
      serviceConfig.Type = "oneshot";
      serviceConfig.ExecStart = "${pkgs.vexos.vexos-ai}/bin/vexos-ai usage-check";
    };
    systemd.user.timers.vexos-ai-usage = {
      description = "Check Claude subscription usage every 10 minutes";
      wantedBy = [ "timers.target" ];
      timerConfig = {
        OnStartupSec = "2min";
        OnUnitActiveSec = "10min";
      };
    };
  };
}
