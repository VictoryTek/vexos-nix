# Specification: Fix VS Code (vscode-fhs) Wayland Launch Failure

**Feature:** `vscode-wayland`  
**Date:** 2026-04-13  
**Status:** Ready for implementation  

---

## 1. Current State Analysis

### File: `modules/development.nix`

VS Code is installed as `unstable.vscode-fhs` — the FHS-wrapped build from nixpkgs-unstable via
the `pkgs.unstable` overlay. This correctly addresses the NixOS FHS library problem (see
`vscode-fhs_spec.md`). On nixpkgs-unstable, `vscode-fhs` ships **VS Code 1.87+**, which bundles
**Electron 28+**.

```nix
environment.systemPackages = with pkgs; [
    unstable.vscode-fhs          # VS Code in FHS env (fixes launch on NixOS)
    ...
];
```

### File: `modules/gnome.nix` (Ozone block, line 88–90)

`NIXOS_OZONE_WL = "1"` is already declared:

```nix
# ── Ozone Wayland ─────────────────────────────────────────────────────────
# Makes Electron/Chromium-based apps use native Wayland rendering.
environment.sessionVariables.NIXOS_OZONE_WL = "1";
```

### File: `home.nix` (line 106–110)

`NIXOS_OZONE_WL = "1"` is additionally declared at the user level:

```nix
home.sessionVariables = {
    NIXOS_OZONE_WL     = "1";
    MOZ_ENABLE_WAYLAND = "1";
    QT_QPA_PLATFORM    = "wayland;xcb";
};
```

### Absence of `ELECTRON_OZONE_PLATFORM_HINT`

A grep of the entire repository finds **no occurrence** of `ELECTRON_OZONE_PLATFORM_HINT`.

---

## 2. Problem Definition

### Why `NIXOS_OZONE_WL = "1"` alone is insufficient for `vscode-fhs` on Electron 28+

`NIXOS_OZONE_WL = "1"` is a **nixpkgs-specific** session variable. It is consumed by nixpkgs
**wrapper scripts** for Electron applications. When found, those wrapper scripts inject:

```
--ozone-platform=wayland
--enable-features=UseOzonePlatform,WaylandWindowDecorations
```

This hardcodes the Wayland backend unconditionally.

**The Electron 28+ compatibility break:** VS Code 1.87 (March 2024) upgraded to Electron 28.
Electron 28 introduced a new, more robust Wayland detection path. With hardcoded
`--ozone-platform=wayland`, Electron 28+ can fail to properly initialize the Wayland renderer
inside a `buildFHSEnvBubblewrap` sandbox because:

1. The bubblewrap sandbox creates a user namespace. Inside this namespace VS Code uses the
   **inner nixpkgs wrapper** to resolve Wayland flags. If the inner wrapper only processes
   `NIXOS_OZONE_WL` and not `ELECTRON_OZONE_PLATFORM_HINT`, the Electron 28+ runtime never
   receives the hint to use its modern auto-detection path.

2. `--ozone-platform=wayland` (triggered by `NIXOS_OZONE_WL`) tells Electron to use Wayland
   unconditionally but does not invoke Electron 28+'s built-in `WAYLAND_DISPLAY`-based socket
   auto-discovery. If the socket path resolution differs inside the bubblewrap namespace,
   Electron crashes before creating a window.

3. `--ozone-platform-hint=auto` (triggered by `ELECTRON_OZONE_PLATFORM_HINT = "auto"`) instructs
   Electron 28+ to inspect `WAYLAND_DISPLAY` at runtime and select Wayland or XCB accordingly.
   This is the **recommended path** in the Electron 28 changelog and in nixpkgs PR #284253.

### Summary

| Variable | Mechanism | Effect on Electron 28+ |
|---|---|---|
| `NIXOS_OZONE_WL = "1"` | nixpkgs wrapper → `--ozone-platform=wayland` | Hardcodes Wayland; bypasses Electron 28 auto-detection; **can fail inside bubblewrap** |
| `ELECTRON_OZONE_PLATFORM_HINT = "auto"` | nixpkgs wrapper → `--ozone-platform-hint=auto` | Uses Electron 28+ native auto-detection via `WAYLAND_DISPLAY`; **robust inside bubblewrap** |

Both variables should be set together. `NIXOS_OZONE_WL` ensures compatibility with Electron apps
on older wrappers; `ELECTRON_OZONE_PLATFORM_HINT` unlocks the Electron 28+ code path required by
the current `unstable.vscode-fhs`.

---

## 3. Proposed Solution

### Location: `modules/gnome.nix`

**Rationale for choosing `modules/gnome.nix` over `configuration.nix`:**

- `modules/gnome.nix` already owns the Ozone Wayland block (`NIXOS_OZONE_WL = "1"` at line 90).
- Wayland rendering hints are inherently Wayland / GNOME session-specific. Placing them in
  `gnome.nix` keeps the concern co-located and self-documenting.
- `configuration.nix` is the root module; it imports `gnome.nix`. Adding Wayland session
  variables there would scatter environment configuration across two files.
- All four GPU variants (`amd`, `nvidia`, `intel`, `vm`) import `configuration.nix` which
  imports `gnome.nix`, so the fix propagates to every host build automatically.

### Exact change

Expand the existing single-variable assignment into an attrset block and add
`ELECTRON_OZONE_PLATFORM_HINT`:

**Before (line 88–90 of `modules/gnome.nix`):**

```nix
  # ── Ozone Wayland ─────────────────────────────────────────────────────────
  # Makes Electron/Chromium-based apps use native Wayland rendering.
  environment.sessionVariables.NIXOS_OZONE_WL = "1";
```

**After:**

```nix
  # ── Ozone Wayland ─────────────────────────────────────────────────────────
  # NIXOS_OZONE_WL: nixpkgs wrapper signal — adds --ozone-platform=wayland to
  #   Electron/Chromium app launch flags.  Required for pre-Electron-28 apps.
  # ELECTRON_OZONE_PLATFORM_HINT: Electron 28+ native hint — adds
  #   --ozone-platform-hint=auto so Electron auto-detects Wayland via
  #   WAYLAND_DISPLAY.  Required for VS Code 1.87+ (vscode-fhs, Electron 28+).
  environment.sessionVariables = {
    NIXOS_OZONE_WL              = "1";
    ELECTRON_OZONE_PLATFORM_HINT = "auto";
  };
```

**Note on NixOS attrset merge:** `modules/flatpak.nix` also declares
`environment.sessionVariables` as an attrset (`XDG_DATA_DIRS`). NixOS merges attrsets from
multiple modules, so there is no conflict. Each key sets independently.

---

## 4. Implementation Steps

1. Open `modules/gnome.nix`.
2. Replace the single-line `environment.sessionVariables.NIXOS_OZONE_WL = "1";` with the
   attrset block shown in Section 3.
3. Run `nix flake check` to validate syntax and flake outputs.
4. Rebuild: `sudo nixos-rebuild dry-build --flake .#vexos-desktop-amd` (and nvidia/vm variants).
5. After confirming dry-builds succeed, apply with `sudo nixos-rebuild switch --flake .#<target>`.
6. Log out and back in (or reboot) so the new session variable is exported by PAM/systemd.
7. Launch VS Code from the GNOME app grid and verify it opens without crashing.

---

## 5. Dependencies

- No new flake inputs required.
- No new packages required.
- Change is purely an environment variable addition inside an existing NixOS module.

---

## 6. Affected Files

| File | Change |
|---|---|
| `modules/gnome.nix` | Expand `environment.sessionVariables` to include `ELECTRON_OZONE_PLATFORM_HINT = "auto"` |

No other files require modification.

---

## 7. Risks and Mitigations

| Risk | Likelihood | Mitigation |
|---|---|---|
| `--ozone-platform-hint=auto` causes XCB fallback on pure Wayland session | Very Low | `WAYLAND_DISPLAY` is always set in GDM Wayland sessions; auto-detection will select Wayland |
| Conflict with `home.nix` `home.sessionVariables.NIXOS_OZONE_WL = "1"` | None | Home Manager `home.sessionVariables` and system `environment.sessionVariables` are independent. Duplicate `NIXOS_OZONE_WL` is harmless. |
| NVIDIA: VS Code GPU process crash despite Ozone flags | Low | `hardware.nvidia.modesetting.enable = true` is already set in `modules/gpu/nvidia.nix`; KMS is active. If GPU crash persists on NVIDIA, add `--disable-gpu` to an overlay or wrapper as a follow-up. |
| VM build: no Wayland display available | Informational | Wayland session is available in the VM via `vboxvideo`/`virtio-gpu` with GDM. `--ozone-platform-hint=auto` will fall back to XCB if Wayland is unavailable — safe. |
| NixOS attrset merge collision | None | `environment.sessionVariables` in gnome.nix will become an attrset `{ NIXOS_OZONE_WL = "1"; ELECTRON_OZONE_PLATFORM_HINT = "auto"; }`. NixOS merges attrset options from all modules. No collision with `flatpak.nix` (`XDG_DATA_DIRS`) or any other module. |
