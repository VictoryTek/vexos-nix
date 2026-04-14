# Specification: Fix VS Code Launch Failure on NixOS (vscode-fhs)

**Feature:** `vscode-fhs`  
**Date:** 2026-04-13  
**Status:** Approved for implementation  

---

## 1. Current State Analysis

### File: `modules/development.nix`

```nix
environment.systemPackages = with pkgs; [
    # ── Editor ────────────────────────────────────────────────────────────────
    unstable.vscode                               # Visual Studio Code (unstable channel)
    ...
];
```

The current configuration installs `unstable.vscode` — the bare, unwrapped Visual Studio Code
binary from the `nixpkgs-unstable` channel as provided by the flake's `pkgs.unstable` overlay
(defined in `flake.nix` as the `unstableOverlayModule`).

### File: `flake.nix` (relevant excerpt)

```nix
unstableOverlayModule = {
  nixpkgs.overlays = [
    (final: prev: {
      unstable = import nixpkgs-unstable {
        inherit (final) config;
        inherit (final.stdenv.hostPlatform) system;
      };
    })
  ];
};
```

The `unstable` attribute namespace is available to all modules through this overlay. Therefore
`unstable.vscode-fhs` resolves to `pkgs-unstable.vscode-fhs`.

---

## 2. Problem Definition

### Root Cause: NixOS Does Not Follow the FHS Standard

NixOS does not adhere to the
[Filesystem Hierarchy Standard (FHS)](https://en.wikipedia.org/wiki/Filesystem_Hierarchy_Standard).
On a traditional Linux distribution, shared libraries live at well-known paths such as:

- `/lib/x86_64-linux-gnu/libdl.so.2`
- `/usr/lib/libc.so.6`

On NixOS, **all files live in the Nix store** under `/nix/store/<hash>-...`. The conventional
paths `/bin`, `/lib`, `/usr/lib`, etc., are absent or contain only a minimal bootstrap
(`/bin/sh`, `/usr/bin/env`).

### Why VS Code Breaks

VS Code is built on the **Electron framework**, which bundles a Chromium-based runtime. Like all
Electron applications, the VS Code binary at launch time:

1. Calls `ld-linux-x86-64.so.2` (the ELF dynamic linker) to resolve shared library paths.
2. Expects those libraries at FHS-standard paths (`/lib`, `/usr/lib`, etc.).
3. On NixOS, the dynamic linker is patched by `autoPatchelfHook` to use the Nix store path of
   `glibc`. However, extensions and bundled helper binaries are **not patched** – they are
   pre-compiled third-party ELF binaries that hard-code FHS paths.

The result is that:
- VS Code itself may launch (if `autoPatchelfHook` has patched its main ELF);
  but on **unstable** channels or after certain updates the patching may lag or fail,
  preventing launch entirely.
- Many extensions (language servers, debuggers, linters) ship pre-compiled binaries that fail
  to start because they reference `/lib/...` or `/usr/lib/...` which do not exist.
- The `jschardet` module (used for auto-encoding detection) can fail to load on launch,
  causing the entire VS Code window to immediately close — confirmed at
  [NixOS/nixpkgs#152939](https://github.com/NixOS/nixpkgs/issues/152939).

### Summary of Failure Modes

| Issue | Cause |
|-------|-------|
| VS Code does not open at all | Main Electron binary fails dynamic linking without patched loader |
| Extensions fail silently | Bundled extension binaries expect FHS paths |
| Window closes immediately | `jschardet` native module fails to load (nixpkgs#152939) |
| Rust, Python LSP failures | Language server binaries not in Nix store, FHS paths missing |

### Sources

1. [NixOS Wiki – Visual Studio Code (official NixOS wiki)](https://wiki.nixos.org/wiki/Visual_Studio_Code)
2. [NixOS Wiki – Visual Studio Code (community wiki)](https://nixos.wiki/wiki/Visual_Studio_Code)
3. [nixpkgs `generic.nix` – vscode FHS implementation source](https://github.com/NixOS/nixpkgs/blob/master/pkgs/applications/editors/vscode/generic.nix)
4. [nixpkgs buildFHSEnv documentation](https://nixos.org/manual/nixpkgs/stable/#sec-fhs-environments)
5. [NixOS Search – `vscode-fhs` package (nixpkgs-unstable)](https://search.nixos.org/packages?channel=unstable&query=vscode-fhs)
6. [NixOS/nixpkgs issue #152939 – jschardet / window closes immediately](https://github.com/NixOS/nixpkgs/issues/152939)

---

## 3. Proposed Solution

### Package: `vscode-fhs` (top-level alias for `vscode.fhs`)

nixpkgs provides `pkgs.vscode-fhs` as a top-level package (confirmed at version **1.114.0** on
`nixpkgs-unstable` as of 2026-04-13). It is defined in
`pkgs/applications/editors/vscode/generic.nix` as:

```nix
passthru = {
  fhs = fhs { };
  fhsWithPackages = f: fhs { additionalPkgs = f; };
};
```

And exposed at top level as `vscode-fhs = vscode.fhs`.

### How `vscode-fhs` Works

`vscode.fhs` uses `buildFHSEnv` to wrap VS Code in a chroot-like environment that:

- Re-creates the standard FHS directory tree (`/bin`, `/lib`, `/usr`, etc.) inside the sandbox.
- Populates it with Nix-store paths for all required libraries (glibc, libX11, ALSA, Mesa,
  NSS, libsecret, dbus, fontconfig, and others – see `targetPkgs` in `generic.nix`).
- Runs VS Code inside this environment so that **all** extension binaries can find their
  expected library paths without requiring per-binary `patchelf` calls.

The official NixOS wiki recommends this approach:

```nix
environment.systemPackages = with pkgs; [ vscode.fhs ];
# or equivalently:
environment.systemPackages = with pkgs; [ vscode-fhs ];
```

### Why `unstable.vscode-fhs` Over `pkgs.vscode-fhs`

The project already pins VS Code to the unstable channel via the `unstableOverlayModule`. Using
`unstable.vscode-fhs` keeps VS Code on the latest upstream release, consistent with the original
intent. The `fhs` wrapper is available under both stable (25.11) and unstable channels.

---

## 4. Implementation Steps

### Single-line change in `modules/development.nix`

**Before:**
```nix
unstable.vscode                               # Visual Studio Code (unstable channel)
```

**After:**
```nix
unstable.vscode-fhs                           # VS Code in FHS env (required on NixOS)
```

That is the **complete** implementation. No other files require modification.

### File Modified

- `modules/development.nix` — replace `unstable.vscode` with `unstable.vscode-fhs` on line ~18.

---

## 5. Dependencies

No new flake inputs are required. `vscode-fhs` is already part of `nixpkgs-unstable` and is
accessible via the existing `pkgs.unstable` overlay.

**Context7 verification:**
- Library ID resolved: `/nixos/nixpkgs` (Source Reputation: High)
- `vscode-fhs` confirmed in nixpkgs-unstable at version 1.114.0 (2026-04-13)
- Implemented via `buildFHSEnv` in `pkgs/applications/editors/vscode/generic.nix#L166`

---

## 6. Alternatives Considered

| Alternative | Notes | Recommendation |
|------------|-------|----------------|
| `pkgs.vscode-fhs` (stable) | Same package from 25.11 stable channel | Lower version; consistent unstable preferred |
| `pkgs.vscodium-fhs` | Open-source build without MS telemetry/marketplace | Valid if Marketplace access not needed; out of scope |
| `programs.nix-ld.enable = true` | System-wide dynamic linker shim; enables all ELF binaries | Broader scope change; not needed for this fix |
| `vscode-with-extensions` | Declarative extension management | Different concern; orthogonal to this fix |
| Keep `unstable.vscode` and `patchelf` manually | Fragile, requires updates per VS Code release | Not viable |

---

## 7. Risks and Mitigations

| Risk | Severity | Mitigation |
|------|----------|-----------|
| `buildFHSEnv` is impure | Low | Acceptable trade-off on a personal developer workstation; documented in nixpkgs manual |
| `sudo` does not work inside the FHS environment | Low | Affects only commands run within the VS Code terminal; system sudo still works normally outside VS Code |
| Non-reproducibility of extension binaries | Low | This is inherent to the FHS approach and is a deliberate trade-off for extension compatibility |
| `vscode-fhs` unavailable in future nixpkgs | Very Low | Established package with high adoption; fallback is `vscode.fhs` attribute form |
| Unfree licence requirement | None | `nixpkgs.config.allowUnfree = true` is already set system-wide (required for existing `unstable.vscode`) |

---

## 8. Validation

After implementation, validate with:

```bash
nix flake check
sudo nixos-rebuild dry-build --flake .#vexos-desktop-amd
sudo nixos-rebuild dry-build --flake .#vexos-desktop-nvidia
sudo nixos-rebuild dry-build --flake .#vexos-desktop-vm
```

Then after `nixos-rebuild switch`, confirm VS Code launches successfully:

```bash
code --version
```

---

## 9. Spec Sign-off

- Single file modified: `modules/development.nix`
- One-line change: `unstable.vscode` → `unstable.vscode-fhs`
- No new flake inputs
- No `system.stateVersion` change
- `hardware-configuration.nix` not affected
