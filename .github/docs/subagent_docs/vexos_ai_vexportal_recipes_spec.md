# vexos-ai VexPortal recipes — spec

## Current state

- VexPortal (`f524cd3`, pinned in `flake.lock`) has an AI Assistant page whose
  controls call six `just` recipes: `ai-pick`, `ai-account-add`,
  `ai-account-use`, `ai-account-remove`, `ai-account-mode`, `ai-crash-mute`
  (`catalog/src/catalog.toml`).
- None of the six exist in `justfile`, and none ever have (`git log -S
  ai-account-add` is empty). VexPortal shows an action only when its recipe
  exists (`src/just.rs` `is_available`), so on a real host the page shows only
  `agent` and `diagnose`. VexPortal's drift test passed because its fixture
  (`catalog/tests/fixtures/vexos-nix-justfile.json`) was written by hand with
  the recipes in it.
- The vexos-ai CLI could not back them: `vexos-ai pick` ignored its argument and
  opened zenity. vexos-ai `2789611` (Phase 1, "machine contract") fixes that: all
  six commands are non-interactive when given argv, treat an empty trailing
  argument as missing, and use exit codes 0–5 (`docs/contract.md` there).
- `flake.lock` pins vexos-ai at `c2ace49`, which predates the contract.

## Problem

Add the six recipes with the exact signatures VexPortal's catalog expects, and
move the vexos-ai pin to a revision whose CLI supports them.

## Design

Thin wrappers in the existing `[group('AI Assistant')]` block of `justfile`,
after `diagnose`, each behind the same "not installed" guard `agent` and
`diagnose` use. Signatures and doc lines are copied from the VexPortal fixture
(`just --dump` reports the comment line directly above the recipe as `doc`):

| Recipe | Params (default) | Runs |
|---|---|---|
| `ai-pick` | `agent` (`""`) | `vexos-ai pick <agent>` |
| `ai-account-add` | `label` (required) | `vexos-ai account add <label>` |
| `ai-account-use` | `target` (required) | `vexos-ai account use <target>` |
| `ai-account-remove` | `label` (required) | `vexos-ai account remove <label>` |
| `ai-account-mode` | `mode` (required), `pct` (`""`) | `vexos-ai account mode <mode> <pct>` |
| `ai-crash-mute` | `name` (`""`), `state` (`""`) | `vexos-ai crash-mute <name> <state>` |

Arguments are passed with just's `quote()` so a value is always one shell word
and never interpreted by the shell. An empty default becomes `''`, which the
vexos-ai contract treats as missing. That is the behaviour the recipes need
(`ai-pick` with no agent opens the picker for a terminal user; `ai-crash-mute`
with no name lists mutes).

The wrappers do not pass `--non-interactive`: a person running `just ai-pick`
in a terminal should get the picker. VexPortal sets
`VEXOS_AI_NONINTERACTIVE=1` in its own job environment (VexPortal follow-up).

No Nix module changes: `modules/ai.nix` and `vexosAiModule` are untouched. The
new vexos-ai module options (crash-capture condition, `~/.agents/skills` links,
usage timer) arrive through the module itself.

## Steps

1. `justfile`: add the six recipes → verify: `just --dump --dump-format json`
   (WSL) shows the six with the fixture's params, defaults and docs.
2. `flake.lock`: `nix flake update vexos-ai` once `2789611` is on origin/main →
   verify: lock `rev` = `27896112c5bb1826bed1a627268a1b7898c5bc97`.
3. Evaluate with the feature on (`extendModules`, desktop-amd): vexos-ai
   package, policy and units present.

## Dependencies

No new inputs or libraries. vexos-ai stays `inputs.nixpkgs.follows =
"nixpkgs"`. just `quote()` is a built-in function (just manual, "Functions").

## Risks

- **Fixture drift:** a doc or default that differs from VexPortal's fixture fails
  VexPortal's live drift test. Mitigation: values copied from the fixture and
  checked against `just --dump`.
- **Lock bump before push:** pinning an unpushed rev breaks every fetch. The lock
  is bumped only after `git ls-remote` shows `2789611` on main.
- **Behaviour change for existing installs:** none. The recipes are new, and the
  vexos-ai contract keeps the old argv and state formats.
