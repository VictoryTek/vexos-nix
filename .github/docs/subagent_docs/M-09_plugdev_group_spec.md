# M-09 — `plugdev` group membership is a silent no-op

Status: Phase 1 (Research & Specification)
Source: MASTER_PLAN M-09 · `modules/gaming.nix:142`

## Current State

```nix
users.users.${config.vexos.user.name}.extraGroups = [ "gamemode" "input" "plugdev" ];
```

`plugdev` is never declared anywhere (`users.groups.plugdev` doesn't exist, confirmed by
repo-wide grep — `plugdev` appears in exactly this one line, nowhere else). NixOS
doesn't hard-fail at build time when `extraGroups` references an undeclared group (no
such assertion exists in `nixos-groups.nix`); it's a silent activation-time no-op —
`usermod`/`update-users-groups` simply has nothing to add the user to.

Repo-wide grep also confirms every `services.udev.extraRules` entry in this same file
(all the DualShock/DualSense/etc. controller rules) already grants device access via
`GROUP="input"`, which *is* a real, standard group. Nothing in this codebase's udev
rules ever targets `GROUP="plugdev"` — the membership doesn't correspond to any actual
access-control rule here.

## Problem Definition

Remove membership in a group that doesn't exist and isn't referenced by anything.

## Proposed Solution

Drop `"plugdev"` from the `extraGroups` list (the MASTER_PLAN's second option) rather
than declaring an empty `users.groups.plugdev = {};` — since no udev rule in this
project ever grants access via that group, creating it would just be an unused,
purposeless group with no functional effect, not a real fix.

## Implementation Steps

1. `modules/gaming.nix` — remove `"plugdev"` from the `extraGroups` list.

## Configuration Changes

None.

## Risks and Mitigations

- **None** — the membership was already inert; removing it changes no observable
  behavior on this system, since nothing here grants access via `plugdev`.
