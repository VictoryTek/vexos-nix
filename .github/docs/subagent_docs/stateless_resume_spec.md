# Resume after a failed stateless install (audit item 10) — Specification

Tracker: `installer_audit_findings.md` item 10.

## 1. Current state
`stateless-setup.sh` always invokes disko with `--mode destroy,format,mount
--yes-wipe-all-disks`. A `nixos-install` failure after disko has already
formatted the disk and populated part of `@nix` (the persistent Nix store
subvolume) means a re-run wipes that disk and starts the from-source build
over from nothing — including whatever was already downloaded/built into
`@nix` by the failed attempt.

`migrate-to-stateless.sh` already detects existing `@nix`/`@persist`
subvolumes (via `btrfs subvolume show`) and skips creating them — but that
script never destroys anything to begin with (it's an in-place, additive
migration), so there's no destructive step to skip there. The audit's
"reuse that approach" means the *detection technique*, not the flow itself.

## 2. Design
Detect, right before the existing "Installation summary" block (same
placement `migrate-to-stateless.sh` uses before its own summary):
- disko's own partition labels for this layout, `disk-main-ESP` /
  `disk-main-data` (from `template/stateless-disko.nix`'s `disk.main` /
  `ESP`/`data` names — disko's fixed naming convention), exist as block
  devices.
- Both resolve (via `lsblk -no PKNAME`) to the **currently selected** `$DISK`
  — never silently reuse a layout left on a different, unplugged/replugged
  disk.
- Their filesystem types are `vfat` / `btrfs` respectively.
- Mounting the data partition at `subvolid=5` shows both `@nix` and
  `@persist` subvolumes present (`btrfs subvolume show`, same call
  `migrate-to-stateless.sh` already makes).

If all of that holds, resume is *possible*. Whether it's *used* is then a
choice, not automatic — the user may genuinely want a clean reinstall (stale
disk from an unrelated earlier attempt, or wanting to change disk layout).
Reuses the same `--wipe` / `VEXOS_ANSWER_WIPE` preset pattern item 8 already
established (`--limine`, `--reboot`) rather than inventing a new mechanism:
- Interactive, resume possible, no `--wipe`: ask (default: resume — the
  non-destructive path), framed as "Wipe and start over instead of
  resuming?" so the safe answer is the empty-Enter default.
- `--wipe`: force the destructive path regardless.
- `--yes` (unattended) with no `--wipe`: resume automatically — the safer
  default for an unattended run is not to silently wipe a disk that has a
  usable prior attempt on it.

When resuming, disko itself does the mount — `nix run … disko -- --mode
mount …` (confirmed via Context7 against current disko docs: `mount`
"mount[s] the partitions at the specified root-mountpoint", no destroy/format
involved; `--yes-wipe-all-disks` is dropped, since nothing is being wiped).
This is a real resume, not just "skip a formatting step": `@nix` already
contains whatever the failed attempt downloaded/built, so the following
`nixos-install` reuses it instead of starting cold.

The summary and confirmation prompt reflect whichever mode was decided
("Mode: Resume — reuses the existing layout, disk not erased" vs. "Mode:
Fresh install — `$DISK` will be erased"), so the confirmation prompt's
wording is never wrong about what it's about to do.

## 3. New flag
`--wipe` (boolean, same shape as `--limine`/`--reboot`): force a fresh
destroy+format even when a resumable layout is detected. Added to
`_flag_for`, `parse_answer_flags`, `_answer_usage` in `lib/prompts.sh` (shared
file, but the flag is only consulted by `stateless-setup.sh`).

## 4. Risks
| Risk | Mitigation |
|---|---|
| Resuming into a layout from an unrelated/incompatible prior attempt | Filesystem-type check + subvolume presence check, not just partlabel existence |
| Reusing a layout left on a different disk than the one just chosen | `lsblk -no PKNAME` parent-disk check against `$DISK` |
| disko's `mount` mode behaves differently across versions | Confirmed via Context7 against current disko docs; not tested against the exact locked revision (no real disk hardware available) |
| User wants a clean reinstall on a disk that happens to carry a stale layout | `--wipe` override |

## 5. Verification
Loopback-disk fixture in WSL (run as root, same technique as item 9's swap
tests): build a GPT disk with the exact `disko` partition/subvolume layout,
confirm detection fires only when partlabels + parent-disk + fstype +
subvolumes all match, and that it correctly declines when any one of those is
wrong (wrong parent disk, missing subvolume, non-btrfs data partition). Not
run against the real `stateless-setup.sh` end to end (needs a live ISO) or
against real disko `--mode mount` (needs the real network-fetched disko
binary and a target the script itself formats — the loopback fixture is
pre-built directly with `btrfs`/`mkfs.vfat`, not through disko, to isolate the
detection logic from the disko binary itself).
