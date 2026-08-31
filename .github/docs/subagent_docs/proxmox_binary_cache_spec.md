# proxmox_binary_cache — Specification

## Current State Analysis

`modules/server/proxmox.nix` enables `services.proxmox-ve` from the
`SaumonNet/proxmox-nixos` flake input. The `proxmox-nixos` input intentionally does
**not** follow the outer `nixpkgs` (see comment at `flake.nix:45-48`); it carries its
own `nixpkgs-stable` pin and builds a large set of Perl/Proxmox packages.

`proxmox-nixos` publishes a public binary cache for these prebuilt closures:

- substituter: `https://cache.saumon.network/proxmox-nixos`
- public key:  `proxmox-nixos:D9RYSWpQQC/msZUWphOY2I5RLH5Dd6yQcaHIuug7dWM=`

This cache is currently referenced **only in comments** — `modules/server/proxmox.nix:5-7`
and `justfile:3124-3128`. It is not present in:

- `nix.settings.substituters` / `nix.settings.trusted-public-keys`
  (`modules/nix.nix:144-152` — only `cache.nixos.org` + optional Attic/Harmonia)
- any `nixConfig` block in `flake.nix` (there is none)

Consequence: every host with `vexos.server.proxmox.enable = true` builds `proxmox-ve`
and its entire Perl dependency tree **from source**.

## Problem Definition

`nixos-rebuild boot --flake /etc/nixos#vexos-server-nvidia-legacy580` (VexOS installer,
2026-08-31) fails building `proxmox-ve-9.2.10` from source. Root failure:

```
error: Cannot build '/nix/store/1d3ma7f0…-perl5.42.0-AnyEvent-HTTP-2.25.drv'.
```

All higher failures (`pve-access-control`, `pve-storage`, `pve-ha-manager`,
`pve-qemu-server`, `proxmox-ve`, `system-path`, `nixos-system-vexos-26.05`) are cascade
failures from that one leaf.

The `proxmox-nixos` pin was advanced to rev `89bf7bb1` (lastModified 2026-08-29) by the
weekly input bump in commit `bd37c13`. The source build of that revision is currently
broken; the SaumonNet cache has working prebuilt closures for it.

## Proposed Solution Architecture

Wire the SaumonNet binary cache into Nix configuration at two levels:

1. **Flake-level `nixConfig`** (`flake.nix`) — makes the cache available during
   `nixos-rebuild` / `nix build` against the flake **before any system configuration
   has been applied** (the install-time / recovery path). Nix behaviour for flake
   `nixConfig`, verified empirically in this environment (Nix 2.34.1):
   - **Interactive** run (e.g. the operator re-running the failed
     `sudo nixos-rebuild boot …` by hand): Nix prompts
     `do you want to allow configuration setting 'extra-substituters' …? (y/N)` —
     answering `y` applies the cache. This is the primary recovery path.
   - **Non-interactive** run (a fully scripted installer with no TTY): the setting is
     ignored with a warning unless the invocation passes `--accept-flake-config` or the
     host's `nix.conf` has `accept-flake-config = true`. Being a trusted user is **not**
     sufficient on its own.
   In every case the fallback is a source build (current behaviour) — never a hard
   failure. The block is still worth adding: it makes the interactive recovery a single
   `y`, and a `--accept-flake-config` in any installer immediately benefits.

2. **System-level `nix.settings`** — persists the cache on the running system for all
   later rebuilds and non-flake Nix operations. Scoped to the two roles that actually
   pull Proxmox packages (`server`, `headless-server`) via a new Option-B addition
   module, so non-server roles do not pay per-path substituter query latency for a
   cache that never has their paths.

`nix.settings.substituters` and `nix.settings.trusted-public-keys` are `listOf str`
options that merge by concatenation across modules, so the new module appends without
clobbering `modules/nix.nix`.

## Implementation Steps (Module Architecture Pattern — Option B)

### 1. `flake.nix` — add top-level `nixConfig`

Insert a `nixConfig` block (sibling of `inputs` / `outputs`), using additive
`extra-` keys so `cache.nixos.org` and daemon defaults are preserved:

```nix
  nixConfig = {
    extra-substituters = [ "https://cache.saumon.network/proxmox-nixos" ];
    extra-trusted-public-keys = [
      "proxmox-nixos:D9RYSWpQQC/msZUWphOY2I5RLH5Dd6yQcaHIuug7dWM="
    ];
  };
```

Preceded by a comment explaining it exists so the installer's first
`nixos-rebuild boot` can fetch prebuilt Proxmox closures instead of building the
Perl tree from source.

### 2. New file `modules/nix-proxmox-cache.nix` — universal-shaped addition, no guards

```nix
# modules/nix-proxmox-cache.nix
# SaumonNet proxmox-nixos binary cache. Imported only by configuration-server.nix
# and configuration-headless-server.nix — the roles that build Proxmox packages.
# proxmox-nixos does not follow this flake's nixpkgs, so proxmox-ve and its large
# Perl dependency tree would otherwise be compiled from source on every rebuild.
{ ... }:
{
  nix.settings = {
    substituters       = [ "https://cache.saumon.network/proxmox-nixos" ];
    trusted-public-keys = [ "proxmox-nixos:D9RYSWpQQC/msZUWphOY2I5RLH5Dd6yQcaHIuug7dWM=" ];
  };
}
```

No `lib.mkIf`, no role/flag conditionals — the file is imported only where it applies,
per Option B. It is not gated on `vexos.server.proxmox.enable`: an unused substituter
is harmless, and scoping is already expressed by the import list.

### 3. `configuration-server.nix` — add import

Add `./modules/nix-proxmox-cache.nix` to the `imports` list.

### 4. `configuration-headless-server.nix` — add import

Add `./modules/nix-proxmox-cache.nix` to the `imports` list.

### 5. Update stale comments

- `modules/server/proxmox.nix:5-7` — change the "Binary cache (avoids rebuilding …)"
  comment from an instruction the reader must act on to a pointer:
  "Binary cache is wired in via modules/nix-proxmox-cache.nix (system) and
  flake.nix nixConfig (install time)."
- Leave `justfile` text output as-is (user-facing informational; still accurate).

## Dependencies

No new flake inputs. No new packages. Context7 not applicable — this is Nix daemon
configuration, not an external versioned library API. The cache URL and Ed25519 key
are published by the existing `proxmox-nixos` input and already recorded verbatim in
the repo's own comments.

## Configuration Changes

| File | Change |
|------|--------|
| `flake.nix` | new `nixConfig` block (2 `extra-` keys) |
| `modules/nix-proxmox-cache.nix` | new file — appends 1 substituter + 1 key |
| `configuration-server.nix` | +1 import |
| `configuration-headless-server.nix` | +1 import |
| `modules/server/proxmox.nix` | comment refresh only |

No change to `system.stateVersion`. No change to `hardware-configuration.nix`
handling. No new flake input, so the `follows` policy is not triggered.

## Risks and Mitigations

| Risk | Mitigation |
|------|------------|
| SaumonNet cache lacks the exact pinned rev's closures | Build falls back to source (current behaviour); user can `--override-input proxmox-nixos <older-rev>` or wait for upstream fix. Not a regression. |
| `nixConfig` prompts a non-trusted interactive user for acceptance | Expected Nix behaviour; declining just falls back to source. Installer runs as root (trusted) so no prompt there. |
| Extra substituter adds latency to server rebuilds | Only the two Proxmox-bearing roles import it; `cache.nixos.org` is still queried first. |
| Third-party cache trust | Same key already documented in-repo; single-operator homelab context (see `modules/nix.nix:131-138`); key pins signature verification. |
| Immediate unblock for the failing install | Out of band: `sudo nixos-rebuild boot --flake /etc/nixos#vexos-server-nvidia-legacy580 --option extra-substituters "https://cache.saumon.network/proxmox-nixos" --option extra-trusted-public-keys "proxmox-nixos:D9RYSWpQQC/msZUWphOY2I5RLH5Dd6yQcaHIuug7dWM="` |

## Verification Goals

1. `nix flake show --impure` still lists all 30 outputs → flake structure valid.
2. `nix eval --impure` (or `dry-build`) of `vexos-server-nvidia-legacy580` and
   `vexos-headless-server-amd` evaluates with no attribute/type errors.
3. `nix config show` on a built server closure lists the SaumonNet substituter.
4. `git ls-files hardware-configuration.nix` empty; `system.stateVersion` unchanged.
5. `bash scripts/preflight.sh` exits 0.
