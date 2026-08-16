# Proxmox VE console "Module is unknown" — glibc/util-linux mismatch fix

## Current state analysis

`modules/server/proxmox.nix` enables Proxmox VE via `services.proxmox-ve.enable = true`,
which comes from the vendored `proxmox-nixos` flake input (`inputs.proxmox-nixos.nixosModules.proxmox-ve`,
wired into `baseModules` at `flake.nix:150`). `proxmox-nixos` pins its **own** `nixpkgs-stable`
input (currently `nixos-25.11`), independent of this repo's root `nixpkgs` (`nixos-26.05`) —
by explicit design (`flake.nix:38-40` forbids adding `.follows` for this input, per upstream
requirement).

Diagnosed live on host `vexmox` (generation 19, 2026-08-15):

- Clicking Shell/Console in the Proxmox web UI opens a session that runs `login -f root`
  (via `vncterm`/`termproxy`), which fails with `Module is unknown`.
- `journalctl -u pvedaemon` shows the real underlying error:
  ```
  PAM unable to dlopen(.../util-linux-2.42.2-lastlog/lib/security/pam_lastlog2.so):
    .../glibc-2.40-66/lib/libc.so.6: version `GLIBC_ABI_DT_X86_64_PLT' not found
    (required by .../glibc-2.42-67/lib/libm.so.6)
  ```
- `nix why-depends /run/current-system /nix/store/...-util-linux-2.41.3-bin` confirmed the
  dependency chain:
  `nixos-system-vexmox-26.05 → system-path → proxmox-ve-9.1.6 → util-linux-2.41.3-bin`

## Problem definition

`proxmox-ve` (built against proxmox-nixos's own `nixpkgs-stable` = `nixos-25.11`) depends on
its pin's `util-linux` (2.41.3, linked against glibc 2.40-66). proxmox-nixos's own
`modules/proxmox-ve/default.nix` does `environment.systemPackages = [ cfg.package ];`,
pulling that whole dependency closure — including its older `util-linux` — into the system's
`environment.systemPackages`.

NixOS merges all `environment.systemPackages` into one `/run/current-system/sw` tree. Two
different `util-linux` builds now coexist in the closure: the root nixpkgs one (2.42.2, glibc
2.42-67, used everywhere else including the PAM modules referenced by the freshly-generated
`/etc/pam.d/login`) and proxmox-ve's bundled one (2.41.3, glibc 2.40-66). Priority resolution
in the `sw/bin` merge picked the older util-linux's `login` binary to win the `login` PATH
entry. When that binary (linked against glibc 2.40) tries to dlopen the newer
`pam_lastlog2.so`/`pam_systemd.so` (built against glibc 2.42), the dynamic linker reuses the
already-loaded (older) `libc.so.6`, which lacks the symbol the newer modules need → dlopen
fails → PAM prints "Module is unknown".

This is a proxmox-nixos packaging gap (upstream doesn't isolate `proxmox-ve`'s dependency
closure from `environment.systemPackages`, and doesn't follow root nixpkgs), not a bug in this
repo's existing configuration — but it can be worked around locally.

## Proposed solution architecture

Use `lib.hiPrio` on the root nixpkgs `util-linux`, added explicitly to
`environment.systemPackages` inside `modules/server/proxmox.nix`, so it wins the
`sw/bin/login` priority conflict against the older util-linux bundled by `proxmox-ve`. This
guarantees `login` (and all other util-linux binaries reachable via PATH) resolves to the
version matching the root nixpkgs's PAM modules and glibc.

This is scoped entirely inside the module's existing `lib.mkIf cfg.enable` block — it only
applies on hosts that actually enable `vexos.server.proxmox`, consistent with the carve-out
in this repo's Module Architecture Pattern (a module gating its own config by an option it
declares itself is not role-smuggling).

## Implementation steps

1. `modules/server/proxmox.nix`:
   - Add `pkgs` to the module's function arguments (`{ config, lib, pkgs, ... }:`).
   - Inside `config = lib.mkIf cfg.enable { ... }`, add:
     ```nix
     environment.systemPackages = [ (lib.hiPrio pkgs.util-linux) ];
     ```
   - Add a short comment explaining why (proxmox-ve bundles an older util-linux from its own
     nixpkgs pin, which otherwise wins the `/bin/login` priority conflict and breaks PAM for
     the web console's Shell button).

No other files need to change. No new dependencies are introduced (`pkgs.util-linux` is
already part of nixpkgs; no Context7 lookup required — this is an internal NixOS
configuration change with no new external library).

## Configuration changes

None beyond the one-line addition above. No new `vexos.*` options needed — this is unconditional
behavior for any host with `vexos.server.proxmox.enable = true`.

## Risks and mitigations

- **Risk**: `lib.hiPrio` could theoretically cause a different, unrelated collision if some
  other package also ships a higher-priority binary of the same name.
  **Mitigation**: `hiPrio` only affects priority *relative to other systemPackages* entries
  for identically-named files; it does not affect anything outside the `util-linux` binary
  set, and this repo does not otherwise override `util-linux`'s priority elsewhere (confirmed
  via repo-wide grep — only plain `pkgs.util-linux` references exist, in unrelated
  service-`path` lists in `modules/boot-discovery.nix`, `modules/zfs-server.nix`,
  `modules/remote-desktop.nix`, none of which touch `environment.systemPackages` priority).
- **Risk**: Doesn't fix the root packaging issue upstream in `proxmox-nixos` — future
  `proxmox-ve` version bumps could reintroduce a similar mismatch if the bundled util-linux
  version drifts further from root nixpkgs's.
  **Mitigation**: Out of scope for this repo; worth an upstream issue on
  `SaumonNet/proxmox-nixos`, noted in the commit message but not filed automatically.
- **Build risk**: None — `pkgs.util-linux` is a stable, always-present nixpkgs attribute;
  `lib.hiPrio` is a standard nixpkgs library function with no version sensitivity.
