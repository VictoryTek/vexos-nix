# nixos_git_secrets — Specification

## Problem

`path:/etc/nixos` copies the entire directory into the world-readable Nix store on
every rebuild — including `/etc/nixos/secrets/` (plaintext passwords for Nextcloud,
MinIO, Attic, etc.). The Nix store at `/nix/store/` is readable by all local users.

## Root Cause

`path:` scheme = full directory copy, no exclusions. `git+file://` = only tracked files
(respects `.gitignore`). Untracked secrets are never copied into the store.

## Key Finding

The MASTER_PLAN stated "the installer already git-inits /etc/nixos" — this is PARTIALLY
true only:
- `stateless-setup.sh` does `git init` + `git add .` during install, but copies only
  individual files (not `.git`) to persistent storage. Running systems have no git repo.
- `install.sh` (non-stateless: desktop, server, htpc) never does `git init`.

## Solution: Two-Part Fix

### Part 1 — Establish git repo in /etc/nixos

**For new installs (`install.sh`):**
Add a git init block after all flake patches (ASUS, GRUB, hostId) and before the
final `nixos-rebuild` call. Create `.gitignore`, init, stage tracked files only.

**For new stateless installs (`stateless-setup.sh`):**
After `git add .`, copy the `.git` directory to persistent storage alongside the
individual files already copied.

**For existing installs (`modules/nix.nix` — `vexos-update`):**
Add an auto-init guard at the top of the script (after the VARIANT check). If
`/etc/nixos` is not a git repo, initialize it now with the correct `.gitignore`.

### Part 2 — Switch all `path:/etc/nixos` → `git+file:///etc/nixos`

**`modules/nix.nix`** — 4 occurrences in `vexos-update`:
- Line 146: `nixos-rebuild dry-build` (kernel override check)
- Line 172: `nix flake update`
- Line 176: `nixos-rebuild dry-build` (heavy build check)
- Line 238: `nixos-rebuild switch`

**`justfile`** — 7 occurrences:
- Line 374: `nix flake update --flake path:/etc/nixos`
- Line 378: `--flake path:/etc/nixos#"${target}"`
- Line 401: `sudo nix flake update vexos-nix --flake path:/etc/nixos`
- Line 404: `sudo nixos-rebuild switch --flake path:/etc/nixos#"${target}"`
- Line 461: `FLAKE_TARGET="path:/etc/nixos"`
- Line 907: `nix eval ... "path:/etc/nixos"`
- Line 1985: `sudo nixos-rebuild switch --flake "path:/etc/nixos#${target}"`

## .gitignore Contents

```
secrets/
hardware-configuration.nix
*.bak
vexos-variant
kernel-install-override.nix
stateless-user-override.nix
```

Rationale per entry:
- `secrets/` — plaintext credentials; must never enter the Nix store
- `hardware-configuration.nix` — host-generated, already excluded from this repo
- `*.bak` — flake.lock.bak backup files written by vexos-update
- `vexos-variant` — host-specific variant tag, not part of declarative config
- `kernel-install-override.nix` — transient installer artifact, auto-deleted by vexos-update
- `stateless-user-override.nix` — host-specific password override for stateless role

## Auto-Init Block (vexos-update)

```bash
# Ensure /etc/nixos is a git repo so git+file:// URIs exclude untracked secrets.
if ! git -C /etc/nixos rev-parse --git-dir &>/dev/null 2>&1; then
  echo "Initializing /etc/nixos as a git repository (one-time setup)..."
  cat > /etc/nixos/.gitignore << 'GITIGNORE'
secrets/
hardware-configuration.nix
*.bak
vexos-variant
kernel-install-override.nix
stateless-user-override.nix
GITIGNORE
  git -C /etc/nixos init -q
  git -C /etc/nixos add .
  git -C /etc/nixos \
    -c user.email="vexos@localhost" \
    -c user.name="VexOS" \
    commit -q -m "chore: track /etc/nixos configuration"
  echo "Done — secrets/ is now excluded from the Nix store."
fi
```

## Files Changed

- `template/.gitignore` — new file (template for new installs)
- `scripts/install.sh` — add git init block before final nixos-rebuild
- `scripts/stateless-setup.sh` — copy `.git` directory to persistent storage
- `modules/nix.nix` — add auto-init guard + 4× `path:` → `git+file:///`
- `justfile` — 7× `path:/etc/nixos` → `git+file:///etc/nixos`

## Risks and Mitigations

- **Existing installs:** auto-init in vexos-update handles migration on first run
- **`git+file://` requires valid repo:** auto-init guard guarantees this before any URI is used
- **No live servers:** no migration urgency; next install picks up installer changes
