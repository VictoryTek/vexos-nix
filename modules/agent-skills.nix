# modules/agent-skills.nix
# One central set of agent skills, installed once per device and linked for every
# agent: Claude Code reads ~/.claude/skills, Codex, opencode and others read
# ~/.agents/skills.
#
#   - files/agent-skills/<name>/   this repo's own skills. Linked when
#                                  vexos.features.ai or vexos.features.development is on.
#   - programs.vexos-ai.skills     the skills the vexos-ai input ships (vexos,
#                                  vexos-diagnose). Linked only when vexos.features.ai
#                                  is on: they tell the agent to edit /etc/nixos and rely
#                                  on the managed policy that only the ai feature installs.
#
# The combined set is built once (one linkFarm in the Nix store) and published
# read-only at /etc/vexos/agent-skills. Each skill is linked on its own (never the
# whole directory) into the primary user's ~/.claude/skills and ~/.agents/skills, so
# the user's other skills there are left alone. `L+` replaces whatever is at the link
# path itself, including a real directory of the same name.
#
# The per-agent links point at the store path of that same set, not at /etc: apps that
# run in a sandbox with their own /etc (T3 Code's FHS env) cannot see /etc/vexos, and
# Claude Code silently skips a skill whose link is broken. /nix is visible everywhere.
#
# Imported by every role that imports development.nix or ai.nix (desktop, htpc, server,
# vanilla). headless-server and stateless import neither, so they do not import this.
# vanilla has no vexos-ai module, and an older locked vexos-ai has no `skills`
# option: in both cases the vexos-ai skills are skipped without an error.
{ config, lib, pkgs, options, ... }:
let
  featureOn = name:
    lib.hasAttrByPath [ "vexos" "features" name ] options
    && config.vexos.features.${name}.enable;

  aiOn = featureOn "ai";
  devOn = featureOn "development";

  # Names come from readDir on source paths, so nothing is built to read them.
  # A folder is a skill only if it holds a SKILL.md (files/agent-skills/.upstream
  # keeps the license and source notes for skills copied in bulk).
  localDir = ../files/agent-skills;
  localSkills = lib.filterAttrs (name: _: builtins.pathExists (localDir + "/${name}/SKILL.md"))
    (lib.mapAttrs (name: _: localDir + "/${name}")
      (lib.filterAttrs (_: type: type == "directory") (builtins.readDir localDir)));

  hasAiSkills = lib.hasAttrByPath [ "programs" "vexos-ai" "skills" ] options;
  aiSkills =
    if aiOn && hasAiSkills
    then
      let s = config.programs.vexos-ai.skills;
      in lib.genAttrs s.names (name: s.path + "/${name}")
    else { };

  skills = (lib.optionalAttrs (aiOn || devOn) localSkills) // aiSkills;

  collisions = lib.attrNames (lib.intersectAttrs localSkills aiSkills);

  centralSet = pkgs.linkFarm "agent-skills" skills;
in
{
  config = lib.mkMerge [
    {
      assertions = [{
        assertion = collisions == [ ];
        message = "modules/agent-skills.nix: skill name(s) in both files/agent-skills and vexos-ai: ${lib.concatStringsSep ", " collisions}";
      }];
    }

    (lib.mkIf (skills != { }) {
      environment.etc."vexos/agent-skills".source = centralSet;

      systemd.user.tmpfiles.users.${config.vexos.user.name}.rules = lib.concatMap
        (dir: map (name: "L+ %h/${dir}/${name} - - - - ${centralSet}/${name}") (lib.attrNames skills))
        [ ".claude/skills" ".agents/skills" ];
    })
  ];
}
