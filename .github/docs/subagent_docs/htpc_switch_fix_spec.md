# htpc_switch_fix Specification

## Current-State Analysis

### Repository target naming
- `flake.nix` defines `nixosConfigurations` using the canonical pattern `vexos-<role>-<variant>`.
- `vexos-htpc-vm` is present in `flake.nix` and maps to `./hosts/htpc-vm.nix`.
- `template/etc-nixos-flake.nix` also exposes `vexos-htpc-vm` in its `nixosConfigurations` output.

### Switch command construction
- `justfile` recipe `switch` constructs the target as:
  - `TARGET="vexos-${ROLE}-${VARIANT}"`
- With `role=htpc` and `variant=vm`, the computed target is `vexos-htpc-vm`.

### Flake path resolution behavior in just
- `just switch` resolves a flake root directory and then runs:
  - `sudo nixos-rebuild switch --flake "<dir>#<target>"`
- Current logic can use a fallback flake location (`/etc/nixos` first, then `$HOME/Projects/vexos-nix`) when the `justfile` directory does not contain `flake.nix`.

### Root cause hypothesis (consistent with observed error)
- The command is likely evaluating a different flake than this repository copy (commonly `/etc/nixos/flake.nix` on the host), and that flake does not define `nixosConfigurations.vexos-htpc-vm`.
- Because target naming in both `justfile` and repo `flake.nix` already matches, the failure is a flake-source mismatch, not a naming-template bug in this repository.

## Problem Definition
- User flow: `just switch` with role `htpc` and variant `vm` fails with:
  - flake does not provide `nixosConfigurations."vexos-htpc-vm"`.
- The failure is caused by ambiguous flake source selection in `justfile`, which can point to a stale or incomplete flake lacking HTPC outputs.
- Goal: ensure `just switch` and `just build` select a flake source that actually provides the computed target, without breaking existing valid targets.

## Proposed Solution Architecture

### Design goals
- Preserve existing target naming convention (`vexos-<role>-<variant>`).
- Make flake source selection deterministic and target-aware.
- Keep compatibility with existing workflows (`/etc/nixos` wrapper and repository-local flake usage).
- Improve diagnostics when target is missing.

### Approach
1. Introduce a shared shell helper in `justfile` to resolve flake directory by validating target existence.
2. Probe candidate flake directories in priority order and select the first that both:
   - contains `flake.nix`, and
   - evaluates `nixosConfigurations.<target>` successfully.
3. Use this helper in both `switch` and `build` recipes.
4. If no candidate contains the target, fail with a clear message that prints:
   - attempted directories,
   - expected target,
   - a suggested command to inspect outputs (`nix flake show`).
5. Update README switching docs to mention that `just switch` is target-aware and how to troubleshoot stale `/etc/nixos/flake.nix`.

## Exact Implementation Steps and Files to Edit

1. Edit `justfile`
- Add a reusable bash helper (inline function) used by `switch` and `build`, for example:
  - `resolve_flake_dir_for_target "$TARGET"`
- Candidate order should preserve current intent while reducing mismatch risk:
  - directory containing the active `justfile` path,
  - `/etc/nixos`,
  - `$HOME/Projects/vexos-nix`.
- For each candidate, verify target existence with an official flake expression evaluation pattern, e.g.:
  - `nix eval --impure --raw "$dir#nixosConfigurations.${target}.config.system.build.toplevel.drvPath"`
- On first success, return that directory.
- Replace direct `nixos-rebuild ... --flake "$_jf_dir#..."` with resolved directory.
- Keep existing interactive role/variant prompts unchanged.

2. Edit `README.md`
- In switching section, add a brief note:
  - `just switch` now resolves a flake that contains the requested target.
  - if `/etc/nixos/flake.nix` is outdated, refresh from template or run using repository flake path.
- Add troubleshooting example commands:
  - `nix flake show /etc/nixos`
  - `nix flake show /path/to/repo`

## Risks and Mitigations

- Risk: Added `nix eval` probe may increase command latency.
  - Mitigation: stop at first matching candidate; only evaluate a small fixed candidate list.

- Risk: `--impure` or host-specific environment differences may affect probe behavior.
  - Mitigation: probe only for attribute existence under `nixosConfigurations.<target>.config.system.build.toplevel`; if evaluation fails, continue probing.

- Risk: Behavior change for users who expected unconditional `/etc/nixos` preference.
  - Mitigation: maintain `/etc/nixos` in candidate list and document selection rules explicitly.

- Risk: False negatives if candidate flake requires unavailable local files.
  - Mitigation: error output should include per-candidate failure and recommended manual checks.

## Validation Plan (Commands)

### Target existence and naming checks
- `nix flake show .`
- `nix eval --raw '.#nixosConfigurations.vexos-htpc-vm.config.system.build.toplevel.drvPath'`

### just command behavior checks
- `just build htpc vm`
- `just switch htpc vm`
- `just build desktop amd`
- `just build server vm`

### Regression checks for repository policy
- `nix flake check`
- `bash scripts/preflight.sh`

### Optional manual mismatch simulation
- Point `/etc/nixos/flake.nix` to a wrapper lacking `vexos-htpc-vm` and verify:
  - `just build htpc vm` selects alternate valid flake directory or fails with explicit diagnostics.

## Research Sources (Credible, >=6)

1. Nix Reference Manual - `nix flake` (stable): https://nix.dev/manual/nix/stable/command-ref/new-cli/nix3-flake.html
2. Nix Reference Manual - `nix flake show` (stable): https://nix.dev/manual/nix/stable/command-ref/new-cli/nix3-flake-show
3. Nix Reference Manual - `nix build` (stable): https://nix.dev/manual/nix/stable/command-ref/new-cli/nix3-build
4. Nix Reference Manual - `nix flake` (2.26 command semantics): https://nix.dev/manual/nix/2.26/command-ref/new-cli/nix3-flake
5. NixOS Wiki - Flakes: https://nixos.wiki/wiki/Flakes
6. Official NixOS Wiki - NixOS system configuration (flakes + hostname selection): https://wiki.nixos.org/wiki/NixOS_system_configuration#Flakes
7. Official NixOS Wiki - nixos-rebuild (`--flake` behavior and hostname lookup): https://wiki.nixos.org/wiki/Nixos-rebuild
8. Nix Reference Manual - `nix eval` (attribute probing patterns): https://nix.dev/manual/nix/2.26/command-ref/new-cli/nix3-eval
