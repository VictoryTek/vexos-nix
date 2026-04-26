# Extract Shared Configuration Blocks — Specification

## 1. Current State Analysis

### 1.1 Duplicated Blocks Inventory

The following blocks are duplicated across all 5 `configuration-*.nix` files.

#### `networking.hostName`

| File | Line | Value |
|------|------|-------|
| configuration-desktop.nix | 30 | `lib.mkDefault "vexos"` |
| configuration-htpc.nix | 19 | `lib.mkDefault "vexos"` |
| configuration-server.nix | 18 | `lib.mkDefault "vexos"` |
| configuration-headless-server.nix | 9 | `lib.mkDefault "vexos"` |
| configuration-stateless.nix | 23 | `lib.mkDefault "vexos"` |

**Verdict: IDENTICAL** — all use `lib.mkDefault "vexos"`.

#### `time.timeZone`

| File | Line | Value |
|------|------|-------|
| configuration-desktop.nix | 33 | `"America/Chicago"` |
| configuration-htpc.nix | 22 | `"America/Chicago"` |
| configuration-server.nix | 21 | `"America/Chicago"` |
| configuration-headless-server.nix | 12 | `"America/Chicago"` |
| configuration-stateless.nix | 26 | `"America/Chicago"` |

**Verdict: IDENTICAL** — direct assignment (no mkDefault).

#### `i18n.defaultLocale`

| File | Line | Value |
|------|------|-------|
| configuration-desktop.nix | 34 | `"en_US.UTF-8"` |
| configuration-htpc.nix | 23 | `"en_US.UTF-8"` |
| configuration-server.nix | 22 | `"en_US.UTF-8"` |
| configuration-headless-server.nix | 13 | `"en_US.UTF-8"` |
| configuration-stateless.nix | 27 | `"en_US.UTF-8"` |

**Verdict: IDENTICAL** — direct assignment (no mkDefault).

#### `i18n.extraLocaleSettings`

Not present in any of the 5 configuration files. The audit item mentioned it, but it does not exist in the codebase. **No action needed.**

#### `nix.settings`

All 5 files contain the identical `nix.settings` attribute set with these values:

| Setting | Value | Identical? |
|---------|-------|------------|
| `experimental-features` | `[ "nix-command" "flakes" ]` | ✅ |
| `trusted-users` | `[ "root" "@wheel" ]` | ✅ |
| `auto-optimise-store` | `true` | ✅ |
| `substituters` | `[ "https://cache.nixos.org" ]` | ✅ |
| `trusted-public-keys` | `[ "cache.nixos.org-1:6NCHdD59X431o0gWypbMrAURkbJ16ZPMQFGspcDShjY=" ]` | ✅ |
| `max-jobs` | `1` | ✅ |
| `cores` | `0` | ✅ |
| `min-free` | `1073741824` | ✅ |
| `max-free` | `5368709120` | ✅ |
| `download-buffer-size` | `524288000` | ✅ |
| `keep-outputs` | `false` | ✅ |
| `keep-derivations` | `false` | ✅ |

**Verdict: IDENTICAL** across all 5. Desktop and Stateless have verbose comments; htpc/server/headless-server have compact comments. Values are byte-for-byte identical.

Line ranges per file:

| File | Lines |
|------|-------|
| configuration-desktop.nix | 52–99 |
| configuration-htpc.nix | 37–56 |
| configuration-server.nix | 41–60 |
| configuration-headless-server.nix | 57–75 |
| configuration-stateless.nix | 54–101 |

#### `nix.daemonCPUSchedPolicy` and `nix.daemonIOSchedClass`

| File | Lines | Values |
|------|-------|--------|
| configuration-desktop.nix | 101–102 | `"idle"`, `"idle"` |
| configuration-htpc.nix | 58–59 | `"idle"`, `"idle"` |
| configuration-server.nix | 62–63 | `"idle"`, `"idle"` |
| configuration-headless-server.nix | 76–77 | `"idle"`, `"idle"` |
| configuration-stateless.nix | 103–104 | `"idle"`, `"idle"` |

**Verdict: IDENTICAL**.

#### `nix.gc`

All 5 contain:
```nix
nix.gc = {
  automatic = true;
  dates = "weekly";
  options = "--delete-older-than 7d";
};
```

| File | Lines |
|------|-------|
| configuration-desktop.nix | 104–108 |
| configuration-htpc.nix | 61–65 |
| configuration-server.nix | 65–69 |
| configuration-headless-server.nix | 79–83 |
| configuration-stateless.nix | 106–110 |

**Verdict: IDENTICAL**.

#### `nix.optimise`

All 5 contain:
```nix
nix.optimise = {
  automatic = true;
  dates = [ "weekly" ];
};
```

| File | Lines |
|------|-------|
| configuration-desktop.nix | 112–115 |
| configuration-htpc.nix | 67–70 |
| configuration-server.nix | 71–74 |
| configuration-headless-server.nix | 85–88 |
| configuration-stateless.nix | 114–117 |

**Verdict: IDENTICAL**.

#### `nixpkgs.config.allowUnfree`

| File | Line | Value |
|------|------|-------|
| configuration-desktop.nix | 123 | `true` |
| configuration-htpc.nix | 76 | `true` |
| configuration-server.nix | 80 | `true` |
| configuration-headless-server.nix | 97 | `true` |
| configuration-stateless.nix | 127 | `true` |

**Verdict: IDENTICAL**.

#### `users.users.nimda`

| File | Lines | `isNormalUser` | `description` | `initialPassword` | `extraGroups` |
|------|-------|---------------|---------------|-------------------|---------------|
| desktop | 40–49 | `true` | `"nimda"` | — | `wheel`, `networkmanager`, `gamemode`, `audio`, `input`, `plugdev` |
| htpc | 26–34 | `true` | `"nimda"` | — | `wheel`, `networkmanager`, `audio` |
| server | 35–42 | `true` | `"nimda"` | — | `wheel`, `networkmanager` |
| headless-server | 49–55 | `true` | `"nimda"` | — | `wheel`, `networkmanager` |
| stateless | 34–44 | `true` | `"nimda"` | `"vexos"` | `wheel`, `networkmanager`, `audio` |

**Common subset (all 5):**
- `isNormalUser = true`
- `description = "nimda"`
- `extraGroups`: `wheel`, `networkmanager`

**Differs by role:**
- `extraGroups` additional entries: `gamemode`, `audio`, `input`, `plugdev` (desktop); `audio` (htpc, stateless)
- `initialPassword = "vexos"` (stateless only)

### 1.2 Service Module Group Delegation Analysis

Several service modules already follow the pattern of adding their own groups to `nimda`:

| Module | Groups Added | Pattern |
|--------|-------------|---------|
| `modules/virtualization.nix` | `libvirtd` | `users.users.nimda.extraGroups = [ "libvirtd" ];` |
| `modules/server/docker.nix` | `docker` | `users.users.nimda.extraGroups = [ "docker" ];` |
| `modules/server/jellyfin.nix` | `jellyfin` | `users.users.nimda.extraGroups = [ "jellyfin" ];` |
| `modules/server/plex.nix` | `plex` | `users.users.nimda.extraGroups = [ "plex" ];` |
| `modules/server/komga.nix` | `komga` | `users.users.nimda.extraGroups = [ "komga" ];` |
| `modules/server/arr.nix` | `sabnzbd`, `sonarr`, `radarr`, `lidarr` | `users.users.nimda.extraGroups = [ ... ];` |

**Missing delegations (groups hardcoded in configuration-\*.nix but not in their service module):**

| Group | Currently in | Natural owner module | Status |
|-------|-------------|---------------------|--------|
| `gamemode` | configuration-desktop.nix | `modules/gaming.nix` | ❌ Not delegated |
| `audio` | desktop, htpc, stateless configs | `modules/audio.nix` | ❌ Not delegated |
| `input` | configuration-desktop.nix | `modules/gaming.nix` | ❌ Not delegated |
| `plugdev` | configuration-desktop.nix | `modules/gaming.nix` | ❌ Not delegated |

**Finding:** `gaming.nix` does not add `gamemode`, `input`, or `plugdev` to nimda. `audio.nix` does not add `audio` to nimda. These groups are hardcoded in the configuration-\*.nix files. Delegating them to their respective service modules (following the established `virtualization.nix` pattern) would eliminate even the role-specific extraGroups lines from the configuration files.

### 1.3 Current Import Lists

**configuration-desktop.nix (21 imports):**
```
./modules/gnome.nix
./modules/gnome-desktop.nix
./modules/gaming.nix
./modules/audio.nix
./modules/gpu.nix
./modules/gpu-gaming.nix
./modules/flatpak.nix
./modules/flatpak-desktop.nix
./modules/network.nix
./modules/network-desktop.nix
./modules/packages-common.nix
./modules/packages-desktop.nix
./modules/development.nix
./modules/virtualization.nix
./modules/branding.nix
./modules/branding-display.nix
./modules/system.nix
./modules/system-gaming.nix
./modules/system-nosleep.nix
```

**configuration-htpc.nix (14 imports):**
```
./modules/gnome.nix
./modules/gnome-htpc.nix
./modules/audio.nix
./modules/gpu.nix
./modules/flatpak.nix
./modules/network.nix
./modules/network-desktop.nix
./modules/packages-common.nix
./modules/packages-desktop.nix
./modules/packages-htpc.nix
./modules/branding.nix
./modules/branding-display.nix
./modules/system.nix
./modules/system-nosleep.nix
```

**configuration-server.nix (14 imports):**
```
./modules/gnome.nix
./modules/gnome-server.nix
./modules/audio.nix
./modules/gpu.nix
./modules/branding.nix
./modules/branding-display.nix
./modules/flatpak.nix
./modules/network.nix
./modules/network-desktop.nix
./modules/packages-common.nix
./modules/packages-desktop.nix
./modules/system.nix
./modules/server
```

**configuration-headless-server.nix (6 imports):**
```
./modules/gpu.nix
./modules/branding.nix
./modules/network.nix
./modules/packages-common.nix
./modules/system.nix
./modules/server
```

**configuration-stateless.nix (14 imports):**
```
./modules/gnome.nix
./modules/gnome-stateless.nix
./modules/audio.nix
./modules/gpu.nix
./modules/flatpak.nix
./modules/network.nix
./modules/network-desktop.nix
./modules/packages-common.nix
./modules/packages-desktop.nix
./modules/branding.nix
./modules/branding-display.nix
./modules/system.nix
./modules/impermanence.nix
```

**Common imports (all 5):** `network.nix`, `packages-common.nix`, `system.nix`, `gpu.nix`, `branding.nix`.

---

## 2. Problem Definition

### Quantified Duplication

| Block | Lines per config (avg) | × 5 configs | Total duplicated |
|-------|----------------------|-------------|-----------------|
| `nix.settings` | 20 | 100 | 100 |
| `nix.daemonCPUSchedPolicy` + `daemonIOSchedClass` | 2 | 10 | 10 |
| `nix.gc` | 5 | 25 | 25 |
| `nix.optimise` | 4 | 20 | 20 |
| `nixpkgs.config.allowUnfree` | 1 | 5 | 5 |
| `networking.hostName` | 1 | 5 | 5 |
| `time.timeZone` | 1 | 5 | 5 |
| `i18n.defaultLocale` | 1 | 5 | 5 |
| `users.users.nimda` (common part) | 6 | 30 | 30 |
| **Total** | **~41** | **~205** | **~205** |

After extraction: ~50 lines in new modules + ~5 lines of role-specific overrides retained across configs.

**Estimated net reduction: ~150 lines** (comments included in the extraction will be consolidated into the module).

### Architecture Reference

Per Option B architecture rules (`.github/copilot-instructions.md`):
- Universal base files contain ONLY settings that apply to ALL roles.
- Role-specific additions go in `modules/<subsystem>-<qualifier>.nix`.
- A `configuration-*.nix` expresses its role entirely through its import list.
- No `lib.mkIf` guards that gate content by role.

All blocks identified above are **identical** across all 5 roles (or have a cleanly separable common subset), making them candidates for universal base modules.

---

## 3. Proposed Solution Architecture

### 3.1 New / Modified Module Files

| File | Action | Responsibility |
|------|--------|---------------|
| `modules/nix.nix` | **CREATE** | All `nix.*` settings, `nix.gc`, `nix.optimise`, `nix.daemon*`, `nixpkgs.config.allowUnfree` |
| `modules/locale.nix` | **CREATE** | `time.timeZone`, `i18n.defaultLocale` |
| `modules/users.nix` | **CREATE** | Common `users.users.nimda` definition |
| `modules/network.nix` | **MODIFY** | Add `networking.hostName = lib.mkDefault "vexos";` |
| `modules/audio.nix` | **MODIFY** | Add `users.users.nimda.extraGroups = [ "audio" ];` |
| `modules/gaming.nix` | **MODIFY** | Add `users.users.nimda.extraGroups = [ "gamemode" "input" "plugdev" ];` |
| `configuration-desktop.nix` | **MODIFY** | Remove extracted blocks, add 3 new imports |
| `configuration-htpc.nix` | **MODIFY** | Remove extracted blocks, add 3 new imports |
| `configuration-server.nix` | **MODIFY** | Remove extracted blocks, add 3 new imports |
| `configuration-headless-server.nix` | **MODIFY** | Remove extracted blocks, add 3 new imports |
| `configuration-stateless.nix` | **MODIFY** | Remove extracted blocks, add 3 new imports |

### 3.2 Per-Setting Migration Table

| Setting | Target Module | Priority | Notes |
|---------|--------------|----------|-------|
| `nix.settings.experimental-features` | `modules/nix.nix` | direct | Universal |
| `nix.settings.trusted-users` | `modules/nix.nix` | direct | Universal |
| `nix.settings.auto-optimise-store` | `modules/nix.nix` | direct | Universal |
| `nix.settings.substituters` | `modules/nix.nix` | direct | Universal |
| `nix.settings.trusted-public-keys` | `modules/nix.nix` | direct | Universal |
| `nix.settings.max-jobs` | `modules/nix.nix` | `lib.mkDefault` | Allows host override for beefy hardware |
| `nix.settings.cores` | `modules/nix.nix` | direct | `0` = auto-detect, universal |
| `nix.settings.min-free` | `modules/nix.nix` | direct | Universal |
| `nix.settings.max-free` | `modules/nix.nix` | direct | Universal |
| `nix.settings.download-buffer-size` | `modules/nix.nix` | direct | Universal |
| `nix.settings.keep-outputs` | `modules/nix.nix` | direct | Universal |
| `nix.settings.keep-derivations` | `modules/nix.nix` | direct | Universal |
| `nix.daemonCPUSchedPolicy` | `modules/nix.nix` | direct | Universal |
| `nix.daemonIOSchedClass` | `modules/nix.nix` | direct | Universal |
| `nix.gc.*` | `modules/nix.nix` | direct | Universal |
| `nix.optimise.*` | `modules/nix.nix` | direct | Universal |
| `nixpkgs.config.allowUnfree` | `modules/nix.nix` | direct | Universal |
| `time.timeZone` | `modules/locale.nix` | `lib.mkDefault` | Allows host/role override |
| `i18n.defaultLocale` | `modules/locale.nix` | `lib.mkDefault` | Allows host/role override |
| `networking.hostName` | `modules/network.nix` | `lib.mkDefault` | Already mkDefault; natural home |
| `users.users.nimda.isNormalUser` | `modules/users.nix` | direct | Universal |
| `users.users.nimda.description` | `modules/users.nix` | direct | Universal |
| `users.users.nimda.extraGroups` (common: `wheel`, `networkmanager`) | `modules/users.nix` | direct | NixOS merges lists |
| `users.users.nimda.extraGroups` `audio` | `modules/audio.nix` | direct | Delegated to service module |
| `users.users.nimda.extraGroups` `gamemode`, `input`, `plugdev` | `modules/gaming.nix` | direct | Delegated to service module |
| `users.users.nimda.initialPassword` | stays in `configuration-stateless.nix` | direct | Stateless-only |

### 3.3 Handling Role-Specific Differences

1. **`users.users.nimda.extraGroups`**: NixOS merges `listOf str` options across modules. The base module declares `["wheel" "networkmanager"]`. Service modules (`audio.nix`, `gaming.nix`, `virtualization.nix`) append their groups via the same `users.users.nimda.extraGroups` attribute. No configuration-\*.nix file needs to declare any extraGroups after this refactor.

2. **`users.users.nimda.initialPassword`**: Only set by `configuration-stateless.nix`. Remains there. The base `modules/users.nix` does not set `initialPassword` or `hashedPassword`, leaving it undefined (NixOS default: no password, login via SSH key or other auth).

3. **`nix.settings.max-jobs`**: Currently `1` everywhere. Wrapped in `lib.mkDefault` so a host file (e.g., `hosts/desktop-amd.nix`) can override to a higher value for powerful hardware.

4. **`time.timeZone` and `i18n.defaultLocale`**: Wrapped in `lib.mkDefault` so a future role or host can override if needed (e.g., a server in a different timezone).

5. **`nixpkgs.config.chromium.enableWidevineCdm`**: HTPC-only, remains in `configuration-htpc.nix`.

### 3.4 Module Content Sketches

#### `modules/nix.nix`

```nix
# modules/nix.nix
# Nix daemon configuration: flakes, binary caches, GC, store optimisation,
# and daemon scheduling. Applies to all roles.
{ lib, ... }:
{
  nix.settings = {
    experimental-features = [ "nix-command" "flakes" ];
    trusted-users = [ "root" "@wheel" ];
    auto-optimise-store = true;

    substituters = [
      "https://cache.nixos.org"
    ];
    trusted-public-keys = [
      "cache.nixos.org-1:6NCHdD59X431o0gWypbMrAURkbJ16ZPMQFGspcDShjY="
    ];

    max-jobs = lib.mkDefault 1;
    cores = 0;

    min-free = 1073741824;   # 1 GiB
    max-free = 5368709120;   # 5 GiB

    download-buffer-size = 524288000; # 500 MiB

    keep-outputs = false;
    keep-derivations = false;
  };

  nix.daemonCPUSchedPolicy = "idle";
  nix.daemonIOSchedClass = "idle";

  nix.gc = {
    automatic = true;
    dates = "weekly";
    options = "--delete-older-than 7d";
  };

  nix.optimise = {
    automatic = true;
    dates = [ "weekly" ];
  };

  nixpkgs.config.allowUnfree = true;
}
```

#### `modules/locale.nix`

```nix
# modules/locale.nix
# Timezone and internationalisation defaults. Applies to all roles.
{ lib, ... }:
{
  time.timeZone      = lib.mkDefault "America/Chicago";
  i18n.defaultLocale = lib.mkDefault "en_US.UTF-8";
}
```

#### `modules/users.nix`

```nix
# modules/users.nix
# Primary user account. Applies to all roles.
# Role-specific groups are appended by service modules (audio.nix, gaming.nix,
# virtualization.nix, etc.) via NixOS list merging.
{ ... }:
{
  users.users.nimda = {
    isNormalUser = true;
    description  = "nimda";
    extraGroups  = [
      "wheel"
      "networkmanager"
    ];
  };
}
```

#### `modules/network.nix` addition

Add after `networking.networkmanager.enable = true;`:
```nix
  networking.hostName = lib.mkDefault "vexos";
```

#### `modules/audio.nix` addition

Add at end of file (before closing `}`):
```nix
  # Grant nimda raw ALSA access (optional alongside PipeWire).
  users.users.nimda.extraGroups = [ "audio" ];
```

#### `modules/gaming.nix` addition

Add at end of file (before closing `}`):
```nix
  # Grant nimda access to GameMode CPU governor, input devices, and USB peripherals.
  users.users.nimda.extraGroups = [ "gamemode" "input" "plugdev" ];
```

---

## 4. Implementation Steps

### Step 1: Create `modules/nix.nix`

**File:** `modules/nix.nix` (new)
**Content:** Full `nix.settings`, `nix.daemonCPUSchedPolicy`, `nix.daemonIOSchedClass`, `nix.gc`, `nix.optimise`, and `nixpkgs.config.allowUnfree` as shown in §3.4. Consolidate comments from the verbose (desktop/stateless) and compact (htpc/server/headless) variants into a single clear set.

### Step 2: Create `modules/locale.nix`

**File:** `modules/locale.nix` (new)
**Content:** `time.timeZone` and `i18n.defaultLocale` with `lib.mkDefault` as shown in §3.4.

### Step 3: Create `modules/users.nix`

**File:** `modules/users.nix` (new)
**Content:** Common user definition as shown in §3.4. No `initialPassword`, no role-specific groups.

### Step 4: Add `networking.hostName` to `modules/network.nix`

**File:** `modules/network.nix` (modify)
**Change:** Add `networking.hostName = lib.mkDefault "vexos";` after the `networking.networkmanager.enable` line.

### Step 5: Delegate `audio` group to `modules/audio.nix`

**File:** `modules/audio.nix` (modify)
**Change:** Add `users.users.nimda.extraGroups = [ "audio" ];` inside the config block.

### Step 6: Delegate gaming groups to `modules/gaming.nix`

**File:** `modules/gaming.nix` (modify)
**Change:** Add `users.users.nimda.extraGroups = [ "gamemode" "input" "plugdev" ];` inside the config block.

### Step 7: Update `configuration-desktop.nix`

**Add imports:** `./modules/nix.nix`, `./modules/locale.nix`, `./modules/users.nix`
**Remove:**
- `networking.hostName` line (line 30)
- `time.timeZone` line (line 33)
- `i18n.defaultLocale` line (line 34)
- Entire `users.users.nimda` block (lines 40–49)
- Entire `nix.settings` block (lines 52–99)
- `nix.daemonCPUSchedPolicy` and `nix.daemonIOSchedClass` lines (lines 101–102)
- Entire `nix.gc` block (lines 104–108)
- Entire `nix.optimise` block (lines 112–115)
- `nixpkgs.config.allowUnfree` line (line 123)
- Associated section comments for removed blocks
**Stays:**
- All existing imports (unchanged except additions)
- `vexos.branding.role = "desktop";`
- `boot.plymouth.enable = true;`
- `environment.systemPackages` (gnome-boxes, popsicle)
- `system.stateVersion = "25.11";`

### Step 8: Update `configuration-htpc.nix`

**Add imports:** `./modules/nix.nix`, `./modules/locale.nix`, `./modules/users.nix`
**Remove:**
- `networking.hostName` line (line 19)
- `time.timeZone` line (line 22)
- `i18n.defaultLocale` line (line 23)
- Entire `users.users.nimda` block (lines 26–34)
- Entire `nix.settings` block (lines 37–56)
- `nix.daemonCPUSchedPolicy` and `nix.daemonIOSchedClass` lines (lines 58–59)
- Entire `nix.gc` block (lines 61–65)
- Entire `nix.optimise` block (lines 67–70)
- `nixpkgs.config.allowUnfree` line (line 76)
- Associated section comments for removed blocks
**Stays:**
- All existing imports + additions
- `nixpkgs.config.chromium.enableWidevineCdm = true;`
- `system.stateVersion = "25.11";`
- `vexos.flatpak.excludeApps`, `vexos.flatpak.extraApps`
- Branding overrides, plymouth
- `environment.systemPackages` (bibata, kora, ghostty, plex-desktop)
- `programs.dconf.profiles.user.databases` block

### Step 9: Update `configuration-server.nix`

**Add imports:** `./modules/nix.nix`, `./modules/locale.nix`, `./modules/users.nix`
**Remove:**
- `networking.hostName` line (line 18)
- `time.timeZone` line (line 21)
- `i18n.defaultLocale` line (line 22)
- Entire `users.users.nimda` block (lines 35–42)
- Entire `nix.settings` block (lines 45–64)
- `nix.daemonCPUSchedPolicy` and `nix.daemonIOSchedClass` lines (lines 66–67)
- Entire `nix.gc` block (lines 69–73)
- Entire `nix.optimise` block (lines 75–78)
- `nixpkgs.config.allowUnfree` line (line 80)
- Associated section comments for removed blocks
**Stays:**
- All existing imports + additions
- Branding overrides, plymouth
- `system.stateVersion = "25.11";`
- `vexos.flatpak.excludeApps`
- Server role placeholder comment

### Step 10: Update `configuration-headless-server.nix`

**Add imports:** `./modules/nix.nix`, `./modules/locale.nix`, `./modules/users.nix`
**Remove:**
- `networking.hostName` line (line 9)
- `time.timeZone` line (line 12)
- `i18n.defaultLocale` line (line 13)
- Entire `users.users.nimda` block (lines 49–55)
- Entire `nix.settings` block (lines 58–75)
- `nix.daemonCPUSchedPolicy` and `nix.daemonIOSchedClass` lines (lines 76–77)
- Entire `nix.gc` block (lines 79–83)
- Entire `nix.optimise` block (lines 85–88)
- `nixpkgs.config.allowUnfree` line (line 97)
- Associated section comments for removed blocks
**Stays:**
- All existing imports + additions
- Console settings (`console.earlySetup`, `console.packages`, `console.font`)
- `services.xserver.enable = lib.mkForce false;`
- Branding settings (`vexos.branding.role = "headless-server";`, distroName override)
- `system.stateVersion = "25.11";`

### Step 11: Update `configuration-stateless.nix`

**Add imports:** `./modules/nix.nix`, `./modules/locale.nix`, `./modules/users.nix`
**Remove:**
- `networking.hostName` line (line 23)
- `time.timeZone` line (line 26)
- `i18n.defaultLocale` line (line 27)
- Entire `users.users.nimda` block (lines 34–44) — **BUT** retain `users.users.nimda.initialPassword = "vexos";` with its comment as a standalone assignment
- Entire `nix.settings` block (lines 54–101)
- `nix.daemonCPUSchedPolicy` and `nix.daemonIOSchedClass` lines (lines 103–104)
- Entire `nix.gc` block (lines 106–110)
- Entire `nix.optimise` block (lines 114–117)
- `nixpkgs.config.allowUnfree` line (line 127)
- Associated section comments for removed blocks
**Stays:**
- All existing imports + additions
- `users.users.nimda.initialPassword = "vexos";` (with its comment)
- `vexos.branding.role = "stateless";`
- `boot.plymouth.enable = true;`
- `vexos.impermanence.enable = true;`
- `environment.systemPackages` (tor-browser, gimp-hidden)
- `vexos.flatpak.excludeApps`
- `system.stateVersion = "25.11";`

---

## 5. Semantic-Equivalence Checklist

For each role, the final evaluated values MUST be identical before and after.

### 5.1 `nix.settings`

| Setting | Before (all roles) | After (all roles) | Source |
|---------|--------------------|--------------------|--------|
| `experimental-features` | `["nix-command" "flakes"]` | `["nix-command" "flakes"]` | `modules/nix.nix` |
| `trusted-users` | `["root" "@wheel"]` | `["root" "@wheel"]` | `modules/nix.nix` |
| `auto-optimise-store` | `true` | `true` | `modules/nix.nix` |
| `substituters` | `["https://cache.nixos.org"]` | `["https://cache.nixos.org"]` | `modules/nix.nix` |
| `trusted-public-keys` | `["cache.nixos.org-1:..."]` | `["cache.nixos.org-1:..."]` | `modules/nix.nix` |
| `max-jobs` | `1` | `1` (mkDefault) | `modules/nix.nix` |
| `cores` | `0` | `0` | `modules/nix.nix` |
| `min-free` | `1073741824` | `1073741824` | `modules/nix.nix` |
| `max-free` | `5368709120` | `5368709120` | `modules/nix.nix` |
| `download-buffer-size` | `524288000` | `524288000` | `modules/nix.nix` |
| `keep-outputs` | `false` | `false` | `modules/nix.nix` |
| `keep-derivations` | `false` | `false` | `modules/nix.nix` |

### 5.2 `nix.gc`, `nix.optimise`, daemon scheduling

| Setting | Before (all) | After (all) |
|---------|-------------|-------------|
| `nix.gc.automatic` | `true` | `true` |
| `nix.gc.dates` | `"weekly"` | `"weekly"` |
| `nix.gc.options` | `"--delete-older-than 7d"` | `"--delete-older-than 7d"` |
| `nix.optimise.automatic` | `true` | `true` |
| `nix.optimise.dates` | `["weekly"]` | `["weekly"]` |
| `nix.daemonCPUSchedPolicy` | `"idle"` | `"idle"` |
| `nix.daemonIOSchedClass` | `"idle"` | `"idle"` |

### 5.3 `time.timeZone`, `i18n.defaultLocale`

| Setting | Before (all) | After (all) | Note |
|---------|-------------|-------------|------|
| `time.timeZone` | `"America/Chicago"` | `"America/Chicago"` | mkDefault in module; no override in any config → same value |
| `i18n.defaultLocale` | `"en_US.UTF-8"` | `"en_US.UTF-8"` | mkDefault in module; no override in any config → same value |

### 5.4 `networking.hostName`

| Role | Before | After | Note |
|------|--------|-------|------|
| All 5 | `"vexos"` (mkDefault) | `"vexos"` (mkDefault, from network.nix) | Identical — already mkDefault |

### 5.5 `users.users.nimda.extraGroups`

| Role | Before | After | Source breakdown |
|------|--------|-------|-----------------|
| desktop | `wheel`, `networkmanager`, `gamemode`, `audio`, `input`, `plugdev` + `libvirtd` (from virtualization.nix) | `wheel`, `networkmanager` (users.nix) + `audio` (audio.nix) + `gamemode`, `input`, `plugdev` (gaming.nix) + `libvirtd` (virtualization.nix) | ✅ Same set |
| htpc | `wheel`, `networkmanager`, `audio` | `wheel`, `networkmanager` (users.nix) + `audio` (audio.nix) | ✅ Same set |
| server | `wheel`, `networkmanager` | `wheel`, `networkmanager` (users.nix) | ✅ Same set (server does NOT import audio.nix) |
| headless-server | `wheel`, `networkmanager` | `wheel`, `networkmanager` (users.nix) | ✅ Same set (headless does NOT import audio.nix or gaming.nix) |
| stateless | `wheel`, `networkmanager`, `audio` | `wheel`, `networkmanager` (users.nix) + `audio` (audio.nix) | ✅ Same set |

**Critical verification:** headless-server does NOT import `audio.nix` or `gaming.nix`, so those modules' group additions do not apply. ✅ Correct.

### 5.6 `users.users.nimda.initialPassword`

| Role | Before | After |
|------|--------|-------|
| desktop | not set | not set |
| htpc | not set | not set |
| server | not set | not set |
| headless-server | not set | not set |
| stateless | `"vexos"` | `"vexos"` (retained in configuration-stateless.nix) |

### 5.7 `nixpkgs.config.allowUnfree`

| Role | Before | After |
|------|--------|-------|
| All 5 | `true` | `true` (from modules/nix.nix) |

---

## 6. Dependencies

**None.** This is a pure internal refactor.

- No new flake inputs
- No new nixpkgs packages
- No new external dependencies
- No changes to flake.nix
- No changes to host files
- No changes to home-*.nix

---

## 7. Risks and Mitigations

### Risk 1: `lib.mkDefault` priority conflicts

**Description:** `lib.mkDefault` sets priority 1000. If an existing host file or module sets the same option at the same priority, NixOS will error with "conflicting definitions."

**Mitigation:** Only `networking.hostName`, `time.timeZone`, `i18n.defaultLocale`, and `nix.settings.max-jobs` use `lib.mkDefault` in the new modules. `networking.hostName` was already mkDefault in all 5 configs — moving it to network.nix changes nothing. The other three were direct assignments (priority 100) in the configs but are now mkDefault (priority 1000) in modules — this is a lower priority, meaning any direct assignment elsewhere would win. No conflict possible.

### Risk 2: NixOS list-merge for extraGroups may produce duplicates

**Description:** If both `modules/users.nix` and another module declare `"wheel"` in extraGroups, the merged list would contain `"wheel"` twice.

**Mitigation:** Cosmetic only — NixOS deduplicates group membership at the system level. No service modules currently declare `"wheel"` or `"networkmanager"`, so in practice no duplicates will occur.

### Risk 3: Forgetting to import new modules

**Description:** If `modules/nix.nix`, `modules/locale.nix`, or `modules/users.nix` is not imported by a configuration-\*.nix, that role would lose its Nix settings, timezone, or user definition.

**Mitigation:** The implementation step for each configuration file explicitly lists the 3 new imports. Validation via `nix eval` (§9) will immediately surface a missing import as an evaluation error (undefined user, missing nix settings).

### Risk 4: `nix.settings` merge semantics for attrsets

**Description:** NixOS merges `nix.settings` (an attrset) across modules. If a future module also sets `nix.settings.experimental-features`, the lists would merge.

**Mitigation:** No other module in this project sets `nix.settings`. The risk is theoretical and applies to any future addition, not this refactor.

### Risk 5: Stateless `initialPassword` regression

**Description:** If the implementation accidentally removes `initialPassword` from `configuration-stateless.nix` without retaining it as a standalone assignment.

**Mitigation:** Step 11 explicitly states `initialPassword` must be retained. The semantic-equivalence checklist in §5.6 verifies it.

---

## 8. Out of Scope

The following items are explicitly **not** part of this extraction:

- Refactoring `modules/system.nix` btrfs/swap logic (audit items A3/A4)
- Any module-architecture changes beyond the specific extraction described
- Changes to `flake.nix`
- Changes to any file under `hosts/`
- Changes to any `home-*.nix` file
- README, justfile, or preflight script updates
- Adding `i18n.extraLocaleSettings` (does not exist in the codebase)
- Refactoring HTPC-specific settings (Widevine, dconf, flatpak extras)
- Refactoring headless-server console settings
- Creating new role-qualifier modules (e.g., `modules/users-stateless.nix` for initialPassword — the single-line override does not warrant its own file)

---

## 9. Validation Plan

### 9.1 Structural Evaluation

Run `nix eval` for all 5 representative configurations to confirm they evaluate without errors:

```bash
for cfg in vexos-desktop-amd vexos-htpc-amd vexos-server-amd vexos-headless-server-amd vexos-stateless-amd; do
  echo "=== $cfg ==="
  nix eval --impure --raw ".#nixosConfigurations.$cfg.config.system.build.toplevel.drvPath" 2>&1 | tail -5
  echo " EXIT=$?"
done
```

### 9.2 Spot-Check: `nix.settings.max-jobs`

```bash
for cfg in vexos-desktop-amd vexos-server-amd vexos-headless-server-amd; do
  printf "%-30s " "$cfg"
  nix eval --impure ".#nixosConfigurations.$cfg.config.nix.settings.max-jobs"
done
```

Expected: `1` for all three.

### 9.3 Spot-Check: `users.users.nimda.extraGroups`

```bash
for cfg in vexos-desktop-amd vexos-htpc-amd vexos-headless-server-amd; do
  echo "=== $cfg ==="
  nix eval --impure --json ".#nixosConfigurations.$cfg.config.users.users.nimda.extraGroups" | jq .
done
```

Expected:
- desktop-amd: contains `wheel`, `networkmanager`, `gamemode`, `audio`, `input`, `plugdev`, `libvirtd`
- htpc-amd: contains `wheel`, `networkmanager`, `audio`
- headless-server-amd: contains `wheel`, `networkmanager`

### 9.4 Spot-Check: `time.timeZone`

```bash
for cfg in vexos-desktop-amd vexos-server-amd vexos-stateless-amd; do
  printf "%-30s " "$cfg"
  nix eval --impure --raw ".#nixosConfigurations.$cfg.config.time.timeZone"
  echo
done
```

Expected: `America/Chicago` for all three.

### 9.5 Spot-Check: `initialPassword` (stateless only)

```bash
nix eval --impure --raw ".#nixosConfigurations.vexos-stateless-amd.config.users.users.nimda.initialPassword"
```

Expected: `vexos`

### 9.6 Flake Check

```bash
nix flake check
```

Must pass.
