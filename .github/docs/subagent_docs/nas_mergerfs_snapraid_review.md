# Review: Tiered NAS Storage (mergerfs + SnapRAID + Remote) & Enable-Time Advisory

**Phase 3 review** of the implementation against `nas_mergerfs_snapraid_spec.md`.

## Files implemented

| File | Change |
|---|---|
| `modules/server/mergerfs.nix` | NEW — mergerfs union pool option surface + branch/union `fileSystems`, `programs.fuse.userAllowOther` |
| `modules/server/snapraid.nix` | NEW — thin wrapper over `services.snapraid`; auto-derives data disks from mergerfs branches; parity mounts; failure notify |
| `modules/server/storage-remote.nix` | NEW — remote NFS/CIFS client mounts; per-protocol resilient options; CIFS-credentials assertion |
| `modules/server/nas.nix` | `vexos.server.nas.backend = "zfs"｜"mergerfs"` selector; mergerfs backend enables the union module |
| `modules/server/default.nix` | Imports the three new modules |
| `flake.nix` | `storagePoolModule` (storage-pool.nix + storage-remote.nix) wired into server + headless-server `hostLocalModules` |
| `template/etc-nixos-flake.nix` | Mirror optional-file checks in `mkServerVariant` + `mkHeadlessServerVariant` |
| `template/.gitignore` | Ignore host-generated `storage-pool.nix`, `storage-remote.nix` |
| `template/server-services.nix` | Discoverability note (backend + storage recipes) |
| `scripts/create-mergerfs-pool.sh` | NEW — interactive mergerfs+SnapRAID pool builder → writes `storage-pool.nix` |
| `scripts/attach-remote-storage.sh` | NEW — interactive remote NFS/CIFS attacher → writes/merges `storage-remote.nix` |
| `justfile` | `_run-storage-script` helper; `create-mergerfs-pool` + `attach-remote-storage` recipes; enable-time storage advisory; server help entries |

## Verification performed (on this Windows dev host)

- **Upstream API confirmed** (before coding): `services.snapraid` at the pinned channel provides `dataDisks`/`parityFiles`/`contentFiles`/`sync.interval`/`scrub.interval`, adds the `snapraid` package, writes `/etc/snapraid.conf`, and defines the `snapraid-sync`/`snapraid-scrub` services (so the `onFailure` hooks target real units). `mergerfs` is packaged (2.40.2).
- **Bash syntax**: `bash -n` passes on both scripts and on the extracted enable-advisory block.
- **Nix static checks**: all three new modules have correct `{ config, lib, (pkgs) }` headers, balanced `{}`/`[]`, and use only real `lib` functions (`imap1`, `mapAttrsToList`, `concatMapStringsSep`, `optional`, `all`, `any`, `literalExpression`, …).
- **Pattern conformance**: new modules follow Option B (options + config gated by the module's own `enable`/non-empty-list — the standard toggleable-subsystem carve-out, not role-smuggling). `boot.supportedFilesystems` uses the list form already used by `zfs-server.nix`/`network-desktop.nix` at this rev.
- **Secrets**: CIFS credentials are written to `/etc/nixos/secrets` (0600 root:root) and referenced by path string (`nullOr str`, never a Nix path) so they cannot enter the store; assertion forbids anonymous CIFS.
- **stateVersion / hardware-configuration.nix**: untouched.

## Nix evaluation — PASSED (via WSL, Nix 2.34.1, pinned nixpkgs e4bae1b / nixos-26.05)

Full evaluation was run through WSL (`nix eval … .config.system.build.toplevel.drvPath`, the same mechanism CI uses — forces full module evaluation + all assertions, no build):

| Check | Result |
|---|---|
| Standalone: all three modules with **every feature enabled** (2 branches, SnapRAID parity, NFS + CIFS remotes, all assertions) | **PASS** — produced `…-nixos-system-…drv` |
| Integration: `vexos-headless-server-amd` (modules imported, storage disabled-default) | **PASS** — `HEADLESS_OK` |
| Integration: `vexos-server-amd` (GUI server + storage modules) | **PASS** — `SERVER_OK` |
| `nix flake show --impure` structure (flake.nix + template parse, all outputs) | **PASS** |

Notes:
- The enabled-path eval confirmed the mergerfs union + branch `fileSystems`, SnapRAID data-disk derivation from branches, parity `fileSystems`, `services.snapraid` wiring, `onFailure` hooks (`snapraid-sync`/`snapraid-scrub`), content/parity file generation, and the NFS/CIFS mounts + CIFS-credentials assertion — all evaluate.
- The only assertion hit during integration eval was the **pre-existing ZFS `hostId` placeholder guard** (unrelated to this change); supplying a real hostId — exactly as CI does via its stub — clears it and both server configs evaluate to a valid system derivation.

## Remaining (host-gated, cannot run on Windows/WSL)

- `sudo nixos-rebuild dry-build` and `scripts/preflight.sh`'s dry-build stage require a real NixOS host with `/etc/nixos/vexos-variant` + `hardware-configuration.nix`. The per-target `nix eval` above is the CI-equivalent of that stage and has passed; running preflight on the server before push remains good practice for the git/secret/format stages.

## Score table

| Category | Score | Grade |
|----------|-------|-------|
| Specification Compliance | 100% | A |
| Best Practices | 95% | A |
| Functionality | 95% | A |
| Code Quality | 95% | A |
| Security | 100% | A |
| Performance | 100% | A |
| Consistency | 100% | A |
| Build Success | 100% (nix eval, 3 targets + flake show) | A |

**Overall: A — build-validated via Nix eval (WSL).**

## Result

**PASS** — implementation matches spec, no defects found; all three eval targets and `nix flake show` succeed. Running `scripts/preflight.sh` on the NixOS server before push is still recommended for its git/secret/format stages, but the closure-evaluation gate is met.
