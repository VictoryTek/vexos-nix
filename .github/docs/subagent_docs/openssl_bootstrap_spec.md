# Spec: Bootstrap openssl in stateless installer scripts

## Current State Analysis

- `scripts/stateless-setup.sh` (run on the NixOS live ISO via
  `curl ... | bash` from `install.sh`) requires `openssl` to hash the nimda
  password (`openssl passwd -6 -stdin`, line 144). If `openssl` is not on
  PATH it aborts (lines 122–125).
- `scripts/migrate-to-stateless.sh` (run via `curl ... | sudo bash`) has the
  same abort (lines 324–327) and usage (line 340).
- The NixOS live ISO does not ship `openssl` in PATH by default, so selecting
  the stateless role from `install.sh` fails at the password prompt.
- Precedent: `scripts/install.sh` lines 348–359 (commit 59bd971) bootstraps
  `git` from the nixpkgs binary cache when missing:
  `nix --extra-experimental-features 'nix-command flakes' build nixpkgs#git
  --no-link --print-out-paths`.

## Problem Definition

Stateless installation/migration must not fail when `openssl` is absent;
it should fetch openssl from the nixpkgs binary cache and continue.

## Proposed Solution

Replace the abort blocks in both scripts with the established git-bootstrap
pattern:

```bash
if command -v openssl >/dev/null 2>&1; then
  OPENSSL="openssl"
else
  echo -e "${CYAN}openssl not found on this system — fetching from nixpkgs binary cache...${RESET}"
  OPENSSL="$(nix --extra-experimental-features 'nix-command flakes' \
    build nixpkgs#openssl.bin --no-link --print-out-paths)/bin/openssl"
fi
```

and change the two hash invocations to use `"$OPENSSL"`.

Notes:
- `nixpkgs#openssl.bin` is used (not `nixpkgs#openssl`) because openssl is a
  multi-output derivation; selecting `.bin` guarantees exactly one store path
  from `--print-out-paths`, and the `openssl` binary lives in the `bin` output.
- `set -euo pipefail` (already in both scripts) aborts naturally if the
  `nix build` fetch fails (e.g. no network), preserving fail-fast behavior.
- The nix CLI is guaranteed present in both contexts (live ISO and installed
  NixOS host).

## Implementation Steps

1. `scripts/stateless-setup.sh`: replace lines 122–125 abort with the
   bootstrap block; line 144 `openssl` → `"$OPENSSL"`.
2. `scripts/migrate-to-stateless.sh`: replace lines 324–327 abort with the
   bootstrap block (indented to match surrounding `else` branch); line 340
   `openssl` → `"$OPENSSL"`.
3. Verify: `bash -n` on both scripts; preflight.

## Dependencies

None new. Uses nixpkgs `openssl` from the binary cache at runtime only
(no flake input change, no Context7-relevant versioned API).

## Configuration Changes

None.

## Risks and Mitigations

- Fetch requires network: both scripts are already curl-fetched, so network
  is guaranteed at this point.
- Multi-output ambiguity: mitigated by targeting `openssl.bin` explicitly.
