# L-06 — stateless-user-override.nix written world-readable

Status: Phase 1 (Research & Specification)
Source: MASTER_PLAN L-06 (BUGS L6) · `scripts/stateless-setup.sh:29-32`
(current file: the write happens at lines 364-372; 29-32 is stale — that
range is now the `cleanup()`/`trap` block. Same stale-line-reference
pattern seen in several prior MASTER_PLAN items.)

## Current State

`scripts/stateless-setup.sh` (lines 364-372) writes the password-hash
override file with a plain `sudo tee`:

```bash
sudo tee /mnt/etc/nixos/stateless-user-override.nix > /dev/null << NIXEOF
{ lib, ... }: {
  users.users.nimda.hashedPassword = lib.mkOverride 50 "${HASHED_PW}";
}
NIXEOF
```

`tee` creates the destination file with the invoking process's default
`umask`-derived mode — on the NixOS live ISO (root shell, umask `022`)
that is `0644`, i.e. world-readable. The file's `hashedPassword` value is
a SHA-512 `crypt(3)` hash (`openssl passwd -6`), which is exactly the
class of value `/etc/shadow` is kept `0640`/root-only to protect: a
world-readable copy lets any local unprivileged user copy the hash and
attempt an offline brute-force/dictionary attack, defeating the purpose
of hashing it in the first place. `/etc/nixos` itself is a normal
world-readable/traversable directory (NixOS reads config as any user via
`nixos-rebuild`), so directory permissions provide no protection here —
the file's own mode is the only gate.

This same file is subsequently:
- `git add`-ed (`stateless-setup.sh:393`) into the local `/etc/nixos` git
  repo — this tracking itself is intentional and required (H-10: the
  template flake imports this file, and `git+file://` only copies
  tracked files into the world-readable Nix store; established by a
  prior session and not in scope to change here). The concern is the
  *working-tree file's on-disk mode*, not whether it's git-tracked.
- `sudo cp`-ed verbatim to `/mnt/persistent/etc/nixos/` at
  `stateless-setup.sh:429`. Plain `cp` (no `-p`) does **not** preserve
  the source file's mode — the destination copy's mode is likewise
  governed by the copying process's umask, so this second copy needs the
  same treatment, not just the original.

**Same defect, second location:** `scripts/migrate-to-stateless.sh`
(lines 396-401) writes the identical override file via the identical
unguarded `tee` pattern, for the existing-install migration path:

```bash
tee /etc/nixos/stateless-user-override.nix > /dev/null << NIXEOF
{ lib, ... }: {
${USER_NAME_OVERRIDE}
  users.users.${DETECTED_USER}.hashedPassword = lib.mkOverride 50 "${HASHED_PW}";
}
NIXEOF
```

...and is later `cp`-ed (again without `-p`) to
`${BTRFS_MOUNT}/@persist/etc/nixos/` at line 443. Fixing only
`stateless-setup.sh` would leave the exact same information disclosure
on the migration path, which handles the same class of secret
(`HASHED_PW`, either freshly set or lifted from the pre-migration
`/etc/shadow`).

## Problem Definition

The `stateless-user-override.nix` file — in both the fresh-install
(`stateless-setup.sh`) and existing-install migration
(`migrate-to-stateless.sh`) code paths, and at both the initial write and
the subsequent persisted copy — is created with a world-readable mode,
exposing a crackable password hash to any local unprivileged user on the
target machine.

## Proposed Solution

Tighten every site that creates or copies this file to `0600`
(root-only read/write), matching the plan's suggested mechanism
(`install -m 0600`) while preserving the existing heredoc-based content
generation:

1. Immediately after each `tee` write, `chmod 0600` the file. (Simpler
   and less invasive than restructuring the heredoc through `install`,
   which does not compose cleanly with a `sudo tee <<EOF` content
   generator — `install` copies an existing source file, it does not
   accept inline stdin content the way `tee` does.)
2. Change the two `cp` calls that duplicate this file to `cp -p` (or an
   explicit follow-up `chmod 0600`) so the persisted copy does not
   silently regain a permissive mode.

## Implementation Steps

1. `scripts/stateless-setup.sh`
   - After the `sudo tee ... stateless-user-override.nix` heredoc
     (currently ending at line 371), add
     `sudo chmod 0600 /mnt/etc/nixos/stateless-user-override.nix`.
   - At the persist-copy site (currently line 429,
     `sudo cp /mnt/etc/nixos/stateless-user-override.nix /mnt/persistent/etc/nixos/ ...`),
     add `-p` to the `cp` invocation so the `0600` mode carries over.
2. `scripts/migrate-to-stateless.sh`
   - After its `tee ... stateless-user-override.nix` heredoc (currently
     ending at line 401), add
     `chmod 0600 /etc/nixos/stateless-user-override.nix`.
   - At its persist-copy site (currently line 443,
     `cp /etc/nixos/stateless-user-override.nix "${BTRFS_MOUNT}/@persist/etc/nixos/" ...`),
     add `-p` so the copy in `@persist` also stays `0600`.

## Configuration Changes

None — shell-script-only changes; no NixOS module/option changes, no
change to the Nix content written into the override file.

## Risks and Mitigations

- **Risk:** `0600` on a file the `nimda`/target user never needs to read
  directly (it's consumed only by Nix evaluation as root during
  `nixos-rebuild`/`nixos-install`, both root operations) — no expected
  functional impact.
  **Mitigation:** Verify by inspection that nothing in either script or
  in `modules/users.nix`/the template flake reads this file as a
  non-root process. `nixos-install` and `nixos-rebuild` both evaluate
  the flake as root, so a `0600` root-owned file is fully readable to
  the only process that needs it.
- **Risk:** `cp -p` also preserves ownership/timestamps, not just mode —
  benign here since both scripts run entirely as `root`
  (`sudo`/live-ISO-root context throughout), so ownership is `root:root`
  either way.
- **Risk:** persisted copy at `/persistent/etc/nixos/` is bind-mounted
  back to `/etc/nixos` post-boot (`modules/impermanence.nix`) — need to
  confirm the `0600` mode survives that bind mount and doesn't get
  reset by anything else that touches `/etc/nixos` post-boot (e.g.
  `vexos-update`'s git operations).
  **Mitigation:** to verify in Phase 3 — check `modules/impermanence.nix`
  and `pkgs/vexos-update/default.nix` for any step that rewrites or
  re-copies `stateless-user-override.nix` with a permissive mode after
  first boot.
