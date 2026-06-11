# drop_legacy470 — Specification

## Current State

VexOS ships three NVIDIA driver tiers:
- `nvidia` (latest) — current driver, Turing+
- `nvidia-legacy535` — 535.x LTS, Maxwell/Pascal/Volta
- `nvidia-legacy470` — 470.x, Kepler (GeForce 600/700)

This produces 34 flake outputs total. The `legacy470` variants exist across all five
GPU-bearing roles: desktop, stateless, server, headless-server, htpc.

The CI matrix is also missing `nvidia-legacy535` from the server and headless-server
groups (these were added to flake.nix marked `# NEW` but never added to ci.yml).

## Problem

1. Bazzite (the reference gaming distro VexOS aligns with) does not support Kepler (GTX
   600/700). Their legacy offering is `akmod-nvidia-580xx`, which covers
   Maxwell/Pascal/Volta only. Kepler is dropped upstream.
2. `legacy_470` is a divergence from that model with no active user base to justify it.
3. The four `# NEW` server/headless-server legacy535 outputs are untested by CI.

## Proposed Solution

### Remove all `legacy_470` outputs and references:
- `flake.nix` hostList: delete 5 `legacy470` entries (desktop, stateless, server,
  headless-server, htpc); update count comment 34→29
- `modules/gpu/nvidia.nix`: remove `legacy_470` from enum; simplify driverPackage
  expression to two-way (latest / legacy_535); remove legacy_470 from header comments
  and option description
- `scripts/install.sh`: remove option 3 (Legacy 470); update prompt to `[1-2]`
- `README.md`: remove 5 `legacy470` variant table rows
- `template/etc-nixos-flake.nix`: remove 5 `legacy470` comment lines

### Fix CI matrix:
- Add `vexos-server-nvidia-legacy535` to server group
- Add `vexos-headless-server-nvidia-legacy535` to headless-server group
- Remove `legacy470` from desktop, stateless, htpc groups
- Update stale count comment (line 64): "4 groups" → "6 groups", "22 configs" → "29 configs"
- Remove `# NEW` markers from flake.nix server/headless-server legacy535 lines

## Output count after change

| Role | Variants | Count |
|---|---|---|
| desktop | amd, nvidia, legacy535, intel, vm | 5 |
| stateless | amd, nvidia, legacy535, intel, vm | 5 |
| server | amd, nvidia, legacy535, intel, vm | 5 |
| headless-server | amd, nvidia, legacy535, intel, vm | 5 |
| htpc | amd, nvidia, legacy535, intel, vm | 5 |
| vanilla | amd, nvidia, intel, vm | 4 |
| **Total** | | **29** |

## Files modified
- `flake.nix`
- `modules/gpu/nvidia.nix`
- `.github/workflows/ci.yml`
- `README.md`
- `template/etc-nixos-flake.nix`
- `scripts/install.sh`

## Risks
- Anyone currently running `vexos-*-nvidia-legacy470` would lose their flake output on
  next pull. Kepler GPUs are out of Bazzite scope and NVIDIA mainstream support.
- `legacy_535` remains and covers Maxwell/Pascal/Volta — no regression for those users.
- `legacy_580` (the eventual Bazzite-aligned replacement for 535) is deferred until
  nixpkgs issue #503740 / PR #505263 lands in 25.11 stable.
