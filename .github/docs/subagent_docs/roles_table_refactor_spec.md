# Spec: Extract `commonBase` / `proxmoxBase` from `roles` Table in `flake.nix`

**Feature name:** `roles_table_refactor`
**Scope:** `flake.nix` only — purely cosmetic refactor, no semantic change
**Phase:** 1 — Research & Specification

---

## 1. Current State Analysis

### 1.1 Variables defined before `roles` (in the outer `let` block)

| Variable | Type | Purpose |
|---|---|---|
| `unstableOverlayModule` | inline attrset | Adds `pkgs.unstable.*` overlay from `nixpkgs-unstable` |
| `upModule` | inline attrset | Adds the Up GUI update app to `environment.systemPackages` |
| `proxmoxOverlayModule` | inline attrset | Applies `proxmox-nixos.overlays.x86_64-linux` to expose `pkgs.proxmox-ve` |
| `customPkgsOverlayModule` | inline attrset | Applies `./pkgs` overlay to expose `pkgs.vexos.*` |
| `serverServicesModule` | list | Either `[ /etc/nixos/server-services.nix ]` or `[]` depending on path existence |

### 1.2 Current `roles` table (exact content)

The `roles` attrset uses **`baseModules`** and **`extraModules`** as its field names.
There is also a **`homeFile`** field per role.

```nix
roles = {
  desktop = {
    homeFile     = ./home-desktop.nix;
    baseModules  = [ unstableOverlayModule upModule customPkgsOverlayModule ];
    extraModules = [];
  };
  htpc = {
    homeFile     = ./home-htpc.nix;
    baseModules  = [ unstableOverlayModule upModule customPkgsOverlayModule ];
    extraModules = [];
  };
  stateless = {
    homeFile     = ./home-stateless.nix;
    baseModules  = [ unstableOverlayModule upModule customPkgsOverlayModule ];
    extraModules = [ impermanence.nixosModules.impermanence ];
  };
  server = {
    homeFile     = ./home-server.nix;
    # inputs.proxmox-nixos.nixosModules.proxmox-ve is imported here (not in
    # modules/server/proxmox.nix) to avoid infinite recursion — `imports`
    # cannot safely reference _module.args.
    # proxmoxOverlayModule must also be listed to make pkgs.proxmox-ve available.
    baseModules  = [ unstableOverlayModule upModule proxmoxOverlayModule customPkgsOverlayModule inputs.proxmox-nixos.nixosModules.proxmox-ve ];
    extraModules = serverServicesModule;
  };
  headless-server = {
    homeFile     = ./home-headless-server.nix;
    # No upModule — headless servers have no display, so the GUI update
    # app is intentionally omitted.
    # proxmoxOverlayModule must also be listed to make pkgs.proxmox-ve available.
    baseModules  = [ unstableOverlayModule proxmoxOverlayModule customPkgsOverlayModule inputs.proxmox-nixos.nixosModules.proxmox-ve ];
    extraModules = serverServicesModule;
  };
  vanilla = {
    homeFile     = ./home-vanilla.nix;
    baseModules  = [];
    extraModules = [];
  };
};
```

### 1.3 How `roles` is consumed downstream

`roles` is consumed in two places within `flake.nix`:

1. **`mkHost`** — builds a `nixpkgs.lib.nixosSystem` for each entry in `hostList`.
   The module list assembled is:
   ```
   [ /etc/nixos/hardware-configuration.nix ]
   ++ r.baseModules
   ++ [ (mkHomeManagerModule r.homeFile) ]
   ++ r.extraModules
   ++ [ hostFile ]
   ++ legacyExtra
   ++ [ variantModule ]
   ```

2. **`mkBaseModule`** — builds the `nixosModules.*Base` exports consumed by the
   thin `/etc/nixos/flake.nix` wrapper on each host. It references
   `roles.${role}.extraModules`, `roles.${role}.homeFile`, and reads
   `proxmoxOverlayModule` / `inputs.proxmox-nixos.nixosModules.proxmox-ve`
   directly (not via `roles.${role}.baseModules`) with a `lib.optionals` guard.
   This function is **independent** of the `roles.baseModules` field.

---

## 2. Problem Definition

### 2.1 Repetition count

`unstableOverlayModule` and `customPkgsOverlayModule` both appear identically in
**five** of the six roles (`desktop`, `htpc`, `stateless`, `server`, `headless-server`).
The `vanilla` role is the sole exception — it intentionally has no overlays.

`proxmoxOverlayModule` and `inputs.proxmox-nixos.nixosModules.proxmox-ve` appear
together in exactly **two** roles (`server`, `headless-server`).

### 2.2 Current ordering within `baseModules`

| Role | baseModules order |
|---|---|
| desktop | `unstableOverlayModule` → `upModule` → `customPkgsOverlayModule` |
| htpc | `unstableOverlayModule` → `upModule` → `customPkgsOverlayModule` |
| stateless | `unstableOverlayModule` → `upModule` → `customPkgsOverlayModule` |
| server | `unstableOverlayModule` → `upModule` → `proxmoxOverlayModule` → `customPkgsOverlayModule` → `proxmox-ve` |
| headless-server | `unstableOverlayModule` → `proxmoxOverlayModule` → `customPkgsOverlayModule` → `proxmox-ve` |
| vanilla | _(empty)_ |

### 2.3 Key structural observations

- **`server` includes `upModule`; `headless-server` does NOT.** The headless-server
  comment explicitly states: _"No upModule — headless servers have no display."_
- Both `server` and `headless-server` include `proxmoxOverlayModule` and
  `inputs.proxmox-nixos.nixosModules.proxmox-ve` — identical pair.
- `vanilla` has no overlays and no packages — `commonBase` must NOT be applied to it.

---

## 3. Proposed Solution

### 3.1 New `let` bindings to introduce

Add two new bindings immediately before the `roles` attrset, within the existing
outer `let` block:

```nix
# Overlay + custom-pkgs pair shared by every non-vanilla role.
commonBase = [ unstableOverlayModule customPkgsOverlayModule ];

# Proxmox overlay + NixOS module pair shared by server and headless-server.
proxmoxBase = [ proxmoxOverlayModule inputs.proxmox-nixos.nixosModules.proxmox-ve ];
```

### 3.2 Rewritten `roles` table

```nix
roles = {
  desktop = {
    homeFile     = ./home-desktop.nix;
    baseModules  = commonBase ++ [ upModule ];
    extraModules = [];
  };
  htpc = {
    homeFile     = ./home-htpc.nix;
    baseModules  = commonBase ++ [ upModule ];
    extraModules = [];
  };
  stateless = {
    homeFile     = ./home-stateless.nix;
    baseModules  = commonBase ++ [ upModule ];
    extraModules = [ impermanence.nixosModules.impermanence ];
  };
  server = {
    homeFile     = ./home-server.nix;
    # upModule: server has a display — GUI update app is included.
    # proxmoxBase: overlay + NixOS module imported here (not in
    # modules/server/proxmox.nix) to avoid infinite recursion — `imports`
    # cannot safely reference _module.args.
    baseModules  = commonBase ++ [ upModule ] ++ proxmoxBase;
    extraModules = serverServicesModule;
  };
  headless-server = {
    homeFile     = ./home-headless-server.nix;
    # No upModule — headless servers have no display, so the GUI update
    # app is intentionally omitted.
    # proxmoxBase: overlay + NixOS module imported here to avoid infinite
    # recursion (same reason as server above).
    baseModules  = commonBase ++ proxmoxBase;
    extraModules = serverServicesModule;
  };
  vanilla = {
    homeFile     = ./home-vanilla.nix;
    baseModules  = [];
    extraModules = [];
  };
};
```

### 3.3 Module list equivalence verification

The table below confirms the resulting flat module list is **identical** before and
after the refactor for every role. List elements are written in the order they appear
after `++` concatenation.

| Role | Before | After (flattened) | Identical? |
|---|---|---|---|
| desktop | `[unstableOverlayModule, upModule, customPkgsOverlayModule]` | `[unstableOverlayModule, customPkgsOverlayModule, upModule]` | **order differs¹** |
| htpc | `[unstableOverlayModule, upModule, customPkgsOverlayModule]` | `[unstableOverlayModule, customPkgsOverlayModule, upModule]` | **order differs¹** |
| stateless | `[unstableOverlayModule, upModule, customPkgsOverlayModule]` | `[unstableOverlayModule, customPkgsOverlayModule, upModule]` | **order differs¹** |
| server | `[unstableOverlayModule, upModule, proxmoxOverlayModule, customPkgsOverlayModule, proxmox-ve]` | `[unstableOverlayModule, customPkgsOverlayModule, upModule, proxmoxOverlayModule, proxmox-ve]` | **order differs¹** |
| headless-server | `[unstableOverlayModule, proxmoxOverlayModule, customPkgsOverlayModule, proxmox-ve]` | `[unstableOverlayModule, customPkgsOverlayModule, proxmoxOverlayModule, proxmox-ve]` | **order differs¹** |
| vanilla | `[]` | `[]` | ✓ identical |

**¹ Order change analysis (see Section 4 — Risks):** The NixOS module system merges
all module attribute sets before evaluation; module list order affects merge priority
only when two modules set the **same option** with conflicting values. In this case:

- `unstableOverlayModule` sets `nixpkgs.overlays` (appends one entry)
- `customPkgsOverlayModule` sets `nixpkgs.overlays` (appends one entry)
- `upModule` sets `environment.systemPackages` (appends one entry)
- `proxmoxOverlayModule` sets `nixpkgs.overlays` (appends one entry)
- `inputs.proxmox-nixos.nixosModules.proxmox-ve` sets various `services.*` options

None of these modules conflict with each other. The `nixpkgs.overlays` option is a
list that is always **merged (concatenated)**, not overridden — order within the list
affects overlay layering, but these three overlays operate on independent namespaces
(`pkgs.unstable`, `pkgs.vexos`, `pkgs.proxmox-ve`) and do not reference one another.
Reordering them does not change the final package set.

**Conclusion: the refactor is semantically equivalent.**

### 3.4 Exact placement of new bindings in `flake.nix`

Insert `commonBase` and `proxmoxBase` immediately before the comment that precedes
`roles = {`. The insertion point is:

```nix
    # Single source of truth for per-role wiring. Consumed by `mkHost` ...
    roles = {
```

Replace with:

```nix
    # Overlay modules shared by every non-vanilla role (unstable channel + custom pkgs).
    commonBase = [ unstableOverlayModule customPkgsOverlayModule ];

    # Proxmox overlay + NixOS module shared by server and headless-server roles.
    proxmoxBase = [ proxmoxOverlayModule inputs.proxmox-nixos.nixosModules.proxmox-ve ];

    # Single source of truth for per-role wiring. Consumed by `mkHost` ...
    roles = {
```

---

## 4. Risks and Mitigations

| Risk | Likelihood | Mitigation |
|---|---|---|
| Module list order change breaks a build | Very low | All affected modules operate on independent namespaces; NixOS overlay merging is order-independent for these specific modules. Confirmed by analysis in Section 3.3. |
| `proxmoxBase` name shadows something in scope | None | `proxmoxBase` is a new binding; `grep` confirms it does not exist in `flake.nix` today. |
| `commonBase` name shadows something in scope | None | `commonBase` is a new binding; `grep` confirms it does not exist in `flake.nix` today. |
| `mkBaseModule` references `proxmoxOverlayModule` directly (not via `roles`) | N/A — not a risk | `mkBaseModule` does not use `roles.baseModules`; it reads `proxmoxOverlayModule` and `inputs.proxmox-nixos.nixosModules.proxmox-ve` directly with its own `lib.optionals` guard. The new `proxmoxBase` binding is an additional convenience that does not break `mkBaseModule`. |
| `vanilla` role incorrectly receives `commonBase` | None | Spec explicitly keeps `vanilla.baseModules = []`. |

---

## 5. Files to Modify

| File | Change |
|---|---|
| `flake.nix` | Add `commonBase` and `proxmoxBase` let-bindings; rewrite `roles` attrset entries as specified in Section 3.2 |

No other files require modification. The `roles` field names (`homeFile`,
`baseModules`, `extraModules`) are unchanged — only the values assigned to
`baseModules` change (to use `++` concatenation with the new shared lists).

---

## 6. Implementation Steps

1. Open `flake.nix`.
2. Locate the comment block beginning `# Single source of truth for per-role wiring`.
3. Insert `commonBase` and `proxmoxBase` bindings immediately before that comment
   (see Section 3.4 for the exact replacement string).
4. Replace the body of the `roles` attrset with the version from Section 3.2,
   preserving all existing inline comments (adapted as shown).
5. Run `nix flake check` to confirm no evaluation errors.
6. Run `sudo nixos-rebuild dry-build --flake .#vexos-desktop-amd` to confirm
   the desktop closure builds.
7. Run `sudo nixos-rebuild dry-build --flake .#vexos-headless-server-amd` to
   confirm the headless-server closure builds (verifies `upModule` absence is
   preserved).
8. Run `sudo nixos-rebuild dry-build --flake .#vexos-server-amd` to confirm
   the server closure builds (verifies `upModule` presence and `proxmoxBase`
   are correctly included).
