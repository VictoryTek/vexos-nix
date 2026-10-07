# VexPortal vexos-ai contract bump — spec

## Current state

`flake.lock` pins vexportal at `f524cd3`. Its AI Assistant page reads vexos-ai's
state files directly and runs `ai-*` jobs without `VEXOS_AI_NONINTERACTIVE`.

VexPortal `1856b63` (on origin/main) moves the page onto the vexos-ai Phase 1
contract that vexos-nix `ebff3c3` already pins (vexos-ai `4fe2b2d`):
- `AiState` from `vexos-ai status --json`, falling back to the file reader
- `VEXOS_AI_NONINTERACTIVE=1` for `ai-*` jobs, with messages for exit codes 2–5
- a drift fixture regenerated from vexos-nix `ebff3c3` (ai-* entries unchanged)

## Change

`nix flake update vexportal` → `1856b63`. No other files change. vexportal keeps
`inputs.nixpkgs.follows = "nixpkgs"`.

## Verification

Preflight (its dry-build stage covers `vexos-desktop-amd`, which installs
VexPortal). VexPortal's own preflight already ran fmt, clippy and its tests.

## Risks

- A Rust build regression against this nixpkgs pin. Mitigation: VexPortal
  follows this flake's nixpkgs, and its preflight built against the same branch.
- The page has not been checked in a running window. It needs a manual look
  after `just rebuild` on a host with the `ai` feature.
