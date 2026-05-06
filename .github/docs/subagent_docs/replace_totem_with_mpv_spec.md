# Specification: Replace GNOME Videos (org.gnome.Totem) with mpv

**Feature:** replace_totem_with_mpv  
**Roles affected:** desktop, stateless, server  
**Roles unaffected:** htpc (already uses mpv), headless-server (no display server)  
**Date:** 2026-05-05  

---

## 1. Current State Analysis

### 1.1 Video player inventory by role

| Role | Flatpak Totem installed? | mpv installed? | Source |
|------|--------------------------|----------------|--------|
| desktop | Yes — `gnomeBaseApps` list in `modules/gnome-desktop.nix` line 10 | No | — |
| stateless | Yes — `gnomeAppsToInstall` list in `modules/gnome-stateless.nix` line 10 | No | — |
| server | Yes — `gnomeAppsToInstall` list in `modules/gnome-server.nix` line 10 | No | — |
| htpc | No — excluded from `gnomeAppsToInstall` in `modules/gnome-htpc.nix` | Yes — `modules/packages-htpc.nix` line 7 | `pkgs.mpv` |
| headless-server | No — no display server, no flatpak | No | — |

### 1.2 Nixpkgs-level exclusions (modules/gnome.nix)

`modules/gnome.nix` lines 188–189 globally exclude the nixpkgs builds of both GNOME video players from all DE-using roles via `environment.gnome.excludePackages`:

```nix
totem         # Flatpak org.gnome.Totem is installed instead (auto-updated by Up)
showtime      # GNOME 49 video player ("Video Player") — duplicate of Flatpak Totem
```

These exclusions are correct and must remain — they prevent the nixpkgs-bundled players from appearing alongside the chosen player. Only the comment on `totem` needs updating.

### 1.3 Flatpak install service structure

Each role's gnome-*.nix defines `systemd.services.flatpak-install-gnome-apps`. The service uses a stamp file whose path embeds a SHA256 hash of `gnomeAppsToInstall`. Removing an app from the list changes the hash, which invalidates the old stamp and forces the service to run again on the next rebuild — this is the migration trigger mechanism.

**Current migration cleanup blocks per role:**

- **gnome-desktop.nix**: No migration cleanup block — service goes straight from disk-space check to `flatpak install`.
- **gnome-stateless.nix**: Has a migration block removing `org.gnome.Calculator`, `org.gnome.Calendar`, `org.gnome.Papers`, `org.gnome.Snapshot` (desktop-only apps). No Totem block.
- **gnome-server.nix**: Same migration block as stateless for desktop-only apps. No Totem block.
- **gnome-htpc.nix** (reference): Has both a desktop-only-app migration block AND a separate Totem migration block. Totem block pattern:

```bash
# Migration: uninstall Totem on HTPC — mpv is the designated player.
if flatpak list --app --columns=application 2>/dev/null | grep -qx "org.gnome.Totem"; then
  echo "flatpak: removing org.gnome.Totem (htpc role uses mpv)"
  flatpak uninstall --noninteractive --assumeyes org.gnome.Totem || true
fi
```

### 1.4 GStreamer status

`modules/packages-htpc.nix` includes the full GStreamer plugin stack (`gst-plugins-base/good/bad/ugly/libav`). This is HTPC-specific. `modules/packages-desktop.nix` and `modules/packages-common.nix` contain no GStreamer packages. mpv does not use GStreamer — it decodes via its own ffmpeg/libav integration — so the non-HTPC roles do not need GStreamer added.

### 1.5 packages-desktop.nix import scope

`modules/packages-desktop.nix` is imported by all three target roles:

- `configuration-desktop.nix` line 13
- `configuration-stateless.nix` line 9
- `configuration-server.nix` line 11

Its header comment confirms: _"GUI packages for roles with a display server (desktop, server, htpc, stateless). Do NOT import on headless-server."_ This makes it the canonical location for mpv on all three target roles.

---

## 2. Problem Definition

`org.gnome.Totem` (GNOME Videos) is installed as a Flatpak on the desktop, stateless, and server roles. Totem is a GStreamer-backed player with limited codec coverage, heavy GLib/GStreamer dependencies, and historically poor hardware-acceleration support compared to mpv.

mpv is already the designated video player on htpc. Consistency, codec breadth (ffmpeg-backed), hardware-acceleration (VA-API/VDPAU), and lower runtime overhead motivate replacing Totem with mpv across all DE-using roles.

---

## 3. Proposed Solution Architecture

### 3.1 Module architecture compliance

This project uses **Option B: Common base + role additions** (per copilot-instructions.md). Rules that apply here:

- `packages-desktop.nix` is the existing display-server packages file. Adding `mpv` there is adding to the correct base file — it is imported unconditionally by all three target roles.
- No `lib.mkIf` guards may be added.
- No new module files are needed — the change fits cleanly into existing files.

### 3.2 Files to modify (no new files required)

| File | Change |
|------|--------|
| `modules/packages-desktop.nix` | Add `mpv` to `environment.systemPackages` |
| `modules/gnome-desktop.nix` | Remove `"org.gnome.Totem"` from `gnomeBaseApps`; add Totem migration cleanup block to flatpak service; update file header comment |
| `modules/gnome-stateless.nix` | Remove `"org.gnome.Totem"` from `gnomeAppsToInstall`; add Totem migration cleanup block to flatpak service; update file header comment |
| `modules/gnome-server.nix` | Remove `"org.gnome.Totem"` from `gnomeAppsToInstall`; add Totem migration cleanup block to flatpak service; update file header comment |
| `modules/gnome.nix` | Update inline comment for `totem` entry in `excludePackages` to reflect mpv replaces it |

### 3.3 Files NOT to create

- `modules/packages-stateless.nix` — not needed; `packages-desktop.nix` covers stateless.
- `modules/packages-server.nix` — not needed; `packages-desktop.nix` covers server.
- `modules/mpv.nix` — mpv is a single package line; a dedicated module file would be over-engineering.

### 3.4 GStreamer decision

Do **not** add GStreamer to `packages-desktop.nix`. Rationale:

1. mpv uses ffmpeg/libav directly — no GStreamer dependency.
2. GStreamer in `packages-htpc.nix` was primarily for Totem and full HDMI-CEC media stack needs specific to HTPC.
3. Adding the full GStreamer stack to desktop/stateless/server would increase the system closure without functional benefit for mpv-based playback.
4. Browser codecs (Brave/Chromium) are handled by the browser's own bundled ffmpeg — GStreamer is not required.

---

## 4. Exact Implementation Steps

### Step 1 — `modules/packages-desktop.nix`

Add `mpv` to `environment.systemPackages`. Position it above or after the existing entries with a clear comment.

**Target result:**

```nix
# modules/packages-desktop.nix
# GUI packages for roles with a display server (desktop, server, htpc, stateless).
# Do NOT import on headless-server.
{ pkgs, ... }:
{
  environment.systemPackages = with pkgs; [
    brave  # Chromium-based browser
    joplin-desktop  # Note-taking app (testing)
    jdk21  # Java 21 (LTS)
    mpv    # Video player (replaces Totem Flatpak on desktop/stateless/server)
  ];
}
```

### Step 2 — `modules/gnome-desktop.nix`

**2a.** Remove `"org.gnome.Totem"` from `gnomeBaseApps` (line 10).

Before:
```nix
gnomeBaseApps = [
  "org.gnome.TextEditor"
  "org.gnome.Loupe"
  "org.gnome.Totem"
];
```

After:
```nix
gnomeBaseApps = [
  "org.gnome.TextEditor"
  "org.gnome.Loupe"
];
```

**2b.** Update the file header comment (line 2–4) to remove "Totem" from the description and note mpv.

Before:
```nix
# Desktop-only GNOME additions: GameMode shell extension, blue accent,
# desktop favourites, and the Flatpak install service for the desktop role
# (TextEditor, Loupe, Totem, Calculator, Calendar, Papers, Snapshot).
```

After:
```nix
# Desktop-only GNOME additions: GameMode shell extension, blue accent,
# desktop favourites, and the Flatpak install service for the desktop role
# (TextEditor, Loupe, Calculator, Calendar, Papers, Snapshot). mpv is the
# video player (nixpkgs, via packages-desktop.nix).
```

**2c.** Add a Totem migration cleanup block inside the flatpak service's `script`, after the disk-space check and before the `flatpak install` call. Match the htpc pattern exactly.

Before (inside `script = ''`):
```bash
      # Require at least 1.5 GB free before attempting installs.
      # Exit 0 (not 1) so the switch doesn't fail — stamp is not written,
      # so the service will retry on the next boot.
      AVAIL_MB=$(df /var/lib/flatpak --output=avail -BM 2>/dev/null | tail -1 | tr -d 'M ' || echo 0)
      if [ "$AVAIL_MB" -lt 1536 ]; then
        echo "flatpak: only ''${AVAIL_MB} MB free — need 1536 MB; skipping this boot"
        exit 0
      fi

      flatpak install --noninteractive --assumeyes flathub \
```

After:
```bash
      # Require at least 1.5 GB free before attempting installs.
      # Exit 0 (not 1) so the switch doesn't fail — stamp is not written,
      # so the service will retry on the next boot.
      AVAIL_MB=$(df /var/lib/flatpak --output=avail -BM 2>/dev/null | tail -1 | tr -d 'M ' || echo 0)
      if [ "$AVAIL_MB" -lt 1536 ]; then
        echo "flatpak: only ''${AVAIL_MB} MB free — need 1536 MB; skipping this boot"
        exit 0
      fi

      # Migration: uninstall Totem — mpv is the designated player.
      if flatpak list --app --columns=application 2>/dev/null | grep -qx "org.gnome.Totem"; then
        echo "flatpak: removing org.gnome.Totem (desktop role uses mpv)"
        flatpak uninstall --noninteractive --assumeyes org.gnome.Totem || true
      fi

      flatpak install --noninteractive --assumeyes flathub \
```

### Step 3 — `modules/gnome-stateless.nix`

**3a.** Remove `"org.gnome.Totem"` from `gnomeAppsToInstall` (line 10).

Before:
```nix
gnomeAppsToInstall = [
  "org.gnome.TextEditor"
  "org.gnome.Loupe"
  "org.gnome.Totem"
];
```

After:
```nix
gnomeAppsToInstall = [
  "org.gnome.TextEditor"
  "org.gnome.Loupe"
];
```

**3b.** Update the file header comment (line 2–3) to remove "Totem" and note mpv.

Before:
```nix
# Stateless-only GNOME additions: teal accent, stateless dock favourites, and
# the Flatpak install service for the stateless role (TextEditor, Loupe, Totem).
```

After:
```nix
# Stateless-only GNOME additions: teal accent, stateless dock favourites, and
# the Flatpak install service for the stateless role (TextEditor, Loupe). mpv
# is the video player (nixpkgs, via packages-desktop.nix).
```

**3c.** Add a Totem migration cleanup block inside the flatpak service's `script`, after the existing desktop-only-apps migration loop and before the `flatpak install` call.

Before (inside `script = ''`):
```bash
      # Migration: uninstall desktop-only apps from the stateless role.
      for app in org.gnome.Calculator org.gnome.Calendar org.gnome.Papers org.gnome.Snapshot; do
        if flatpak list --app --columns=application 2>/dev/null | grep -qx "$app"; then
          echo "flatpak: removing desktop-only app $app (role: stateless)"
          flatpak uninstall --noninteractive --assumeyes "$app" || true
        fi
      done

      flatpak install --noninteractive --assumeyes flathub \
```

After:
```bash
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

      flatpak install --noninteractive --assumeyes flathub \
```

### Step 4 — `modules/gnome-server.nix`

**4a.** Remove `"org.gnome.Totem"` from `gnomeAppsToInstall` (line 10).

Before:
```nix
gnomeAppsToInstall = [
  "org.gnome.TextEditor"
  "org.gnome.Loupe"
  "org.gnome.Totem"
];
```

After:
```nix
gnomeAppsToInstall = [
  "org.gnome.TextEditor"
  "org.gnome.Loupe"
];
```

**4b.** Update the file header comment (line 2–3) to remove "Totem" and note mpv.

Before:
```nix
# Server-only GNOME additions: yellow accent, server dock favourites, and
# the Flatpak install service for the server role (TextEditor, Loupe, Totem).
```

After:
```nix
# Server-only GNOME additions: yellow accent, server dock favourites, and
# the Flatpak install service for the server role (TextEditor, Loupe). mpv
# is the video player (nixpkgs, via packages-desktop.nix).
```

**4c.** Add a Totem migration cleanup block inside the flatpak service's `script`, after the existing desktop-only-apps migration loop and before the `flatpak install` call.

Before (inside `script = ''`):
```bash
      # Migration: uninstall desktop-only apps from the server role.
      for app in org.gnome.Calculator org.gnome.Calendar org.gnome.Papers org.gnome.Snapshot; do
        if flatpak list --app --columns=application 2>/dev/null | grep -qx "$app"; then
          echo "flatpak: removing desktop-only app $app (role: server)"
          flatpak uninstall --noninteractive --assumeyes "$app" || true
        fi
      done

      flatpak install --noninteractive --assumeyes flathub \
```

After:
```bash
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

      flatpak install --noninteractive --assumeyes flathub \
```

### Step 5 — `modules/gnome.nix`

Update the inline comment for the `totem` entry in `environment.gnome.excludePackages` (line 188) to reflect that mpv replaces it rather than the Flatpak.

Before:
```nix
    totem         # Flatpak org.gnome.Totem is installed instead (auto-updated by Up)
```

After:
```nix
    totem         # mpv (nixpkgs) is the video player; Flatpak Totem is not installed
```

---

## 5. Migration Cleanup Approach

### Mechanism

The stamp file path for each role's `flatpak-install-gnome-apps` service embeds a SHA256 hash of the `gnomeAppsToInstall` list:

```
/var/lib/flatpak/.gnome-apps-installed-<sha256-of-app-list>
```

Removing `"org.gnome.Totem"` from the list changes the hash → the old stamp no longer matches → the service script runs again on the next `nixos-rebuild switch`. The migration cleanup block runs before `flatpak install`, conditionally removing Totem if present, then the service stamps with the new hash.

### Consistency with htpc pattern

The htpc role established this exact pattern in `modules/gnome-htpc.nix`. This spec replicates it faithfully for the three target roles. The block is:

1. Guarded by `flatpak list ... grep -qx "org.gnome.Totem"` — idempotent, no error if already uninstalled.
2. Uses `--noninteractive --assumeyes` — no TTY interaction.
3. Uses `|| true` — failure to uninstall does not abort the service; the main install proceeds.

### One-time execution guarantee

The stamp file is only written after the migration and install both succeed. If either step fails the service exits non-zero, retries via `Restart = "on-failure"`, and the migration runs again. Once stamped, neither the migration nor the install re-runs unless the app list changes again.

---

## 6. Risks and Mitigations

| Risk | Likelihood | Mitigation |
|------|-----------|------------|
| mpv not available in nixpkgs 25.05 | Very low — mpv is a long-standing nixpkgs package | Verify with `nix-instantiate --eval -E 'with import <nixpkgs> {}; mpv.version'` during review |
| Totem Flatpak data (recent files, preferences) lost | Low — Totem stores its data in `~/.var/app/org.gnome.Totem/`; uninstalling the Flatpak removes the sandbox but user media files are in `~/` | Acceptable; this is a player swap, not a data migration |
| mpv has no .desktop file / GNOME file associations not updated | Low — nixpkgs mpv package includes `mpv.desktop` and sets MIME associations for common video types | Verify during review that `mpv.desktop` appears in `~/.nix-profile/share/applications/` |
| Stamp file hash collision (two different app lists producing the same hash prefix) | Negligible — 16 hex chars of SHA256 is 64-bit space | No action needed |
| stateless role: Totem Flatpak persisted across reboots (in `/persistent/var/lib/flatpak`) | Medium — stateless uses impermanence and flatpak data survives reboot | Migration cleanup runs on next rebuild regardless of persistence; `|| true` prevents blocking if already gone |
| Flatpak disk-space guard prevents migration from running | Low — guard exits 0 without stamping; migration retries next boot | `|| true` on uninstall means the stamp is only written after a full successful run |
| server role has no practical use case for mpv | Low impact — server role has a GNOME DE and packages-desktop.nix is already imported; mpv is small | Acceptable; consistent player across all DE roles is the goal |

---

## 7. Dependencies

No new external dependencies. `pkgs.mpv` is available in nixpkgs 25.05 stable.

No Context7 lookup required — this change is internal to the repository and uses only an already-available nixpkgs package with no new integrations.

---

## 8. Files Modified Summary

| File | Nature of change |
|------|-----------------|
| `modules/packages-desktop.nix` | Add `mpv` to `systemPackages` |
| `modules/gnome-desktop.nix` | Remove Totem from app list; update comment; add migration block |
| `modules/gnome-stateless.nix` | Remove Totem from app list; update comment; add migration block |
| `modules/gnome-server.nix` | Remove Totem from app list; update comment; add migration block |
| `modules/gnome.nix` | Update `totem` excludePackages comment only |

Total: 5 files modified. No new files created.
