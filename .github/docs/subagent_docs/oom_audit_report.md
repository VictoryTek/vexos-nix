# OOM-Bomb Audit Report — vexos-nix

**Date**: 2026-05-23  
**Machine**: 32 GB RAM  
**Scope**: All tracked files excluding `.git/` and `result/`  
**Status**: READ-ONLY audit — no files were modified

---

## Background

The following commands have been confirmed to OOM-lock this machine:

- `nix flake check` (any flags) — evaluates all 30+ `nixosConfigurations` in parallel, exhausts all RAM
- `nix eval --json '.#nixosConfigurations' --apply builtins.attrNames` — enumerates all configs, triggers parallel eval
- Any loop over all 30+ `nixosConfiguration` targets running `nixos-rebuild dry-build` or `nix build --dry-run` sequentially — cumulative RAM pressure causes OOM

These have been fixed in `scripts/preflight.sh` (Stages 1 & 2) and documented as ABSOLUTE RULES in `.github/copilot-instructions.md`.

---

## CRITICAL — OOM Bombs Found

**None.**

No executable file (script, CI workflow, Justfile) contains an active OOM-bomb pattern.

---

## WARNING — Stale Documentation (3 files)

These files are not executable — they are historical specification and review documents in `.github/docs/subagent_docs/`. The risk is a future developer reading them as current guidance when redesigning the preflight or CI pipeline.

### W-1 — `.github/docs/subagent_docs/bazzite_parity_preflight_spec.md`

**Lines**: 76, 82–83, 308–313, 383

The spec proposes bare `nix flake check` as CHECK 1 (the primary hard gate):

```bash
if nix flake check; then
  PASS "nix flake check"
else
  FAIL "nix flake check — flake evaluation failed"
```

**Status**: Superseded. The actual `scripts/preflight.sh` uses `nix flake show --json` and explicitly documents the prohibition.

---

### W-2 — `.github/docs/subagent_docs/ci_automation_spec.md`

**Lines**: 103, 108, 259, 263, 290, 412

The spec proposes `nix flake check --no-build --impure --show-trace` as the primary CI gate:

```bash
run: nix flake check --no-build --impure --show-trace
```

**Why risky**: `--no-build` prevents package builds but does NOT prevent evaluating all 30+ `nixosConfigurations` simultaneously — which is the exact OOM trigger. Safe only on GitHub-hosted runners with unlimited RAM; dangerous locally and on self-hosted runners.

**Status**: Superseded. The actual `ci.yml` uses `nix eval --impure ".#nixosConfigurations.${config}.config.system.build.toplevel.drvPath"` per-config sequentially inside a matrix.

---

### W-3 — `.github/docs/subagent_docs/ci_automation_review.md`

**Lines**: 158–170, 238–247

The reviewer recommended adding `nix flake check --impure --no-build --show-trace` back to `preflight.sh` for consistency with CI. If acted upon, a future developer might restore `nix flake check` to the preflight script.

**Status**: Recommendation was not followed. Current `preflight.sh` does not use `nix flake check` in any form.

---

## SAFE — Verified Clean

| File | Notes |
|---|---|
| `scripts/preflight.sh` | CHECK 1: `nix flake show --json`. CHECK 2: single-variant dry-build via `/etc/nixos/vexos-variant`. No `nix flake check`. No multi-config loop. |
| `scripts/install.sh` | `nixos-rebuild switch` on a single interactively chosen target. |
| `scripts/migrate-to-stateless.sh` | `nixos-rebuild switch` on a single target. |
| `scripts/stateless-setup.sh` | `nixos-install` on a single target. `nix run` for disko (external tool, not a NixOS config eval). |
| `scripts/create-zfs-pool.sh` | ZFS/disk management only. No Nix commands. |
| `scripts/configure-network.py` | Python text substitution. No Nix commands. |
| `.github/workflows/ci.yml` | GitHub-hosted runners (`ubuntu-latest`). 6-group matrix — each group runs on a separate cloud runner with independent RAM. Per-config sequential `nix eval` of single `drvPath` attribute. No `nix flake check`. No bulk evaluation. |
| `.github/workflows/update-flake-lock.yml` | `nix flake update` + `git push` only. No config evaluation. |
| `.github/workflows/gitlab-mirror.yml` | `git remote add` + `git push` only. No Nix commands. |
| `justfile` | All `nixos-rebuild` calls target a single runtime-resolved variant. `nix flake update` only. `nix eval` calls are single-attribute lookups (one package version, one flake path). `for cfg` loop in `version-upgrade` runs only `grep`/`sed` — no Nix evaluation. |
| `README.md` | Rebuild instructions target single variant via `$(cat /etc/nixos/vexos-variant)`. No `nix flake check`. |
| `modules/server/plex.nix` line 46 | `nix eval` reference is inside a `# TODO` comment block — not an executed command. |

---

## NOT CHECKED — Out of Scope

| Path | Reason |
|---|---|
| `.github/docs/subagent_docs/*.md` (historical docs beyond W-1, W-2, W-3) | Not executable. Contain `nix flake check` references as part of design discussions only. |
| `flake.nix`, `flake.lock`, `configuration-*.nix`, `modules/**/*.nix`, `hosts/**/*.nix`, `home/**/*.nix`, `pkgs/**` | Nix expression files — no shell commands, cannot trigger OOM on their own. |
| `files/**`, `wallpapers/**`, `template/**` | Static assets and templates. |
| `authorized_keys`, `.gitattributes`, `LICENSE` | Non-executable metadata. |

---

## Summary

| Category | Count |
|---|---|
| Active OOM bombs in executable files | **0** |
| Stale documentation proposing dangerous patterns | **3** (WARNING — not executable) |
| Executable files verified clean | **11** |

The implementation layer (scripts, CI workflows, Justfile) is fully clean. The only residual risk is three historical spec/review documents in `.github/docs/subagent_docs/` that predate the OOM fix and propose `nix flake check` as a preflight/CI gate. These could mislead a future developer performing a preflight redesign.
