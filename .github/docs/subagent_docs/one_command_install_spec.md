# One-command install — Specification

## Current state
Install is two commands (README "Fresh install"):
1. `sudo curl -o /etc/nixos/flake.nix .../template/etc-nixos-flake.nix`
2. `curl .../scripts/install.sh | bash`

`install.sh` assumes step 1 already happened: it patches `/etc/nixos/flake.nix`
(GRUB/Limine/ASUS/hostId), `git add`s it and builds `git+file:///etc/nixos`.
`migrate-to-stateless.sh` (in-place stateless path) likewise only *copies* the
existing `/etc/nixos/flake.nix` into `@persist`. `stateless-setup.sh` (live-ISO
stateless path) already downloads its own template into `/mnt/etc/nixos`.

## Problem
Step 1 is pure boilerplate the installer can do itself.

## Solution
Add `ensure_flake_wrapper()` to `scripts/install.sh`:
- No-op when `/etc/nixos/flake.nix` already exists. A re-run (switch role/variant)
  therefore keeps the existing wrapper; never overwrites user edits.
- Otherwise downloads the template **pinned to `$VEXOS_REV`** (same pin as every
  other file the script fetches) to a temp file, then `sudo install -m 644` into
  place, so a truncated download can never leave a partial `flake.nix` that the
  "already exists" check would later trust.

Call sites (two, because the script has two consumers of the wrapper):
1. Immediately before the `migrate-to-stateless.sh` hand-off.
2. Immediately before the UEFI/BIOS preflight block (first place that patches
   `/etc/nixos/flake.nix`); also covers the "already-stateless, switch variant"
   fall-through.
Not called on the live-ISO stateless path — `stateless-setup.sh` owns that.

Docs: README "Fresh install" collapses to the single `install.sh` command;
`install.sh` header notes it fetches the wrapper.

## Out of scope / unchanged
- `hardware-configuration.nix` is still expected to exist (generated per host).
- `template/etc-nixos-flake.nix` header comment describes the manual path; left as-is.
- No new dependencies, no flake/module changes, no `lib.mkIf`.

## Risks
- A pre-existing *foreign* `/etc/nixos/flake.nix` is left alone (same as before,
  when it would also fail at build time); not adding detection — unrequested.
- Network failure → `curl -f` non-zero → `set -e` aborts before any patching.

## Validation
`bash -n`, shellcheck on `install.sh`; `scripts/preflight.sh` (script is not
covered by nix eval, so syntax/lint checks are the meaningful ones).
