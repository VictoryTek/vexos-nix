# Spec: Seer (Jellyseerr / Overseerr) Server Service

**Feature Name:** seer  
**Spec Path:** `.github/docs/subagent_docs/seer_spec.md`  
**Date:** 2026-05-09  
**Status:** READY FOR IMPLEMENTATION

---

## 1. Research Summary — What Is "Seer"?

In the context of a home media server / arr stack (Radarr, Sonarr, etc.), **"Seer"** is community shorthand for one of two media request management tools:

| Tool | nixpkgs package | NixOS service | Version (25.11) | Focus |
|------|----------------|---------------|-----------------|-------|
| **Jellyseerr** | `jellyseerr` | `services.jellyseerr` | 2.7.3 | Jellyfin + Emby + Plex |
| **Overseerr** | `overseerr` | `services.overseerr` | 1.34.0 | Plex ecosystem |

**Important disambiguation**: The nixpkgs package literally named `seer` (v2.6, `github.com/epasveer/seer`) is a Qt GUI front-end for the GDB debugger — completely unrelated to media servers. It is NOT what the user is requesting.

### Recommendation

Since this project already uses **Jellyfin** (`modules/server/jellyfin.nix`), **Jellyseerr** is the correct "Seer" — it provides native Jellyfin support (plus Emby and Plex as bonus back-ends). Overseerr is Plex-only and would be redundant unless the user exclusively uses Plex.

---

## 2. Current State Analysis

### What Already Exists

Both service modules are **already implemented and registered** in `modules/server/default.nix`:

```
modules/server/overseerr.nix   — services.overseerr (Plex-focused, port 5055)
modules/server/jellyseerr.nix  — services.jellyseerr (Jellyfin/Emby/Plex, port 5055)
```

Both are already imported under the `# ── Media Requests ──` section in `modules/server/default.nix`.

### Current Implementation (jellyseerr.nix)

```nix
# modules/server/jellyseerr.nix
# Jellyseerr — media request management for Jellyfin/Emby/Plex.
# Note: Jellyseerr and Overseerr both default to port 5055 — enable only one.
{ config, lib, pkgs, ... }:
let
  cfg = config.vexos.server.jellyseerr;
in
{
  options.vexos.server.jellyseerr = {
    enable = lib.mkEnableOption "Jellyseerr media request manager";
  };

  config = lib.mkIf cfg.enable {
    services.jellyseerr = {
      enable = true;
      openFirewall = true; # Default port: 5055
    };
  };
}
```

### Current Implementation (overseerr.nix)

```nix
# modules/server/overseerr.nix
# Overseerr — media request management for Plex.
{ config, lib, pkgs, ... }:
let
  cfg = config.vexos.server.overseerr;
in
{
  options.vexos.server.overseerr = {
    enable = lib.mkEnableOption "Overseerr media request manager";
  };

  config = lib.mkIf cfg.enable {
    services.overseerr = {
      enable = true;
      openFirewall = true; # Default port: 5055
    };
  };
}
```

### Identified Gaps

1. **`jellyseerr.nix` does not expose `port`** — `services.jellyseerr.port` exists in nixpkgs 25.11 (default: 5055) but the vexos module does not surface it. This means the port cannot be customised without forking the service definition.
2. **`jellyseerr.nix` does not expose `configDir`** — `services.jellyseerr.configDir` exists in nixpkgs (default: `/var/lib/jellyseerr`) but is not surfaced.
3. **`overseerr.nix` does not expose `port`** — `services.overseerr.port` exists in nixpkgs (default: 5055) but is not surfaced.
4. The port-conflict warning exists only as a comment — no runtime guard prevents both from being enabled simultaneously.

---

## 3. NixOS Service Options (nixpkgs 25.11)

### services.jellyseerr

| Option | Type | Default | Description |
|--------|------|---------|-------------|
| `services.jellyseerr.enable` | bool | false | Enable Jellyseerr |
| `services.jellyseerr.openFirewall` | bool | false | Open firewall for the configured port |
| `services.jellyseerr.port` | port | 5055 | Port Jellyseerr listens on |
| `services.jellyseerr.configDir` | path | `/var/lib/jellyseerr` | Directory for persistent state |
| `services.jellyseerr.package` | package | `pkgs.jellyseerr` | Package to use |

### services.overseerr

| Option | Type | Default | Description |
|--------|------|---------|-------------|
| `services.overseerr.enable` | bool | false | Enable Overseerr |
| `services.overseerr.openFirewall` | bool | false | Open firewall for the configured port |
| `services.overseerr.port` | port | 5055 | Port Overseerr listens on |
| `services.overseerr.package` | package | `pkgs.overseerr` | Package to use |

**Port conflict**: Both default to port 5055. Only one may be enabled on the same host unless one is reconfigured to a different port.

---

## 4. Problem Definition

The user requested "adding Seer as a server service." Research confirms:

- "Seer" = Jellyseerr (recommended for this Jellyfin-based setup) or Overseerr (Plex-only)
- Both modules already exist and are registered
- The modules are minimal and do not expose the `port` option, making them harder to customise without host-level hacks

**The implementation task is therefore to improve the existing modules** by surfacing the `port` (and for jellyseerr: `configDir`) as vexos options, consistent with how other modules in the project are structured.

---

## 5. Proposed Solution Architecture

### Pattern Reference

All server modules follow this pattern (from `arr.nix`, `jellyfin.nix`, `docker.nix`):

```nix
{ config, lib, pkgs, ... }:
let
  cfg = config.vexos.server.<name>;
in
{
  options.vexos.server.<name> = {
    enable = lib.mkEnableOption "<description>";
    # additional typed options as needed
  };

  config = lib.mkIf cfg.enable {
    services.<name> = {
      enable = true;
      # map vexos options to nixpkgs options
    };
  };
}
```

### Improved jellyseerr.nix

Add `port` option (surfacing `services.jellyseerr.port`) to allow non-default port configuration. Keep `openFirewall = true` unconditional (consistent with all other modules). Do not expose `configDir` — the default `/var/lib/jellyseerr` is appropriate for this use case and adding it would be over-engineering.

**Target file:** `modules/server/jellyseerr.nix`

```nix
# modules/server/jellyseerr.nix
# Jellyseerr — media request management for Jellyfin/Emby/Plex.
# Note: Jellyseerr and Overseerr both default to port 5055 — enable only one.
{ config, lib, pkgs, ... }:
let
  cfg = config.vexos.server.jellyseerr;
in
{
  options.vexos.server.jellyseerr = {
    enable = lib.mkEnableOption "Jellyseerr media request manager";

    port = lib.mkOption {
      type    = lib.types.port;
      default = 5055;
      description = "Port Jellyseerr listens on. Change if co-hosting with Overseerr.";
    };
  };

  config = lib.mkIf cfg.enable {
    services.jellyseerr = {
      enable      = true;
      openFirewall = true;
      port        = cfg.port;
    };
  };
}
```

### Improved overseerr.nix

Add `port` option symmetrically.

**Target file:** `modules/server/overseerr.nix`

```nix
# modules/server/overseerr.nix
# Overseerr — media request management for Plex.
# Note: Overseerr and Jellyseerr both default to port 5055 — enable only one.
{ config, lib, pkgs, ... }:
let
  cfg = config.vexos.server.overseerr;
in
{
  options.vexos.server.overseerr = {
    enable = lib.mkEnableOption "Overseerr media request manager";

    port = lib.mkOption {
      type    = lib.types.port;
      default = 5055;
      description = "Port Overseerr listens on. Change if co-hosting with Jellyseerr.";
    };
  };

  config = lib.mkIf cfg.enable {
    services.overseerr = {
      enable      = true;
      openFirewall = true;
      port        = cfg.port;
    };
  };
}
```

### No changes to `modules/server/default.nix`

Both `./overseerr.nix` and `./jellyseerr.nix` are already imported. No structural changes required.

---

## 6. Implementation Steps

1. **Edit `modules/server/jellyseerr.nix`**  
   Replace the current minimal content with the improved version that adds the `port` option.

2. **Edit `modules/server/overseerr.nix`**  
   Replace the current minimal content with the improved version that adds the `port` option.

3. **No other files need modification** — `default.nix` already imports both; `configuration-server.nix` already imports `./modules/server`.

4. **To activate Jellyseerr**, the user adds to their `/etc/nixos/server-services.nix`:
   ```nix
   vexos.server.jellyseerr.enable = true;
   # Optional: change port if needed
   # vexos.server.jellyseerr.port = 5056;
   ```

---

## 7. Dependencies

No new dependencies required. Both `jellyseerr` and `overseerr` packages are natively available in `nixpkgs/nixos-25.11` (the channel this flake tracks). No new flake inputs needed.

---

## 8. Risks and Mitigations

| Risk | Severity | Mitigation |
|------|----------|------------|
| Port conflict: both enabled on same host at port 5055 | Medium | Existing comment warning; `port` option now allows one to be moved. Both default to 5055 — user must explicitly set a different port if enabling both. |
| `seer` package (GDB debugger) confused with media seer | Low | Spec explicitly documents the distinction. Implementation uses correct nixpkgs service names. |
| Breaking change to existing host configs | None | Adding a `port` option with default 5055 is fully backward-compatible. Existing hosts that set `vexos.server.jellyseerr.enable = true` will continue to work identically. |
| `services.jellyseerr.port` availability in 25.11 | None | Confirmed present via NixOS options search (5 options: enable, openFirewall, port, configDir, package). |
| `services.overseerr.port` availability in 25.11 | None | Confirmed present via NixOS options search (4 options: enable, openFirewall, port, package). |

---

## 9. Files Modified

| File | Action |
|------|--------|
| `modules/server/jellyseerr.nix` | Edit — add `port` option |
| `modules/server/overseerr.nix` | Edit — add `port` option |

No new files. No deletions.

---

## 10. Verification Checklist (for Review Phase)

- [ ] `nix flake check` passes
- [ ] `sudo nixos-rebuild dry-build --flake .#vexos-server-amd` succeeds
- [ ] `modules/server/default.nix` still imports both `./jellyseerr.nix` and `./overseerr.nix`
- [ ] `hardware-configuration.nix` is NOT committed to repo
- [ ] `system.stateVersion` is unchanged
- [ ] Default port (5055) is preserved — no regression for existing hosts
- [ ] `vexos.server.jellyseerr.port` option evaluates correctly
- [ ] `vexos.server.overseerr.port` option evaluates correctly
