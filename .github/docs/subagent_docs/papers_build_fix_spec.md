# Spec: papers Build Failure Fix

**Feature name:** `papers_build_fix`
**Date:** 2026-05-12
**Status:** Ready for Implementation

---

## 1. Current State

### Where `papers` is included

GNOME's NixOS module automatically includes `papers` (GNOME Papers 49.4, the document
viewer — upstream successor to Evince) as a core default application whenever
`services.desktopManager.gnome.enable = true`. It is **not** listed explicitly in any
`environment.systemPackages` in this repository.

The current per-role exclusion state:

| Role module | Excludes `papers` from nixpkgs? | Gets Papers how? |
|---|---|---|
| `gnome.nix` (universal base) | **No** | — |
| `gnome-desktop.nix` | **No** | Flatpak `org.gnome.Papers` |
| `gnome-htpc.nix` | Yes (`environment.gnome.excludePackages`) | Not installed |
| `gnome-server.nix` | Yes (`environment.gnome.excludePackages`) | Not installed |
| `gnome-stateless.nix` | Yes (`environment.gnome.excludePackages`) | Not installed |

**Result:** The desktop role (and ONLY the desktop role) currently pulls in the nixpkgs
`papers` 49.4 package at build time, triggering the failure described below.

---

## 2. Problem

### Build error

```
error: Cannot build '/nix/store/w4k8b4mv2659fxnzpf6daqpf19sh4164-papers-49.4.drv'.
Reason: builder failed with exit code 101.
...
error: could not compile `winnow` (lib)
...
process didn't exit successfully: `rustc --crate-name winnow ...` (exit status: 101)
```

### Root cause

`papers` 49.4 depends on the `winnow` Rust crate (version 0.7.13). This crate fails to
compile with the Rust compiler version shipped by nixpkgs 25.11 (rustc 1.91.1). The
incompatibility is upstream: `winnow` 0.7.x requires a newer compiler feature not yet
stabilised in Rust 1.91.1.

### Impact

All desktop-role builds fail completely — every `nixosConfigurations` output whose name
begins with `vexos-desktop-*` is unbuildable.

---

## 3. Proposed Solution

### Strategy

Add `papers` to the **universal** `environment.gnome.excludePackages` list in
`modules/gnome.nix`. This prevents the broken nixpkgs package from being included in the
build closure for **all** roles.

Desktop users continue to receive GNOME Papers functionality via the pre-existing Flatpak
installation (`org.gnome.Papers` is already in `gnomeDesktopOnlyApps` in
`modules/gnome-desktop.nix`). No end-user functionality is lost.

### Files to modify

**File 1: `modules/gnome.nix`**

Location of change: the `environment.gnome.excludePackages` list (around line 193).

Add `papers` to that list, alongside the existing comment for `snapshot`:

```nix
environment.gnome.excludePackages = with pkgs; [
  gnome-photos
  gnome-tour
  gnome-connections
  gnome-weather
  gnome-clocks
  gnome-contacts
  gnome-maps
  gnome-characters
  gnome-user-docs
  yelp
  simple-scan
  epiphany
  geary
  xterm
  gnome-music
  rhythmbox
  totem
  showtime
  gnome-calculator
  gnome-calendar
  snapshot
  papers           # nixpkgs 49.4 fails to build (winnow crate / Rust 1.91.1 incompatibility);
                   # desktop role installs Flatpak org.gnome.Papers instead
];
```

Update the block comment immediately above `environment.gnome.excludePackages` to remove
the note that says `papers` is handled in role-specific modules (it no longer will be
exclusively there).

**Files 2–4: `modules/gnome-htpc.nix`, `modules/gnome-server.nix`, `modules/gnome-stateless.nix`**

Each of these files has a single-entry `environment.gnome.excludePackages` block
containing only `papers`. Since `gnome.nix` will now exclude `papers` universally (and
these files all `import` `gnome.nix`), the duplicate entries are no longer needed.

Remove the entire redundant `environment.gnome.excludePackages` block from each of
these three files:

```nix
# DELETE this block from gnome-htpc.nix / gnome-server.nix / gnome-stateless.nix:
environment.gnome.excludePackages = with pkgs; [
  papers            # Flatpak org.gnome.Papers installed on desktop only
];
```

> **Note:** NixOS merges all `environment.gnome.excludePackages` lists across all imported
> modules, so the duplicate entries are harmless if left in place. However, removing them
> makes each role file cleaner and eliminates the now-misleading comment implying desktop
> is the only role that cares. Removing them is recommended but does not affect
> correctness — the implementation agent may choose to leave them for a minimal-change
> approach.

### Summary of changes

| File | Change |
|---|---|
| `modules/gnome.nix` | Add `papers` to universal `excludePackages` list; update comment |
| `modules/gnome-htpc.nix` | Remove now-redundant `excludePackages` block (recommended) |
| `modules/gnome-server.nix` | Remove now-redundant `excludePackages` block (recommended) |
| `modules/gnome-stateless.nix` | Remove now-redundant `excludePackages` block (recommended) |

**Minimum required change:** only `modules/gnome.nix` must be modified to fix the build.

---

## 4. Architecture Pattern Compliance

This fix follows the **Option B: Common base + role additions** pattern:

- The universal base file (`modules/gnome.nix`) receives a universal exclusion that
  applies to all roles — appropriate because the nixpkgs `papers` package is broken for
  all roles.
- No `lib.mkIf` guard is introduced.
- The desktop role continues to obtain Papers functionality via Flatpak, which is already
  declared in `modules/gnome-desktop.nix` without any conditionals.
- Role selection is expressed entirely through the import list in each
  `configuration-*.nix` file.

---

## 5. Alternative: evince as Replacement

`evince` (the predecessor to GNOME Papers) remains available in nixpkgs 25.11. However:

- The desktop role already installs `org.gnome.Papers` via Flatpak — adding the nixpkgs
  `evince` alongside it would create two document viewers without a clear reason.
- HTPC, server, and stateless roles have never included a document viewer and do not
  need one.
- `evince` builds successfully with the current toolchain, so it is technically a viable
  replacement. If Papers via Flatpak were not already in place, it would be a reasonable
  fallback.

**Recommendation:** Do not add `evince`. The Flatpak Papers installation on the desktop
role is sufficient.

---

## 6. Risks and Mitigations

| Risk | Likelihood | Mitigation |
|---|---|---|
| Papers still pulled in as a transitive dependency of another GNOME package | Very low | `environment.gnome.excludePackages` removes the package from the profile closure; if a remaining package hard-depends on it the build would still fail, but GNOME Papers has no such reverse deps among core apps |
| Flatpak Papers not available on some desktop machines | Low | Flatpak is already installed and the install service runs at first boot; offline machines should pre-populate the Flatpak bundle |
| Removing the role-specific `excludePackages` blocks breaks something | None | NixOS list options are merged; removing a sublist from a merged set cannot cause a breakage |

---

## 7. Implementation Steps

1. Open `modules/gnome.nix`.
2. In the `environment.gnome.excludePackages` list, add `papers` after `snapshot` with the comment above.
3. Update the comment above `environment.gnome.excludePackages` to remove the reference
   to `papers` being handled by role-specific modules.
4. Open `modules/gnome-htpc.nix`, `modules/gnome-server.nix`,
   `modules/gnome-stateless.nix`.
5. Remove the `environment.gnome.excludePackages = with pkgs; [ papers ... ];` block from
   each (it is now superseded by the universal base).
6. Run `nix flake check` to validate.
7. Run `sudo nixos-rebuild dry-build --flake .#vexos-desktop-amd` (and at least one other
   desktop variant) to confirm the build succeeds without `papers`.
