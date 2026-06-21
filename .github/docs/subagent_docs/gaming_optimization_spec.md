---
name: gaming-optimization
description: Bazzite/CachyOS parity gaming improvements — gamemode fixes, RADV perf flags, Mesa shader cache
metadata:
  type: project
---

# Spec: Gaming Optimization — Bazzite/CachyOS Parity

## Goal

Match Bazzite and CachyOS gaming configuration quality across four areas:
1. Fix a gamemode bug that actively hurts the experience (screen-lock mid-game)
2. Add AMD GPU performance governor via gamemode (architectural gap)
3. Enable RADV Graphics Pipeline Library async shader compilation
4. Increase Mesa shader cache size for faster repeat-load times

---

## Current State Analysis

**What the current stack already does well:**
- SCX LAVD scheduler ✓
- `preempt=full` kernel, `split_lock_detect=off` ✓
- `vm.max_map_count = 2147483642` (SteamOS value) ✓
- 32-bit Mesa/VA-API for Proton ✓
- proton-ge-bin as extraCompatPackages ✓
- PipeWire with 64-quantum low latency ✓
- Full controller udev rules ✓
- `renice = 10` — **correct** (gamemode negates the value to apply nice = -10) ✓

**Bug — `inhibit_screensaver = 0`:**
The gamemode 1.8.2 default and documentation both specify `inhibit_screensaver=1`.
The current config overrides it to `0`, which means GNOME's idle/screen-lock timer
continues running while games are active. Users experience mid-game screen-lock.

**Architectural issue — AMD `gpu` section in shared `gaming.nix`:**
`programs.gamemode.settings.gpu` with `amd_performance_level = "high"` is AMD-specific
kernel sysfs configuration (`/sys/class/drm/card0/device/power_dpm_force_performance_level`).
On NVIDIA hosts, gamemode silently fails (no amdgpu sysfs, wrong driver path). The config
belongs in `modules/gpu/amd.nix` per Option B architecture.

**Missing — CPU core pinning:**
gamemode 1.8.2 supports `[cpu] pin_cores=yes` which auto-detects Ryzen 7000 3D V-Cache,
Ryzen 7900x3d/7950x3d, and Intel P+E-core (12th gen+) CPUs and pins game threads to
the preferred cores. The user is already in the `gamemode` group (required for parking,
not required for pinning). This is a Bazzite/CachyOS configuration that we lack.

**Missing — RADV async shader compilation (AMD):**
`RADV_PERFTEST=gpl` enables Graphics Pipeline Libraries in RADV, allowing async Vulkan
shader compilation. This reduces the stutters during first-play of Vulkan games where
pipelines are being compiled. Bazzite sets this. In Mesa 26.1.2, some GPL paths are
already default, but the flag is still useful for edge cases.

**Missing — Mesa shader cache size (all GPU/gaming configs):**
`MESA_SHADER_CACHE_MAX_SIZE` defaults to 1GB. Increasing to 4GB means Mesa caches more
compiled shaders between play sessions, reducing stutter on repeated launch.

---

## Proposed Changes

### 1. `modules/gaming.nix` — fix inhibit_screensaver, add cpu pinning, remove gpu section

**Fix:**
```nix
programs.gamemode.settings.general = {
  renice = 10;              # unchanged — negated by gamemode to nice = -10
  inhibit_screensaver = 1;  # fix: was 0; default and correct value is 1
};
programs.gamemode.settings.cpu = {
  pin_cores = "yes";        # add: auto-pin to P-cores on Ryzen 3D / Intel hybrid
};
# Remove programs.gamemode.settings.gpu — move to gpu/amd.nix
```

### 2. `modules/gpu/amd.nix` — AMD-specific gamemode GPU settings + RADV

```nix
programs.gamemode.settings.gpu = {
  apply_gpu_optimisations = "accept-responsibility";
  gpu_device = 0;
  amd_performance_level = "high";
};

environment.variables.RADV_PERFTEST = "gpl";
```

### 3. `modules/gpu-gaming.nix` — Mesa shader cache (all gaming GPU types)

```nix
environment.variables.MESA_SHADER_CACHE_MAX_SIZE = "4G";
```

---

## What is NOT changed (and why)

| Item | Decision | Reason |
|------|----------|--------|
| `renice = 10` | Keep | Correct — gamemode negates to nice = -10 |
| `desiredgov = performance` | Not added | Already the gamemode default |
| `softrealtime = auto` | Not added | Requires SCHED_ISO; not in upstream kernel |
| NVIDIA gamemode GPU | Not added | Requires Coolbits + nvidia-settings on Wayland; unreliable |
| `__GL_THREADED_OPTIMIZATIONS` | Not added | OpenGL-specific; modern Vulkan games unaffected |
| PipeWire quantum | Not changed | Already tuned; comment already notes increase path for crackling |
| kernel params | Not changed | Already Bazzite-parity (`preempt=full`, vm.max_map_count, SCX) |
| DXVK/Proton env vars | Not added | Per-game; better set in Steam launch options |

---

## Files Modified

- `modules/gaming.nix`
- `modules/gpu/amd.nix`
- `modules/gpu-gaming.nix`

## Risk Assessment

| Risk | Likelihood | Impact | Mitigation |
|------|-----------|--------|-----------|
| `pin_cores` stutter on unsupported CPUs | Low | Low | gamemode no-ops gracefully if CPU not recognized |
| RADV_PERFTEST=gpl already default in Mesa 26 | Medium | None | Flag is idempotent; no harm if already enabled |
| MESA_SHADER_CACHE_MAX_SIZE uses 4GB disk | Low | Low | Cache is filled lazily; not pre-allocated |
| gamemode.settings merge conflict | Low | High | All changed keys are in different INI sections; NixOS attrs merge is safe |
