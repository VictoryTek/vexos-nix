# Joplin Sync Server — Phase 3 Review

Spec: `.github/docs/subagent_docs/joplin_server_spec.md`

Files reviewed:
- `modules/server/joplin.nix` (new)
- `modules/server/default.nix`
- `modules/server/backup.nix`
- `template/server-services.nix`
- `justfile`

## Method

In addition to static review against the spec and sibling modules
(`arcane.nix`, `vaultwarden.nix`, `cockpit.nix`, `dockhand.nix`), the single
most load-bearing correctness question raised for this review — whether
`systemd.services."docker-joplin-db".after/.requires` set from a *second*
location in `joplin.nix` merges with, or clobbers, the definition the
`virtualisation.oci-containers` module itself generates for that same
service name — was verified empirically, not just by reading source. An
isolated `lib.evalModules` harness was built with the real
`nixos/modules/virtualisation/oci-containers.nix` from this repo's pinned
nixpkgs plus the real `modules/server/joplin.nix`, `vexos.server.joplin.enable
= true` and the two other required options set. Results:

```
dbAfter     = ["docker.service","docker.socket","network-online.target","joplin-network.service"]
dbRequires  = ["joplin-network.service"]
serverAfter = ["docker.service","docker.socket","network-online.target","docker-joplin-db.service","joplin-network.service"]
serverRequires = ["docker-joplin-db.service","joplin-network.service"]
dbEnv     = {"POSTGRES_DB":"joplin","POSTGRES_USER":"joplin"}
serverEnv = {"APP_BASE_URL":"http://test.ts.net:22300","APP_PORT":"22300","DB_CLIENT":"pg",
             "POSTGRES_DATABASE":"joplin","POSTGRES_HOST":"joplin-db","POSTGRES_PORT":"5432",
             "POSTGRES_USER":"joplin"}
allAssertionsPass = true
failedAssertions  = []
```

**Finding: not a bug.** `after`/`requires` are declared with
`type = types.listOf unitNameType` in `nixos/lib/systemd-unit-options.nix`.
List-typed NixOS options merge by concatenation across every module that
contributes a definition at the same (default) priority — there is no
clobber. The empirical result confirms this directly: both the
oci-containers-module-generated entries (`docker.service`,
`docker.socket`, `network-online.target`, and — for `joplin-server` — the
`dependsOn`-derived `docker-joplin-db.service`) *and* the
`joplin.nix`-contributed `joplin-network.service` are present together in
the final list. The network-creation ordering the module intends
(`joplin-network.service` before both containers) is real and will hold at
runtime.

**Finding: `dependsOn` is a real, existing option, not invented.**
Confirmed in `nixos/modules/virtualisation/oci-containers.nix:229-243`:
`dependsOn = mkOption { type = listOf str; ... }`, and `mkService` resolves
each name in the list to `"${v.serviceName}.service"` and adds it to both
`after` and `requires` (lines 388, 437, 442-446 of that file). The harness
output (`docker-joplin-db.service` appearing in `serverAfter`/`serverRequires`)
confirms this resolves correctly for `dependsOn = [ "joplin-db" ]`.

**Finding: environment variable types are correct.** `attrsOf str` is
enforced at the type-check layer inside `evalModules`; the harness could not
have produced output at all if any environment value were non-string (e.g.
an int). All values on both containers evaluate as plain strings, matching
the option's `attrsOf str` type.

**Finding: `pkgs` is correctly in scope.** Module header is
`{ config, lib, pkgs, ... }:` (line 33) and both `joplin-network.service`
and `joplin-postgres-dump` reference `${pkgs.docker}/bin/docker` — this
evaluates and was exercised in the harness without error.

**Finding: tmpfiles `0700 root root` on `${cfg.dataDir}/postgres` is not a
bug.** The official `postgres:16` image has no `USER` directive — the
container starts as root, and `docker-entrypoint.sh` chowns `$PGDATA`
recursively to the `postgres` user (uid/gid 999) before re-execing itself
via `gosu postgres` as part of its own first-run initialization. No
`user = ...` override is set on the `joplin-db` container in this module,
so the container does start as root and this chown step runs. Root:root
0700 pre-created host directories are standard practice for official
Postgres container deployments for exactly this reason. Recommend adding a
one-line comment noting this dependency on the container running
entrypoint-as-root, since it is not obvious to a future reader and would
break silently if a `user = "999:999"` override were ever added later.

**Finding: `backup.nix`'s new `servicePaths.joplin` entry is safe when
disabled.** `enabledServicePaths` is built via
`lib.mapAttrsToList (name: paths: lib.optionals (config.vexos.server.${name}.enable or false) paths) servicePaths`
— the joplin path string is only realized into the final list when
`vexos.server.joplin.enable = true`. Referencing
`config.vexos.server.joplin.dataDir` unconditionally in the attrset value is
fine — `dataDir` has a plain string default and is always defined
regardless of `enable`, so there is no eval-time error when Joplin is
disabled. Confirmed no error in both the isolated harness (default
`dataDir`) and the full-flake eval (see Build Validation below).

## Minor / Recommended (non-blocking)

1. **`pkgs.docker` vs `config.virtualisation.docker.package`** —
   `joplin-network.service` and `joplin-postgres-dump` invoke
   `${pkgs.docker}/bin/docker` directly, whereas the oci-containers module
   itself uses `config.virtualisation.docker.package` for the container
   unit's `path`. Functionally identical at this repo's pinned nixpkgs rev
   (no override of `virtualisation.docker.package` exists anywhere in the
   repo), but if `virtualisation.docker.package` is ever overridden, these
   two manually-added units would silently use a different Docker client
   binary than the one managing the daemon/containers. Recommend switching
   to `config.virtualisation.docker.package` for consistency, not urgent.
2. **`networks` option vs `extraOptions`** — nixpkgs at this pin already
   exposes a native `networks = [ "..." ]` option on
   `virtualisation.oci-containers.containers.<name>` (verified in
   `oci-containers.nix:372-378`) that generates the same `--network=`
   flag. The module uses `extraOptions = [ "--network=joplin-net" ]`
   instead. Both are functionally equivalent and produce an identical
   command line here (no duplicate flag, since `networks` defaults to
   `[ ]`); using the native option would be marginally more idiomatic but
   this is a style preference, not a defect.
3. Add the one-line comment suggested above near the
   `${cfg.dataDir}/postgres` tmpfiles rule explaining the postgres-image
   root-entrypoint chown dependency.

None of the above are CRITICAL — they do not affect functional correctness,
security, or spec compliance.

## Consistency with Module Architecture Pattern (Option B)

- `modules/server/joplin.nix` is a self-contained optional-service module,
  matching `arcane.nix`/`vaultwarden.nix`/`dockhand.nix`: single
  `options.vexos.server.joplin`, `config = lib.mkIf cfg.enable { ... }`,
  no role/display/gaming `lib.mkIf` guards. Compliant.
- `default.nix`, `backup.nix`, `template/server-services.nix`, and
  `justfile` touch points are additive, alphabetically/thematically placed,
  and don't alter any existing shared module's unconditional behavior.
  Compliant.
- Firewall handling correctly follows the `cockpit.nix` interface-scoped
  precedent (`networking.firewall.interfaces.tailscale0.allowedTCPPorts`)
  rather than the global list — matches the spec's explicit Tailscale-only
  decision. Compliant.

## Security

- No hardcoded secrets. `POSTGRES_PASSWORD` is required via
  `environmentFile` (systemd `EnvironmentFiles`), enforced by assertion —
  same pattern as `arcane.nix`.
- No world-writable files (`tmpfiles` rules use `0700`).
- Default admin credentials are upstream-published, not repo-introduced,
  and are documented prominently in the module header with an explicit
  "change immediately" instruction — same treatment as Vaultwarden's
  `ADMIN_TOKEN` handling elsewhere in this repo.
- Firewall exposure is scoped to `tailscale0` only, not the global
  allowed-ports list, and `joplin-db` publishes no ports at all. No new
  attack surface beyond the existing Docker-daemon trust boundary shared by
  every other OCI-container service already in this repo.

## Build Validation

- `nix flake show --impure` — **PASS**. All 30 `nixosConfigurations`
  entries evaluated and listed correctly (structure valid); no errors.
- `git ls-files hardware-configuration.nix` — **PASS**, empty output;
  not committed.
- `system.stateVersion` — **PASS**, unchanged. `git diff --stat HEAD --
  configuration-*.nix` shows zero changes to any `configuration-*.nix`
  file; `stateVersion` is untouched by this feature by construction.
- Flake input `follows` — **N/A**, no new flake inputs added (per spec:
  `joplin/server` and `postgres:16` are OCI images pulled at
  container-start, not flake inputs).

### `sudo nixos-rebuild dry-build` — could not be executed

This sandboxed review environment enforces `no_new_privs`, which
unconditionally blocks `sudo` regardless of sandbox settings:
`sudo: The "no new privileges" flag is set, which prevents sudo from
running as root.` This is an environment limitation, not a code issue —
confirmed by running the exact required commands and observing the same
sudo failure independent of which flake target was requested.

**Substituted with the CLAUDE.md-sanctioned no-sudo equivalent**
(`nix eval --impure ... .config.system.build.toplevel.drvPath`, listed in
CLAUDE.md's own Test Commands as "equivalent to `nix flake check --no-build`
for a single target"):

| Target | Result |
|---|---|
| `vexos-desktop-amd` | **PASS** — full derivation evaluated (`/nix/store/0n4sri2...-nixos-system-vexos-26.05.drv`) |
| `vexos-desktop-nvidia` | **PASS** — full derivation evaluated |
| `vexos-desktop-vm` | **PASS** — full derivation evaluated |
| `vexos-server-amd` | **BLOCKED by pre-existing, unrelated assertion** (see below) |
| `vexos-headless-server-amd` | **BLOCKED by pre-existing, unrelated assertion** (see below) |

Note: the default `.` flake reference filters the evaluated source tree to
git-*tracked* files (a previously-documented characteristic of this repo/
Nix — untracked new files are invisible to `nix eval`/`nix flake show`
until staged). Since `modules/server/joplin.nix` is new and not yet staged,
targets that import `modules/server/default.nix` (i.e. `server`,
`headless-server`) needed the `path:$(pwd)#...` flake-reference form, which
copies the working tree as-is instead of filtering by git index state, to
even reach evaluation of the new file. This is expected given the new file
is unstaged; per CLAUDE.md's absolute rules this review does not run
`git add` — the user will need to stage the new files before a normal
`nix flake show`/`dry-build`/CI run against `.` will see them. This is
purely a staging precondition, not a defect in the implementation.

**`vexos-server-amd` / `vexos-headless-server-amd` failure detail** (both
identical): full evaluation reaches
`modules/zfs-server.nix:77-98`'s own assertion:

```
ZFS requires a unique networking.hostId per host — this is still a
shared placeholder committed in hosts/<role>-<gpu>.nix, not a real
per-machine value.
```

This is confirmed **pre-existing and unrelated to this change**:
- `git diff --stat HEAD -- hosts/` shows zero modifications to any host
  file in this diff.
- `hosts/server-amd.nix` already sets `networking.hostId =
  lib.mkDefault "a0000001";` — one of the exact placeholder values the
  `zfs-server.nix` assertion (lines 85-89) is designed to reject on *any*
  unedited install of that role+GPU combination, joplin-related or not.
- The same assertion does not fire for `desktop-*` targets (which don't
  import the ZFS-enabling server modules), consistent with it being a
  role-scoped, pre-existing safety check rather than something this diff
  introduced.

To further de-risk the joplin module specifically (independent of this
host-configuration precondition), an isolated `lib.evalModules` harness
using the actual `oci-containers.nix` + actual `joplin.nix` with
`enable = true` was run (see Method above) and passed cleanly: all
assertions true, correct systemd unit merging, correct environment string
types. Combined with the successful full-flake desktop-target evaluations
(proving the new `default.nix` import doesn't break unrelated roles) and
the isolated harness (proving the enabled-path module logic itself is
sound), this is considered sufficient evidence that the `server`/
`headless-server` full-flake failures are unrelated to the Joplin
implementation.

## Score Table

| Category | Score | Grade |
|----------|-------|-------|
| Specification Compliance | 100% | A |
| Best Practices | 96% | A |
| Functionality | 100% | A |
| Code Quality | 95% | A |
| Security | 100% | A |
| Performance | 100% | A |
| Consistency | 98% | A |
| Build Success | 90% | A- |

**Overall Grade: A (97%)**

Build Success is scored 90% rather than 100% only because the
`sudo nixos-rebuild dry-build` commands literally specified in CLAUDE.md's
Phase 3 checklist could not be executed in this sandboxed environment (see
above) and one substitute target pair (`server-amd`,
`headless-server-amd`) hit a pre-existing, unrelated host-configuration
precondition rather than completing to a green result. No code defect was
found in the reviewed files.

## Verdict

**PASS**

No CRITICAL issues. Three non-blocking RECOMMENDED items listed above
(pkgs.docker vs config.virtualisation.docker.package; native `networks`
option vs `extraOptions`; one doc comment on the postgres tmpfiles
ownership assumption) may be picked up opportunistically but do not block
merge or require a refinement cycle.

Two things require the **user's** attention before Phase 6/7 can fully
close out (per CLAUDE.md, staging is the user's action, not Claude's):
1. Stage `modules/server/joplin.nix` and
   `.github/docs/subagent_docs/joplin_server_spec.md` (currently untracked)
   so `nix flake show`/CI can see them via the default `.` flake reference.
2. The `vexos-server-amd`/`vexos-headless-server-amd` ZFS `hostId`
   placeholder assertion is a pre-existing condition on this dev host/repo
   state, unrelated to Joplin — flagging for awareness, not something this
   review is asking to be fixed as part of this feature.
