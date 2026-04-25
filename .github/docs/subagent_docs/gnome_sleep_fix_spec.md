# Specification: Disable Sleep/Hibernate + Fix Post-Resume Wallpaper Corruption

**Feature name**: `gnome_sleep_fix`  
**Date**: 2026-04-25  
**Status**: DRAFT — Pending Implementation

---

## 1. Current State Analysis

### 1.1 Sleep/Power Configuration (what exists today)

| File | Relevant content |
|------|-----------------|
| `modules/system.nix` | `powerManagement.cpuFreqGovernor = "schedutil"`. ZRAM swap enabled. **No sleep-disable settings.** |
| `modules/gnome.nix` | `lock-enabled = false` in screensaver dconf. Caffeine extension installed/enabled. **No `org/gnome/settings-daemon/plugins/power` keys set.** |
| `home/gnome-common.nix` | Home-manager dconf: `idle-delay = 300` (5 min), `lock-enabled = false`. **No power plugin dconf keys.** |
| `modules/gpu/nvidia.nix` | `hardware.nvidia.powerManagement.enable = false` (comment: "set true if suspend/resume causes GPU lockups"). |
| All other modules | No `services.logind.extraConfig`, no `systemd.sleep.extraConfig`, no `systemd.suppressedSystemUnits`. |

### 1.2 What GNOME defaults to without configuration

- `org/gnome/settings-daemon/plugins/power sleep-inactive-ac-type` → `"suspend"` (default)
- `org/gnome/settings-daemon/plugins/power sleep-inactive-ac-timeout` → `1200` seconds (20 minutes on AC)
- `services.logind` → `IdleAction=suspend` by default in systemd
- `systemd.sleep` → all sleep variants allowed by default

**Result**: The system currently suspends to RAM after 20 minutes of inactivity on AC power. Nothing in the configuration prevents this.

### 1.3 Post-Resume Wallpaper/Rendering Corruption (root cause)

On Wayland (mutter compositor), after resume from `suspend.target`:

1. **mutter** must re-initialize the GPU framebuffer chain. On AMD and NVIDIA, this sometimes fails to trigger a full composite refresh of the background actor.
2. **GNOME Shell's background manager** (`Main.layoutManager._backgroundGroup`) holds a reference to the previously-rendered texture. On resume the texture object is still valid but the GPU-side backing store may have been invalidated, resulting in a black rectangle.
3. **GNOME Shell extensions** and the panel text are drawn on a separate scenegraph layer. If the Clutter/mutter rendering pipeline stalls or misses the first post-resume frame, these elements render corrupted (misaligned, partially drawn, or absent) until the next scheduled repaint event.
4. **NVIDIA-specific**: `hardware.nvidia.powerManagement.enable = false` means the NVIDIA ACPI hooks (`/lib/systemd/system-sleep/nvidia`) are **not** invoked. These hooks (nvidia-sleep.sh) are responsible for saving and restoring the GPU context across suspend/resume. Without them, the display engine can be in an undefined state on wake, causing exactly the "jumbled/black" rendering symptom.
5. **AMD-specific**: amdgpu's `amdgpu_gfx_off` power gating and display engine re-initialization are generally handled in-kernel, but edge cases exist when GNOME's compositor doesn't receive the `wakeup` udev event in time to trigger a repaint.

**Root fix**: If the system never sleeps, there is no post-resume corruption to fix. Disabling sleep entirely is the primary and correct solution. A belt-and-suspenders post-resume reload service is specified below in case sleep is ever accidentally triggered.

---

## 2. Problem Definition

### Problem 1 — Wallpaper goes black; text jumbled or missing after resume
- **Trigger**: System wakes from `suspend.target` (S3 RAM suspend, automatically activated by GNOME power settings after idle timeout).
- **Symptom**: GNOME desktop background is black; GNOME Shell UI text and extension overlays are garbled.
- **Cause**: mutter/GNOME Shell compositor does not fully reinitialize the rendering pipeline after GPU wake. NVIDIA worsened by absence of NVIDIA ACPI sleep hooks.

### Problem 2 — User wants sleep/hibernate permanently disabled on desktop and HTPC
- **Scope**: `configuration-desktop.nix` and `configuration-htpc.nix` roles only.
- **Not in scope**: server, headless-server, stateless roles may legitimately sleep.

---

## 3. Proposed Solution Architecture

### 3.1 Single new module: `modules/system-nosleep.nix`

This module is the **role-specific addition** file per the Module Architecture Pattern:

- **Universal base** (`modules/system.nix`): left untouched.
- **Role-specific addition** (`modules/system-nosleep.nix`): imported only by the two display roles that must never sleep.

Placing sleep-disable settings in `system.nix` would incorrectly apply them to servers. Placing them in `gnome.nix` would mix power management concerns into the GNOME module. A dedicated `system-nosleep.nix` is the correct separation.

### 3.2 Four-layer defense-in-depth sleep block

Sleep must be blocked at every layer because any single layer can be bypassed:

| Layer | Mechanism | Why needed |
|-------|-----------|------------|
| L1 — GNOME power plugin | `org/gnome/settings-daemon/plugins/power` dconf keys | Prevents GNOME from sending D-Bus Suspend() to logind |
| L2 — systemd-logind | `services.logind.extraConfig` IdleAction + HandleSuspendKey | Prevents logind from independently suspending on idle or key press |
| L3 — systemd-sleep.conf | `environment.etc."systemd/sleep.conf.d/no-sleep.conf"` | Tells systemd-sleep to refuse all suspend/hibernate calls |
| L4 — masked targets | `systemd.suppressedSystemUnits` | Hard masks sleep.target, suspend.target, hibernate.target, hybrid-sleep.target, suspend-then-hibernate.target |

### 3.3 Post-resume belt-and-suspenders (GNOME background reload)

A `systemd.services` entry that runs **after** `suspend.target` as a final fallback. Because `suspend.target` is masked (Layer 4), this service will only execute in the unlikely event a suspend gets through the first three layers. It forces a GNOME dconf toggle to trigger a wallpaper repaint.

### 3.4 Files to modify

| File | Change |
|------|--------|
| `modules/system-nosleep.nix` | **CREATE** — the full nosleep module (see §4) |
| `configuration-desktop.nix` | Add `./modules/system-nosleep.nix` to imports |
| `configuration-htpc.nix` | Add `./modules/system-nosleep.nix` to imports |

No other files are modified. Specifically:
- `modules/system.nix` — **NOT modified** (universal base)
- `modules/gnome.nix` — **NOT modified** (universal GNOME base)
- `modules/gpu/nvidia.nix` — **NOT modified** (see §5 risk note on NVIDIA power management)
- `home/gnome-common.nix` — **NOT modified** (idle-delay=300 screensaver is acceptable; sleep is blocked at systemd level)

---

## 4. Implementation Steps

### Step 1 — Create `modules/system-nosleep.nix`

```nix
# modules/system-nosleep.nix
# Permanently disable sleep, suspend, and hibernation.
# Import in configuration-desktop.nix and configuration-htpc.nix.
# Do NOT import in server, headless-server, or stateless roles.
{ pkgs, lib, config, ... }:
{
  # ── Layer 4: mask all systemd sleep targets ───────────────────────────────
  # Creates /etc/systemd/system/<unit> -> /dev/null symlinks.
  # Prevents systemctl suspend/hibernate from ever activating.
  systemd.suppressedSystemUnits = [
    "sleep.target"
    "suspend.target"
    "hibernate.target"
    "hybrid-sleep.target"
    "suspend-then-hibernate.target"
  ];

  # ── Layer 3: systemd-sleep.conf ──────────────────────────────────────────
  # Placed in a drop-in directory so it doesn't replace /etc/systemd/sleep.conf.
  environment.etc."systemd/sleep.conf.d/no-sleep.conf".text = ''
    [Sleep]
    AllowSuspend=no
    AllowHibernation=no
    AllowHybridSleep=no
    AllowSuspendThenHibernate=no
  '';

  # ── Layer 2: systemd-logind ──────────────────────────────────────────────
  # Prevents logind from initiating suspend on idle or on suspend/power key press.
  # HandleLidSwitch* included for completeness (harmless on desktops without a lid).
  services.logind.extraConfig = ''
    HandleSuspendKey=ignore
    HandleHibernateKey=ignore
    HandleLidSwitch=ignore
    HandleLidSwitchExternalPower=ignore
    HandleLidSwitchDocked=ignore
    IdleAction=ignore
    IdleActionSec=0
  '';

  # ── Layer 1: GNOME power settings ────────────────────────────────────────
  # Set in the system dconf profile so they apply at session start (before
  # home-manager activation), which is critical on autoLogin systems.
  # These keys are NOT set anywhere else in this project, so no conflict arises.
  programs.dconf.profiles.user.databases = lib.mkBefore [
    {
      settings = {
        "org/gnome/settings-daemon/plugins/power" = {
          # Never sleep on AC or battery power regardless of idle time.
          sleep-inactive-ac-type         = "nothing";
          sleep-inactive-battery-type    = "nothing";
          sleep-inactive-ac-timeout      = lib.gvariant.mkInt32 0;
          sleep-inactive-battery-timeout = lib.gvariant.mkInt32 0;
          # Power button: do nothing (avoids accidental suspend on bare button press).
          power-button-action            = "nothing";
        };
      };
    }
  ];

  # ── Belt-and-suspenders: post-resume GNOME background reload ─────────────
  # Executes after resume IF sleep somehow gets through layers 1–4.
  # Toggles the wallpaper URI (picture-options zoom → stretch → zoom) to force
  # mutter's background actor to invalidate and repaint its texture cache.
  # Runs as the primary user; uses the stable systemd user D-Bus socket path.
  systemd.services."gnome-background-reload" = {
    description = "Reload GNOME background after resume (wallpaper corruption workaround)";
    after  = [ "suspend.target" "hibernate.target" "hybrid-sleep.target" ];
    wantedBy = [ "suspend.target" "hibernate.target" "hybrid-sleep.target" ];
    serviceConfig = {
      Type = "oneshot";
      User = "nimda";
      Environment = [
        "DBUS_SESSION_BUS_ADDRESS=unix:path=/run/user/1000/bus"
        "HOME=/home/nimda"
      ];
      # Toggle picture-options to force a background repaint, then restore.
      ExecStart = pkgs.writeShellScript "gnome-bg-reload" ''
        ${pkgs.glib}/bin/gsettings set org.gnome.desktop.background picture-options stretch
        sleep 1
        ${pkgs.glib}/bin/gsettings set org.gnome.desktop.background picture-options zoom
      '';
    };
  };
}
```

### Step 2 — Add import to `configuration-desktop.nix`

In the `imports` list (after `./modules/system-gaming.nix`), add:

```nix
./modules/system-nosleep.nix
```

### Step 3 — Add import to `configuration-htpc.nix`

In the `imports` list (after `./modules/system.nix`), add:

```nix
./modules/system-nosleep.nix
```

---

## 5. Key Technical Notes

### 5.1 dconf profile list merging

`programs.dconf.profiles.user.databases` is a `types.listOf submodule` in the NixOS dconf module. Multiple NixOS modules can each contribute entries — NixOS concatenates all definitions. `lib.mkBefore` is used in `system-nosleep.nix` to ensure the power settings database entry appears **before** (higher priority than) the main database in `modules/gnome.nix`. Since `sleep-inactive-ac-type` is not currently set in any existing database, `lib.mkBefore` is a precautionary measure and does not create a conflict.

### 5.2 NVIDIA power management

`modules/gpu/nvidia.nix` currently sets `hardware.nvidia.powerManagement.enable = false`. A code comment warns this should be set to `true` if suspend/resume causes GPU lockups. The user IS experiencing GPU rendering corruption after wake. However:

- Since `system-nosleep.nix` masks all sleep targets, the system will no longer suspend.
- `hardware.nvidia.powerManagement.enable = true` activates `nvidia-sleep.sh` ACPI hooks. These hooks are only relevant during suspend/resume cycles.
- **With sleep disabled, the NVIDIA powerManagement flag is irrelevant for the reported problem.** No change to `gpu/nvidia.nix` is needed.
- If a future user re-enables sleep on an NVIDIA system, they should set `hardware.nvidia.powerManagement.enable = true` in their host config.

### 5.3 Why screensaver (idle-delay) is NOT changed

`home/gnome-common.nix` sets `idle-delay = 300` (5-minute screensaver). This is a home-manager user dconf setting and has higher priority than the system dconf added by `system-nosleep.nix`. The screensaver activating ≠ sleep activating. With Layer 1 (`sleep-inactive-ac-type = "nothing"`) set, GNOME will display the screensaver but will never transition from screensaver → sleep. This is the desired behaviour: screensaver for display longevity, no sleep for always-on operation.

### 5.4 Roles NOT affected

`configuration-server.nix`, `configuration-headless-server.nix`, and `configuration-stateless.nix` do **not** import `system-nosleep.nix`. Those roles retain the default systemd sleep behaviour and can be configured independently.

### 5.5 NixOS option: `systemd.suppressedSystemUnits`

This is a confirmed NixOS option (present in nixpkgs since NixOS 21.05, maintained through 25.11). It creates `/etc/systemd/system/<unit>` symlinks pointing to `/dev/null`, which is the canonical systemd way to mask a unit. Unlike `systemd.units.<name>.enable = false` (which only suppresses NixOS-generated units), `suppressedSystemUnits` works on units shipped with systemd itself.

### 5.6 sleep.conf drop-in directory

`environment.etc."systemd/sleep.conf.d/no-sleep.conf".text` writes to a drop-in subdirectory rather than `/etc/systemd/sleep.conf` directly. This avoids clobbering the base sleep.conf file and is the recommended pattern for NixOS configuration.

---

## 6. Risks and Mitigations

| Risk | Severity | Mitigation |
|------|----------|------------|
| User cannot suspend manually if they ever want to | Low | `system-nosleep.nix` is only imported in desktop/htpc configs; stateless is unaffected. User can remove the import to re-enable sleep. |
| `lib.mkBefore` on `programs.dconf.profiles.user.databases` conflicts with gnome.nix list | Low | These are additive list contributions. `lib.mkBefore` only affects ordering, not attribute values. Since the power plugin keys are not set in gnome.nix, no key collision can occur. |
| `ExecStart` script path (`/run/user/1000/bus`) assumes UID 1000 for user `nimda` | Low | This is a personal config; `nimda` is the only interactive user. UID 1000 is always assigned to the first created user on NixOS. |
| Belt-and-suspenders service references `pkgs.writeShellScript` inside a `systemd.services` attribute | Low | This is a valid NixOS pattern for inline scripts. The script package is added to the closure automatically. |
| `IdleActionSec=0` in logind.conf may interact unexpectedly with `IdleAction=ignore` | Negligible | `IdleAction=ignore` means the action is no-op regardless of the timer value. `IdleActionSec=0` is added defensively and cannot cause harm. |
| Masking sleep targets may cause `systemctl suspend` calls from scripts/applications to return error | Low–Medium | This is the intended behaviour. Any application that calls suspend will receive an error. This is correct for always-on systems. |
| GNOME `power-button-action = "nothing"` means the power button does nothing | Low | On a desktop/HTPC, the power button in GNOME Settings will show "Nothing". Hard power-off via long-press on the physical button still works at the hardware level. |

---

## 7. Verification Steps (for Review Phase)

After implementation, the reviewer must confirm:

1. `nix flake check` passes with no evaluation errors.
2. `sudo nixos-rebuild dry-build --flake .#vexos-desktop-amd` succeeds.
3. `sudo nixos-rebuild dry-build --flake .#vexos-desktop-nvidia` succeeds.
4. `sudo nixos-rebuild dry-build --flake .#vexos-htpc-amd` succeeds.
5. `sudo nixos-rebuild dry-build --flake .#vexos-htpc-nvidia` succeeds.
6. `sudo nixos-rebuild dry-build --flake .#vexos-htpc-vm` succeeds.
7. `hardware-configuration.nix` is NOT committed to the repository.
8. `system.stateVersion` has not changed.
9. `configuration-desktop.nix` imports list contains `./modules/system-nosleep.nix`.
10. `configuration-htpc.nix` imports list contains `./modules/system-nosleep.nix`.
11. `modules/system-nosleep.nix` exists and contains all four sleep-blocking layers.
12. `modules/system.nix` is unchanged.
13. `modules/gnome.nix` is unchanged.

---

## 8. Sources Consulted

1. **NixOS Manual — systemd options** (`systemd.suppressedSystemUnits`, `services.logind.extraConfig`): https://nixos.org/manual/nixos/stable/options
2. **NixOS Wiki — Power Management**: https://nixos.wiki/wiki/Power_management
3. **systemd sleep.conf(5) man page** — `AllowSuspend`, `AllowHibernation`, `AllowHybridSleep`, `AllowSuspendThenHibernate` directives in `[Sleep]` section
4. **systemd logind.conf(5) man page** — `HandleSuspendKey`, `HandleHibernateKey`, `HandleLidSwitch*`, `IdleAction`, `IdleActionSec` directives
5. **GNOME Settings Daemon gsettings schema** (`org.gnome.settings-daemon.plugins.power`) — `sleep-inactive-ac-type`, `sleep-inactive-ac-timeout`, `sleep-inactive-battery-type`, `sleep-inactive-battery-timeout`, `power-button-action` keys and their GVariant types (`s` for type strings, `i` for int32 timeouts)
6. **NixOS dconf module source** (`nixpkgs/nixos/modules/programs/dconf.nix`) — `programs.dconf.profiles.<name>.databases` is `types.listOf submodule`; confirmed additive merging via `lib.mkBefore`
7. **NVIDIA NixOS documentation** — `hardware.nvidia.powerManagement.enable` and its role in suspend/resume GPU state preservation via `nvidia-sleep.sh` hooks
8. **Arch Linux Wiki — GNOME/Tips and tricks: Disable suspend** — multi-layer approach to fully preventing GNOME-initiated sleep on always-on machines
9. **NixOS Discourse / GitHub issues** — confirmed `systemd.suppressedSystemUnits` as the correct way to mask systemd-shipped units like `sleep.target` (vs. `systemd.units.<name>.enable = false` which only affects NixOS-generated units)
