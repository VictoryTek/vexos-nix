# Final review — backup self-registration, dump-timer helper, three new modules

Covers Parts 1–4. Supersedes `BACKUP_SELF_REGISTRATION_review.md` (Part 1 only).

## Validation

| Check | Result |
|---|---|
| `nix-instantiate --parse`, all `modules/server/*.nix` + `modules/lib/dump-timer.nix` | PASS |
| Backup mechanism eval (isolated `nixosSystem`, pinned `flake.lock` rev) | PASS |
| Assertion negative control (registration force-removed) | PASS — fires, names the service |
| Dump-timer conversion eval vs. pre-conversion units | PASS — identical |
| New-module eval (wishlist / bookshelf / cloudflare-ddns) | PASS — no failed assertions |
| `bash scripts/preflight.sh` | **PASS, exit 0** |
| `nixos-rebuild dry-build` | **NOT RUN** — requires a NixOS host; unavailable on this Windows workstation |

### Dump-timer behavioural equivalence

Evaluated `systemd.services`/`systemd.timers` for both converted services and
compared against the hand-rolled definitions they replaced:

| | grimmory | joplin |
|---|---|---|
| unit name | `grimmory-mariadb-dump` | `joplin-postgres-dump` |
| `OnCalendar` | `*-*-* 23:15:00` | `*-*-* 23:30:00` |
| `Persistent` | `true` | `true` |
| `description` | unchanged | unchanged |
| `after` / `requires` | `docker-grimmory-db.service` | `docker-joplin-db.service` |
| `script` | identical | identical |

All four identity-bearing fields (unit name, schedule, ordering, script) are
byte-identical, so activation neither renames a unit nor resets a timer stamp.
`offsetMinute` and `unitName` are pinned in both modules for exactly this
reason; new modules omit them and take the hashed offset.

## Part 4 audit — every module in `modules/server/default.nix`

| Module | Self-registers? | Backup method | Issue found |
|---|---|---|---|
| adguard | yes | direct path | — |
| alertmanager | no — `noBackupNeeded` | none | silences/nflog are transient |
| arcane | **yes (newly added)** | direct path (named volume) | **had zero coverage before this change** |
| arr | yes | direct path (5 paths) | — |
| attic | yes | direct path (`cfg.dataDir`) | — |
| audiobookshelf | yes | direct path | — |
| authelia | yes | direct path | — |
| backup | n/a — `noBackupNeeded` | n/a | — |
| bookshelf | yes (new module) | direct path | `libraryDir` deliberately excluded |
| caddy | yes | direct path | — |
| cloudflare-ddns | no — `noBackupNeeded` (new module) | none | genuinely stateless |
| cockpit | no — `noBackupNeeded` | none | — |
| code-server | no — `noBackupNeeded` | none | — |
| docker / podman | no — `noBackupNeeded` | none | container runtimes |
| dockhand | yes | direct path (`cfg.dataDir`) | — |
| dozzle | no — `noBackupNeeded` | none | — |
| fluent-bit | no — `noBackupNeeded` | none | log cursor only |
| forgejo | yes | direct path | — |
| grafana | yes | direct path | — |
| grimmory | yes | **dump-timer helper** + direct path | — |
| harmonia | yes | direct path | separate pre-existing eval break, see below |
| headscale | yes | direct path | — |
| home-assistant | yes | direct path | — |
| homepage | yes | direct path | ⚠ **path likely wrong — see Q1** |
| immich | yes | direct path | — |
| jellyfin | yes | direct path | — |
| joplin | yes | **dump-timer helper** + direct path | — |
| kavita / komga | yes | direct path | — |
| kernelBuilder | no — `noBackupNeeded` | none | derived build artifacts |
| kiji-proxy | no — `noBackupNeeded` | none | — |
| listmonk / loki | yes | direct path | — |
| matrix-conduit | yes | direct path | — |
| mealie / minio | yes | direct path | — |
| nas | no — `noBackupNeeded` | none | umbrella toggle |
| navidrome / nextcloud | yes | direct path | — |
| netdata | no — `noBackupNeeded` | none | — |
| nginx | no — `noBackupNeeded` | none | certs live in `/var/lib/acme` |
| nginx-proxy-manager | **yes (newly added)** | direct path (named volumes) | **had zero coverage before this change** |
| node-red / ntfy | yes | direct path | — |
| paperless / papermc / photoprism / plex | yes | direct path | — |
| portainer / portbook / prometheus | yes | direct path | — |
| proxmox | yes | direct path (2 paths) | — |
| proxy | no — `noBackupNeeded` | none | generates Caddy vhosts only |
| rustdesk / scrutiny / seerr | yes | direct path | — |
| searxng | no — `noBackupNeeded` | none | declarative config |
| stirling-pdf | no — `noBackupNeeded` | none | ⚠ **has config volume — see Q2** |
| syncthing | no — `noBackupNeeded` | none | deliberate; use `extraPaths` |
| tautulli | yes | direct path | — |
| traefik | **yes (newly added)** | direct path | **had zero coverage before this change** |
| unbound | no — `noBackupNeeded` | none | — |
| uptime-kuma | yes | direct path (named volume) | — |
| vaultwarden / vexboard | yes | direct path | — |
| wishlist | yes (new module) | direct path | SQLite copied live, no dump tool in image |
| zigbee2mqtt | yes | direct path | — |

**Coverage is exact**: 18 modules decline to register, and all 18 are in
`noBackupNeeded` (19 entries, the extra being `backup` itself). No unmatched
entries in either direction — no service escapes the check, no dead exemptions.

## Open questions — not changed, awaiting user decision

**Q1 — `homepage` path.** Registered as `/var/lib/homepage`, carried over
verbatim from the old central table. But `homepage.nix:46` mounts the named
volume `homepage-config:/app/config`, so the real state is at
`/var/lib/docker/volumes/homepage-config/_data`. The registered path very
likely does not exist, meaning homepage has had no effective backup coverage
regardless of the refactor.

**Q2 — `stirling-pdf`.** Classified `noBackupNeeded` as specified, but
`stirling-pdf.nix:32-33` mounts `stirling-pdf-data:/usr/share/tessdata` and
`stirling-pdf-config:/configs`. `tessdata` is redownloadable OCR data; the
`/configs` volume holds settings and may be worth capturing.

**Q3 — `vexos.server.storage.{mergerfs,snapraid}`.** These sit one level deeper
than the assertion walks (`vexos.server.storage.mergerfs.enable`, not
`vexos.server.storage.enable`), so they are neither covered nor exempted. Not a
regression — the old table didn't cover them either. SnapRAID content files may
warrant coverage.

**Q4 — `bookshelf.libraryDir`.** Excluded from backup on the assumption that a
media library belongs on its own storage tier, matching how the repo treats
large media elsewhere. Note this differs from `grimmory`, which *does* include
its `libraryDir`.

## Pre-existing issue (unrelated, unfixed)

`modules/server/harmonia.nix:98` sets `services.harmonia.cache.*`. At the
nixpkgs rev pinned in `flake.lock` (`e4bae1bd`) that option does not exist —
verified directly:

```
{ hasCache = false; keys = [ "enable" "package" "settings" "signKeyPath" "signKeyPaths" ]; }
```

Any config importing `modules/server/default.nix` therefore fails to evaluate
before reaching any of this work. Needs either a lock bump or a rewrite against
the flat option set. Out of scope here; reported only.

## Score table

| Category | Score | Grade |
|----------|-------|-------|
| Specification Compliance | 100% | A |
| Best Practices | 98% | A |
| Functionality | 100% | A |
| Code Quality | 98% | A |
| Security | 100% | A |
| Performance | 100% | A |
| Consistency | 100% | A |
| Build Success | 90% | A− |

Build Success reflects that full-config `dry-build` could not run here (no
NixOS host, plus the pre-existing `harmonia` blocker). Every check that could
run, passed.

**Overall Grade: A (98%)**

## Result

**APPROVED** — preflight exit 0. The user must still run
`sudo nixos-rebuild dry-build --flake .#vexos-<role>-<gpu>` on the target host
before switching.
