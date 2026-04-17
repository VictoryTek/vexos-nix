# Spec: Remove org.gnome.Calculator and org.gnome.Calendar from Non-Desktop Roles

**Feature:** remove-gnome-apps-non-desktop  
**Date:** 2026-04-17  
**Status:** Draft

---

## 1. Current State Analysis

### 1.1 The GNOME Flatpak Install Service

`modules/gnome.nix` defines a systemd oneshot service named
`flatpak-install-gnome-apps`. It runs once on first boot (guarded by the
stamp file `/var/lib/flatpak/.gnome-apps-installed`) and unconditionally
installs all six GNOME apps on **every role**:

```
org.gnome.TextEditor
org.gnome.Calculator
org.gnome.Calendar
org.gnome.Loupe
org.gnome.Papers
org.gnome.Totem
```

The stamp is a **static path** — once written it never changes, so the
service never re-runs on existing systems regardless of configuration
changes.

### 1.2 Role Awareness

`modules/branding.nix` declares `options.vexos.branding.role` as a
`lib.types.enum [ "desktop" "htpc" "server" "stateless" ]` with a default
of `"desktop"`. Each configuration file sets it explicitly:

| Configuration file            | `vexos.branding.role` |
|-------------------------------|-----------------------|
| `configuration-desktop.nix`   | `"desktop"`           |
| `configuration-htpc.nix`      | `"htpc"`              |
| `configuration-server.nix`    | `"server"`            |
| `configuration-stateless.nix` | `"stateless"`         |

The option is available as `config.vexos.branding.role` in any NixOS
module that receives the `config` argument.

### 1.3 Existing Flatpak Pattern

`modules/flatpak.nix` already uses a **hash-based stamp** for the main
`flatpak-install-apps` service. The hash is derived from the final
`appsToInstall` list so that any change to `excludeApps` or `extraApps`
changes the stamp path, invalidating it and causing the service to re-run.
The re-run removes newly excluded apps and installs newly added ones.

`gnome.nix`'s service pre-dates this pattern and uses the simpler static
stamp. Adopting the hash-based stamp for the GNOME service is the
mechanism that enables migration of already-deployed systems.

### 1.4 Module Structure

`modules/gnome.nix` is a **flat module** (no `options`/`config` split).
All attributes are declared directly in the module body. A `let` block
placed before the opening `{` is idiomatic and fully supported.

---

## 2. Problem Definition

`org.gnome.Calculator` and `org.gnome.Calendar` are productivity apps
appropriate for a general-purpose desktop. They serve no purpose on:

- **HTPC** — a media-centre role focused on streaming and playback
- **Server** — a headless-adjacent role with no productivity use case
- **Stateless** — a minimal ephemeral role

The apps should remain on the **Desktop** role only. Because the current
stamp is static and the install script is unconditional, there is no
mechanism today to skip or remove them on non-desktop roles.

---

## 3. Proposed Solution

### 3.1 Approach Selected: Conditional App List in `modules/gnome.nix` (Self-Contained)

This change is made **entirely within `modules/gnome.nix`**. No other
file needs to be modified.

**Rationale for choosing this over alternatives:**

| Approach | Verdict |
|----------|---------|
| (a) `lib.optionalString` inline in shell script | Works but embeds logic in an untyped string; harder to read |
| (b) New `vexos.gnome.desktopOnlyApps` option | Over-engineered; adds option namespace for a two-app exclusion |
| (c) `lib.concatStringsSep` to build app list | Part of the chosen approach — used at Nix level, not in shell |
| (d) Remove from `gnome.nix`, add via `extraApps` in `configuration-desktop.nix` | Requires touching four files; does not handle migration uninstall automatically |
| **Chosen: conditional list + hash stamp + migration loop in `gnome.nix`** | Self-contained, consistent with `flatpak.nix` pattern, handles new and existing installs |

### 3.2 What the Change Does

1. **Adds a `let` block** at the top of `gnome.nix` that builds the app
   list in Nix, not in shell:
   - `gnomeBaseApps` — apps installed on all roles
   - `gnomeDesktopOnlyApps` — apps installed only on the Desktop role
   - `gnomeAppsToInstall` — union of the above using `lib.optionals`
   - `gnomeAppsHash` — 16-char SHA-256 prefix of the joined app list
     (same pattern as `flatpak.nix`)

2. **Changes the stamp** from the fixed path
   `/var/lib/flatpak/.gnome-apps-installed` to the dynamic path
   `/var/lib/flatpak/.gnome-apps-installed-<hash>`.

   - On **desktop**: the hash includes Calculator and Calendar → different
     hash from non-desktop → no collision.
   - On **htpc/server/stateless**: the hash excludes Calculator and
     Calendar → different from old stamp (which was static without hash) →
     service re-runs once on the next `nixos-rebuild switch`.

3. **Adds a migration uninstall loop** (inside a `lib.optionalString` that
   activates only when `role != "desktop"`) that runs **before** the
   install block, removing Calculator and Calendar if they are present from
   a prior install.

4. **Cleans up old stamps** (`rm -f .gnome-apps-installed .gnome-apps-installed-*`)
   before writing the new hash stamp, preventing stale stamps from
   accumulating across rebuilds.

---

## 4. Implementation Steps

### 4.1 File: `modules/gnome.nix`

**Step 1 — Replace the module opening with a `let` block**

Current opening line:
```nix
{ config, pkgs, lib, ... }:
{
```

Replace with:
```nix
{ config, pkgs, lib, ... }:
let
  # ── GNOME Flatpak app lists ────────────────────────────────────────────────
  # Apps installed on every role.
  gnomeBaseApps = [
    "org.gnome.TextEditor"
    "org.gnome.Loupe"
    "org.gnome.Papers"
    "org.gnome.Totem"
  ];

  # Apps installed only on the Desktop role.
  gnomeDesktopOnlyApps = [
    "org.gnome.Calculator"
    "org.gnome.Calendar"
  ];

  # Final list for this role.
  gnomeAppsToInstall =
    gnomeBaseApps
    ++ lib.optionals (config.vexos.branding.role == "desktop") gnomeDesktopOnlyApps;

  # Short hash of the app list — changes when the list changes, invalidating
  # the old stamp so the service re-runs and syncs (same pattern as flatpak.nix).
  gnomeAppsHash = builtins.substring 0 16
    (builtins.hashString "sha256" (lib.concatStringsSep "," gnomeAppsToInstall));
in
{
```

**Step 2 — Replace the `flatpak-install-gnome-apps` service `script` attribute**

Current script:
```nix
    script = ''
      if [ -f /var/lib/flatpak/.gnome-apps-installed ]; then exit 0; fi
      flatpak install --noninteractive --assumeyes flathub \
        org.gnome.TextEditor \
        org.gnome.Calculator \
        org.gnome.Calendar \
        org.gnome.Loupe \
        org.gnome.Papers \
        org.gnome.Totem
      touch /var/lib/flatpak/.gnome-apps-installed
    '';
```

Replace with:
```nix
    script = ''
      STAMP="/var/lib/flatpak/.gnome-apps-installed-${gnomeAppsHash}"
      if [ -f "$STAMP" ]; then exit 0; fi

      ${lib.optionalString (config.vexos.branding.role != "desktop") ''
      # Migration: uninstall desktop-only apps from non-desktop roles.
      for app in ${lib.concatStringsSep " " gnomeDesktopOnlyApps}; do
        if flatpak list --app --columns=application 2>/dev/null | grep -qx "$app"; then
          echo "flatpak: removing desktop-only app $app (role: ${config.vexos.branding.role})"
          flatpak uninstall --noninteractive --assumeyes "$app" || true
        fi
      done
      ''}
      flatpak install --noninteractive --assumeyes flathub \
        ${lib.concatStringsSep " \\\n        " gnomeAppsToInstall}

      rm -f /var/lib/flatpak/.gnome-apps-installed \
            /var/lib/flatpak/.gnome-apps-installed-*
      touch "$STAMP"
    '';
```

### 4.2 No Other Files Modified

All four configuration files (`configuration-desktop.nix`,
`configuration-htpc.nix`, `configuration-server.nix`,
`configuration-stateless.nix`) are unchanged.

---

## 5. Files Modified

| File | Change |
|------|--------|
| `modules/gnome.nix` | Add `let` block with conditional app list; replace service `script` with hash-stamped, role-aware version |

---

## 6. Expected Behaviour After Change

### New installations (no prior stamp)

| Role | Calculator installed? | Calendar installed? |
|------|-----------------------|---------------------|
| desktop | Yes | Yes |
| htpc | No | No |
| server | No | No |
| stateless | No | No |

### Existing installations (prior static stamp `/var/lib/flatpak/.gnome-apps-installed` exists)

The new hash-based stamp path does **not** match the old static path. On
the next `nixos-rebuild switch` and reboot (or systemd daemon-reload +
service restart), the service will:

1. Find no matching hash stamp → proceed.
2. (Non-desktop only) Run the migration uninstall loop → remove Calculator
   and Calendar if present.
3. Install the role-appropriate app list.
4. Delete all old stamps and write the new hash stamp.

### Desktop role

The desktop hash includes Calculator and Calendar. The old static stamp
does not match the new hash path, so the service re-runs once but finds
Calculator and Calendar already installed (from the old run) and skips
them. All apps are confirmed installed.

---

## 7. Risks and Mitigations

| Risk | Likelihood | Mitigation |
|------|-----------|------------|
| Circular dependency: `config.vexos.branding.role` used in `gnome.nix` before `branding.nix` is evaluated | Low | NixOS module evaluation is lazy; all modules are merged before any attribute is forced. `branding.nix` has no dependency on `gnome.nix` outputs, so no cycle exists. |
| `flatpak` binary not in PATH during migration uninstall | Low | The service already declares `path = [ pkgs.flatpak ]`; this covers both the install and uninstall commands. |
| Hash collision between desktop and non-desktop stamp files | Negligible | Hash is SHA-256 of a different input string per role; collision probability is astronomically low. |
| Service re-runs on desktop if prior static stamp exists | Expected/benign | The re-run finds all apps already installed, skips them, and writes the new stamp. One spurious service execution on the first rebuild; no app changes occur. |
| `rm -f .gnome-apps-installed-*` glob removes too much | Low | The glob is scoped to a specific prefix in `/var/lib/flatpak/`. Only stamps written by this service match the prefix. Verified safe by the `flatpak.nix` precedent using the same pattern. |
| Nix evaluation error if `lib.optionals` or `builtins.hashString` behaves unexpectedly | Low | Both are stable, widely-used Nix builtins present since Nix 2.0. `lib.optionals` is part of nixpkgs `lib` with no known issues. |

---

## 8. Out of Scope

- `org.gnome.Camera` — confirmed absent from the current config; no action needed.
- Removing any of the four base apps (`TextEditor`, `Loupe`, `Papers`, `Totem`) from non-desktop roles — not requested.
- Adding a formal `vexos.gnome.*` option namespace — unjustified for a two-app change.
