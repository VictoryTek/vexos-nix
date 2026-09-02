# Spec — Decentralized, self-registering backup path registration

## 1. Current state

`modules/server/backup.nix` holds a hardcoded `servicePaths` let-binding: a
51-entry attrset mapping service name → list of paths. `enabledServicePaths`
filters it by `config.vexos.server.<name>.enable`.

This is a second, disconnected place that must be kept in sync with every
module file under `modules/server/`. Verified gaps caused by that split:

| Service | Container state | `servicePaths` entry | Status |
|---|---|---|---|
| `nginx-proxy-manager` | named volumes `npm-data:/data`, `npm-letsencrypt:/etc/letsencrypt` | **absent** | zero backup coverage (certs + proxy rules) |
| `arcane` | named volume `arcane-data:/app/data` | **absent** | zero backup coverage |
| `traefik` | `services.traefik.dataDir` = `/var/lib/traefik` (acme.json) | **absent** | zero backup coverage (ACME certs) |

Two further correctness questions found but deliberately **out of scope** for
this structural change (see §6):

| Service | Listed path | Actual state location |
|---|---|---|
| `homepage` | `/var/lib/homepage` | named volume `homepage-config:/app/config` |
| `stirling-pdf` | `[ ]` | named volumes `stirling-pdf-data`, `stirling-pdf-config` |

## 2. Problem

Backup wiring is opt-in-by-memory. Nothing fails when a module author forgets
it, so a module can be fully functional and completely unbacked-up.

## 3. Proposed solution

Invert the registration: each module declares its own backup paths, and
`backup.nix` asserts that every enabled service has declared something.

### 3.1 New option (declared in `backup.nix`)

```nix
options.vexos.server.backup.servicePaths = lib.mkOption {
  type    = lib.types.attrsOf (lib.types.listOf lib.types.str);
  default = { };
};
```

Declared outside the `config = lib.mkIf cfg.enable` block so modules can set it
regardless of whether backups are enabled on a given host. `attrsOf` merges
definitions across modules natively.

### 3.2 Consumption

```nix
enabledServicePaths = lib.flatten (
  lib.mapAttrsToList
    (name: paths: lib.optionals (config.vexos.server.${name}.enable or false) paths)
    cfg.servicePaths
);
```

Identical filtering to today. The `or false` guard keeps non-service members of
the `vexos.server` tree (`storage`, which has no `.enable`) harmless.

### 3.3 Build-time assertion

Placed **outside** `lib.mkIf cfg.enable` — the guarantee is "every service
module declares its backup intent", which must hold on hosts that have not
enabled restic too, otherwise the guard is only active where it is least needed.

```nix
unregistered = lib.filter
  (name: (config.vexos.server.${name}.enable or false)
         && !(cfg.servicePaths ? ${name})
         && !(lib.elem name noBackupNeeded))
  (builtins.attrNames config.vexos.server);
```

`noBackupNeeded` is an explicit in-file list, each entry commented with why.

### 3.4 `noBackupNeeded` classification

Infrastructure / not a data service: `backup`, `docker`, `podman`, `proxy`
(Caddy vhost generator, no state of its own), `nas` (umbrella).

Stateless or derived-state only: `cockpit`, `code-server`, `dozzle`, `netdata`,
`kiji-proxy`, `stirling-pdf`, `searxng` (declarative config), `unbound`
(regenerable trust anchor), `nginx` (cache/logs; certs live in `/var/lib/acme`),
`fluent-bit` (log-cursor db only), `kernelBuilder` (GC roots for derived build
artifacts), `alertmanager` (transient silences/nflog).

Deliberately excluded, pre-existing decision carried forward: `syncthing` — its
`dataDir` is the entire user home directory; auto-including it would make
"enable syncthing" silently mean "back up the whole home directory". Documented
in the current file; preserved as a `noBackupNeeded` entry with the same
rationale, and reachable via `extraPaths`.

`vexos.server.storage.{mergerfs,snapraid}` is nested one level deeper and has no
`vexos.server.storage.enable`, so the assertion does not reach it. Noted in the
Part 4 audit rather than forced into this mechanism.

### 3.5 Migration

Every module currently in the map gains, inside its own
`config = lib.mkIf cfg.enable { ... }` block:

```nix
vexos.server.backup.servicePaths.<name> = [ ... ];
```

Path values are carried over **verbatim**. Where the old map referenced
`config.vexos.server.<name>.<opt>`, the in-module form uses the identical
`cfg.<opt>` reference. The seven `[ ]` entries (`cockpit`, `code-server`,
`dozzle`, `kiji-proxy`, `nas`, `netdata`, `stirling-pdf`) become
`noBackupNeeded` members rather than empty registrations.

Three modules gain a **new** entry (the gaps in §1). Adding a path is the safe
direction — the failure mode of over-inclusion is wasted repo space; the failure
mode of omission is data loss. All three are called out for user confirmation.

`arr.nix`, `cockpit.nix` and `nas.nix` use a top-level `lib.mkMerge`; only
`arr.nix` needs a registration, which goes in its first `lib.mkIf cfg.enable`
block. All other modules use the plain `config = lib.mkIf cfg.enable {` shape.

### 3.6 Deletion

The `servicePaths` let-binding is removed from `backup.nix` once every module
self-registers.

## 4. Dependencies

None. No new flake inputs, no external libraries — Context7 not applicable
(internal options-level refactor, no new dependency).

## 5. Risks and mitigations

| Risk | Mitigation |
|---|---|
| Unconditional assertion breaks an existing host config | `noBackupNeeded` enumerates every currently-enable-able service; classification done exhaustively over `modules/server/*.nix`, not sampled |
| Infinite recursion reading `config.vexos.server` from within a module declaring options under it | `builtins.attrNames` forces only the option-tree structure, not values; `.enable or false` forces one leaf per service |
| Silent behaviour change to a running service | Change is confined to `options.vexos.server.backup.servicePaths` definitions and assertions; no container, port, volume, or service definition is touched |
| Named-volume paths differ between Docker and Podman backends | Backend-conditional path expression, matching the existing `uptime-kuma` precedent |

## 6. Explicitly out of scope

Correcting `homepage`'s and `stirling-pdf`'s path values. Both are pre-existing
correctness questions, not part of this structural move; raised for the user in
the Part 4 audit.

## 7. Validation

`nixos-rebuild dry-build` requires a NixOS host and is unavailable on this
Windows workstation (no NixOS, no `/etc/nixos/hardware-configuration.nix`).
Validation performed via WSL (Nix 2.34.1): `nix flake show --impure` for
structure, and `nix eval --impure` against the module set for evaluation of the
new option and assertion. `nixos-rebuild dry-build` must be run by the user on
the target host before switching.
