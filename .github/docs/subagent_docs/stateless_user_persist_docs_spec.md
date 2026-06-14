# Spec: Stateless Role — User-writable Persistent Documents Directory

## Current State

The stateless role uses `modules/impermanence.nix` to bind-mount a minimal set of system
directories from the `/persistent` Btrfs subvolume on each boot. The user's entire home
directory (`/home/<user>`) lives on the ephemeral tmpfs root and is wiped on every reboot.

The module already defines `environment.persistence."/persistent".users.<name>.directories`
as the extension point for user-level persistence, and comments in `impermanence.nix`
(lines 221–228) document this pattern. However no user directories are currently declared,
so nothing in the home directory survives reboots.

## Problem

The user cannot save documents, downloads, or other personal files between sessions. Every
reboot produces a clean home directory with no saved content.

## Proposed Solution

Add `~/Documents` as a user-level persisted directory via the impermanence `users.<name>.directories`
option in `configuration-stateless.nix`.

The impermanence module (from `nixos-impermanence`) bind-mounts
`/persistent/home/<user>/Documents` → `~/Documents` on every boot. On first boot, if the
target path on `/persistent` does not exist, impermanence creates it with the correct
ownership (uid/gid of the user) automatically. The directory is therefore user-writable
without any extra permissions changes.

## Why `configuration-stateless.nix` (not `modules/impermanence.nix`)

Following Option B (common base + role additions):
- `modules/impermanence.nix` is the universal base; it must not contain role-specific content.
- User-level persistence of `~/Documents` is stateless-role-specific behaviour.
- `configuration-stateless.nix` already owns all stateless-specific impermanence config
  (it sets `vexos.impermanence.enable = true`).
- The `environment.persistence` attrset is merged by NixOS, so adding `.users.<name>.directories`
  in `configuration-stateless.nix` is additive and does not conflict with anything in
  `modules/impermanence.nix`.

## Implementation Steps

1. In `configuration-stateless.nix`, under the `# ---------- Impermanence ----------` section,
   add:

```nix
environment.persistence."/persistent".users.${config.vexos.user.name}.directories = [
  { directory = "Documents"; mode = "0755"; }
];
```

No new files, no new imports, no new modules.

## Dependencies

- `nixos-impermanence` — already a flake input; no new dependency.
- No Context7 lookup required (internal module, no external library API).

## Risks and Mitigations

| Risk | Mitigation |
|------|-----------|
| `/persistent/home/<user>/Documents` does not exist on first boot | impermanence creates it automatically with correct ownership |
| Conflict with other `environment.persistence` keys | NixOS merges attrsets; no conflict possible |
| User expects `~/Downloads` or other XDG dirs | Out of scope; easy to add via same pattern if requested |

## Files to Modify

- `configuration-stateless.nix` — add user-level persistence entry
