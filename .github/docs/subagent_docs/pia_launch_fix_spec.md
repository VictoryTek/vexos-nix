# PIA Launch Fix — Implementation Specification

**Feature:** `pia_launch_fix`
**Files:** `pkgs/pia-client-bin/default.nix`, `modules/pia.nix`
**Date:** 2026-05-28
**Status:** Ready for Implementation

---

## 1. Problem Summary

Four bugs were discovered after deploying the nixified PIA VPN package to a live machine:

| # | Symptom | Root Cause |
|---|---------|------------|
| 1 | Clicking the desktop icon does nothing | `libGLX.so.0` not found — GLVND dispatch library missing from `LD_LIBRARY_PATH` |
| 2 | `piavpn` daemon never starts at boot | `wantedBy = []` in `modules/pia.nix` — service is declared but not auto-started |
| 3 | Qt platform plugin fails to load | `bin/qt.conf` hardcodes `/opt/piavpn/` paths that do not exist in the Nix store |
| 4 | `QT_PLUGIN_PATH` points to wrong directory | Wrapper uses `lib/qt/plugins` but actual path is `plugins` (no `lib/qt/` prefix) |

---

## 2. Root Cause Analysis

### Bug 1 — Missing `libGLX.so.0`

PIA's bundled Qt6 GUI requires the OpenGL/GLVND dispatch layer. On NixOS this library
is provided by `pkgs.libglvnd`. Without it in `LD_LIBRARY_PATH` the dynamic linker
cannot find `libGLX.so.0` and the process exits immediately.

The current wrapper builds `LD_LIBRARY_PATH` as:

```
$out/share/pia-client/lib : /run/current-system/sw/share/nix-ld/lib
```

Neither path contains `libGLX.so.0`. The nix-ld shim path covers the ELF interpreter
gap but does not provide OpenGL dispatch libraries.

The vendor-specific GL implementation (`libGLX_mesa.so.0`, `libGLX_nvidia.so.0`) is
placed at `/run/opengl-driver/lib/` by NixOS's `hardware.graphics` subsystem. The
GLVND dispatch stub (`libGLX.so.0`, `libGL.so.1`, `libEGL.so.1`, `libGLdispatch.so.0`)
is in `${pkgs.libglvnd}/lib`. Both paths must appear before the bundled PIA libs.

### Bug 2 — Daemon not auto-started

The systemd service in `modules/pia.nix` has:

```nix
wantedBy = [ ];   # not auto-started
```

The `wantedBy` attribute controls which targets pull the unit in at boot. An empty list
means no target wants the service, so systemd never starts it automatically. The PIA GUI
communicates with the daemon over a local socket; if the daemon is not running, the GUI
connects, fails, and appears to do nothing. PIA's own Linux installer registers the daemon
at `multi-user.target`, which is the correct target.

### Bug 3 — `qt.conf` hardcodes `/opt/piavpn/`

The extracted PIA payload contains `bin/qt.conf`:

```ini
[Paths]
Plugins=/opt/piavpn/plugins
Libraries=/opt/piavpn/lib
Qml2Imports=/opt/piavpn/qml
```

Qt reads this file at startup to locate plugins and QML modules. On NixOS the files are
at `$out/share/pia-client/{plugins,lib,qml}`. Because `/opt/piavpn/` does not exist in
a nixified install, Qt cannot find the `xcb` or `wayland` platform plugins and the GUI
crashes silently or exits with a platform plugin error.

### Bug 4 — Wrong `QT_PLUGIN_PATH`

The existing `makeWrapper` call sets:

```bash
--set QT_PLUGIN_PATH "$out/share/pia-client/lib/qt/plugins"
```

Actual layout confirmed by `ls result/share/pia-client/`:

```
bin  lib  plugins  qml  share
```

The plugins directory is `plugins/` at the top level of `share/pia-client/`, not
`lib/qt/plugins/`. The wrong path means `QT_PLUGIN_PATH` points to a non-existent
directory and Qt falls back to its own search logic (which then fails because
`qt.conf` also points at `/opt/piavpn/`).

---

## 3. Implementation Plan

### 3.1 File: `pkgs/pia-client-bin/default.nix`

#### 3.1.1 Add `libglvnd` to function parameters

**Current:**
```nix
{ lib, stdenvNoCC, fetchurl, makeWrapper, bash }:
```

**Change to:**
```nix
{ lib, stdenvNoCC, fetchurl, makeWrapper, bash, libglvnd }:
```

No overlay or `callPackage` changes needed — `libglvnd` is already in nixpkgs and
`callPackage` will inject it automatically.

#### 3.1.2 Patch `qt.conf` in `installPhase`

After the `chmod -R u+rX "$out/share/pia-client"` line and before the `mkdir -p "$out/bin"` line, add:

```bash
# ── Patch qt.conf: replace /opt/piavpn with Nix store path ──────────────
# PIA's bundled qt.conf hardcodes /opt/piavpn/{plugins,lib,qml}.
# Rewrite these to point to the actual store paths.
if [ -f "$out/share/pia-client/bin/qt.conf" ]; then
  sed -i \
    -e "s|/opt/piavpn/plugins|$out/share/pia-client/plugins|g" \
    -e "s|/opt/piavpn/lib|$out/share/pia-client/lib|g" \
    -e "s|/opt/piavpn/qml|$out/share/pia-client/qml|g" \
    "$out/share/pia-client/bin/qt.conf"
fi
```

#### 3.1.3 Update `pia-client` `makeWrapper` call

**Current:**
```nix
makeWrapper "$out/share/pia-client/bin/pia-client" "$out/bin/pia-client" \
  --set    NIX_LD_LIBRARY_PATH "/run/current-system/sw/share/nix-ld/lib" \
  --prefix LD_LIBRARY_PATH : "$out/share/pia-client/lib:/run/current-system/sw/share/nix-ld/lib" \
  --set    QT_PLUGIN_PATH "$out/share/pia-client/lib/qt/plugins"
```

**Change to:**
```nix
makeWrapper "$out/share/pia-client/bin/pia-client" "$out/bin/pia-client" \
  --set    NIX_LD_LIBRARY_PATH "/run/current-system/sw/share/nix-ld/lib" \
  --prefix LD_LIBRARY_PATH : "${libglvnd}/lib:/run/opengl-driver/lib:$out/share/pia-client/lib:/run/current-system/sw/share/nix-ld/lib" \
  --set    QT_PLUGIN_PATH "$out/share/pia-client/plugins" \
  --set    QML2_IMPORT_PATH "$out/share/pia-client/qml"
```

Changes made:
- `LD_LIBRARY_PATH` prepends `${libglvnd}/lib` (GLVND dispatch stubs: `libGLX.so.0`,
  `libGL.so.1`, `libEGL.so.1`, `libGLdispatch.so.0`) and `/run/opengl-driver/lib`
  (vendor GL implementation, placed there by `hardware.graphics`) before PIA's own libs
- `QT_PLUGIN_PATH` corrected from `lib/qt/plugins` to `plugins`
- `QML2_IMPORT_PATH` added pointing to `qml/` for Qt5/Qt6 QML module resolution

**Order rationale for `LD_LIBRARY_PATH`:**
`${libglvnd}/lib` must come before `$out/share/pia-client/lib` because PIA may bundle
an older or stripped libGL stub. The GLVND dispatch library forwards to the correct
vendor driver at runtime via `/run/opengl-driver/lib`.

---

### 3.2 File: `modules/pia.nix`

#### 3.2.1 Enable auto-start for the daemon

**Current:**
```nix
systemd.services.piavpn = {
  description = "Private Internet Access daemon";
  after = [ "syslog.target" "network.target" ];
  wantedBy = [ ];   # not auto-started; user starts it manually via `just pia`
```

**Change to:**
```nix
systemd.services.piavpn = {
  description = "Private Internet Access daemon";
  after = [ "syslog.target" "network.target" ];
  wantedBy = [ "multi-user.target" ];   # auto-starts at boot; stop with: systemctl stop piavpn
```

No other changes to `modules/pia.nix` are required. The `serviceConfig` block, cleanup
activation script, and all other options remain unchanged.

---

## 4. File List

| File | Change type |
|------|-------------|
| `pkgs/pia-client-bin/default.nix` | Add `libglvnd` param; add `qt.conf` patch; fix `QT_PLUGIN_PATH`; add `QML2_IMPORT_PATH`; extend `LD_LIBRARY_PATH` |
| `modules/pia.nix` | Change `wantedBy = []` to `wantedBy = [ "multi-user.target" ]` |

---

## 5. Dependencies

| Dependency | Source | Notes |
|------------|--------|-------|
| `pkgs.libglvnd` | nixpkgs | Already in nixpkgs; injected via `callPackage`. No overlay change needed. |

No new flake inputs. No new overlays. No changes to `flake.nix`.

---

## 6. Risk Assessment

| Risk | Severity | Mitigation |
|------|----------|------------|
| `libglvnd` version mismatch with vendor driver | Low | GLVND dispatch layer is designed to be forward/backward compatible; `/run/opengl-driver/lib` provides the vendor side |
| `qt.conf` patch misses path variants | Low | The `sed` replacements cover all three paths (`plugins`, `lib`, `qml`). If `qt.conf` is absent the block is skipped via `[ -f ... ]` guard |
| `QML2_IMPORT_PATH` conflicts with system Qt | Low | Path is scoped to `$out/share/pia-client/qml`; only PIA's wrapper inherits it |
| Daemon auto-start causes resource usage at boot | Low | piavpn daemon is lightweight (wireguard + routing); matches upstream installer behavior |
| Enabling `wantedBy` on a machine without PIA credentials | Low | The daemon starts but sits idle until configured; does not open network connections until connected via `piactl` or GUI |

Overall risk: **Low**. Both changes are targeted and narrow in scope. The `default.nix`
changes only affect the PIA package derivation; the `pia.nix` change only affects the
systemd unit declaration. Neither touches shared modules or other packages.

---

## 7. Validation Steps (for Review Phase)

1. Run `nix flake show` — confirms flake structure is valid after `default.nix` changes
2. Run `sudo nixos-rebuild dry-build --flake .#vexos-desktop-amd` — confirms the AMD
   closure builds (PIA is included via `modules/pia.nix` → `configuration-desktop.nix`)
3. Run `sudo nixos-rebuild dry-build --flake .#vexos-desktop-nvidia` — confirms the
   NVIDIA closure builds (NVIDIA uses the same Qt/GL path)
4. Confirm `result/share/pia-client/bin/qt.conf` contains Nix store paths (not `/opt/piavpn/`)
5. Confirm `result/bin/pia-client` wrapper script contains `libglvnd` in `LD_LIBRARY_PATH`
6. Confirm `result/bin/pia-client` wrapper script contains `QML2_IMPORT_PATH`
7. Confirm `result/bin/pia-client` wrapper script has `QT_PLUGIN_PATH=.../plugins` (not `.../lib/qt/plugins`)
