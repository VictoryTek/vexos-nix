# VM install OOM + install speed — spec

Feature name: `vm_install_oom`
Trigger: `desktop-vm` + Hyprland install on Proxmox repeatedly OOMs / cancels.

## Current state analysis

The install path (README "Fresh install") is:

1. `sudo curl -o /etc/nixos/flake.nix .../template/etc-nixos-flake.nix`
2. `curl .../scripts/install.sh | bash`

`scripts/install.sh` then, on the already-running stock NixOS system:

- `nix flake update --flake git+file:///etc/nixos` (line 741-746)
- `sudo nixos-rebuild dry-build --flake 'git+file:///etc/nixos#<target>'`
  (line 766-772) — a **full evaluation**, discarded after printing an
  informational "will build locally" list.
- `sudo nixos-rebuild boot --flake 'git+file:///etc/nixos#<target>'`
  (line 811-812) — a **second full evaluation**, then the real build.

No `--max-jobs`, no `--option extra-substituters`, no swap handling anywhere.

### Measured facts (this machine, warm store)

| Measurement | Command | Result |
|---|---|---|
| Peak RSS of one full evaluation of `vexos-desktop-vm` | `time -v nix eval --impure '.#nixosConfigurations.vexos-desktop-vm.config.system.build.toplevel.drvPath'` | **1,784,224 KB ≈ 1.7 GiB**, 11.5 s on 16 cores |
| `noctalia-5.1.0` in `cache.nixos.org` | `nix path-info --store https://cache.nixos.org /nix/store/5pk42nv144lw8q9drsyg4i5q6r48fin3-noctalia-5.1.0` | **NO** (`path is not valid`) |
| `noctalia-5.1.0` in `noctalia.cachix.org` | same, `--store https://noctalia.cachix.org` | **YES** |
| `noctalia` in the Hyprland VM closure | `nix-store -q --requisites <toplevel.drv>` with `vexos.desktop.environment = "hyprland"` | **YES** (`noctalia-5.1.0.drv`) |
| `up-2.3.3` in `cache.nixos.org` | `nix path-info --store https://cache.nixos.org …` | **NO** — and it is a `cargo` release build (`buildRustPackage`, `doCheck = 1`, GTK4/libadwaita) |
| `vexportal-0.1.0` in `cache.nixos.org` | same | **NO** — same shape |
| `dms-shell` in the closure | `nix-store -q --requisites` | **NO** (disabled in `home/dank-material-shell.nix`, `enable = false`) — not a factor |
| `nixos-rebuild` flag support | `nixos-rebuild --help` | `--max-jobs`, `--cores`, `--option OPTION OPTION`, `--accept-flake-config` all supported (nixos-rebuild-ng) |

### Why the substituters are missing at install time

`flake.nix` (repo root) has a `nixConfig` block listing
`https://noctalia.cachix.org` and the proxmox cache. It does **not** apply
during an install, for two independent reasons:

1. The flake actually being built is `git+file:///etc/nixos` (the template
   wrapper), not this repo. Only the **top-level** flake's `nixConfig` is ever
   read; an input's `nixConfig` is ignored. `template/etc-nixos-flake.nix` has
   no `nixConfig`.
2. Even for a direct repo build, `nixConfig` requires an interactive y/N
   prompt or `--accept-flake-config`, and `install.sh` passes neither.

`modules/nix-noctalia-cache.nix` fixes this permanently — but only from the
**second** boot onward, because it is part of the configuration being built.

## Problem definition

On a Proxmox `desktop-vm` + Hyprland install the guest must, within its
assigned RAM and with no swap:

1. Hold a ~1.7-2 GiB evaluation heap — **twice** (dry-build, then build).
2. Compile `noctalia` (Qt/QML/C++) from source, purely because a known-good
   binary cache is not configured at that moment.
3. Compile `up` and `vexportal` (Rust release builds + test suites) from
   source — these are in no public cache at all.
4. Do (2) and (3) with `max-jobs = auto`, i.e. as many concurrent compiles as
   the guest has vCPUs, each with its own multi-hundred-MB-to-GB peak.

A 2 GiB Proxmox guest (the Proxmox default) OOMs during step 1, before any
build starts. A 4 GiB guest survives evaluation and dies in step 2/3.

Note `modules/gpu/vm.nix:51` also sets `vexos.swap.enable = false` for every VM
guest ("VMs rely on hypervisor memory management"), which is incorrect for a
guest: ballooning cannot give a guest more RAM than its configured maximum. So
the *installed* VM has only zram and repeats the same failure on the next
`just update`.

## Proposed solution

Five changes; the first three stop the OOM, the fourth is pure speed, the fifth
stops the same failure recurring after install.

### 1. Configure the known binary caches for the install build (`scripts/install.sh`)

Pass them explicitly on both `nixos-rebuild` invocations:

```
--option extra-substituters "https://noctalia.cachix.org https://cache.saumon.network/proxmox-nixos"
--option extra-trusted-public-keys "noctalia.cachix.org-1:pCOR47nnMEo5thcxNDtzWpOxNFQsBRglJzxWPp3dkU4= proxmox-nixos:D9RYSWpQQC/msZUWphOY2I5RLH5Dd6yQcaHIuug7dWM="
```

Explicit `--option` rather than adding `nixConfig` to the template plus
`--accept-flake-config`, because:

- it works even when `/etc/nixos/flake.nix` is an older template — a documented
  flow (the installer's own "run this installer again to switch" path never
  re-downloads the template);
- it needs no interactive prompt and no `accept-flake-config` setting;
- `root` is always a trusted user, so `extra-substituters` is honoured.

Keys are duplicated from `flake.nix`'s `nixConfig`; `install.sh` runs
standalone via `curl | bash` with no repo checkout, so a shared fragment is not
possible. Same "kept in sync manually" situation as the existing
`UNAVOIDABLE_REGEX` — carry the same style of comment.

### 2. Serialise local builds (`scripts/install.sh`)

Add `--max-jobs 1` to the `nixos-rebuild boot` invocation. This matches what
the installed system already enforces for exactly this reason
(`modules/nix.nix:150`, `max-jobs = lib.mkDefault 1`, comment: "Prevents OOM on
low-RAM machines"). Substitutions are governed by `max-substitution-jobs`, not
`max-jobs`, so download throughput is unaffected — this costs no install time
on a cache-hit install.

### 3. Temporary install swap (`scripts/install.sh`)

Before the build, if `MemTotal + SwapTotal < 8 GiB`, create and activate a
4 GiB swapfile at `/var/vexos-install-swap`, and `swapoff`/`rm` it from an
`EXIT` trap. Per root filesystem type:

- `btrfs` → `btrfs filesystem mkswapfile --size 4g` (a plain `dd` file cannot
  be swapped on btrfs — needs nocow/nodatasum, which that subcommand handles)
- `tmpfs` (live ISO) or `zfs` → skip with a printed warning (swap into RAM is
  pointless; a zvol is out of scope)
- anything else (ext4/xfs) → `fallocate` (fall back to `dd`) + `mkswap`
- skip with a warning if less than 10 GiB free on `/`

Print the detected RAM/swap either way, so a too-small guest is visible in the
log rather than showing up as a silent kill.

### 4. Drop the redundant dry-build evaluation (`scripts/install.sh`)

Remove the "Checking build cache..." stage (lines ~752-809) and the
`SOURCE_BUILDS`/`UNAVOIDABLE`/`OTHER` reporting it feeds. It costs one entire
extra evaluation — the single most expensive non-build step, and a second
~1.7 GiB memory peak — to print a list that `nix build` prints itself
("these N derivations will be built") at the start of the real build that
follows seconds later.

Renumber the remaining `render_progress` steps (currently `1 4` … `3 4`).

### 5. Give VM guests real swap (`modules/gpu/vm.nix`)

Remove `vexos.swap.enable = false;` (line 51) so VM guests get the standard
8 GiB `/var/lib/swapfile` from `modules/system.nix` like every other role. The
existing rationale is wrong for a guest, and this is what makes the *next*
rebuild on a small VM survive. `hosts/desktop-vm.nix:22-24` and
`modules/gpu/vanilla-vm.nix:29` carry comments referencing this line — update
them so they do not describe a setting that no longer exists.

Not changed: `vexos.btrfs.enable = false` in the same file (unrelated).

## Implementation steps

1. `scripts/install.sh` — add `SUBSTITUTER_ARGS` (array) near the top of the
   build section; add the swap helper + `trap`; delete the dry-build stage;
   renumber progress steps; add `--max-jobs 1` and the substituter options to
   the `nixos-rebuild boot` call.
   Verify: `shellcheck scripts/install.sh` clean; `bash -n` clean.
2. `modules/gpu/vm.nix` — delete the `vexos.swap.enable = false;` line and its
   comment. Verify: `nix eval` of `vexos-desktop-vm` shows a non-empty
   `swapDevices`.
3. `hosts/desktop-vm.nix`, `modules/gpu/vanilla-vm.nix` — correct the stale
   cross-references. Verify: `grep -rn "swap.enable" modules/gpu hosts`.
4. Build validation: `nix flake show --impure`, then
   `sudo nixos-rebuild dry-build` for `vexos-desktop-amd`, `-nvidia`, `-vm`.
5. `bash scripts/preflight.sh`.

## Dependencies

None added. No Context7 lookup applies — no new external library; the only
third-party surfaces touched (`nixos-rebuild` flags, `btrfs filesystem
mkswapfile`) were verified directly against the binaries on this host.

## Configuration changes

- VM guests gain an 8 GiB `/var/lib/swapfile` after the next rebuild (disk
  space, thin-provisioned).
- Install-time: one transient 4 GiB `/var/vexos-install-swap`, removed on exit.

## Risks and mitigations

| Risk | Mitigation |
|---|---|
| `--option` unsupported by an older `nixos-rebuild` on some host | Both the legacy Perl and current `nixos-rebuild-ng` accept `--option`/`--max-jobs`; verified in `--help` on this host |
| Substituter unreachable (offline install) | Additive substituter; Nix falls back to the next one, then to building. Never fatal |
| Stale `/var/vexos-install-swap` left behind if the script is SIGKILLed | Named distinctively; the helper reuses/replaces it on the next run rather than failing |
| Swapfile creation fails on an exotic root fs | Every failure path warns and continues — the install proceeds exactly as it does today |
| Losing the pre-build "will build locally" list | The real build prints the same list; the NVIDIA/openrazer explanation was informational only |
| 8 GiB swapfile on small VM disks | Standard for every other role in this repo; `vexos.swap.enable = false` remains available per-host |

## Out of scope (recommended follow-up)

`up` and `vexportal` are Rust release builds present in **no** binary cache, so
every install of every role compiles both. Publishing them (Cachix in their own
repos' CI, or pinning them into the existing Harmonia cache) would remove the
largest remaining chunk of install time and the last significant memory peak.
That work belongs in the `Up`/`VexPortal` repositories, not here.
