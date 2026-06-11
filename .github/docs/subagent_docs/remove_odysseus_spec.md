# remove_odysseus — Specification

## Decision

Remove the Odysseus module entirely from vexos-nix.

## Rationale

Odysseus is a Python FastAPI app that requires building from source (no published
Docker image). The module implemented this via a runtime `git clone --depth 1` of
a moving HEAD ref followed by a `docker-compose up --build` on every service start,
running as root. This pattern:

- Is a supply chain security risk (unverified, unpinned remote code built as root)
- Cannot be made fully declarative without translating ~50 Python deps to Nix
- Never successfully built due to hash/build issues
- Does not belong in a declarative NixOS configuration

Odysseus is better run ad-hoc via `docker compose` when needed. Docker is available
on server roles and the upstream README documents the manual procedure clearly.

## Files to Change

- `modules/server/odysseus.nix` — delete
- `modules/server/default.nix:42` — remove `./odysseus.nix` import line
- `template/server-services.nix:158-160` — remove odysseus comment block
