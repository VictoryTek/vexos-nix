# Uptime Kuma v2 Upgrade — Specification

**Feature name:** `uptime_kuma_v2_upgrade`
**Date:** 2026-08-20
**Phase:** 1 — Research & Specification

---

## 1. Current State Analysis

### 1.1 The module

`modules/server/uptime-kuma.nix` declares a single OCI container:

```nix
virtualisation.oci-containers.containers.uptime-kuma = {
  image = "louislam/uptime-kuma:1.23.17";
  ports = [ "${toString cfg.port}:3001" ];
  volumes = [ "uptime-kuma-data:/app/data" ];
};
```

Options exposed: `enable`, `port` (default 3001), `openFirewall` (default true).

### 1.2 The automation

`.github/workflows/update-container-images-weekly-wednesday.yml` tracks 14 OCI images.
Each entry is `file:image-repo:registry:tag-regex`. The Uptime Kuma entry (line 52) is:

```
"modules/server/uptime-kuma.nix:louislam/uptime-kuma:dockerhub:^1\.[0-9]+\.[0-9]+\$"
```

The `^1\.` prefix constrains matching to the 1.x release line.

### 1.3 Verified registry state (queried 2026-08-20)

| Service | Pinned | Latest available | Status |
|---|---|---|---|
| portainer-ce | 2.44.0 | 2.44.0 | current |
| s-pdf | 2.14.3 | 2.14.3 | current |
| authelia | 4.39.20 | 4.39.20 | current |
| nginx-proxy-manager | 2.15.1 | 2.15.1 | current |
| dozzle | v10.7.3 | v10.7.3 | current |
| joplin/server | 3.7.1 | 3.7.1 | current |
| grimmory | v3.3.2 | v3.3.2 | current |
| arcane | v1.19.4 | v1.19.4 | current |
| homepage | v1.4.5 | v1.4.5 | current |
| maintainerr | 3.13.0 | 3.13.0 | current |
| postgres | 16.15 | 16.15 (16.x line) | current, intentional major pin |
| linuxserver/mariadb | 11.4.12 | 11.4.12 (11.4.x line) | current, intentional major pin |
| dockhand | v1.0.37 | unverifiable (GHCR 403) | unknown |
| **uptime-kuma** | **1.23.17** | **2.5.0** | **STALE** |

The workflow has committed a bump every week without interruption
(`45203b6` 07-08, `3160798` 07-15, `7a75b30` 07-22, `4fd188c` 07-29,
`b41afe8` 08-05, `b86f091` 08-12, `ae99a35` 08-19). The automation itself is healthy.

---

## 2. Problem Definition

Two compounding causes, only the second of which is still active:

**Cause A (historical, now resolved).** Until commit `5e113e3` (2026-08-17), Uptime Kuma
was not tracked by the automation at all. It was pinned as `louislam/uptime-kuma:1` — a
floating *major* tag. Docker resolved this to the newest 1.x image on each pull, so the
service silently tracked the 1.x line and could never cross into 2.x.

**Cause B (active).** When `5e113e3` added Uptime Kuma to the tracked list, the tag regex
was written as `^1\.[0-9]+\.[0-9]+$` — evidently derived from the pre-existing `:1` pin
rather than from the upstream release line. Every other application image in the list uses
a major-agnostic `^v?[0-9]+\.[0-9]+\.[0-9]+$`.

Consequently the 2026-08-19 run (`ae99a35`) filtered Docker Hub down to 1.x tags only,
correctly identified 1.23.17 as newest among them, and rewrote `:1` → `:1.23.17`. This
converted a floating tag that *could* still move into a hard pin that *cannot*. All future
runs will report "already at latest" and be correct within their constrained view.

**Net effect:** Uptime Kuma is frozen at 1.23.17 while upstream is at 2.5.0, and no future
automation run will ever correct it.

---

## 3. Upstream Research — v1.23 → v2.5.0

Sources consulted:

1. [GitHub Releases — louislam/uptime-kuma](https://github.com/louislam/uptime-kuma/releases) — confirms 2.5.0 is latest, released August 1
2. [Uptime Kuma v2: Breaking Changes You Need to Know — BuzzRAG](https://buzzrag.com/article/uptime-kuma-v2-breaking-changes-you-need-to-know)
3. [Uptime Kuma 2.0 introduces MariaDB support, rootless Docker, modern UI — AlternativeTo](https://alternativeto.net/news/2025/10/uptime-kuma-2-0-introduces-mariadb-support-rootless-docker-modern-ui-and-upgrade-tools)
4. [Issue #5281 — SQLITE_CORRUPT migration error 1.23.15 → 2.0.0-beta](https://github.com/louislam/uptime-kuma/issues/5281)
5. [Issue #6264 — SQLite migration failing (v2.0.2)](https://github.com/louislam/uptime-kuma/issues/6264)
6. [Issue #6091 — SQLite to MariaDB migration in 2.0](https://github.com/louislam/uptime-kuma/issues/6091)
7. Upstream `compose.yaml` at tag `2.5.0` (fetched directly from raw.githubusercontent.com)

### 3.1 Breaking changes in v2

| Change | Impact on this module |
|---|---|
| `latest` tag removed | **None** — module already pins an explicit version |
| Alpine-based images dropped | **None** — module uses the default (Debian) variant |
| SQLite schema migration on first 2.x start | **None in practice** — user has confirmed no monitors/data are currently tracked |
| SQLite → MariaDB migration unsupported | **None** — module uses the bundled SQLite backend and is not changing that |
| Badge endpoint changes | **None** — no badge consumers in this repo |
| Retry defaults / email template changes | **None** — no declarative monitor config in this repo |
| New `UPTIME_KUMA_SQLITE_SINGLE_CONNECTION` env var (2.3.0+) | **Not needed** — opt-in, targets Raspberry Pi SQLite locking |

### 3.2 Container interface — verified unchanged

Upstream `compose.yaml` at tag `2.5.0`:

```yaml
services:
  uptime-kuma:
    image: louislam/uptime-kuma:2
    restart: unless-stopped
    volumes:
      - ./data:/app/data
    ports:
      - "3001:3001"
```

Container port remains **3001**; data path remains **`/app/data`**. The module's `ports`
and `volumes` lines therefore require **no change**.

### 3.3 Tag shape on Docker Hub

2.x publishes `2.5.0`, `2.5.0-rootless`, `2.5.0-slim`, `2.5.0-slim-rootless`. The plain
`2.5.0` tag exists and is the correct analogue of the current pin. A
`^[0-9]+\.[0-9]+\.[0-9]+$` regex matches `2.5.0` and correctly excludes the
`-rootless` / `-slim` variants.

### 3.4 Migration risk — assessed as not applicable

The documented v2 migration failures (issues #5281, #6264) all involve migrating an
existing populated 1.x SQLite database. The user has explicitly confirmed **no monitors or
data are currently tracked** in this instance. On an empty `uptime-kuma-data` volume, 2.x
initialises a fresh schema with no migration path exercised.

---

## 4. Proposed Solution

Two surgical, single-line changes.

### 4.1 Bump the image pin

`modules/server/uptime-kuma.nix` line 29:

```diff
-      image = "louislam/uptime-kuma:1.23.17";
+      image = "louislam/uptime-kuma:2.5.0";
```

### 4.2 Widen the automation regex

`.github/workflows/update-container-images-weekly-wednesday.yml` line 52:

```diff
-            "modules/server/uptime-kuma.nix:louislam/uptime-kuma:dockerhub:^1\.[0-9]+\.[0-9]+\$"
+            "modules/server/uptime-kuma.nix:louislam/uptime-kuma:dockerhub:^[0-9]+\.[0-9]+\.[0-9]+\$"
```

This aligns Uptime Kuma with the major-agnostic convention used by every other application
image in the list. The two deliberate major locks (`postgres` `^16\.`, `linuxserver/mariadb`
`^11\.4\.`) are **left untouched** — major pinning is correct for stateful databases where
a major bump implies a data migration.

### 4.3 Explicitly out of scope

- No change to `ports`, `volumes`, `openFirewall`, or the option set — verified unnecessary.
- No new environment variables.
- No change to `modules/server/backup.nix`, `proxy.nix`, `default.nix`, or `justfile`.
- No change to the two database major-version regexes.

---

## 5. Implementation Steps

```
1. Edit modules/server/uptime-kuma.nix line 29: pin 1.23.17 -> 2.5.0
   → verify: grep confirms image = "louislam/uptime-kuma:2.5.0"

2. Edit .github/workflows/update-container-images-weekly-wednesday.yml line 52:
   regex ^1\. -> ^[0-9]+\.
   → verify: grep confirms the entry matches the major-agnostic form; simulate the
     workflow's tag-resolution locally against Docker Hub and confirm it yields 2.5.0

3. Confirm no other file hardcodes a 1.x Uptime Kuma version
   → verify: grep -rn "uptime-kuma:1" across the repo returns nothing

4. Phase 3 build validation (see Section 8)
   → verify: nix flake show --impure succeeds; dry-build succeeds for required variants
```

---

## 6. Dependencies

No new flake inputs, Nix packages, or external libraries. Context7 is **not required** for
this change — it modifies a container image tag string and a CI regex, introducing no new
dependency and no new external API surface.

The only external artifact is the Docker image `louislam/uptime-kuma:2.5.0`, verified
present on Docker Hub.

---

## 7. Configuration Changes

None user-facing. The option set (`enable`, `port`, `openFirewall`) is unchanged, as are
default values. Existing `vexos.server.uptime-kuma.*` settings in host configs and
`template/server-services.nix` remain valid without edit.

On the next `nixos-rebuild switch` on a host with the service enabled, the container is
recreated from the 2.5.0 image against the existing `uptime-kuma-data` volume.

---

## 8. Build Validation Plan (for Phase 3)

Per CLAUDE.md, this change touches a server module, so:

- `nix flake show --impure` — flake structure (**not** `nix flake check`, which is FORBIDDEN)
- `sudo nixos-rebuild dry-build --flake .#vexos-desktop-amd`
- `sudo nixos-rebuild dry-build --flake .#vexos-desktop-nvidia`
- `sudo nixos-rebuild dry-build --flake .#vexos-desktop-vm`
- `sudo nixos-rebuild dry-build --flake .#vexos-server-amd` (server module touched)
- `sudo nixos-rebuild dry-build --flake .#vexos-headless-server-amd` (server module touched)
- `git ls-files hardware-configuration.nix` → must be empty
- `system.stateVersion` unchanged in all `configuration-*.nix`
- No new flake inputs → `follows` check trivially satisfied

**Environment caveat:** the primary working directory is Windows (`win32`). `nixos-rebuild`
requires a NixOS host. If Nix tooling is unavailable in this environment, Phase 3 must record
the build steps as **NOT EXECUTABLE HERE** rather than falsely reporting a pass, and defer
closure validation to GitHub Actions CI and to the user's own host rebuild.

---

## 9. Risks & Mitigations

| # | Risk | Severity | Mitigation |
|---|---|---|---|
| 1 | v2 SQLite schema migration corrupts existing data | High (generally) | **Not applicable here** — user confirmed no tracked monitors/data. Volume is effectively empty; 2.x initialises fresh. |
| 2 | Widened regex later auto-bumps across a future major (3.x) unattended | Medium | Accepted, and consistent with how all 11 other application images are already handled. Databases keep their major locks. Noted below as a follow-up option. |
| 3 | Container interface changed in v2 (port/volume) | High if true | **Retired** — verified against upstream `compose.yaml` at tag 2.5.0: port 3001 and `/app/data` unchanged. |
| 4 | Docker Hub tag listing truncation (`page_size=100`) hides plain semver tags behind many variant tags | Low | Verified by live query: `2.5.0` is present in the first 100 `last_updated`-ordered tags. |
| 5 | Build validation not executable on this Windows host | Medium | Explicitly surfaced in Phase 3 output; CI + user host rebuild act as the real gate. |

### 9.1 Noted but out of scope (per Surgical Changes rule)

`modules/server/backup.nix:69` maps `uptime-kuma = [ "/var/lib/uptime-kuma" ]`, but the
container stores its data in the Docker **named volume** `uptime-kuma-data`
(`/var/lib/docker/volumes/uptime-kuma-data/_data`), not `/var/lib/uptime-kuma`. This
backup path appears to be pre-existing dead configuration that likely backs up nothing.
It is **unrelated to this task and is not being changed** — flagged here for the user's
awareness as a candidate for separate follow-up work.

---

## 10. Success Criteria

1. `modules/server/uptime-kuma.nix` pins `louislam/uptime-kuma:2.5.0`.
2. The workflow's Uptime Kuma regex is major-agnostic and, when simulated against Docker
   Hub, resolves to `2.5.0` (i.e. reports "already at latest" post-change).
3. No other file references a 1.x Uptime Kuma tag.
4. `nix flake show --impure` succeeds (or is recorded as not executable in this environment).
5. `bash scripts/preflight.sh` exits 0 (Phase 6).
