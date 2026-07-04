# M-12 — Attic help text instructs the wrong token algorithm

Status: Phase 1 (Research & Specification)
Source: MASTER_PLAN M-12 · `justfile` (`attic)` case in the post-enable info block, `modules/server/attic.nix`

## Current State

`justfile`'s post-`just enable attic` info block prints:
```
ATTIC_SERVER_TOKEN_HS256_SECRET_BASE64=<secret>
Generate secret:  openssl rand -base64 32
```

`modules/server/attic.nix`'s own header comment (the actual, correct source of truth
for what `atticd` requires) says:
```
ATTIC_SERVER_TOKEN_RS256_SECRET_BASE64=<secret>
Generate secret with: openssl genrsa -traditional 4096 | base64 -w0
```

atticd requires an RS256 RSA private key, not an HS256 symmetric secret — following the
justfile's current instructions would generate a value in the wrong format entirely
(`openssl rand -base64 32` produces random bytes, not a valid RSA key), which
`atticd` would reject at startup. This is also already correctly documented in a second
place in the same file — `secrets-sops.nix`'s sops secret name,
`attic-server-token-rs256-secret-base64` (justfile line ~1184) — confirming `rs256` is
the established, correct convention everywhere except this one help-text block.

## Problem Definition

Fix the justfile's help text to match `attic.nix`'s own (correct) documentation.

## Proposed Solution

Replace both lines exactly as the MASTER_PLAN specifies:
`ATTIC_SERVER_TOKEN_HS256_SECRET_BASE64` → `ATTIC_SERVER_TOKEN_RS256_SECRET_BASE64`,
and `openssl rand -base64 32` → `openssl genrsa -traditional 4096 | base64 -w0`.

## Implementation Steps

1. `justfile` — the `attic)` case in the post-enable info block: fix both lines.

## Configuration Changes

None.

## Risks and Mitigations

- **None** — this is a documentation-only string fix; no code path changes.
