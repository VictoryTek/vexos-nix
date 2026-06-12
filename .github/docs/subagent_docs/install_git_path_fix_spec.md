---
name: install-git-path-fix
description: Fix installer failing on git-less systems because bootstrapped git binary is not on PATH for Nix-internal git calls
metadata:
  type: project
---

# install.sh git PATH fix — spec

## Problem

On systems without git, install.sh bootstraps it from the Nix store:

```bash
GIT="$(nix ... build nixpkgs#git --no-link --print-out-paths)/bin/git"
```

All explicit `sudo "$GIT" -C /etc/nixos ...` calls succeed because they use the
variable directly.  But `sudo nix ... flake update --flake git+file:///etc/nixos`
invokes Nix, which internally spawns `git` as a subprocess using `PATH` — not
`$GIT`.  Since the Nix store git binary is not on `PATH`, the subprocess fails:

```
error: executing 'git': No such file or directory
… while updating the lock file of flake 'git+file:///etc/nixos'
```

## Fix — scripts/install.sh only

Split the store-path capture and PATH export into two steps:

```bash
_GIT_STORE="$(nix ... build nixpkgs#git --no-link --print-out-paths)"
GIT="$_GIT_STORE/bin/git"
export PATH="$_GIT_STORE/bin:$PATH"
```

`PATH` is exported so every subsequent subprocess — including Nix's internal git
call — finds the bootstrapped binary.  When git is already on the system, `PATH`
is unchanged.

## Files to modify

- `scripts/install.sh` — bootstrap block only (~3 lines)

## Risks

None — the PATH prepend is guarded inside the `else` branch that only runs when
git is absent.  On systems that already have git, nothing changes.
