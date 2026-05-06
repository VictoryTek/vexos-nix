# Review: Replace GNOME Videos (org.gnome.Totem) with mpv

**Feature:** replace_totem_with_mpv  
**Review Date:** 2026-05-05  
**Reviewer:** QA Subagent (Phase 3)  
**Verdict:** PASS  

---

## 1. Summary of Findings

All five files required by the specification were modified correctly. Every checklist item passes. A single minor stale comment was found in `modules/gnome.nix` outside the spec's explicitly required changes — it does not affect correctness, builds, or runtime behaviour and is categorised as RECOMMENDED.

---

## 2. File-by-File Analysis

### 2.1 `modules/packages-desktop.nix` ✅

- `mpv` added to `environment.systemPackages` with the inline comment `# Video player (replaces Totem Flatpak on desktop/stateless/server)`.
- Position is consistent with existing entry style.
- No GStreamer packages added (correct per spec §3.4 — mpv uses ffmpeg directly).
- File header confirms scope: _"GUI packages for roles with a display server (desktop, server, htpc, stateless). Do NOT import on headless-server."_

### 2.2 `modules/gnome-desktop.nix` ✅

- `org.gnome.Totem` is absent from `gnomeBaseApps` — list now contains only `TextEditor` and `Loupe`.
- File header comment updated: Totem removed, mpv sourced from nixpkgs via `packages-desktop.nix` noted.
- Totem migration cleanup block present in `flatpak-install-gnome-apps` service script, positioned after disk-space check and before `flatpak install`:

  ```bash
  # Migration: uninstall Totem — mpv is the designated player.
  if flatpak list --app --columns=application 2>/dev/null | grep -qx "org.gnome.Totem"; then
    echo "flatpak: removing org.gnome.Totem (desktop role uses mpv)"
    flatpak uninstall --noninteractive --assumeyes org.gnome.Totem || true
  fi
  ```

- Block matches htpc reference pattern exactly (guarded, `--noninteractive --assumeyes`, `|| true`).
- No `lib.mkIf` guards added.

### 2.3 `modules/gnome-stateless.nix` ✅

- `org.gnome.Totem` is absent from `gnomeAppsToInstall`.
- File header updated with mpv note.
- Desktop-only-app migration loop preserved.
- Totem migration cleanup block added after the desktop-only-app loop, before `flatpak install` — identical pattern to htpc reference.
- No `lib.mkIf` guards added.

### 2.4 `modules/gnome-server.nix` ✅

- `org.gnome.Totem` is absent from `gnomeAppsToInstall`.
- File header updated with mpv note.
- Desktop-only-app migration loop preserved.
- Totem migration cleanup block added after the desktop-only-app loop, before `flatpak install`.
- No `lib.mkIf` guards added.

### 2.5 `modules/gnome.nix` ✅ (with RECOMMENDED note)

- `totem` inline comment in `environment.gnome.excludePackages` updated per spec:

  ```nix
  totem         # mpv (nixpkgs) is the video player; Flatpak Totem is not installed
  ```

- **RECOMMENDED — stale NOTE comment (lines 35–40):** The unstable-overlay section contains the comment:

  ```nix
  # NOTE: gnome-text-editor, gnome-system-monitor, loupe, and totem are
  # installed via Flatpak on all roles; …
  ```

  After this change, totem is no longer installed via Flatpak on any role. The comment was outside the spec's required scope and does not affect evaluation or builds, but it is now misleading. It should be updated to remove "totem" from the Flatpak list in a follow-up.

---

## 3. Validation Checklist

| # | Check | Result |
|---|-------|--------|
| 1 | All 5 spec files modified | ✅ PASS |
| 2 | `org.gnome.Totem` absent from desktop `gnomeBaseApps` | ✅ PASS |
| 3 | `org.gnome.Totem` absent from stateless `gnomeAppsToInstall` | ✅ PASS |
| 4 | `org.gnome.Totem` absent from server `gnomeAppsToInstall` | ✅ PASS |
| 5 | `mpv` present in `packages-desktop.nix` system packages | ✅ PASS |
| 6 | Totem migration block in `gnome-desktop.nix` (htpc pattern) | ✅ PASS |
| 7 | Totem migration block in `gnome-stateless.nix` (htpc pattern) | ✅ PASS |
| 8 | Totem migration block in `gnome-server.nix` (htpc pattern) | ✅ PASS |
| 9 | No `lib.mkIf` guards added | ✅ PASS |
| 10 | `gnome.nix` `totem` inline comment updated | ✅ PASS |
| 11 | `system.stateVersion` unchanged (`"25.11"`) | ✅ PASS |
| 12 | `hardware-configuration.nix` not tracked in git | ✅ PASS |
| 13 | `nix flake check --impure` — all 30 configs pass | ✅ PASS |
| 14 | `nixos-rebuild dry-build .#vexos-desktop-amd --impure` | ✅ PASS |
| 15 | `nixos-rebuild dry-build .#vexos-stateless-amd --impure` | ✅ PASS |
| 16 | `nixos-rebuild dry-build .#vexos-server-amd --impure` | ✅ PASS |

---

## 4. Build Results

### `nix flake check`

Pure-mode `nix flake check` fails with "access to absolute path '/etc' is forbidden" — this is an expected, pre-existing architectural constraint: the flake imports `hardware-configuration.nix` from `/etc/nixos/` on the host, which is forbidden in Nix sandbox evaluation. This failure is not introduced by this change.

With `--impure`: **ALL 30 `nixosConfigurations` pass.**

```
checking NixOS configuration 'nixosConfigurations.vexos-desktop-amd'...
checking NixOS configuration 'nixosConfigurations.vexos-desktop-nvidia'...
[... 28 more configurations ...]
checking NixOS configuration 'nixosConfigurations.vexos-htpc-vm'...
```

Exit code: **0**

### `nixos-rebuild dry-build .#vexos-desktop-amd --impure`

Exit code: **0** — system closure evaluated and derivation paths printed successfully.

### `nixos-rebuild dry-build .#vexos-stateless-amd --impure`

Exit code: **0** — system closure evaluated successfully.

### `nixos-rebuild dry-build .#vexos-server-amd --impure`

Exit code: **0** — system closure evaluated successfully.

---

## 5. Issues Found

### CRITICAL
None.

### RECOMMENDED
1. **Stale NOTE comment in `modules/gnome.nix` (lines 35–40):** The overlay comment names "totem" as a Flatpak-installed package, but totem is no longer Flatpak-installed on any role. The comment should have "and totem" removed from the list. This is outside the spec's explicitly required changes and has zero impact on the build or runtime, but leaves inaccurate documentation.

---

## 6. Score Table

| Category | Score | Grade |
|----------|-------|-------|
| Specification Compliance | 97% | A |
| Best Practices | 97% | A |
| Functionality | 100% | A+ |
| Code Quality | 95% | A |
| Security | 100% | A+ |
| Performance | 100% | A+ |
| Consistency | 97% | A |
| Build Success | 100% | A+ |

**Overall Grade: A (98%)**

---

## 7. Verdict

**PASS**

All spec requirements are fully implemented. All builds pass. One RECOMMENDED stale comment was identified in `gnome.nix` outside the spec's required scope; it does not affect correctness, builds, or runtime behaviour. The implementation is ready for Phase 6 Preflight Validation.
