# Spec: install.sh — bootstrap git when missing on the host

## Current State Analysis

`scripts/install.sh` git-tracks `/etc/nixos` before building (lines 348–368) so that
`git+file:///etc/nixos` only copies tracked files into the Nix store, keeping
`secrets/` out. It calls `sudo git` four times:

- line 350: `sudo git -C /etc/nixos rev-parse --git-dir` (repo detection)
- line 361: `sudo git -C /etc/nixos init -q`
- line 362: `sudo git -C /etc/nixos add .`
- lines 363–366: `sudo git ... commit`

The script runs in two host contexts:

1. **NixOS live ISO** — the installation environment includes `git`
   (nixpkgs `profiles/installation-device.nix` adds it for flake support). Works.
2. **Existing plain NixOS install** (vanilla → vexos migration) — `git` is NOT in
   the system profile of a stock NixOS install. `sudo git init` fails with
   `sudo: git: command not found`, and `set -euo pipefail` aborts the installer
   mid-flight, leaving `/etc/nixos` partially configured (flake.nix patched, no
   git repo, no build). This is the failure observed in the field on
   2026-06-11 (desktop-nvidia + ASUS path).

Note: line 350 does not abort (it is inside an `if !` condition, so the
command-not-found is swallowed and the branch is entered), line 361 is the first
hard failure.

`scripts/stateless-setup.sh` also calls `sudo git`, but only ever runs from the
live ISO (it is dispatched by install.sh on the `tmpfs` root path), so it is not
affected. `scripts/migrate-to-stateless.sh` does not invoke git.

## Problem Definition

The installer must work on a stock NixOS system where `git` is not installed,
without requiring the user to pre-install anything. The one-liner
(`curl ... | bash`) is the advertised entry point for exactly this migration
scenario.

## Proposed Solution

Resolve a usable git binary once, before the git-track section, and use it via
an **absolute store path** for all four invocations:

```bash
if command -v git >/dev/null 2>&1; then
  GIT="git"
else
  GIT="$(nix --extra-experimental-features 'nix-command flakes' \
    build nixpkgs#git --no-link --print-out-paths)/bin/git"
fi
```

Then replace every `sudo git` in install.sh with `sudo "$GIT"`.

Rationale:
- `nix build nixpkgs#git --no-link --print-out-paths` fetches git from the
  binary cache via the flake registry — no channel required, no profile
  mutation, no root needed (multi-user daemon builds it). The installer already
  requires network and already passes `--extra-experimental-features
  "nix-command flakes"` to its other `nix` invocation (line 377), so this adds
  no new requirements.
- An absolute store path sidesteps `sudo` PATH handling entirely
  (`env_reset`/`secure_path` differences across configs) — the observed failure
  was precisely `sudo` not finding the command.
- When git IS present (live ISO, re-runs on installed vexos systems),
  behavior is byte-identical to today (`GIT="git"`).

Placement: immediately before the "Git-track /etc/nixos" section (line 348).
Earlier placement would pay the fetch cost on code paths that exit before
needing git (stateless dispatch at lines 104–129 exits earlier anyway, but
keeping the bootstrap adjacent to its only consumer is clearer).

### Considered and rejected

- `nix-shell -p git` — requires a configured channel; stock flake-era systems
  may not have one. Rejected.
- `nix shell nixpkgs#git -c git ...` per call — re-evaluates per invocation and
  the resulting PATH would not survive `sudo`. Rejected.
- Skipping git-tracking when git is absent — would silently copy `secrets/`
  into the world-readable Nix store on later runs. Rejected (security).

### Out of scope / accepted risk

`sudo nix flake update --flake git+file:///etc/nixos` (line 377) and the
subsequent `git+file://` builds rely on Nix's internal git fetcher. Nix ≥ 2.19
(NixOS ≥ 24.05) uses libgit2 and does not shell out to a git binary for this;
all supported host systems for this installer ship a newer Nix. No change.

## Implementation Steps

1. Add the git-resolution block before line 348 of `scripts/install.sh`
   → verify: `bash -n scripts/install.sh` passes.
2. Replace the four `sudo git` invocations with `sudo "$GIT"`
   → verify: `grep -n 'sudo git' scripts/install.sh` returns nothing.
3. Lint with shellcheck if available
   → verify: no new warnings attributable to the change.

## Dependencies

None added. Uses `nix` (already required) and the public flake registry's
`nixpkgs` (already implied by the flake-based install). Context7 not applicable
(no versioned library APIs; pure bash + nix CLI).

## Configuration Changes

None. No Nix modules, flake outputs, or `system.stateVersion` touched.

## Risks and Mitigations

- **Registry fetch adds a nixpkgs tarball download on git-less hosts** — only
  on the path that previously hard-failed; acceptable cost, and git itself
  comes from cache.nixos.org (no source build).
- **`--print-out-paths` requires nix ≥ 2.4** — flakes themselves require the
  same; no additional constraint.
- **Multiple outputs from `nix build`** — `nixpkgs#git` resolves to the default
  (`out`) output only; single path is printed.
