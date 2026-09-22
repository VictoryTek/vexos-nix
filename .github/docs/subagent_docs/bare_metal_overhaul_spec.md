# Live-ISO bare-metal install for every role (audit item 12) — Specification

Tracker: `installer_audit_findings.md` item 12. User explicitly chose "full
implementation" over the audit's cheaper interim mitigation (fail-fast
messaging only).

## 1. Current state
Only `stateless` has a disko-based bare-metal path (`stateless-setup.sh`,
hidden entirely inside `install.sh`'s `ROLE = stateless` branch). The other
five roles (`desktop`, `htpc`, `server`, `headless-server`, `vanilla`), run
from a live ISO, fall into `install.sh`'s normal "already installed" flow —
which mounts an EFI partition that doesn't exist yet, then fails on a missing
`hardware-configuration.nix` after several minutes, per the audit's own
evidence.

## 2. Design

### 2a. Generalized disko layout
`template/stateless-disko.nix` → renamed `template/disko-layout.nix`, adds a
`stateless` bool param (default `true`, preserving today's behaviour for
existing callers). The only structural difference is what's inside the
`data`/`luks` partition's content:
- `stateless = true` (unchanged): Btrfs, `@nix`→`/nix`, `@persist`→`/persistent`.
- `stateless = false` (new): Btrfs, single top-level filesystem →`/`. No
  subvolumes — these roles have no impermanence needs, so no split is
  justified (Simplicity First). Btrfs, not ext4, to match the repo's existing
  conventions (`vexos.btrfs.enable` auto-detects and wires up
  `btrfs-assistant`/scrub for any Btrfs root; `mkswapfile` is already used
  Btrfs-aware throughout).

ESP (512M, vfat, `/boot`) and the LUKS wrapping are untouched — refactored
into a shared `rootContent` `let`-binding so the one real difference is
expressed once.

**No new NixOS module needed** for the conventional layout: unlike
`modules/stateless-disk.nix` (impermanence-specific, `neededForBoot` etc.),
conventional roles get their `fileSystems` straight from a freshly generated
`hardware-configuration.nix` — see 2c.

### 2b. Generalized script
`stateless-setup.sh` → renamed `scripts/bare-metal-install.sh`, takes a role
(via `ROLE` env, inherited from `install.sh`'s hand-off — matching every
other hand-off in this codebase — or `--role`/prompted when run standalone,
matching the script's existing dual "hand-off or run directly from a live
ISO by URL" usage).

Kept exactly as today, unconditionally: header/warning, nix-command+flakes
check, block-device listing, disk prompt, resume detection, summary +
confirm, disko template download, disko invocation, ASUS side-file, flake
template download, git init + flake update, `nixos-install`, reboot prompt.

**Resume detection (item 10) generalizes with almost no new logic**: the
subvolume-presence check only applies when `stateless`; the conventional
layout has nothing to check beyond "the partitions exist, belong to this
disk, and have the right filesystem types" — actually a *simpler* case than
stateless, not harder.

**What branches on role:**
- disko invocation: passes `--arg stateless "$([ "$ROLE" = stateless ] && echo true || echo false)"`.
- Install-time swap: stateless keeps its existing behaviour (the swapfile
  *is* the installed system's permanent swap, matching
  `modules/impermanence.nix`'s `swapDevices`, left on disk — see item 9's
  reasoning). Conventional roles use a disposable scratch file instead
  (`/mnt/var/tmp/vexos-install-swap`, always deleted after) — **not** the
  final system's own `/var/lib/swapfile` path, because predicting whether
  `vexos.swap.enable` will actually end up `true` for the chosen
  role+variant (it's `false` on VM guests and ZFS server roles) isn't worth
  the complexity; matches `install.sh`'s own existing scratch-swap pattern
  for the "already installed" flow instead.
- `hardware-configuration.nix` generation: stateless keeps its existing
  `--no-filesystems` + manual UUID injection (impermanence needs
  `neededForBoot = true`, which `nixos-generate-config` doesn't set).
  Conventional roles use a **plain** `nixos-generate-config --root /mnt` —
  no `--no-filesystems`, no manual injection — auto-detecting real
  `fileSystems` entries exactly the way an already-installed host's
  `hardware-configuration.nix` looks. Simpler than the stateless case, not
  harder.
- User password: stateless keeps writing `stateless-user-override.nix`
  exactly as today (required — `configuration-stateless.nix` locks the
  account by default and asserts against it). Conventional roles get a
  **new** `user-override.nix`.

### 2c. New requirement found during research: conventional roles need a password too
`modules/users.nix` (universal) declares the `nimda` account with no
`hashedPassword`/`initialPassword` at all. `nixos-install` does not prompt
for non-root account passwords, and NixOS defaults an undeclared password to
locked (`!`). A bare-metal install of `desktop`/`htpc`/`server`/
`headless-server`/`vanilla` that never asks for a password would boot into an
account nobody can log into — worse than today's "doesn't support fresh
installs" boundary, and not "end to end" per the audit's own framing. Not
mentioned in the audit (which was written assuming these roles are already
installed), but a hard requirement for this item to actually work.

Fix: `bare-metal-install.sh` always calls `ask_password` (already built in
item 8) for a fresh conventional install too, and writes:
```nix
# /etc/nixos/user-override.nix
{ lib, ... }: { users.users.nimda.hashedPassword = lib.mkOverride 50 "<hash>"; }
```
(same shape and priority as `stateless-user-override.nix`, chmod 0600 —
same reasoning, separate file so stateless's tested mechanism is untouched).

### 2d. Second pre-existing bug found during research: VM platform is broken for 2 of 6 roles
`install.sh`'s existing VM-platform write (`features_set "vexos.vm.platform"
… → features.nix`) is silently inert for `headless-server` and `vanilla`:
neither builder imports `featuresFile` (confirmed by reading
`template/etc-nixos-flake.nix`), so a VirtualBox choice for either role is
accepted, printed as a success, and never applied — the VM stays on the
`qemu` default. `vexos.vm.platform` itself is declared by
`modules/gpu/vm-guest-additions.nix`, reachable from *any* role via the
shared `gpuVm` module, independent of `featuresFile`.

This directly blocks item 12's own goal (`install.sh` handling bare metal
"end to end" for every role) whenever VirtualBox + headless-server/vanilla is
chosen, so it's in scope here, not adjacent scope creep. Fix: promote
`vm-platform.nix` (already used correctly by `mkStatelessVariant` and by
`migrate-to-stateless.sh`) into the shared `localFiles` list in
`template/etc-nixos-flake.nix` — all six builders import it uniformly, same
as `bootloader.nix`/`hardware-local.nix`/`hostname.nix`. `install.sh`'s
"already installed" flow switches from the `features.nix` write to a direct
`vm-platform.nix` write for this one key (its `DESKTOP_ENV` → `features.nix`
write is untouched — desktop does import `featuresFile`, no bug there).
`bare-metal-install.sh` writes the same file for a fresh VirtualBox install,
for any role, once — no per-role branching needed.

### 2e. New generic side-file: `user-override.nix`
Added to the shared `localFiles` list alongside `vm-platform.nix` — all six
builders. Harmless when absent or when stateless's own separate
`stateless-user-override.nix` is what's actually in use.

### 2f. `install.sh` control-flow change
Live-ISO detection moves out of the `ROLE = stateless`-only branch to run
once, right after role/desktop-environment selection, for every role. The
existing stateless-only logic (switch-variant-on-an-already-stateless-system;
in-place migration via `migrate-to-stateless.sh` on an existing non-tmpfs-root
install) is **preserved exactly as today**, still gated on `ROLE = stateless`
— that part is unrelated to item 12 (migration to stateless in-place isn't a
concept the other five roles have). Only the "this is a live ISO, no
persistent OS yet" sub-case generalizes: instead of a stateless-only hand-off,
it hands off to `bare-metal-install.sh` for *any* role, after the shared
GPU/NVIDIA/VM/ASUS prompts run (previously those prompts ran *after* the
stateless hand-off check, meaning stateless's own copy of them in
`stateless-setup.sh` was the only path that ever asked them for a live-ISO
run — now `install.sh` asks them once, uniformly, before branching on
live-ISO-ness, exactly like it already does for the "already installed" path).

### 2g. Renames requiring reference updates
Full-repo grep for `stateless-setup.sh` / `stateless-disko.nix` before
starting found 14 files with references (comments and one `just` recipe
message) beyond the files being renamed — `flake.nix`, `justfile`,
`modules/impermanence.nix`, `modules/stateless-disk.nix`,
`scripts/lib/{prompts,swap,progress,bootstrap}.sh`,
`scripts/{install,migrate-to-stateless}.sh`. All are comments/strings, no
logic; updated for accuracy, not functional changes.

**Found and deliberately left alone:** `template/.gitignore` is dead — grepped
for any reference to it anywhere in the repo and found none; nothing ever
copies it into `/etc/nixos` (every script writes its own inline, shorter
`.gitignore` instead). Pre-existing, unrelated to item 12, flagged per
CLAUDE.md's dead-code policy rather than touched.

## 3. Risks
| Risk | Mitigation |
|---|---|
| Conventional bare-metal install leaves the account locked | §2c — always ask for and write a password |
| VirtualBox silently inert on 2 of 6 roles | §2d — promote vm-platform.nix to universal |
| Cannot test any of this on real hardware or a live ISO | Real loopback-disk `nix eval` matrix across all 6 builders × all side-files, same technique as items 3/9/10; disko itself not exercised (needs real block devices it can safely wipe) |
| Rename leaves a stale reference | Full-repo grep before *and* after implementation |
| Btrfs-only conventional root is a bigger default change than "just fix the ISO path" | Matches repo-wide convention; `vexos.btrfs.enable` already auto-detects either way, so nothing downstream assumes ext4 |

## 4. Verification
`nix eval` of the renamed/generalized template for all 6 role×variant
combinations, with `stateless` true/false, and with the new
`vm-platform.nix`/`user-override.nix` side-files present; `bash -n` +
shellcheck on the renamed/new script; full-repo grep sweep for stale
references after implementation; preflight exit 0. `bare-metal-install.sh`'s
disk-selection/resume logic reused verbatim from the already-verified item-10
code, so not re-derived from scratch. Explicitly **not** verified: an actual
`nixos-install` run, a live ISO, or real disk hardware.
