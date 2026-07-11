# SearXNG Server Service — Specification

## Current State Analysis

- `modules/server/` contains one Nix file per optional server service, each exposing
  `vexos.server.<service>.enable` (default `false`) plus a small set of service-specific
  options (typically `port`, `openFirewall`, sometimes `environmentFile`). See
  `modules/server/ntfy.nix` and `modules/server/kiji-proxy.nix` for the closest analogues:
  self-contained services with no reverse-proxy wiring baked in.
- Reverse proxying (Caddy/Nginx/Traefik) is deliberately **not** configured inside
  individual service modules — `modules/server/caddy.nix` and `modules/server/nginx.nix`
  say virtual hosts are set up by the user in `/etc/nixos/server-services.nix`
  (host-local, not committed). SearXNG will follow the same pattern: it exposes its own
  port and does not touch `services.caddy`/`services.nginx` itself.
  ([[project_nix_git_index_untracked]] — `server-services.nix` is untracked and enables
  services at the host level.)
- All new modules are registered by adding one `./foo.nix` import line to
  `modules/server/default.nix` under the relevant category comment block. No role-specific
  wiring is needed — server services are opt-in via `server-services.nix`, not via
  `configuration-*.nix` imports, so this does not interact with the Option B module
  pattern beyond the single import line.
- Confirmed via local nixpkgs source
  (`nixos/modules/services/networking/searx.nix`) that `services.searx` is the current
  upstream NixOS module name for **SearXNG** (the module deploys the `searxng` package;
  "searx" is the retained legacy option-namespace name). Verified option surface:
  `enable`, `openFirewall`, `domain`, `environmentFile` (`nullOr path`), `redisCreateLocally`,
  `settings` (freeform, merged over SearXNG defaults via `use_default_settings`),
  `settingsFile`, `faviconsSettings`, `limiterSettings`, `package`, `configureUwsgi`,
  `configureNginx`.
- Key upstream behavior relevant to privacy hardening:
  - `configureUwsgi = false` (the default) runs SearXNG's built-in Werkzeug HTTP server,
    whose own option description explicitly warns: *"The built-in HTTP server logs all
    queries by default."*
  - `configureUwsgi = true` runs SearXNG under uWSGI instead, and uWSGI's own
    `disable-logging` flag can be set to suppress request logging entirely.
  - `server.method` in `settings.yml` controls whether search form submissions use GET
    or POST; POST keeps the query out of URLs (and therefore out of any surrounding
    access logs, proxy logs, browser history, or `Referer` headers).
  - `server.secret_key` is required by SearXNG itself for session/CSRF signing; upstream
    supports `$VAR` substitution in `settings.yml` sourced from `environmentFile` via
    `envsubst`.
  - Tor/SOCKS5 outbound proxying and per-engine timeout tuning are supported via
    `settings.outgoing.proxies` / `settings.outgoing.request_timeout` /
    `settings.outgoing.max_request_timeout`, and per-engine `weight` values are supported
    via `settings.engines`.
  - `redisCreateLocally` + `limiterSettings` enable a bot-detection/rate-limiter layer
    that requires Redis; not needed for a private single-user/LAN instance and adds a
    dependency, so it will be left disabled by default (matches upstream default).

## Problem Definition

Add SearXNG as a new opt-in server service, following the existing Option B module
pattern (self-contained module, single import line, activated via
`server-services.nix`), hardened by default for maximum privacy:
- No query logging (built-in server logging disabled; uWSGI request logging disabled).
- POST-based search submissions to avoid queries appearing in any log/URL surface.
- Local-only network exposure by default (`openFirewall = false`), since this is a
  personal instance, not a public one.
- No local telemetry/tracking: `server.method = "POST"`; no analytics options exist in
  SearXNG'; default upstream settings already ship with no query logging enabled.
- No reverse-proxy or bot-protection stack added — kept minimal per Simplicity First and
  per the project's established "the service exposes a port, the user wires the proxy"
  convention.

Out of scope (explicitly not requested, would violate Simplicity First / Surgical
Changes):
- Tor/SOCKS5 outbound routing — not requested by the user; would add a hard dependency
  on a local Tor daemon this repo does not currently provision. Left as a documented
  comment for future opt-in rather than implemented.
- Per-engine weight tuning (`google_news`, academic/news presets) — no default engine
  preferences were requested; upstream defaults apply.
- Nginx/Caddy virtual host wiring — out of pattern for this repo's service modules.
- Redis-backed rate limiter/bot detection — unnecessary overhead for a private instance.

## Proposed Solution Architecture

New file: `modules/server/searxng.nix`

```
{ config, lib, pkgs, ... }:
let
  cfg = config.vexos.server.searxng;
in
{
  options.vexos.server.searxng = {
    enable = lib.mkEnableOption "SearXNG private metasearch engine";

    port = lib.mkOption {
      type = lib.types.port;
      default = 8888;
      description = "Port for the SearXNG HTTP listener.";
    };

    openFirewall = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = ''
        Open the firewall for SearXNG's port. Defaults to false — this is a
        private instance intended for localhost/LAN reverse-proxy access, not
        direct public exposure.
      '';
    };

    environmentFile = lib.mkOption {
      type = lib.types.nullOr lib.types.path;
      default = null;
      description = ''
        Path to an environment file providing SEARXNG_SECRET_KEY, referenced
        from settings.yml as $SEARXNG_SECRET_KEY. Required for a working
        instance (SearXNG needs a secret key for session/CSRF signing). File
        should not be world-readable.
      '';
    };
  };

  config = lib.mkIf cfg.enable {
    services.searx = {
      enable = true;
      environmentFile = cfg.environmentFile;
      openFirewall = cfg.openFirewall;

      # uWSGI instead of the built-in Werkzeug server: the built-in server
      # logs all queries by default (see upstream configureUwsgi option
      # description). uWSGI + disable-logging avoids that entirely.
      configureUwsgi = true;
      uwsgiConfig = {
        disable-logging = true;
        http = ":${toString cfg.port}";
      };

      settings = {
        use_default_settings = true;
        server = {
          port = cfg.port;
          bind_address = "127.0.0.1";
          secret_key = "$SEARXNG_SECRET_KEY";
          method = "POST"; # keep queries out of URLs/logs/referrers
        };
        search = {
          safe_search = 0;
          autocomplete = "";
        };
      };
    };
  };
}
```

Registration: add `./searxng.nix` to `modules/server/default.nix`'s import list under a
new `# ── Search ───` category comment (or alongside an existing similar category —
final placement decided during implementation to match surrounding style).

### Notes on option choices

- `bind_address = "127.0.0.1"` combined with `openFirewall = false` by default means the
  service is loopback-only until the user either flips `openFirewall` or fronts it with
  a reverse proxy (Caddy/Nginx/Traefik modules already in this repo) — consistent with
  how `caddy.nix`/`nginx.nix` document virtual-host wiring living in
  `server-services.nix`, not in the service module itself.
- `secret_key` is sourced from an environment variable rather than hardcoded, avoiding a
  plaintext credential in a committed file (Phase 3 security checklist item).
- No `services.nginx`/`services.caddy` touched by this module — avoids coupling to
  whichever reverse proxy the user has chosen, matching existing convention.

## Implementation Steps

1. Create `modules/server/searxng.nix` per the architecture above.
2. Add `./searxng.nix` to `modules/server/default.nix` import list.
3. No changes to `configuration-*.nix`, `flake.nix`, or GPU modules — this is purely an
   opt-in server service module, activated by the user via `server-services.nix` (host
   -local, untracked file), matching every other module in `modules/server/`.
4. No new flake inputs — `services.searx` (SearXNG) is already available in nixpkgs;
   confirmed present in the `nixpkgs` input already pinned by this flake.

## Dependencies

- `services.searx` NixOS module — ships in nixpkgs (already a flake input, no new
  dependency). Verified present via local `nix eval` against the pinned nixpkgs source
  and by reading `nixos/modules/services/networking/searx.nix` directly from the pinned
  input's store path.
- No new flake inputs required.

## Configuration Changes

- New module file `modules/server/searxng.nix`.
- One new import line in `modules/server/default.nix`.
- End-user activation (not part of this change, host-local):
  ```nix
  # /etc/nixos/server-services.nix
  { vexos.server.searxng.enable = true; }
  ```

## Risks and Mitigations

| Risk | Mitigation |
|---|---|
| `secret_key` left as a literal string in a tracked file | Sourced via `$SEARXNG_SECRET_KEY` + `environmentFile` (user-supplied, host-local path), never hardcoded. |
| Built-in server logs every query | `configureUwsgi = true` + `uwsgiConfig.disable-logging = true` avoids the logging server entirely. |
| Accidental public exposure | `openFirewall` defaults to `false`; `bind_address` defaults to loopback. |
| GET-based queries leaking into proxy/browser logs | `server.method = "POST"`. |
| Redis/rate-limiter adds unnecessary attack surface/dependency for a private single-user instance | Left disabled (`redisCreateLocally` not set, defaults to `false`). |
