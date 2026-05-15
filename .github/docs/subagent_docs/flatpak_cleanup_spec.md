# Spec: Remove Dead Flatpak Migration Cleanup Blocks

**Feature name:** `flatpak_cleanup`  
**Status:** Ready for implementation  
**Date:** 2026-05-15  

---

## 1. Current State Analysis

### 1.1 Stamp / Hash Mechanism

Every `flatpak-install-gnome-apps` service uses a stamp file whose name encodes a
16-character SHA-256 prefix of `gnomeAppsToInstall`:

```
STAMP="/var/lib/flatpak/.gnome-apps-installed-${gnomeAppsHash}"
if [ -f "$STAMP" ]; then exit 0; fi
```

The hash is computed **only** over `gnomeAppsToInstall`.  Migration/cleanup
lines inside the script are invisible to the hash.  Therefore removing them
does **not** change the stamp path and does **not** cause the service to
re-run on hosts that already have a valid stamp.

### 1.2 Apps each role installs

| Role | `gnomeAppsToInstall` |
|------|----------------------|
| desktop | `TextEditor`, `Loupe`, `Calculator`, `Calendar`, `Papers`, `Snapshot` |
| htpc | `TextEditor`, `Loupe` |
| server | `TextEditor`, `Loupe` |
| stateless | `TextEditor`, `Loupe` |

### 1.3 Migration blocks present in each file

#### `modules/gnome-htpc.nix` (inside `script = ''...''`)

Block A — desktop-only apps (~lines 129–136):
```sh
      # Migration: uninstall desktop-only apps from the htpc role.
      for app in org.gnome.Calculator org.gnome.Calendar org.gnome.Papers org.gnome.Snapshot; do
        if flatpak list --app --columns=application 2>/dev/null | grep -qx "$app"; then
          echo "flatpak: removing desktop-only app $app (role: htpc)"
          flatpak uninstall --noninteractive --assumeyes "$app" || true
        fi
      done
```

Block B — Totem (~lines 138–143):
```sh
      # Migration: uninstall Totem on HTPC — mpv is the designated player.
      if flatpak list --app --columns=application 2>/dev/null | grep -qx "org.gnome.Totem"; then
        echo "flatpak: removing org.gnome.Totem (htpc role uses mpv)"
        flatpak uninstall --noninteractive --assumeyes org.gnome.Totem || true
      fi
```

Above the service declaration (~lines 111–113), a stale comment:
```nix
  # ── GNOME default app Flatpaks (htpc role) ────────────────────────────────
  # Includes migration cleanup for both the desktop-only apps and Totem,
  # which may have been installed under previous configurations.
```

#### `modules/gnome-server.nix` (inside `script = ''...''`)

Block A — desktop-only apps (~lines 129–136):
```sh
      # Migration: uninstall desktop-only apps from the server role.
      for app in org.gnome.Calculator org.gnome.Calendar org.gnome.Papers org.gnome.Snapshot; do
        if flatpak list --app --columns=application 2>/dev/null | grep -qx "$app"; then
          echo "flatpak: removing desktop-only app $app (role: server)"
          flatpak uninstall --noninteractive --assumeyes "$app" || true
        fi
      done
```

Block B — Totem (~lines 138–144):
```sh
      # Migration: uninstall Totem — mpv is the designated player.
      if flatpak list --app --columns=application 2>/dev/null | grep -qx "org.gnome.Totem"; then
        echo "flatpak: removing org.gnome.Totem (server role uses mpv)"
        flatpak uninstall --noninteractive --assumeyes org.gnome.Totem || true
      fi
```

Above the service declaration (~lines 113–116), a stale comment:
```nix
  # ── GNOME default app Flatpaks (server role) ──────────────────────────────
  # Includes migration cleanup for desktop-only apps that may have been
  # installed under previous configurations.
```

#### `modules/gnome-stateless.nix` (inside `script = ''...''`)

Block A — desktop-only apps (~lines 129–136):
```sh
      # Migration: uninstall desktop-only apps from the stateless role.
      for app in org.gnome.Calculator org.gnome.Calendar org.gnome.Papers org.gnome.Snapshot; do
        if flatpak list --app --columns=application 2>/dev/null | grep -qx "$app"; then
          echo "flatpak: removing desktop-only app $app (role: stateless)"
          flatpak uninstall --noninteractive --assumeyes "$app" || true
        fi
      done
```

Block B — Totem (~lines 138–143):
```sh
      # Migration: uninstall Totem — mpv is the designated player.
      if flatpak list --app --columns=application 2>/dev/null | grep -qx "org.gnome.Totem"; then
        echo "flatpak: removing org.gnome.Totem (stateless role uses mpv)"
        flatpak uninstall --noninteractive --assumeyes org.gnome.Totem || true
      fi
```

Above the service declaration (~lines 115–118), a stale comment:
```nix
  # ── GNOME default app Flatpaks (stateless role) ───────────────────────────
  # Includes migration cleanup for desktop-only apps that may have been
  # installed under previous configurations.
```

#### `modules/gnome-desktop.nix` — **NOT changing**

The desktop role contains only the Totem migration block (no Calculator/etc
cleanup, because desktop IS the role that installs those apps).  The Totem
removal is legitimate on desktop: the desktop role plausibly had Totem before
mpv became the designated player.  Leave as-is.

---

## 2. Why Removal Is Safe

### 2.1 `Calculator / Calendar / Papers / Snapshot` loop

These four apps appear **only** in `gnome-desktop.nix`'s `gnomeDesktopOnlyApps`
list.  They have **never** been in the htpc/server/stateless `gnomeAppsToInstall`
list, verified by reading the current files.

Possible host states at the time of this cleanup:

| Host state | Effect of removal |
|---|---|
| Never had old config; new install | Apps were never installed → removal is already a no-op |
| Had old config; migration already ran (stamp exists) | Stamp prevents service re-run → no change in behaviour |
| Had old config; migration not yet run (stamp absent) | Apps were never installed via these roles → removal is still a no-op |

In every case removing the loop produces identical runtime behaviour.

### 2.2 `Totem` loop (htpc / server / stateless only)

Totem does not appear in the `gnomeAppsToInstall` list of any of these three
roles in the current codebase.  If Totem was ever transiently installed (e.g.,
via the shared GNOME base package or an older `flatpak.nix` default list), that
migration would have already fired on any host that ran the service after the
loop was added.  The stamp (computed from `gnomeAppsToInstall`, which never
included Totem) would not change on removal of the loop.

The `flatpak.nix` `defaultApps` list has never contained `org.gnome.Totem`.
The `gnome.nix` base module does not install any Flatpaks directly.  There is
no credible vector by which htpc/server/stateless hosts would have acquired
Totem through the managed configuration — only through direct user action, which
is out-of-scope for managed migration.

The **desktop** role retains its Totem loop, which is the one role where Totem
plausibly existed under an earlier configuration.

### 2.3 Stamp hash is unchanged

`gnomeAppsHash` hashes `gnomeAppsToInstall` only.  The migration shell blocks
are not part of the hash input.  Removing them does not alter the stamp path.
No existing stamp is invalidated; no host will unexpectedly re-run the service.

---

## 3. Decision: Option A

**Option A — Simply delete both cleanup loops from htpc, server, stateless.**

Option B (stamp-guarded retention) would preserve functionality that is already
a guaranteed no-op.  There is no value in keeping dead shell code; it adds
confusion for future maintainers and was called out in the full-code-analysis as
dead code.  The desktop role's single Totem loop provides a working reference
pattern if a similar migration is ever needed again.

---

## 4. Implementation Steps

### Step 1 — `modules/gnome-htpc.nix`

**a)** Replace the stale two-line comment above the service:

```nix
  # ── GNOME default app Flatpaks (htpc role) ────────────────────────────────
  # Includes migration cleanup for both the desktop-only apps and Totem,
  # which may have been installed under previous configurations.
  systemd.services.flatpak-install-gnome-apps = lib.mkIf config.services.flatpak.enable {
```

→

```nix
  # ── GNOME default app Flatpaks (htpc role) ────────────────────────────────
  systemd.services.flatpak-install-gnome-apps = lib.mkIf config.services.flatpak.enable {
```

**b)** Remove Block A and Block B from inside the `script = ''...''` string.
The content immediately before Block A is the disk-space guard block, and the
content immediately after Block B is the `flatpak install` command.

Remove (exact text):

```sh
      # Migration: uninstall desktop-only apps from the htpc role.
      for app in org.gnome.Calculator org.gnome.Calendar org.gnome.Papers org.gnome.Snapshot; do
        if flatpak list --app --columns=application 2>/dev/null | grep -qx "$app"; then
          echo "flatpak: removing desktop-only app $app (role: htpc)"
          flatpak uninstall --noninteractive --assumeyes "$app" || true
        fi
      done

      # Migration: uninstall Totem on HTPC — mpv is the designated player.
      if flatpak list --app --columns=application 2>/dev/null | grep -qx "org.gnome.Totem"; then
        echo "flatpak: removing org.gnome.Totem (htpc role uses mpv)"
        flatpak uninstall --noninteractive --assumeyes org.gnome.Totem || true
      fi

```

(Note: include the trailing blank line so the `flatpak install` command that
follows abuts the disk-space guard cleanly, matching the style in
`gnome-desktop.nix`.)

---

### Step 2 — `modules/gnome-server.nix`

**a)** Replace the stale two-line comment:

```nix
  # ── GNOME default app Flatpaks (server role) ──────────────────────────────
  # Includes migration cleanup for desktop-only apps that may have been
  # installed under previous configurations.
  systemd.services.flatpak-install-gnome-apps = lib.mkIf config.services.flatpak.enable {
```

→

```nix
  # ── GNOME default app Flatpaks (server role) ──────────────────────────────
  systemd.services.flatpak-install-gnome-apps = lib.mkIf config.services.flatpak.enable {
```

**b)** Remove Block A and Block B from inside `script = ''...''`:

```sh
      # Migration: uninstall desktop-only apps from the server role.
      for app in org.gnome.Calculator org.gnome.Calendar org.gnome.Papers org.gnome.Snapshot; do
        if flatpak list --app --columns=application 2>/dev/null | grep -qx "$app"; then
          echo "flatpak: removing desktop-only app $app (role: server)"
          flatpak uninstall --noninteractive --assumeyes "$app" || true
        fi
      done

      # Migration: uninstall Totem — mpv is the designated player.
      if flatpak list --app --columns=application 2>/dev/null | grep -qx "org.gnome.Totem"; then
        echo "flatpak: removing org.gnome.Totem (server role uses mpv)"
        flatpak uninstall --noninteractive --assumeyes org.gnome.Totem || true
      fi

```

---

### Step 3 — `modules/gnome-stateless.nix`

**a)** Replace the stale two-line comment:

```nix
  # ── GNOME default app Flatpaks (stateless role) ───────────────────────────
  # Includes migration cleanup for desktop-only apps that may have been
  # installed under previous configurations.
  systemd.services.flatpak-install-gnome-apps = lib.mkIf config.services.flatpak.enable {
```

→

```nix
  # ── GNOME default app Flatpaks (stateless role) ───────────────────────────
  systemd.services.flatpak-install-gnome-apps = lib.mkIf config.services.flatpak.enable {
```

**b)** Remove Block A and Block B from inside `script = ''...''`:

```sh
      # Migration: uninstall desktop-only apps from the stateless role.
      for app in org.gnome.Calculator org.gnome.Calendar org.gnome.Papers org.gnome.Snapshot; do
        if flatpak list --app --columns=application 2>/dev/null | grep -qx "$app"; then
          echo "flatpak: removing desktop-only app $app (role: stateless)"
          flatpak uninstall --noninteractive --assumeyes "$app" || true
        fi
      done

      # Migration: uninstall Totem — mpv is the designated player.
      if flatpak list --app --columns=application 2>/dev/null | grep -qx "org.gnome.Totem"; then
        echo "flatpak: removing org.gnome.Totem (stateless role uses mpv)"
        flatpak uninstall --noninteractive --assumeyes org.gnome.Totem || true
      fi

```

---

### Step 4 — `modules/gnome-desktop.nix`

**No changes.**  The Totem migration loop in the desktop role is retained.

---

## 5. Expected Diffs (Abbreviated)

### `modules/gnome-htpc.nix`

```diff
-  # ── GNOME default app Flatpaks (htpc role) ────────────────────────────────
-  # Includes migration cleanup for both the desktop-only apps and Totem,
-  # which may have been installed under previous configurations.
+  # ── GNOME default app Flatpaks (htpc role) ────────────────────────────────
   systemd.services.flatpak-install-gnome-apps = lib.mkIf config.services.flatpak.enable {
```

```diff
       fi
 
-      # Migration: uninstall desktop-only apps from the htpc role.
-      for app in org.gnome.Calculator org.gnome.Calendar org.gnome.Papers org.gnome.Snapshot; do
-        if flatpak list --app --columns=application 2>/dev/null | grep -qx "$app"; then
-          echo "flatpak: removing desktop-only app $app (role: htpc)"
-          flatpak uninstall --noninteractive --assumeyes "$app" || true
-        fi
-      done
-
-      # Migration: uninstall Totem on HTPC — mpv is the designated player.
-      if flatpak list --app --columns=application 2>/dev/null | grep -qx "org.gnome.Totem"; then
-        echo "flatpak: removing org.gnome.Totem (htpc role uses mpv)"
-        flatpak uninstall --noninteractive --assumeyes org.gnome.Totem || true
-      fi
-
       flatpak install --noninteractive --assumeyes flathub \
```

### `modules/gnome-server.nix`

```diff
-  # ── GNOME default app Flatpaks (server role) ──────────────────────────────
-  # Includes migration cleanup for desktop-only apps that may have been
-  # installed under previous configurations.
+  # ── GNOME default app Flatpaks (server role) ──────────────────────────────
   systemd.services.flatpak-install-gnome-apps = lib.mkIf config.services.flatpak.enable {
```

```diff
       fi
 
-      # Migration: uninstall desktop-only apps from the server role.
-      for app in org.gnome.Calculator org.gnome.Calendar org.gnome.Papers org.gnome.Snapshot; do
-        if flatpak list --app --columns=application 2>/dev/null | grep -qx "$app"; then
-          echo "flatpak: removing desktop-only app $app (role: server)"
-          flatpak uninstall --noninteractive --assumeyes "$app" || true
-        fi
-      done
-
-      # Migration: uninstall Totem — mpv is the designated player.
-      if flatpak list --app --columns=application 2>/dev/null | grep -qx "org.gnome.Totem"; then
-        echo "flatpak: removing org.gnome.Totem (server role uses mpv)"
-        flatpak uninstall --noninteractive --assumeyes org.gnome.Totem || true
-      fi
-
       flatpak install --noninteractive --assumeyes flathub \
```

### `modules/gnome-stateless.nix`

```diff
-  # ── GNOME default app Flatpaks (stateless role) ───────────────────────────
-  # Includes migration cleanup for desktop-only apps that may have been
-  # installed under previous configurations.
+  # ── GNOME default app Flatpaks (stateless role) ───────────────────────────
   systemd.services.flatpak-install-gnome-apps = lib.mkIf config.services.flatpak.enable {
```

```diff
       fi
 
-      # Migration: uninstall desktop-only apps from the stateless role.
-      for app in org.gnome.Calculator org.gnome.Calendar org.gnome.Papers org.gnome.Snapshot; do
-        if flatpak list --app --columns=application 2>/dev/null | grep -qx "$app"; then
-          echo "flatpak: removing desktop-only app $app (role: stateless)"
-          flatpak uninstall --noninteractive --assumeyes "$app" || true
-        fi
-      done
-
-      # Migration: uninstall Totem — mpv is the designated player.
-      if flatpak list --app --columns=application 2>/dev/null | grep -qx "org.gnome.Totem"; then
-        echo "flatpak: removing org.gnome.Totem (stateless role uses mpv)"
-        flatpak uninstall --noninteractive --assumeyes org.gnome.Totem || true
-      fi
-
       flatpak install --noninteractive --assumeyes flathub \
```

---

## 6. Files Modified

| File | Change |
|------|--------|
| `modules/gnome-htpc.nix` | Remove 2-line stale comment; remove 14 lines of dead migration shell |
| `modules/gnome-server.nix` | Remove 2-line stale comment; remove 14 lines of dead migration shell |
| `modules/gnome-stateless.nix` | Remove 2-line stale comment; remove 14 lines of dead migration shell |
| `modules/gnome-desktop.nix` | **No change** |
| `modules/flatpak.nix` | **No change** |

---

## 7. New Dependencies

None.

---

## 8. Risks and Mitigations

| Risk | Likelihood | Mitigation |
|------|-----------|------------|
| A host somehow had Calculator/Calendar/Papers/Snapshot on htpc/server/stateless via out-of-band `flatpak install` | Very low — out-of-scope for managed config | These apps would remain installed (not removed). The host operator would need to remove them manually if desired. This is acceptable; we do not manage manually-installed Flatpaks. |
| Totem left installed on htpc/server/stateless because loop removed | Very low — Totem was never in the managed install list for these roles | Same as above. `flatpak.nix`'s global banned-apps list can be used if Totem ever needs to be force-removed. |
| Stamp hash changes, causing service to re-run unexpectedly | None | Hash is computed over `gnomeAppsToInstall` only; removing shell blocks inside `script` does not alter the hash. |
| `nix flake check` failure | None | These are pure shell-script content removals inside a Nix string literal; the Nix expression remains valid. |

---

## 9. Build Validation Steps

After implementation, the reviewer must run:

```sh
nix flake check
sudo nixos-rebuild dry-build --flake .#vexos-htpc-amd
sudo nixos-rebuild dry-build --flake .#vexos-server-amd
sudo nixos-rebuild dry-build --flake .#vexos-stateless-amd
sudo nixos-rebuild dry-build --flake .#vexos-desktop-amd
```

All four dry-builds must succeed.  The htpc/server/stateless variants are
targeted specifically to exercise the modified modules.

---

## 10. Summary

The dead-code blocks identified in `full_code_analysis.md` are:

- **Block A** (all three roles): A `for` loop removing
  `org.gnome.{Calculator,Calendar,Papers,Snapshot}` — apps that were never
  part of the htpc/server/stateless install lists at any point captured in this
  codebase.
- **Block B** (all three roles): An `if` block removing `org.gnome.Totem` —
  Totem was never in the managed Flatpak install list for these roles, and the
  stamp mechanism means the removal would only ever fire once (or never, on
  new installs).

The desktop role retains its single Totem migration loop because the desktop
is the plausible origin role for a historical Totem installation.

Removal is safe under all host lifecycle scenarios due to the stamp-hash
protection: existing hosts with a valid stamp are unaffected, and new installs
never had these apps.
