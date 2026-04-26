# Host Normalization Specification (B1 Audit Finding)

## 1. Current State Analysis

### 1.1 Host File Inventory (20 files)

| Host File | Imports `asus.nix`? | Sets `vbox-guest`? | Variant Stamp | Sets `hostName`? | Other Content |
|---|---|---|---|---|---|
| `desktop-amd.nix` | YES | `lib.mkForce false` | none | no | `distroName` |
| `desktop-nvidia.nix` | YES | `lib.mkForce false` | none | no | `distroName` |
| `desktop-intel.nix` | **NO** | `lib.mkForce false` | none | no | `distroName` |
| `desktop-vm.nix` | **NO** | none | none | **YES** `lib.mkDefault "vexos"` | `distroName`, bootloader comments |
| `htpc-amd.nix` | no | `lib.mkForce false` | `environment.etc` = `"vexos-htpc-amd\n"` | no | `distroName` |
| `htpc-nvidia.nix` | no | `lib.mkForce false` | `environment.etc` = `"vexos-htpc-nvidia\n"` | no | `distroName` |
| `htpc-intel.nix` | no | `lib.mkForce false` | `environment.etc` = `"vexos-htpc-intel\n"` | no | `distroName` |
| `htpc-vm.nix` | no | none | `environment.etc` = `"vexos-htpc-vm\n"` | **YES** `lib.mkDefault "vexos"` | `distroName` |
| `server-amd.nix` | no | `lib.mkForce false` | none | no | `distroName` |
| `server-nvidia.nix` | no | `lib.mkForce false` | none | no | `distroName` |
| `server-intel.nix` | no | `lib.mkForce false` | none | no | `distroName` |
| `server-vm.nix` | no | none | none | **YES** `lib.mkDefault "vexos"` | `distroName` |
| `headless-server-amd.nix` | no | `lib.mkForce false` | none | no | `distroName` |
| `headless-server-nvidia.nix` | no | `lib.mkForce false` | none | no | `distroName` |
| `headless-server-intel.nix` | no | `lib.mkForce false` | none | no | `distroName` |
| `headless-server-vm.nix` | no | none | none | **YES** `lib.mkDefault "vexos"` | `distroName` |
| `stateless-amd.nix` | no | `lib.mkForce false` | `vexos.variant` = `"vexos-stateless-amd"` | no | `distroName`, `vexos.stateless.disk` |
| `stateless-nvidia.nix` | no | `lib.mkForce false` | `vexos.variant` = `"vexos-stateless-nvidia"` | no | `distroName`, `vexos.stateless.disk` |
| `stateless-intel.nix` | no | `lib.mkForce false` | `vexos.variant` = `"vexos-stateless-intel"` | no | `distroName`, `vexos.stateless.disk` |
| `stateless-vm.nix` | no | none | `vexos.variant` = `"vexos-stateless-vm"` | **YES** `lib.mkDefault "vexos"` | `distroName`, `vexos.stateless.disk` |

### 1.2 GPU Module Content Relevant to VBox-Guest

| Module | Imports parent? | Sets `vbox-guest`? | Notes |
|---|---|---|---|
| `modules/gpu/amd.nix` | — | no | Base AMD (display roles) |
| `modules/gpu/nvidia.nix` | — | no | Base NVIDIA (display roles) |
| `modules/gpu/intel.nix` | — | no | Base Intel (display roles) |
| `modules/gpu/amd-headless.nix` | **no** (re-implements) | no | Headless AMD; no `imports = [ ./amd.nix ]` |
| `modules/gpu/intel-headless.nix` | **no** (re-implements) | no | Headless Intel; no `imports = [ ./intel.nix ]` |
| `modules/gpu/nvidia-headless.nix` | **yes** (`imports = [ ./nvidia.nix ]`) | no (inherits) | Headless NVIDIA; inherits from nvidia.nix |
| `modules/gpu/vm.nix` | — | `true` | Sets `virtualisation.virtualbox.guest.enable = true` |

### 1.3 Current `mkHost` Contract (flake.nix)

`mkHost` accepts `{ role, gpu, nvidiaVariant }` and builds:
1. `/etc/nixos/hardware-configuration.nix`
2. `roles.${role}.baseModules` (overlay, upModule, proxmox…)
3. Home-manager wiring (per-role homeFile)
4. `roles.${role}.extraModules` (impermanence / serverServicesModule)
5. `./hosts/${role}-${gpu}.nix` (host file)
6. `legacyExtra` (nvidiaDriverVariant if non-null)

Each entry in `hostList` has a `name` field (e.g. `"vexos-desktop-amd"`) that is the flake output key. This name is the variant identity. Currently `mkHost` does NOT set a variant stamp.

### 1.4 Variant Stamp Mechanisms

**HTPC (4 hosts):** Inline `environment.etc."nixos/vexos-variant".text = "vexos-htpc-<gpu>\n";` — standard NixOS etc mechanism, writes a symlink under `/etc/nixos/`.

**Stateless (4 hosts):** `vexos.variant = "vexos-stateless-<gpu>";` — sets a NixOS option declared in `modules/impermanence.nix` (line 70). The option feeds `system.activationScripts.vexosVariant` which writes directly to `${cfg.persistentPath}/etc/nixos/vexos-variant`, bypassing a timing race between NixOS `etc` activation and the impermanence bind-mount of `/etc/nixos`. The whole config block is guarded by `lib.mkIf cfg.enable` (i.e., `vexos.impermanence.enable = true`). The option has `default = ""` and the activation script fires only when non-empty.

**Desktop, Server, Headless-Server (12 hosts):** No variant stamp at all.

### 1.5 `vexos.variant` Option Scope

Defined only in `modules/impermanence.nix`. Used only by the activation script in the same file. Not read by any other module. The option only exists in configurations that import `impermanence.nix` (i.e., stateless role only — `configuration-stateless.nix` is the sole importer via `modules/impermanence.nix`). Setting `vexos.variant` in a non-stateless host would cause an "undefined option" error.

### 1.6 `networking.hostName` in `modules/network.nix`

`modules/network.nix` line 10: `networking.hostName = lib.mkDefault "vexos";` — already set as mkDefault. All 5 VM hosts redundantly re-declare the same value with the same priority.

---

## 2. Problem Definition

Audit finding **B1: Host file inconsistencies** identifies four normalization issues:

| Sub-task | Issue | Scope |
|---|---|---|
| **A** | `asus.nix` imported by `desktop-amd` and `desktop-nvidia` but NOT `desktop-intel` and `desktop-vm` | 2 files to add import |
| **B** | Variant stamp uses 3 different mechanisms (env.etc, vexos.variant, nothing) across 5 roles | 20 hosts affected (8 have stamps, 12 have none) |
| **C** | `virtualisation.virtualbox.guest.enable = lib.mkForce false` duplicated in 15 non-VM host files | 15 files to remove, 5 GPU modules to add line |
| **D** | `networking.hostName = lib.mkDefault "vexos"` redundantly set in 5 VM hosts | 5 files to remove line |

---

## 3. Proposed Solution Architecture

### Sub-task A: Add `asus.nix` to remaining desktop hosts

Add `../modules/asus.nix` to the imports list in:
- `hosts/desktop-intel.nix`
- `hosts/desktop-vm.nix`

`asus.nix` is safe on non-ASUS hardware (asusd and supergfxd exit gracefully when ASUS platform drivers are absent — documented in the module header comment). It is also safe in a VM (the kernel modules simply won't bind to any device).

### Sub-task B: Consolidate variant stamp via `mkHost`

**Decision: Hybrid approach — `environment.etc` for non-stateless, `vexos.variant` for stateless, both driven from `mkHost`.**

**Rationale for NOT using a single `environment.etc` mechanism for all roles:**
The stateless role has a timing constraint: `environment.etc` writes via NixOS `etc` activation, but on a tmpfs-rooted system, `/etc/nixos` is a bind-mount from `/persistent/etc/nixos` set up by the impermanence module. The existing `system.activationScripts.vexosVariant` in `modules/impermanence.nix` writes directly to the persistent subvolume path to bypass this race. Replacing it with `environment.etc` risks the stamp being written to ephemeral tmpfs before the bind mount is established.

**Rationale for NOT using `environment.etc` per-host (Option 1):**
DRY violation — the variant name is already known in `mkHost` via the `name` field. No reason to manually repeat it in 20 files.

**Rationale for `mkHost` (Option 2, chosen):**
The flake output name IS the variant identity. `mkHost` already has access to it. Adding the stamp there is a single-line change that covers all 30 outputs automatically, including future additions.

#### Implementation detail in `mkHost`:

```nix
mkHost = { name, role, gpu, nvidiaVariant ? null }:
  let
    r           = roles.${role};
    hostFile    = ./hosts + "/${role}-${gpu}.nix";
    legacyExtra = lib.optional (nvidiaVariant != null)
                    { vexos.gpu.nvidiaDriverVariant = nvidiaVariant; };

    # Variant stamp: identifies the active build variant in /etc/nixos/vexos-variant.
    # Non-stateless: use standard environment.etc (file managed by NixOS etc activation).
    # Stateless: use vexos.variant option which feeds a persistent-aware activation
    # script in modules/impermanence.nix (bypasses tmpfs/bind-mount timing race).
    variantModule =
      if role == "stateless"
      then { vexos.variant = name; }
      else { environment.etc."nixos/vexos-variant".text = "${name}\n"; };
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
      ++ legacyExtra
      ++ [ variantModule ];
  };
```

The call site must also pass `name` through. Currently `mkHost` is called as:
```nix
value = mkHost {
  inherit (h) role gpu;
  nvidiaVariant = h.nvidiaVariant or null;
};
```
Change to:
```nix
value = mkHost {
  inherit (h) name role gpu;
  nvidiaVariant = h.nvidiaVariant or null;
};
```

**Removals:**
- Remove `environment.etc."nixos/vexos-variant".text` from `hosts/htpc-amd.nix`, `hosts/htpc-nvidia.nix`, `hosts/htpc-intel.nix`, `hosts/htpc-vm.nix`.
- Remove `vexos.variant = "vexos-stateless-*";` from `hosts/stateless-amd.nix`, `hosts/stateless-nvidia.nix`, `hosts/stateless-intel.nix`, `hosts/stateless-vm.nix`.

**Behavioral change (improvement):** NVIDIA legacy stateless variants (e.g. `vexos-stateless-nvidia-legacy535`) currently get `vexos.variant = "vexos-stateless-nvidia"` because the host file is shared. With mkHost, each output gets its exact name as the variant. This is more accurate.

**Behavioral change (new stamps):** Desktop, server, and headless-server hosts that currently have NO variant stamp will now get one. This is additive and non-breaking.

### Sub-task C: Move VBox-guest disable into GPU brand modules

Add `virtualisation.virtualbox.guest.enable = lib.mkForce false;` to:
1. `modules/gpu/amd.nix`
2. `modules/gpu/nvidia.nix`
3. `modules/gpu/intel.nix`
4. `modules/gpu/amd-headless.nix` (does NOT import `amd.nix`, so needs its own line)
5. `modules/gpu/intel-headless.nix` (does NOT import `intel.nix`, so needs its own line)

**NOT added to:**
- `modules/gpu/nvidia-headless.nix` — imports `./nvidia.nix`, inherits the line automatically.
- `modules/gpu/vm.nix` — sets `virtualisation.virtualbox.guest.enable = true;` (VM guests need VirtualBox guest additions).

**Remove from all 15 non-VM host files:**
`desktop-amd`, `desktop-nvidia`, `desktop-intel`, `htpc-amd`, `htpc-nvidia`, `htpc-intel`, `server-amd`, `server-nvidia`, `server-intel`, `headless-server-amd`, `headless-server-nvidia`, `headless-server-intel`, `stateless-amd`, `stateless-nvidia`, `stateless-intel`.

**Comment:** Add a brief comment in the GPU modules explaining the purpose (prevent VBox guest additions from building against incompatible kernels on bare-metal hosts). No comment needed per-host anymore.

**nixosModules impact:** The `nixosModules.gpuAmd`, `gpuNvidia`, `gpuIntel`, `gpuAmdHeadless`, `gpuIntelHeadless` wrappers in `flake.nix` also set `virtualisation.virtualbox.guest.enable = lib.mkForce false;` inline. Once the GPU modules themselves include this, the wrapper lines become redundant. **Out of scope for this change** — the nixosModules wrappers are consumed by the thin `/etc/nixos/flake.nix` template and their cleanup is a separate follow-on task. Leaving redundant `lib.mkForce false` in both places is harmless (idempotent).

### Sub-task D: Remove redundant `networking.hostName` from VM hosts

Remove `networking.hostName = lib.mkDefault "vexos";` from all 5 VM hosts:
- `hosts/desktop-vm.nix`
- `hosts/htpc-vm.nix`
- `hosts/server-vm.nix`
- `hosts/headless-server-vm.nix`
- `hosts/stateless-vm.nix`

`modules/network.nix` already sets `networking.hostName = lib.mkDefault "vexos";` (confirmed at line 10). The VM hosts re-declare the identical value at the identical priority — pure redundancy.

---

## 4. Implementation Steps

### Phase 1: Sub-task C — VBox-guest into GPU modules (do first, largest blast radius)

**Step 1.1:** Add to `modules/gpu/amd.nix` (after the last existing config line):
```nix
  # Prevent hardware-configuration.nix (generated inside a VM) from enabling
  # VirtualBox guest additions on bare-metal hosts. Guest additions fail to
  # build against linuxPackages_latest (kernel 6.12+).
  virtualisation.virtualbox.guest.enable = lib.mkForce false;
```

**Step 1.2:** Add identical block to `modules/gpu/nvidia.nix` (inside `config = { ... }`).

**Step 1.3:** Add identical block to `modules/gpu/intel.nix` (after the last existing config line).

**Step 1.4:** Add to `modules/gpu/amd-headless.nix` (after the tmpfiles.rules block).

**Step 1.5:** Add to `modules/gpu/intel-headless.nix` (after the last existing config line).

**Step 1.6:** Verify `modules/gpu/nvidia-headless.nix` inherits via `imports = [ ./nvidia.nix ]` — no change needed.

**Step 1.7:** Verify `modules/gpu/vm.nix` sets `virtualisation.virtualbox.guest.enable = true;` — no change needed.

**Step 1.8:** Remove `virtualisation.virtualbox.guest.enable = lib.mkForce false;` and its comment block from all 15 non-VM host files:
- `hosts/desktop-amd.nix` (lines 14–16)
- `hosts/desktop-nvidia.nix` (lines 14–16)
- `hosts/desktop-intel.nix` (lines 12–14)
- `hosts/htpc-amd.nix` (line 12)
- `hosts/htpc-nvidia.nix` (line 12)
- `hosts/htpc-intel.nix` (line 12)
- `hosts/server-amd.nix` (line 11)
- `hosts/server-nvidia.nix` (line 11)
- `hosts/server-intel.nix` (line 11)
- `hosts/headless-server-amd.nix` (line 11)
- `hosts/headless-server-nvidia.nix` (line 11)
- `hosts/headless-server-intel.nix` (line 11)
- `hosts/stateless-amd.nix` (lines 21–24)
- `hosts/stateless-nvidia.nix` (lines 21–24)
- `hosts/stateless-intel.nix` (lines 21–24)

### Phase 2: Sub-task D — Remove redundant hostName from VM hosts

**Step 2.1:** Remove `networking.hostName = lib.mkDefault "vexos";` from:
- `hosts/desktop-vm.nix` (line 21)
- `hosts/htpc-vm.nix` (line 12)
- `hosts/server-vm.nix` (line 11)
- `hosts/headless-server-vm.nix` (line 11)
- `hosts/stateless-vm.nix` (line 19)

### Phase 3: Sub-task A — Add `asus.nix` to remaining desktop hosts

**Step 3.1:** Add `../modules/asus.nix` to imports in `hosts/desktop-intel.nix`.

**Step 3.2:** Add `../modules/asus.nix` to imports in `hosts/desktop-vm.nix`.

### Phase 4: Sub-task B — Variant stamp in `mkHost`

**Step 4.1:** Modify `mkHost` in `flake.nix`:
- Add `name` parameter to the function signature.
- Add `variantModule` that conditionally produces `environment.etc` (non-stateless) or `vexos.variant` (stateless).
- Append `variantModule` to the modules list.

**Step 4.2:** Modify the `nixosConfigurations` call site to pass `name`:
```nix
value = mkHost {
  inherit (h) name role gpu;
  nvidiaVariant = h.nvidiaVariant or null;
};
```

**Step 4.3:** Remove `environment.etc."nixos/vexos-variant".text` from:
- `hosts/htpc-amd.nix`
- `hosts/htpc-nvidia.nix`
- `hosts/htpc-intel.nix`
- `hosts/htpc-vm.nix`

**Step 4.4:** Remove `vexos.variant = "vexos-stateless-*";` from:
- `hosts/stateless-amd.nix`
- `hosts/stateless-nvidia.nix`
- `hosts/stateless-intel.nix`
- `hosts/stateless-vm.nix`

---

## 5. Semantic-Equivalence Checklist

### 5.1 `virtualisation.virtualbox.guest.enable` — Before/After

| Host | Before | After | Source |
|---|---|---|---|
| desktop-amd | `false` (host mkForce) | `false` (gpu/amd.nix mkForce) | Equivalent |
| desktop-nvidia | `false` (host mkForce) | `false` (gpu/nvidia.nix mkForce) | Equivalent |
| desktop-intel | `false` (host mkForce) | `false` (gpu/intel.nix mkForce) | Equivalent |
| **desktop-vm** | `true` (gpu/vm.nix) | `true` (gpu/vm.nix) | **Unchanged** |
| htpc-amd | `false` (host mkForce) | `false` (gpu/amd.nix mkForce) | Equivalent |
| htpc-nvidia | `false` (host mkForce) | `false` (gpu/nvidia.nix mkForce) | Equivalent |
| htpc-intel | `false` (host mkForce) | `false` (gpu/intel.nix mkForce) | Equivalent |
| **htpc-vm** | `true` (gpu/vm.nix) | `true` (gpu/vm.nix) | **Unchanged** |
| server-amd | `false` (host mkForce) | `false` (gpu/amd.nix mkForce) | Equivalent |
| server-nvidia | `false` (host mkForce) | `false` (gpu/nvidia.nix mkForce) | Equivalent |
| server-intel | `false` (host mkForce) | `false` (gpu/intel.nix mkForce) | Equivalent |
| **server-vm** | `true` (gpu/vm.nix) | `true` (gpu/vm.nix) | **Unchanged** |
| headless-server-amd | `false` (host mkForce) | `false` (gpu/amd-headless.nix mkForce) | Equivalent |
| headless-server-nvidia | `false` (host mkForce) | `false` (gpu/nvidia.nix→nvidia-headless.nix mkForce) | Equivalent |
| headless-server-intel | `false` (host mkForce) | `false` (gpu/intel-headless.nix mkForce) | Equivalent |
| **headless-server-vm** | `true` (gpu/vm.nix) | `true` (gpu/vm.nix) | **Unchanged** |
| stateless-amd | `false` (host mkForce) | `false` (gpu/amd.nix mkForce) | Equivalent |
| stateless-nvidia | `false` (host mkForce) | `false` (gpu/nvidia.nix mkForce) | Equivalent |
| stateless-intel | `false` (host mkForce) | `false` (gpu/intel.nix mkForce) | Equivalent |
| **stateless-vm** | `true` (gpu/vm.nix) | `true` (gpu/vm.nix) | **Unchanged** |

Key invariant: VM hosts import `gpu/vm.nix` which sets `enable = true` (plain assignment). Non-VM GPU modules now set `enable = lib.mkForce false`. These two modules are NEVER imported together (each host imports exactly one GPU module), so there is no priority conflict.

### 5.2 `networking.hostName` — Before/After

| Host | Before | After | Source |
|---|---|---|---|
| All non-VM hosts | `"vexos"` (from network.nix mkDefault) | `"vexos"` (from network.nix mkDefault) | Unchanged |
| desktop-vm | `"vexos"` (host mkDefault + network.nix mkDefault) | `"vexos"` (network.nix mkDefault) | Equivalent |
| htpc-vm | `"vexos"` (host mkDefault + network.nix mkDefault) | `"vexos"` (network.nix mkDefault) | Equivalent |
| server-vm | `"vexos"` (host mkDefault + network.nix mkDefault) | `"vexos"` (network.nix mkDefault) | Equivalent |
| headless-server-vm | `"vexos"` (host mkDefault + network.nix mkDefault) | `"vexos"` (network.nix mkDefault) | Equivalent |
| stateless-vm | `"vexos"` (host mkDefault + network.nix mkDefault) | `"vexos"` (network.nix mkDefault) | Equivalent |

### 5.3 `asus.nix` Import — Before/After

| Host | Before | After |
|---|---|---|
| desktop-amd | imported | imported (unchanged) |
| desktop-nvidia | imported | imported (unchanged) |
| desktop-intel | **NOT imported** | **imported** (new) |
| desktop-vm | **NOT imported** | **imported** (new) |
| All non-desktop hosts | not imported | not imported (unchanged) |

### 5.4 Variant Stamp (`/etc/nixos/vexos-variant`) — Before/After

| Host | Before | After | Mechanism |
|---|---|---|---|
| desktop-amd | **none** | `"vexos-desktop-amd\n"` | **NEW** — mkHost env.etc |
| desktop-nvidia | **none** | `"vexos-desktop-nvidia\n"` | **NEW** — mkHost env.etc |
| desktop-nvidia-legacy535 | **none** | `"vexos-desktop-nvidia-legacy535\n"` | **NEW** — mkHost env.etc |
| desktop-nvidia-legacy470 | **none** | `"vexos-desktop-nvidia-legacy470\n"` | **NEW** — mkHost env.etc |
| desktop-intel | **none** | `"vexos-desktop-intel\n"` | **NEW** — mkHost env.etc |
| desktop-vm | **none** | `"vexos-desktop-vm\n"` | **NEW** — mkHost env.etc |
| htpc-amd | `"vexos-htpc-amd\n"` | `"vexos-htpc-amd\n"` | Moved to mkHost env.etc |
| htpc-nvidia | `"vexos-htpc-nvidia\n"` | `"vexos-htpc-nvidia\n"` | Moved to mkHost env.etc |
| htpc-nvidia-legacy535 | `"vexos-htpc-nvidia\n"` | `"vexos-htpc-nvidia-legacy535\n"` | **CORRECTED** — now exact name |
| htpc-nvidia-legacy470 | `"vexos-htpc-nvidia\n"` | `"vexos-htpc-nvidia-legacy470\n"` | **CORRECTED** — now exact name |
| htpc-intel | `"vexos-htpc-intel\n"` | `"vexos-htpc-intel\n"` | Moved to mkHost env.etc |
| htpc-vm | `"vexos-htpc-vm\n"` | `"vexos-htpc-vm\n"` | Moved to mkHost env.etc |
| server-amd | **none** | `"vexos-server-amd\n"` | **NEW** — mkHost env.etc |
| server-nvidia | **none** | `"vexos-server-nvidia\n"` | **NEW** — mkHost env.etc |
| server-nvidia-legacy535 | **none** | `"vexos-server-nvidia-legacy535\n"` | **NEW** — mkHost env.etc |
| server-nvidia-legacy470 | **none** | `"vexos-server-nvidia-legacy470\n"` | **NEW** — mkHost env.etc |
| server-intel | **none** | `"vexos-server-intel\n"` | **NEW** — mkHost env.etc |
| server-vm | **none** | `"vexos-server-vm\n"` | **NEW** — mkHost env.etc |
| headless-server-amd | **none** | `"vexos-headless-server-amd\n"` | **NEW** — mkHost env.etc |
| headless-server-nvidia | **none** | `"vexos-headless-server-nvidia\n"` | **NEW** — mkHost env.etc |
| headless-server-nvidia-legacy535 | **none** | `"vexos-headless-server-nvidia-legacy535\n"` | **NEW** — mkHost env.etc |
| headless-server-nvidia-legacy470 | **none** | `"vexos-headless-server-nvidia-legacy470\n"` | **NEW** — mkHost env.etc |
| headless-server-intel | **none** | `"vexos-headless-server-intel\n"` | **NEW** — mkHost env.etc |
| headless-server-vm | **none** | `"vexos-headless-server-vm\n"` | **NEW** — mkHost env.etc |
| stateless-amd | `"vexos-stateless-amd"` | `"vexos-stateless-amd"` | Moved to mkHost vexos.variant |
| stateless-nvidia | `"vexos-stateless-nvidia"` | `"vexos-stateless-nvidia"` | Moved to mkHost vexos.variant |
| stateless-nvidia-legacy535 | `"vexos-stateless-nvidia"` | `"vexos-stateless-nvidia-legacy535"` | **CORRECTED** — now exact name |
| stateless-nvidia-legacy470 | `"vexos-stateless-nvidia"` | `"vexos-stateless-nvidia-legacy470"` | **CORRECTED** — now exact name |
| stateless-intel | `"vexos-stateless-intel"` | `"vexos-stateless-intel"` | Moved to mkHost vexos.variant |
| stateless-vm | `"vexos-stateless-vm"` | `"vexos-stateless-vm"` | Moved to mkHost vexos.variant |

Note: Non-stateless stamps include a trailing `\n`; stateless stamps do not (the impermanence activation script uses `printf '%s'` without newline, matching the existing behavior).

---

## 6. Dependencies

| Dependency | Status | Impact |
|---|---|---|
| **Change #3** (network.nix `hostName = lib.mkDefault "vexos"`) | **In place** | Sub-task D depends on this. Confirmed at `modules/network.nix` line 10. |
| **Change #7** (GPU headless refactor) | **NOT yet done** | `amd-headless.nix` and `intel-headless.nix` currently re-implement independently (do not import base). Sub-task C must add `vbox-guest` to these files separately. If change #7 later makes them import their base modules, the line becomes inherited and the separate copy can be removed. |
| **impermanence.nix `vexos.variant` option** | Stateless-only | Option is defined inside the `lib.mkIf cfg.enable` config block of impermanence.nix. Only exists when `vexos.impermanence.enable = true`. Must NOT be set for non-stateless roles. The mkHost `variantModule` respects this by using `environment.etc` for non-stateless roles. |

---

## 7. Risks and Mitigations

### Risk 1: VM hosts accidentally getting VBox-guest force-disabled
**Assessment:** SAFE. VM hosts import `modules/gpu/vm.nix`, which is the only GPU module that sets `virtualisation.virtualbox.guest.enable = true`. Non-VM GPU modules (`amd.nix`, `nvidia.nix`, `intel.nix`, `amd-headless.nix`, `intel-headless.nix`) are never imported by VM hosts. Each host imports exactly one GPU module — there is no overlap.

### Risk 2: Stateless variant stamp broken by removing per-host `vexos.variant`
**Assessment:** LOW. The `vexos.variant` value is now set by `mkHost` via the `variantModule` inline module. The impermanence activation script in `modules/impermanence.nix` reads `config.vexos.variant` — it doesn't care where the value was set (host file or mkHost module). Semantically equivalent.

### Risk 3: NVIDIA legacy variant stamps now more specific
**Assessment:** IMPROVEMENT. NVIDIA legacy variants (e.g. `vexos-htpc-nvidia-legacy535`) currently get the base variant name (`"vexos-htpc-nvidia"`) because the host file is shared. With mkHost, they get their exact output name. This is more accurate for identification purposes. No downstream code parses the variant stamp format.

### Risk 4: `asus.nix` on VM hosts causing eval issues
**Assessment:** SAFE. `asus.nix` enables `services.asusd`, `services.supergfxd`, and adds `asusctl` to systemPackages. These are standard NixOS services that evaluate cleanly regardless of hardware. On a VM, the ASUS kernel modules (`asus-nb-wmi`, `asus-wmi`) simply won't bind to any device. The `asusd` systemd service will start, detect no ASUS hardware, and idle. The `asus.nix` module header comment itself states: "Safe on non-ASUS hardware: asusd and supergfxd exit gracefully when ASUS platform drivers are absent." The header also says "DO NOT import in hosts/vm.nix" — but this comment predates the user's decision to include it on all desktop variants. The comment should be updated.

### Risk 5: `environment.etc` conflict with existing files
**Assessment:** SAFE. `environment.etc."nixos/vexos-variant"` creates a NixOS-managed file. Hosts that previously had no stamp simply gain a new file. Hosts that previously wrote via `environment.etc` (htpc) get identical behavior from a different source (mkHost instead of host file). No conflicting definitions — only one source sets the value.

### Risk 6: mkHost signature change breaking other callers
**Assessment:** SAFE. `mkHost` is a local `let` binding inside `flake.nix` `outputs`. The only call site is the `nixosConfigurations` generation via `map`. There are no external callers. Adding `name` to the parameter set is a purely internal change.

---

## 8. Out of Scope

- **GPU headless refactor (change #7):** Making `amd-headless.nix` / `intel-headless.nix` import their base modules is a separate task. This spec adds the vbox-guest line to the headless modules independently.
- **nixosModules wrapper cleanup:** The `gpuAmd`, `gpuNvidia`, `gpuIntel`, `gpuAmdHeadless`, `gpuIntelHeadless` wrappers in `flake.nix` also set `virtualisation.virtualbox.guest.enable = lib.mkForce false` inline. Once the GPU modules include it, these wrapper lines are redundant but harmless. Cleanup is a follow-on.
- **configuration-*.nix changes:** No changes to any `configuration-*.nix` file.
- **`modules/impermanence.nix` changes:** The `vexos.variant` option and activation script remain as-is. Only the VALUE source changes (from host file to mkHost).
- **README, justfile, preflight.sh:** No changes.
- **`asus.nix` header comment update:** The "DO NOT import in hosts/vm.nix" comment in `modules/asus.nix` should be updated since the user decided to include it in all desktop variants. This is a cosmetic doc fix that can be done in this change or deferred.

---

## 9. Validation Plan

### 9.1 Structural validation (fast — nix eval)

Test 5 representative hosts:

```bash
# Non-VM, non-stateless: variant stamp via environment.etc, vbox-guest from GPU module
nix eval --impure --json \
  '.#nixosConfigurations.vexos-desktop-amd.config.environment.etc' \
  --apply 'etc: etc."nixos/vexos-variant".text'
# Expected: "vexos-desktop-amd\n"

# VM host: no vbox-guest force-disable, variant stamp via environment.etc
nix eval --impure --json \
  '.#nixosConfigurations.vexos-desktop-vm.config.virtualisation.virtualbox.guest.enable'
# Expected: true

# Non-VM host: vbox-guest disabled
nix eval --impure --json \
  '.#nixosConfigurations.vexos-server-intel.config.virtualisation.virtualbox.guest.enable'
# Expected: false

# Stateless: variant stamp via vexos.variant option
nix eval --impure --raw \
  '.#nixosConfigurations.vexos-stateless-amd.config.vexos.variant'
# Expected: "vexos-stateless-amd"

# NVIDIA legacy: correct specific variant name
nix eval --impure --json \
  '.#nixosConfigurations.vexos-htpc-nvidia-legacy535.config.environment.etc' \
  --apply 'etc: etc."nixos/vexos-variant".text'
# Expected: "vexos-htpc-nvidia-legacy535\n"
```

### 9.2 Build validation

```bash
# Full flake check
nix flake check

# Dry-build representative hosts
sudo nixos-rebuild dry-build --flake .#vexos-desktop-amd
sudo nixos-rebuild dry-build --flake .#vexos-desktop-vm
sudo nixos-rebuild dry-build --flake .#vexos-stateless-amd
```

### 9.3 Regression checks

- Confirm `asus.nix` now imported by all 4 desktop hosts (check imports via nix eval or grep).
- Confirm no host file contains `virtualisation.virtualbox.guest.enable`.
- Confirm no VM host file contains `networking.hostName`.
- Confirm no htpc host file contains `environment.etc."nixos/vexos-variant"`.
- Confirm no stateless host file contains `vexos.variant`.

---

## 10. File Change Summary

| File | Changes |
|---|---|
| `flake.nix` | Add `name` param to `mkHost`, add `variantModule`, pass `name` at call site |
| `modules/gpu/amd.nix` | Add `virtualisation.virtualbox.guest.enable = lib.mkForce false;` |
| `modules/gpu/nvidia.nix` | Add `virtualisation.virtualbox.guest.enable = lib.mkForce false;` (inside `config`) |
| `modules/gpu/intel.nix` | Add `virtualisation.virtualbox.guest.enable = lib.mkForce false;` |
| `modules/gpu/amd-headless.nix` | Add `virtualisation.virtualbox.guest.enable = lib.mkForce false;` |
| `modules/gpu/intel-headless.nix` | Add `virtualisation.virtualbox.guest.enable = lib.mkForce false;` |
| `hosts/desktop-intel.nix` | Add `../modules/asus.nix` to imports |
| `hosts/desktop-vm.nix` | Add `../modules/asus.nix` to imports; remove `networking.hostName` |
| `hosts/desktop-amd.nix` | Remove vbox-guest line + comment |
| `hosts/desktop-nvidia.nix` | Remove vbox-guest line + comment |
| `hosts/htpc-amd.nix` | Remove vbox-guest line; remove variant-stamp line |
| `hosts/htpc-nvidia.nix` | Remove vbox-guest line; remove variant-stamp line |
| `hosts/htpc-intel.nix` | Remove vbox-guest line; remove variant-stamp line |
| `hosts/htpc-vm.nix` | Remove variant-stamp line; remove `networking.hostName` |
| `hosts/server-amd.nix` | Remove vbox-guest line |
| `hosts/server-nvidia.nix` | Remove vbox-guest line |
| `hosts/server-intel.nix` | Remove vbox-guest line |
| `hosts/server-vm.nix` | Remove `networking.hostName` |
| `hosts/headless-server-amd.nix` | Remove vbox-guest line |
| `hosts/headless-server-nvidia.nix` | Remove vbox-guest line |
| `hosts/headless-server-intel.nix` | Remove vbox-guest line |
| `hosts/headless-server-vm.nix` | Remove `networking.hostName` |
| `hosts/stateless-amd.nix` | Remove vbox-guest line + comment; remove `vexos.variant` |
| `hosts/stateless-nvidia.nix` | Remove vbox-guest line + comment; remove `vexos.variant` |
| `hosts/stateless-intel.nix` | Remove vbox-guest line + comment; remove `vexos.variant` |
| `hosts/stateless-vm.nix` | Remove `vexos.variant`; remove `networking.hostName` |

**Total: 26 files modified** (1 flake.nix + 5 GPU modules + 20 host files)
