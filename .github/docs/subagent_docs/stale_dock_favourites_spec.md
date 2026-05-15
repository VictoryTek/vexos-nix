# Specification: Remove Stale Dock Favourites

**Feature name:** `stale_dock_favourites`  
**Date:** 2026-05-15  
**Phase:** 1 — Research & Specification  
**Scope:** `modules/gnome-htpc.nix`, `modules/gnome-desktop.nix`

---

## 1. Summary

Two GNOME dock favourites reference `.desktop` files that never exist at
runtime. Each produces a blank / invisible slot in the respective role's
Dash-to-Dock sidebar.

| # | File | Stale entry | Reason |
|---|------|-------------|--------|
| A | `modules/gnome-htpc.nix` | `system-update.desktop` | The `up` package ships `io.github.up.desktop`; `system-update.desktop` is a legacy name not installed by any module |
| B | `modules/gnome-desktop.nix` | `virtualbox.desktop` | `virtualisation.virtualbox.host.enable` is commented-out in `modules/virtualization.nix` (kernel 7.0 incompatibility); the package — and its `.desktop` file — are never present |

The fix is a pure list removal in each file. No new files, no `lib.mkIf`
guards, and no architecture changes are required.

---

## 2. Affected Files

| File | Change |
|------|--------|
| `modules/gnome-htpc.nix` | Remove `"system-update.desktop"` from `favorite-apps` |
| `modules/gnome-desktop.nix` | Remove `"virtualbox.desktop"` from `favorite-apps` |

No other tracked Nix source files reference either stale entry.

---

## 3. Issue A — `modules/gnome-htpc.nix`

### 3.1 Confirmation

- **`system-update.desktop` present:** YES — line 54 of `modules/gnome-htpc.nix`
- **`io.github.up.desktop` also present:** YES — line 52 of `modules/gnome-htpc.nix`  
  The `up` updater is already represented by the correct `.desktop` ID;
  `system-update.desktop` is a duplicate that resolves to nothing.

### 3.2 Current `favorite-apps` list (exact strings, as written in the file)

```nix
favorite-apps = [
  "brave-browser.desktop"
  "app.zen_browser.zen.desktop"
  "plex-desktop.desktop"             # nixpkgs plex-desktop package
  "io.freetubeapp.FreeTube.desktop"
  "org.gnome.Nautilus.desktop"
  "io.github.up.desktop"
  "com.mitchellh.ghostty.desktop"
  "system-update.desktop"
];
```

### 3.3 Proposed `favorite-apps` list (after removing `system-update.desktop`)

Remove the last entry. All other entries remain in the same order.

```nix
favorite-apps = [
  "brave-browser.desktop"
  "app.zen_browser.zen.desktop"
  "plex-desktop.desktop"             # nixpkgs plex-desktop package
  "io.freetubeapp.FreeTube.desktop"
  "org.gnome.Nautilus.desktop"
  "io.github.up.desktop"
  "com.mitchellh.ghostty.desktop"
];
```

---

## 4. Issue B — `modules/gnome-desktop.nix`

### 4.1 Confirmation

- **`virtualbox.desktop` present:** YES — line 71 of `modules/gnome-desktop.nix`
- **`virtualisation.virtualbox.host.enable` status:** COMMENTED OUT in
  `modules/virtualization.nix` (lines 20–23). The comment block reads:

  ```nix
  # ── VirtualBox host (DISABLED — incompatible with kernel 7.0) ─────────────
  # virtualisation.virtualbox.host = {
  #   enable              = true;
  #   enableExtensionPack = true;
  # };
  ```

  VirtualBox is never installed; `virtualbox.desktop` therefore never exists.

### 4.2 Current `favorite-apps` list (exact strings, as written in the file)

```nix
favorite-apps = [
  "brave-browser.desktop"
  "app.zen_browser.zen.desktop"
  "org.gnome.Nautilus.desktop"
  "com.mitchellh.ghostty.desktop"
  "io.github.up.desktop"
  "org.gnome.Boxes.desktop"
  "virtualbox.desktop"
  "code.desktop"
];
```

### 4.3 Proposed `favorite-apps` list (after removing `virtualbox.desktop`)

Remove the `"virtualbox.desktop"` entry. All other entries remain in the
same order.

```nix
favorite-apps = [
  "brave-browser.desktop"
  "app.zen_browser.zen.desktop"
  "org.gnome.Nautilus.desktop"
  "com.mitchellh.ghostty.desktop"
  "io.github.up.desktop"
  "org.gnome.Boxes.desktop"
  "code.desktop"
];
```

---

## 5. Cross-reference Check — No Other Source Files Affected

A workspace-wide text search was performed for both stale entries across
all tracked Nix source files.

| Search term | Nix source files matched | Result |
|-------------|--------------------------|--------|
| `system-update.desktop` | `modules/gnome-htpc.nix` only | Only the one target file |
| `virtualbox.desktop` | `modules/gnome-desktop.nix` only | Only the one target file |

Matches in `.github/docs/subagent_docs/` are documentation artefacts; they
are not evaluated by Nix and require no changes.  
`home-desktop.nix` does **not** contain `virtualbox.desktop` (the earlier
`virtualbox_replacement_spec.md` planned to add it but it was never written
to that file).

---

## 6. Implementation Steps

1. Open `modules/gnome-htpc.nix`.  
   In the `programs.dconf.profiles.user.databases` block, locate the
   `favorite-apps` list and delete the line:
   ```
   "system-update.desktop"
   ```
   No trailing comma adjustment needed (Nix list syntax).

2. Open `modules/gnome-desktop.nix`.  
   In the same dconf block, locate the `favorite-apps` list and delete
   the line:
   ```
   "virtualbox.desktop"
   ```

3. No other files need modification.

---

## 7. Validation Steps

- `nix flake check` — must pass with no evaluation errors.
- `sudo nixos-rebuild dry-build --flake .#vexos-desktop-amd` — verify
  desktop closure builds cleanly.
- `sudo nixos-rebuild dry-build --flake .#vexos-htpc-amd` — verify htpc
  closure builds cleanly.
- Confirm `hardware-configuration.nix` is not committed.
- Confirm `system.stateVersion` is unchanged.

---

## 8. Risks and Mitigations

| Risk | Severity | Mitigation |
|------|----------|------------|
| Re-enabling VirtualBox later requires manually re-adding `virtualbox.desktop` | LOW | Tracked in `modules/virtualization.nix` comment; the implementer of VirtualBox re-enablement should restore the dock entry |
| Doc artefacts still reference the stale names | INFO | `.github/docs/` files are not evaluated by Nix; no action required |
