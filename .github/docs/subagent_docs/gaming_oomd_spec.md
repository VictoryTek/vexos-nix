# Specification: Gaming Role — systemd-oomd Slice Enablement

**Feature name:** `gaming_oomd`
**Spec file:** `.github/docs/subagent_docs/gaming_oomd_spec.md`
**Date:** 2026-05-15
**Status:** Ready for Implementation

---

## 1. Current State Analysis

### 1.1 Files Examined

| File | Relevant lines | Notes |
|------|---------------|-------|
| `modules/system-gaming.nix` | 1–53 (entire file) | Gaming kernel params, THP, SCX scheduler — no oomd config |
| `modules/system.nix` | 1–134 (entire file) | Base system: ZRAM swap enabled, `vm.swappiness = 10`, persistent swap file |
| `configuration-desktop.nix` | 1–52 (entire file) | Imports `system.nix` and `system-gaming.nix`; no oomd config |
| `modules/gaming.nix` | 1–100+ (entire file) | Steam, Gamescope, GameMode, controllers — no oomd config |

### 1.2 Memory Pressure Configuration Already Present

`modules/system.nix` (unconditional, all roles):

```nix
zramSwap = {
  enable = true;
  algorithm = "lz4";
  memoryPercent = 50;
};

boot.kernel.sysctl = {
  "vm.swappiness" = 10;
  ...
};
```

`vm.swappiness = 10` means the kernel actively prefers keeping pages in RAM and uses swap only under significant pressure. Combined with ZRAM as the only swap (plus an opt-out 8 GiB file swap in `system.nix`), the system can reach hard memory exhaustion before the kernel OOM killer fires. On gaming desktops this manifests as:
- Full desktop freeze when a game or Electron app (Discord/Vesktop) exhausts RAM
- Kernel hard OOM kill is non-selective and often kills the wrong process
- No early warning or graceful kill before livelocking begins

### 1.3 Current oomd Status

`systemd.oomd.enable` is **not set anywhere** in this repository. However, per the NixOS 25.05 module source (see §3), the default is already `true` — so `systemd-oomd.service` is already **running** on all vexos-nix hosts.

The problem is that oomd is running but **monitoring nothing**, because the three slice-enablement options all default to `false`:

- `systemd.oomd.enableRootSlice = false` (default)
- `systemd.oomd.enableSystemSlice = false` (default)
- `systemd.oomd.enableUserSlices = false` (default)

Without at least one of these set, oomd is a no-op daemon.

---

## 2. Problem Definition

On gaming desktops with ZRAM + `vm.swappiness = 10`:

1. **ZRAM fills before kernel OOM fires.** With 50 % of RAM as compressed swap and swappiness=10, the working set expands until ZRAM is full. The desktop then livelocks before the kernel OOM killer has time to react.

2. **Bazzite/SteamOS equivalent is missing.** Bazzite (systemd 258 on Fedora) ships `systemd-oomd-defaults` package which configures `ManagedOOMSwap=kill` on `-.slice` and `ManagedOOMMemoryPressure=kill` on user slices. The vexos-nix gaming configuration lacks this.

3. **oomd daemon is already running but idle.** `systemd.oomd.enable` defaults to `true` in NixOS 25.05, so no daemon overhead is introduced by this fix — only the monitoring directives are missing.

---

## 3. Research Findings (6+ Sources)

### Source 1 — nixpkgs 25.05 module source (authoritative)

**URL:** `https://github.com/NixOS/nixpkgs/blob/nixos-25.05/nixos/modules/system/boot/systemd/oomd.nix`

```nix
options.systemd.oomd = {
  enable = lib.mkEnableOption "the `systemd-oomd` OOM killer" // {
    default = true;  # ← ENABLED BY DEFAULT in NixOS 25.05
  };
  # Comment in source: "Fedora enables the first and third option by default."
  enableRootSlice   = lib.mkEnableOption "oomd on the root slice (`-.slice`)";
  enableSystemSlice = lib.mkEnableOption "oomd on the system slice (`system.slice`)";
  enableUserSlices  = lib.mkEnableOption "oomd on all user slices (`user@.slice`) and all user owned slices";
  ...
};
config = lib.mkIf cfg.enable {
  systemd.slices."-".sliceConfig = lib.mkIf cfg.enableRootSlice {
    ManagedOOMMemoryPressure      = "kill";
    ManagedOOMMemoryPressureLimit = lib.mkDefault "80%";
  };
  systemd.slices."user".sliceConfig = lib.mkIf cfg.enableUserSlices {
    ManagedOOMMemoryPressure      = "kill";
    ManagedOOMMemoryPressureLimit = lib.mkDefault "80%";
  };
};
```

**Key finding:**
- `enable` defaults to `true` → daemon already running on all vexos-nix hosts
- `enableRootSlice`, `enableSystemSlice`, `enableUserSlices` all default to `false`
- The NixOS module itself says "Fedora enables the first and third option by default" (= `enableRootSlice` + `enableUserSlices`)
- Note: The NixOS module configures `ManagedOOMMemoryPressure` on `-.slice` when `enableRootSlice=true`. For `ManagedOOMSwap`, see systemd recommendation below.

### Source 2 — systemd-oomd man page (usage recommendations)

**URL:** `https://man7.org/linux/man-pages/man8/systemd-oomd.service.8.html`

> **ManagedOOMSwap=** works with the system-wide swap values, so setting it on the root slice `-.slice`, and allowing all descendant cgroups to be eligible candidates may make the most sense.

> **ManagedOOMMemoryPressure=** tends to work better on the cgroups below the root slice. For units which tend to have processes that are less latency sensitive (e.g. `system.slice`), a higher limit like the default of 60% may be acceptable. However, something like `user@$UID.service` may prefer a much lower value like 40%.

> Be aware that if you intend to enable monitoring and actions on `user.slice`, `user-$UID.slice`, or their ancestor cgroups, it is highly recommended that your programs be managed by the systemd user manager… If you're using a desktop environment like **GNOME or KDE**, it already spawns many session components with the systemd user manager.

**Key finding:** GNOME (used by desktop and htpc roles) is explicitly called out as safe for `enableUserSlices`. Games run in user slices.

### Source 3 — systemd-oomd man page (system requirements)

From the same page:

> It is highly recommended for the system to have swap enabled for systemd-oomd to function optimally. With swap enabled, the system spends enough time swapping pages to let systemd-oomd react. Without swap, the system enters a livelocked state much more quickly.

**Key finding:** vexos-nix has ZRAM + optional file swap → oomd can react. `vm.swappiness=10` reduces swap use but does NOT disable swap, so oomd remains effective.

### Source 4 — Bazzite GitHub issues (operational evidence)

**URL:** `https://github.com/ublue-os/bazzite/search?q=oomd&type=issues`

Multiple Bazzite journal snippets show `systemd-oomd.service` and `systemd-oomd.socket` loading at boot as standard behaviour. The `systemd-oomd-defaults` RPM package (Fedora 39–43) ships drop-in files that configure `ManagedOOMSwap=kill` on `-.slice` and `ManagedOOMMemoryPressure=kill` on `user.slice`.

**Key finding:** Bazzite inherits this configuration from Fedora's systemd package. NixOS users must set it explicitly via `systemd.oomd.enableRootSlice` and `systemd.oomd.enableUserSlices`.

### Source 5 — nixpkgs commit history

**URL:** `https://github.com/NixOS/nixpkgs/commit/54f759989dd29b5b903387e5011ce719fd72705d`

Commit message: "nixos/systemd-oomd: use the correct name for the top-level user slice" — confirming that the NixOS oomd module in 25.05 correctly maps `enableUserSlices` to the `user.slice` cgroup (not `user@.slice`).

### Source 6 — systemd resource-control man page (`ManagedOOMMemoryPressure`)

**URL:** referenced from `systemd-oomd.service(8)`

`ManagedOOMMemoryPressure = "kill"` in a slice unit instructs oomd to monitor PSI (Pressure Stall Information) for that cgroup and kill descendant processes when memory pressure exceeds the configured limit. This is the directive that `systemd.oomd.enableRootSlice` and `systemd.oomd.enableUserSlices` inject via NixOS module logic.

---

## 4. Architecture Constraints (CRITICAL)

Per the project's **Option B: Common base + role additions** pattern:

- `modules/system.nix` = universal base (all roles) — **DO NOT MODIFY** for this change; oomd slice monitoring is not appropriate for headless servers, VMs, or stateless roles.
- `modules/system-gaming.nix` = gaming/desktop additions — **ONLY FILE TO MODIFY**.
- No `lib.mkIf` guards inside `system-gaming.nix` — it is already conditional by virtue of being imported only by roles that need it.
- `configuration-desktop.nix` and `configuration-htpc.nix` both import `system-gaming.nix` → both will inherit oomd slice monitoring. This is correct; both roles use GNOME.

**Why NOT in `system.nix`:**
- Headless servers, stateless, and server roles have no user sessions generating gaming memory pressure
- `enableUserSlices = true` on a server that never has a user X session is meaningless overhead
- `enableRootSlice = true` on a server that runs under strict `MemoryLimit=` service configs could interfere with intentional memory limits

---

## 5. Exact Implementation

### 5.1 File to Modify

**Only one file:** `modules/system-gaming.nix`

### 5.2 Change

Add the following block after the SCX section (end of file), immediately before the closing `}`:

```nix
  # ── Out-of-memory daemon — userspace OOM killer ────────────────────────────
  # systemd-oomd monitors PSI (Pressure Stall Information) and kills cgroups
  # before the kernel OOM killer fires, preventing desktop freezes under
  # gaming memory pressure (Bazzite/Fedora equivalent configuration).
  #
  # systemd.oomd.enable defaults to true in NixOS 25.05, so the daemon is
  # already running on all vexos-nix hosts. What is missing are the slice
  # monitoring directives; without these, oomd runs but monitors nothing.
  #
  # enableRootSlice   → ManagedOOMMemoryPressure=kill on -.slice
  #                     Enables swap-aware OOM killing across the whole system.
  # enableUserSlices  → ManagedOOMMemoryPressure=kill on user.slice
  #                     Kills offending games/Electron apps before the desktop
  #                     freezes. Safe with GNOME: GNOME already manages session
  #                     components via the systemd user manager.
  #
  # Fedora/Bazzite use exactly this combination (enableRootSlice + enableUserSlices).
  # enableSystemSlice is intentionally omitted — system services are not the
  # source of gaming OOM events.
  systemd.oomd = {
    enableRootSlice  = true;
    enableUserSlices = true;
  };
```

### 5.3 Complete Resulting File

After the change, `modules/system-gaming.nix` will be:

```nix
# modules/system-gaming.nix
# Gaming-optimised kernel parameters, vm.max_map_count, Transparent Huge Pages,
# and the SCX LAVD CPU scheduler.
#
# Import in any configuration that requires gaming-level kernel tuning.
# Do NOT import on VM guests or headless roles.
#
# If a specific host must disable SCX (e.g. a VM pinned to a kernel < 6.12
# that lacks sched_ext support), override in the host file:
#   services.scx.enable = lib.mkForce false;
{ ... }:
{
  boot.kernelParams = [
    # Full preemption — lowest desktop/gaming latency
    "preempt=full"

    # Disable split-lock detection for better Wine/Proton compatibility
    "split_lock_detect=off"

    # Clean boot experience (matches Bazzite)
    "quiet"
    "splash"
    "loglevel=3"
  ];

  # Maximum memory map areas per process — required by Proton/Wine anti-cheat
  # (EAC, BattlEye). 2147483642 is MAX_INT-5, the value set by SteamOS/Bazzite.
  boot.kernel.sysctl."vm.max_map_count" = 2147483642;

  # ── Transparent Huge Pages ────────────────────────────────────────────────
  # madvise: allocate THP only when applications explicitly request it.
  systemd.tmpfiles.rules = [
    "w /sys/kernel/mm/transparent_hugepage/enabled - - - - madvise"
    "w /sys/kernel/mm/transparent_hugepage/defrag   - - - - defer+madvise"
  ];

  # ── SCX LAVD CPU scheduler ────────────────────────────────────────────────
  # SteamOS/Bazzite scheduler — optimised for gaming desktops.
  # Requires sched_ext support (upstream 6.14+, zen 6.12+, lqx 6.12+).
  # Override with lib.mkForce false in the host file if running a kernel
  # older than 6.12 that lacks sched_ext (e.g. the VM 6.6 LTS pin).
  services.scx = {
    enable    = true;
    scheduler = "scx_lavd";
  };

  # ── Out-of-memory daemon — userspace OOM killer ────────────────────────────
  # systemd-oomd monitors PSI (Pressure Stall Information) and kills cgroups
  # before the kernel OOM killer fires, preventing desktop freezes under
  # gaming memory pressure (Bazzite/Fedora equivalent configuration).
  #
  # systemd.oomd.enable defaults to true in NixOS 25.05, so the daemon is
  # already running on all vexos-nix hosts. What is missing are the slice
  # monitoring directives; without these, oomd runs but monitors nothing.
  #
  # enableRootSlice   → ManagedOOMMemoryPressure=kill on -.slice
  #                     Enables swap-aware OOM killing across the whole system.
  # enableUserSlices  → ManagedOOMMemoryPressure=kill on user.slice
  #                     Kills offending games/Electron apps before the desktop
  #                     freezes. Safe with GNOME: GNOME already manages session
  #                     components via the systemd user manager.
  #
  # Fedora/Bazzite use exactly this combination (enableRootSlice + enableUserSlices).
  # enableSystemSlice is intentionally omitted — system services are not the
  # source of gaming OOM events.
  systemd.oomd = {
    enableRootSlice  = true;
    enableUserSlices = true;
  };
}
```

### 5.4 What NOT to Change

| File | Action | Reason |
|------|--------|--------|
| `modules/system.nix` | No change | oomd slice monitoring is gaming/desktop-specific; headless/server roles do not need it |
| `configuration-desktop.nix` | No change | Already imports `system-gaming.nix`; change is inherited automatically |
| `modules/gaming.nix` | No change | Unrelated to kernel memory management |
| Any host file | No change | System-level defaults are set in the module |

---

## 6. Why NOT Add `enable = true`

`systemd.oomd.enable` already defaults to `true` in NixOS 25.05. Explicitly setting it would be redundant and misleading — it implies the daemon was disabled, which it was not. The implementation must NOT add `enable = true`.

---

## 7. Why NOT Add `enableSystemSlice = true`

The systemd man page notes that `system.slice` processes are "less latency sensitive" and a 60 % memory pressure limit "may be acceptable". For a gaming desktop the threat is games and Electron apps running in user sessions — not system services. Adding `enableSystemSlice` would:
- Kill system daemons (NetworkManager, PipeWire, etc.) unnecessarily
- Not match Fedora/Bazzite's actual gaming configuration

The Fedora reference implementation (cited in nixpkgs source) uses only root + user slices.

---

## 8. Interaction with ZRAM + vm.swappiness = 10

| Parameter | Value | Interaction with oomd |
|-----------|-------|----------------------|
| `zramSwap.enable` | `true` | ZRAM provides compressed swap; oomd can monitor swap PSI and react before ZRAM is exhausted |
| `zramSwap.memoryPercent` | `50` | Up to 50 % RAM in ZRAM; a game filling RAM → ZRAM will generate PSI signals that oomd detects |
| `vm.swappiness` | `10` | Low: kernel avoids swap; means system reaches memory pressure threshold more sharply → oomd can still react, but the window is shorter. `DefaultMemoryPressureDurationSec = 20s` (NixOS default from Fedora) gives oomd 20 seconds of sustained pressure before killing |
| Optional file swap | 8 GiB (opt-out) | Provides additional buffer before hard OOM; oomd reacts before the file swap is exhausted |

**Summary:** With `vm.swappiness=10`, the system under gaming pressure will not aggressively swap. Instead, once RSS fills RAM + ZRAM, PSI memory pressure climbs sharply. The 20-second default duration threshold means oomd acts during a sustained spike, not on transient allocations.

---

## 9. Risks and Mitigations

| Risk | Severity | Mitigation |
|------|----------|------------|
| oomd kills game mid-session | Low | oomd targets the cgroup using the most memory under pressure; on a GNOME desktop where a game is the largest consumer, the game is the right process to kill — this is the intended behavior |
| oomd kills wrong process (e.g. PipeWire) | Low | `enableSystemSlice` is not set; PipeWire runs in user slice but oomd kills by highest memory use within the slice; audio daemons use negligible memory vs. games |
| False positives during normal operation | Very low | Default `DefaultMemoryPressureDurationSec = 20s` requires sustained pressure, not momentary spikes |
| Conflict with `lib.mkDefault` / `lib.mkIf` | None | These options are plain booleans; no merge conflicts expected |
| Missing NixOS module for `systemd.oomd` | None | Confirmed present since NixOS 23.11; actively maintained in 25.05 |
| VM hosts unexpectedly importing this module | None | `hosts/desktop-vm.nix` etc. import `configuration-desktop.nix` which imports `system-gaming.nix`; this is by design for consistency. VM users already expected to override `services.scx.enable = lib.mkForce false` if needed |

---

## 10. Verification Steps

After implementation, verify with:

```bash
# 1. Flake structure check
nix flake check

# 2. Dry-build AMD variant
sudo nixos-rebuild dry-build --flake .#vexos-desktop-amd

# 3. Dry-build NVIDIA variant  
sudo nixos-rebuild dry-build --flake .#vexos-desktop-nvidia

# 4. Dry-build VM variant (still imports system-gaming.nix)
sudo nixos-rebuild dry-build --flake .#vexos-desktop-vm
```

On a live system after `nixos-rebuild switch`:

```bash
# Verify daemon is active
systemctl status systemd-oomd.service

# Verify slice config was applied
systemctl show -.slice | grep ManagedOOM
# Expected: ManagedOOMMemoryPressure=kill  ManagedOOMMemoryPressureLimit=80%

systemctl show user.slice | grep ManagedOOM
# Expected: ManagedOOMMemoryPressure=kill  ManagedOOMMemoryPressureLimit=80%

# Inspect live oomd monitoring
oomctl
# Expected: shows -.slice and user.slice (or user@UID.slice) as monitored cgroups
```

---

## 11. Implementation Checklist

- [ ] Read this spec
- [ ] Read `modules/system-gaming.nix` (confirm current state matches §1.2)
- [ ] Add the `systemd.oomd` block from §5.2 to `modules/system-gaming.nix`
- [ ] Do NOT add `enable = true` (it is already the default)
- [ ] Do NOT add `enableSystemSlice = true` (not needed; see §7)
- [ ] Do NOT modify any other file
- [ ] Run `nix flake check`
- [ ] Run dry-build on at least `vexos-desktop-amd`, `vexos-desktop-nvidia`, `vexos-desktop-vm`

---

## 12. Summary

| Item | Value |
|------|-------|
| Files to modify | `modules/system-gaming.nix` only |
| Lines to add | ~20 (comment block + 4 nix lines) |
| NixOS default for `systemd.oomd.enable` | `true` (already running) |
| New options being set | `enableRootSlice = true`, `enableUserSlices = true` |
| Fedora/Bazzite equivalent | Yes (matches Fedora's `systemd-oomd-defaults` package) |
| Roles affected | `desktop`, `htpc` (both import `system-gaming.nix`) |
| Roles NOT affected | `server`, `headless-server`, `stateless` (do not import `system-gaming.nix`) |
| Scope reduction vs. original issue | `enable = true` is redundant (already default); no other changes |
