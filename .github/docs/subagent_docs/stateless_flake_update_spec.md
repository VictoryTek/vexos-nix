# Spec: Add nix flake update to stateless-setup.sh before nixos-install

## Current State Analysis

`install.sh` (desktop/server/htpc/vanilla paths) runs `nix flake update` at line 403–404
before calling `nixos-rebuild`:

```bash
echo -e "${CYAN}Refreshing flake inputs...${RESET}"
sudo nix --extra-experimental-features "nix-command flakes" \
  flake update --flake git+file:///etc/nixos
```

`stateless-setup.sh` does NOT run `nix flake update`. It initialises a git repo in
`/mnt/etc/nixos`, then immediately calls `nixos-install` without refreshing the lock.
`nixos-install` creates `/mnt/etc/nixos/flake.lock` fresh, resolving
`github:VictoryTek/vexos-nix` via the GitHub API / CDN. If GitHub's CDN is serving a
stale cached HEAD for the `main` branch, `nixos-install` will evaluate against an older
`vexos-nix` commit.

## Problem Definition

A real-world install on 2026-06-12 locked to commit `c238ce6` instead of the then-current
HEAD `8054138`. `c238ce6` had two co-operating bugs:

1. `stateless-setup.sh` ran `nixos-generate-config` WITHOUT `--no-filesystems`, so
   hardware-configuration.nix gained filesystem entries with no `neededForBoot = true`.
2. `modules/stateless-disk.nix` used `lib.mkForce true` *nested inside* `lib.mkDefault {
   ... }`, which does not propagate the mkForce priority to the sub-module option.
   Hardware-configuration.nix definitions (priority 100) silently overrode the
   lib.mkDefault block (priority 1000), leaving `neededForBoot = false`.

`8054138` fixed both (script now uses `--no-filesystems` + injects `neededForBoot = true`;
module now uses `lib.mkMerge` with a separate top-level `lib.mkForce`). But without a
`nix flake update` step in `stateless-setup.sh`, any user whose `nixos-install` resolves
to a stale/cached commit will still hit the bug.

## Proposed Solution

Add a `nix flake update` step in `stateless-setup.sh`, immediately after the `git add`
step (line ~298) and before the `nixos-install` call (line ~305). This mirrors `install.sh`
lines 401–404.

The command to add:
```bash
echo ""
echo -e "${CYAN}Refreshing flake inputs...${RESET}"
sudo nix --extra-experimental-features "nix-command flakes" \
  flake update --flake git+file:///mnt/etc/nixos
```

Note: the path is `/mnt/etc/nixos` (the install root) not `/etc/nixos`.

## Implementation Steps

1. In `scripts/stateless-setup.sh`, insert the four-line block above between the
   `git add` section and the `nixos-install` section (around line 298–305).
2. No other files change.

## Dependencies

None — uses only the nix CLI already present on the live ISO.

## Risks and Mitigations

- **Risk:** `nix flake update` adds a few seconds of network latency.
  **Mitigation:** Acceptable; the subsequent `nixos-install` takes minutes anyway.
- **Risk:** GitHub API is unavailable (offline install).
  **Mitigation:** If GitHub is unreachable, `nix flake update` will fail and the
  stateless install will abort early with a clear error, which is better than silently
  evaluating against a stale commit and failing mid-install.
