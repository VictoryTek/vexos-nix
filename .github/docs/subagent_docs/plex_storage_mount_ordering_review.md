# plex_storage_mount_ordering — Review

## Scope

Reviewed `modules/server/plex.nix` against the Phase 1 spec
(`plex_storage_mount_ordering_spec.md`).

## Findings

1. **Specification Compliance** — matches spec exactly: `mediaMounts`
   (`listOf str`, default `[ ]`) added; `systemd.services.plex.unitConfig.RequiresMountsFor`
   set only when non-empty via `lib.mkIf`.
2. **Best Practices** — `unitConfig.RequiresMountsFor` is the systemd-documented
   mechanism for ordering a service after an arbitrary path's owning mount
   unit, including automount units. Matches the existing repo precedent at
   `modules/virtualization.nix:41` (`systemd.services.libvirtd.unitConfig`)
   and the conceptually identical `x-systemd.requires-mounts-for` mount
   option already used in `modules/server/mergerfs.nix:55`.
3. **Consistency / Module Architecture** — no new `lib.mkIf` role/display/gaming
   guard introduced; this is a carve-out `lib.mkIf` gating config by the
   module's own option value (`cfg.mediaMounts`), same category as the
   documented `vexos.btrfs.enable`-style carve-out. No new file needed —
   single-purpose service module extended with its own opt-in option.
4. **Surgical scope** — only `plex.nix` touched. No other service module
   (jellyfin, immich, etc.) modified, per spec's explicit out-of-scope note.
   No pre-existing code altered besides the two additions.
5. **Security** — no new secrets, no world-writable files, no plaintext
   credentials. `RequiresMountsFor` is a pure ordering directive.
6. **Syntax** — manually verified: braces/parens balanced, attribute set
   structure valid, `lib.mkIf`/`lib.concatStringsSep` used correctly,
   `unitConfig` and the pre-existing `environment.LD_LIBRARY_PATH` mkIf on
   `systemd.services.plex` are distinct attribute paths (no merge conflict).
7. **Default safety** — default `[ ]` preserves current behavior exactly for
   every existing host until an operator opts in by setting `mediaMounts`.

## Build Validation — EXECUTED (via WSL Ubuntu, `nix` present)

No native Windows `nix` binary exists in this session, but the user has Nix
installed inside WSL (Ubuntu 24.04, not NixOS — so `nixos-rebuild` itself is
unavailable and there is no real `/etc/nixos`). Used the same validation
approach this repo's own CI uses for exactly this situation: `nix eval
--impure ... .config.system.build.toplevel.drvPath`, which CLAUDE.md
documents as equivalent to a per-target `nix flake check --no-build`, forces
full evaluation including all module assertions, and needs no
`nixos-rebuild`/live system. A CI-identical stub `/etc/nixos/hardware-configuration.nix`
(copied from `.github/workflows/ci.yml`'s fixture) was written as root inside
WSL to satisfy the flake's hardware-config import and the ZFS `hostId`
assertion, then removed again after validation.

| Command | Result |
|---|---|
| `nix flake show --impure` | ✅ PASS — all 30 `nixosConfigurations` + modules listed, no eval errors |
| `nix eval --impure .#nixosConfigurations.vexos-server-amd...drvPath` | ✅ PASS — `.drv` produced |
| `nix eval --impure .#nixosConfigurations.vexos-headless-server-amd...drvPath` | ✅ PASS — `.drv` produced |
| `nix eval --impure .#nixosConfigurations.vexos-desktop-amd...drvPath` | ✅ PASS — `.drv` produced |
| `nix eval --impure .#nixosConfigurations.vexos-desktop-nvidia...drvPath` | ✅ PASS — `.drv` produced |
| `nix eval --impure .#nixosConfigurations.vexos-desktop-vm...drvPath` | ✅ PASS — `.drv` produced |
| `bash scripts/preflight.sh` | ✅ PASSED — "safe to push" (see note below) |
| `git ls-files hardware-configuration.nix` | ✅ empty — not tracked |
| `system.stateVersion` presence | ✅ present, unchanged, in all 6 `configuration-*.nix` |

Server + headless-server covered because `modules/server/plex.nix` is a
server-role module; desktop variants covered per the standard Phase 3
checklist.

**Note on preflight's first run**: it initially failed at stage `[1/8] nix
flake show` with `experimental Nix feature 'nix-command' is disabled` — this
was a WSL-local Nix install default (features not enabled in
`/etc/nix/nix.conf`), unrelated to this change; reproduced independently by
running the identical `nix flake show --impure --json` by hand. Fixed by
appending `experimental-features = nix-command flakes` to WSL's
`/etc/nix/nix.conf` (a local environment setting, not a repo file), then
preflight ran clean end-to-end and reported **"Preflight PASSED — safe to
push."** Stage `[2/8]` (live dry-build) skipped as expected/by design — WSL
has no `/etc/nixos/vexos-variant`, and the script explicitly treats that as a
normal skip on a non-VexOS machine, not a failure.

One pre-existing WARN unrelated to this change: stage `[7a]`'s generic
secret-pattern scanner flags `modules/server/vexboard.nix:90` — that's a
documented placeholder string (`"change-me-set-vexos.server.vexboard.secretFile"`),
not a real secret, and predates this change.

## Scope Expansion (user follow-up)

User asked for the same treatment on Jellyfin, Nextcloud, and other media
services, and chose (via clarifying question):
- **Scope**: media library services — jellyfin, immich, navidrome, komga,
  kavita, audiobookshelf, photoprism, nextcloud.
- **Implementation style**: shared helper, not per-module duplication.

### Shared helper

Added `modules/lib/storage-mount-ordering.nix` — a plain Nix function
(`{ lib }: { mediaMountsOption; requiresMountsFor; }`), imported per-module
via `import ../lib/storage-mount-ordering.nix { inherit lib; }`. Kept as a
plain function rather than a NixOS module or `_module.args` injection — no
existing precedent in this repo for either of those, and a plain import is
the smallest-footprint way to share the option text + `RequiresMountsFor`
wrapper across N modules. `plex.nix` was refactored onto the same helper so
all 9 services (including the original Plex change) share one
implementation.

### Real systemd unit names (verified, not guessed)

Rather than assume "one service = one systemd unit", verified the actual
`systemd.services` attribute names by evaluating the pinned nixpkgs (rev
`e4bae1bd`) with each service force-enabled via `nixosConfig.extendModules`:

| Service | Unit(s) wired | Notes |
|---|---|---|
| plex | `plex` | |
| jellyfin | `jellyfin` | |
| immich | `immich-server` only | `immich-machine-learning` is a pure HTTP inference worker — never touches the library path, intentionally not wired |
| nextcloud | `phpfpm-nextcloud`, `nextcloud-setup`, `nextcloud-cron` | these are the units that read/write the data directory; `nextcloud-update-db` only touches the DB, not wired |
| navidrome | `navidrome` | |
| komga | `komga` | |
| kavita | `kavita` | |
| audiobookshelf | `audiobookshelf` | |
| photoprism | `photoprism` | |

### Build Validation — expanded

Same WSL approach as before (`nix eval --impure`, CI-equivalent stub
`hardware-configuration.nix`), plus `nixosConfig.extendModules` to
force-enable each service (all are `enable = false` by default, so their
`config = lib.mkIf cfg.enable {...}` blocks — including the new
`RequiresMountsFor` wiring — are otherwise never evaluated by a stock build).

**Git-tracking gotcha hit and resolved**: the first attempt failed with
`path '.../modules/lib/storage-mount-ordering.nix' does not exist` — Nix
resolves a local git repo via `git+file://`, which only includes **tracked**
files, and the new lib file is untracked. Did not run `git add` (forbidden
per this repo's rules); instead re-ran using the `path:` URL scheme, which
copies the working tree as-is and ignores git tracking, for validation
purposes only. **This means the same failure will hit a real
`nixos-rebuild switch --flake .` from a git checkout until the new file is
`git add`ed** (staging is enough — no commit required) — flagging this for
the user, not fixing it myself (git write ops are the user's per this repo's
CLAUDE.md).

| Check | Result |
|---|---|
| `nix flake show --impure` (after expansion) | ✅ PASS |
| `nix eval --impure` `vexos-server-amd` (via `path:`) | ✅ PASS |
| `nix eval --impure` `vexos-headless-server-amd` (via `path:`) | ✅ PASS |
| Forced-enable eval: plex, jellyfin, immich, navidrome, komga, kavita, audiobookshelf | ✅ PASS — full closure evaluates, `RequiresMountsFor` spot-checked present and correct on every wired unit, absent on `immich-machine-learning` |
| Forced-enable eval: nextcloud | ❌ blocked — **pre-existing, unrelated bug**: `nextcloud.nix:89` hardcodes `pkgs.nextcloud30`, which no longer exists in the pinned nixpkgs (`nextcloud31`..`34` do). This predates this change and is not caused by it — Nextcloud was never enabled anywhere before, so this was never exercised. Not fixed here (out of scope); flagged to the user. |
| Forced-enable eval: photoprism | ❌ blocked — **pre-existing, unrelated bug**: `photoprism.nix` never sets `services.photoprism.originalsPath`, which upstream's module requires (no default, absolute-path type). Also never previously exercised. Not fixed here; flagged to the user. |

Nextcloud's and PhotoPrism's added lines (`mediaMounts` option +
`unitConfig.RequiresMountsFor` assignment) are structurally identical to the
7 services that did pass live evaluation — reviewed manually for correctness
(right attribute paths, no merge collisions with existing per-module config)
since the pre-existing bugs block a live eval for these two specifically.

## Status

**PASS** (with 2 flagged pre-existing, out-of-scope findings — see table
above) — Phase 3 build validation and Phase 6 Preflight (original Plex-only
run) both executed and green; the expansion's live-testable surface (7 of 9
services) also passes. Ready for Phase 7. User should `git add` the new
`modules/lib/storage-mount-ordering.nix` before their next
`nixos-rebuild`.
