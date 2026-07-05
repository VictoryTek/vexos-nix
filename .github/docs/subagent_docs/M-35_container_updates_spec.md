# M-35 — `:latest` containers never actually update without an explicit pull

Status: Phase 1 (Research & Specification)
Source: MASTER_PLAN M-35 (FEATURES 3.1)

## Current State — re-checked directly, not assumed from the plan text

The user correctly flagged that M-22 (this session) already pinned all 7
OCI-container services that used to track `:latest`
(`portainer`, `homepage`, `stirling-pdf`, `authelia`, `nginx-proxy-manager`,
`dockhand`, `dozzle`) to specific version tags, and added
`.github/workflows/update-container-images.yml` — a Wednesday-scheduled,
direct-commit workflow that checks Docker Hub/GHCR for a newer matching tag
and rewrites the pin in place.

Re-grepped every `modules/server/*.nix` for `image = ".*:latest"` to check
what, if anything, still applies: **exactly one straggler** —
`modules/server/arcane.nix:79`, `image = "ghcr.io/getarcaneapp/manager:latest"`.
Arcane was added to this repo after M-22's pinning pass and was missed.

Checked GHCR directly for Arcane's actual published tags: the only
semver-shaped tag currently published is `v1.19.4` (others are `v1.19`/`v1`
floating majors, `next`/`development`/`pr-*` prerelease channels, and
digest-pinned `sha256-*` tags) — `v1.19.4` is the correct pin, matching this
repo's existing semver-pin convention (e.g. `dockhand:v1.0.36`).

## User's second point — no separate `just update-containers` recipe

Confirmed directly in `justfile`: `just update` and `just update-all` both
end in `sudo nixos-rebuild switch --flake path:/etc/nixos#$target` after
`nix flake update` (which bumps the `vexos-nix` flake input on the thin
`/etc/nixos` wrapper to the latest `main` commit). `just deploy` does the
same via `nix flake update vexos-nix` specifically (nixpkgs held pinned).

Since every OCI container's image tag is now a literal string baked into
this repo's own `modules/server/*.nix` (not fetched externally at runtime),
the existing pipeline already handles updates end-to-end with zero new
recipe needed:
1. `update-container-images.yml` runs weekly, bumps a stale pin, commits to
   `main`.
2. The next `just update` / `just update-all` / `just deploy` on any host
   pulls that new `vexos-nix` commit (containing the new pin) and runs
   `nixos-rebuild switch`.
3. `nixos-rebuild switch` diffs the `virtualisation.oci-containers`
   derivation — the changed image string changes the generated systemd unit,
   so NixOS recreates the container with the new image automatically. This
   is exactly the same mechanism the other 7 already-pinned services rely on
   today; nothing extra was needed for them, and nothing extra is needed for
   Arcane either once it's pinned.

So the plan's originally-proposed fix (a `just update-containers` recipe
that pulls each image and restarts its unit) would be solving a problem that
pinning already solves — confirmed with the user, who does not want a
separate recipe; updates should ride the same `update`/`update-all`/`deploy`
path as everything else.

## Proposed Solution

1. Pin `modules/server/arcane.nix`'s image to `ghcr.io/getarcaneapp/manager:v1.19.4`.
2. Add Arcane to `update-container-images.yml`'s tracked-services list (GHCR,
   same tag-regex style as `homepage`/`dockhand`).
3. No new `just` recipe — the existing `update`/`update-all`/`deploy`
   pipeline already covers this once every image is pinned.

## Implementation Steps

1. `modules/server/arcane.nix` — pin the image tag.
2. `.github/workflows/update-container-images.yml` — add Arcane's entry to
   `SERVICES` and update the header comment's service list/count (7 → 8).

## Configuration Changes

None beyond the pinned tag itself — same non-breaking category as M-22's
original pins (a fixed version replacing a moving one, same running
software).

## Risks and Mitigations

- **Risk:** `v1.19.4` might not be the version currently running in the
  field if a host already pulled a newer `:latest` digest before this pin
  lands.
  **Mitigation:** same accepted tradeoff as M-22's original 7 pins — the
  next `nixos-rebuild switch` converges every host to the same pinned
  version, which is the entire point of pinning.
