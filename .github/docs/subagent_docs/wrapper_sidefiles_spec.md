# Wrapper side-files (audit item 3) — Specification

Tracker: `installer_audit_findings.md` item 3. Decisions taken with the user:
**auto-upgrade legacy wrappers with backup**, and **fix vanilla + BIOS GRUB** in scope.

## 1. Current state

`/etc/nixos/flake.nix` (from `template/etc-nixos-flake.nix`) carries three inline
Nix blocks that tooling rewrites with `awk`/`sed` keyed to exact literal text:

| Block | Rewritten by |
|---|---|
| `bootloaderModule = { ... }: {` | `install.sh` (GRUB, Limine), `justfile` `switch-bootloader` |
| `hardwareModule = { ... }: { };` | `install.sh`, `stateless-setup.sh` (ASUS), `justfile` `set-hostname` |
| `networking.hostId = "XXXXXXXX"` | `install.sh` |

Facts established while researching (beyond the audit):
- The wrapper is written **once and never resynced** (`install.sh` `ensure_flake_wrapper`
  keeps an existing file; `vexos-update` says so too). Every already-installed
  machine keeps the inline blocks forever. A new installer that only writes
  side-files would be silently ignored there (a BIOS host would fall back to
  systemd-boot).
- `justfile` patches the same anchors in two recipes the audit did not list.
- The wrapper's default `bootloaderModule` is redundant: every role except vanilla
  imports `modules/system.nix`, which already defaults `vexos.bootloader =
  "systemd-boot"` and sets the loader options; vanilla sets them with `mkDefault`.
  It also *causes* the equal-priority conflict that forces the awk rewrite.
- Existing bug: on vanilla, the GRUB patch writes `vexos.bootloader`/`vexos.grub.device`,
  which vanilla never declares (it does not import `modules/system.nix`). By static
  reading this breaks evaluation. Not confirmed on hardware.
- Missing `host.nix` on a server role is not silent: `modules/zfs-server.nix`
  asserts on the placeholder hostId, so the build aborts with a message.

## 2. Design

Four optional side-files, each wired with the template's existing
`builtins.pathExists` + `lib.optional` idiom. The installer only ever writes
small whole files; it never rewrites the wrapper.

| File | Content | Written by | Imported by |
|---|---|---|---|
| `bootloader.nix` | `vexos.bootloader` / `vexos.grub.device` (vanilla: direct `boot.loader.grub`) | `install.sh`, `just switch-bootloader` | all 6 builders |
| `hardware-local.nix` | ASUS options or OpenRGB block | `install.sh`, `stateless-setup.sh` | all 6 |
| `host.nix` | `networking.hostId` | `install.sh` (server role, **only if absent**) | server, headless-server |
| `hostname.nix` | `networking.hostName` | `just set-hostname` | all 6 |

`hostname.nix` is new relative to the audit: `set-hostname` anchored on
`hardwareModule`, which is being deleted, and appending into a hand-shaped module
would reintroduce text patching.

Template: delete `bootloaderModule`, `hardwareModule`, `hostModule` and the
`XXXXXXXX` placeholder; replace header BIOS/Limine comments (also fixes the stale
comment in audit item 11).

Preserved behaviours (parity, deliberately):
- Installer only **writes** `bootloader.nix` / `hardware-local.nix` when the user
  picks GRUB/Limine/ASUS; it never deletes them. (Deleting would flip an installed
  Limine host back to systemd-boot when the user answers the default "N" on a
  re-run, without `switch-bootloader`'s NVRAM cleanup.)
- `host.nix` is never overwritten: ZFS pools bake the hostId in.
- Limine still not offered for vanilla.

### Legacy-wrapper upgrade — `scripts/upgrade-wrapper.sh`
Idempotent; no-op unless `/etc/nixos/flake.nix` contains an uncommented
`hardwareModule =` / `bootloaderModule =`. Otherwise, fail-closed:
1. Extract, from non-comment lines only: `vexos.bootloader` + `vexos.grub.device`
   (or a raw `boot.loader.grub` stanza's `device`), a real `networking.hostId`
   (not `XXXXXXXX`), and the full `hardwareModule` right-hand side (brace-depth to
   the `;` at depth 0) unless it is the empty `{ ... }: { }`.
2. Validate the extracted hardware expression with `nix-instantiate --parse`.
   Any failure → abort, wrapper untouched, message points at the backup-less state.
3. Only then: back up to `flake.nix.legacy.bak` (`*.bak` is already gitignored),
   install the current template, move the side-files into place.

Called from `ensure_flake_wrapper` (covers both `install.sh` call sites, including
the hand-off to `migrate-to-stateless.sh`) and from the two `justfile` recipes.
Template source: local checkout if present, else fetched pinned to `VEXOS_REV`
(same convention as every other file the installer pulls).

### Other files that must learn the new names
- `install.sh` git-add loop and `pkgs/vexos-update/default.nix` force-add loop.
- Stateless persistence: `stateless-setup.sh` and `migrate-to-stateless.sh` copy
  `hardware-local.nix` / `hostname.nix` / `bootloader.nix` alongside `vm-platform.nix`.

## 3. Dependencies
None new. `nix-instantiate` is already required by the installer environment.
No new flake inputs, so no `follows` concern.

## 4. Risks
| Risk | Mitigation |
|---|---|
| Upgrade mis-extracts a hand-edited legacy wrapper | Fail-closed parse check; full original kept as `flake.nix.legacy.bak`; only the three known settings are carried |
| Hand edits outside those blocks are lost on upgrade | Stated in the upgrade output; recoverable from the backup |
| Re-run overwrites `hardware-local.nix` carrying migrated custom content | Only when the user re-selects ASUS; documented |
| brace-depth extraction confused by braces in strings/comments | Comments stripped first; parse check rejects garbage; legacy hardwareModule contents were installer-generated one-liners |
| Nothing here can be run on real hardware from the dev box | Verify with per-target `nix eval`/dry-build on a test `/etc/nixos`-shaped dir, and unit-test the upgrade script against fixture wrappers |

## 5. Verification
- `nix eval` of the updated template with each side-file present/absent, per role.
- Upgrade script against fixtures: empty legacy, GRUB legacy, Limine legacy, ASUS
  laptop/desktop legacy, real hostId, garbage → abort.
- Whitespace-only reformat of the template still applies every setting (no anchors).
- `bash scripts/preflight.sh` exit 0 (incl. the new shellcheck stage).
