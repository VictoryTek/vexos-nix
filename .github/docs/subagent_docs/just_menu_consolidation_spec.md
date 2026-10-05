# Just menu consolidation (spec)

## Current state
`just --list` showed ~60 flat recipes: 8 `vpn-*`, two kill-switch toggles, 3 `kernel-build-*`,
`attic-*`/`harmonia-info`, `features`/`enable-feature`/`disable-feature`, attach/detach remote
storage (also listed a second time in the server-only help block), `switch-bootloader[-cleanup]`,
`*-plex-pass`, seven server-service recipes, and separate create-pool recipes for ZFS and mergerfs
(`create-zfs-pool` carried a 60-line duplicate of `_run-storage-script`'s script lookup).
mergerfs had only a create script — no destroy/add/remove; re-running create overwrote
`storage-pool.nix`, dropping existing branches.

## Requested grouping (user-specified)
kernel-build-* → `kernel`; attic-* (+ harmonia-info) → `cache`; features/enable-feature/disable-feature →
`feature`; attach/detach-remote-storage → `remote-storage` (listed once); switch-bootloader* →
`bootloader`; enable/disable-kill-switch → `kill-switch`; vpn* → `vpn`; *-plex-pass → `plex-pass`;
services/available-services/service-info/status/restart/enable/disable → `service`;
create-mergerfs-pool → `mergerfs-pool` menu with destroy and related actions; zfs-pool (done earlier).
Behaviour chosen by user: menu with no action, direct subcommand with an action
(`just vpn` / `just vpn up`); old names removed, references updated.
Left alone (not requested): build/switch/update/deploy/rollback, backup-*/restore-*, nas-sync-*,
prune-services, setup-tailscale, fix-flake, agent/diagnose.

## Design
- Existing recipe bodies are unchanged; they are renamed to hidden `_<group>-<action>` recipes
  (`[private]`, dependencies such as `_require-server-role` kept).
- One shared private `_menu` recipe (`[positional-arguments]`) renders the numbered menu or, given an
  action, validates it, prompts for a required argument only on a tty, and `exec just _<group>-<action> args`.
  Each public group recipe is `<group> action="" *args:` plus a list of `key|description[|prompt]` items.
  No tty and no action → usage, exit 1 (scriptable, never hangs).
- `_run-storage-script` now forwards extra args, so `just zfs-pool create` / `just mergerfs-pool add`
  run one action directly. `create-zfs-pool` recipe deleted (wizard now calls `just zfs-pool create`).
- New `scripts/mergerfs-pool.sh`: status, create (delegates to unchanged `create-mergerfs-pool.sh`,
  warns that it replaces an existing pool), add content/parity disk (size check for parity), remove disk
  (refuses last content disk), destroy (unmount, remove config, optional wipe), SnapRAID sync/scrub.
  Parses/writes `storage-pool.nix` in the exact format the create script emits.
- All textual `just <old-name>` references (justfile, modules, templates, scripts, SKILL.md, flake.nix
  comments, pkgs messages) rewritten mechanically; `.github/docs` history left as is.
- Option B module pattern: comment/message text only in modules; no new `lib.mkIf`.

## Risks and mitigations
- **External callers**: `VexPortal` (github:VictoryTek/VexPortal, a GUI front end for this justfile with
  a recipe catalog + argument validation + drift detection) and any user muscle memory/scripts use old
  names. Not verifiable from this repo — flagged to the user; VexPortal's catalog must be updated.
- Behavioural nuance: grouped recipes take `*args` as one whitespace-split string (no arguments with spaces).
- Real ZFS/mergerfs/SnapRAID/disks not available in dev: validated with stub harnesses + shellcheck +
  `just` parse/dispatch tests; user should try on spare disks.
