# Spec: Remove `gimp-hidden` writeText Derivation from `configuration-stateless.nix`

## 1. Current State Analysis

`configuration-stateless.nix` contains a `writeTextFile` derivation named `gimp-hidden` in
`environment.systemPackages` (lines 52–70). It installs a minimal `NoDisplay=true` `.desktop`
entry for `org.gimp.GIMP` into the Nix system profile at:

```
/run/current-system/sw/share/applications/org.gimp.GIMP.desktop
```

Its stated purpose (from inline comments) is to shadow the Flatpak-exported GIMP desktop entry
early in `XDG_DATA_DIRS` — before Home Manager has written
`~/.local/share/applications/org.gimp.GIMP.desktop` on the fresh tmpfs home.

---

## 2. Three Mechanisms That Hide / Remove GIMP

| # | Mechanism | Location | Effect |
|---|-----------|----------|--------|
| 1 | `writeTextFile` `gimp-hidden` derivation | `configuration-stateless.nix` lines 60–69 | Writes `NoDisplay=true` into the **system** XDG share dir |
| 2 | `xdg.desktopEntries."org.gimp.GIMP" { noDisplay = true; }` | `home-stateless.nix` line ~117 | Writes `NoDisplay=true` into `~/.local/share/applications/` via Home Manager |
| 3 | `vexos.flatpak.excludeApps = [ "org.gimp.GIMP" … ]` | `configuration-stateless.nix` lines 78–85 | Actively **uninstalls** GIMP from the Flatpak store at boot via `flatpak-install-apps.service` |

All three are currently active on the stateless role.

---

## 3. Problem Definition — Why Mechanism #1 Is Dead Code

### 3a. Mechanism #3 runs before login

`flatpak-install-apps.service` is ordered `after = [ "flatpak-add-flathub.service" ]` and
`wantedBy = [ "multi-user.target" ]`. It executes at boot, before GDM presents the login screen.
The uninstall loop in `flatpak.nix` (lines ~110–117) checks every app in `excludeApps` and calls
`flatpak uninstall` if it is present. If GIMP is carried over in `/persistent/var/lib/flatpak`
from a prior session or role migration, it is removed **before any user can log in**.
There is therefore no Flatpak GIMP `.desktop` entry in `XDG_DATA_DIRS` to shadow.

### 3b. Mechanism #2 covers any residual race

On the stateless role, `~/.local` is part of the fresh tmpfs root that is cleared on every
reboot. Home Manager activates during user session setup (systemd `--user` session). GNOME
Shell reads `~/.local/share/applications/` at session startup; HM writes the `noDisplay = true`
entry during activation — which occurs as part of session initialisation, before the GNOME Shell
app grid is rendered. The **user XDG path** (`~/.local/share/applications/`) takes priority
over all system paths and Flatpak-exported paths, so Mechanism #2 wins even if GIMP somehow
survived Mechanism #3.

### 3c. GDM / greeter session edge case

GDM does not display regular application `.desktop` entries regardless of `XDG_DATA_DIRS`
ordering. The system-level `gimp-hidden` entry has no effect in the greeter session.

**Conclusion:** Mechanism #1 achieves nothing that Mechanisms #2 and #3 do not already provide.

---

## 4. Proposed Change

### File to Modify

`configuration-stateless.nix` — one edit only.

### Exact Code to Remove

**Step 1 — Remove the `gimp-hidden` comment block (lines 51–57):**

```nix
    #
    # gimp-hidden: a minimal NoDisplay=true desktop entry for org.gimp.GIMP.
    # Placed in the Nix system profile share dir, which XDG_DATA_DIRS searches
    # BEFORE /var/lib/flatpak/exports/share (added via lib.mkAfter in flatpak.nix).
    # The first match in the search path wins, so GNOME hides the GIMP Flatpak
    # from the app grid immediately at session start — before Home Manager writes
    # its own ~/.local/share/applications override.
```

**Step 2 — Remove the `writeTextFile` derivation from `environment.systemPackages` (lines 60–69):**

```nix
    (pkgs.writeTextFile {
      name        = "gimp-hidden";
      destination = "/share/applications/org.gimp.GIMP.desktop";
      text        = ''
        [Desktop Entry]
        Name=GIMP
        Type=Application
        NoDisplay=true
      '';
    })
```

### `pkgs.tor-browser` Handling

`pkgs.tor-browser` appears on its own line (line 59) in the same `environment.systemPackages`
list. **It must be kept.** Only the `writeTextFile` derivation and its associated comment block
are removed.

### Result After Change

The `environment.systemPackages` block becomes:

```nix
  # ---------- System packages ----------
  # tor-browser: installed system-wide (not via Home Manager) so torbrowser.desktop
  # lands in /run/current-system/sw/share/applications/ and is always visible to
  # GNOME regardless of Home Manager activation timing on the fresh tmpfs home.
  environment.systemPackages = [
    pkgs.tor-browser
  ];
```

---

## 5. No New Files Needed

This change removes code only. No new modules, options, or files are required.

---

## 6. Remaining Mechanisms Are Sufficient

| Mechanism | Verdict | Reasoning |
|-----------|---------|-----------|
| `vexos.flatpak.excludeApps = [ "org.gimp.GIMP" ]` | **Keep** | Uninstalls GIMP from `/persistent/var/lib/flatpak` at every boot, before login |
| `xdg.desktopEntries."org.gimp.GIMP" { noDisplay = true; }` in `home-stateless.nix` | **Keep** | Hides any residual entry at the user XDG layer; user path has highest priority |

---

## 7. Risks and Mitigations

| Risk | Likelihood | Mitigation |
|------|-----------|------------|
| GIMP visible in app grid on first login after a role migration where the Flatpak service has not yet run | **Very low** — service runs at `multi-user.target`, before GDM | None needed; the service completes before any login is possible |
| GIMP visible in a brief window between session start and HM activation on the fresh tmpfs home | **Negligible** — HM activation is part of session setup; GNOME Shell app grid renders after activation | Mechanism #2 (`xdg.desktopEntries`) fires before the app grid is populated |
| `pkgs.tor-browser` accidentally removed during the edit | **Possible if not careful** | Implementation must confirm `pkgs.tor-browser` is the sole remaining entry in `environment.systemPackages` after the edit |

---

## 8. Implementation Steps

1. Open `configuration-stateless.nix`
2. Remove the blank `#` separator comment and the six-line `gimp-hidden` explanation block
   (the comment block beginning with `# gimp-hidden: a minimal NoDisplay=true …`)
3. Remove the `(pkgs.writeTextFile { … })` derivation from `environment.systemPackages`
4. Confirm `pkgs.tor-browser` is the sole remaining entry in `environment.systemPackages`
5. Run `nix flake check`
6. Run `sudo nixos-rebuild dry-build --flake .#vexos-stateless-amd` (or another stateless variant)
   to confirm the closure builds cleanly
