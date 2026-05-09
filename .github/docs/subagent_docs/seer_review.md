# Review: Seer (Jellyseerr / Overseerr) Module Improvements

**Feature Name:** seer  
**Spec Path:** `.github/docs/subagent_docs/seer_spec.md`  
**Review Path:** `.github/docs/subagent_docs/seer_review.md`  
**Date:** 2026-05-09  
**Verdict:** ✅ **PASS**

---

## 1. Code Quality Checklist

### 1.1 jellyseerr.nix — port option

**Requirement:** `port` option with `lib.types.port`, default `5055`.

```nix
port = lib.mkOption {
  type    = lib.types.port;
  default = 5055;
  description = "Port Jellyseerr listens on. Change if co-hosting with Overseerr.";
};
```

**Result:** ✅ PASS — Type is `lib.types.port`, default is `5055`, description is accurate.

---

### 1.2 overseerr.nix — port option

**Requirement:** `port` option with `lib.types.port`, default `5055`.

```nix
port = lib.mkOption {
  type    = lib.types.port;
  default = 5055;
  description = "Port Overseerr listens on. Change if co-hosting with Jellyseerr.";
};
```

**Result:** ✅ PASS — Symmetric with jellyseerr.nix; type, default, and description all correct.

---

### 1.3 port = cfg.port wiring

**jellyseerr.nix config block:**

```nix
config = lib.mkIf cfg.enable {
  services.jellyseerr = {
    enable      = true;
    openFirewall = true;
    port        = cfg.port;
  };
};
```

**overseerr.nix config block:**

```nix
config = lib.mkIf cfg.enable {
  services.overseerr = {
    enable      = true;
    openFirewall = true;
    port        = cfg.port;
  };
};
```

**Result:** ✅ PASS — `cfg.port` correctly wired to the underlying `services.<name>.port` option in both files.

---

### 1.4 Style consistency with project pattern

Both files follow the canonical project structure:
- Header comment with service name and note about port conflict
- `{ config, lib, pkgs, ... }:` function signature
- `let cfg = config.vexos.server.<name>;` binding
- `options` block with `enable` + typed options
- `config = lib.mkIf cfg.enable { ... }` block
- `openFirewall = true` unconditional (consistent with all other server modules)

**Result:** ✅ PASS — Style is fully consistent with the project pattern documented in the spec.

---

### 1.5 Spec compliance: configDir not exposed

The spec explicitly states: *"Do not expose `configDir` — the default `/var/lib/jellyseerr` is appropriate for this use case and adding it would be over-engineering."*

Neither file exposes `configDir`.

**Result:** ✅ PASS — No over-engineering; spec guidance followed precisely.

---

### 1.6 default.nix — both modules still imported

Confirmed `modules/server/default.nix` contains, under `# ── Media Requests ──`:

```nix
./overseerr.nix
./jellyseerr.nix
```

No changes were made to `default.nix`.

**Result:** ✅ PASS — Both modules imported; file is structurally unchanged from pre-implementation state.

---

## 2. Build Validation

### 2.1 nix flake check (pure mode)

```
$ nix flake check
error: access to absolute path '/etc' is forbidden in pure evaluation mode
       (use '--impure' to override)
EXIT: 1
```

**Assessment:** This failure is **NOT caused by the seer changes**. It is an inherent architectural constraint of the vexos-nix "thin flake" pattern, where `hardware-configuration.nix` is intentionally kept at `/etc/nixos/` (host-generated, not tracked in this repo) and imported by reference. The `preflight.sh` script explicitly accounts for this by using `nix flake check --no-build --impure` and skipping the check when `/etc/nixos/hardware-configuration.nix` is absent.

### 2.2 nix flake check --impure

```
$ nix flake check --impure
checking NixOS configuration 'nixosConfigurations.vexos-desktop-amd'...
checking NixOS configuration 'nixosConfigurations.vexos-desktop-nvidia'...
checking NixOS configuration 'nixosConfigurations.vexos-desktop-nvidia-legacy535'...
checking NixOS configuration 'nixosConfigurations.vexos-desktop-nvidia-legacy470'...
checking NixOS configuration 'nixosConfigurations.vexos-desktop-intel'...
checking NixOS configuration 'nixosConfigurations.vexos-desktop-vm'...
checking NixOS configuration 'nixosConfigurations.vexos-stateless-amd'...
checking NixOS configuration 'nixosConfigurations.vexos-stateless-nvidia'...
checking NixOS configuration 'nixosConfigurations.vexos-stateless-nvidia-legacy535'...
checking NixOS configuration 'nixosConfigurations.vexos-stateless-nvidia-legacy470'...
checking NixOS configuration 'nixosConfigurations.vexos-stateless-intel'...
checking NixOS configuration 'nixosConfigurations.vexos-stateless-vm'...
checking NixOS configuration 'nixosConfigurations.vexos-server-amd'...
checking NixOS configuration 'nixosConfigurations.vexos-server-nvidia'...
checking NixOS configuration 'nixosConfigurations.vexos-server-nvidia-legacy535'...
checking NixOS configuration 'nixosConfigurations.vexos-server-nvidia-legacy470'...
checking NixOS configuration 'nixosConfigurations.vexos-server-intel'...
checking NixOS configuration 'nixosConfigurations.vexos-server-vm'...
checking NixOS configuration 'nixosConfigurations.vexos-headless-server-amd'...
checking NixOS configuration 'nixosConfigurations.vexos-headless-server-nvidia'...
checking NixOS configuration 'nixosConfigurations.vexos-headless-server-nvidia-legacy535'...
checking NixOS configuration 'nixosConfigurations.vexos-headless-server-nvidia-legacy470'...
checking NixOS configuration 'nixosConfigurations.vexos-headless-server-intel'...
checking NixOS configuration 'nixosConfigurations.vexos-headless-server-vm'...
checking NixOS configuration 'nixosConfigurations.vexos-htpc-amd'...
checking NixOS configuration 'nixosConfigurations.vexos-htpc-nvidia'...
checking NixOS configuration 'nixosConfigurations.vexos-htpc-nvidia-legacy535'...
checking NixOS configuration 'nixosConfigurations.vexos-htpc-nvidia-legacy470'...
checking NixOS configuration 'nixosConfigurations.vexos-htpc-intel'...
checking NixOS configuration 'nixosConfigurations.vexos-htpc-vm'...
EXIT: 0
```

**Result:** ✅ PASS — All 30 NixOS configurations evaluate successfully.

### 2.3 sudo nixos-rebuild dry-build

```
$ sudo nixos-rebuild dry-build --flake .#vexos-server-amd
sudo: The "no new privileges" flag is set, which prevents sudo from running as root.
```

**Result:** NOT AVAILABLE — Container environment restricts sudo. This is an environment limitation, not a code defect. `nix flake check --impure` (which evaluates all system closures) passed successfully.

---

## 3. Safety Checks

### 3.1 hardware-configuration.nix not in git

```
$ git ls-files hardware-configuration.nix
(no output)
EXIT: 0
```

**Result:** ✅ PASS — `hardware-configuration.nix` is not tracked in this repository.

### 3.2 system.stateVersion present in configuration-desktop.nix

```
$ grep stateVersion configuration-desktop.nix
  system.stateVersion = "25.11";
EXIT: 0
```

**Result:** ✅ PASS — `system.stateVersion` is present and has not been changed.

---

## 4. Score Table

| Category | Score | Grade |
|----------|-------|-------|
| Specification Compliance | 100% | A |
| Best Practices | 100% | A |
| Functionality | 100% | A |
| Code Quality | 100% | A |
| Security | 100% | A |
| Performance | 100% | A |
| Consistency | 100% | A |
| Build Success | 95% | A |

> **Build Success note:** `nix flake check --impure` passes (all 30 configs, exit 0). Pure-mode failure is an inherent architecture constraint, not a defect. `sudo` unavailable in this environment.

**Overall Grade: A (99%)**

---

## 5. Summary

The implementation is fully compliant with the specification. Both `jellyseerr.nix` and `overseerr.nix` have been correctly updated to expose a `port` option using `lib.types.port` with a default of `5055`, wired to the underlying `services.<name>.port` option. Style is consistent with all other server modules. `default.nix` is unchanged and still imports both modules. No regressions introduced.

**Build Result:** PASS (`nix flake check --impure` — all 30 configurations evaluated successfully)  
**Overall Verdict:** ✅ **PASS**
