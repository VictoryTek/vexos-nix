# just/ai.just — AI assistant (vexos-ai) — also VexPortal's AI Assistant page controls.
# Imported by the root justfile; recipe names share one namespace.

# Requires the ai feature: just feature enable ai
# Open your AI assistant (Claude Code or OpenCode) in /etc/nixos.
[group('AI Assistant')]
[doc('Open your AI assistant (Claude Code or OpenCode) in /etc/nixos')]
agent: _require-ai
    @vexos-ai

# No argument: failed units and this boot's errors. A unit name: that service.
# "rebuild": reproduce a failed rebuild with a dry-build. Read-only.
# Have your AI assistant explain a problem: just diagnose [unit|rebuild]
[group('AI Assistant')]
[doc("Have your AI assistant explain a problem (a unit name, or 'rebuild')")]
[arg('target', pattern='|[A-Za-z0-9][A-Za-z0-9@._:-]*', help='a systemd unit, or rebuild')]
diagnose target="": _require-ai
    @vexos-ai diagnose {{ if target == "" { "" } else { quote(target) } }}

# The ai-* recipes are VexPortal's AI Assistant page controls; each wraps a
# non-interactive vexos-ai command (github:VictoryTek/vexos-ai docs/contract.md).
# Choose your AI assistant: just ai-pick [claude|opencode]
[group('AI Assistant')]
[doc('Choose your AI assistant (claude or opencode)')]
ai-pick agent="": _require-ai
    @vexos-ai pick {{quote(agent)}}

# Mute, unmute or list crash notifications: just ai-crash-mute [name] [off]
[group('AI Assistant')]
[doc('Mute, unmute or list crash notifications')]
ai-crash-mute name="" state="": _require-ai
    @vexos-ai crash-mute {{quote(name)}} {{quote(state)}}

# Guard: the AI assistant recipes need the ai feature (vexos-ai on PATH).
[private]
_require-ai:
    @command -v vexos-ai >/dev/null || { echo "The AI assistant is not installed — run: just feature enable ai && just rebuild"; exit 1; }
