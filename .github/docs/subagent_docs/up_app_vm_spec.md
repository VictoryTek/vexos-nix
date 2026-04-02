# Spec: Integrate the "Up" App into the vexos-vm NixOS Configuration

**Feature Name:** `up_app_vm`
**Date:** 2026-04-02
**Status:** Draft

---

## 1. Current State Analysis

### 1.1 flake.nix — Inputs

```
nixpkgs          github:NixOS/nixpkgs/nixos-25.11
nixpkgs-unstable github:NixOS/nixpkgs/nixos-unstable
nix-gaming        github:fufexan/nix-gaming       (inputs.nixpkgs.follows = "nixpkgs")
home-manager      github:nix-community/home-manager/release-25.11 (inputs.nixpkgs.follows = "nixpkgs")
nix-cachyos-kernel github:xddxdd/nix-cachyos-kernel/release  (NO follows — intentional)
kernel-bazzite    github:VictoryTek/vex-kernels    (NO follows — intentional)
```

### 1.2 flake.nix — outputs destructuring

```nix
outputs = { self, nixpkgs, nixpkgs-unstable, nix-gaming,
            nix-cachyos-kernel, home-manager, kernel-bazzite, ... }@inputs:
```

All three `nixosConfigurations` and one `nixosModules.*` entry pass
`specialArgs = { inherit inputs; }`, making every input accessible inside any
NixOS module through the function argument `inputs`.

### 1.3 hosts/vm.nix — current state

```nix
{ pkgs, lib, inputs, ... }:
{
  imports = [
    ../configuration.nix
    ../modules/gpu/vm.nix
  ];

  boot.kernelPackages = lib.mkOverride 49 (
    pkgs.linuxPackagesFor inputs.kernel-bazzite.packages.x86_64-linux.linux-bazzite
  );

  networking.hostName = "vexos-vm";
}
```

The module already:
- Receives `inputs` as a parameter (via `specialArgs`)
- Accesses a package directly from an input flake as  
  `inputs.kernel-bazzite.packages.x86_64-linux.linux-bazzite`

There is **no** `environment.systemPackages` stanza in `hosts/vm.nix` yet.

### 1.4 modules/gpu/vm.nix

GPU/display configuration only (QEMU guest agent, SPICE, VirtualBox additions,
virtio-gpu/QXL drivers, makeModulesClosure overlay). No involvement needed.

### 1.5 configuration.nix

Shared across all three variants (AMD, NVIDIA, VM). Must not be modified for
a VM-only change.

---

## 2. Problem Definition

The "Up" app (`github:VictoryTek/Up`) is a modern GTK4 + libadwaita system
update/upgrade GUI built in Rust. On NixOS VMs it provides a convenient
one-click interface to update Nix profile packages (both flake-managed and
legacy). The app should be present only in the VM variant of vexos-nix,
consistent with the project's principle of keeping GPU-specific and
variant-specific packages isolated to the relevant host file.

---

## 3. Analysis of the Up Flake

**Repository:** `https://github.com/VictoryTek/Up`  
**Primary language:** Rust  
**UI toolkit:** GTK4 + libadwaita (GNOME-native)  
**License:** GPL-3.0-or-later

### 3.1 Up flake.nix structure (as fetched 2026-04-02)

```nix
{
  inputs = {
    nixpkgs.url      = "github:NixOS/nixpkgs/nixos-25.05";
    flake-utils.url  = "github:numtide/flake-utils";
  };

  outputs = { self, nixpkgs, flake-utils }:
    flake-utils.lib.eachDefaultSystem (system:
      let pkgs = import nixpkgs { inherit system; };
      in {
        packages.default = pkgs.rustPlatform.buildRustPackage {
          pname   = "up";
          version = "0.1.0";
          src     = ./.;
          cargoLock.lockFile = ./Cargo.lock;

          nativeBuildInputs = with pkgs; [ pkg-config wrapGAppsHook4 glib gtk4 ];
          buildInputs       = with pkgs; [ gtk4 libadwaita glib dbus hicolor-icon-theme ];

          preFixup   = '' gappsWrapperArgs+=(--prefix XDG_DATA_DIRS : "$out/share") '';
          postInstall = ''
            install -Dm644 data/io.github.up.desktop $out/share/applications/io.github.up.desktop
            install -Dm644 data/io.github.up.metainfo.xml $out/share/metainfo/io.github.up.metainfo.xml
            install -Dm644 data/icons/hicolor/256x256/apps/io.github.up.png \
              $out/share/icons/hicolor/256x256/apps/io.github.up.png
            gtk4-update-icon-cache -qtf $out/share/icons/hicolor
          '';

          meta = with pkgs.lib; {
            description = "A modern Linux system update & upgrade app";
            license     = licenses.gpl3Plus;
            platforms   = platforms.linux;
            mainProgram = "up";
          };
        };

        devShells.default = pkgs.mkShell { ... };
      });
}
```

### 3.2 Findings

| Item | Value |
|------|-------|
| Package output | `packages.<system>.default` |
| NixOS module output | **None** — no `nixosModules` exported |
| Consumption method | Add as a flake input; reference `inputs.up.packages.x86_64-linux.default` |
| nixpkgs dependency | Yes — `inputs.nixpkgs` must receive `follows = "nixpkgs"` |
| flake-utils dependency | Yes — build-time only; no runtime components; acceptable to leave at Up's pinned version |
| Binary cache coverage | None upstream — package will be built from source on first build |

---

## 4. Proposed Solution

### 4.1 Integration Method

Consume the Up flake as a **flake input** and reference its pre-built default
package directly in `hosts/vm.nix`. No overlay, no NixOS module, no new module
file.

This mirrors the exact pattern already used in `hosts/vm.nix` for the Bazzite
kernel:

```nix
# Existing precedent:
boot.kernelPackages = lib.mkOverride 49 (
  pkgs.linuxPackagesFor inputs.kernel-bazzite.packages.x86_64-linux.linux-bazzite
);

# New pattern (same style, systemPackages instead of kernelPackages):
environment.systemPackages = [
  inputs.up.packages.x86_64-linux.default
];
```

### 4.2 nixpkgs.follows Decision

The Up flake declares `inputs.nixpkgs.url = "github:NixOS/nixpkgs/nixos-25.05"`.
The vexos-nix primary nixpkgs is `nixos-25.11`.

Setting `inputs.up.inputs.nixpkgs.follows = "nixpkgs"` causes the Up package
to be evaluated against the same nixpkgs as the rest of the system
(nixos-25.11). This is the correct approach because:

1. It avoids a duplicate nixpkgs closure in `flake.lock`.
2. GTK4, libadwaita, and the Rust toolchain are all present in nixos-25.11.
3. It ensures ABI consistency between system GTK4 libraries and the Up binary.

The Up flake also pulls in `flake-utils`. Since vexos-nix does not use
`flake-utils` directly, and since `flake-utils` imposes no runtime closure
cost (it is a pure Nix build helper), we do **not** add a
`flake-utils.follows` override. This avoids the need to add `flake-utils` as
a first-class vexos-nix input solely to satisfy a transitional dependency.

### 4.3 Scope Constraint

The package is added **only to the VM variant** through `hosts/vm.nix`.
`configuration.nix` (shared) is not touched. `modules/gpu/vm.nix` (GPU/display
specific) is not touched.

---

## 5. Implementation Steps

### Step 1 — Add `up` input in `flake.nix`

**File:** `flake.nix`  
**Location:** `inputs` block, after the `kernel-bazzite` entry.

Add:

```nix
    # Up — modern GTK4 system update/upgrade GUI for the VM variant.
    # flake-utils is a build-only helper; no follows needed.
    up = {
      url = "github:VictoryTek/Up";
      inputs.nixpkgs.follows = "nixpkgs";
    };
```

The `outputs` function signature does **not** need to change because it already
uses `@inputs` to capture all inputs, and `hosts/vm.nix` receives the complete
`inputs` set via `specialArgs = { inherit inputs; }`.

### Step 2 — Add `up` to `environment.systemPackages` in `hosts/vm.nix`

**File:** `hosts/vm.nix`  
**Location:** Append after the `networking.hostName` line.

Add:

```nix
  # Up — GTK4 system update/upgrade GUI (VM-only)
  environment.systemPackages = [
    inputs.up.packages.x86_64-linux.default
  ];
```

### Final state of `hosts/vm.nix`

```nix
{ pkgs, lib, inputs, ... }:
{
  imports = [
    ../configuration.nix
    ../modules/gpu/vm.nix
  ];

  # Bazzite kernel override (unchanged)
  boot.kernelPackages = lib.mkOverride 49 (
    pkgs.linuxPackagesFor inputs.kernel-bazzite.packages.x86_64-linux.linux-bazzite
  );

  # Distinguish the VM host on the network
  networking.hostName = "vexos-vm";

  # Up — GTK4 system update/upgrade GUI (VM-only)
  environment.systemPackages = [
    inputs.up.packages.x86_64-linux.default
  ];
}
```

---

## 6. Files to Modify

| File | Change |
|------|--------|
| `flake.nix` | Add `up` input block inside `inputs { }` |
| `hosts/vm.nix` | Add `environment.systemPackages` with `inputs.up.packages.x86_64-linux.default` |

**Files NOT modified:**
- `configuration.nix` (shared; must not get VM-specific content)
- `modules/gpu/vm.nix` (GPU/display only)
- `hosts/amd.nix`, `hosts/nvidia.nix`, `hosts/intel.nix` (unaffected variants)

---

## 7. Dependencies

### 7.1 New Flake Input

| Name | URL | follows |
|------|-----|---------|
| `up` | `github:VictoryTek/Up` | `inputs.nixpkgs.follows = "nixpkgs"` |

### 7.2 Transitive Inputs Introduced

| Name | Managed by | Action |
|------|-----------|--------|
| `flake-utils` | Up flake's own lock | No action — build-only helper, no runtime closure |

### 7.3 Runtime Dependencies (from Up's buildInputs)

All resolved from vexos-nix's nixpkgs (nixos-25.11) due to `follows`:

- `gtk4`
- `libadwaita`
- `glib`
- `dbus`
- `hicolor-icon-theme`

All of these are already present on the system via `modules/gnome.nix`, so
there is no additional system-level closure growth beyond the `up` binary itself.

---

## 8. Risks and Mitigations

| Risk | Severity | Mitigation |
|------|----------|-----------|
| Up package must be compiled from source (no binary cache) | Low | First `nixos-rebuild` on the VM will compile the Up Rust crate. Subsequent builds are cached locally. ~2–5 min build on a typical machine. |
| Up's nixpkgs pin (25.05) differs from vexos-nix (25.11) | Low | `inputs.nixpkgs.follows = "nixpkgs"` ensures ABI consistency. GTK4/libadwaita APIs are stable between these releases. |
| Up declares `homepage = "https://github.com/user/up"` (placeholder) | Negligible | Meta field only; does not affect build or runtime. |
| `nix flake check` may error if Up's flake has evaluation issues | Low | Run `nix flake check` in review phase to confirm. The Up flake successfully uses standard `flake-utils.lib.eachDefaultSystem` pattern which is well-supported. |
| Up's Nix backend runs `nix profile upgrade` — on NixOS this affects user profiles, not the system | Informational | Expected behavior; Up is a GUI convenience tool, not a system management replacement. |

---

## 9. Source Research

1. **Up Repository README** — `https://github.com/VictoryTek/Up` — confirms Nix flake consumption method, package output name, and Nix backend feature.
2. **Up flake.nix** — `https://raw.githubusercontent.com/VictoryTek/Up/main/flake.nix` — full flake structure confirming `packages.default`, `nixpkgs` input, `flake-utils` input.
3. **NixOS Wiki — Flakes** — `https://nixos.wiki/wiki/Flakes` — `inputs.<name>.inputs.nixpkgs.follows` pattern for de-duplicating nixpkgs; `specialArgs` for passing flake inputs to NixOS modules.
4. **nix.dev — Flakes concepts** — `https://nix.dev/concepts/flakes.html` — `follows` statement semantics; avoiding multiple nixpkgs versions via explicit overrides.
5. **vexos-nix `flake.nix`** — project source — confirms `specialArgs = { inherit inputs; }` is used for all three `nixosConfigurations`; confirms `@inputs` capture pattern.
6. **vexos-nix `hosts/vm.nix`** — project source — confirms `inputs` parameter is already in scope; establishes the `inputs.<name>.packages.x86_64-linux.<pkg>` precedent for direct input package references.
7. **NixOS Manual — `environment.systemPackages`** — standard NixOS option for adding packages to the system environment; accepts any derivation, including those from flake inputs.
