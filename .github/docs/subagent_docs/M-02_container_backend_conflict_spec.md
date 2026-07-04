# M-02 — Container backend conflict between podman.nix and docker-backed modules

Status: Phase 1 (Research & Specification)
Source: MASTER_PLAN M-02 · `modules/server/podman.nix`, `modules/server/{dozzle,portainer,homepage,authelia,uptime-kuma,stirling-pdf,nginx-proxy-manager}.nix`
(all 8 files read in full)

## Current State

`podman.nix` sets `virtualisation.oci-containers.backend = "podman";` as a plain
(priority-100) assignment. Each of the seven docker-backed service modules
(`dozzle`, `portainer`, `homepage`, `authelia`, `uptime-kuma`, `stirling-pdf`,
`nginx-proxy-manager`) independently sets the *same option* to `"docker"`, also as a
plain (priority-100) assignment. NixOS's module system throws a hard eval error
("conflicting definition values") the moment podman is enabled alongside *any one* of
these seven services, since two modules define the identical option to different
values at the identical priority — a non-mergeable `str` option can't reconcile that.

## Problem Definition

Enabling `vexos.server.podman` together with any docker-backed service is a supported,
reasonable combination (podman with docker-compat handles both), but currently crashes
evaluation entirely.

## Proposed Solution

Change the seven docker-backed modules' `virtualisation.oci-containers.backend =
"docker";` to `virtualisation.oci-containers.backend = lib.mkDefault "docker";`
(priority 1000 — easily overridden). `podman.nix`'s assignment stays a plain
(priority-100) `"podman"`, so:
- podman alone: only definition present, applies normally.
- any docker-backed service alone: only definition present (`mkDefault "docker"`),
  applies normally.
- multiple docker-backed services together: all define the identical value
  (`"docker"`) at the identical priority (`mkDefault`, i.e. priority 1000) — NixOS
  permits multiple same-priority definitions of a non-mergeable option as long as they
  agree on the value, so this is not a conflict.
- podman + any docker-backed service together: podman's priority-100 `"podman"`
  outranks the docker modules' priority-1000 `mkDefault "docker"` — podman wins
  cleanly, no conflict, no eval error.

This is the standard, idiomatic NixOS pattern for "several modules agree on a sensible
default that a higher-priority module can override" — not a workaround, the correct
fix.

## Implementation Steps

1. `modules/server/dozzle.nix`, `portainer.nix`, `homepage.nix`, `authelia.nix`,
   `uptime-kuma.nix`, `stirling-pdf.nix`, `nginx-proxy-manager.nix` — change
   `virtualisation.oci-containers.backend = "docker";` to
   `virtualisation.oci-containers.backend = lib.mkDefault "docker";` (one line each,
   all seven files already have `lib` in their module arguments).
2. `modules/server/podman.nix` — no change; its plain-priority assignment is exactly
   what should win when podman is explicitly enabled.

## Configuration Changes

None — pure priority annotation change, no new options, no flake changes.

## Risks and Mitigations

- **Verify `lib` is already a module argument in all seven files** — confirmed by
  reading each file; all already destructure `{ config, lib, pkgs, ... }` or similar.
- **Confirm the fix actually resolves the conflict** — verified by forcing both podman
  and each docker-backed service on together via a synthetic build (see Build
  Validation in the review), not just assumed from the theory above.
