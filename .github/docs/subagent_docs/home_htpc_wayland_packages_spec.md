# Specification: home-htpc.nix — Wayland Session Variables & Terminal Packages

**Feature:** `home_htpc_wayland_packages`  
**Target file:** `home-htpc.nix`  
**Status:** READY FOR IMPLEMENTATION

---

## 1. Current State of `home-htpc.nix`

Verified by full read of the file (130 lines total).

| Attribute | Present? | Notes |
|---|---|---|
| `home.packages` | **No** | No `home.packages` block exists anywhere in the file |
| `home.sessionVariables` | **No** | No `home.sessionVariables` block exists anywhere in the file |

The file currently contains:
- `imports` (bash-common.nix, gnome-common.nix)
- `home.username` / `home.homeDirectory`
- `programs.starship` + `xdg.configFile."starship.toml"`
- `home.file` wallpaper entries
- `systemd.user.services.vexos-init-app-folders`
- `systemd.user.services.vexos-init-extensions`
- `xdg.desktopEntries."org.gnome.Extensions"`
- `xdg.desktopEntries."gparted"`
- `home.file."justfile"`
- `home.stateVersion = "24.05"`

---

## 2. Analysis Findings

### Issue A — Missing Wayland session variables (CONFIRMED)

All three peer roles export identical Wayland variables:

| Role | `NIXOS_OZONE_WL` | `MOZ_ENABLE_WAYLAND` | `QT_QPA_PLATFORM` |
|---|---|---|---|
| `home-desktop.nix` | `"1"` | `"1"` | `"wayland;xcb"` |
| `home-server.nix` | `"1"` | `"1"` | `"wayland;xcb"` |
| `home-stateless.nix` | `"1"` | `"1"` | `"wayland;xcb"` |
| `home-htpc.nix` | **MISSING** | **MISSING** | **MISSING** |

Impact: Electron apps (Plex Desktop, Brave) and Qt apps on HTPC silently use the X11 backend under Wayland, causing suboptimal rendering and potential HiDPI issues on a TV-connected display.

### Issue B — Missing terminal packages (CONFIRMED)

`ghostty` is pinned as a dock favourite in `modules/gnome-htpc.nix`:

```nix
favorite-apps = [
  "brave-browser.desktop"
  "app.zen_browser.zen.desktop"
  "plex-desktop.desktop"
  "io.freetubeapp.FreeTube.desktop"
  "org.gnome.Nautilus.desktop"
  "io.github.up.desktop"
  "com.mitchellh.ghostty.desktop"   # <-- ghostty is in the dock
  "system-update.desktop"
];
```

**ghostty is in the HTPC dock favourites but is not installed.** The dock entry would show a broken/missing icon at launch. This confirms Issue B is a real defect, not an intentional omission.

Canonical package list across server and stateless roles (the non-dev subset used by all non-desktop roles):

```
ghostty  tree  ripgrep  fd  bat  eza  fzf  wl-clipboard  fastfetch
```

This exact list appears verbatim in both `home-server.nix` and `home-stateless.nix`. The desktop role includes these plus `rustup`, `unstable.nodejs_25`.

---

## 3. Style Decision: `with pkgs;` vs `pkgs.` prefix

`home-htpc.nix` does not currently have a `home.packages` block.  
All three peer files use `with pkgs;` style for `home.packages`:

```nix
home.packages = with pkgs; [
  ghostty
  tree
  ...
];
```

**Use `with pkgs;` style.** This matches `home-desktop.nix`, `home-server.nix`, and `home-stateless.nix` exactly.

---

## 4. Package Availability Audit

All packages are in standard `nixpkgs` (no overlays required):

| Package | nixpkgs attribute | Notes |
|---|---|---|
| `ghostty` | `pkgs.ghostty` | Available in nixpkgs 25.05 stable |
| `tree` | `pkgs.tree` | Standard |
| `ripgrep` | `pkgs.ripgrep` | Standard |
| `fd` | `pkgs.fd` | Standard |
| `bat` | `pkgs.bat` | Standard |
| `eza` | `pkgs.eza` | Standard (successor to `exa`) |
| `fzf` | `pkgs.fzf` | Standard |
| `wl-clipboard` | `pkgs.wl-clipboard` | Standard; provides `wl-copy`/`wl-paste` |
| `fastfetch` | `pkgs.fastfetch` | Standard |

None of these use `unstable.` pinning in the peer roles. `home-desktop.nix` uses `unstable.nodejs_25` only for the desktop-specific Node.js requirement — the terminal utilities listed above are all standard `pkgs.*`.

---

## 5. Exact Changes — Diff-Ready

### Change 1: Add `home.packages`

**Insert after** the `home.homeDirectory = "/home/nimda";` line (line 10), before the `programs.starship` section.

```nix
  # ── User packages ──────────────────────────────────────────────────────────
  home.packages = with pkgs; [
    # Terminal emulator
    ghostty

    # Terminal utilities
    tree
    ripgrep
    fd
    bat
    eza
    fzf
    wl-clipboard  # Wayland clipboard CLI (wl-copy / wl-paste)
    # NOTE: just is installed system-wide via modules/packages-common.nix.

    # System utilities
    fastfetch
    # NOTE: btop and inxi are installed system-wide via modules/packages-common.nix.
  ];
```

**Insertion anchor (oldString):**
```nix
  home.username    = "nimda";
  home.homeDirectory = "/home/nimda";

  # ── Starship prompt ────────────────────────────────────────────────────────
```

**After insertion (newString):**
```nix
  home.username    = "nimda";
  home.homeDirectory = "/home/nimda";

  # ── User packages ──────────────────────────────────────────────────────────
  home.packages = with pkgs; [
    # Terminal emulator
    ghostty

    # Terminal utilities
    tree
    ripgrep
    fd
    bat
    eza
    fzf
    wl-clipboard  # Wayland clipboard CLI (wl-copy / wl-paste)
    # NOTE: just is installed system-wide via modules/packages-common.nix.

    # System utilities
    fastfetch
    # NOTE: btop and inxi are installed system-wide via modules/packages-common.nix.
  ];

  # ── Starship prompt ────────────────────────────────────────────────────────
```

---

### Change 2: Add `home.sessionVariables`

**Insert after** the `xdg.desktopEntries."gparted"` block and before the `home.file."justfile"` entry. This matches the ordering in `home-server.nix` and `home-stateless.nix`.

**Insertion anchor (oldString):**
```nix
  xdg.desktopEntries."gparted" = {
    name       = "GParted";
    exec       = "gparted %f";
    icon       = "gparted";
    comment    = "Create, reorganize, and delete disk partitions";
    categories = [ "System" ];
  };

  # ── Justfile ───────────────────────────────────────────────────────────────
```

**After insertion (newString):**
```nix
  xdg.desktopEntries."gparted" = {
    name       = "GParted";
    exec       = "gparted %f";
    icon       = "gparted";
    comment    = "Create, reorganize, and delete disk partitions";
    categories = [ "System" ];
  };

  # ── Session environment variables ─────────────────────────────────────────
  # NIXOS_OZONE_WL: forces Electron apps (Plex Desktop, Brave) to use the Wayland backend.
  # MOZ_ENABLE_WAYLAND: forces Firefox/Zen to use the Wayland backend.
  # QT_QPA_PLATFORM: ensures Qt apps prefer Wayland with XCB as fallback.
  home.sessionVariables = {
    NIXOS_OZONE_WL     = "1";
    MOZ_ENABLE_WAYLAND = "1";
    QT_QPA_PLATFORM    = "wayland;xcb";
  };

  # ── Justfile ───────────────────────────────────────────────────────────────
```

---

## 6. No Architecture Conflicts

- `home-htpc.nix` is a Home Manager file, not a NixOS module. The Option B architecture rule applies at the NixOS module layer only.
- Home Manager home files are per-role by definition — `home-htpc.nix` is only consumed by HTPC hosts. No `lib.mkIf` guards are needed or appropriate here.
- No changes to any NixOS module files are required.

---

## 7. Risks & Mitigations

| Risk | Severity | Mitigation |
|---|---|---|
| `ghostty` pulls in large GPU/graphics closure | Low | Same risk accepted in desktop/server/stateless; already a dock favourite so it was always intended to be installed |
| `wl-clipboard` conflicts with a system package | Negligible | Not in `packages-common.nix` or `packages-htpc.nix`; no collision |
| Any package removed from nixpkgs 25.05 | Very Low | All 9 packages confirmed available in nixpkgs 25.05 stable |
| Duplicate `home.packages` if future edits add one | N/A | Currently absent; implementation adds it fresh |
| Duplicate `home.sessionVariables` | N/A | Currently absent; implementation adds it fresh |

---

## 8. Files to Modify

| File | Change |
|---|---|
| `home-htpc.nix` | Add `home.packages` block (Change 1) + add `home.sessionVariables` block (Change 2) |

No other files require modification.

---

## 9. Validation Steps

After implementation the reviewer must confirm:

1. `nix flake check` passes
2. `sudo nixos-rebuild dry-build --flake .#vexos-htpc-amd` succeeds (validates the HTPC closure includes all 9 packages and exports the session variables)
3. `home-htpc.nix` contains exactly one `home.packages` block and exactly one `home.sessionVariables` block
4. The three Wayland variable values match `home-desktop.nix`, `home-server.nix`, and `home-stateless.nix` exactly
5. The package list matches `home-server.nix` exactly (the closest peer role)
