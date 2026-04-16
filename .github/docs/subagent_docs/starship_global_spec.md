# Starship Global Configuration — Specification

## Current State Analysis

### Starship Status Per Role

| Role | `programs.starship` | `xdg.configFile."starship.toml"` | `programs.bash.enable` |
|------|---------------------|----------------------------------|------------------------|
| Desktop (`home-desktop.nix`) | **Yes** — lines 69-72 | **Yes** — line 74 | **Yes** — line 55 |
| Server (`home-server.nix`) | **Yes** — lines 56-59 | **Yes** — line 61 | **Yes** — line 43 |
| Stateless (`home-stateless.nix`) | **Yes** — lines 61-64 | **Yes** — line 66 | **Yes** — line 43 |
| HTPC (`home-htpc.nix`) | **MISSING** | **MISSING** | **MISSING** |

### How Starship Is Currently Configured

In the three roles that have it, the configuration is **identical** and consists of two parts:

1. **Home Manager `programs.starship` module** — installs the `starship` binary and injects `eval "$(starship init bash)"` into `.bashrc`:
   ```nix
   programs.starship = {
     enable = true;
     enableBashIntegration = true;
   };
   ```

2. **Config file deployment via `xdg.configFile`** — copies the repo's `files/starship.toml` to `~/.config/starship.toml`:
   ```nix
   xdg.configFile."starship.toml".source = ./files/starship.toml;
   ```

### Configuration File

`files/starship.toml` exists in the repo root with a complete two-line prompt layout: username, hostname, directory, git status, command duration on line 1; battery and character prompt on line 2. Includes Nerd Font symbols for language/tool indicators.

### Architecture Context

- All four roles use **Home Manager** for user `nimda` (configured in `flake.nix`)
- The `flake.nix` defines role-specific Home Manager modules that import `home-desktop.nix`, `home-htpc.nix`, `home-server.nix`, or `home-stateless.nix`
- `home-manager.useGlobalPkgs = true` and `home-manager.useUserPackages = true` are set for all roles
- Shared system packages live in `modules/packages.nix` (imported by all `configuration-*.nix` files)
- The project has a `home/` directory for shared Home Manager sub-modules (precedent: `home/photogimp.nix`)

### Dependency on `programs.bash`

Home Manager's `programs.starship` with `enableBashIntegration = true` requires `programs.bash.enable = true` to inject the init line into `.bashrc`. Without bash management, starship is installed but **never activates**.

`home-htpc.nix` does **not** currently enable `programs.bash`, so simply adding `programs.starship` would be insufficient — the init script would have nowhere to be written.

---

## Problem Definition

1. **HTPC role lacks starship entirely** — `home-htpc.nix` has no `programs.starship`, no `xdg.configFile."starship.toml"`, and no `programs.bash.enable`. Users on HTPC systems get a plain bash prompt.

2. **Inconsistency across roles** — Three of four roles have identical starship configuration, but HTPC does not. This violates the user's expectation that starship is applied globally.

3. **No shell management on HTPC** — Without `programs.bash.enable = true`, Home Manager cannot inject the starship init into `.bashrc`, so even adding the starship module alone would not activate the prompt.

---

## Proposed Solution Architecture

### Approach: Add Starship + Bash to `home-htpc.nix`

Add the missing starship configuration and bash shell management to `home-htpc.nix`, matching the pattern already established in the other three roles. This is the minimal, targeted change.

### Files to Modify

| File | Change |
|------|--------|
| `home-htpc.nix` | Add `programs.bash`, `programs.starship`, `xdg.configFile."starship.toml"` |

### Files NOT Modified

| File | Reason |
|------|--------|
| `flake.nix` | No structural changes needed — HTPC already uses Home Manager |
| `configuration-htpc.nix` | System-level config; starship is user-level via Home Manager |
| `modules/packages.nix` | Starship is installed per-user by Home Manager, not system-wide |
| `files/starship.toml` | Already exists and is correct |
| `home-desktop.nix` | Already has starship — no changes needed |
| `home-server.nix` | Already has starship — no changes needed |
| `home-stateless.nix` | Already has starship — no changes needed |

---

## Implementation Steps

### Step 1: Add `programs.bash` to `home-htpc.nix`

Insert after the `home.homeDirectory` line and before the wallpapers section. Use the same shell aliases as the other roles for consistency:

```nix
  # ── Shell ──────────────────────────────────────────────────────────────────
  programs.bash = {
    enable = true;
    shellAliases = {
      ll  = "ls -la";
      ".." = "cd ..";

      # Tailscale shortcuts
      ts   = "tailscale";
      tss  = "tailscale status";
      tsip = "tailscale ip";

      # System service shortcuts
      sshstatus = "systemctl status sshd";
      smbstatus = "systemctl status smbd";
    };
  };
```

### Step 2: Add `programs.starship` to `home-htpc.nix`

Insert immediately after the `programs.bash` block:

```nix
  # ── Starship prompt ────────────────────────────────────────────────────────
  programs.starship = {
    enable = true;
    enableBashIntegration = true;
  };

  xdg.configFile."starship.toml".source = ./files/starship.toml;
```

### Step 3: Verify `home.stateVersion` is present

`home-htpc.nix` already has `home.stateVersion = "24.05";` at the bottom — no change needed.

---

## Dependencies

| Dependency | Type | Status |
|------------|------|--------|
| `starship` package (nixpkgs) | Nix package | Available — installed by `programs.starship.enable` |
| `files/starship.toml` | Config file | Already exists in repo |
| Home Manager integration | Flake module | Already configured for HTPC in `flake.nix` (`htpcHomeManagerModule`) |
| `programs.bash.enable` | Home Manager option | Must be added to `home-htpc.nix` |

No new flake inputs or external dependencies are required.

---

## Configuration Changes

### `home-htpc.nix` — Additions

The following blocks will be added between the `home.homeDirectory` line and the `# ── Wallpapers` section:

1. `programs.bash` — enables Home Manager bash management + shell aliases
2. `programs.starship` — installs starship and injects bash init
3. `xdg.configFile."starship.toml"` — deploys the shared config file

### Insertion Point

The new blocks should be inserted after line 5 (`home.homeDirectory = "/home/nimda";`) and before line 7 (`# ── Wallpapers`). This matches the ordering convention used in `home-desktop.nix`, `home-server.nix`, and `home-stateless.nix` where shell/programs come before wallpapers/dconf.

---

## Risks and Mitigations

### Risk 1: Existing `.bashrc` on HTPC hosts

**Risk**: If an HTPC host already has a manually-created `~/.bashrc`, Home Manager activation will detect a conflict.

**Mitigation**: The project already sets `backupFileExtension = "backup"` in `flake.nix` for the `htpcHomeManagerModule`. Conflicting files are renamed to `*.backup` automatically instead of aborting activation.

### Risk 2: HTPC role has no `home.packages` for terminal utilities

**Risk**: The HTPC `home-htpc.nix` is intentionally minimal — it does not install terminal utilities (tree, ripgrep, fd, bat, eza, fzf, etc.) that the other roles include. Adding starship alone is fine, but users may want to align HTPC packages with other roles in the future.

**Mitigation**: Out of scope for this change. Starship works standalone; it does not depend on any of those utilities.

### Risk 3: `home.stateVersion` mismatch

**Risk**: `home-htpc.nix` has `home.stateVersion = "24.05"` while the other roles do not explicitly set it (inheriting from the system). This is fine — `home.stateVersion` should never be changed after initial deployment.

**Mitigation**: No change to `home.stateVersion`. This is correct behavior per NixOS/Home Manager conventions.

### Risk 4: No Nerd Font on HTPC

**Risk**: The starship configuration in `files/starship.toml` uses Nerd Font symbols (e.g., ` ` for git, ` ` for Node.js). If the HTPC terminal does not have a Nerd Font installed, these symbols will render as boxes/tofu.

**Mitigation**: This is an existing UX concern, not introduced by this change. The same `starship.toml` is already deployed on desktop, server, and stateless roles. Font installation is orthogonal to this task.

---

## Validation Criteria

After implementation:

1. `nix flake check` passes
2. All `nixos-rebuild dry-build` commands succeed for HTPC variants (amd, nvidia, intel, vm)
3. `home-htpc.nix` contains `programs.bash.enable = true`
4. `home-htpc.nix` contains `programs.starship.enable = true` with `enableBashIntegration = true`
5. `home-htpc.nix` contains `xdg.configFile."starship.toml".source = ./files/starship.toml`
6. The starship configuration is now present in all 4 roles: desktop, htpc, server, stateless
7. `hardware-configuration.nix` is NOT committed to the repository
8. `system.stateVersion` is unchanged in all configuration files

---

## Research Sources

1. **Home Manager `programs.starship` module** — Context7 `/nix-community/home-manager`: confirms `enable`, `enableBashIntegration` as the standard options; requires `programs.bash.enable = true` for init injection
2. **Home Manager FAQ: Multiple Users/Machines** — Context7 `/nix-community/home-manager`: recommends `imports = [ ./common.nix ]` pattern for shared config across machines (the project already uses this via `home/photogimp.nix`)
3. **NixOS module imports** — Context7 `/nixos/nixpkgs`: confirms standard `imports = []` pattern for modular configuration
4. **Home Manager `xdg.configFile`** — deploys files to `~/.config/` via the Home Manager activation script; `.source` copies a file from the repo
5. **Existing project patterns** — analyzed `home-desktop.nix`, `home-server.nix`, `home-stateless.nix` for the established starship configuration pattern (all identical)
6. **`flake.nix` HTPC module definition** — `htpcHomeManagerModule` already configures `backupFileExtension = "backup"` for safe activation on hosts with existing dotfiles
