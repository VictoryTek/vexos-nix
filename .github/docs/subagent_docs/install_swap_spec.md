# Shared install-time swap (audit item 9) — Specification

Tracker: `installer_audit_findings.md` item 9.

## 1. Current state
Three separate implementations of "give the current session enough swap to
survive a from-source build," all sharing the same underlying purpose but with
different policies:

| Caller | Path | Size | Guards | Lifecycle |
|---|---|---|---|---|
| `install.sh` | `/var/vexos-install-swap` | 4 GiB | skip if RAM+swap≥8GiB, skip on tmpfs/zfs root, skip if <10GiB free on `/` | deleted (rm) via EXIT trap |
| `stateless-setup.sh` | `/mnt/persistent/swapfile` | 8 GiB | none | left on disk (only swapoff'd); becomes the *permanent* swapfile `modules/impermanence.nix` declares |
| `migrate-to-stateless.sh` | `${BTRFS_MOUNT}/@persist/swapfile` | 8 GiB | none | same as above |

The 8 GiB size in the stateless paths is not arbitrary — it matches
`modules/impermanence.nix`'s `swapDevices` declaration exactly
(`modules/impermanence.nix:154-156`), which auto-creates the same file via
`btrfs filesystem mkswapfile` on first boot if it isn't already there (per that
module's own comment). So creating it early is an optimization (skip
recreating it at first boot), not a correctness requirement — confirmed by
reading the module, not previously stated in the audit.

## 2. Design
One function, `ensure_install_swap <swapfile-path> <size-mib>`, in a new
`scripts/lib/swap.sh`, loaded by `lib/bootstrap.sh` (not cosmetic — aborts the
same way `prompts.sh` does if it fails to load). Applies `install.sh`'s three
guards uniformly, parameterised:
- RAM+swap ≥ 8 GiB → skip (unchanged threshold, independent of requested size).
- Target filesystem is tmpfs/zfs → skip. Checked with `findmnt -T` (resolves
  any path to its containing mount), not `findmnt <path>` (exact-mountpoint
  only) — required because `migrate-to-stateless.sh`'s target
  (`@persist/swapfile`) is a subvolume directory, not a separate mountpoint.
- Free space < size + 6 GiB headroom (same ratio as the original 4 GiB/10 GiB
  check, scaled to the requested size) → skip.

Sets `INSTALL_SWAP_ACTIVE=true|false`; creation/activation only. Each caller
keeps its own EXIT-trap cleanup (their lifecycles genuinely differ — delete vs.
leave in place — so a shared teardown would need the same "mode" parameter and
save nothing).

**Behaviour change (intended by the audit's proposed fix — "carrying
install.sh's guards"):** the two stateless scripts previously created their
8 GiB swapfile unconditionally. They now skip it under the same conditions
`install.sh` always has — most commonly, on a machine with ≥8 GiB RAM. The
final installed system is unaffected either way: NixOS creates the same file
at first boot if it's missing (see above). This trades a small amount of
wasted disk on well-provisioned machines for consistency with `install.sh`; it
does not weaken safety on constrained machines. Flagged for the user to
confirm this trade-off is wanted.

**Incidental parity fix:** `install.sh`'s original creation omitted
`--uuid clear` (both stateless scripts pass it, to avoid stale/duplicate swap
signatures on a freshly wiped disk). The shared function always passes it —
harmless on `install.sh`'s already-installed target, and now consistent.

## 3. Call sites
- `install.sh`: `ensure_install_swap "$VEXOS_INSTALL_SWAP" 4096`; cleanup trap
  now checks `INSTALL_SWAP_ACTIVE` instead of the old local `SWAP_CREATED`.
- `stateless-setup.sh` / `migrate-to-stateless.sh`: same call at 8192 MiB
  against their respective paths; their existing `swapoff`-only cleanup traps
  are unchanged (the file is still meant to survive).

## 4. Risks
| Risk | Mitigation |
|---|---|
| Behaviour change on stateless installs (see above) | Documented; final installed state unchanged either way |
| `findmnt -T` on a path that doesn't exist yet | Callers only invoke this after their target directory is mounted/created |
| Cannot run any of this on real hardware from the dev box | Unit-test the guard logic against fixture `/proc/meminfo` / `df` output and real loopback/tmpfs mounts in WSL |

## 5. Verification
`bash -n` + shellcheck; drive `ensure_install_swap` directly against a real
tmpfs mount (guard: skip) and a real loopback-mounted btrfs filesystem (guard:
create + `INSTALL_SWAP_ACTIVE=true`, confirm via `swapon --show`), with
`/proc/meminfo`-style thresholds forced both ways; preflight exit 0.
