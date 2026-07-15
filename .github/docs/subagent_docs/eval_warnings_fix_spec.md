# Spec: Fix `system` and `sabnzbd.configFile` evaluation warnings

## Current State Analysis

Two evaluation warnings appear when building/evaluating vexos-nix configurations:

```
evaluation warning: 'system' has been renamed to/replaced by 'stdenv.hostPlatform.system'
evaluation warning: `sabnzbd.configFile` is deprecated, consider using `sabnzbd.settings` instead.
```

### Warning 1 — `system`

`flake.nix`'s `mkHost` builder was already migrated to `{ nixpkgs.hostPlatform = system; }`
(see `.github/docs/subagent_docs/nixos_system_deprecation_spec.md` /
`nixos_system_deprecation_review.md` — that fix is confirmed present at
`flake.nix:273` and covers all 30 `nixosConfigurations` built directly from this repo).

The warning persists because `template/etc-nixos-flake.nix` — the per-host
`/etc/nixos/flake.nix` wrapper installed on real machines — was never updated to match.
It still passes the deprecated top-level `system = "x86_64-linux";` argument directly to
`nixpkgs.lib.nixosSystem` in six separate builder functions:

- `_mkVariantWith` (line 148) — used by `mkVariant` (desktop) and `mkStatelessVariant`'s sibling builders
- `mkStatelessVariant` (line 184)
- `mkHtpcVariant` (line 211)
- `mkVanillaVariant` (line 231)
- `mkHeadlessServerVariant` (line 249)
- `mkServerVariant` (line 283)

This is the file installed on the user's actual host (`/etc/nixos/flake.nix`), so it is the
active source of the warning during real `nixos-rebuild` runs, even though the upstream
repo's own `flake.nix` is already clean.

### Warning 2 — `sabnzbd.configFile`

`services.sabnzbd.configFile` (declared in nixpkgs' `sabnzbd.nix` module) defaults to:

```nix
default =
  if lib.versionOlder config.system.stateVersion "26.05" then
    "/var/lib/sabnzbd/sabnzbd.ini"
  else
    null;
```

All `configuration-*.nix` files in this repo pin `system.stateVersion = "25.11"` (must not
change — see CLAUDE.md), so `configFile` resolves to the non-null legacy default, which
trips the module's own warning:

```nix
warnings = lib.optional (cfg.configFile != null) ''
  `sabnzbd.configFile` is deprecated, consider using `sabnzbd.settings` instead. ...
'';
```

`modules/server/arr.nix` (`services.sabnzbd = { enable = true; openFirewall = true; }`)
does not touch `configFile` or `settings` at all, so the legacy default silently applies.

### Addendum — SABnzbd bind address (discovered during live-host follow-up)

After deploying the `configFile = null;` fix, the user reported SABnzbd was still
unreachable from the LAN despite `openFirewall = true`. Live-host inspection
(`sudo ss -tlnp | grep 8080`) showed the running SABnzbd process bound to
`127.0.0.1:8080` — loopback only. `services.sabnzbd.settings.misc.host` (the option that
controls the Web UI bind address in the settings-based config path) defaults to
`"127.0.0.1"`. `openFirewall = true` only opens the port at the firewall; it has no effect
if the process itself never listens on a non-loopback interface. Since `arr.nix` already
declares `openFirewall = true` (signalling intent for off-box reachability), this default
is a functional gap for this config, not just a cosmetic warning.

## Problem Definition

1. `template/etc-nixos-flake.nix` still uses the deprecated `system = "..."` argument to
   `nixosSystem` in 6 places.
2. `modules/server/arr.nix`'s sabnzbd block relies on the deprecated `configFile` default
   instead of setting `configFile = null;` (the settings-based path).
3. Once (2) is fixed, SABnzbd's settings-based default (`settings.misc.host = "127.0.0.1"`)
   still leaves it loopback-only, silently defeating `openFirewall = true`.

## Proposed Solution

### Fix 1 — `template/etc-nixos-flake.nix`

For each of the 6 `nixpkgs.lib.nixosSystem { system = "x86_64-linux"; ... }` call sites,
replace the top-level `system = "x86_64-linux";` line with a
`{ nixpkgs.hostPlatform = "x86_64-linux"; }` module prepended to that builder's `modules`
list — identical pattern to the fix already applied in this repo's own `flake.nix:273`.

### Fix 2 — `modules/server/arr.nix`

Add `configFile = null;` to the `services.sabnzbd` block under
`lib.mkIf cfg.sabnzbd.enable`, so the module falls onto its `settings`-based
(non-deprecated) configuration path. Also set `settings.misc.host = "0.0.0.0";` so the
Web UI actually listens on all interfaces, matching the existing `openFirewall = true`
intent (otherwise the module default of `127.0.0.1` makes the open firewall port
unreachable).

## Implementation Steps

1. `template/etc-nixos-flake.nix`: in each of `_mkVariantWith`, `mkStatelessVariant`,
   `mkHtpcVariant`, `mkVanillaVariant`, `mkHeadlessServerVariant`, `mkServerVariant`,
   remove the `system = "x86_64-linux";` line and prepend
   `{ nixpkgs.hostPlatform = "x86_64-linux"; }` to that function's `modules` list.
2. `modules/server/arr.nix`: add `configFile = null;` inside the
   `services.sabnzbd = { ... }` block (alongside `enable` and `openFirewall`).

## Module Architecture Pattern Compliance

Fix 2 touches `modules/server/arr.nix`, a role-neutral shared service module gated only by
its own `cfg.sabnzbd.enable` option (the standard carve-out for a module's own toggle) —
no new `lib.mkIf` guard by role/display/gaming flag is introduced. Fix 1 is confined to the
template file, not a NixOS module.

## Dependencies

No new external dependencies, no new flake inputs. Context7 not required (internal Nix
module option change only, verified directly against the installed nixpkgs option schema
via the nixos MCP tool).

## Configuration Changes

None to `system.stateVersion` (unchanged, per CLAUDE.md constraint) and none to any flake
input.

## Build/Test Commands (Phase 3)

- `nix flake show --impure` (repo `flake.nix` — confirms no regression there)
- `sudo nixos-rebuild dry-build --flake .#vexos-desktop-amd`
- `sudo nixos-rebuild dry-build --flake .#vexos-desktop-nvidia`
- `sudo nixos-rebuild dry-build --flake .#vexos-desktop-vm`
- `sudo nixos-rebuild dry-build --flake .#vexos-server-amd` and
  `--flake .#vexos-headless-server-amd` (Fix 2 touches a server module)
- `template/etc-nixos-flake.nix` is not part of `nixosConfigurations` in this repo (it is a
  standalone template consumed by real hosts) and cannot be dry-built from here; validate
  it with `nix eval --impure --expr` syntax-check or manual review only.

## Risks and Mitigations

| Risk | Mitigation |
|------|-----------|
| `configFile = null;` changes sabnzbd's on-disk config path unexpectedly | `settings` defaults produce a working config; `allowConfigWrite` behavior is unaffected since it's a separate option |
| Template file drifts from `flake.nix` again in future | Not solved by this fix — flagged as tech debt only, no scope creep here |
| `nixpkgs.hostPlatform` module ordering matters in template builders | Prepend (same position as the already-approved `flake.nix` fix) so it applies before any other module reads it |
