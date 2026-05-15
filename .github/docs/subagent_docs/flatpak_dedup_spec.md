# Spec: Deduplicate GNOME Flatpak Install Service

**Feature:** `gnome-flatpak-install`  
**Date:** 2026-05-15  
**Authored by:** Research Phase (orchestrated by Copilot)

---

## 1. Current State Analysis

Four role modules each define an **identical systemd service body** for
`flatpak-install-gnome-apps`, differing only in the app list and one
migration-remove block present only in the desktop role.

| File | App list variable | Apps | Migration removes |
|---|---|---|---|
| `modules/gnome-desktop.nix` | `gnomeAppsToInstall = gnomeBaseApps ++ gnomeDesktopOnlyApps` | TextEditor, Loupe, Calculator, Calendar, Papers, Snapshot (6) | `org.gnome.Totem` |
| `modules/gnome-htpc.nix` | `gnomeAppsToInstall` (inline) | TextEditor, Loupe (2) | none |
| `modules/gnome-server.nix` | `gnomeAppsToInstall` (inline) | TextEditor, Loupe (2) | none |
| `modules/gnome-stateless.nix` | `gnomeAppsToInstall` (inline) | TextEditor, Loupe (2) | none |

All four files also carry a duplicate `commonExtensions` list (12 entries) in
their `let` block. That is addressed in a separate spec; this spec focuses only
on the service deduplication.

### 1.1 Hash Computation (current)

All four files compute:

```nix
gnomeAppsHash = builtins.substring 0 16
  (builtins.hashString "sha256" (lib.concatStringsSep "," gnomeAppsToInstall));
```

The hash feeds only the **install list** — not the migration removes.

### 1.2 `vexos.user.name` Usage

No usage of `config.vexos.user.name` (or the literal `"nimda"`) appears in the
service body of any of the four files. The service manipulates the system-level
Flatpak store as root; no per-user context is referenced.

### 1.3 `flatpak.nix` Dependency Chain

`modules/flatpak.nix` provides:
- `flatpak-add-flathub.service` — adds the Flathub remote (one-shot, stamped)
- `flatpak-install-apps.service` — installs the cross-role default app list (one-shot, stamped)

The GNOME service in every role file declares:
```nix
after    = [ "flatpak-install-apps.service" ];
requires = [ "flatpak-add-flathub.service" ];
```

`flatpak.nix` itself does **not** define `flatpak-install-gnome-apps`. The
`flatpak.nix` `flatpak-install-apps` service has a leaner `serviceConfig`
(only `Type = "oneshot"` and `RemainAfterExit = true`). The GNOME service adds
`Restart = "on-failure"` and `RestartSec = 60`, plus `unitConfig` burst limits.

---

## 2. Problem Definition

Approximately 50 lines of systemd unit definition are copy-pasted four times
with trivial variation. Adding a new GNOME Flatpak app or changing service
settings requires four simultaneous edits. The pattern violates the project's
"universal base + role additions" architecture.

---

## 3. Proposed Solution Architecture

### 3.1 New Module: `modules/gnome-flatpak-install.nix`

Declares two NixOS module options under `vexos.gnome.flatpakInstall`:

| Option | Type | Default | Purpose |
|---|---|---|---|
| `apps` | `listOf str` | `[]` | App IDs to install from Flathub |
| `extraRemoves` | `listOf str` | `[]` | App IDs to uninstall for migration; also included in the hash |

Defines `systemd.services.flatpak-install-gnome-apps` when
`config.services.flatpak.enable == true` AND `cfg.apps != []`.

### 3.2 Import Chain

**Option A (selected):** Import `./gnome-flatpak-install.nix` from `modules/gnome.nix`.

**Justification:**
- `gnome.nix` is the universal base for every display role that uses GNOME.
  Every role file (`gnome-desktop.nix`, `gnome-htpc.nix`, etc.) already imports
  `./gnome.nix`. Importing the helper there makes the options available to all
  roles without each file needing an additional explicit import.
- With `apps = []` (the default), the `config` block inside the helper is
  guarded by `lib.mkIf` and produces **no output** — no service, no side
  effects. Safe to include in the base.
- Follows the project rule: "a configuration-*.nix expresses its role entirely
  through its import list." The role files express GNOME Flatpak behaviour by
  setting options, not by importing extra files.

**Option B (rejected):** Each role file imports `./gnome-flatpak-install.nix`
explicitly. More verbose, no architectural benefit since it's always needed by
every GNOME role.

### 3.3 Hash Migration Note

For **htpc / server / stateless** roles:
- New hash = `sha256(apps ++ extraRemoves)` = `sha256(["org.gnome.TextEditor","org.gnome.Loupe"] ++ [])` = same string as before → **stamp unchanged → no re-run**.

For the **desktop** role:
- Old hash = `sha256("org.gnome.TextEditor,org.gnome.Loupe,org.gnome.Calculator,org.gnome.Calendar,org.gnome.Papers,org.gnome.Snapshot")`
- New hash = `sha256("org.gnome.TextEditor,org.gnome.Loupe,org.gnome.Calculator,org.gnome.Calendar,org.gnome.Papers,org.gnome.Snapshot,org.gnome.Totem")` (Totem added to `extraRemoves`)
- Hash **changes** → service re-runs **once** on next boot after migration.
- The re-run is safe: Totem will have already been removed; the re-run simply
  re-installs the six apps (idempotent — Flatpak skips already-installed apps)
  and writes the new stamp.
- **Acceptable.** Document in role file comment.

---

## 4. Exact Shared Service Body (verbatim from gnome-htpc.nix — canonical baseline)

```nix
systemd.services.flatpak-install-gnome-apps = lib.mkIf config.services.flatpak.enable {
  description = "Install GNOME Flatpak apps (once)";
  wantedBy    = [ "multi-user.target" ];
  after       = [ "flatpak-install-apps.service" ];
  requires    = [ "flatpak-add-flathub.service" ];
  path        = [ pkgs.flatpak ];
  script = ''
    STAMP="/var/lib/flatpak/.gnome-apps-installed-${gnomeAppsHash}"
    if [ -f "$STAMP" ]; then exit 0; fi

    # Require at least 1.5 GB free before attempting installs.
    AVAIL_MB=$(df /var/lib/flatpak --output=avail -BM 2>/dev/null | tail -1 | tr -d 'M ' || echo 0)
    if [ "$AVAIL_MB" -lt 1536 ]; then
      echo "flatpak: only ''${AVAIL_MB} MB free — need 1536 MB; skipping this boot"
      exit 0
    fi

    flatpak install --noninteractive --assumeyes flathub \
      ${lib.concatStringsSep " \\\n        " gnomeAppsToInstall}

    rm -f /var/lib/flatpak/.gnome-apps-installed \
          /var/lib/flatpak/.gnome-apps-installed-*
    touch "$STAMP"
  '';
  unitConfig = {
    StartLimitIntervalSec = 600;
    StartLimitBurst       = 10;
  };
  serviceConfig = {
    Type            = "oneshot";
    RemainAfterExit = true;
    Restart         = "on-failure";
    RestartSec      = 60;
  };
};
```

**Desktop-only addition inside `script` (before the `flatpak install` line):**

```sh
# Migration: uninstall Totem — mpv is the designated player.
if flatpak list --app --columns=application 2>/dev/null | grep -qx "org.gnome.Totem"; then
  echo "flatpak: removing org.gnome.Totem (desktop role uses mpv)"
  flatpak uninstall --noninteractive --assumeyes org.gnome.Totem || true
fi
```

---

## 5. Complete Proposed `modules/gnome-flatpak-install.nix`

```nix
# modules/gnome-flatpak-install.nix
# Shared systemd service for GNOME-role Flatpak app installation.
#
# Declares options.vexos.gnome.flatpakInstall.{apps,extraRemoves}.
# Each gnome-<role>.nix sets those options; this module generates the
# shared service body so the ~50-line definition is not copy-pasted four times.
#
# Activation condition: services.flatpak.enable == true AND apps != [].
# When apps = [] (the default) no service is defined.
{ config, pkgs, lib, ... }:
let
  cfg = config.vexos.gnome.flatpakInstall;

  # Hash of desired apps + migration removes, baked in at Nix evaluation time.
  # Including extraRemoves ensures the stamp changes whenever the remove list
  # changes, forcing a re-run that cleans up the unwanted apps.
  appsHash = builtins.substring 0 16
    (builtins.hashString "sha256"
      (lib.concatStringsSep "," (cfg.apps ++ cfg.extraRemoves)));
in
{
  options.vexos.gnome.flatpakInstall = {
    apps = lib.mkOption {
      type        = lib.types.listOf lib.types.str;
      default     = [];
      description = "GNOME Flatpak app IDs to install from Flathub for this role.";
    };

    extraRemoves = lib.mkOption {
      type        = lib.types.listOf lib.types.str;
      default     = [];
      description = ''
        App IDs to uninstall for migration (apps that were previously installed
        but are no longer desired for this role).  Included in the stamp hash so
        removal is triggered exactly once when the list changes.
      '';
    };
  };

  config = lib.mkIf (config.services.flatpak.enable && cfg.apps != []) {
    systemd.services.flatpak-install-gnome-apps = {
      description = "Install GNOME Flatpak apps (once)";
      wantedBy    = [ "multi-user.target" ];
      after       = [ "flatpak-install-apps.service" ];
      requires    = [ "flatpak-add-flathub.service" ];
      path        = [ pkgs.flatpak ];
      script = ''
        STAMP="/var/lib/flatpak/.gnome-apps-installed-${appsHash}"
        if [ -f "$STAMP" ]; then exit 0; fi

        # Require at least 1.5 GB free before attempting installs.
        # Exit 0 (not 1) so the switch doesn't fail — stamp is not written,
        # so the service will retry on the next boot.
        AVAIL_MB=$(df /var/lib/flatpak --output=avail -BM 2>/dev/null | tail -1 | tr -d 'M ' || echo 0)
        if [ "$AVAIL_MB" -lt 1536 ]; then
          echo "flatpak: only ''${AVAIL_MB} MB free — need 1536 MB; skipping this boot"
          exit 0
        fi

        ${lib.concatMapStrings (app: ''
          if flatpak list --app --columns=application 2>/dev/null | grep -qx "${app}"; then
            echo "flatpak: removing ${app} (migration)"
            flatpak uninstall --noninteractive --assumeyes ${app} || true
          fi
        '') cfg.extraRemoves}
        flatpak install --noninteractive --assumeyes flathub \
          ${lib.concatStringsSep " \\\n          " cfg.apps}

        rm -f /var/lib/flatpak/.gnome-apps-installed \
              /var/lib/flatpak/.gnome-apps-installed-*
        touch "$STAMP"
      '';
      unitConfig = {
        StartLimitIntervalSec = 600;
        StartLimitBurst       = 10;
      };
      serviceConfig = {
        Type            = "oneshot";
        RemainAfterExit = true;
        Restart         = "on-failure";
        RestartSec      = 60;
      };
    };
  };
}
```

---

## 6. Changes to `modules/gnome.nix`

Add one import at the top of the imports list:

```nix
imports = [ ./gnome-flatpak-install.nix ];
```

`gnome.nix` currently has no `imports` attribute. Add one. The file opens with
`{ config, pkgs, lib, ... }:` followed directly by `{`. Insert:

```nix
{ config, pkgs, lib, ... }:
{
  imports = [ ./gnome-flatpak-install.nix ];

  # ... rest of file unchanged ...
```

---

## 7. Exact Changes to Each Role File

### 7.1 `modules/gnome-desktop.nix`

**Remove** the entire `let` block declarations that are no longer needed locally:

```nix
  gnomeBaseApps = [ ... ];
  gnomeDesktopOnlyApps = [ ... ];
  gnomeAppsToInstall = gnomeBaseApps ++ gnomeDesktopOnlyApps;
  gnomeAppsHash = builtins.substring 0 16
    (builtins.hashString "sha256" (lib.concatStringsSep "," gnomeAppsToInstall));
```

**Remove** the entire `systemd.services.flatpak-install-gnome-apps` block
(approximately lines 153–204 in the current file).

**Add** in the top-level attribute set (after the dconf block):

```nix
  # ── GNOME default app Flatpaks (desktop role) ─────────────────────────────
  # Defined by modules/gnome-flatpak-install.nix (imported via gnome.nix).
  # Note: stamp hash changes from the pre-migration value (extraRemoves adds
  # org.gnome.Totem to the hash string) — service re-runs once on next boot;
  # re-run is idempotent.
  vexos.gnome.flatpakInstall = {
    apps = [
      "org.gnome.TextEditor"
      "org.gnome.Loupe"
      "org.gnome.Calculator"
      "org.gnome.Calendar"
      "org.gnome.Papers"
      "org.gnome.Snapshot"
    ];
    extraRemoves = [ "org.gnome.Totem" ];
  };
```

The `commonExtensions` let binding is still required by the dconf block — **do not remove it**.

### 7.2 `modules/gnome-htpc.nix`

**Remove** from `let` block:

```nix
  gnomeAppsToInstall = [ ... ];
  gnomeAppsHash = builtins.substring 0 16
    (builtins.hashString "sha256" (lib.concatStringsSep "," gnomeAppsToInstall));
```

**Remove** the entire `systemd.services.flatpak-install-gnome-apps` block.

**Add** after the dconf block:

```nix
  # ── GNOME default app Flatpaks (htpc role) ────────────────────────────────
  vexos.gnome.flatpakInstall.apps = [
    "org.gnome.TextEditor"
    "org.gnome.Loupe"
  ];
```

The `commonExtensions` let binding is still required — **do not remove it**.

### 7.3 `modules/gnome-server.nix`

**Remove** from `let` block:

```nix
  gnomeAppsToInstall = [ ... ];
  gnomeAppsHash = builtins.substring 0 16
    (builtins.hashString "sha256" (lib.concatStringsSep "," gnomeAppsToInstall));
```

**Remove** the entire `systemd.services.flatpak-install-gnome-apps` block.

**Add** after the dconf block:

```nix
  # ── GNOME default app Flatpaks (server role) ──────────────────────────────
  vexos.gnome.flatpakInstall.apps = [
    "org.gnome.TextEditor"
    "org.gnome.Loupe"
  ];
```

### 7.4 `modules/gnome-stateless.nix`

**Remove** from `let` block:

```nix
  gnomeAppsToInstall = [ ... ];
  gnomeAppsHash = builtins.substring 0 16
    (builtins.hashString "sha256" (lib.concatStringsSep "," gnomeAppsToInstall));
```

**Remove** the entire `systemd.services.flatpak-install-gnome-apps` block.

**Add** after the dconf block:

```nix
  # ── GNOME default app Flatpaks (stateless role) ───────────────────────────
  vexos.gnome.flatpakInstall.apps = [
    "org.gnome.TextEditor"
    "org.gnome.Loupe"
  ];
```

---

## 8. Files to Create / Modify

| Action | File |
|---|---|
| **Create** | `modules/gnome-flatpak-install.nix` |
| **Modify** | `modules/gnome.nix` (add `imports` list) |
| **Modify** | `modules/gnome-desktop.nix` (remove service + let vars, add option assignment) |
| **Modify** | `modules/gnome-htpc.nix` (remove service + let vars, add option assignment) |
| **Modify** | `modules/gnome-server.nix` (remove service + let vars, add option assignment) |
| **Modify** | `modules/gnome-stateless.nix` (remove service + let vars, add option assignment) |

---

## 9. Risk Assessment

| Risk | Severity | Mitigation |
|---|---|---|
| Desktop stamp hash changes → one-time re-run | Low | Re-run is idempotent; documented in comment |
| `lib.concatMapStrings` generates empty string when `extraRemoves = []` | None | Nix evaluates correctly; empty interpolation in shell is a no-op |
| Circular import (gnome.nix imports helper, helper references gnome.nix options) | None | Helper only references `config.services.flatpak.enable` (from NixOS core) and its own options |
| Role files omit `pkgs` arg after removing service | None | `pkgs` is still used in environment.systemPackages (desktop) and dconf (all); arg must remain |

---

## 10. Validation Steps

After implementation, the review phase must confirm:

1. `nix flake check` passes without evaluation errors
2. `sudo nixos-rebuild dry-build --flake .#vexos-desktop-amd` succeeds — the `flatpak-install-gnome-apps` service appears in the system closure with the 6-app install list
3. `sudo nixos-rebuild dry-build --flake .#vexos-desktop-nvidia` succeeds
4. `sudo nixos-rebuild dry-build --flake .#vexos-desktop-vm` succeeds
5. The service is absent in the VM closure (Flatpak disabled on VM roles — `vexos.flatpak.enable = false`)
6. No duplicate definition of `flatpak-install-gnome-apps` in any module
7. `hardware-configuration.nix` is NOT committed
8. `system.stateVersion` is unchanged
