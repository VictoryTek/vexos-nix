# Spec: `mkHost` helper, NVIDIA legacy variants for server/headless-server, and `"headless-server"` branding role

Status: ready for single-pass implementation.
Scope: `flake.nix`, `modules/branding.nix`, `configuration-headless-server.nix`. No other files.

---

## 1. Current State Analysis

### 1.1 Inventory of current `nixosConfigurations` (26 outputs)

Naming convention (verified): legacy variants use a no-underscore suffix in the **output name** (`legacy535`, `legacy470`) but the underscored value in the **option string** (`vexos.gpu.nvidiaDriverVariant = "legacy_535"`).

| # | Output name | role | gpu | nvidiaVariant | host file | common-modules set | home-manager module | extra inline modules |
|---|---|---|---|---|---|---|---|---|
| 1 | `vexos-desktop-amd` | desktop | amd | — | `hosts/desktop-amd.nix` | `commonModules` | `homeManagerModule` (home-desktop) | — |
| 2 | `vexos-desktop-nvidia` | desktop | nvidia | — | `hosts/desktop-nvidia.nix` | `commonModules` | `homeManagerModule` | — |
| 3 | `vexos-desktop-nvidia-legacy535` | desktop | nvidia | `legacy_535` | `hosts/desktop-nvidia.nix` | `commonModules` | `homeManagerModule` | `{ vexos.gpu.nvidiaDriverVariant = "legacy_535"; }` |
| 4 | `vexos-desktop-nvidia-legacy470` | desktop | nvidia | `legacy_470` | `hosts/desktop-nvidia.nix` | `commonModules` | `homeManagerModule` | `{ vexos.gpu.nvidiaDriverVariant = "legacy_470"; }` |
| 5 | `vexos-desktop-vm` | desktop | vm | — | `hosts/desktop-vm.nix` | `commonModules` | `homeManagerModule` | — |
| 6 | `vexos-desktop-intel` | desktop | intel | — | `hosts/desktop-intel.nix` | `commonModules` | `homeManagerModule` | — |
| 7 | `vexos-stateless-amd` | stateless | amd | — | `hosts/stateless-amd.nix` | `statelessModules` | `statelessHomeManagerModule` | `impermanence.nixosModules.impermanence` |
| 8 | `vexos-stateless-nvidia` | stateless | nvidia | — | `hosts/stateless-nvidia.nix` | `statelessModules` | `statelessHomeManagerModule` | `impermanence.nixosModules.impermanence` |
| 9 | `vexos-stateless-nvidia-legacy535` | stateless | nvidia | `legacy_535` | `hosts/stateless-nvidia.nix` | `statelessModules` | `statelessHomeManagerModule` | impermanence + `{ vexos.gpu.nvidiaDriverVariant = "legacy_535"; }` |
| 10 | `vexos-stateless-nvidia-legacy470` | stateless | nvidia | `legacy_470` | `hosts/stateless-nvidia.nix` | `statelessModules` | `statelessHomeManagerModule` | impermanence + `{ vexos.gpu.nvidiaDriverVariant = "legacy_470"; }` |
| 11 | `vexos-stateless-intel` | stateless | intel | — | `hosts/stateless-intel.nix` | `statelessModules` | `statelessHomeManagerModule` | impermanence |
| 12 | `vexos-stateless-vm` | stateless | vm | — | `hosts/stateless-vm.nix` | `statelessModules` | `statelessHomeManagerModule` | impermanence |
| 13 | `vexos-server-amd` | server | amd | — | `hosts/server-amd.nix` | `serverModules` | `serverHomeManagerModule` | — |
| 14 | `vexos-server-nvidia` | server | nvidia | — | `hosts/server-nvidia.nix` | `serverModules` | `serverHomeManagerModule` | — |
| 15 | `vexos-server-intel` | server | intel | — | `hosts/server-intel.nix` | `serverModules` | `serverHomeManagerModule` | — |
| 16 | `vexos-server-vm` | server | vm | — | `hosts/server-vm.nix` | `serverModules` | `serverHomeManagerModule` | — |
| 17 | `vexos-headless-server-amd` | headless-server | amd | — | `hosts/headless-server-amd.nix` | `headlessServerModules` | `headlessServerHomeManagerModule` | — |
| 18 | `vexos-headless-server-nvidia` | headless-server | nvidia | — | `hosts/headless-server-nvidia.nix` | `headlessServerModules` | `headlessServerHomeManagerModule` | — |
| 19 | `vexos-headless-server-intel` | headless-server | intel | — | `hosts/headless-server-intel.nix` | `headlessServerModules` | `headlessServerHomeManagerModule` | — |
| 20 | `vexos-headless-server-vm` | headless-server | vm | — | `hosts/headless-server-vm.nix` | `headlessServerModules` | `headlessServerHomeManagerModule` | — |
| 21 | `vexos-htpc-amd` | htpc | amd | — | `hosts/htpc-amd.nix` | `htpcModules` | `htpcHomeManagerModule` | — |
| 22 | `vexos-htpc-nvidia` | htpc | nvidia | — | `hosts/htpc-nvidia.nix` | `htpcModules` | `htpcHomeManagerModule` | — |
| 23 | `vexos-htpc-nvidia-legacy535` | htpc | nvidia | `legacy_535` | `hosts/htpc-nvidia.nix` | `htpcModules` | `htpcHomeManagerModule` | `{ vexos.gpu.nvidiaDriverVariant = "legacy_535"; }` |
| 24 | `vexos-htpc-nvidia-legacy470` | htpc | nvidia | `legacy_470` | `hosts/htpc-nvidia.nix` | `htpcModules` | `htpcHomeManagerModule` | `{ vexos.gpu.nvidiaDriverVariant = "legacy_470"; }` |
| 25 | `vexos-htpc-intel` | htpc | intel | — | `hosts/htpc-intel.nix` | `htpcModules` | `htpcHomeManagerModule` | — |
| 26 | `vexos-htpc-vm` | htpc | vm | — | `hosts/htpc-vm.nix` | `htpcModules` | `htpcHomeManagerModule` | — |

### 1.2 Duplicated `*HomeManagerModule` pattern

Every role defines an identical module with only the imported home file path differing:

```nix
xxxHomeManagerModule = {
  imports = [ home-manager.nixosModules.home-manager ];
  home-manager = {
    useGlobalPkgs       = true;
    useUserPackages     = true;
    extraSpecialArgs    = { inherit inputs; };
    users.nimda         = import ./home-<role>.nix;
    backupFileExtension = "backup";
  };
};
```

Five copies exist: `homeManagerModule` (desktop), `htpcHomeManagerModule`, `statelessHomeManagerModule`, `serverHomeManagerModule`, `headlessServerHomeManagerModule`.

### 1.3 Current `nixosModules.base` (consumer-facing API)

Consumed by `template/etc-nixos-flake.nix` via `vexos-nix.nixosModules.base`, `.statelessBase`, `.htpcBase`, `.serverBase`, `.headlessServerBase`, `.gpuAmd`, `.gpuNvidia`, `.gpuIntel`, `.gpuVm`, `.gpuAmdHeadless`, `.gpuNvidiaHeadless`, `.gpuIntelHeadless`, `.statelessGpuVm`, `.asus`.

`nixosModules.base` (and the four sibling `*Base` modules) is a single-attribute module that:
- imports `home-manager.nixosModules.home-manager` and the role's `configuration-*.nix`
- sets `home-manager.useGlobalPkgs/useUserPackages/extraSpecialArgs/users.nimda` (and `backupFileExtension = "backup"` for htpc/server/headlessServer/stateless — **but NOT for `base` itself; missing `backupFileExtension` is a real drift bug**)
- inlines the unstable overlay
- adds `up` to `environment.systemPackages` (omitted on `headlessServerBase`)

For `statelessBase` it additionally imports `impermanence.nixosModules.impermanence` and `./modules/stateless-disk.nix`, and sets `vexos.stateless.disk.{enable,device}`.

### 1.4 Current `vexos.branding.role` enum (`modules/branding.nix`)

```nix
options.vexos.branding.role = lib.mkOption {
  type        = lib.types.enum [ "desktop" "htpc" "server" "stateless" ];
  default     = "desktop";
  description = "Role-specific subdirectory to use for branding pixmaps and background logos.";
};
```

The role string is used in three ways in `branding.nix`:

1. **Asset path interpolation** (lines 8–10):
   ```nix
   pixmapsDir  = ../files/pixmaps          + "/${role}";
   bgLogosDir  = ../files/background_logos + "/${role}";
   plymouthDir = ../files/plymouth         + "/${role}";
   ```
   Directories that exist under `files/{pixmaps,background_logos,plymouth}/`: `desktop/`, `htpc/`, `server/`, `stateless/`. **No `headless-server/` directory exists.**

2. **`distroName` default** (lines 86–91, an existing `lib.mkIf`-style chain — flagged tech debt, not changed by this spec):
   ```nix
   if role == "stateless" then "VexOS Stateless"
   else if role == "server" then "VexOS Server"
   else if role == "htpc" then "VexOS HTPC"
   else "VexOS Desktop"
   ```

3. No other branches on role.

`configuration-headless-server.nix` currently sets `vexos.branding.role = "server"` to reuse server assets, then overrides `distroName` via `lib.mkOverride 500 "VexOS Headless Server"`.

---

## 2. Problem Definition

Quoting `.github/copilot-instructions.md`:

> Existing `lib.mkIf` guards in shared modules are tech debt to be eliminated. Do not add new ones.
> A `configuration-*.nix` expresses its role **entirely through its import list** — if a file is imported, all its content applies unconditionally.

Three problems:

1. **Boilerplate.** 26× repetition of `nixpkgs.lib.nixosSystem { inherit system; modules = … ++ [ host ]; specialArgs = { inherit inputs; }; }` and 5× duplication of the home-manager module. Adding a new role × gpu × variant requires editing 2+ disconnected places, and `nixosModules.*Base` exports drift from per-role module sets (concrete drift today: `nixosModules.base` lacks `backupFileExtension = "backup"`).
2. **Missing legacy NVIDIA variants for `server` and `headless-server`.** Desktop/htpc/stateless each expose `-legacy535` and `-legacy470`; server and headless-server do not. The user has confirmed this should exist for symmetry.
3. **`"headless-server"` is not a real `vexos.branding.role` value.** The enum is `[ "desktop" "htpc" "server" "stateless" ]`, forcing `configuration-headless-server.nix` to alias `"server"`. This conflates two semantically distinct roles and blocks future divergence.

---

## 3. Proposed Solution Architecture

### 3.1 `mkHomeManagerModule` helper

Replaces all five `*HomeManagerModule` definitions:

```nix
mkHomeManagerModule = homeFile: {
  imports = [ home-manager.nixosModules.home-manager ];
  home-manager = {
    useGlobalPkgs       = true;
    useUserPackages     = true;
    extraSpecialArgs    = { inherit inputs; };
    users.nimda         = import homeFile;
    backupFileExtension = "backup";
  };
};
```

### 3.2 Role descriptor table (single source of truth)

Internal `let`-bound table keyed by role; consumed by both `mkHost` and the regenerated `nixosModules.*Base` exports:

```nix
roles = {
  desktop = {
    homeFile     = ./home-desktop.nix;
    baseModules  = [ unstableOverlayModule upModule ];
    extraModules = [];   # nothing role-specific beyond the home file
  };
  htpc = {
    homeFile     = ./home-htpc.nix;
    baseModules  = [ unstableOverlayModule upModule ];
    extraModules = [];
  };
  stateless = {
    homeFile     = ./home-stateless.nix;
    baseModules  = [ unstableOverlayModule upModule ];
    extraModules = [ impermanence.nixosModules.impermanence ];
  };
  server = {
    homeFile     = ./home-server.nix;
    baseModules  = [ unstableOverlayModule upModule inputs.proxmox-nixos.nixosModules.proxmox-ve ];
    extraModules = serverServicesModule;  # already a list
  };
  headless-server = {
    homeFile     = ./home-headless-server.nix;
    baseModules  = [ unstableOverlayModule inputs.proxmox-nixos.nixosModules.proxmox-ve ]; # NO upModule (no display)
    extraModules = serverServicesModule;
  };
};
```

`serverServicesModule` keeps its existing definition (conditional list of `/etc/nixos/server-services.nix`).

### 3.3 `mkHost` helper

```nix
mkHost = { role, gpu, nvidiaVariant ? null }:
  let
    r           = roles.${role};
    hostFile    = ./hosts + "/${role}-${gpu}.nix";
    legacyExtra = lib.optional (nvidiaVariant != null)
                    { vexos.gpu.nvidiaDriverVariant = nvidiaVariant; };
  in
  nixpkgs.lib.nixosSystem {
    inherit system;
    specialArgs = { inherit inputs; };
    modules =
      [ /etc/nixos/hardware-configuration.nix ]
      ++ r.baseModules
      ++ [ (mkHomeManagerModule r.homeFile) ]
      ++ r.extraModules
      ++ [ hostFile ]
      ++ legacyExtra;
  };
```

The output name for a descriptor is `"vexos-${role}-${gpu}"` plus, if `nvidiaVariant != null`, `"-legacy${suffix}"` where `suffix = "535"` for `legacy_535` and `"470"` for `legacy_470` (verified naming).

### 3.4 Host descriptor list & assembly

```nix
hostList = [
  # Desktop
  { name = "vexos-desktop-amd";              role = "desktop";         gpu = "amd"; }
  { name = "vexos-desktop-nvidia";           role = "desktop";         gpu = "nvidia"; }
  { name = "vexos-desktop-nvidia-legacy535"; role = "desktop";         gpu = "nvidia"; nvidiaVariant = "legacy_535"; }
  { name = "vexos-desktop-nvidia-legacy470"; role = "desktop";         gpu = "nvidia"; nvidiaVariant = "legacy_470"; }
  { name = "vexos-desktop-intel";            role = "desktop";         gpu = "intel"; }
  { name = "vexos-desktop-vm";               role = "desktop";         gpu = "vm"; }

  # Stateless
  { name = "vexos-stateless-amd";              role = "stateless";     gpu = "amd"; }
  { name = "vexos-stateless-nvidia";           role = "stateless";     gpu = "nvidia"; }
  { name = "vexos-stateless-nvidia-legacy535"; role = "stateless";     gpu = "nvidia"; nvidiaVariant = "legacy_535"; }
  { name = "vexos-stateless-nvidia-legacy470"; role = "stateless";     gpu = "nvidia"; nvidiaVariant = "legacy_470"; }
  { name = "vexos-stateless-intel";            role = "stateless";     gpu = "intel"; }
  { name = "vexos-stateless-vm";               role = "stateless";     gpu = "vm"; }

  # Server (GUI)
  { name = "vexos-server-amd";              role = "server";           gpu = "amd"; }
  { name = "vexos-server-nvidia";           role = "server";           gpu = "nvidia"; }
  { name = "vexos-server-nvidia-legacy535"; role = "server";           gpu = "nvidia"; nvidiaVariant = "legacy_535"; }  # NEW
  { name = "vexos-server-nvidia-legacy470"; role = "server";           gpu = "nvidia"; nvidiaVariant = "legacy_470"; }  # NEW
  { name = "vexos-server-intel";            role = "server";           gpu = "intel"; }
  { name = "vexos-server-vm";               role = "server";           gpu = "vm"; }

  # Headless server
  { name = "vexos-headless-server-amd";              role = "headless-server"; gpu = "amd"; }
  { name = "vexos-headless-server-nvidia";           role = "headless-server"; gpu = "nvidia"; }
  { name = "vexos-headless-server-nvidia-legacy535"; role = "headless-server"; gpu = "nvidia"; nvidiaVariant = "legacy_535"; }  # NEW
  { name = "vexos-headless-server-nvidia-legacy470"; role = "headless-server"; gpu = "nvidia"; nvidiaVariant = "legacy_470"; }  # NEW
  { name = "vexos-headless-server-intel";            role = "headless-server"; gpu = "intel"; }
  { name = "vexos-headless-server-vm";               role = "headless-server"; gpu = "vm"; }

  # HTPC
  { name = "vexos-htpc-amd";              role = "htpc";               gpu = "amd"; }
  { name = "vexos-htpc-nvidia";           role = "htpc";               gpu = "nvidia"; }
  { name = "vexos-htpc-nvidia-legacy535"; role = "htpc";               gpu = "nvidia"; nvidiaVariant = "legacy_535"; }
  { name = "vexos-htpc-nvidia-legacy470"; role = "htpc";               gpu = "nvidia"; nvidiaVariant = "legacy_470"; }
  { name = "vexos-htpc-intel";            role = "htpc";               gpu = "intel"; }
  { name = "vexos-htpc-vm";               role = "htpc";               gpu = "vm"; }
];

nixosConfigurations = lib.listToAttrs (map (h: {
  name  = h.name;
  value = mkHost {
    inherit (h) role gpu;
    nvidiaVariant = h.nvidiaVariant or null;
  };
}) hostList);
```

Total: 30 outputs (26 existing, 4 new — the four NEW entries are flagged above).

### 3.5 `nixosModules.*Base` preserved (external-API-stable)

`nixosModules.base` and siblings MUST keep their current attribute names and observable shape (consumed by `template/etc-nixos-flake.nix`). They are re-derived from the same `roles.<role>` building blocks:

```nix
mkBaseModule = role: configFile: extraSystemPackages: { ... }: {
  imports =
    [ home-manager.nixosModules.home-manager configFile ]
    ++ roles.${role}.extraModules                        # impermanence for stateless, etc.
    ++ (lib.optional (role == "server" || role == "headless-server")
          inputs.proxmox-nixos.nixosModules.proxmox-ve);
  home-manager = {
    useGlobalPkgs       = true;
    useUserPackages     = true;
    extraSpecialArgs    = { inherit inputs; };
    users.nimda         = import roles.${role}.homeFile;
    backupFileExtension = "backup";
  };
  nixpkgs.overlays = [ /* unstable overlay */ ];
  environment.systemPackages = extraSystemPackages;
};

nixosModules = {
  base               = mkBaseModule "desktop"         ./configuration-desktop.nix         [ up.packages.x86_64-linux.default ];
  htpcBase           = mkBaseModule "htpc"            ./configuration-htpc.nix            [ up.packages.x86_64-linux.default ];
  serverBase         = mkBaseModule "server"          ./configuration-server.nix          [ up.packages.x86_64-linux.default ];
  headlessServerBase = mkBaseModule "headless-server" ./configuration-headless-server.nix [];  # no `up` on headless
  statelessBase      = { lib, ... }: {
    imports =
      (mkBaseModule "stateless" ./configuration-stateless.nix [ up.packages.x86_64-linux.default ]).imports
      ++ [ ./modules/stateless-disk.nix ];
    /* + same home-manager + overlay + systemPackages as the helper produces */
    vexos.stateless.disk = { enable = true; device = lib.mkDefault "/dev/nvme0n1"; };
    /* ... */
  };
  # gpu* / asus / statelessGpuVm exports unchanged.
};
```

**Net behavioural changes vs. today:**
- `nixosModules.base` gains `home-manager.backupFileExtension = "backup"` (drift fix; aligns with all sibling `*Base` modules and with what `commonModules` does for the per-role outputs). The user has accepted that `nixosModules.base` is a stable external API — adding this option is purely additive and cannot break existing consumers. Documented in §7.

All other `*Base` modules: bit-for-bit equivalent attribute set.

### 3.6 `branding.nix` accommodates `"headless-server"` (minimal)

Two surgical changes — no `lib.mkIf`, no new conditionals beyond the existing `distroName` chain (which is already flagged tech debt and is **not** touched here):

1. **Enum addition:**
   ```nix
   type = lib.types.enum [ "desktop" "htpc" "server" "stateless" "headless-server" ];
   ```

2. **Asset path mapping** — introduce a tiny `let`-bound `assetRole` so `headless-server` reuses the existing `files/.../server/` directories without duplicating assets and without touching the rest of the file:
   ```nix
   role          = config.vexos.branding.role;
   assetRole     = if role == "headless-server" then "server" else role;
   pixmapsDir    = ../files/pixmaps          + "/${assetRole}";
   bgLogosDir    = ../files/background_logos + "/${assetRole}";
   plymouthDir   = ../files/plymouth         + "/${assetRole}";
   ```
   This is a `let`-binding, not a `lib.mkIf` in module config space, so it does not violate the Option B no-conditional-config rule. The `distroName` chain falls through to its existing `else "VexOS Desktop"` branch for `"headless-server"`, which is harmless because `configuration-headless-server.nix` already sets `system.nixos.distroName = lib.mkOverride 500 "VexOS Headless Server";`.

### 3.7 `configuration-headless-server.nix`

One-line semantic change: `vexos.branding.role = "server";` → `vexos.branding.role = "headless-server";`. The accompanying comment is updated to reflect that asset reuse is now performed by `branding.nix`'s `assetRole` mapping.

---

## 4. Implementation Steps

Order is chosen so the tree is buildable after every step.

### Step 1 — `modules/branding.nix`

- In the top `let` block, add `assetRole = if role == "headless-server" then "server" else role;` and change `pixmapsDir`/`bgLogosDir`/`plymouthDir` to use `assetRole` instead of `role`.
- In the `options.vexos.branding.role` declaration, change the enum to:
  ```nix
  type = lib.types.enum [ "desktop" "htpc" "server" "stateless" "headless-server" ];
  ```
- Do NOT modify the `distroName` `if/else` chain (out of scope).

### Step 2 — `configuration-headless-server.nix`

- Change `vexos.branding.role = "server";` to `vexos.branding.role = "headless-server";`.
- Update the adjacent comment from "Reuse the 'server' role to pick up existing server/ branding assets…" to "Use the 'headless-server' role; branding.nix maps it to server/ asset directories via assetRole."

After Steps 1–2, all 26 existing outputs still build and `vexos-headless-server-*` correctly resolves assets via the mapping.

### Step 3 — `flake.nix` refactor

In the top `let` block of `outputs`, replace the existing definitions of `homeManagerModule`, `commonModules`, `htpcHomeManagerModule`, `htpcModules`, `statelessHomeManagerModule`, `statelessModules`, `serverHomeManagerModule`, `serverModules`, `headlessServerHomeManagerModule`, `headlessServerModules` with:

- Keep: `system`, `unstableOverlayModule`, `upModule`, `serverServicesModule`.
- Introduce: `mkHomeManagerModule`, `roles`, `mkHost`, `hostList` (per §3.1–§3.4).
- Replace the 26 hand-written `nixosConfigurations.X = nixpkgs.lib.nixosSystem { … };` blocks with the single `nixosConfigurations = lib.listToAttrs (map …)` expression from §3.4 — this also adds the four NEW outputs.
- Replace the body of `nixosModules.{base,htpcBase,serverBase,headlessServerBase,statelessBase}` with the shared `mkBaseModule` helper (§3.5). Keep `gpuAmd`, `gpuNvidia`, `gpuIntel`, `gpuVm`, `gpuAmdHeadless`, `gpuNvidiaHeadless`, `gpuIntelHeadless`, `statelessGpuVm`, `asus` exports byte-identical.

The `inputs` block, `outputs` argument list, `serverServicesModule`'s `pathExists` check, and the `unstableOverlayModule` body are unchanged.

### Step 4 — verification (see §9).

---

## 5. Semantic-Equivalence Checklist

For each of the 26 existing outputs the tuple `(role, gpu, nvidiaVariant, hostFile, homeFile, common-modules-set)` BEFORE the refactor must equal the tuple AFTER. Verified by construction:

| Output | Before tuple | After tuple |
|---|---|---|
| `vexos-desktop-amd` | (desktop, amd, —, hosts/desktop-amd.nix, home-desktop.nix, commonModules) | identical via `roles.desktop` |
| `vexos-desktop-nvidia` | (desktop, nvidia, —, hosts/desktop-nvidia.nix, home-desktop.nix, commonModules) | identical |
| `vexos-desktop-nvidia-legacy535` | (desktop, nvidia, legacy_535, hosts/desktop-nvidia.nix, home-desktop.nix, commonModules) | identical (legacyExtra injects same attrset) |
| `vexos-desktop-nvidia-legacy470` | (desktop, nvidia, legacy_470, …) | identical |
| `vexos-desktop-intel` / `-vm` | (desktop, intel/vm, —, …, commonModules) | identical |
| `vexos-stateless-*` (6 outputs) | (stateless, *, *, hosts/stateless-*.nix, home-stateless.nix, statelessModules + impermanence) | identical via `roles.stateless.extraModules = [impermanence…]` |
| `vexos-server-{amd,nvidia,intel,vm}` | (server, *, —, hosts/server-*.nix, home-server.nix, serverModules) | identical via `roles.server` |
| `vexos-headless-server-{amd,nvidia,intel,vm}` | (headless-server, *, —, hosts/headless-server-*.nix, home-headless-server.nix, headlessServerModules) | identical via `roles.headless-server` (no `upModule`, includes proxmox + serverServicesModule) |
| `vexos-htpc-{amd,nvidia,nvidia-legacy535,nvidia-legacy470,intel,vm}` | (htpc, *, *, hosts/htpc-*.nix, home-htpc.nix, htpcModules) | identical via `roles.htpc` |

Module-list ordering is preserved exactly (`hardware-configuration.nix` first, then base modules, then HM module, then role extras like impermanence, then host file, then legacyExtra). `system.build.toplevel.drvPath` for the 26 unchanged outputs MUST be identical — verified empirically per §9.

For headless-server, with the new `assetRole` mapping:
- `pixmapsDir`/`bgLogosDir`/`plymouthDir` resolve to `files/pixmaps/server`, `files/background_logos/server`, `files/plymouth/server` — identical to today (when role was aliased to `"server"`).
- `distroName` default falls through to `"VexOS Desktop"` but is overridden to `"VexOS Headless Server"` at priority 500 in `configuration-headless-server.nix` — same final value as today.
- `vexos.branding.role` now equals `"headless-server"` (was `"server"`) — this is the intended change.

---

## 6. Dependencies

Pure Nix refactor. No new flake inputs, no `inputs.*.follows` changes, no version bumps.

**Context7 not required** — no new external libraries introduced; all changes stay within nixpkgs / home-manager / impermanence / proxmox-nixos APIs already in use, and `nixpkgs.lib.nixosSystem` + `lib.listToAttrs` + `lib.optional` are stable nixpkgs primitives.

---

## 7. Risks and Mitigations

| Risk | Mitigation |
|---|---|
| Silent drift between `nixosModules.base` and per-role module sets (current bug: `base` lacks `backupFileExtension`). | Both per-role outputs and `nixosModules.*Base` exports are derived from the single `roles` table + `mkHomeManagerModule` helper. Drift is structurally impossible after the refactor. |
| Forgotten output during migration. | §5 checklist enumerates all 26 existing tuples; §9 verifies drvPath equality. |
| `branding.nix` resolving `"headless-server"` to a non-existent asset directory. | Explicit `assetRole` `let`-binding maps `"headless-server"` → `"server"`, no FS changes required. |
| `legacy_470` removed upstream in nixpkgs 25.11. | Verified in `modules/gpu/nvidia.nix` (lines 19–22): `boot.kernelPackages.nvidiaPackages.legacy_470` is referenced and the option enum still includes `"legacy_470"`. The module comment explicitly says only `legacy_390` (Fermi) is broken. ⇒ Both `legacy_535` and `legacy_470` remain supported. The four new outputs are safe to add. |
| `nixosModules.base` external-API contract change. | Attribute name and shape unchanged; only behavioural delta is the additive `home-manager.backupFileExtension = "backup"`. This option is already set on every other `*Base` module and is purely a fix. Consumer `template/etc-nixos-flake.nix` does not override `backupFileExtension`, so behaviour stays consistent. Documented as an intentional drift fix. |
| Headless-server NVIDIA module honoring `vexos.gpu.nvidiaDriverVariant`. | Verified: `modules/gpu/nvidia-headless.nix` `imports = [ ./nvidia.nix ];` and only forces `hardware.nvidia.modesetting.enable = lib.mkForce false;`. The variant→`driverPackage` machinery in `nvidia.nix` is inherited. The two new headless-server NVIDIA legacy outputs will work without any module change. |
| Stateless `extraModules` list ordering. | `mkHost` appends `extraModules` (impermanence) AFTER the home-manager module and BEFORE the host file — matches current `statelessModules ++ [ ./hosts/stateless-*.nix impermanence.nixosModules.impermanence ]` evaluation semantics (module ordering is irrelevant for set-merging in NixOS modules; verified by drvPath equality test in §9). |

---

## 8. Out of Scope

- README rewrite (separate change #5).
- Justfile selector additions for legacy NVIDIA server/headless variants (separate change #10).
- `home-headless-server.nix` overhaul.
- Renaming or duplicating `files/server/` to `files/headless-server/`.
- Removing the `lib.mkIf`-style chain in `branding.nix`'s `distroName` default (handled later).
- Touching any file other than `flake.nix`, `modules/branding.nix`, `configuration-headless-server.nix`.
- Changes to `template/etc-nixos-flake.nix` — its public consumption surface is unchanged.

The README's host table will need four new entries added later: `vexos-server-nvidia-legacy535`, `vexos-server-nvidia-legacy470`, `vexos-headless-server-nvidia-legacy535`, `vexos-headless-server-nvidia-legacy470`. Recorded here for the future README change; not done now.

The Justfile (verified by quick grep) currently references roles by short name; if it does NOT enumerate per-variant selectors today, no Justfile change is required. If it does, it must be updated separately.

---

## 9. Validation Plan

Run on a clean checkout of the implementation branch.

### 9.1 Output count
```sh
nix flake show 2>&1 | grep -c '^├── nixosConfigurations\|^│   ├── vexos-'
```
Expect 30 `vexos-…` entries under `nixosConfigurations`.

```sh
nix flake show 2>&1 | grep '"vexos-'
```
Must include the four NEW entries:
- `vexos-server-nvidia-legacy535`
- `vexos-server-nvidia-legacy470`
- `vexos-headless-server-nvidia-legacy535`
- `vexos-headless-server-nvidia-legacy470`

### 9.2 Semantic equivalence (sampled)

BEFORE the implementation lands, capture drvPaths for a representative sample on the current `main` branch:

```sh
for n in vexos-desktop-amd vexos-desktop-nvidia vexos-desktop-nvidia-legacy535 \
         vexos-stateless-amd vexos-stateless-nvidia-legacy470 \
         vexos-server-amd vexos-server-nvidia \
         vexos-headless-server-amd vexos-headless-server-nvidia \
         vexos-htpc-amd vexos-htpc-nvidia-legacy535; do
  printf '%s ' "$n"
  nix eval --impure --raw ".#nixosConfigurations.$n.config.system.build.toplevel.drvPath"
  echo
done > /tmp/drvpaths.before
```

AFTER the refactor:

```sh
# (same loop) > /tmp/drvpaths.after
diff /tmp/drvpaths.before /tmp/drvpaths.after
```

Expect: empty diff for all 11 sampled unchanged outputs.

### 9.3 New outputs evaluate

```sh
for n in vexos-server-nvidia-legacy535 vexos-server-nvidia-legacy470 \
         vexos-headless-server-nvidia-legacy535 vexos-headless-server-nvidia-legacy470; do
  nix eval --impure --raw ".#nixosConfigurations.$n.config.system.build.toplevel.drvPath" >/dev/null \
    && echo "$n OK" || echo "$n FAIL"
done
```
Expect: all four print `OK`.

For each, verify the variant propagated:
```sh
nix eval --impure ".#nixosConfigurations.vexos-server-nvidia-legacy535.config.vexos.gpu.nvidiaDriverVariant"
# → "legacy_535"
```

### 9.4 Headless-server branding role

```sh
nix eval --impure ".#nixosConfigurations.vexos-headless-server-amd.config.vexos.branding.role"
# Expect: "headless-server"
nix eval --impure ".#nixosConfigurations.vexos-headless-server-amd.config.system.nixos.distroName"
# Expect: "VexOS Headless Server"
```

### 9.5 stateVersion preservation

```sh
for cfg in vexos-desktop-amd vexos-htpc-amd vexos-server-amd \
           vexos-stateless-amd vexos-headless-server-amd; do
  echo -n "$cfg "; nix eval --impure ".#nixosConfigurations.$cfg.config.system.stateVersion"
done
```
Values must match the values recorded on `main`.

### 9.6 Standard preflight

```sh
nix flake check
sudo nixos-rebuild dry-build --flake .#vexos-desktop-amd
sudo nixos-rebuild dry-build --flake .#vexos-headless-server-nvidia-legacy535   # one of the NEW outputs
```
All must succeed.

### 9.7 External-API smoke test

`nixosModules.base` and the four sibling `*Base` modules must still be valid module values:

```sh
nix eval --impure '.#nixosModules.base'                 --apply 'm: builtins.typeOf m'  # → "lambda" or "set"
nix eval --impure '.#nixosModules.headlessServerBase'   --apply 'm: builtins.typeOf m'
```
And consumers of these modules (the `template/etc-nixos-flake.nix` shape) must remain compilable in principle — covered by `nix flake check` plus the unchanged attribute names listed in §3.5.
