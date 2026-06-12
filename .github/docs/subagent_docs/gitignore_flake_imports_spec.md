# Spec: Stop gitignoring flake-imported files in /etc/nixos

## Current State Analysis

- `template/etc-nixos-flake.nix` (the thin wrapper installed to
  `/etc/nixos/flake.nix`) imports, relative to the flake source:
  - `./hardware-configuration.nix` — unconditional (line 156 et al.)
  - `./kernel-install-override.nix` — gated by `builtins.pathExists` (line 131)
  - `./stateless-user-override.nix` — gated by `builtins.pathExists` (line 184)
- Both `scripts/install.sh` (lines 365–372) and `scripts/stateless-setup.sh`
  (lines 240–247) initialise `/etc/nixos` (resp. `/mnt/etc/nixos`) as a git
  repo with a `.gitignore` listing all three files plus `secrets/`, `*.bak`,
  `vexos-variant`.
- Nix `git+file:` fetching copies ONLY tracked files into the store. Result,
  observed on a live-ISO stateless install:
  `error: path '/mnt/nix/store/…-source/hardware-configuration.nix' does not exist`
- Consequences of the same root cause:
  1. `nixos-install` / `nixos-rebuild` via `git+file:` fails for EVERY role on
     a freshly initialised repo (hardware-configuration.nix missing).
  2. Stateless: `stateless-user-override.nix` is silently absent from the
     store copy → `pathExists` is false → compiled-in locked account ("!").
  3. install.sh's kernel cache-miss fallback writes
     `kernel-install-override.nix` AFTER `git add .`; ignored + untracked, it
     never reaches the flake source, so the fallback re-check (line 448) sees
     no change and aborts — the feature is currently inoperative.
- Security note: excluding these from git provides no protection. The
  password hash from stateless-user-override.nix is compiled into the system
  closure in /nix/store regardless; hardware-configuration.nix and the kernel
  override contain no secrets. Only `secrets/` (consumed outside the flake
  source) must stay untracked.

## Problem Definition

Files imported by the template flake must be tracked in the /etc/nixos git
repo, or git+file: evaluation fails (hard import) or silently drops them
(pathExists imports). `secrets/` must remain untracked.

## Proposed Solution

1. **scripts/stateless-setup.sh** — remove `hardware-configuration.nix`,
   `kernel-install-override.nix`, `stateless-user-override.nix` from the
   `.gitignore` heredoc (keep `secrets/`, `*.bak`, `vexos-variant`). All
   three files are written before `git add .`, so they become tracked.
2. **scripts/install.sh** —
   a. Same `.gitignore` trim in the init block.
   b. After the init block (which is skipped when a repo already exists),
      force-add the flake-imported files when present, repairing repos
      created by earlier installer versions whose committed `.gitignore`
      still lists them:
      ```bash
      for f in hardware-configuration.nix kernel-install-override.nix stateless-user-override.nix; do
        [ -f "/etc/nixos/$f" ] && sudo "$GIT" -C /etc/nixos add -f "$f"
      done
      ```
   c. After writing `kernel-install-override.nix` (cache-miss fallback),
      `add -f` it so the fallback re-dry-build actually sees it; in the
      abort path that deletes the file, also `git rm --cached` it.
3. No changes to `template/etc-nixos-flake.nix`, modules, or `flake.nix`.

## Implementation Steps

1. Edit both heredocs → verify: heredoc contents list only
   `secrets/`, `*.bak`, `vexos-variant`.
2. Add repair loop + kernel-override add/rm in install.sh → verify:
   `bash -n` both scripts.
3. Preflight.

## Dependencies

None new (Context7 not applicable).

## Configuration Changes

Per-host /etc/nixos repos will now track hardware-configuration.nix and the
two override files. The vexos-nix repository itself still never contains
hardware-configuration.nix (repo constraint unchanged; preflight check 3
still applies).

## Risks and Mitigations

- Risk: hash visible in /etc/nixos git history — already visible in the
  built closure; no regression.
- Risk: `git add -f` on missing files — guarded by `[ -f … ]`.
- Risk: stale `.gitignore` on existing installs — once a file is tracked,
  gitignore no longer applies to it; repair loop handles first contact.
