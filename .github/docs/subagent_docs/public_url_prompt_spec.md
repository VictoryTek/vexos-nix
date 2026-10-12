# Public-URL prompt for `just service enable` + `just service set-url`

## Current state analysis

Six server modules expose an option holding the externally visible URL:

| Service        | Option                              | Default                          | Fed to                          | Notes |
|----------------|-------------------------------------|----------------------------------|---------------------------------|-------|
| wishlist       | `vexos.server.wishlist.origin`      | `http://<hostName>:3280`         | `ORIGIN` (SvelteKit CSRF check) | wrong value => 403 on login behind a proxy |
| joplin         | `vexos.server.joplin.baseUrl`       | `http://<hostName>:22300`        | `APP_BASE_URL`                  | wrong value => "invalid origin" sync errors |
| mediamanager   | `vexos.server.mediamanager.frontendUrl` | `http://<hostName>:8000`     | `MEDIAMANAGER_MISC__FRONTEND_URL` (also CORS origin) | |
| arcane         | `vexos.server.arcane.appUrl`        | `http://localhost:3552`          | `APP_URL`                       | default uses `localhost`, not hostName |
| vaultwarden    | `vexos.server.vaultwarden.domain`   | `https://vault.example.com`      | `DOMAIN`                        | placeholder + build assertion: **required** |
| headscale      | `vexos.server.headscale.serverUrl`  | `https://headscale.example.com`  | `server_url`                    | placeholder + build assertion: **required** |

Not included (no URL-shaped option): forgejo (`ROOT_URL` hard-coded, no option),
nextcloud (`hostName`, a bare name), homepage (`allowedHosts`, host:port list),
paperless, immich. Changing/adding options is out of scope ("do not change defaults").

`just service enable <svc>` (`just/server-enable.just`, `_service-enable`) asks
per-service questions inline (`read -r -p`, `nix_set` to `/etc/nixos/server-services.nix`),
refuses in a non-tty for the services listed in its `case` guard, and exits early
with "already enabled" when the flag is already true. None of these six asks for
the URL. `scripts/migrate-services.sh` does **not** exist in this repo, and no other
script/recipe writes these options (grepped scripts/, pkgs/, just/*.just, lib/).

## Problem

Behind a reverse proxy the default `http://<host>:<port>` is wrong and breaks the
app; the operator has to hand-edit `server-services.nix`.

## Proposed solution

1. `just/lib.sh` gains three small helpers (shared by enable and set-url):
   - `nix_get_str FILE OPTION` — print the value of an uncommented `OPTION = "...";`.
   - `public_url_info SERVICE` — one `case` table: prints `option|default-port|default-host|required`
     for the six services above, returns 1 for any other service.
   - `prompt_public_url FILE SERVICE` — the prompt/validate/write flow.
2. `_service-enable` calls `prompt_public_url` next to the other per-service
   prompts (before `✓ Enabled`). When the service is already enabled it prints a
   one-line hint pointing at `set-url` if the option is not set.
3. New `just service set-url <svc>` (`_service-set-url` in `just/server.just`, one
   new `_menu` item) runs the same helper for an already-enabled service.

### Behaviour of `prompt_public_url`

- Prompt: `Public URL for <svc> (the address users type, e.g. https://<svc>.example.org). Press Enter to keep the default <default>:`
  where `<default>` is `http://<hostname>:<port>` (`localhost` for arcane). `<port>` is the
  `vexos.server.<svc>.port` value from server-services.nix if set, else the module default.
- Enter => keep default, write nothing (optional services).
- Otherwise: trailing `/` stripped, must match `^https?://` followed by a host and only
  characters safe inside a Nix string and the sed replacement (no space, `"`, `\`, `$`); invalid => re-ask.
- Write: `nix_set FILE vexos.server.<svc>.<option> "\"<url>\""`.
- Option already set to a string => show it, ask `Change it? [y/N]`; `n` leaves it.
- Non-interactive stdin (VexPortal daemon, stdin closed): the prompt is **skipped** with a
  hint to run `just service set-url <svc>`. The enable `case` refuse-list is deliberately
  NOT extended, so daemon-driven enable keeps working exactly as before.
- vaultwarden / headscale: their default is an intentionally invalid placeholder guarded by a
  build assertion, so Enter cannot "keep the default" usefully. For these two the prompt
  says `(required)` and re-asks on empty input instead of writing nothing.

## Dependencies

None new. Shell only. No Context7 lookup needed (no new libraries).

## Risks and mitigations

- Arcane previously had a *mandatory* URL prompt removed (arcane_appurl_autodefault_spec.md)
  because it blocked first use. This prompt is optional (Enter skips), so it does not
  reintroduce that block; the stale "no prompt is needed" comment is updated.
- Port override read by grep: falls back to the module default when the line is absent.
- `just` recipe names are a VexPortal contract: only an additive menu item and a new
  private recipe are introduced; no existing recipe/parameter changes.
- shellcheck `-S warning` runs over `just/lib.sh` and recipes in preflight; helpers print
  results rather than setting globals to avoid SC2034.
