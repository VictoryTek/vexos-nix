# VM install OOM + install speed — review

Spec: `.github/docs/subagent_docs/vm_install_oom_spec.md`

## Files reviewed

| File | Change |
|---|---|
| `scripts/install.sh` | Install-time substituters, `--max-jobs 1`, temporary swapfile, dry-build stage removed, progress renumbered |
| `modules/gpu/vm.nix` | `vexos.swap.enable = false` removed (VM guests get the standard swapfile) |
| `hosts/desktop-vm.nix` | Stale cross-reference corrected |
| `modules/gpu/vanilla-vm.nix` | Stale cross-references corrected (×2) |
| `template/etc-nixos-flake.nix` | Stale cross-reference corrected |

## 1. Specification compliance

All five changes implemented as specified, nothing beyond them.

- Substituters passed as `--option` (not template `nixConfig`), as decided in the
  spec, so an outdated `/etc/nixos/flake.nix` is still covered.
- `--max-jobs 1` on the build call only.
- Swap threshold, size, fs handling (`btrfs filesystem mkswapfile` / `dd`),
  tmpfs+zfs skip, 10 GiB free-space guard, `EXIT` trap — all as specified.
- Dry-build stage and its `SOURCE_BUILDS`/`UNAVOIDABLE`/`OTHER` reporting removed;
  no dangling references remain (`grep -n "DRY_OUT\|SOURCE_BUILDS"` → none).
- Progress steps renumbered `1 3`, `2 3`, `3 3`.

## 2. Best practices / code quality

- `set -e` safety: the swapfile creation runs inside an `if ( set -e … ); then`
  subshell, so a failure is consumed by the condition and cannot abort the
  installer. Every early return in `setup_install_swap` is an explicit
  `return 0`, never a bare test as the last command.
- `dd` rather than `fallocate` on non-btrfs: `swapon` rejects the unwritten
  extents `fallocate` leaves on ext4. Chosen deliberately and commented.
- Cleanup is a `trap … EXIT` guarded by `SWAP_CREATED`, and the creation path
  `rm -f`s any stale file first, so a SIGKILLed previous run self-heals.
- Option arrays quoted as `"${INSTALL_CACHE_OPTS[@]}"`.
- `shellcheck scripts/install.sh` → only the pre-existing `SC1091` info at
  line 84 (`source /dev/stdin`, untouched by this change). No new findings.
- `bash -n scripts/install.sh` → clean.

## 3. Consistency (Module Architecture Pattern)

No new `lib.mkIf` guards and no new module files — the only Nix change is the
removal of one unconditional assignment in an existing GPU-variant module.
`vexos.swap.enable` remains a declared toggle in `modules/system.nix`
(the documented carve-out: a module gating on an option it declares), and the
per-role overrides that still set it (`modules/impermanence.nix` `mkForce
false`, `modules/zfs-server.nix` `mkDefault false`) are untouched and still win.

## 4. Completeness / functionality

Verified per-variant effect of removing the VM swap opt-out:

| Variant | `config.swapDevices` | Correct? |
|---|---|---|
| `vexos-desktop-vm` | `[{ device = "/var/lib/swapfile"; size = 8192; }]` | Yes — the intended fix |
| `vexos-htpc-vm` | evaluates (same path) | Yes |
| `vexos-stateless-vm` | `[ "/persistent/swapfile" ]` | Yes — unchanged; `modules/impermanence.nix` still forces the generic swapfile off and supplies its own on persistent storage |
| `vexos-headless-server-vm` | `[ ]` | Yes — unchanged; `modules/zfs-server.nix` still disables swap on ZFS |
| `vexos-vanilla-vm` | n/a | Yes — vanilla does not import `modules/system.nix` |

## 5. Security

No secrets, no credentials, no world-writable files. The temporary swapfile is
created `0600` (`chmod 600` on the `dd` path; `btrfs filesystem mkswapfile`
creates `0600` itself) and removed on exit. The two substituter public keys
added are public verification keys already committed in `flake.nix`'s
`nixConfig` — not secrets. Substituters are additive and signature-verified.

## 6. Performance

- One full evaluation removed from every install (measured peak **1.7 GiB**,
  and the single most expensive non-build step).
- `noctalia` now fetched instead of compiled on every Hyprland install
  (verified present in `noctalia.cachix.org`, absent from `cache.nixos.org`).
- `--max-jobs 1` does not slow a cache-hit install: substitution concurrency is
  governed by `max-substitution-jobs`.
- Cost added: up to ~4 GiB of `dd` on low-RAM machines only, and 8 GiB of disk
  for the post-install VM swapfile.

## 7. Build validation

`sudo` is unavailable in this environment ("no new privileges" flag), so
`nixos-rebuild dry-build` could not be invoked. Used the project's documented
equivalent instead — `nix eval` of `…config.system.build.toplevel.drvPath`,
which forces the same full evaluation (CLAUDE.md, Test Commands).

| Check | Result |
|---|---|
| `nix flake show --impure` | Pass (only the pre-existing `kernel-override … is not a derivation` warnings) |
| `nix eval … vexos-desktop-amd …drvPath` | Pass |
| `nix eval … vexos-desktop-nvidia …drvPath` | Pass |
| `nix eval … vexos-desktop-vm …drvPath` | Pass |
| `nix eval … vexos-htpc-vm …drvPath` | Pass |
| `nix eval … vexos-stateless-vm …drvPath` | Pass |
| `nix eval … vexos-vanilla-vm …drvPath` | Pass |
| `nix eval … vexos-server-vm …drvPath` | Fails on the `networking.hostId` assertion — **pre-existing**, host-supplied by the installer, unrelated to this change |
| `git ls-files hardware-configuration.nix` | Empty |
| `system.stateVersion` in all `configuration-*.nix` | Unchanged (`25.11` ×6); not in the diff |
| New flake inputs | None added — no `follows` review needed |

## Score table

| Category | Score | Grade |
|----------|-------|-------|
| Specification Compliance | 100% | A |
| Best Practices | 96% | A |
| Functionality | 98% | A |
| Code Quality | 95% | A |
| Security | 100% | A |
| Performance | 98% | A |
| Consistency | 100% | A |
| Build Success | 95% | A |

**Overall Grade: A (98%)**

Build Success is 95% rather than 100% only because `nixos-rebuild dry-build`
could not be executed here; the equivalent full evaluation passed for every
affected variant.

## Result

**PASS** — no CRITICAL or RECOMMENDED findings. Proceed to Phase 6.

## Note for the user (not a defect in this change)

`up` and `vexportal` are Rust release builds present in no binary cache, so
every install of every role still compiles both. That is now the largest
remaining chunk of install time. Fixing it means publishing those two packages
(Cachix in their own repos' CI, or pinning them into the existing Harmonia
cache) — work that belongs in the `Up`/`VexPortal` repositories.
