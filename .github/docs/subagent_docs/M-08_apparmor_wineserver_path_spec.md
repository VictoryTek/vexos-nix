# M-08 — AppArmor wineserver profile attaches to a nonexistent path

Status: Phase 1 (Research & Specification)
Source: MASTER_PLAN M-08 · `modules/gaming.nix:165-178`

## Current State

```nix
security.apparmor.policies."usr.bin.wineserver".profile = ''
  ...
  /usr/bin/wineserver flags=(complain) {
  ...
'';
```

`/usr/bin/wineserver` does not exist on NixOS — package binaries live under
`/nix/store/<hash>-<name>/bin/...`, never at FHS paths like `/usr/bin`. AppArmor
profiles attach by exact path (or glob); since this literal path never matches any real
file on the system, the profile never attaches to anything — the complain-mode
monitoring this block exists to provide (per its own comment: "misused by a compromised
Wine prefix... deviations from normal operation appear in audit logs") silently never
activates.

## Problem Definition

Point the profile at wineserver's actual location so it can attach at all.

## Proposed Solution

The MASTER_PLAN suggests a glob (`/nix/store/*-wine-*/bin/wineserver`). A more precise
option is available here: `pkgs.wineWow64Packages.stagingFull` is already referenced
elsewhere in this same file (line 80, `environment.systemPackages`) as the actual Wine
package installed — its exact store path is known at Nix-eval time. Using
`${pkgs.wineWow64Packages.stagingFull}/bin/wineserver` as the profile's attachment path
is strictly more precise than a glob: it matches only the real, actually-installed
binary, ties the profile automatically to whichever Wine build is actually in use (no
separate glob to keep in sync if the package changes), and avoids any AppArmor
glob-matching ambiguity entirely.

## Implementation Steps

1. `modules/gaming.nix` — replace the literal `/usr/bin/wineserver` inside the profile
   body with the interpolated `${pkgs.wineWow64Packages.stagingFull}/bin/wineserver`.

## Configuration Changes

None.

## Risks and Mitigations

- **Deviates from the MASTER_PLAN's literal glob suggestion** — documented above why
  the interpolated exact path is a strictly better realization of the same intent
  (attach to the real binary); not a scope change, same fix goal.
- **Verify the interpolated path is syntactically valid inside the `''...''` Nix
  string** (which already contains AppArmor's own `@{...}` variable syntax, unrelated
  to Nix's `${...}` interpolation) — confirmed by building the actual profile string via
  `nix eval` and checking the rendered text contains a real, existing store path.
