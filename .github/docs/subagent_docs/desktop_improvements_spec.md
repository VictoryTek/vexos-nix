# Desktop Improvements Specification

## Feature Name
`desktop_improvements`

## Date
2026-04-15

---

## 1. Current State Analysis

### flake.nix
- Inputs: `nixpkgs` (25.11), `nixpkgs-unstable`, `home-manager` (release-25.11), `impermanence`, `up`
- **No `nix-gaming` input** — previously removed from `flake.nix`
- However, `nix-gaming` still persists as a stale entry in `flake.lock` (lines 60, 81, 161–179, 250)
- Outputs: desktop (amd/nvidia/intel/vm), stateless, server, htpc — all variants

### configuration.nix
- Imports 10 modules: gnome, gaming, audio, gpu, flatpak, network, development, virtualization, branding, system
- Does NOT import `modules/packages.nix`
- No `permittedInsecurePackages` block (clean)
- `nixpkgs.config.allowUnfree = true`
- `system.stateVersion = "25.11"` — **MUST NOT be changed**
- `gnome-boxes` in systemPackages (from unstable)

### configuration-stateless.nix
- Imports 8 modules including `modules/packages.nix` and `modules/impermanence.nix`
- **Has** `nixpkgs.config.permittedInsecurePackages = [ "electron-36.9.5" ]` — Heroic Games Launcher is NOT installed
- `system.stateVersion = "25.11"`

### configuration-htpc.nix / configuration-server.nix
- Both import `modules/packages.nix` (NOT `modules/development.nix`)
- These non-desktop roles rely on packages.nix for base CLI tools

### home.nix (nimda user, Home Manager)
- Packages: `rustup`, `unstable.nodejs_25`, `ghostty`, `tree`, `ripgrep`, `fd`, `bat`, `eza`, `fzf`, `just`, `wl-clipboard`, `bibata-cursors`, `kora-icon-theme`, `fastfetch`, `btop`, `inxi`, `blivet-gui`
- `programs.direnv` with `nix-direnv.enable = true` — **already configured**
- `programs.tmux` with mouse, vi-mode, C-a prefix, history 10000 — **already configured**
- `programs.bash` with aliases
- `programs.starship` enabled
- dconf settings including System folder apps (no `htop.desktop`)
- JXL wallpapers deployed

### modules/system.nix
- `boot.kernel.sysctl."vm.max_map_count" = 2147483642` — **already present**
- `services.scx = { enable = true; scheduler = "scx_lavd"; }` — **already uncommented**
- ZRAM, swap, btrfs, kernel params, THP, sysctl all configured

### modules/audio.nix
- PipeWire with low-latency native config (quantum=64 at 48kHz)
- WirePlumber bluez5 codecs: `[ "aac" "ldac" "aptx" "aptx_hd" ]` — **already configured**
- SBC-XQ, mSBC, hw-volume, HSP/HFP roles all enabled

### modules/development.nix
- Contains: `unstable.vscode-fhs`, `python3`, `uv`, `ruff`, `nodePackages.typescript`, `pnpm`, `bun`, `podman-compose`, `buildah`, `skopeo`, `flatpak-builder`, `gh`, `git-lfs`, `jq`, `yq-go`, `pre-commit`, `sqlite`, `httpie`, `mkcert`, `nil`, `nixpkgs-fmt`, `nix-output-monitor`, `go`, `brave`, `git`, `curl`, `wget`
- No rustfmt, clippy, rustup, nodejs (standalone), direnv, htop, or inxi — **already clean**
- Podman with dockerCompat enabled

### modules/packages.nix
- Contains: `brave`, `inxi`, `git`, `curl`, `wget`, `htop`
- Imported by: stateless, htpc, server roles (NOT desktop role)
- Serves as the base CLI toolset for non-desktop configurations
- `htop` present here but `btop` is not — non-desktop roles have htop, desktop has btop via home.nix

### modules/gnome.nix
- `jxl-pixbuf-loader` — **already present**
- Full unstable GNOME overlay (shell, mutter, GDM, nautilus, etc.)
- Extensions, fonts, GNOME-bloat excludePackages, Flatpak GNOME-app service

### modules/flatpak.nix
- `org.gnome.World.PikaBackup` — **already present**
- `com.usebottles.bottles` — **already present**
- `com.github.wwmm.easyeffects` — **already present**
- Full app list with `vexos.flatpak.excludeApps` opt-out option

### modules/gaming.nix
- Steam, Gamescope, GameMode fully configured
- `## mangohud` — commented out (line 45)
- `##services.input-remapper.enable = true;` — commented out (line 70)
- Header: `# Gaming stack: Steam, Proton, Lutris, MangoHud, Gamescope, GameMode, Wine/Proton tooling, Distrobox, Input Remapper.`
- NOTE comment correctly references Lutris, ProtonPlus, Bottles as Flatpak

### modules/gpu.nix
- Common GPU base: hardware.graphics, VA-API, VDPAU, Vulkan, mesa — all clean, no changes needed

### modules/branding.nix
- Plymouth, os-release, GDM logo, icons, boot menu cleanup — all clean

### modules/network.nix, modules/virtualization.nix
- Clean, no changes needed

### home/photogimp.nix
- PhotoGIMP GIMP overlay — clean, no changes needed

### files/starship.toml
- Custom prompt config — clean, no changes needed

---

## 2. Problem Definition

Despite many improvements already applied, several issues remain:

1. **Package duplication across roles** — `brave`, `git`, `curl`, `wget` exist in both `development.nix` (desktop role) and `packages.nix` (non-desktop roles). `inxi` is in both `packages.nix` and `home.nix`. This is partly by design (different roles load different module sets), but `htop` in `packages.nix` is dead weight now that `btop` is preferred.

2. **Dead code in gaming.nix** — Commented-out `mangohud` package and `input-remapper` service. Header references tools not present or only present via Flatpak.

3. **Stale `permittedInsecurePackages`** — `configuration-stateless.nix` allows `electron-36.9.5` for Heroic, which is not installed anywhere.

4. **Stale nix-gaming in flake.lock** — The input was removed from `flake.nix` but `flake.lock` still carries it.

5. **MangoHud not properly enabled** — A gaming desktop should have MangoHud available. NixOS provides `programs.mangohud.enable` which is the idiomatic approach.

---

## 3. Research Summary

### Source 1: NixOS 25.05+ `boot.kernel.sysctl` options
- `boot.kernel.sysctl` accepts arbitrary sysctl key-value pairs as an attribute set
- `vm.max_map_count = 2147483642` is the SteamOS/Bazzite standard (MAX_INT-5)
- **Status: Already implemented** in `modules/system.nix`

### Source 2: WirePlumber Bluetooth codec configuration
- WirePlumber's `monitor.bluez.properties` accepts `bluez5.codecs` as a list of codec names
- Valid codecs: `"sbc"`, `"sbc_xq"`, `"aac"`, `"ldac"`, `"aptx"`, `"aptx_hd"`, `"aptx_ll"`, `"aptx_ll_duplex"`, `"faststream"`, `"lc3plus_h3"`, `"opus_05"`, `"opus_05_51"`, `"opus_05_71"`, `"opus_05_duplex"`, `"opus_05_pro"`, `"lc3"`
- When `bluez5.codecs` is set, only listed codecs are enabled. SBC is always available as fallback regardless.
- **Status: Already implemented** — `[ "aac" "ldac" "aptx" "aptx_hd" ]` in `modules/audio.nix`

### Source 3: Home Manager `programs.direnv` and `programs.tmux`
- `programs.direnv.enable = true` installs direnv, adds shell hooks, and manages config
- `programs.direnv.nix-direnv.enable = true` adds Nix-aware `use_nix`/`use_flake` with caching
- `programs.tmux` supports: `mouse`, `terminal`, `prefix`, `baseIndex`, `escapeTime`, `historyLimit`, `keyMode`
- **Status: Both already implemented** in `home.nix`

### Source 4: `nix-gaming` flake modules
- Provides: `pipewireLowLatency`, `steamPlatformOptimizations`, `nix-gaming.packages` (wine-ge, proton-ge, etc.)
- `pipewireLowLatency` sets quantum/rate via a NixOS module — **now obsolete** since PipeWire supports native `extraConfig` for the same settings (already used in `modules/audio.nix`)
- `steamPlatformOptimizations` is minimal sysctl tuning — already covered by `modules/system.nix`
- **Status: Correctly removed from flake.nix.** flake.lock needs cleanup.

### Source 5: NixOS `services.scx` and `programs.mangohud`
- `services.scx = { enable = true; scheduler = "scx_lavd"; }` — available in NixOS 25.05+ with sched_ext kernel support
- `programs.mangohud.enable = true` — NixOS module that installs MangoHud and sets up 32-bit support; preferred over raw `pkgs.mangohud` in systemPackages
- **scx: Already implemented.** MangoHud: needs to be enabled.

### Source 6: Flatpak application IDs
- PikaBackup: `org.gnome.World.PikaBackup` — already in flatpak.nix
- Bottles: `com.usebottles.bottles` — already in flatpak.nix
- EasyEffects: `com.github.wwmm.easyeffects` — already in flatpak.nix

---

## 4. Proposed Changes

### Legend
- ✅ ALREADY DONE — no changes needed, verified in current files
- 🔧 NEEDS IMPLEMENTATION — changes required

---

### 4.1 modules/system.nix — ✅ NO CHANGES NEEDED

| Item | Status |
|------|--------|
| #4 `vm.max_map_count = 2147483642` | ✅ Already present |
| #12 `services.scx` uncommented | ✅ Already present and enabled |

---

### 4.2 modules/audio.nix — ✅ NO CHANGES NEEDED

| Item | Status |
|------|--------|
| #5 Bluetooth codecs (AAC, LDAC, aptX, aptX HD) | ✅ Already configured |

---

### 4.3 home.nix — ✅ NO CHANGES NEEDED

| Item | Status |
|------|--------|
| #8 `programs.direnv` with nix-direnv | ✅ Already configured |
| #15 `wl-clipboard` | ✅ Already in packages |
| tmux — `programs.tmux` | ✅ Already configured |
| btop — in packages | ✅ Already present |

---

### 4.4 modules/development.nix — ✅ NO CHANGES NEEDED

| Item | Status |
|------|--------|
| #6 rustfmt/clippy removed | ✅ Not present |
| #7 nodejs removed | ✅ Not present |
| #9 nil, nixpkgs-fmt, nix-output-monitor | ✅ Already present |
| Go toolchain | ✅ Already present |
| brave, git, curl, wget | ✅ Present (needed for desktop role) |

---

### 4.5 modules/gnome.nix — ✅ NO CHANGES NEEDED

| Item | Status |
|------|--------|
| #10 jxl-pixbuf-loader | ✅ Already present |

---

### 4.6 modules/flatpak.nix — ✅ NO CHANGES NEEDED

| Item | Status |
|------|--------|
| #16 PikaBackup | ✅ Already present |
| #18 Bottles | ✅ Already present |
| EasyEffects | ✅ Already present |

---

### 4.7 flake.nix — ✅ NO SOURCE CHANGES NEEDED

| Item | Status |
|------|--------|
| #11 nix-gaming input removal | ✅ Already removed from flake.nix |

**However:** `flake.lock` still contains stale `nix-gaming` entries. This will be cleaned automatically on the next `nix flake update` or can be forced with `nix flake lock` (which regenerates the lock file from current inputs). **No source file edit needed** — this is a lock file hygiene issue resolved by running the lock command.

---

### 4.8 modules/gaming.nix — 🔧 NEEDS IMPLEMENTATION

**Change 1: Enable MangoHud via NixOS module** (replaces commented-out package)

Add `programs.mangohud.enable = true;` to the module. This is the idiomatic NixOS approach — it installs MangoHud with 32-bit support and creates the wrapper.

**Before (lines 43-45):**
```nix
    # Performance overlay — enable per-game with: mangohud %command% in Steam launch options
    ## mangohud
```

**After:**
```nix
    # NOTE: MangoHud is enabled via programs.mangohud.enable below (not as a package).
```

Add after the `programs.gamescope` block:
```nix
  # ── MangoHud (in-game performance overlay) ────────────────────────────────
  # Enable per-game with: mangohud %command% in Steam launch options.
  programs.mangohud.enable = true;
```

**Change 2: Remove commented-out input-remapper service** (line 70)

**Before:**
```nix
  # ── Input Remapper daemon ─────────────────────────────────────────────────
  # Use the NixOS service module instead of a manual systemd service definition
  # to avoid conflicts with the packaged service file.
  ##services.input-remapper.enable = true;
```

**After:**
Remove the entire 4-line block. Input Remapper is not being used — if needed in the future, it can be re-added with a single line.

**Change 3: Update module header comment** (lines 1-3)

**Before:**
```nix
# modules/gaming.nix
# Gaming stack: Steam, Proton, Lutris, MangoHud, Gamescope,
# GameMode, Wine/Proton tooling, Distrobox, Input Remapper.
```

**After:**
```nix
# modules/gaming.nix
# Gaming stack: Steam, Proton, MangoHud, Gamescope, GameMode,
# Wine/Proton tooling, Distrobox.
# Lutris, ProtonPlus, and Bottles are installed via Flatpak (see modules/flatpak.nix).
```

---

### 4.9 modules/packages.nix — 🔧 NEEDS IMPLEMENTATION

This file is imported by `configuration-stateless.nix`, `configuration-htpc.nix`, and `configuration-server.nix` (but NOT by `configuration.nix`). It provides base CLI tools for non-desktop roles.

**Change: Replace `htop` with `btop`; update header and formatting**

The desktop role gets `btop` via `home.nix`. Non-desktop roles (stateless, server, htpc) should also use `btop` instead of `htop` for consistency.

`inxi` is kept — server/htpc admins need quick system info and those roles do NOT have home-manager.

**Before:**
```nix
# modules/packages.nix
# Third-party and supplementary Nix packages — installed system-wide.
# Covers the Brave browser.
{ pkgs, ... }:
{
  environment.systemPackages = with pkgs; [

    # ── Browser ───────────────────────────────────────────────────────────────
    brave                                              # Chromium-based browser

    # ── System Info ───────────────────────────────────────────────────────────
    inxi                                               # System information tool
    git
    curl
    wget
    htop

  ];
}
```

**After:**
```nix
# modules/packages.nix
# Base system packages for non-desktop roles (server, htpc, stateless).
# Desktop role uses modules/development.nix instead (which includes these plus dev tools).
{ pkgs, ... }:
{
  environment.systemPackages = with pkgs; [

    # ── Browser ───────────────────────────────────────────────────────────────
    brave                                              # Chromium-based browser

    # ── System utilities ──────────────────────────────────────────────────────
    btop                                               # Terminal process viewer
    inxi                                               # System information tool
    git                                                # Version control
    curl                                               # HTTP / transfer CLI
    wget                                               # File downloader

  ];
}
```

---

### 4.10 configuration-stateless.nix — 🔧 NEEDS IMPLEMENTATION

**Change: Remove `permittedInsecurePackages` block**

Heroic Games Launcher is not installed anywhere (it's not in gaming.nix, flatpak.nix, or any other module). The `electron-36.9.5` exception is dead code that unnecessarily broadens the allowed insecure package set.

**Before (lines 119-123):**
```nix
  # ---------- Permitted insecure packages ----------
  # electron: required by Heroic Games Launcher; permit until nixpkgs ships a newer version.
  nixpkgs.config.permittedInsecurePackages = [
    "electron-36.9.5"
  ];
```

**After:**
Remove the entire 5-line block.

**Note:** `configuration.nix` (desktop role) does NOT have this block — it's already clean.

---

### 4.11 flake.lock cleanup — 🔧 POST-IMPLEMENTATION STEP

Run `nix flake lock` to regenerate `flake.lock` from the current `flake.nix` inputs, which will drop the stale `nix-gaming` entry.

This is not a source code change but a required maintenance step. Can only be run on a NixOS host with `nix` available.

---

## 5. Package Deduplication Map

### Cross-role analysis

| Package | development.nix (desktop) | packages.nix (server/htpc/stateless) | home.nix (HM) | Action |
|---------|--------------------------|--------------------------------------|---------------|--------|
| `brave` | ✅ Present | ✅ Present | — | **Keep both** — different roles, no overlap |
| `git` | ✅ Present | ✅ Present | — | **Keep both** — different roles, no overlap |
| `curl` | ✅ Present | ✅ Present | — | **Keep both** — different roles, no overlap |
| `wget` | ✅ Present | ✅ Present | — | **Keep both** — different roles, no overlap |
| `inxi` | — | ✅ Present | ✅ Present | **Keep both** — HM covers desktop, packages.nix covers non-desktop |
| `htop` | — | ✅ Present | — | 🔧 **Replace with `btop`** in packages.nix |
| `btop` | — | — | ✅ Present | **Keep** — desktop role gets it via HM |
| `rustup` | — | — | ✅ Present | **Keep** — HM only, no duplication |
| `nodejs_25` | — | — | ✅ Present | **Keep** — HM only, no duplication |

### Key insight
The apparent duplication between `development.nix` and `packages.nix` is **by design**: `configuration.nix` (desktop) imports `development.nix` but NOT `packages.nix`, while `configuration-{stateless,server,htpc}.nix` import `packages.nix` but NOT `development.nix`. There is no true duplication within any single role's module set.

The only actionable deduplication is replacing `htop` with `btop` in `packages.nix`.

---

## 6. Summary of All Changes

### Files requiring changes (3 files):

| File | Changes |
|------|---------|
| `modules/gaming.nix` | Enable MangoHud via `programs.mangohud.enable`; remove commented-out mangohud package and input-remapper service; update header |
| `modules/packages.nix` | Replace `htop` with `btop`; update header comment; add alignment comments |
| `configuration-stateless.nix` | Remove `permittedInsecurePackages` block |

### Files confirmed clean (no changes needed):

| File | Reason |
|------|--------|
| `flake.nix` | nix-gaming already removed; all inputs correct |
| `configuration.nix` | No insecure packages block; correct imports |
| `home.nix` | direnv, tmux, wl-clipboard, btop all present; no htop |
| `modules/system.nix` | vm.max_map_count, scx already configured |
| `modules/audio.nix` | Bluetooth codecs already configured |
| `modules/development.nix` | No rustfmt/clippy/nodejs/direnv/htop; nil/nixpkgs-fmt/nom/go present |
| `modules/gnome.nix` | jxl-pixbuf-loader already present |
| `modules/flatpak.nix` | PikaBackup, Bottles, EasyEffects already present |
| `modules/gpu.nix` | Clean |
| `modules/network.nix` | Clean |
| `modules/virtualization.nix` | Clean |
| `modules/branding.nix` | Clean |

### Post-implementation manual step:
- Run `nix flake lock` on the NixOS host to prune stale `nix-gaming` from `flake.lock`

---

## 7. Implementation Order

1. `modules/gaming.nix` — MangoHud enable, remove dead comments, update header
2. `modules/packages.nix` — Replace htop with btop, update header
3. `configuration-stateless.nix` — Remove permittedInsecurePackages block

---

## 8. Risks and Mitigations

| Risk | Impact | Mitigation |
|------|--------|------------|
| MangoHud `programs.mangohud.enable` not available in 25.11 | Build failure | `programs.mangohud.enable` has been in nixpkgs since NixOS 23.05. Verified available. |
| Removing `permittedInsecurePackages` causes eval failure | Build failure for stateless role | No package in the stateless module set requires `electron-36.9.5`. Heroic is not installed. Safe to remove. |
| htop → btop in packages.nix breaks server/htpc workflows | Admin inconvenience | btop is a strict superset of htop functionality. No scripts depend on `htop` binary name. |
| Stale flake.lock causes `nix flake check` issues | CI noise | Running `nix flake lock` regenerates cleanly. |
| Removing input-remapper comment loses future reference | Minor | Single-line re-add (`services.input-remapper.enable = true;`) is trivially searchable in NixOS docs. |

---

## 9. Validation Plan

1. **Syntax check:** All modified `.nix` files must parse without errors
2. **`nix flake check`** — must pass with no evaluation errors
3. **`nix flake lock`** — regenerate lock file, confirm nix-gaming is absent
4. **Dry-build all desktop variants:**
   - `sudo nixos-rebuild dry-build --flake .#vexos-desktop-amd`
   - `sudo nixos-rebuild dry-build --flake .#vexos-desktop-nvidia`
   - `sudo nixos-rebuild dry-build --flake .#vexos-desktop-vm`
5. **Verify `programs.mangohud.enable` is in dry-build output** (MangoHud should appear in system closure)
6. **Verify `htop` is NOT in packages.nix** and `btop` IS
7. **Verify `permittedInsecurePackages` is absent** from configuration-stateless.nix
8. **`system.stateVersion`** unchanged in all configuration files
9. **`hardware-configuration.nix`** NOT tracked in git
