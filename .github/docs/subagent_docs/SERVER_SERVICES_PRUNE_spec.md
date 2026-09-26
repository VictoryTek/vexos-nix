# SERVER_SERVICES_PRUNE — Specification

Phase 1 output. Feature: tolerate and clean up entries in the host-owned
`/etc/nixos/server-services.nix` that name a server service which no longer
exists in vexos-nix, without maintaining any list of removed services.

---

## 1. Current State Analysis

### 1.1 How host configuration reaches a running host

`/etc/nixos/flake.nix` (from `template/etc-nixos-flake.nix`) is a thin wrapper
written once at install time. It imports the repo's modules via the `vexos-nix`
flake input, plus a set of **host-owned side-files** that are never resynced:

| File | Owner | Written by |
|------|-------|-----------|
| `hardware-configuration.nix` | host | `nixos-generate-config` |
| `host.nix` (ZFS hostId) | host | `scripts/install.sh` |
| `hostname.nix` | host | `just set-hostname` |
| `bootloader.nix`, `hardware-local.nix`, `vm-platform.nix`, `user-override.nix` | host | installer |
| `features.nix` | host | `just enable-feature` |
| `storage-pool.nix`, `storage-remote.nix`, `zfs-pools.nix` | host | storage recipes |
| `kernel-install-override.nix` | host | installer / `vexos-update` |
| `server-services.nix` | host | `just enable <service>` |
| `flake.nix` (the wrapper itself) | host | installer, one time |

Everything else — all of `modules/`, `pkgs/`, `home/`, the justfile — is pulled
fresh from GitHub on every update. Repo changes to service modules already
reach hosts correctly. Only the table above is exempt, by design: these hold
per-machine facts and per-machine choices.

`server-services.nix` is imported by `mkServerVariant`
(`template/etc-nixos-flake.nix:349`) and `mkHeadlessServerVariant` (`:313`),
guarded by `builtins.pathExists`.

### 1.2 The failure

`server-services.nix` is host-owned *data* written in Nix, but the option names
it uses are *schema* owned by this repo. Commit `f380b23` removed 14 service
modules. Hosts still listing one fail evaluation outright:

```
error: The option `vexos.server.home-assistant' does not exist. Definition values:
- In `/nix/store/...-source/server-services.nix':
    { enable = false; }
```

`vexos-update` restores `flake.lock` and exits 1, so the update that would have
delivered the removal is itself blocked by the removal. Observed on
`vexos-headless-server-intel`, 2026-09-25.

### 1.3 Precedent in this repo

This class of problem is already handled twice in
`pkgs/vexos-update/default.nix`, both times by patching the host file from the
update script:

- lines 56–84: wrapper auto-heal wiring in `features.nix` (without it, every
  feature toggle silently reverted on each update)
- lines 86–110: force-tracking host-local files in `/etc/nixos`'s git repo

So "repair the host file during update" is established practice here, not a new
idea. What is new is doing it without a hand-maintained list.

---

## 2. Problem Definition

**Goal:** a host whose `server-services.nix` names a removed service must be
able to update, and the dead entries must not silently persist.

**Hard constraint from the user:** no hand-maintained list of added or removed
services anywhere in the repo. Any design requiring a developer to record a
removal in a second place is rejected.

**Success criteria:**

1. Removing a service module from `modules/server/` requires **no** other
   bookkeeping edit.
2. A host with dead entries is told exactly which entries are dead.
3. Dead entries are removable with one command, no hand editing of Nix files.
4. Nothing rewrites a host-owned file without the operator asking.
5. The mechanism works on a host whose installed tooling predates the removal.

---

## 3. Rejected Approaches

### 3.1 Stub module with an explicit list (`mkRemovedOptionModule`-style)

Declare a hidden option per removed service so stale entries evaluate.

Rejected: requires a hand-maintained list, violating the hard constraint.
Nixpkgs' own `lib.mkRemovedOptionModule` has the same shape, and additionally
raises on *any* definition, including `enable = false`, so it would not even
tolerate the common case.

### 3.2 Freeform catch-all on `vexos.server` — **verified infeasible**

Declare `options.vexos.server` with
`freeformType = types.attrsOf types.anything` so unrecognised names fall
through automatically. No list needed.

Verified working in isolation (`lib.evalModules`, 2026-09-25): unknown names are
accepted, declared options keep their types and type-checking, and the unknown
set is computable via `options.vexos.server.type.getSubOptions`.

**Verified to fail against the real flake** with `error: infinite recursion
encountered`, traced through `modules/server/proxmox.nix` and
`modules/server/papermc.nix`.

Cause: making `vexos.server` a single option means Nix must merge every
definition to produce any part of it. 40 modules in `modules/server/` both read
and write under that path:

```nix
cfg = config.vexos.server.proxmox;          # read
config = lib.mkIf cfg.enable {
  vexos.server.backup.servicePaths.proxmox = [ ... ];   # write
};
```

Producing `vexos.server` requires evaluating those `config` blocks, which
requires reading `vexos.server`. Cycle. Escaping it would mean relocating
`backup.servicePaths` out from under `vexos.server` across 40 modules — far
outside the scope of this change.

### 3.3 Warn at evaluation time, prune later

Rejected as impossible without 3.1 or 3.2. Nix hard-fails on the unknown option
before any warning could be emitted, so there is no build to complete and no
warning to attach. This is why the design below moves the check *before*
evaluation.

---

## 4. Proposed Solution

### 4.1 Key finding — the list already exists in the code

The set of valid service names can be read straight from the option
declarations, **without evaluating config and without any host files**:

```nix
lib.evalModules {
  specialArgs = { inherit pkgs; inputs = { }; utils = { }; };
  modules = [ { _module.check = false; } ./modules/server/default.nix ];
}
```
then `builtins.attrNames` of `options.vexos.server`.

Verified 2026-09-25 against the real tree; returns all 58 names:

```
adguard alertmanager arcane arr attic audiobookshelf authelia backup bookshelf
caddy cloudflare-ddns cockpit code-server docker dockhand fluent-bit forgejo
grimmory harmonia headscale home-registry homepage humidor immich jellyfin
joplin kernelBuilder kiji-proxy mealie nas nasSync netdata nextcloud nginx
nginx-proxy-manager ntfy paperless papermc photoprism plex podman portainer
prometheus proxmox proxy scrutiny searxng seerr storage syncthing tautulli
traefik unbound uptime-kuma vaultwarden vexboard wishlist zigbee2mqtt
```

This correctly includes the irregular names (`kernelBuilder`, `nasSync`, `nas`,
`storage`, `backup`, `proxy`) that a filename-derived list would get wrong. It
updates itself when a module is added or deleted. **This is the single source of
truth, and it is already maintained by the act of writing the modules.**

Because it reads only `options`, it is immune to a broken `server-services.nix`.

### 4.2 Ordering

Check **before** evaluation, not during it. `vexos-update` already performs
several host-file repairs before its dry-build; this becomes one more, inserted
after `nix flake update` (`pkgs/vexos-update/default.nix:230`) and before the
dry-build (`:233`).

### 4.3 Components

**A. `pkgs/vexos-prune-services/default.nix`** — new package, a flake app.

Modes:
- `--check` — report dead entries, change nothing.
- `--apply` — remove dead entries, leaving `server-services.nix.bak`.

Behaviour:
1. Derive valid names per 4.1 from **its own flake revision** (the one being
   deployed), not from whatever is installed.
2. Parse `/etc/nixos/server-services.nix` (path overridable via `$1` for tests).
3. Report or remove statements whose first path segment after `vexos.server.`
   is not in the valid set.

Exit codes: `0` clean / nothing to do; `1` dead entries found (`--check`);
`2` file cannot be parsed safely; `3` usage or environment error.

**B. Flake output** — expose as `packages.${system}.vexos-prune-services` and
`apps.${system}.prune-services`, so it is runnable with no rebuild:

```
nix run github:VictoryTek/vexos-nix#prune-services -- --apply
```

This is what makes the mechanism immune to the stale-tooling problem: the logic
always comes from GitHub at the moment it is needed. It also resolves the
current `home-assistant` breakage with no stub module and no hand editing.

**C. `pkgs/vexos-update/default.nix`** — insert the pre-evaluation check.

Resolve the locked `vexos-nix` revision from `/etc/nixos/flake.lock` via
`nix flake metadata --json` + `jq` (`jq` is already a `runtimeInput`), then run
that exact revision's app in `--check` mode. On dead entries: print them, print
the fix command, restore `flake.lock`, exit 1 — the same failure discipline the
dry-build path already uses.

**D. `justfile`** — add `prune-services`, calling the app with `--apply`.

**E. `scripts/preflight.sh`** — add a stage asserting 4.1 still evaluates and
returns a non-empty list, so a future refactor that breaks the derivation is
caught in CI rather than on a host.

### 4.4 Parsing rules

`template/server-services.nix` uses the flat form exclusively
(`vexos.server.<name>.<attr> = <value>;`), confirmed by inspection, and
`just enable` writes only that form (`justfile:2582`, `_set_flag`).

- Match `^[[:space:]]*vexos\.server\.(<name>)([.[:space:]=])` where
  `<name>` is `[A-Za-z0-9_-]+`.
- Skip commented lines; the template ships dozens of them and they must survive.
- A statement may span lines; consume until brace/bracket depth returns to zero
  **and** the line ends the statement with `;`.
- **Refuse** (exit 2, change nothing) if the file uses the nested form
  `vexos.server = { ... }` or `vexos = { server = ...`. Textual removal is not
  safe there. Message names the file and says to remove the entries by hand.
  This form is not produced by any tooling in this repo.
- `--apply` always writes `server-services.nix.bak` first.
- An unknown name is dead whether set `true` or `false`; the option does not
  exist, so it has no effect either way. Both are removed, and `--check` lists
  any that were set `true` separately, as those indicate a service the operator
  believed was running.

### 4.5 Resulting behaviour

1. `just update` → dead entries detected → update **stops**, names them, prints
   the fix command. `flake.lock` restored; system unchanged.
2. Operator runs `just prune-services` (or the `nix run` form).
3. `just update` → clean → proceeds.

**Open decision (one-line change):** step 1 stops rather than auto-pruning,
per the operator's stated preference that nothing edit a host-owned file
unasked. Switching to auto-prune means calling `--apply` instead of `--check`
at that call site; the update would then complete in one pass and report what
it removed.

---

## 5. Implementation Steps

1. Add `pkgs/vexos-prune-services/default.nix` (name derivation + parser +
   `--check`/`--apply`), registered in `pkgs/default.nix`.
   → verify: `--check` against fixtures for clean / flat-dead / nested /
     commented-only files returns 0 / 1 / 2 / 0.
2. Expose `packages.${system}.vexos-prune-services` and
   `apps.${system}.prune-services` in `flake.nix`.
   → verify: `nix flake show --impure` lists both.
3. Insert the pre-evaluation check in `pkgs/vexos-update/default.nix` between
   `:230` and `:233`.
   → verify: package builds (shellcheck runs at build time).
4. Add the `prune-services` justfile recipe.
   → verify: `just --list` shows it; `just --evaluate` parses.
5. Add the preflight stage from 4.3.E.
   → verify: `bash scripts/preflight.sh` exits 0.
6. Regression: evaluate `vexos-headless-server-amd` with a stale entry present
   and confirm the failure is unchanged (this design does not make Nix tolerate
   it — it prevents reaching Nix with it).

## 6. Dependencies

None added. No new flake inputs, no new external libraries, so Context7
verification does not apply (internal change, no new dependencies). Runtime
tools — `nix`, `jq`, `git`, coreutils — are already present via
`writeShellApplication` `runtimeInputs` and ambient system PATH.

## 7. Module Architecture Pattern

No NixOS modules are added or changed. `modules/server/default.nix` is left
untouched, and no `lib.mkIf` guards are introduced. Option B is unaffected.

## 8. Risks and Mitigations

| Risk | Severity | Mitigation |
|------|----------|-----------|
| Textual edit corrupts a host's `server-services.nix` | High | `.bak` written before any write; refuse on nested form; the file is also git-tracked in `/etc/nixos` by `vexos-update:97` |
| Name derivation breaks after a refactor, emptying the valid set and marking every entry dead | High | Treat an empty derived list as a hard error (exit 3), never as "everything is dead"; preflight stage asserts non-empty |
| `_module.check = false` in the derivation masks a genuine error | Low | Scoped to the throwaway `evalModules` used only to read option names; never applied to a real configuration |
| Pre-evaluation check adds network/eval time to every update | Low | Options-only eval, no `nixpkgs` NixOS evaluation; revision already fetched by the preceding `nix flake update` |
| A typo in a service name is reported as a removed service | Medium | `--check` prints "not a known service" with the valid list, and `just enable` validates names at write time |
| Host uses the nested form | Medium | Detected; tool refuses and explains rather than corrupting |

## 9. Forbidden Commands

No step uses `nix flake check`, `nixos-rebuild switch`, or `nixos-rebuild boot`.
Validation uses `nix flake show --impure`, `nix eval --impure`, and
`bash scripts/preflight.sh`. `nixos-rebuild dry-build` cannot run on this
Windows/WSL workstation and remains the user's step on a NixOS host.

## 10. Sources

1. `template/etc-nixos-flake.nix` — host-owned side-file set and the two server
   variant builders (`:313`, `:349`).
2. `pkgs/vexos-update/default.nix` — existing host-file repair precedent
   (`:56-110`), update ordering (`:228-240`).
3. `modules/server/default.nix` + 58 service modules — option declarations.
4. `modules/server/proxmox.nix:19,59` and `papermc.nix:5,25` — the read/write
   pattern that causes the recursion in 3.2; 40 occurrences of
   `vexos.server.backup.servicePaths` found across `modules/server/`.
5. `justfile:2476-2590` (`enable`) — flat-form writer and name validation.
6. `template/server-services.nix` — flat form and commented-entry convention.
7. Empirical `lib.evalModules` experiments, Nix 2.34.1 under WSL, 2026-09-25 —
   freeform coexistence, `getSubOptions` introspection, type-check retention,
   real-flake recursion failure, and the options-only name derivation.
8. `nixpkgs` `lib/modules.nix` (rev `c508844`) — option merging and the
   `checked` wrapper producing the "option does not exist" throw.

## 11. Returns

Spec path: `.github/docs/subagent_docs/SERVER_SERVICES_PRUNE_spec.md`
