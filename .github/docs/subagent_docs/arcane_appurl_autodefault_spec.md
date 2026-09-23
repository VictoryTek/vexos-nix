# Arcane `appUrl` — remove interactive prompt, auto-default like every other service

## Current State Analysis

`modules/server/arcane.nix`:
- `options.vexos.server.arcane.appUrl` defaults to the placeholder string
  `"http://arcane.example.com"`.
- `config.assertions` (line 84-91) fails the build unless `cfg.appUrl !=
  "http://arcane.example.com"`, i.e. the user must set a real value.
- `environmentFile` (ENCRYPTION_KEY/JWT_SECRET) has an equivalent assertion,
  but is satisfied automatically — no user input required.

`justfile`, `enable service` recipe (lines 2846-2887):
- For `environmentFile`, SearXNG's `environmentFile`, and VexBoard's
  `secretFile`, the recipe auto-generates a random secret with `openssl rand`
  and writes it to `/etc/nixos/secrets/<name>` with no prompt — this is the
  established pattern for every service that needs a secret/config value it
  can synthesize itself.
- For Arcane's `appUrl` specifically (lines 2858-2869), the recipe instead
  blocks with an interactive `read -r -p "Enter the public URL..."` prompt.
  This is the only service in `_server_service_names` that requires typed
  input during `just enable <service>`.

## Problem Definition

The user enabled Arcane and was stopped by a prompt asking for a "public
URL" for an instance that is only ever accessed over the LAN (no reverse
proxy, no public exposure). They want `just enable arcane` to behave like
`just enable portainer`, `just enable searxng`, etc. — no interactive input,
fully declarative, ready to rebuild.

## Upstream Verification (Context7 — `/getarcaneapp/arcane`)

Confirmed via Arcane's own `.env.example` and `_autodocs/configuration.md`:
- `APP_URL` is used for link/redirect construction, CORS origin handling,
  and (if configured) OIDC callback URLs — it is not a listen-address or
  network-exposure setting. Arcane's own example value is a placeholder
  domain (`https://your-domain.com`), used for its own doc convention, not a
  functional requirement to be internet-reachable.
- These are optional/advanced-feature concerns (reverse-proxy + TLS, OIDC).
  A default single-host, LAN-only deployment (this project's default —
  `openFirewall = true`, no OIDC/reverse-proxy wiring anywhere in the
  server module set) does not depend on `APP_URL` being externally correct
  for basic container management to function, since the SPA and its API
  share the same origin (`http://<host>:3552`) in that case.

## Proposed Solution

1. **`modules/server/arcane.nix`**
   - Change `appUrl` default from the invalid placeholder to a working,
     non-interactive value: `lib.mkDefault "http://localhost:${toString
     cfg.port}"`. Still a plain `str` option — users who *do* reverse-proxy
     Arcane behind a real domain (Caddy/Traefik + OIDC) can override it in
     their own `server-services.nix`, same as any other option.
   - Drop the assertion requiring `appUrl` to differ from a placeholder
     (no longer applicable — the default is now a valid, working value, not
     a sentinel that must be replaced).
   - Update the file-header doc comment: remove `appUrl` from "Required
     configuration" (only `environmentFile` remains genuinely required, and
     that's already handled automatically).

2. **`justfile`** (`enable service` recipe)
   - Remove the `read -r -p "Enter the public URL..."` block (lines
     2858-2869). Arcane no longer needs special-cased URL handling — the
     module's own default satisfies the build.
   - Keep the `environmentFile` auto-generation block (lines 2871-2886)
     unchanged; it already matches the SearXNG/VexBoard pattern the user is
     not objecting to.
   - Update the comment above the block (lines 2848-2852) to reflect that
     Arcane now only needs the auto-generated secret, matching every other
     service.

## Implementation Steps (Module Architecture Pattern — Option B)

This is a same-module option/config change, not a new shared-vs-role-file
split — `modules/server/arcane.nix` is already a role-addition file (only
imported where Arcane is relevant) with no cross-role `lib.mkIf` guards
being added. No new files needed.

- Edit `modules/server/arcane.nix`: option default + assertion removal +
  header comment.
- Edit `justfile`: remove interactive prompt block + adjust comment.

## Dependencies

None added. Verified existing dependency (`ghcr.io/getarcaneapp/manager`)
behavior via Context7 as above — no version/package change.

## Configuration Changes

- `vexos.server.arcane.appUrl` now defaults to
  `http://localhost:<vexos.server.arcane.port>` instead of an invalid
  placeholder. Existing hosts that already set `appUrl` explicitly in their
  `server-services.nix` are unaffected (`lib.mkDefault` — explicit values
  still win).

## Risks and Mitigations

- **Risk:** A host that later puts Arcane behind a reverse proxy with a real
  domain and OIDC will silently keep working off the `localhost` default
  unless the operator remembers to set `appUrl` themselves.
  **Mitigation:** The option's own description text (already present,
  left intact) documents what `appUrl` is for and that it should be set to
  the real public URL for that scenario; this is consistent with how every
  other advanced/optional setting in this repo (e.g. `backend`,
  `environmentFile` path override) is self-service via `server-services.nix`,
  not enforced interactively.
- **Risk:** None to existing installs — `lib.mkDefault` never overrides a
  value a host has already set.
