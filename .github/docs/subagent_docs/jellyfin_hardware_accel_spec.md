# Jellyfin Hardware Acceleration Specification

Date: 2026-05-16
Feature: jellyfin_hardware_accel
Phase: 1 (Research and Specification)

## 1. Current State Analysis

### 1.1 Repository wiring and activation path
- `configuration-server.nix` and `configuration-headless-server.nix` both import `./modules/server` and `./modules/gpu.nix`.
- Host role variants import GPU-specific modules (`modules/gpu/amd*.nix`, `modules/gpu/intel*.nix`, `modules/gpu/nvidia*.nix`), so GPU driver and media stack wiring is present for server and headless-server builds.
- `flake.nix` conditionally imports `/etc/nixos/server-services.nix` (when present) for service toggles; the tracked template is `template/server-services.nix`.

### 1.2 Jellyfin module behavior today
- `modules/server/jellyfin.nix` only does:
  - `services.jellyfin.enable = true`
  - `services.jellyfin.openFirewall = true`
  - adds the primary user (`config.vexos.user.name`) to the `jellyfin` group.
- It does not configure GPU-oriented group access (`render`, `video`) for the service process.

### 1.3 Plex reference pattern
- `modules/server/plex.nix` includes an explicit `plexPass` toggle and maps this to `services.plex.accelerationDevices = [ "*" ]` when enabled.
- Upstream nixpkgs Plex has a first-class `services.plex.accelerationDevices` option (default `[ "*" ]`) and systemd `DeviceAllow` handling for explicit device sets.

### 1.4 GPU modules
- `modules/gpu.nix` and vendor modules provide drivers and user-space acceleration packages (VA-API, Vulkan, Intel media stack, NVIDIA VAAPI bridge where applicable).
- None of the GPU modules grant Jellyfin process-level group membership to access media device nodes.

## 2. Current Operational Behavior (Service User and Device Access)

When `vexos.server.jellyfin.enable = true`:
- Jellyfin runs under upstream defaults `services.jellyfin.user = "jellyfin"` and `services.jellyfin.group = "jellyfin"` unless overridden.
- Upstream NixOS jellyfin service sets `PrivateDevices = false`, so `/dev` is visible to the unit.
- However, visibility does not imply permission. On Linux, media nodes are typically owned by `video` and/or `render` groups.
- Because the VexOS wrapper does not assign Jellyfin to those groups, VA-API/QSV/NVENC access can fail with permission-denied behavior and Jellyfin falls back to software transcoding.

Conclusion: the missing piece is Linux group authorization for the Jellyfin service process, not missing GPU driver packages.

## 3. Problem Definition

Bug statement:
- Jellyfin hardware transcoding is not reliably usable on server/headless-server variants even though GPU modules are imported and acceleration packages are installed.

Root cause:
- `modules/server/jellyfin.nix` does not grant the Jellyfin service process membership in `render`/`video` groups required by Linux GPU device nodes.

Impact:
- Intel/AMD paths (QSV/VA-API) frequently fail to open `/dev/dri/renderD*`.
- NVIDIA paths require proper video-device permissions and similarly degrade without them.
- CPU usage spikes under transcoding workloads, defeating the purpose of GPU-enabled role variants.

## 4. External Research and Best Practices

The following sources were used (minimum 6 required):

1. NixOS nixpkgs jellyfin module source (nixos-25.11)
   - URL: https://raw.githubusercontent.com/NixOS/nixpkgs/nixos-25.11/nixos/modules/services/misc/jellyfin.nix
   - Key points: default user/group are `jellyfin`; `PrivateDevices = false`; no `accelerationDevices` option.

2. NixOS nixpkgs plex module source (nixos-25.11)
   - URL: https://raw.githubusercontent.com/NixOS/nixpkgs/nixos-25.11/nixos/modules/services/misc/plex.nix
   - Key points: `services.plex.accelerationDevices` exists and is integrated with systemd device controls.

3. MyNixOS option docs: `services.plex.accelerationDevices`
   - URL: https://mynixos.com/nixpkgs/option/services.plex.accelerationDevices
   - Key points: default `[ "*" ]`; option is intended for transcoding device access.

4. Jellyfin official hardware acceleration overview
   - URL: https://jellyfin.org/docs/general/post-install/transcoding/hardware-acceleration/
   - Key points: Linux acceleration methods and verification guidance; hardware transcode requires correct device/runtime setup.

5. Jellyfin official Intel HWA guide
   - URL: https://jellyfin.org/docs/general/post-install/transcoding/hardware-acceleration/intel
   - Key points: ensure `/dev/dri/renderD*` exists; add Jellyfin user to `render` (sometimes `video`/`input`).

6. Jellyfin official AMD HWA guide
   - URL: https://jellyfin.org/docs/general/post-install/transcoding/hardware-acceleration/amd
   - Key points: explicitly add Jellyfin user to both `render` and `video` groups on Linux.

7. Jellyfin official NVIDIA HWA guide
   - URL: https://jellyfin.org/docs/general/post-install/transcoding/hardware-acceleration/nvidia
   - Key points: Linux setup requires correct NVIDIA permissions/device access for transcoding.

8. NixOS Wiki: Jellyfin
   - URL: https://wiki.nixos.org/wiki/Jellyfin
   - Key points: NixOS Jellyfin setup and hardware-transcoding guidance ties to official Jellyfin docs.

9. NixOS Wiki: Accelerated Video Playback
   - URL: https://wiki.nixos.org/wiki/Accelerated_Video_Playback
   - Key points: NixOS acceleration is package + driver + runtime/device permission dependent.

## 5. Proposed Solution Architecture (Minimal and Safe)

Design goals:
- Fix hardware transcoding permissions without broadening unrelated service attack surface.
- Preserve existing role and module architecture (Option B: role expressed by imports; no role-conditional logic inside shared modules).
- Keep changes narrowly scoped to Jellyfin wrapper module and optional service-toggle discoverability docs.

### Proposed implementation

1. Add a new VexOS option in `modules/server/jellyfin.nix`:
   - `vexos.server.jellyfin.hardwareAcceleration`
   - type: boolean
   - default: `true`
   - purpose: allow explicit opt-out for hardened/minimal deployments.

2. When both `vexos.server.jellyfin.enable` and `vexos.server.jellyfin.hardwareAcceleration` are true:
   - set `systemd.services.jellyfin.serviceConfig.SupplementaryGroups = [ "render" "video" ];`

Rationale:
- This directly solves Linux device permission requirements documented by Jellyfin.
- It avoids adding brittle manual `DeviceAllow` entries for jellyfin, since upstream already keeps `PrivateDevices = false` and device filtering is not the blocker here.
- It is resilient if `services.jellyfin.user` is overridden from default, because group assignment is attached to service runtime rather than hardcoding only `users.users.jellyfin`.

3. Optional but recommended: annotate `template/server-services.nix` with:
   - `# vexos.server.jellyfin.hardwareAcceleration = true;`
   - comment explaining render/video group grant.

## 6. Exact Implementation Steps and File Changes

### Step 1: Update Jellyfin module
File: `modules/server/jellyfin.nix`

Changes:
- Extend `options.vexos.server.jellyfin` with `hardwareAcceleration` bool option (default true).
- Under existing `config = lib.mkIf cfg.enable { ... }` block, add conditional supplementary groups:
  - `systemd.services.jellyfin.serviceConfig.SupplementaryGroups = lib.mkIf cfg.hardwareAcceleration [ "render" "video" ];`
- Keep existing primary-user media-management group behavior (`users.users.${config.vexos.user.name}.extraGroups = [ "jellyfin" ];`).

### Step 2: Expose toggle in template service file (recommended)
File: `template/server-services.nix`

Changes:
- Add commented line near Jellyfin toggle documenting the new option and default behavior.

## 7. Risks and Mitigations

1. Risk: Increased hardware-device access for Jellyfin process.
   - Mitigation: scope is limited to media service process via `SupplementaryGroups`; include opt-out toggle `hardwareAcceleration = false`.

2. Risk: Assumption that groups exist on all builds.
   - Mitigation: validated in current configs (`render` and `video` exist in evaluated host config); keep checks in validation plan.

3. Risk: Users may expect auto-enablement in Jellyfin UI.
   - Mitigation: document that OS-level permissions are enabled by this change; actual method selection (VA-API/QSV/NVENC) remains in Jellyfin admin dashboard.

4. Risk: Potential mismatch with non-default custom Jellyfin user.
   - Mitigation: use service-level `SupplementaryGroups` instead of hardcoded `users.users.jellyfin.extraGroups`.

## 8. Validation Plan

### 8.1 Evaluation and build checks
1. `nix flake check --impure`
2. `nix build --dry-run --impure .#nixosConfigurations.vexos-server-amd.config.system.build.toplevel`
3. `nix build --dry-run --impure .#nixosConfigurations.vexos-server-intel.config.system.build.toplevel`
4. `nix build --dry-run --impure .#nixosConfigurations.vexos-server-nvidia.config.system.build.toplevel`
5. `nix build --dry-run --impure .#nixosConfigurations.vexos-headless-server-amd.config.system.build.toplevel`
6. `nix build --dry-run --impure .#nixosConfigurations.vexos-headless-server-intel.config.system.build.toplevel`
7. `nix build --dry-run --impure .#nixosConfigurations.vexos-headless-server-nvidia.config.system.build.toplevel`

### 8.2 Service option sanity checks
1. Confirm option defaults still evaluate:
   - `nix eval --impure --raw .#nixosConfigurations.vexos-server-amd.options.services.jellyfin.user.default`
   - `nix eval --impure --raw .#nixosConfigurations.vexos-server-amd.options.services.jellyfin.group.default`
2. Confirm required groups exist in config:
   - `nix eval --impure --raw .#nixosConfigurations.vexos-server-amd.config.users.groups.render.name`
   - `nix eval --impure --raw .#nixosConfigurations.vexos-server-amd.config.users.groups.video.name`

### 8.3 Runtime verification (post-switch on a host with Jellyfin enabled)
1. `systemctl show jellyfin -p SupplementaryGroups`
2. `systemctl status jellyfin`
3. Trigger a transcoding stream in Jellyfin and verify GPU activity:
   - Intel: `intel_gpu_top`
   - AMD: `radeontop`
   - NVIDIA: `nvidia-smi`

## 9. Expected Modified File List (Implementation Phase)

Expected files to change in Phase 2:
- `modules/server/jellyfin.nix`
- `template/server-services.nix` (recommended documentation/option discoverability update)
