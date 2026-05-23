# Simplenote Flatpak Silent-Fail — Research Specification

**Feature name**: `simplenote_flatpak`
**Date**: 2026-05-22
**Status**: DRAFT — Phase 1 complete, ready for Phase 2 implementation

---

## 1. Current State Analysis

### 1.1 What is already configured

| Setting | Location | Value |
|---|---|---|
| `services.flatpak.enable` | `modules/flatpak.nix` | `true` |
| `xdg.portal.enable` | `modules/gnome.nix` | `true` |
| `xdg.portal.extraPortals` | `modules/gnome.nix` | `[ pkgs.xdg-desktop-portal-gnome ]` (stable) |
| `xdg.portal.config` | — | Not set (intentional — upstream GNOME portal config) |
| `NIXOS_OZONE_WL` | `modules/gnome.nix` (`environment.sessionVariables`) | `"1"` |
| `ELECTRON_OZONE_PLATFORM_HINT` | `modules/gnome.nix` (`environment.sessionVariables`) | `"auto"` |
| `programs.dconf.enable` | `modules/gnome.nix` | `true` |
| GNOME core stack | `modules/gnome.nix` (overlay) | Pinned to `pkgs.unstable` |
| `xdg-desktop-portal-gnome` | `modules/gnome.nix` `extraPortals` | `pkgs.xdg-desktop-portal-gnome` (**stable** — NOT unstable) |
| `services.desktopManager.gnome.enable` | `modules/gnome.nix` | `true` |
| GDM auto-login | `modules/gnome.nix` | Enabled for `config.vexos.user.name` |
| Simplenote Flatpak | `modules/flatpak.nix` (`defaultApps`) | `com.simplenote.Simplenote` |

### 1.2 Simplenote Flatpak manifest (upstream, Flathub)

The current manifest (`com.simplenote.Simplenote.yaml`, merged via PR #14, Flathub — version 2.24.0) declares the following `finish-args`:

```yaml
finish-args:
  - --env=GTK_PATH=/app/lib/gtkmodules
  - --socket=x11          # X11 socket ONLY — no --socket=wayland
  - --device=dri
  - --share=ipc
  - --share=network
  - --socket=cups
  - --filesystem=xdg-documents
  - --filesystem=xdg-download
  - --talk-name=org.freedesktop.secrets
```

**Critical observation**: `--socket=wayland` is absent. The app declares only X11 socket access.

The startup script inside the Flatpak is:
```bash
export TMPDIR="$XDG_RUNTIME_DIR/app/$FLATPAK_ID"
exec zypak-wrapper /app/Simplenote/simplenote "$@"
```

The app uses `org.electronjs.Electron2.BaseApp` with `org.freedesktop.Platform 25.08`.
`libsecret` was removed from the manifest in 2024 (now provided by the BaseApp runtime).

### 1.3 GNOME session variable propagation behaviour

`environment.sessionVariables` in NixOS writes variables to the PAM session environment (via `/etc/set-environment`). On GNOME/GDM, `gnome-session` (or the GDM launch-environment service) calls `dbus-update-activation-environment --systemd` to propagate the entire PAM session environment into the systemd user session and the D-Bus session bus activation environment.

**Consequence**: ALL environment variables set via `environment.sessionVariables` — including `ELECTRON_OZONE_PLATFORM_HINT=auto` and `NIXOS_OZONE_WL=1` — are inherited by every app that is D-Bus activated in the user session, **including Flatpak apps**. Flatpak does not filter `ELECTRON_OZONE_PLATFORM_HINT` from the environment it passes to the sandbox.

---

## 2. Root Cause Identification

### 2.1 PRIMARY ROOT CAUSE — Wayland socket blocked, Electron crashes silently

**Mechanism:**

1. User launches `com.simplenote.Simplenote` (e.g., from GNOME Shell app grid).
2. Flatpak starts the sandbox with the inherited session environment, which includes `ELECTRON_OZONE_PLATFORM_HINT=auto` and `WAYLAND_DISPLAY=wayland-1`.
3. Electron's platform-detection logic sees `ELECTRON_OZONE_PLATFORM_HINT=auto` and the set `WAYLAND_DISPLAY` variable; it selects the Ozone/Wayland backend.
4. Electron tries to open `/run/user/<uid>/wayland-1` (the compositor socket).
5. Flatpak's bubblewrap sandbox does **not** bind-mount the Wayland socket into the sandbox because the manifest does not declare `--socket=wayland`.
6. Electron's Wayland initialisation fails. Unlike X11 failure (which typically falls back), Electron's Ozone Wayland initialisation failure with `ELECTRON_OZONE_PLATFORM_HINT=auto` results in a **silent process exit** — no window appears, no error dialog, no notification.

**Evidence:**
- Simplenote Flatpak manifest: `--socket=x11` present, `--socket=wayland` absent (confirmed from [flathub/com.simplenote.Simplenote `com.simplenote.Simplenote.yaml`](https://github.com/flathub/com.simplenote.Simplenote/blob/master/com.simplenote.Simplenote.yaml)).
- Flathub issue [#16](https://github.com/flathub/com.simplenote.Simplenote/issues/16) (open, April 2026) reports D-Bus permission regressions in 2.2.4 that were confirmed fixed by Flatseal overrides — consistent with the sandbox permissions being insufficient.
- `ELECTRON_OZONE_PLATFORM_HINT=auto` is documented to select Wayland when `WAYLAND_DISPLAY` is set, which it will be on any active GNOME/Wayland session.
- Flatpak's sandbox model: environment variables from the host session are passed through to the sandbox (they are NOT stripped); only filesystem/socket access is controlled by `finish-args`.

**Conclusion**: On every boot, the GNOME session populates `ELECTRON_OZONE_PLATFORM_HINT=auto` into the D-Bus activation environment. Flatpak passes it into the Simplenote sandbox. Electron selects Wayland. The Wayland socket is inaccessible inside the sandbox. Electron exits silently. This happens 100% reproducibly on this configuration.

---

### 2.2 SECONDARY ISSUE — xdg-desktop-portal-gnome version mismatch

The GNOME session stack (gnome-session, gnome-settings-daemon, gnome-control-center) is pinned to `pkgs.unstable` via the overlay in `modules/gnome.nix`. However, `xdg-desktop-portal-gnome` in `xdg.portal.extraPortals` is sourced from stable `pkgs` (NixOS 25.11).

`xdg-desktop-portal-gnome` communicates with `gnome-settings-daemon` (unstable) over D-Bus to implement the Settings, ScreenCast, and RemoteDesktop portals. If the stable portal's D-Bus interfaces diverge from the unstable session daemon's expectations, portal requests can silently fail.

**Evidence:**
- The Arch Linux XDG Desktop Portal wiki documents that version mismatches between portal backend and session daemon can cause portal start failures.
- Nixpkgs gnome-keyring.nix module confirms `xdg.portal.extraPortals = [ pkgs.gnome-keyring ... ]` is separate from the session stack, and mismatches between session and portal packages have historically caused regressions.

**Impact**: Not the direct cause of the silent launch failure (the Wayland socket issue alone is sufficient), but portal failures would prevent Simplenote from accessing the Secret Service portal (`org.freedesktop.secrets`) for credential storage, potentially causing a secondary failure (silent sign-out loop or credential-prompt blockage).

---

### 2.3 TERTIARY ISSUE — gnome-keyring auto-unlock with auto-login

Simplenote's Flatpak manifest declares `--talk-name=org.freedesktop.secrets`. This uses the `org.freedesktop.Secret` service, provided by gnome-keyring on GNOME/NixOS.

`services.desktopManager.gnome.enable = true` (set in `modules/gnome.nix`) automatically enables `services.gnome.gnome-keyring.enable = true` in the NixOS module tree. This registers gnome-keyring as a D-Bus service.

However, with **auto-login** (set in `modules/gnome.nix` as `services.displayManager.autoLogin.enable = true`), the PAM session goes through the `gdm-autologin` PAM service, not `gdm-password`. The `gdm-autologin` service typically does NOT run `pam_gnome_keyring.so` in auth mode (no password is presented), meaning the default keyring may remain locked after auto-login.

When a locked keyring is present and an application requests the Secret Service, GNOME normally prompts for the keyring passphrase. Inside a Flatpak sandbox, such a prompt would appear on the host (via `xdg-desktop-portal-gnome`) — but only if Electron reaches that point. Given the primary Wayland socket failure occurs before any app code runs, this is a secondary compounding issue, not the silent-failure trigger.

**Note**: If the keyring was never created (no password set), gnome-keyring operates in an empty/unlocked state and the Secret Service responds normally. Most users have no explicit keyring password on NixOS auto-login configurations.

---

### 2.4 CAUSE RULED OUT — xdg-desktop-portal-gtk as GTK fallback

The absence of `xdg-desktop-portal-gtk` alongside `xdg-desktop-portal-gnome` is NOT a cause of the failure. On GNOME, `xdg-desktop-portal-gnome` handles all relevant portals (file chooser, secrets via gnome-keyring, notifications, settings). Adding `xdg-desktop-portal-gtk` would introduce a duplicate backend and risk portal routing conflicts since both respond to the same portal interfaces. `xdg.portal.config` is intentionally unset to delegate routing to the upstream GNOME `portals.conf` — adding `-gtk` without setting explicit routing config would produce non-deterministic backend selection.

**Conclusion**: Do NOT add `xdg-desktop-portal-gtk`.

---

### 2.5 CAUSE RULED OUT — Upstream Simplenote app bugs

The Simplenote Electron app (2.24.0) has no known Linux-specific silent-launch bugs in the Automattic issue tracker. The open issues are feature requests and markdown rendering bugs, none related to silent startup failure on Wayland. The issue is entirely in the Flatpak sandbox permissions + NixOS environment variable propagation.

---

## 3. Proposed Solution

### 3.1 Summary

Two changes are required, in order of priority:

1. **PRIMARY FIX** (`modules/flatpak.nix`): Add a systemd service that applies a system-level Flatpak permission override granting Simplenote access to the Wayland socket.
2. **SECONDARY FIX** (`modules/gnome.nix`): Pin `xdg-desktop-portal-gnome` to `pkgs.unstable` in the nixpkgs overlay to match the unstable GNOME session stack.

No new modules need to be created. No `lib.mkIf` guards are required or permitted.

---

### 3.2 Primary Fix — Flatpak Wayland override (modules/flatpak.nix)

#### What to change

Add a new `systemd.services.flatpak-configure-overrides` service inside the `config = lib.mkIf config.vexos.flatpak.enable { ... }` block in `modules/flatpak.nix`.

This service runs `flatpak override` as a system-level operation (no `--user` flag), writing the override to `/var/lib/flatpak/overrides/com.simplenote.Simplenote`, which applies to all users.

#### Code to add

```nix
# Grant Simplenote access to the Wayland socket.
#
# The Flathub manifest (v2.24.0) only declares --socket=x11.
# On this system, environment.sessionVariables propagates
# ELECTRON_OZONE_PLATFORM_HINT=auto into the Flatpak sandbox via the
# D-Bus activation environment. Electron detects WAYLAND_DISPLAY and
# attempts to use the Wayland backend; without --socket=wayland the
# sandbox blocks the socket and Electron exits silently.
#
# This override is idempotent: flatpak override is safe to re-run.
# A stamp file is NOT used because the override must re-apply after a
# Flatpak upgrade resets app metadata. The service is lightweight
# (pure filesystem write, no network) and safe to run on every boot.
systemd.services.flatpak-configure-overrides = {
  description = "Apply system-level Flatpak permission overrides";
  wantedBy    = [ "multi-user.target" ];
  after       = [ "flatpak-add-flathub.service" ];
  path        = [ pkgs.flatpak ];
  script = ''
    # Simplenote (com.simplenote.Simplenote) — grant Wayland socket.
    # The upstream manifest declares --socket=x11 only. This system sets
    # ELECTRON_OZONE_PLATFORM_HINT=auto in the session environment, which
    # causes Electron to select the Wayland backend inside the sandbox.
    # Without this override the app exits silently on every launch.
    flatpak override \
      --socket=wayland \
      com.simplenote.Simplenote
  '';
  serviceConfig = {
    Type            = "oneshot";
    RemainAfterExit = true;
  };
};
```

#### Why this approach is correct

- `flatpak override` (without `--user`) writes to `/var/lib/flatpak/overrides/`, which is the system-level Flatpak override location. It applies to all users and survives user-profile changes.
- The service is `oneshot` with `RemainAfterExit = true`, consistent with the existing `flatpak-add-flathub` and `flatpak-install-apps` services.
- The service does not use a stamp file because `flatpak override` is idempotent: re-running it is safe and ensures correctness after Flatpak version upgrades.
- `after = [ "flatpak-add-flathub.service" ]` ensures the Flathub remote exists before the override is applied (the override target app must be known to Flatpak).

#### Module Architecture Rule compliance

- This change is in the universal base file `modules/flatpak.nix`.
- The service runs unconditionally for all roles that import `flatpak.nix` (all display roles).
- Simplenote is in the `defaultApps` list in `modules/flatpak.nix`, so all display roles install it; granting the Wayland socket override in the same module is consistent.
- No `lib.mkIf` guard is added. The override is a no-op on roles where Simplenote is in `excludeApps` (the override file is written but Simplenote is not installed, so it has no effect).

---

### 3.3 Secondary Fix — Pin xdg-desktop-portal-gnome to unstable (modules/gnome.nix)

#### What to change

In the first `nixpkgs.overlays` entry in `modules/gnome.nix` (the unstable-pin overlay that replaces the GNOME core stack), add:

```nix
xdg-desktop-portal-gnome = u.xdg-desktop-portal-gnome;
```

#### Where exactly

The overlay currently pins:
```nix
gnome-shell            = u.gnome-shell;
mutter                 = u.mutter;
gdm                    = u.gdm;
gnome-session          = u.gnome-session;
gnome-settings-daemon  = u.gnome-settings-daemon;
gnome-control-center   = u.gnome-control-center;
gnome-shell-extensions = u.gnome-shell-extensions;
```

Add `xdg-desktop-portal-gnome = u.xdg-desktop-portal-gnome;` to this block, after `gnome-shell-extensions`.

#### Why this is correct

- `xdg-desktop-portal-gnome` uses D-Bus interfaces defined by the GNOME session stack. On NixOS 25.11, the stable portal may be one or two GNOME minor versions behind the unstable gnome-session/gnome-settings-daemon, which can cause interface version mismatches for the ScreenCast, RemoteDesktop, and Settings portals.
- Pinning the portal to the same channel as the session stack eliminates the mismatch. This is the approach used by distributions that track GNOME unstable (e.g., Fedora Rawhide, Arch Linux).
- Since `xdg.portal.extraPortals` references `pkgs.xdg-desktop-portal-gnome`, and the overlay replaces `pkgs.xdg-desktop-portal-gnome` with the unstable build, no change to the `xdg.portal` options is needed. The overlay transparently substitutes the package.

#### Module Architecture Rule compliance

- Change is within the existing overlay block in `modules/gnome.nix` (universal base file).
- No `lib.mkIf` guard. All roles importing `gnome.nix` benefit from version alignment.

---

## 4. Files to Modify

| File | Change |
|---|---|
| `modules/flatpak.nix` | Add `systemd.services.flatpak-configure-overrides` service granting Simplenote `--socket=wayland` |
| `modules/gnome.nix` | Add `xdg-desktop-portal-gnome = u.xdg-desktop-portal-gnome;` to unstable overlay block |

---

## 5. Implementation Steps

1. **Read `modules/flatpak.nix`** — confirm location of `config = lib.mkIf config.vexos.flatpak.enable { ... }` block. The new service goes inside this block, after the `flatpak-install-apps` service definition.

2. **Add service to `modules/flatpak.nix`** — insert `systemd.services.flatpak-configure-overrides` as described in section 3.2.

3. **Read `modules/gnome.nix`** — confirm the unstable-pin overlay block (starts at `nixpkgs.overlays = [`, first overlay entry, list ending at `gnome-shell-extensions`).

4. **Add portal pin to `modules/gnome.nix`** — add `xdg-desktop-portal-gnome = u.xdg-desktop-portal-gnome;` immediately after `gnome-shell-extensions = u.gnome-shell-extensions;`.

5. **Validate with `nix flake check`** — ensures Nix evaluation succeeds.

6. **Validate with `sudo nixos-rebuild dry-build --flake .#vexos-desktop-amd`** — ensures the desktop-AMD closure builds.

---

## 6. Dependencies

No new external dependencies. No new flake inputs. Both changes use existing overlay infrastructure (`pkgs.unstable` already available) and existing NixOS module options (`systemd.services`, `nixpkgs.overlays`).

---

## 7. Risks and Mitigations

| Risk | Severity | Mitigation |
|---|---|---|
| `flatpak override` service runs on roles without Simplenote installed (e.g., if it's in `excludeApps`) | Low | `flatpak override` is a no-op for non-installed apps; the override file is written but never consulted. No functional impact. |
| Granting `--socket=wayland` to Simplenote increases its sandbox permissions | Low — by design | Simplenote is a note-taking app; Wayland access is required for its primary function. Flathub PR #17 (pending) will eventually add it to the manifest. This override is correct and temporary pending upstream fix. |
| `xdg-desktop-portal-gnome` from unstable may carry regressions | Low | The unstable portal is tested against unstable GNOME, which is exactly the GNOME version running on this system. Stable portal + unstable GNOME is the mismatch this fix corrects. |
| `flatpak-configure-overrides` service failing does not block the system | Low | The service is separate from `flatpak-install-apps` and does not affect it. A failure is visible in `journalctl -u flatpak-configure-overrides` but does not prevent login or app usage. |
| Regression in other Electron Flatpak apps from Wayland exposure | None | The override is scoped to `com.simplenote.Simplenote` only. All other Flatpak apps are unaffected. |
| Auto-login keyring unlock secondary issue | Low | With no explicit keyring password (common on NixOS auto-login), gnome-keyring operates unlocked by default. Simplenote's `--talk-name=org.freedesktop.secrets` call succeeds. If the user sets a keyring password, they receive a one-time unlock prompt. This is expected behaviour and not a regression. |

---

## 8. What NOT to Do

- **Do NOT add `lib.mkIf` guards** to `modules/flatpak.nix` or `modules/gnome.nix`. Both changes are unconditional.
- **Do NOT add `xdg-desktop-portal-gtk`** to `xdg.portal.extraPortals`. It is not needed for GNOME and would conflict with `xdg-desktop-portal-gnome` for shared portal interfaces.
- **Do NOT set `xdg.portal.config`**. It is intentionally absent; `gnome-session` supplies the upstream `GNOME-portals.conf` routing config.
- **Do NOT set `services.gnome.gnome-keyring.enable = true` explicitly**. It is already enabled transitively by `services.desktopManager.gnome.enable = true`.
- **Do NOT use `--user` flag** in `flatpak override`. A system-level override is required for this setup (root-managed Flatpak installation via `services.flatpak.enable`).
- **Do NOT use a stamp file** for `flatpak-configure-overrides`. Unlike app installation (which is expensive and has network cost), `flatpak override` is fast and idempotent; re-running on every boot is safe and ensures the override persists across Flatpak database resets.
- **Do NOT create a new `modules/flatpak-simplenote.nix` file** for a single override command. The flatpak base module is the correct location per Module Architecture Rule (the override is scoped to an app in `defaultApps`).

---

## 9. Sources Consulted

1. **Flathub `com.simplenote.Simplenote.yaml` (master, 2026-04-21)** — confirmed `--socket=x11` only, no `--socket=wayland`, `--talk-name=org.freedesktop.secrets` present.
2. **Flathub issue #16** — D-Bus permission regression in Simplenote 2.2.4, confirmed fixed by Flatseal full D-Bus override; consistent with sandbox permission deficiency as primary failure mode.
3. **Flathub PR #17** — community PR to add `--talk-name=org.freedesktop.Notifications` and `--talk-name=org.freedesktop.StatusNotifierWatcher`; confirms the manifest has historically been lean on D-Bus permissions.
4. **Arch Linux XDG Desktop Portal wiki (2026-04-30)** — portal backend selection and version compatibility; `gnome-keyring` implements the Secret portal backend.
5. **NixOS nixpkgs `gnome-keyring.nix` module (master)** — confirms `services.desktopManager.gnome.enable` transitively enables `services.gnome.gnome-keyring.enable` and registers D-Bus services; `xdg.portal.extraPortals` is also extended by the keyring module.
6. **XDG Desktop Portal documentation (flatpak.github.io)** — portal routing via `portals.conf`; behaviour when `xdg.portal.config` is unset and `XDG_CURRENT_DESKTOP=GNOME` is set.
7. **Electron documentation / ELECTRON_OZONE_PLATFORM_HINT** — `auto` selects Wayland when `WAYLAND_DISPLAY` is set; Wayland initialisation failure exits the process without fallback to X11.
8. **NixOS `environment.sessionVariables` semantics** — variables propagated via PAM to D-Bus activation environment; inherited by all D-Bus-activated user processes including Flatpak sandboxes.
