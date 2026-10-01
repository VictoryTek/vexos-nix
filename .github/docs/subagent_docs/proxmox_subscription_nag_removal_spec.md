# Proxmox VE Subscription Nag Removal — Spec

## Current State Analysis

`modules/server/proxmox.nix` enables Proxmox VE via SaumonNet's `proxmox-nixos` flake
input (`inputs.proxmox-nixos`, pinned in `flake.lock` at rev `fc773dcf59bf188fcc806c78af635e5917ca2983`).
`services.proxmox-ve.package` defaults (lazily, via `mkPackageOption`) to `pkgs.proxmox-ve`,
a `buildEnv` wrapper around `pve-manager` and friends, all built from source and served
from `cache.saumon.network` (wired in via `modules/nix-proxmox-cache.nix`).

Unlike the Debian ISO install this project (and the upstream community-scripts
`post-pve-install.sh`) was modeled on, there is no apt package management here —
Proxmox's "No valid subscription" web-UI nag popup (triggered by a client-side check in
`proxmoxlib.js`) has never been addressed on this stack.

## Problem Definition

The Proxmox VE web UI displays a dismissible-but-recurring "No valid subscription" nag
dialog, driven entirely by a client-side JS check in `proxmoxlib.js`
(part of the `proxmox-widget-toolkit` package). This is cosmetic only — it has no
licensing or functional effect — but is undesired on a self-hosted/no-subscription setup.

## Research — Package Graph Trace (6 sources, all at the pinned `proxmox-nixos` rev)

1. `https://raw.githubusercontent.com/community-scripts/ProxmoxVE/main/tools/pve/post-pve-install.sh`
   — reference patch: `sed -i -e "/data\.status/ s/!//" -e "/data\.status/ s/active/NoMoreNagging/" proxmoxlib.js`.
   Flips `data.status.toLowerCase() !== 'active'` into a check that's always false, so the
   nag dialog's branch never executes. This exact one-liner has been the standard
   community fix for years across PVE 8.x/9.x.
2. `pkgs/proxmox-widget-toolkit/default.nix` — confirms `proxmoxlib.js` is installed to
   `$out/share/javascript/proxmox-widget-toolkit/proxmoxlib.js` inside the
   `proxmox-widget-toolkit` derivation's own output.
3. `pkgs/pve-manager/default.nix` — takes `proxmox-widget-toolkit` as an explicit
   `callPackage` argument; passes `WIDGETKIT=${proxmox-widget-toolkit}/share/javascript/proxmox-widget-toolkit/proxmoxlib.js`
   as a `makeFlags` entry (build-time only — does not copy the file).
4. `pkgs/pve-http-server/default.nix` — the package that actually serves static JS at
   runtime. Its `postFixup` does **not** copy `proxmoxlib.js`; it symlinks:
   `ln -s ${proxmox-widget-toolkit}/share/javascript/proxmox-widget-toolkit $out/share/javascript`.
   This confirms the browser-served bytes always physically resolve back to
   `proxmox-widget-toolkit`'s own immutable store path, regardless of which package
   serves the request.
5. `pkgs/proxmox-ve/default.nix` — the `buildEnv` meta-package `services.proxmox-ve.package`
   defaults to; takes `pve-manager` as an argument and does `pve-manager.override {...}`
   internally, confirming override-composition would work *if* taken (see rejected
   alternative below) — but is not the path chosen.
6. `pkgs/default.nix` — confirms `proxmox-widget-toolkit` and `pve-manager` are wired
   together via a self-referential `let ours = { ... }; in ours` pattern inside the
   `proxmox-nixos` overlay (`overlays = _: _: (import ./pkgs { inherit pkgs; })`), which
   discards `final`/`prev` — i.e. overriding `pkgs.proxmox-widget-toolkit` from *our* flake
   would not propagate into `pve-manager`'s build without *also* separately overriding
   `pve-manager` (and `proxmox-ve`) to take the patched input, forcing a full `pve-manager`
   rebuild and defeating `cache.saumon.network` for that path.

## Rejected Alternative: Layered `.override`

```nix
pkgs.proxmox-ve.override {
  pve-manager = pkgs.pve-manager.override {
    proxmox-widget-toolkit = pkgs.proxmox-widget-toolkit.overrideAttrs (...);
  };
}
```

Works in principle (confirmed via source #5/#6) but changes `pve-manager`'s input hash,
forcing a full from-source rebuild of the Perl-heavy `pve-manager` tree on every affected
host — a real, recurring cost for a cosmetic fix. Rejected in favor of the serving-layer
patch below.

## Proposed Solution

Patch only the single served file, at the layer where it's actually read from disk, using
a systemd per-service bind mount — no `proxmox-widget-toolkit`/`pve-manager`/`pve-http-server`
override, so all three stay on the binary cache untouched:

```nix
# modules/server/proxmox.nix, inside the existing `config = lib.mkIf cfg.enable { ... }` block
let
  patchedProxmoxLib = pkgs.runCommand "proxmoxlib-no-nag.js" { } ''
    sed -e "/data\.status/ s/!//" -e "/data\.status/ s/active/NoMoreNagging/" \
      ${pkgs.proxmox-widget-toolkit}/share/javascript/proxmox-widget-toolkit/proxmoxlib.js > $out
  '';
in
systemd.services.pveproxy.serviceConfig.BindReadOnlyPaths = [
  "${patchedProxmoxLib}:${pkgs.proxmox-widget-toolkit}/share/javascript/proxmox-widget-toolkit/proxmoxlib.js"
];
```

- `patchedProxmoxLib` is a trivial `runCommand` (single `sed` over one small JS file) —
  builds locally in under a second; nothing to substitute, nothing expensive.
- `BindReadOnlyPaths` is a standard NixOS/systemd per-unit option — it bind-mounts the
  patched file over the real path, scoped to `pveproxy`'s own private mount namespace
  only. The global Nix store view, and every other process on the system, is unaffected.
- Tracks flake updates automatically: when `proxmox-nixos` is bumped,
  `pkgs.proxmox-widget-toolkit`'s store path changes, Nix re-evaluates
  `patchedProxmoxLib` against the new path with no manual re-patch step (unlike the
  community script's mutable apt post-invoke hook).

## Implementation Steps (Module Architecture Pattern — Option B)

This is not a role-gated addition — it applies universally whenever Proxmox is enabled,
via the option (`vexos.server.proxmox.enable`) the module *already* declares and gates on.
Per the documented carve-out (`lib.mkIf` guarding a block by an option the same module
declares is standard, not role-smuggling), this is added directly inside the existing
`config = lib.mkIf cfg.enable { ... }` block in `modules/server/proxmox.nix` — no new
file, no new option, no configurability beyond what was asked for (unconditional
whenever Proxmox VE is enabled).

1. Add the `patchedProxmoxLib` derivation and the `systemd.services.pveproxy.serviceConfig.BindReadOnlyPaths`
   entry inside `modules/server/proxmox.nix`'s existing `config` block.

## Dependencies

None new. Uses only `pkgs.runCommand` (stdenv, already available) and
`pkgs.proxmox-widget-toolkit` (already pulled in transitively via the existing
`proxmox-nixos` overlay). No Context7 lookup required (internal-only change, no new
external library/dependency, per the Dependency Policy's exclusion list).

## Configuration Changes

None beyond the module edit above. No new `vexos.*` options.

## Risks and Mitigations

- **Risk:** `pveproxy` might read/cache the file's bytes into memory at process start in
  a way bind-mounting before start wouldn't affect differently than before — low risk,
  since `BindReadOnlyPaths` sets up the mount namespace before the unit's main process
  execs, so the very first read already sees the patched file either way.
- **Risk:** Upstream `proxmoxlib.js` could change the `data.status` check's structure in
  a future `proxmox-widget-toolkit` bump, silently no-op'ing the sed. Mitigation: this is
  the same risk the community script itself carries across PVE 8.x/9.x; not a regression
  introduced here. Acceptable given the file is small and the worst case is simply "nag
  comes back," not a build or boot failure.
- **Risk:** `systemd.services.pveproxy` is defined by the `proxmox-nixos` NixOS module,
  not by this project — confirm the unit name and that `serviceConfig` merges correctly
  (NixOS `systemd.services.<name>` options merge by default; no conflict expected).
- Verified: not applicable to the mobile GUI (`pve-yew-mobile-gui`'s separate nag removal
  in the community script) — out of scope; not requested, not implemented.
