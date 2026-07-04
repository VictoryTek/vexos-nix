# H-19 — Builder-machine `/etc/nixos` state leaks into flake outputs

Status: Phase 1 (Research & Specification)
Source: MASTER_PLAN ARCH 1.1 · `flake.nix:89-99` (read in full — `flake.nix:1-422`, plus
`template/etc-nixos-flake.nix` read in full for the consumer side)

## Current State

`flake.nix` defines three "optional host file" modules using impure
`builtins.pathExists` against absolute `/etc/nixos/*` paths:

```nix
serverServicesModule = let path = /etc/nixos/server-services.nix; in
  if builtins.pathExists path then [ path ] else [];
featuresModule = let path = /etc/nixos/features.nix; in ...
statelessUserOverrideModule = let path = /etc/nixos/stateless-user-override.nix; in ...
```

These feed into the shared `roles.<role>.extraModules` table (`flake.nix:139-184`),
which is consumed by **both** `mkHost` (→ `nixosConfigurations.*`) and — since H-18 —
`mkBaseModule` (→ `nixosModules.*Base`).

Separately, `template/etc-nixos-flake.nix` (the actual per-host thin wrapper that real
deployed machines use, verified by reading it in full) **already implements the
identical check itself**, using paths relative to its own location
(`./server-services.nix`, `./features.nix`, `./stateless-user-override.nix` —
unambiguous, since that file always lives at `/etc/nixos/flake.nix`):
`flake.nix:138-139` (features), `:192-193` (stateless user override), `:254-255` and
`:289-290` (server-services, in both `mkHeadlessServerVariant` and `mkServerVariant`).

## Problem Definition

Two distinct consumers of this "optional host file" pattern, only one of which should
actually be impure:

- **`mkHost`** (`nixosConfigurations.vexos-server-amd`, etc.) is used directly for real
  deployment when a developer runs `just switch`/`just build` from a plain repo
  checkout (`justfile:_resolve-flake-dir` falls back to `$HOME/Projects/vexos-nix`) —
  `nix` genuinely runs on the target machine, evaluating a flake meant to represent that
  same machine. Reading `/etc/nixos/server-services.nix` here is correct and
  intentional, exactly analogous to what the thin wrapper does for itself.
- **`mkBaseModule`** (`nixosModules.*Base`) is consumed *by* `template/etc-nixos-flake.nix`,
  which already does its own equivalent, correctly-scoped check. Baking the same impure
  check into `nixosModules.*Base` itself is pure redundancy — on a real deployed host
  using the thin wrapper, both checks run on the same machine against the same absolute
  path and NixOS's module system silently dedups the resulting identical import, so
  there's no visible bug on that path today. But it means `nixosModules.*Base` is not a
  self-contained, host-state-independent module the way its own architecture intends —
  evaluating it (e.g. structurally, or from an unrelated machine) is silently influenced
  by whatever happens to be sitting in that machine's `/etc/nixos`, which is exactly the
  "builder-machine state leaks into flake outputs" problem this item names.

`featuresModule` has the identical shape and the identical redundancy against
`template/etc-nixos-flake.nix`'s own `hasFeatures` check, even though the MASTER_PLAN
wording only names `serverServicesModule`/`statelessUserOverrideModule` explicitly.
Fixing the two named ones while leaving `featuresModule` with the same bug would be an
inconsistent half-fix reviewers would flag immediately, so this spec folds it in too —
same defect, same fix, same file already has the corresponding local check.

## Proposed Solution

Split `roles.<role>.extraModules` into two fields:

- `extraModules` — kept for genuinely shared, pure modules only. Today that's just
  `impermanence.nixosModules.impermanence` for the `stateless` role (a real flake input
  module, not a filesystem check).
- `hostLocalModules` (new) — the three impure `/etc/nixos/*` checks, per role exactly as
  today (`featuresModule` for desktop/htpc/server, `serverServicesModule` for
  server/headless-server, `statelessUserOverrideModule` for stateless).

`mkHost` includes **both** — `r.extraModules ++ r.hostLocalModules` — in the same
position `r.extraModules` occupies today, preserving its exact real-deployment behavior
(confirmed: this results in byte-identical `.drv` output, see Build Validation below).

`mkBaseModule` includes **only** `r.baseModules ++ r.extraModules` — dropping
`hostLocalModules` entirely, since `template/etc-nixos-flake.nix` already supplies the
equivalent local, relative-path check when it consumes `nixosModules.*Base`. This has no
behavioral effect on real thin-wrapper-deployed hosts (same file, same machine, same
result either way) — it only removes the redundant internal check, making
`nixosModules.*Base` itself pure/host-state-independent.

## Implementation Steps

1. `flake.nix` — add `hostLocalModules` field to each `roles.<role>` entry, moving
   `featuresModule`/`serverServicesModule`/`statelessUserOverrideModule` there from
   `extraModules`.
2. `flake.nix` — `mkHost`: change `r.extraModules` reference to
   `r.extraModules ++ r.hostLocalModules`.
3. `flake.nix` — `mkBaseModule`: leave its `imports` list as `roles.${role}.baseModules
   ++ roles.${role}.extraModules` (unchanged from the H-18 refactor — `hostLocalModules`
   is simply never referenced here).
4. Update the doc comments on `serverServicesModule`/`featuresModule`/
   `statelessUserOverrideModule` and the `roles` table to explain the new field and why
   it's `mkHost`-only.

## Configuration Changes

None to `flake.nix` inputs. No new dependencies.

## Risks and Mitigations

- **`mkHost` behavior must not change** — verified via `.drv` hash comparison before/after
  (same technique used for the H-18 review), since `hostLocalModules` occupies the exact
  same position in the module list that these three modules already held.
- **`mkBaseModule`/real deployed hosts must not change** — the removed check is
  redundant with `template/etc-nixos-flake.nix`'s own equivalent, already-correct local
  check; confirmed by reading that file in full rather than assuming.
- **CI evaluation of all 30 `nixosConfigurations`** still relies on `serverServicesModule`
  etc. resolving to `[]` on the CI runner (which has no `/etc/nixos/server-services.nix`)
  — unchanged by this fix, since `mkHost` still includes `hostLocalModules`.
