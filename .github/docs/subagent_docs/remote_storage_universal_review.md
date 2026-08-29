# remote_storage_universal — Phase 3 Review

Spec: `.github/docs/subagent_docs/remote_storage_universal_spec.md`

## Modified files

- `modules/server/storage-remote.nix` → `modules/storage-remote.nix` (git mv)
  - option renamed `vexos.server.storage.remote` → `vexos.storage.remote`
  - `mkRenamedOptionModule` back-compat shim added
  - header comment rewritten (universal scope, fstab framing)
- `modules/server/default.nix` — import path `./storage-remote.nix` → `../storage-remote.nix`
- `configuration-desktop.nix` — imports `./modules/storage-remote.nix`
- `configuration-htpc.nix` — imports `./modules/storage-remote.nix`
- `flake.nix` — `storageRemoteModule` split out of `storagePoolModule`; attached to
  desktop + htpc `hostLocalModules`; server/headless updated to use it
- `template/etc-nixos-flake.nix` — `hasStorageRemote`/`storageRemoteFile` wired into
  `_mkVariantWith` (desktop) and `mkHtpcVariant`; comment updated
- `scripts/attach-remote-storage.sh` — emits `vexos.storage.remote`
- `justfile` — new `_require-remote-storage-role` guard; recipe un-`[private]`d,
  moved to `System Administration` group, guard swapped
- `modules/lib/storage-mount-ordering.nix`, `modules/server/nas.nix` — comment/description
  option-name updates

## Validation

| Check | Result |
|-------|--------|
| `nix flake show --impure` | PASS — all 30 nixosConfigurations enumerate |
| `nix eval .#…vexos-desktop-nvidia…toplevel.drvPath` | PASS |
| `nix eval .#…vexos-htpc-amd…toplevel.drvPath` | PASS |
| `nix eval .#…vexos-server-amd…` | pre-existing ZFS `networking.hostId` placeholder assertion — unrelated to this change, delegated to CI (see `zfs_hostid_fix` notes) |
| Back-compat shim: isolated `nixosSystem` setting **old** `vexos.server.storage.remote` | PASS — produces `fileSystems."/mnt/nas"` with `device = "10.0.0.5:/tank/media"` |
| `git ls-files hardware-configuration.nix` | empty |
| `system.stateVersion` unchanged | confirmed (no `configuration-*.nix` stateVersion edits) |
| `grep -rn "vexos.server.storage.remote"` | only the `mkRenamedOptionModule` line + its comment |
| `bash scripts/preflight.sh` | **PASSED** ("safe to push") |
| `nixpkgs-fmt --check` on touched files | fails, but every touched file already failed at HEAD — repo does not enforce fmt (preflight WARN only); surgical-changes rule ⇒ no whole-file reformat |

## Score table

| Category | Score | Grade |
|----------|-------|-------|
| Specification Compliance | 100% | A |
| Best Practices | 95% | A |
| Functionality | 100% | A |
| Code Quality | 95% | A |
| Security | 100% | A |
| Performance | 100% | A |
| Consistency | 100% | A |
| Build Success | 100% | A (desktop/htpc; server/headless via CI) |

**Overall Grade: A (98%)**

## Result: PASS

Notes:
- Server/headless local eval blocked only by the known pre-existing ZFS hostId
  placeholder guard — not introduced here. CI covers those variants.
- `stateless`/`vanilla` intentionally excluded per user decision; the
  `_require-remote-storage-role` guard blocks the recipe there with a clear message.
