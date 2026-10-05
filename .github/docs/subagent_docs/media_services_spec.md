# Spec: MediaManager, Sportarr, Tdarr, Listenarr server services

## Current state
`modules/server/` holds one module per service, each exposing
`vexos.server.<name>.enable`, imported via `modules/server/default.nix`.
Closest precedents: `bookshelf.nix` (single OCI container, self-contained DB),
`joplin.nix` / `grimmory.nix` (app + dedicated DB container on a private Docker
network, generated secrets, nightly dump via `lib/dump-timer.nix`),
`audiobookshelf.nix` (`lib/storage-mount-ordering.nix`).
`scripts/preflight.sh` stage 10 derives service names from option declarations,
so new modules need no manual list entry there.

## Problem
Add four services as optional server modules: MediaManager, Sportarr, Tdarr,
Listenarr.

## Research findings
| Service | Packaging | Image / package | Port | State |
|---|---|---|---|---|
| Tdarr | nixpkgs `services.tdarr` (server + `nodes.<name>`), unfree (allowed by `modules/nix.nix`); present in stable and unstable | `tdarr-server`/`tdarr-node` | 8265 UI, 8266 API | `services.tdarr.dataDir` (`/var/lib/tdarr`) |
| Sportarr | none | `sportarr/sportarr:4.1.9.1119` (Docker Hub, tag verified) | 1867 | `/config`, `/data`; PUID/PGID/UMASK/TZ |
| Listenarr | none | `ghcr.io/listenarrs/listenarr:canary` (only published tag; releases are all pre-release) | 4545 | `/app/config`, `/audiobooks`, `/downloads`; PUID/PGID/UMASK |
| MediaManager | none | `quay.io/maxdorninger/mediamanager:1.12.3` (tag verified) + `postgres:17` | 8000 | `/app/config`, `/data`; Postgres required |

MediaManager config: upstream `media_manager/config.py` uses pydantic-settings
with `env_prefix="MEDIAMANAGER_"`, `env_nested_delimiter="__"`, env taking
precedence over `config.toml`. So no generated TOML is needed. DB fields: host,
port, user, password, dbname. Auth: `token_secret`, `admin_emails`
(registration closed by default, so an admin email is mandatory).
Sources: github.com/{maxdorninger/MediaManager, Sportarr/Sportarr,
Listenarrs/Listenarr}, docs.tdarr.io Docker compose page, quay.io tag API,
Docker Hub tag API, GitHub releases API, nixpkgs option search (stable +
unstable) via the NixOS MCP server, and the repo's own precedent modules.
Context7: none of these are libraries added as flake dependencies; no flake
input is added.

## Design (Option B: one file per service, no role-gating `mkIf`)
- `tdarr.nix`: native module. `server.enable`, `nodes.local.enable =
  cfg.node.enable`, `openFirewall`, `mediaMounts`; backup path = `services.tdarr.dataDir`.
- `sportarr.nix`, `listenarr.nix`: bookshelf-style single container; options
  `port`, `dataDir`, `libraryDir` (+ `downloadsDir` for Listenarr), `userId`,
  `groupId`, `mediaMounts`, `openFirewall`; tmpfiles for bind mounts; backup
  `dataDir` only.
- `mediamanager.nix`: joplin-style two containers on `mediamanager-net`;
  `adminEmails` (asserted non-empty), `frontendUrl`, `dataDir`, `libraryDir`,
  `mediaMounts`, `environmentFile`, `openFirewall`; auto-generated
  `dataDir/secrets/mediamanager-env` (0600); no tmpfiles rule for `postgres/`
  (image chowns it); nightly `pg_dump` via `dump-timer.nix`; backup `dump/` and `config/`.
- `default.nix`: import all four. `template/server-services.nix`: document them.

## Out of scope
justfile `just enable` lists (bookshelf is also absent); Tdarr GPU
transcoding; reverse-proxy registration in `proxy.nix`.

## Risks and mitigations
- MediaManager non-root support undocumented → run as image default, root-owned mounts.
- Listenarr rolling `canary` tag → documented in module header.
- Tdarr systemd unit names → verified by evaluating the config.
- Forbidden commands: only `nix eval`/`nix build`/preflight are used; never
  `nix flake check` or `nixos-rebuild switch|boot`.
