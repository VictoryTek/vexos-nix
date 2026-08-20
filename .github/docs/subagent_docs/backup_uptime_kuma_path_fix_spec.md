# backup.nix Uptime Kuma Path Fix — Specification

**Feature name:** `backup_uptime_kuma_path_fix`
**Date:** 2026-08-20
**Phase:** 1 — Research & Specification

---

## 1. Current State Analysis

`modules/server/backup.nix` auto-derives restic backup paths per enabled service from a
`servicePaths` table (`modules/server/backup.nix:21-73`), documented as following "the
StateDirectory convention of `/var/lib/<service-name>`" for native NixOS systemd services.

The `uptime-kuma` entry (line 69) follows that convention:

```nix
uptime-kuma = [ "/var/lib/uptime-kuma" ];
```

But Uptime Kuma is not a native systemd service with a StateDirectory — it is deployed as
an OCI container (`modules/server/uptime-kuma.nix:28-32`):

```nix
virtualisation.oci-containers.containers.uptime-kuma = {
  image = "louislam/uptime-kuma:2.5.0";
  ports = [ "${toString cfg.port}:3001" ];
  volumes = [ "uptime-kuma-data:/app/data" ];
};
```

`"uptime-kuma-data:/app/data"` is a **named volume** mount, not a bind mount. The host-side
data never lands at `/var/lib/uptime-kuma` — that path does not exist for this service.
`/var/lib/uptime-kuma` is very likely empty or absent, meaning the current backup config
silently backs up nothing for this service.

### 1.1 Actual on-disk location of the named volume

The real path depends on which OCI backend is active, which is host-configurable:

- `modules/server/uptime-kuma.nix:26` sets `virtualisation.oci-containers.backend =
  lib.mkDefault "docker"` — the default on any host that doesn't opt into Podman.
- `modules/server/podman.nix:29` sets `virtualisation.oci-containers.backend = "podman"`
  as a plain (non-`mkDefault`) assignment, which **overrides** every service's
  `mkDefault "docker"` when `vexos.server.podman.enable = true`. This is a host-wide
  switch — it doesn't just affect Podman-aware services with their own `backend` option
  (`arcane`, `dockhand`, `portainer`); it silently repoints the *entire* Docker default,
  including services like `uptime-kuma` that hardcode `mkDefault "docker"` with no per-
  service override.
- Confirmed via the NixOS option index: `virtualisation.oci-containers.backend` is `one
  of "podman", "docker"`.

Named-volume storage roots for each backend (rootful, the standard case for NixOS
`oci-containers` systemd units):

| Backend | Named volume root |
|---|---|
| docker | `/var/lib/docker/volumes/<name>/_data` |
| podman | `/var/lib/containers/storage/volumes/<name>/_data` |

So the correct path for the `uptime-kuma-data` volume is:
- `/var/lib/docker/volumes/uptime-kuma-data/_data` (docker, the default), or
- `/var/lib/containers/storage/volumes/uptime-kuma-data/_data` (podman, if
  `vexos.server.podman.enable = true` on that host).

A static single path is wrong for whichever backend isn't currently active on the host.

### 1.2 Prior art for backend-conditional paths in this module set

`arcane.nix:111-114`, `dockhand.nix:95-98`, and `portainer.nix:59-62` already use the
established pattern for backend-conditional values:

```nix
(if cfg.backend == "docker"
 then "/var/run/docker.sock:/var/run/docker.sock"
 else "/run/podman/podman.sock:/var/run/docker.sock:ro")
```

`backup.nix` is not the `uptime-kuma` module and has no `cfg.backend` of its own, but it
can read the merged, host-wide `config.virtualisation.oci-containers.backend` directly —
the same option every service module above contributes to — to select the correct root at
eval time.

---

## 2. Problem Definition

`modules/server/backup.nix:69` backs up a path (`/var/lib/uptime-kuma`) that the Uptime
Kuma container never writes to. On any host with `vexos.server.backup.enable = true` and
`vexos.server.uptime-kuma.enable = true`, the declared backup silently captures nothing
for this service — no error, no warning, just an empty or nonexistent path handed to
restic.

---

## 3. Proposed Solution

Replace the single static guess with a backend-conditional path pointing at the actual
named-volume location, mirroring the existing `cfg.backend == "docker"` conditional
pattern used elsewhere in `modules/server/`:

```nix
uptime-kuma = [
  (if config.virtualisation.oci-containers.backend == "podman"
   then "/var/lib/containers/storage/volumes/uptime-kuma-data/_data"
   else "/var/lib/docker/volumes/uptime-kuma-data/_data")
];
```

`config` is already in scope in `backup.nix` (used throughout, e.g.
`config.vexos.server.attic.dataDir`, `config.services.postgresql.enable`), so this needs
no new module argument.

### 3.1 Scope boundary

This fix touches **only** the `uptime-kuma` line, per the user's explicit request. It does
not touch:
- `servicePaths.homepage` / `servicePaths.portainer`, which show the same
  static-`/var/lib/<name>`-guess-vs-named-volume mismatch (`homepage-config:/app/config`,
  `portainer-data:/data`) — flagged as a separate pre-existing issue, not fixed here.
- Any other `servicePaths` entry.
- `modules/server/uptime-kuma.nix` itself (no change needed — the container config is
  already correct; the bug is solely in `backup.nix`'s assumption).

---

## 4. Dependencies

None. No new flake inputs, packages, or external libraries. Context7 not applicable —
pure Nix module logic, no external API.

---

## 5. Configuration Changes

None user-facing. `vexos.server.backup.*` option set is unchanged. Behavior changes only
for hosts that have both `vexos.server.backup.enable = true` and
`vexos.server.uptime-kuma.enable = true` — for them, restic now backs up the volume that
actually contains Uptime Kuma's SQLite database instead of an empty/nonexistent path.

---

## 6. Implementation Steps

```
1. Edit modules/server/backup.nix line 69: replace static /var/lib/uptime-kuma with
   the backend-conditional named-volume path.
   → verify: grep confirms both docker and podman paths are present in the entry

2. Phase 3 build validation
   → verify: nix eval succeeds for a config with backup + uptime-kuma both enabled,
     for both the default (docker) and podman backend cases if a host combination
     exercises them; otherwise confirm via targeted nix eval of the derived
     `enabledServicePaths` value or an existing config combining both flags
```

---

## 7. Risks & Mitigations

| # | Risk | Severity | Mitigation |
|---|---|---|---|
| 1 | No host in this repo currently combines `backup.enable` + `uptime-kuma.enable`, so the change may be unexercised by existing configs | Low | Verify via direct `nix eval` of the `enabledServicePaths` derivation using `--impure` overrides, independent of any specific host's toggles |
| 2 | Rootless Docker/Podman would use a different (`$HOME`-relative) volume root than assumed here | Low | NixOS `virtualisation.oci-containers` / `virtualisation.docker` run rootful by default in this repo; no rootless config exists in `modules/server/` |
| 3 | Named volume may not exist yet on a freshly provisioned host before first container start | None (backup-time concern, not eval-time) | restic/systemd unit ordering already handles service dependencies elsewhere in this file; out of scope for a path-correctness fix |

---

## 8. Success Criteria

1. `modules/server/backup.nix` derives the Uptime Kuma backup path from the actual named
   volume location, correctly branching on `virtualisation.oci-containers.backend`.
2. `nix eval --impure` succeeds for the affected configuration(s).
3. `bash scripts/preflight.sh` exits 0.
