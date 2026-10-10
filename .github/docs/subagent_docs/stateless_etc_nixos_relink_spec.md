# Stateless: relink every /etc/nixos tool entry — Spec

## Current state
`modules/packages-common.nix` (all roles) deploys five entries under `/etc/nixos`
through `environment.etc`:

| Entry | Used by |
|---|---|
| `justfile` | the `just` alias, VexPortal |
| `just/` | imported by the justfile (Tier 3) |
| `scripts/` | `set-hostname` and `bootloader switch` (`scripts/upgrade-wrapper.sh`), storage menus |
| `template/server-services.nix` | `just service enable` (seeds the file) |
| `template/features.nix` | `just feature enable`, and `just switch` DE/VM selection (seeds the file) |

On stateless, impermanence bind-mounts `/persistent/etc/nixos` over `/etc/nixos`,
which hides those `environment.etc` symlinks. `modules/impermanence.nix`
(`system.activationScripts.vexosJustfile`) relinks only `justfile` and `just/` into
the persistent directory. `scripts/` and `template/*` stay hidden.

## Problem
On a stateless host, `just set-hostname` and `just bootloader switch` run
`bash /etc/nixos/scripts/upgrade-wrapper.sh`, which does not exist there, so they
fail under `set -e`. Template seeding falls back to `$HOME/Projects/vexos-nix`,
which a stateless tmpfs home does not have. This is derived from the code and has not
been observed on a stateless host.

## Solution
Generate the activation script from one list of entry names, and take each link
target from `config.environment.etc."nixos/<name>".source`. That keeps one
source of truth: the relink cannot drift from what `packages-common.nix` deploys.
Keep the existing guard for each entry: a real file or directory (for example, a
repo checkout) is left alone; only a missing entry or an existing symlink is
(re)pointed. Create parent directories (`template/`) as needed.

Files: `modules/impermanence.nix` only. No new options, no `lib.mkIf` role
guards (the block already lives in the impermanence module's own `mkIf cfg.enable`).

## Verification
- Evaluate `vexos-stateless-amd` and check that the generated activation text contains all five
  entries pointing at the same store paths as `environment.etc`.
- Run the generated activation text against a temp "persistent" dir: fresh dir,
  re-run (idempotent), existing stale symlink (repointed), and a real file or
  directory (left untouched).
- Desktop, stateless, and htpc evaluate; preflight passes.

## Risks
- If a host has a real `scripts/` directory in `/persistent/etc/nixos`, it is
  intentionally kept, matching the justfile's behaviour.
- `ln -sfn` on an existing symlink to a directory replaces the link and does
  not descend into it (`-n`).
