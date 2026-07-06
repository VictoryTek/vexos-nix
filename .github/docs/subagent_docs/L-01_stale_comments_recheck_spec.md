# L-01 — Stale comments contradicting live code

Status: Phase 1 (Research & Specification)
Source: MASTER_PLAN L-01 (BUGS L1) · `modules/gpu/vm.nix:5-8`,
`modules/gaming.nix:4,70-71`, `home-desktop.nix:21-23`, others

## Current State — re-checked every cited claim directly, not assumed

- **Kernel version in `vm.nix`**: comment says "Pin to Linux 6.12 LTS
  — VirtualBox Guest Additions 7.2.4 is incompatible with Linux 6.19+
  ... 6.12 LTS is maintained until Dec 2026." Code:
  `boot.kernelPackages = lib.mkForce pkgs.linuxPackages_6_12;` — comment and
  code agree exactly. `git log --oneline -- modules/gpu/vm.nix` shows a
  top commit "Update vm.nix" — this was already fixed since the plan was
  written.
- **Bottles**: `grep -rn "Bottles"` across every `.nix` file in the repo
  returns zero matches — no comment anywhere claims Bottles is present.
  `git log --all -S"Bottles" -- modules/gaming.nix` confirms Bottles *was*
  referenced historically and was fully removed (the current
  `vexos.flatpak.extraApps` gaming list has exactly 3 apps: Lutris,
  ProtonPlus, PrismLauncher — no Bottles, no stale claim about it).
- **VS Code comment in `home-desktop.nix`**: line 22 says "NOTE: VS Code
  (programs.vscode, below) is currently disabled." — the actual
  `programs.vscode = { ... }` block a few lines down (56-62) is indeed fully
  commented out. Comment matches code exactly.
- **`authorized_keys` comment** (`modules/network.nix:165-172`): documents
  that `PasswordAuthentication` is deliberately left at the openssh default
  (enabled) precisely so hosts stay reachable without requiring
  `authorized_keys` to be populated — matches the actual
  `services.openssh.settings` block immediately above it and the
  `authorizedKeys.keyFiles` conditional immediately below. Also: this is
  SSH-adjacent configuration this session has standing instruction to treat
  with extra care (never propose disabling `PasswordAuthentication`) — left
  entirely untouched regardless, since it's accurate as-is.

## Problem Definition

None remaining. All four specific claims in this item — kernel version,
Bottles, VS Code, authorized_keys — were already corrected by prior commits
before this session reached this item in the backlog (same stale-plan
pattern as M-01/M-21/M-25/M-34 earlier this session).

## Proposed Solution

No code changes. Mark resolved with a resolution note documenting that every
cited claim was independently re-verified against current code and found
already accurate.

## Implementation Steps

None — verification only.

## Configuration Changes

None.

## Risks and Mitigations

None — no code touched.
