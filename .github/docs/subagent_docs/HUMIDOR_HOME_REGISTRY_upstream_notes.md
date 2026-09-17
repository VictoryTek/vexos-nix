# Upstream notes — humidor / home-registry

Observations from wiring these two apps into NixOS modules that are worth
fixing in the app repos themselves (both are the user's own projects:
github.com/VictoryTek/humidor, github.com/VictoryTek/home-registry). None
of these block the NixOS module — they're just things that would make
future config cleaner.

## humidor

- **`DATABASE_URL` only, no discrete connection vars.** The app reads a
  single composed `DATABASE_URL` rather than separate `POSTGRES_HOST` /
  `POSTGRES_USER` / `POSTGRES_PORT` / `POSTGRES_DB` vars. This forces any
  orchestration layer (NixOS module, k8s, etc.) that wants to keep the
  password in a separate secret from the rest of the config to pre-compose
  the full URL string itself — you can't just drop in a password file and
  let the app assemble the connection string from named parts. Consider
  supporting both: read `DATABASE_URL` if set, otherwise assemble from
  `POSTGRES_HOST`/`POSTGRES_USER`/`POSTGRES_PASSWORD`/`POSTGRES_PORT`/
  `POSTGRES_DB`. This is the same pattern most 12-factor Rust web apps use
  (e.g. sqlx's own examples show both paths).
- No documented default login / first-run account creation flow was found
  in the repo's README — worth confirming whether first visit requires
  registration or ships a default account, and documenting it either way
  (Joplin, for comparison, documents `admin@localhost` / `admin`).

## home-registry

- **Same `DATABASE_URL`-only issue** as humidor — same recommendation
  applies.
- **`POSTGRES_USER` and `POSTGRES_DB` are hardcoded** in `docker-compose.yml`/
  `docker-compose.prod.yml` (`postgres` / `home_inventory`), unlike
  humidor's `humidor_user`/`humidor_db` which are at least
  environment-overridable in its own compose file. This means a NixOS (or
  any) module wiring this app up has zero flexibility on DB naming without
  patching the app's own compose assumptions — every deployment is stuck
  with a Postgres role literally named `postgres` for an app-specific
  database, which is unusual (most self-hosted apps use a dedicated,
  least-privilege DB role matching the app name). Consider making these
  configurable via `POSTGRES_USER`/`POSTGRES_DB` env vars in the compose
  file the same way humidor already does, and using a dedicated
  `home_registry` role instead of `postgres` (the superuser role) for the
  app's own connection.
- `docker-compose.yml` (dev) bakes a **hardcoded fallback password**
  (`uK8m3NvQ7wPxRj2Y5tLz`) directly into the compose file as the
  `POSTGRES_PASSWORD` default. It's clearly intended as a dev-only
  convenience with a big warning comment, but a hardcoded credential
  checked into a public repo is still worth avoiding — even for local dev,
  generating a random one at `docker compose up` time (e.g. via a
  `.env`-only default with no compose-level fallback) removes the
  temptation to reuse it anywhere real.
