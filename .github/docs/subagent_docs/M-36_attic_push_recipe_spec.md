# M-36 — `just attic-push`: push custom packages to a configured Attic cache

Status: Phase 1 (Research & Specification)
Source: MASTER_PLAN M-36 (FEATURES 4.1) · `modules/nix.nix:25-46`

## Scope decision (confirmed with user)

The plan's original ask was CI automation (build `pkgs/*` in GitHub Actions,
push via a repo-secret Attic token). Investigated first and found there is
**no project-owned Attic cache today** — `vexos.attic.cacheUrl` defaults to
`null`; this is purely a client-side option for each operator to point at
their *own* self-hosted `vexos.server.attic` instance (or none). No repo
secret, no stable public URL, nothing for CI to push to.

Raised this with the user, who then asked the more fundamental question:
is the existing Attic wiring (client substituter config + server module)
actually correct if they choose to enable it later? Verified both sides
directly against the upstream `atticd` NixOS module source:

- **Client** (`modules/nix.nix`): correctly wired — substituter and
  trusted-public-key are conditionally added, with an assertion requiring
  `publicKey` whenever `cacheUrl` is set. No issues found.
- **Server** (`modules/server/attic.nix`): correctly wired — `dataDir`
  defaults to exactly `/var/lib/atticd`, which matches atticd's own
  `StateDirectory = "atticd"` (systemd creates/owns it automatically; the
  upstream module only needs extra `ReadWritePaths` for a *non-default*
  storage path, which doesn't apply here). No missing tmpfiles rule, no
  permission gap.
- **The actual gap**: there is no *push* mechanism anywhere in the repo —
  nothing populates the cache with a built package in the first place.
  `modules/server/attic.nix`'s comment and the `just enable attic` info text
  (`justfile`) only document `attic login`/manual `attic push <cache> <path>`
  for arbitrary derivations — nothing specific to this repo's own
  `pkgs/*` custom packages.

Given the user isn't committed to running a persistent, CI-reachable
instance yet, scoped this down from "CI job + secret" to: **a local `just`
recipe that builds and pushes this repo's own custom packages to whatever
cache the operator has already configured and logged into** — works the
moment they stand up any Attic server, no CI/secrets commitment required.

## Current State

`pkgs/default.nix` exposes 7 packages under the `vexos.*` overlay namespace
(`cockpit-navigator`, `cockpit-file-sharing`, `cockpit-identities`,
`brave-origin`, `kiji-proxy`, `portbook`, `vexos-update`). These are NOT
exposed as standalone flake `packages.<system>.<name>` outputs — only via
the overlay applied inside each `nixosConfiguration`'s `pkgs` set
(`pkgs.vexos.<name>`). Since each is a plain `final.callPackage ./x { }`
with no NixOS-config-dependent arguments, the resulting store path is
identical regardless of which `nixosConfiguration` it's pulled through —
confirmed by inspecting `pkgs/default.nix` (no host-specific parameters
passed to any of the 7 `callPackage` calls).

## Proposed Solution

Add `just attic-push [cache]` (default cache name `vexos`, matching
`modules/nix.nix`'s own doc example). Builds all 7 `pkgs.vexos.*` packages
via a fixed reference `nixosConfiguration`
(`vexos-desktop-amd` — arbitrary but representative, since output is
identical across configs) using `nix build --print-out-paths`, then runs
`attic push <cache> <path>` for each resulting store path. Assumes the
operator has already run `attic login <cache> <url> <token>` once (existing
`just enable attic` guidance already documents this) — the recipe checks
for the `attic` CLI on `PATH` and fails with a clear message if missing,
rather than silently doing nothing.

## Implementation Steps

1. `justfile` — add `attic-push` recipe under a new `[group('Binary Cache')]`.
2. `modules/server/attic.nix` — add a one-line pointer to the new recipe in
   the existing header comment, alongside the existing `attic login` note.

## Configuration Changes

None — a new opt-in `just` recipe; no NixOS module/option changes.

## Risks and Mitigations

- **Risk:** running the recipe without ever having configured/logged into
  an Attic cache would fail confusingly deep inside the `attic push` call.
  **Mitigation:** recipe checks `command -v attic` up front and prints a
  clear error (pointing at `just enable attic`'s existing login guidance)
  before attempting any build.
- **Risk:** assuming all 7 packages build identically regardless of which
  `nixosConfiguration` they're pulled from.
  **Mitigation:** verified directly in `pkgs/default.nix` that none of the
  7 `callPackage` invocations receive host-specific arguments — confirmed
  in Phase 3 by building all 7 via `vexos-desktop-amd`'s `pkgs.vexos.*` and
  cross-checking one (`vexos-update`, already built earlier this session via
  `vexos-desktop-amd`) has the same store path as previously observed.
