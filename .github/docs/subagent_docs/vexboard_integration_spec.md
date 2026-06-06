# vexboard Integration Spec
**Feature:** vexboard — Default VexOS Server Dashboard
**Date:** 2026-06-06

---

## 1. Current State Analysis

The VexOS server role (`configuration-server.nix`) imports `modules/server/` which
is a collection of optional service modules, each gated behind a
`vexos.server.<name>.enable` option (default: `false`). Services are activated
by the user via `/etc/nixos/server-services.nix` (managed by `just enable <service>`).

No default dashboard is pre-enabled for the server role today.

Existing service flake inputs (e.g. `proxmox-nixos`, `up`) follow the established
pattern of being wired at the flake level and exposed as module options.

---

## 2. Problem Definition

- VexOS Server has no default dashboard after initial deploy.
- vexboard (`github:VictoryTek/vexboard`) is a self-hosted dashboard purpose-built
  for VexOS Server, available as a Nix flake with a NixOS module.
- It should be **on by default** for every server role deployment, while remaining
  manageable through the standard `just enable/disable vexboard` workflow.

---

## 3. Proposed Solution Architecture

### 3.1 Flake input

Add `vexboard` as a new flake input:

```nix
vexboard.url = "github:VictoryTek/vexboard";
```

**Do NOT** add `inputs.vexboard.inputs.nixpkgs.follows = "nixpkgs"`.
vexboard builds with nixos-unstable + rust-overlay. Forcing it to follow our
stable nixpkgs pin would break the Rust/WASM toolchain. (Same pattern as
`proxmox-nixos`.)

### 3.2 Overlay + NixOS module wiring in flake.nix

Create a `vexboardBase` list (mirrors `proxmoxBase`) to be added to the
`server` role's `baseModules`:

```nix
vexboardBase = [
  { nixpkgs.overlays = [ inputs.vexboard.overlays.default ]; }
  inputs.vexboard.nixosModules.vexboard
];
```

- The overlay exposes `pkgs.vexboard` (needed by vexboard's NixOS module default).
- The NixOS module exposes `services.vexboard.*` options.
- Scoped to `server` role only (headless-server excluded per user request).

Update the `server` role in the `roles` table:
```nix
server = {
  ...
  baseModules = commonBase ++ [ upModule ] ++ proxmoxBase ++ sopsBase ++ vexboardBase;
  ...
};
```

Also update `mkBaseModule "server"` in `nixosModules.serverBase` to include
the same modules.

### 3.3 modules/server/vexboard.nix (new file)

Thin wrapper following the established pattern (same as `portbook.nix`,
`jellyfin.nix`):

- Exposes `options.vexos.server.vexboard.{enable, port, openFirewall, secretFile}`
- `config = lib.mkIf cfg.enable { services.vexboard = { enable=true; ... }; }`
- Default port: 7280 (upstream default, no existing service conflict)
- `openFirewall` defaults to `true`

### 3.4 modules/server/default.nix

Add `./vexboard.nix` under a new `# ── Dashboards ──` section.

### 3.5 configuration-server.nix

Add:
```nix
vexos.server.vexboard.enable = lib.mkDefault true;
```

`lib.mkDefault` (priority 1000) allows users to override with an explicit
`vexos.server.vexboard.enable = false;` in `server-services.nix` (which has
priority 100, winning over mkDefault).

### 3.6 template/server-services.nix

Add commented-out vexboard option under a new `# ── Dashboard ──` section:
```nix
# vexos.server.vexboard.enable = true;   # Port 7280 — VexOS server dashboard
```

### 3.7 justfile

Add `vexboard` to:
- `_server_service_names` variable
- `available-services` recipe (category: Monitoring & Admin)
- `service-info` case statement
- `status` case statement
- `services` listing

---

## 4. Implementation Steps

1. Edit `flake.nix` — add input, vexboardBase, update server baseModules and mkBaseModule
2. Create `modules/server/vexboard.nix`
3. Edit `modules/server/default.nix` — add import
4. Edit `configuration-server.nix` — add mkDefault enable
5. Edit `template/server-services.nix` — add commented option
6. Edit `justfile` — add CLI management entries

---

## 5. Build/Test Commands (Phase 3)

- `nix flake show` — validate flake structure (safe, low RAM)
- `sudo nixos-rebuild dry-build --flake .#vexos-server-amd`
- `sudo nixos-rebuild dry-build --flake .#vexos-server-vm`
- `sudo nixos-rebuild dry-build --flake .#vexos-desktop-amd` (non-server regression check)
- **NOT** `nix flake check` — FORBIDDEN (OOM risk)

---

## 6. Dependencies

| Dependency | Version | Notes |
|---|---|---|
| vexboard | github:VictoryTek/vexboard | No nixpkgs.follows |
| services.vexboard NixOS module | upstream | Via nixosModules.vexboard |
| pkgs.vexboard overlay | upstream | Via overlays.default |

---

## 7. Port Assignment

| Port | Service |
|---|---|
| 7280 | vexboard (upstream default) |

No conflict with existing service ports confirmed.

---

## 8. Risks & Mitigations

| Risk | Mitigation |
|---|---|
| vexboard's nixpkgs drift from stable | Do not add nixpkgs.follows; use upstream's overlay |
| users not wanting the dashboard | lib.mkDefault allows override via server-services.nix |
| package evaluation failure when disabled | overlay ensures pkgs.vexboard always resolves |
