# M-34 — cockpit-zfs NAS Phase B — re-check packageability

Status: Phase 1 (Research & Specification)
Source: MASTER_PLAN M-34 (FEATURES 1.4) · `modules/server/nas.nix:16-19`,
`modules/server/cockpit.nix:13-17`

## Current State

`modules/server/nas.nix` and `modules/server/cockpit.nix` both carry a
deferred-feature comment: cockpit-zfs was excluded because, at the time that
comment was written, upstream v1.2.26 used "a Yarn Berry v4 monorepo with
unresolved workspace: deps in the zfs/ package-lock.json, making sandbox
builds infeasible."

Per the plan's own instruction ("Re-check 45drives/cockpit-zfs
packageability"), re-checked directly against this repo's pinned nixpkgs
rather than trusting the old comment:

- `pkgs.cockpit-zfs` **now exists** as an attribute in the pinned nixpkgs
  (version `1.2.27-3`, not marked `meta.broken`) — this is new since the
  original comment was written; the workspace-dependency resolution issue
  described in the old comment appears to have been fixed upstream.
- **Actually built it** (`nix build` against the pinned nixpkgs rev) to
  verify, rather than trusting attribute existence alone: the build **fails**
  with a different, unrelated error — a Tailwind/PostCSS build failure in the
  shared `@45drives/houston-common-ui` workspace
  (`[vite:css] [postcss] Cannot convert undefined or null to object`,
  in `ToggleSwitchGroup.vue`'s scoped style compilation) that aborts before
  `cockpit-zfs` itself ever builds, since Yarn workspaces refuses to proceed
  when a dependency-of a workspace fails.

## Problem Definition

cockpit-zfs is closer to buildable than before (the specific blocker named in
the existing comment has been resolved), but it is still not buildable at
this pinned nixpkgs revision — a different, upstream CSS build bug now blocks
it. Per the plan's own explicit conditional ("if buildable: add ...; " —
implying no changes if not), no functional integration should be added yet.

## Proposed Solution

Documentation-only update: refresh the deferral comments in `nas.nix` and
`cockpit.nix` with the current, more specific blocking reason (verified via
an actual build attempt, not assumption), so a future re-check doesn't have
to redo this investigation from the stale "Yarn Berry v4 workspace: deps"
description. No sub-option, no `pkgs/cockpit-zfs/`, no `nas.nix` line added —
the reserved landing site stays reserved, per the plan's own "if buildable"
condition not being met.

## Implementation Steps

1. `modules/server/cockpit.nix` — update the comment block (currently lines
   13-17) with the current build-failure reason and the pinned nixpkgs
   version tested against.
2. `modules/server/nas.nix` — update the comment block (currently lines
   16-19) similarly.

## Configuration Changes

None — comments only, zero functional/option changes. Both files are shared
with the working Samba/NFS file-sharing configuration (per standing project
notes on SMB fragility); confirmed the edit touches only the header comment
block, not any line inside `options`/`config`.

## Risks and Mitigations

- **None functionally** — comment-only change. Re-ran the full Phase 3
  validation battery (including the server-role dry-builds this file's
  Samba/NFS logic requires) to confirm zero behavior change, out of caution
  given this file's role in the working SMB setup.
