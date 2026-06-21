---
name: steam-bwrap-setuid-fix
description: Fix Steam failing to launch because bubblewrap 0.11.x removed setuid priv mode
metadata:
  type: project
---

# Spec: Fix Steam launch failure — bubblewrap setuid regression

## Current State

`programs.steam.enable = true` causes the NixOS module to add `security.wrappers.bwrap`
with `setuid = true`. Confirmed by:

```
nix eval --impure --json ".#nixosConfigurations.vexos-desktop-amd.config.security.wrappers"
→ "bwrap": { "setuid": true, ... }
```

The running system has `/run/wrappers/bin/bwrap` with the setuid bit set.

## Problem

bubblewrap **0.11.0** (released 2024-09-09) removed the legacy setuid privilege mode:
> "Remove legacy setuid priv mode"

nixpkgs 26.05 ships **bubblewrap 0.11.2**. When Steam's pressure-vessel invokes
`/run/wrappers/bin/bwrap` and the setuid bit fires, bwrap detects `geteuid() != getuid()`
and immediately aborts:

```
bwrap: setuid use of bubblewrap is not supported in this build
```

The NixOS `programs.steam` module has not yet been updated to reflect this change.

## Verified preconditions

- `user.max_user_namespaces = 2147483647` — unprivileged user namespaces are fully
  available on the running kernel. bwrap can create sandboxes without setuid.
- No `kernel.unprivileged_userns_clone = 0` restriction in vexos-nix config or sysctl.
- AppArmor is in `killUnconfinedConfinables = false` mode — no AAprofile will block bwrap.

## Proposed Solution

Override `security.wrappers.bwrap` in `modules/gaming.nix` using `lib.mkForce` to strip
the setuid bit. bwrap will then use unprivileged user namespaces (CLONE_NEWUSER), which
are supported by the kernel and sufficient for Steam's pressure-vessel runtime.

```nix
security.wrappers.bwrap = lib.mkForce {
  source      = "${pkgs.bubblewrap}/bin/bwrap";
  setuid      = false;
  setgid      = false;
  owner       = "root";
  group       = "root";
  permissions = "u+rx,g+x,o+x";
};
```

### Why gaming.nix

`gaming.nix` is the file that enables `programs.steam`. The bwrap override is a direct
consequence of Steam being enabled, so it belongs in the same file. No new module file is
needed — this is one attribute override, not a new subsystem.

### Why lib.mkForce

`programs.steam.enable` sets `security.wrappers.bwrap` at the NixOS module level. A plain
assignment would create a conflict ("attribute defined multiple times"). `lib.mkForce`
overrides it without needing `mkMerge` gymnastics.

## Files to Modify

- `modules/gaming.nix` — add the `security.wrappers.bwrap` override

## Risks and Mitigations

| Risk | Mitigation |
|------|-----------|
| Kernel without unprivileged user namespaces | Verified: `user.max_user_namespaces = 2147483647` |
| AppArmor blocking bwrap | `killUnconfinedConfinables = false`; no bwrap profile in apparmor-profiles |
| Future NixOS fix re-enabling setuid | `lib.mkForce` will silently win; when upstream fixes the steam module to set `setuid = false` our override becomes a no-op conflict — safe to remove then |
| Other roles (htpc, stateless-gaming) | Those roles also import gaming.nix, so they get the fix automatically |
