# remote_storage_universal — Phase 1 Spec

## Request

Make `just attach-remote-storage` (attach a NAS via NFS/CIFS without hand-editing
fstab) available on **all** roles, not just server / headless-server. Chosen
approach: **promote the consumer module to universal** rather than build a
parallel desktop-only mechanism.

---

## Current state analysis

### The module
- `modules/server/storage-remote.nix` declares `vexos.server.storage.remote`
  (list of submodules: `type` nfs|cifs, `server`, `export`, `mountPoint`,
  `credentialsFile`, `options`) and, when non-empty, emits `fileSystems.*`
  entries with resilient options (`_netdev,nofail,x-systemd.automount,
  x-systemd.mount-timeout=30,noatime`), plus `boot.supportedFilesystems` and
  `environment.systemPackages` (`nfs-utils` / `cifs-utils`).
- Pure client mount. Nothing server-specific in its logic.
- Imported **only** via `modules/server/default.nix:67`, which is imported only
  by `configuration-server.nix` and `configuration-headless-server.nix`.

### The generated file
- `scripts/attach-remote-storage.sh` writes `/etc/nixos/storage-remote.nix`
  containing `{ vexos.server.storage.remote = [ <entries> ]; }`.
- `flake.nix:166-168` `storagePoolModule` conditionally imports that file
  (`builtins.pathExists`), and it is attached via `hostLocalModules` for
  **server** (`flake.nix:267`) and **headless-server** (`flake.nix:282`) only.
- CIFS credentials are written to `/etc/nixos/secrets/<name>` (mode 0600),
  referenced by host path — never inlined, never in the Nix store.

### The recipe
- `justfile:1853-1855`: `attach-remote-storage` is `[private]` (hidden from
  `just --list`) and depends on `_require-server-role` (`justfile:1596-1604`),
  which aborts unless `/etc/nixos/vexos-variant` matches `*server*`.
- Advertised only in the server-role branch of the default recipe
  (`justfile:23`).

### Consumers of the option
- `modules/lib/storage-mount-ordering.nix` — does **not** read the option; it
  only takes an explicit `mediaMounts` list per service. Comments reference
  `vexos.server.storage.remote` by name (lines 5, 27).
- 11 `modules/server/*.nix` service modules reference the name in **comments
  only** (grep: immich, jellyfin, plex, audiobookshelf, photoprism, kavita,
  nextcloud, komga, grimmory, navidrome, default).
- `modules/server/nas.nix:43` references it in a description string.

### Why it's currently gated
Not a deliberate "desktops shouldn't mount a NAS" decision. The feature shipped
as part of the server NAS stack (commit `d492936`); the option lives in the
`vexos.server.*` namespace and its declaring module is only pulled in by server
roles, so on a desktop the generated file would fail evaluation with
"option does not exist". `_require-server-role` is a guard rail around that gap.

---

## Problem definition

A client-side network mount is role-agnostic. Desktop / htpc / stateless users
have an equally legitimate need to attach a NAS share declaratively. The module,
the generated-file wiring, and the recipe are all artificially scoped to server
roles.

---

## Proposed solution architecture

### 1. Move + rename the module (Option B: universal base)

- Move `modules/server/storage-remote.nix` → `modules/storage-remote.nix`.
- Rename the option `vexos.server.storage.remote` → `vexos.storage.remote`.
  New namespace reflects that it is universal, not a server subsystem.
- Keep the existing `lib.mkIf (cfg != [])` carve-out — it gates on an option the
  same module declares, which the CLAUDE.md carve-out explicitly permits. No
  role/display/gaming `lib.mkIf`. Base file is inert (empty list) otherwise, so
  it is safe to import unconditionally on every role.
- Add a back-compat shim in the same file:
  ```nix
  imports = [
    (lib.mkRenamedOptionModule
      [ "vexos" "server" "storage" "remote" ]
      [ "vexos" "storage" "remote" ])
  ];
  ```
  This keeps any **already-deployed** `/etc/nixos/storage-remote.nix` on the
  user's server hosts evaluating cleanly after the rename, emitting only a
  deprecation warning until the file is regenerated.

### 2. Import it on every role

- `configuration-desktop.nix`, `configuration-htpc.nix`: add
  `./modules/storage-remote.nix` to the `imports` list (matching the
  "role = its import list" convention).
- `modules/server/default.nix:67`: update the path from `./storage-remote.nix`
  to `../storage-remote.nix` (server + headless-server keep it this way).
- `stateless` and `vanilla`: **out of scope** (user decision). Stateless has an
  unresolved `/etc/nixos/secrets` persistence question for CIFS; vanilla is a
  barebones role (`baseModules = []`). Both deferred to a possible follow-up.
  The `mkRenamedOptionModule` shim is still added (it costs nothing and covers
  existing server deployments).

### 3. Wire the generated file for every role

`flake.nix`:
- Split `storagePoolModule` (`flake.nix:166-168`) so the `storage-remote.nix`
  check is reusable, e.g. add:
  ```nix
  storageRemoteModule =
    let p = /etc/nixos/storage-remote.nix;
    in if builtins.pathExists p then [ p ] else [];
  ```
  and have `storagePoolModule` keep the `storage-pool.nix` half.
- Add `storageRemoteModule` to `hostLocalModules` for `desktop` and `htpc`
  (server/headless: replace the remote half of `storagePoolModule` with
  `storageRemoteModule`, no behaviour change). `stateless`/`vanilla` unchanged.
- Update the `template/etc-nixos-flake.nix` wrapper if it does the equivalent
  `pathExists` check independently (verify during Phase 2 — `flake.nix:145`
  notes the template does its own checks with relative paths).

### 4. Update the script

`scripts/attach-remote-storage.sh`:
- Line ~160: emit `vexos.storage.remote = [` instead of
  `vexos.server.storage.remote = [`.
- No other change (paths, markers, secrets handling unchanged).

### 5. Update the recipe

`justfile`:
- Replace the `_require-server-role` dependency with a new
  `_require-remote-storage-role` guard that permits
  `desktop|htpc|server|headless-server` and aborts on `stateless`/`vanilla`
  (those roles don't import the module yet — running the recipe there would
  write a file that fails evaluation). Message points at the follow-up.
- Remove `[private]` so it appears in `just --list`.
- Move it out of the server-only section into a role-neutral group
  (e.g. a new `[Storage]` group, or `[System Administration]`).
- `create-mergerfs-pool` and the `create-zfs-pool` recipes stay server-gated
  and `[private]` (they format local disks / are genuinely server-scoped).
- `justfile:23` server-branch help line: keep it (still valid for server), and
  ensure the recipe is discoverable for other roles via `just --list`.

### 6. Cosmetic comment updates (surgical, name-accuracy only)

- `modules/lib/storage-mount-ordering.nix` comments (lines 5, 27): rename to
  `vexos.storage.remote`.
- `modules/server/nas.nix:43`: rename in the description string.
- The 11 service-module comment references: rename to `vexos.storage.remote`.
  These are one-word substitutions; no logic touched.

---

## Implementation steps

1. `git mv modules/server/storage-remote.nix modules/storage-remote.nix`;
   rename option to `vexos.storage.remote`; add `mkRenamedOptionModule` shim.
   → verify: `nix flake show --impure` still lists all 30 outputs.
2. Update `modules/server/default.nix` import path.
   → verify: `sudo nixos-rebuild dry-build --flake .#vexos-server-amd`.
3. Add `./modules/storage-remote.nix` to `configuration-desktop.nix` and
   `configuration-htpc.nix` import lists.
   → verify: dry-build `.#vexos-desktop-amd`, `.#vexos-htpc-amd`.
4. `flake.nix`: add `storageRemoteModule`, attach to desktop/htpc
   `hostLocalModules`, refactor server/headless to use it.
   → verify: `nix flake show --impure`; dry-build desktop-amd with a temp
   `/etc/nixos/storage-remote.nix` present (see test plan).
5. Update `scripts/attach-remote-storage.sh` emitted option name.
   → verify: run script's write path in a scratch dir, `nix-instantiate
   --parse` the output.
6. `justfile`: ungate + unprivate + regroup the recipe.
   → verify: `just --list` shows `attach-remote-storage`;
   `just attach-remote-storage` no longer aborts on this desktop host.
7. Comment/description renames (steps 6 items above).
   → verify: `grep -rn "vexos.server.storage.remote"` returns only the
   `mkRenamedOptionModule` shim.
8. Phase 6 preflight.

---

## Dependencies

None new. No external libraries. `nfs-utils` / `cifs-utils` are already in
nixpkgs and already referenced by the module. Context7 not required (no new
dependency, internal Nix refactor).

---

## Configuration changes

- **Breaking (mitigated):** option path `vexos.server.storage.remote` →
  `vexos.storage.remote`. `mkRenamedOptionModule` preserves eval for existing
  deployed hosts with a deprecation warning; regenerating the file via the
  recipe clears it. The generated file is host-local and never committed, so no
  in-repo call sites change except comments.
- New: desktop / htpc / stateless roles now evaluate
  `/etc/nixos/storage-remote.nix` if present.

---

## Risks and mitigations

| Risk | Mitigation |
|------|------------|
| Existing server hosts break on option rename | `mkRenamedOptionModule` shim; verified via server-amd dry-build |
| `stateless` role: tmpfs root — mountpoint dirs and `/etc/nixos/secrets` persistence | `fileSystems` entries are declarative (recreated each boot). `/etc/nixos` persistence on stateless must be confirmed in Phase 2; if `/etc/nixos/secrets` is not persisted, CIFS on stateless needs a documented caveat or a persistence entry. NFS (no creds) is unaffected. **Flag for review.** |
| `template/etc-nixos-flake.nix` does its own `pathExists` wiring and is missed | Phase 2 must inspect the template and apply the equivalent change; Phase 3 build-validates a template-consumer path if one is testable |
| Recipe now runs on non-NixOS-ish hosts where `just rebuild` differs | `attach-remote-storage.sh` already checks `id -u` / root and does an optional test-mount; `just rebuild` is the existing apply path on all roles |
| `boot.supportedFilesystems = "nfs"/"cifs"` on desktop pulls kernel modules | Expected and desired; only triggered when an entry exists (`lib.mkIf cfg != []`) |
| Someone expects `create-mergerfs-pool` ungated too | Explicitly out of scope — that recipe formats local disks and is legitimately server-scoped |

---

## Test plan (Phase 3)

- `nix flake show --impure` — 30 outputs, no eval error.
- `sudo nixos-rebuild dry-build --flake .#vexos-desktop-amd`
- `sudo nixos-rebuild dry-build --flake .#vexos-desktop-nvidia`
- `sudo nixos-rebuild dry-build --flake .#vexos-desktop-vm`
- `sudo nixos-rebuild dry-build --flake .#vexos-htpc-amd`
- `sudo nixos-rebuild dry-build --flake .#vexos-stateless-amd` (regression — unchanged role)
- `sudo nixos-rebuild dry-build --flake .#vexos-server-amd`
- `sudo nixos-rebuild dry-build --flake .#vexos-headless-server-amd`
- Back-compat: temporarily place a `/etc/nixos/storage-remote.nix` using the
  **old** `vexos.server.storage.remote` name, dry-build desktop-amd + server-amd,
  confirm only a rename warning (not an error). Remove the temp file after.
- `git ls-files hardware-configuration.nix` → empty.
- `system.stateVersion` unchanged in all `configuration-*.nix`.
- `grep -rn "vexos.server.storage.remote"` → only the shim line.
- `bash scripts/preflight.sh` (Phase 6).

---

## Out of scope

- `create-mergerfs-pool`, `create-zfs-pool` — stay server-gated.
- `stateless` and `vanilla` roles — deferred (user decision). Stateless needs
  the `/etc/nixos/secrets` persistence question resolved first.
- Any change to mount-option defaults or the submodule schema.
- A GUI / GNOME "attach network drive" integration.
