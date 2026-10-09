# Spec: Chaptarr server service

## Current state

- No `chaptarr` anywhere in the repo; not packaged in nixpkgs (`nix search` on
  unstable returns nothing), so it must run as an OCI container.
- Closest precedents in `modules/server/`: `bookshelf.nix` (Readarr revival,
  single container, `/config` + `/data`), `sportarr.nix` (same shape, pinned
  image + `mediaMounts`), `listenarr.nix`.
- `just service enable <name>` only works for names in the justfile tables;
  the wishlist fix (f937340) shows the full registration set.

## Problem

Add Chaptarr — a re-work of the retired Readarr that manages audiobooks *and*
ebooks in one instance — as an optional `vexos.server.chaptarr` module.

## Findings (sources)

- Docker Hub `chaptarr/chaptarr` ("Audiobook and eBook manager"; tags
  0.9.965 … 0.9.925, `develop`, `latest` — `latest` last pushed 2026-08-08, i.e.
  stale vs the numbered tags). `robertlordhood/chaptarr` is the same build
  (pushed seconds apart, same date) under the author's personal namespace.
- SSD Nodes guide (self-host-chaptarr-audiobook-library): port **8789**, `/config`
  holds SQLite DB + all state, PUID/PGID default to unRAID's 99/100 so they must
  be set, `UMASK=002`, library mounts `/audiobooks`, `/ebooks`, `/downloads`, and
  a single parent `/data` mount recommended for hardlinks.
- Prowlarr treats it as a Readarr-type app (API-compatible) — no module wiring.
- Upstream is beta software; Docker is the only supported install.

## Design (Option B: no mkIf-by-role; options-gated `mkIf cfg.enable` only)

New `modules/server/chaptarr.nix`, modelled on `sportarr.nix`:

| Option | Default | Notes |
|---|---|---|
| `enable` | false | |
| `port` | 8789 | host port → container 8789 |
| `dataDir` | `/var/lib/chaptarr` | → `/config`; added to `backup.servicePaths` |
| `libraryDir` | `${dataDir}/data` | → `/data` (single parent: hardlink-friendly, matches bookshelf/sportarr); not backed up |
| `mediaMounts` | `[]` | `lib/storage-mount-ordering.nix` → `docker-chaptarr` |
| `userId`/`groupId` | 1000/1000 | PUID/PGID + tmpfiles ownership |
| `openFirewall` | true | |

- Image pinned `chaptarr/chaptarr:0.9.965` and added to the weekly bump
  workflow (regex `^[0-9]+\.[0-9]+\.[0-9]+$`; matches `0.9.965`, not `0.9`).
- Env: `PUID`, `PGID`, `UMASK=002` (upstream guide's value), `TZ`.
- Separate `/audiobooks` `/ebooks` `/downloads` mounts are deliberately not
  added: root folders are set in the UI under `/data`, avoiding cross-device
  hardlink failures. Postgres (`Chaptarr__Postgres__*`) is not wired; SQLite default.

## Files

1. `modules/server/chaptarr.nix` (new)
2. `modules/server/default.nix` — import under "Books & Comics"
3. `template/server-services.nix` — commented enable line
4. `justfile` — `_server_service_names`, `_service_catalog` (Books & Reading),
   `_service-info`, `_service-units`, `_service-status` URLs, `_service-enable` detail
5. `.github/workflows/update-container-images-weekly-wednesday.yml` — SERVICES entry

## Risks

- **Namespace choice**: `chaptarr/chaptarr` vs `robertlordhood/chaptarr` — same
  builds today; chose the project-branded namespace used by the guides. One-line change.
- **Beta software / SQLite in backup**: restic of a live SQLite DB; same as every
  other container module here.
- Port 8789 checked: unused elsewhere in the repo.
- Not run: `nix flake check` (forbidden); validation via `nix eval`/`dry-build`.
