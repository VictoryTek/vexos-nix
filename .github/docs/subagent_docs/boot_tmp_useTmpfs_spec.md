# Specification: `boot.tmp.useTmpfs` — Volatile `/tmp` for All Roles

**Feature name:** `boot_tmp_useTmpfs`
**Date:** 2026-05-16
**Status:** DRAFT — awaiting implementation

---

## 1. Current State Analysis

### 1.1 `modules/system.nix` — base module (imported by ALL roles)

**File:** `modules/system.nix`

- **No `boot.tmp.*` options are set anywhere in this file.**
- The unconditional config block (lines 42–101) configures the kernel, bootloader,
  Plymouth, ZRAM swap, CPU governor, and sysctl tunables — but `/tmp` handling is
  entirely absent.
- Result: all roles (desktop, server, htpc, headless-server, stateless)
  **inherit the NixOS default**, which is `boot.tmp.useTmpfs = false` and
  `boot.tmp.cleanOnBoot = false`. `/tmp` is a plain directory on the root
  filesystem, persisting across reboots.

### 1.2 `modules/impermanence.nix` — stateless role only

**File:** `modules/impermanence.nix`, **line 143**

```nix
# ── Clean /tmp on boot ──────────────────────────────────────────────────
# Belt-and-suspenders: / is already a fresh tmpfs on each boot, but
# setting cleanOnBoot makes the ephemeral intent explicit.
boot.tmp.cleanOnBoot = true;
```

This is the **only** `boot.tmp.*` setting in the entire repository.

It is emitted only when `cfg.enable = true` (i.e., the stateless role) via
`config = lib.mkIf cfg.enable { ... }`. The comment acknowledges the setting is
redundant — `/` is already a fresh tmpfs on each stateless boot, making `/tmp`
automatically empty — but retains it for explicitness.

### 1.3 Configuration imports summary

| Role             | Imports `system.nix` | Imports `impermanence.nix` | `/tmp` today         |
|------------------|----------------------|----------------------------|----------------------|
| desktop          | ✓                    | ✗                          | persists across boots |
| htpc             | ✓                    | ✗                          | persists across boots |
| server           | ✓                    | ✗                          | persists across boots |
| headless-server  | ✓                    | ✗                          | persists across boots |
| stateless        | ✓                    | ✓ (`enable = true`)        | cleaned on boot (via `cleanOnBoot`; also ephemeral because root is tmpfs) |

### 1.4 Existing `boot.tmp.*` grep

Running `grep -r 'boot\.tmp' .` across the repository yields exactly **one hit**:

```
modules/impermanence.nix:143:    boot.tmp.cleanOnBoot = true;
```

No other module, host file, or configuration file sets any `boot.tmp.*` option.

---

## 2. NixOS Option Reference (`nixos/modules/system/boot/tmp.nix`)

Source verified at:
`https://github.com/NixOS/nixpkgs/blob/nixos-25.05/nixos/modules/system/boot/tmp.nix`

### 2.1 `boot.tmp.cleanOnBoot` (default: `false`)

```nix
systemd.tmpfiles.rules = lib.optional cfg.cleanOnBoot "D! /tmp 1777 root root";
```

- Adds a **systemd-tmpfiles rule** (`D!` = create+clean on boot) that deletes all
  files under `/tmp` when the system boots.
- **Does not change the filesystem type or location of `/tmp`**.
- `/tmp` remains on the same storage as `/` — typically a persistent btrfs/ext4
  partition.
- The `!` flag in `D!` means the rule is "volatile" (executed at boot, not
  periodically), so the clean happens once per boot cycle.

### 2.2 `boot.tmp.useTmpfs` (default: `false`)

```nix
systemd.mounts = lib.mkIf cfg.useTmpfs [
  {
    what = "tmpfs";
    where = "/tmp";
    type = "tmpfs";
    mountConfig.Options = lib.concatStringsSep "," [
      "mode=1777"
      "strictatime"
      "rw"
      "nosuid"
      "nodev"
      "size=${toString cfg.tmpfsSize}"
      "huge=${cfg.tmpfsHugeMemoryPages}"
    ];
  }
];
```

- Adds a **systemd mount** that overlays `/tmp` with a fresh `tmpfs` at boot.
- `/tmp` is backed entirely by RAM (backed by ZRAM/swap on overflow).
- **Inherently wiped on every reboot** — a fresh tmpfs starts empty by definition.
- nixpkgs note: "Large Nix builds can fail if the mounted tmpfs is not large enough."

### 2.3 `boot.tmp.tmpfsSize` (default: `"50%"`)

- Passed as the `size=` mount option to systemd.
- Systemd interprets percentage strings as a fraction of physical RAM.
- `"50%"` → on 16 GiB RAM → `/tmp` may grow up to 8 GiB before swap.
- Can be overridden per-host with a plain assignment (priority 100, beats
  `lib.mkDefault` priority 1000).

### 2.4 Renamed options (backward compatibility)

```nix
(lib.mkRenamedOptionModule [ "boot" "cleanTmpDir"    ] [ "boot" "tmp" "cleanOnBoot" ])
(lib.mkRenamedOptionModule [ "boot" "tmpOnTmpfs"     ] [ "boot" "tmp" "useTmpfs"    ])
(lib.mkRenamedOptionModule [ "boot" "tmpOnTmpfsSize" ] [ "boot" "tmp" "tmpfsSize"   ])
```

`useTmpfs` is the canonical modern name (renamed from `tmpOnTmpfs`), available
since NixOS 22.11.

### 2.5 Compatibility: `useTmpfs` + `cleanOnBoot`

`useTmpfs` and `cleanOnBoot` are **completely independent** in the implementation:

- `useTmpfs` emits a `systemd.mounts` entry.
- `cleanOnBoot` emits a `systemd.tmpfiles.rules` entry.
- They do not conflict and can both be `true` simultaneously.
- When `useTmpfs = true`, `cleanOnBoot` is **redundant** (the fresh tmpfs mount is
  always empty) but **harmless** — the tmpfiles rule runs on an already-empty
  directory and does nothing.

---

## 3. Problem Definition

### 3.1 Desktop, HTPC, Server, Headless-Server — `/tmp` persists across reboots

On all non-stateless roles, `/tmp` is a plain directory on the persistent root
filesystem (btrfs or ext4). Files written to `/tmp` by applications, package
managers, build tools, or system services survive reboots indefinitely unless
manually deleted.

**Consequences:**
- Stale lock files, sockets, and crash remnants accumulate.
- GNOME session artefacts from one boot can interfere with the next.
- Build artefacts from `nixos-rebuild` or `nix build` sessions persist.
- Non-deterministic state from prior sessions leaks into fresh logins.

### 3.2 Stateless role — `cleanOnBoot` is redundant

On the stateless role, `/` is already a `tmpfs` (25% of RAM). `/tmp` lives on
that root tmpfs and is wiped on every boot as a side effect of root being
ephemeral. The `boot.tmp.cleanOnBoot = true` in `impermanence.nix` is therefore
redundant from day one.

Furthermore, after adding `useTmpfs = true` globally (proposed fix), `/tmp` on
stateless gets its **own** dedicated tmpfs overlay (50% of RAM), making
`cleanOnBoot` redundant at a second level.

### 3.3 Architecture drift: tmp policy scattered across modules

The project's module architecture principle is that `system.nix` is the
unconditional base for all roles. Placing a `/tmp` policy only in
`impermanence.nix` (a role-specific module) breaks this principle: the policy
that applies to ALL roles (clean /tmp on boot) is not expressed in the base.

---

## 4. Proposed Solution

### 4.1 Architecture decision

Following the **Option B: Common base + role additions** architecture:

- **Universal policy** (clean `/tmp` on every reboot) belongs in `modules/system.nix`.
- **Role-specific override** (remove stale redundant `cleanOnBoot` flag) belongs
  in `modules/impermanence.nix`.
- No new module file is required — this is a change to two existing files.

### 4.2 Exact changes

#### Change 1 — `modules/system.nix`

Add inside the unconditional `config` block, after the existing `zramSwap`
block and before the closing `}` of the unconditional section. Place it in the
`# ── Kernel parameters ───────────────────────────────────────────────`
logical group or as its own `# ── Volatile /tmp ───` block.

**Exact location:** After line 76 (end of `zramSwap` block), before line 78
(`# ── CPU frequency governor`), insert:

```nix
      # ── Volatile /tmp (tmpfs) ────────────────────────────────────────────────
      # Mount /tmp as a RAM-backed tmpfs, wiped on every reboot.
      # Matches modern NixOS/SteamOS/Bazzite practice; prevents stale session
      # artefacts (lock files, sockets, GNOME state, build remnants) from
      # persisting across boots on persistent installs.
      # lib.mkDefault (priority 1000) allows any host file (priority 100) or
      # role module to override — e.g. a Nix build server needing disk-backed
      # /tmp for very large Nix derivations can set:
      #   boot.tmp.useTmpfs = false;
      # tmpfsSize is explicitly set to document the inherited default value.
      # A 50% cap is appropriate: ZRAM provides additional compressed overflow
      # beyond physical RAM, so effective capacity exceeds the nominal 50%.
      boot.tmp.useTmpfs  = lib.mkDefault true;
      boot.tmp.tmpfsSize = lib.mkDefault "50%";
```

#### Change 2 — `modules/impermanence.nix`

Remove the now-redundant `cleanOnBoot` setting (lines 140–143) and update the
comment. The stateless role already has `/` as tmpfs (so `/tmp` is ephemeral),
AND will now also have `/tmp` as a dedicated tmpfs from `system.nix`.

**Remove** (lines 139–143):

```nix
    # ── Clean /tmp on boot ──────────────────────────────────────────────────
    # Belt-and-suspenders: / is already a fresh tmpfs on each boot, but
    # setting cleanOnBoot makes the ephemeral intent explicit.
    boot.tmp.cleanOnBoot = true;
```

**No replacement text needed.** The behavior is fully covered by `system.nix`'s
`useTmpfs = lib.mkDefault true`.

---

## 5. Role-by-Role Impact Analysis

### 5.1 Desktop (`configuration-desktop.nix`)

- Imports `system.nix` → gains `boot.tmp.useTmpfs = true`.
- `/tmp` becomes a 50%-of-RAM tmpfs.
- **Benefit:** GNOME session files, build artefacts, and lock files no longer
  accumulate across reboots.
- **Risk:** Nix builds that write large intermediate outputs to `/tmp` could
  fail with OOM if the tmpfs fills. Workaround: override
  `boot.tmp.useTmpfs = false` in the host file or increase `tmpfsSize`.
- **Net:** Safe. Desktop machines typically have ≥8 GiB RAM. 50% = ≥4 GiB for
  `/tmp`, ample for typical desktop Nix builds (which write to
  `/nix/var/nix/builds`, not `/tmp`, by default).

### 5.2 HTPC (`configuration-htpc.nix`)

- Imports `system.nix` → gains `boot.tmp.useTmpfs = true`.
- Identical analysis to desktop. HTPC machines do not run large Nix builds.
- **Net:** Safe.

### 5.3 Server (`configuration-server.nix`)

- Imports `system.nix` → gains `boot.tmp.useTmpfs = true`.
- Server role also imports `zfs-server.nix` — ZFS and tmpfs are fully
  independent; no interaction with `/tmp`.
- Server machines typically have ≥16 GiB RAM. 50% = ≥8 GiB for `/tmp`.
- **Risk:** If the server runs heavy Nix rebuilds locally, `/tmp` may fill.
  Override per-host with `boot.tmp.useTmpfs = false` if needed.
- **Net:** Safe for standard server workloads.

### 5.4 Headless-Server (`configuration-headless-server.nix`)

- Imports `system.nix` → gains `boot.tmp.useTmpfs = true`.
- Headless servers often have constrained RAM (4–8 GiB in VMs or SBCs).
  On 4 GiB RAM, `tmpfsSize = "50%"` → 2 GiB for `/tmp`.
- **Risk:** Low (headless servers don't run large Nix builds). Mitigated by
  `lib.mkDefault` which allows host-level override.
- **Net:** Safe. `lib.mkDefault` ensures host files can override if needed.

### 5.5 Stateless (`configuration-stateless.nix` + `modules/impermanence.nix`)

- Imports `system.nix` → `useTmpfs = lib.mkDefault true`.
- Imports `impermanence.nix` → `/` is already a tmpfs (25%, `size=25%`).
- **No conflict:** `useTmpfs = true` mounts a NEW tmpfs overlay on `/tmp` (a
  subdirectory of the root tmpfs). The `/tmp` tmpfs (50%) is independent of
  the root tmpfs (25%). Linux tmpfs mounts are per-mount, not cumulative in
  physical allocation — pages are only allocated when written.
- The `cleanOnBoot = true` line in `impermanence.nix` **must be removed** (see
  Change 2) as it is entirely redundant.
- **Net:** Safe. Stateless role behavior is unchanged (still ephemeral `/tmp`)
  but `/tmp` now gets its own dedicated 50%-of-RAM allocation instead of
  sharing the root tmpfs 25%.

### 5.6 VM variants (`hosts/*-vm.nix`)

VM guest hosts have `vexos.swap.enable = false` set by `modules/gpu/vm.nix`.
`useTmpfs = true` is unrelated to swap — `/tmp` tmpfs uses RAM (backed by ZRAM
when full), not the swap file. No conflict.

---

## 6. `impermanence.nix` — Final Decision

**Yes, `boot.tmp.cleanOnBoot = true` must be removed from `modules/impermanence.nix`.**

Reasoning:
1. The comment already acknowledges it is "belt-and-suspenders" (i.e., redundant).
2. After this change, `useTmpfs = true` is set in `system.nix` for all roles
   including stateless. `/tmp` is a fresh tmpfs on every boot; there is nothing to
   clean.
3. The `cleanOnBoot` flag would trigger a no-op systemd-tmpfiles rule at every
   boot. While harmless, it is misleading — it implies manual cleaning is needed
   when it is not.
4. Removing it keeps `impermanence.nix` focused on impermanence logic; `/tmp`
   policy belongs in `system.nix`.

---

## 7. Risks and Mitigations

| Risk | Severity | Probability | Mitigation |
|------|----------|-------------|------------|
| Large Nix build fills `/tmp` (50%), OOM or ENOSPC | Medium | Low (Nix builds use `/nix/var/nix/builds` by default, not `/tmp`) | `lib.mkDefault` allows per-host `boot.tmp.useTmpfs = false` override |
| Headless server with 4 GiB RAM: 50% = 2 GiB `/tmp` | Low | Low (headless servers rarely fill `/tmp`) | Override `boot.tmp.tmpfsSize = "25%"` or disable `useTmpfs` per-host |
| Stateless role: stacking two tmpfs mounts | Low | Very Low | Linux handles overlaid tmpfs mounts correctly; independent allocations |
| `cleanOnBoot` removal breaks stateless | None | None | `cleanOnBoot` was always redundant; removing it has no behavioral change |
| `lib.mkDefault` priority conflict | None | None | `lib.mkDefault` is priority 1000; host files use priority 100 (plain assignments), ensuring host always wins |

---

## 8. Implementation Steps

1. **Edit `modules/system.nix`**:
   - Insert the `boot.tmp.useTmpfs` and `boot.tmp.tmpfsSize` block inside the
     unconditional config block, after the `zramSwap` section.
   - Exact Nix code: see §4.2 Change 1.

2. **Edit `modules/impermanence.nix`**:
   - Remove lines 139–143 (the `cleanOnBoot` comment block and the option
     assignment).
   - Exact removal: see §4.2 Change 2.

3. **Validation**:
   - Run `nix flake check` to confirm no evaluation errors.
   - Run `sudo nixos-rebuild dry-build --flake .#vexos-desktop-amd` to verify the
     desktop/AMD closure builds cleanly.
   - Run `sudo nixos-rebuild dry-build --flake .#vexos-stateless-amd` to verify the
     stateless closure builds cleanly (confirms no conflict between root tmpfs and
     `/tmp` tmpfs).
   - Run `sudo nixos-rebuild dry-build --flake .#vexos-headless-server-amd` to
     verify the headless-server closure builds cleanly.

---

## 9. Sources

1. **nixpkgs source — `nixos/modules/system/boot/tmp.nix` (nixos-25.05)**
   `https://github.com/NixOS/nixpkgs/blob/nixos-25.05/nixos/modules/system/boot/tmp.nix`
   Defines all `boot.tmp.*` options, their types, defaults, and systemd implementation.
   Confirms: `useTmpfs` and `cleanOnBoot` are independent; both emit to different
   systemd subsystems; `tmpfsSize` default is `"50%"`.

2. **NixOS Options Search — `boot.tmp` (channel 25.11)**
   `https://search.nixos.org/options?channel=25.11&query=boot.tmp`
   Lists 9 `boot.tmp.*` options; confirms `useTmpfs` and `cleanOnBoot` exist as
   separate options with `false` defaults.

3. **NixOS Wiki — Impermanence**
   `https://wiki.nixos.org/wiki/Impermanence`
   Documents the canonical pattern of using `fileSystems."/" = { fsType = "tmpfs"; }`.
   Confirms that `/tmp` on a tmpfs root is inherently ephemeral.

4. **NixOS Discourse — "How do you optimize your /tmp?"** (Sep 2024)
   `https://discourse.nixos.org/t/how-do-you-optimize-your-tmp`
   Community consensus: `useTmpfs = true` is the preferred approach for clean
   `/tmp` semantics; "50%" is the standard community-used value.

5. **NixOS Discourse — "What do you change from the default?"** (Apr 2026)
   `https://discourse.nixos.org/search?q=boot.tmp.useTmpfs`
   Multiple community configurations use `boot.tmp.useTmpfs = true;
   boot.tmp.tmpfsSize = "50%";` as a standard pair.

6. **NixOS Discourse — "No space left on device error when rebuilding"** (Mar 2025)
   `https://discourse.nixos.org/search?q=boot.tmp.useTmpfs`
   Confirms: NixOS builds write to `/nix/var/nix/builds` by default, not `/tmp`,
   mitigating the risk of large builds filling a 50% tmpfs.

7. **NixOS Discourse — "Upgrading to NixOS 25.05 broke my headless setup"** (Oct 2025)
   `https://discourse.nixos.org/search?q=boot.tmp.useTmpfs`
   Real-world headless-server config uses `boot.tmp.useTmpfs = true` — no issues
   reported with the standard 50% size on headless machines.

8. **nixpkgs rename shims** (in `tmp.nix`):
   ```nix
   (lib.mkRenamedOptionModule [ "boot" "tmpOnTmpfs" ] [ "boot" "tmp" "useTmpfs" ])
   ```
   Confirms `useTmpfs` is the canonical modern name, stable since NixOS 22.11,
   and is the correct option to set in NixOS 25.05+.

---

## 10. Summary

| Item | Decision |
|------|----------|
| Add `boot.tmp.useTmpfs = lib.mkDefault true` to `system.nix` | **YES** |
| Add `boot.tmp.tmpfsSize = lib.mkDefault "50%"` to `system.nix` | **YES** (documents nixpkgs default explicitly) |
| Remove `boot.tmp.cleanOnBoot = true` from `impermanence.nix` | **YES** (redundant; covered by `useTmpfs`) |
| Create a new module file | **NO** (change goes in existing `system.nix`) |
| Change any `configuration-*.nix` file | **NO** (`lib.mkDefault` in `system.nix` propagates automatically) |
| Change any `hosts/` file | **NO** |
| Change `flake.nix` | **NO** |

**Files to modify:** 2 files only.
- `modules/system.nix`
- `modules/impermanence.nix`
