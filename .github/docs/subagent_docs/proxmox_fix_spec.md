# Spec: Fix Proxmox VE Package Resolution in Server NixOS Configurations

**Date:** 2026-04-28  
**Author:** Research & Specification Agent  
**Status:** Ready for Implementation

---

## 1. Current State Analysis

### 1.1 `flake.nix` — inputs

`proxmox-nixos` **is** present in `inputs`:

```nix
proxmox-nixos.url = "github:SaumonNet/proxmox-nixos";
```

The comment deliberately omits `inputs.proxmox-nixos.inputs.nixpkgs.follows = "nixpkgs"` because the upstream flake manages its own nixpkgs-stable pin; overriding it breaks package builds.

The flake's `outputs` function signature is:

```nix
outputs = { self, nixpkgs, nixpkgs-unstable, home-manager, impermanence, up, ... }@inputs:
```

`proxmox-nixos` is accessed as `inputs.proxmox-nixos` throughout (correct, via `...@inputs`).

### 1.2 Where the proxmox NixOS module is imported

`inputs.proxmox-nixos.nixosModules.proxmox-ve` is included in two places:

**Path A — `mkHost` (nixosConfigurations):**

```nix
roles = {
  server = {
    baseModules = [ unstableOverlayModule upModule inputs.proxmox-nixos.nixosModules.proxmox-ve ];
    ...
  };
  headless-server = {
    baseModules = [ unstableOverlayModule inputs.proxmox-nixos.nixosModules.proxmox-ve ];
    ...
  };
};
```

**Path B — `mkBaseModule` (nixosModules.*Base exports):**

```nix
mkBaseModule = role: configFile: { ... }: {
  imports =
    [ home-manager.nixosModules.home-manager configFile ]
    ++ roles.${role}.extraModules
    ++ lib.optional (role == "server" || role == "headless-server")
         inputs.proxmox-nixos.nixosModules.proxmox-ve;
  ...
};
```

### 1.3 What the proxmox NixOS module does

`inputs.proxmox-nixos.nixosModules.proxmox-ve` defines the NixOS **module interface** for `services.proxmox-ve.*` options and their config blocks. It does **not** auto-apply its own overlay to `nixpkgs.overlays`. The consumer flake is responsible for adding `inputs.proxmox-nixos.overlays.default` to `nixpkgs.overlays`.

This is confirmed by the error path: the module is evaluated (the error trace shows `/nix/store/.../modules/proxmox-ve/cluster.nix`), but `pkgs.proxmox-ve` is missing — meaning the evaluation reached the module but the package was not found in `pkgs`.

### 1.4 What `just enable proxmox` changed

The recipe modified `/etc/nixos/server-services.nix` (the live host's opt-in service file):

- Uncommented / inserted `vexos.server.proxmox.enable = true;`
- Prompted for an IP address and inserted `vexos.server.proxmox.ipAddress = "<IP>";`

This file is loaded at eval time via `serverServicesModule` in `flake.nix`:

```nix
serverServicesModule =
  let path = /etc/nixos/server-services.nix;
  in if builtins.pathExists path then [ path ] else [];
```

### 1.5 What `modules/server/proxmox.nix` does

Translates `vexos.server.proxmox.enable = true` into:

```nix
services.proxmox-ve = {
  enable    = true;
  ipAddress = cfg.ipAddress;
};
```

The comment in that file says:
> ⚠ The proxmox-nixos overlay is applied by the proxmox-ve NixOS module imported at the flake level — it does not need to be re-applied here.

This comment is **incorrect** — the proxmox NixOS module does not auto-apply its overlay. The overlay must be explicitly added.

### 1.6 Why there was no error before enabling

NixOS option evaluation is lazy. The option:

```nix
services.proxmox-ve.package = lib.mkOption {
  default = pkgs.proxmox-ve;
  ...
};
```

When `services.proxmox-ve.enable = false`, the config blocks gated by `lib.mkIf config.services.proxmox-ve.enable { ... }` are never entered, so `pkgs.proxmox-ve` is never evaluated. The missing overlay goes undetected.

When `services.proxmox-ve.enable = true`, the config block is entered, `services.proxmox-ve.package` is evaluated (defaulting to `pkgs.proxmox-ve`), and since the overlay was never applied, Nix fails with:

```
error: proxmox-ve cannot be found in pkgs
```

### 1.7 Preflight scope

`scripts/preflight.sh` **does** test server hosts. Stage [2/7] dry-builds all 30 `nixosConfigurations` outputs, including all server and headless-server variants. Any fix must enable all 10 server/headless-server outputs to evaluate cleanly.

---

## 2. Root Cause

**The `proxmox-nixos` overlay (`inputs.proxmox-nixos.overlays.default`) is never added to `nixpkgs.overlays` in either `mkHost` (for direct `nixosConfigurations`) or `mkBaseModule` (for `nixosModules.*Base` exports).**

The proxmox NixOS module adds the module interface. A separate overlay is required to make `pkgs.proxmox-ve` available. Without the overlay, `pkgs.proxmox-ve` does not exist and any path that evaluates `services.proxmox-ve.package` fails.

---

## 3. Proposed Fix

### 3.1 Verify the overlay attribute name

Before implementing, confirm the overlay attribute exposed by the pinned `proxmox-nixos` input:

```bash
nix eval --json 'github:SaumonNet/proxmox-nixos#overlays' --apply builtins.attrNames
```

Expected output: `["default"]` (i.e., `inputs.proxmox-nixos.overlays.default`).

If the attribute is named differently (e.g., `overlay`), adjust accordingly.

### 3.2 Add a `proxmoxOverlayModule` in `flake.nix`

Following the same pattern as `unstableOverlayModule`, define a new inline module near the top of the `let` block:

```nix
# Proxmox VE overlay — exposes pkgs.proxmox-ve (and related Proxmox packages)
# Required by services.proxmox-ve.package (lazy default in the proxmox NixOS module).
# Scoped to server / headless-server roles only.
proxmoxOverlayModule = {
  nixpkgs.overlays = [ inputs.proxmox-nixos.overlays.default ];
};
```

### 3.3 Add `proxmoxOverlayModule` to Path A — `roles` (fixes `mkHost`)

In the `roles` attrset, add `proxmoxOverlayModule` to the `baseModules` of both server roles:

```nix
server = {
  homeFile     = ./home-server.nix;
  baseModules  = [ unstableOverlayModule upModule proxmoxOverlayModule inputs.proxmox-nixos.nixosModules.proxmox-ve ];
  extraModules = serverServicesModule;
};
headless-server = {
  homeFile     = ./home-headless-server.nix;
  baseModules  = [ unstableOverlayModule proxmoxOverlayModule inputs.proxmox-nixos.nixosModules.proxmox-ve ];
  extraModules = serverServicesModule;
};
```

### 3.4 Add `proxmoxOverlayModule` to Path B — `mkBaseModule` (fixes `nixosModules.*Base`)

In `mkBaseModule`, extend the `imports` list to include the overlay module when the role is server or headless-server. Change the existing `lib.optional` block from:

```nix
++ lib.optional (role == "server" || role == "headless-server")
     inputs.proxmox-nixos.nixosModules.proxmox-ve;
```

to:

```nix
++ lib.optionals (role == "server" || role == "headless-server")
     [ proxmoxOverlayModule inputs.proxmox-nixos.nixosModules.proxmox-ve ];
```

Note the change from `lib.optional` (single value) to `lib.optionals` (list).

### 3.5 Update the comment in `modules/server/proxmox.nix`

The comment:
> ⚠ The proxmox-nixos overlay is applied by the proxmox-ve NixOS module imported at the flake level

is incorrect. Correct it to:
> ⚠ The proxmox-nixos overlay (`proxmoxOverlayModule`) and the proxmox-ve NixOS module are both applied at the flake level (in `roles.server/headless-server.baseModules`). The overlay makes `pkgs.proxmox-ve` available; the NixOS module defines `services.proxmox-ve.*` options.

---

## 4. Files to Modify

| File | Change |
|------|--------|
| `flake.nix` | Add `proxmoxOverlayModule`; add it to `roles.server.baseModules`, `roles.headless-server.baseModules`, and `mkBaseModule` for server/headless-server roles |
| `modules/server/proxmox.nix` | Correct the misleading overlay comment |

No other files need changes. The host's `/etc/nixos/server-services.nix` (not tracked in this repo) already has the correct `vexos.server.proxmox.enable = true` and `vexos.server.proxmox.ipAddress` settings from the `just enable proxmox` run.

---

## 5. Affected Configurations

All 10 server/headless-server `nixosConfigurations` outputs will be fixed:

- `vexos-server-amd`
- `vexos-server-nvidia`
- `vexos-server-nvidia-legacy535`
- `vexos-server-nvidia-legacy470`
- `vexos-server-intel`
- `vexos-server-vm`
- `vexos-headless-server-amd`
- `vexos-headless-server-nvidia`
- `vexos-headless-server-nvidia-legacy535`
- `vexos-headless-server-nvidia-legacy470`
- `vexos-headless-server-intel`
- `vexos-headless-server-vm`

The `nixosModules.serverBase` and `nixosModules.headlessServerBase` exports are also fixed by the `mkBaseModule` change.

The remaining 18 non-server outputs (desktop, htpc, stateless) are unaffected.

---

## 6. Risks and Mitigations

| Risk | Likelihood | Mitigation |
|------|-----------|------------|
| `inputs.proxmox-nixos.overlays.default` attribute name is wrong | Low | Verify with `nix eval` before implementing; the overlay may be named `overlay` in older versions |
| The overlay conflicts with nixpkgs-25.11 package versions (name clashes) | Low | proxmox-nixos uses its own nixpkgs pin and its packages are namespaced; conflicts are unlikely but check `nix flake check` output carefully |
| `lib.optional` → `lib.optionals` change in `mkBaseModule` breaks evaluation | Very low | `lib.optionals cond list` is standard; the original `lib.optional cond val` would fail anyway when val is a list |
| The non-server roles (desktop, htpc, stateless) accidentally get the proxmox overlay | None | `proxmoxOverlayModule` is only added to server/headless-server `baseModules` and gated by the `role == "server" || role == "headless-server"` condition in `mkBaseModule` |
| Dry-build of server variants requires `/etc/nixos/server-services.nix` to exist on the build host | Low | `serverServicesModule` already handles the missing-file case with `builtins.pathExists`; preflight accounts for this |

---

## 7. Validation Criteria

After the fix, the following must all pass:

1. `nix flake check --no-build --impure` — flake structure valid, all outputs evaluate
2. `nix build --dry-run --impure .#nixosConfigurations.vexos-server-amd.config.system.build.toplevel` — no `proxmox-ve cannot be found in pkgs` error
3. Same dry-build for at least one headless-server variant (e.g., `vexos-headless-server-amd`)
4. Non-server variant dry-build still passes (e.g., `vexos-desktop-amd`) — no regression
5. `bash scripts/preflight.sh` exits 0

---

## 8. Implementation Notes

- The `proxmoxOverlayModule` placement (before `inputs.proxmox-nixos.nixosModules.proxmox-ve` in the module list) ensures the overlay is applied before the module is evaluated. NixOS merges `nixpkgs.overlays` from all modules, so ordering is not strictly required, but placing it first is conventional and readable.
- The fix is purely additive to `flake.nix`. No host files, no module logic, no option definitions change.
- The comment fix in `modules/server/proxmox.nix` prevents future confusion for contributors who might otherwise remove the overlay thinking the NixOS module handles it.
