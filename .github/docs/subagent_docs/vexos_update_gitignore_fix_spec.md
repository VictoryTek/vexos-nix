---
name: vexos-update-gitignore-fix
description: Fix vexos-update one-time git init writing a gitignore that excludes flake-imported files, breaking git+file:// builds
metadata:
  type: project
---

# vexos-update gitignore fix — spec

## Current state

`modules/nix.nix` contains a one-time migration block (runs when `/etc/nixos` is not yet
a git repo) that creates `.gitignore` and calls `git init` + `git add .` + `git commit`.

The gitignore it writes (lines 143–150) excludes:
```
secrets/
hardware-configuration.nix
*.bak
vexos-variant
kernel-install-override.nix
stateless-user-override.nix
```

`git+file:///etc/nixos` only copies git-tracked files into the Nix store.  Because
`hardware-configuration.nix` is in the gitignore it is never tracked, so the store
snapshot is missing it.  `template/etc-nixos-flake.nix` imports `./hardware-configuration.nix`
(relative = store path), which does not exist → build fails.

The same silent breakage affects `kernel-install-override.nix` and
`stateless-user-override.nix`: `builtins.pathExists` returns false (file absent from
store) so these optional overrides are permanently disabled even when the files exist
on disk.

## Root cause

Commit `dff48b5` fixed `scripts/install.sh` and `scripts/stateless-setup.sh` to stop
excluding these files from gitignore and added a force-add repair loop.  It did not
update the equivalent one-time-migration code in `modules/nix.nix`, which still carries
the old (broken) gitignore.

## Proposed fix — modules/nix.nix only

### 1. Fix the one-time init gitignore

Change the gitignore written during one-time init to match the installer's gitignore
(only exclude files that must never enter the Nix store):

```
secrets/
*.bak
vexos-variant
```

Remove `hardware-configuration.nix`, `kernel-install-override.nix`,
`stateless-user-override.nix` from the gitignore.  With these files no longer excluded,
`git add .` in the init block will track them and `git+file://` will include them.

### 2. Add unconditional repair loop (runs on every vexos-update)

Immediately after the one-time init block, add a repair loop that force-adds the three
files if they exist on disk.  This repairs repos that were already initialized with
the broken gitignore on previous `vexos-update` runs:

```bash
for f in hardware-configuration.nix kernel-install-override.nix stateless-user-override.nix; do
  if [ -f "/etc/nixos/$f" ]; then
    git -C /etc/nixos add -f "$f" 2>/dev/null || true
  fi
done
```

This mirrors the repair loop added to `scripts/install.sh` in commit `dff48b5`.

## Files to modify

- `modules/nix.nix` — only file; two surgical changes in the vexos-update script

## No changes required

- `template/etc-nixos-flake.nix` — relative paths are correct once files are tracked
- `scripts/install.sh` — already fixed in dff48b5
- `scripts/stateless-setup.sh` — already fixed in dff48b5

## Risks

None — the gitignore change only removes exclusions (expanding what is tracked),
never adds new ones.  The repair loop is idempotent (`git add -f` on an already-tracked
file is a no-op).
