# Specification: Remove `restart-to` GNOME Extension

**Feature name:** remove_restart_to_extension  
**Date:** 2026-05-28  
**Status:** READY FOR IMPLEMENTATION

---

## 1. Current State Analysis

The `restart-to` GNOME Shell extension is currently installed and enabled across all GNOME-enabled vexos roles. It appears in two distinct locations in the codebase:

### 1.1 Package installation (system-level)

**File:** `modules/gnome.nix`, line 206  
The package `pkgs.gnomeExtensions.restart-to` is listed in `environment.systemPackages` inside the `config` block.

### 1.2 Extension UUID in `vexos.gnome.commonExtensions` option

**File:** `modules/gnome.nix`, line 26  
The UUID `"restartto@tiagoporsch.github.io"` is present in the default list of the `vexos.gnome.commonExtensions` NixOS option. This option's default value is consumed by:

- `modules/gnome-stateless.nix` line 18 — `enabled-extensions = config.vexos.gnome.commonExtensions;`
- `modules/gnome-server.nix` line 18 — `enabled-extensions = config.vexos.gnome.commonExtensions;`
- `modules/gnome-htpc.nix` line 18 — `enabled-extensions = config.vexos.gnome.commonExtensions;`
- `modules/gnome-desktop.nix` line 28 — `config.vexos.gnome.commonExtensions ++ [ "gamemodeshellextension@trsnaqe.com" ]`

**These four files do NOT need modification** — they reference the option by name and will automatically reflect the removal once `gnome.nix` is updated.

### 1.3 Hard-coded UUID in home-manager dconf init scripts

Each role's `home-*.nix` file contains a one-shot systemd user service that writes `enabled-extensions` to dconf via a shell script. The extension UUID is hard-coded in the GVariant string literal in each file. These are **independent copies** that must each be updated separately.

| File | Line | Context |
|------|------|---------|
| `home-desktop.nix` | 246 | `dconf write /org/gnome/shell/enabled-extensions "['..., 'restartto@tiagoporsch.github.io', ...]"` |
| `home-server.nix` | 164 | same pattern |
| `home-htpc.nix` | 95 | same pattern |
| `home-stateless.nix` | 233 | same pattern |

**Files with no references** (confirmed clean):
- `home-vanilla.nix` — no reference
- `home-headless-server.nix` — no reference
- `configuration-*.nix` — no reference
- `flake.nix` — no reference
- All files under `home/` — no reference

---

## 2. Problem Definition

The `restart-to` GNOME Shell extension (`restartto@tiagoporsch.github.io`) is to be fully removed from all vexos roles. This includes:

1. Removing the package from the system package list.
2. Removing the UUID from the NixOS option default (affects all system-level dconf profiles).
3. Removing the UUID from each home-manager dconf init shell script.

---

## 3. Extension Identity

| Attribute | Value |
|-----------|-------|
| Nixpkgs attribute | `gnomeExtensions.restart-to` |
| Extension UUID | `restartto@tiagoporsch.github.io` |
| Previous/alternate UUID (historical, not in codebase) | `restart-to@system76.com` |

---

## 4. Proposed Solution

Straightforward line/token removal — no restructuring required.

### 4.1 `modules/gnome.nix` — two changes

#### Change A: Remove UUID from `commonExtensions` option default (line 26)

Remove this line from the list:
```nix
      "restartto@tiagoporsch.github.io"
```

**Before (lines 25–29):**
```nix
      "caffeine@patapon.info"
      "restartto@tiagoporsch.github.io"
      "blur-my-shell@aunetx"
```

**After:**
```nix
      "caffeine@patapon.info"
      "blur-my-shell@aunetx"
```

#### Change B: Remove package from `environment.systemPackages` (line 206)

Remove this line:
```nix
    pkgs.gnomeExtensions.restart-to                 # Restart-to menu entry
```

**Before (lines 205–208):**
```nix
    pkgs.gnomeExtensions.caffeine                   # Prevent screen sleep
    pkgs.gnomeExtensions.restart-to                 # Restart-to menu entry
    pkgs.gnomeExtensions.blur-my-shell              # Blur effects for shell UI
```

**After:**
```nix
    pkgs.gnomeExtensions.caffeine                   # Prevent screen sleep
    pkgs.gnomeExtensions.blur-my-shell              # Blur effects for shell UI
```

---

### 4.2 `home-desktop.nix` — remove UUID from GVariant string (line 246)

The entire dconf write command is a single long string. Remove `'restartto@tiagoporsch.github.io', ` from within the list.

**Before (abbreviated):**
```
"['..., 'caffeine@patapon.info', 'restartto@tiagoporsch.github.io', 'blur-my-shell@aunetx', ...]"
```

**After:**
```
"['..., 'caffeine@patapon.info', 'blur-my-shell@aunetx', ...]"
```

Full before string (line 246):
```
          "['appindicatorsupport@rgcjonas.gmail.com', 'dash-to-dock@micxgx.gmail.com', 'AlphabeticalAppGrid@stuarthayhurst', 'gnome-ui-tune@itstime.tech', 'nothing-to-say@extensions.gnome.wouter.bolsterl.ee', 'steal-my-focus-window@steal-my-focus-window', 'tailscale-status@maxgallup.github.com', 'caffeine@patapon.info', 'restartto@tiagoporsch.github.io', 'blur-my-shell@aunetx', 'background-logo@fedorahosted.org', 'tiling-assistant@leleat-on-github', 'gamemodeshellextension@trsnaqe.com']"
```

Full after string:
```
          "['appindicatorsupport@rgcjonas.gmail.com', 'dash-to-dock@micxgx.gmail.com', 'AlphabeticalAppGrid@stuarthayhurst', 'gnome-ui-tune@itstime.tech', 'nothing-to-say@extensions.gnome.wouter.bolsterl.ee', 'steal-my-focus-window@steal-my-focus-window', 'tailscale-status@maxgallup.github.com', 'caffeine@patapon.info', 'blur-my-shell@aunetx', 'background-logo@fedorahosted.org', 'tiling-assistant@leleat-on-github', 'gamemodeshellextension@trsnaqe.com']"
```

---

### 4.3 `home-server.nix` — remove UUID from GVariant string (line 164)

Full before string (line 164):
```
          "['appindicatorsupport@rgcjonas.gmail.com', 'dash-to-dock@micxgx.gmail.com', 'AlphabeticalAppGrid@stuarthayhurst', 'gnome-ui-tune@itstime.tech', 'nothing-to-say@extensions.gnome.wouter.bolsterl.ee', 'steal-my-focus-window@steal-my-focus-window', 'tailscale-status@maxgallup.github.com', 'caffeine@patapon.info', 'restartto@tiagoporsch.github.io', 'blur-my-shell@aunetx', 'background-logo@fedorahosted.org', 'tiling-assistant@leleat-on-github']"
```

Full after string:
```
          "['appindicatorsupport@rgcjonas.gmail.com', 'dash-to-dock@micxgx.gmail.com', 'AlphabeticalAppGrid@stuarthayhurst', 'gnome-ui-tune@itstime.tech', 'nothing-to-say@extensions.gnome.wouter.bolsterl.ee', 'steal-my-focus-window@steal-my-focus-window', 'tailscale-status@maxgallup.github.com', 'caffeine@patapon.info', 'blur-my-shell@aunetx', 'background-logo@fedorahosted.org', 'tiling-assistant@leleat-on-github']"
```

---

### 4.4 `home-htpc.nix` — remove UUID from GVariant string (line 95)

Full before string (line 95):
```
          "['appindicatorsupport@rgcjonas.gmail.com', 'dash-to-dock@micxgx.gmail.com', 'AlphabeticalAppGrid@stuarthayhurst', 'gnome-ui-tune@itstime.tech', 'nothing-to-say@extensions.gnome.wouter.bolsterl.ee', 'steal-my-focus-window@steal-my-focus-window', 'tailscale-status@maxgallup.github.com', 'caffeine@patapon.info', 'restartto@tiagoporsch.github.io', 'blur-my-shell@aunetx', 'background-logo@fedorahosted.org', 'tiling-assistant@leleat-on-github']"
```

Full after string:
```
          "['appindicatorsupport@rgcjonas.gmail.com', 'dash-to-dock@micxgx.gmail.com', 'AlphabeticalAppGrid@stuarthayhurst', 'gnome-ui-tune@itstime.tech', 'nothing-to-say@extensions.gnome.wouter.bolsterl.ee', 'steal-my-focus-window@steal-my-focus-window', 'tailscale-status@maxgallup.github.com', 'caffeine@patapon.info', 'blur-my-shell@aunetx', 'background-logo@fedorahosted.org', 'tiling-assistant@leleat-on-github']"
```

---

### 4.5 `home-stateless.nix` — remove UUID from GVariant string (line 233)

Full before string (line 233):
```
          "['appindicatorsupport@rgcjonas.gmail.com', 'dash-to-dock@micxgx.gmail.com', 'AlphabeticalAppGrid@stuarthayhurst', 'gnome-ui-tune@itstime.tech', 'nothing-to-say@extensions.gnome.wouter.bolsterl.ee', 'steal-my-focus-window@steal-my-focus-window', 'tailscale-status@maxgallup.github.com', 'caffeine@patapon.info', 'restartto@tiagoporsch.github.io', 'blur-my-shell@aunetx', 'background-logo@fedorahosted.org', 'tiling-assistant@leleat-on-github']"
```

Full after string:
```
          "['appindicatorsupport@rgcjonas.gmail.com', 'dash-to-dock@micxgx.gmail.com', 'AlphabeticalAppGrid@stuarthayhurst', 'gnome-ui-tune@itstime.tech', 'nothing-to-say@extensions.gnome.wouter.bolsterl.ee', 'steal-my-focus-window@steal-my-focus-window', 'tailscale-status@maxgallup.github.com', 'caffeine@patapon.info', 'blur-my-shell@aunetx', 'background-logo@fedorahosted.org', 'tiling-assistant@leleat-on-github']"
```

---

## 5. Implementation Steps

1. Edit `modules/gnome.nix`:
   - Remove `"restartto@tiagoporsch.github.io"` from the `commonExtensions` default list (line 26).
   - Remove `pkgs.gnomeExtensions.restart-to` from `environment.systemPackages` (line 206).

2. Edit `home-desktop.nix` (line 246): remove `'restartto@tiagoporsch.github.io', ` from the GVariant string.

3. Edit `home-server.nix` (line 164): remove `'restartto@tiagoporsch.github.io', ` from the GVariant string.

4. Edit `home-htpc.nix` (line 95): remove `'restartto@tiagoporsch.github.io', ` from the GVariant string.

5. Edit `home-stateless.nix` (line 233): remove `'restartto@tiagoporsch.github.io', ` from the GVariant string.

No imports, no conditionals, no file creation, no restructuring required. All changes are pure deletions.

---

## 6. Files That Do NOT Need Modification

| File | Reason |
|------|--------|
| `modules/gnome-desktop.nix` | References `config.vexos.gnome.commonExtensions` by name; inherits removal automatically |
| `modules/gnome-server.nix` | Same as above |
| `modules/gnome-htpc.nix` | Same as above |
| `modules/gnome-stateless.nix` | Same as above |
| `home-vanilla.nix` | No reference to the extension |
| `home-headless-server.nix` | No reference to the extension |
| `configuration-*.nix` | No direct reference |
| `flake.nix` | No direct reference |
| `home/*.nix` | No reference |
| `.github/docs/subagent_docs/*.md` | Historical documentation only; no functional impact |

---

## 7. Risks and Mitigations

| Risk | Likelihood | Mitigation |
|------|-----------|------------|
| Residual UUID in dconf on already-built systems | Medium | The HM dconf init stamp file prevents re-run; users must manually remove the stamp or reset dconf. No action needed in this repo. |
| UUID typo or partial removal in GVariant string | Low | Exact before/after strings provided in §4 above; implementer should use exact string replacement |
| `gnomeExtensions.restart-to` referenced elsewhere | Low | Exhaustive `grep_search` found only line 206 of `gnome.nix`; no other references in active Nix files |

---

## 8. Summary of Files to Modify

| # | File | Change | Complexity |
|---|------|--------|-----------|
| 1 | `modules/gnome.nix` | Remove UUID from `commonExtensions` default (line 26) | Simple deletion |
| 2 | `modules/gnome.nix` | Remove package from `environment.systemPackages` (line 206) | Simple deletion |
| 3 | `home-desktop.nix` | Remove UUID from GVariant enabled-extensions string (line 246) | Substring removal |
| 4 | `home-server.nix` | Remove UUID from GVariant enabled-extensions string (line 164) | Substring removal |
| 5 | `home-htpc.nix` | Remove UUID from GVariant enabled-extensions string (line 95) | Substring removal |
| 6 | `home-stateless.nix` | Remove UUID from GVariant enabled-extensions string (line 233) | Substring removal |

**Total files to modify: 5** (gnome.nix has 2 changes but is one file)
