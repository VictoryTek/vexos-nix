# TMOG (TaskManagerOG) — AppImage Package Spec

## Current State Analysis

- No existing package for TMOG (tmog.org). It ships only as a raw AppImage
  (`TaskManagerOG-<version>-x86_64.AppImage`), a `.deb`, and a `.tar.gz`, with no
  GitHub releases feed — downloads are served directly from `https://tmog.org/downloads/`.
- The repo already supports *running* arbitrary AppImages via `programs.appimage`
  (`modules/appimage.nix`, imported only by desktop + htpc) using `appimage-run` +
  binfmt. The user has flagged that this runtime path (and the adjacent
  GearLever-managed "drop an AppImage in and let the desktop integrate it" flow) has
  been unreliable before (e.g. the Crality print app never worked). This spec does
  **not** use that path.
- Precedent for packaging a pre-built third-party binary that isn't in nixpkgs exists
  at `pkgs/brave-origin/default.nix`: pinned `version`/`hash`, `autoPatchelfHook`,
  hand-written `.desktop`/icons, exposed via the `pkgs.vexos.*` overlay
  (`pkgs/default.nix`), consumed from `modules/packages-desktop.nix`, and kept current
  by a weekly GitHub Actions bump workflow
  (`.github/workflows/update-brave-origin-weekly-thursday.yml`) that builds before
  committing.
- `modules/packages-desktop.nix` is explicitly "GUI packages for roles with a display
  server (desktop, server, htpc, stateless). Do NOT import on headless-server." — the
  exact scope requested ("all roles except vanilla"), since headless-server has no
  display (same reason `upModule` in `flake.nix` excludes it) and vanilla is the
  deliberately minimal baseline.
- The GNOME "Utilities" app-folder (a dconf-defined app-grid folder, not a filesystem
  directory) is declared twice per role that has it — once as the system dconf default
  in `modules/gnome-<role>.nix`, and once in a home-manager first-run oneshot
  (`vexos-init-app-folders`) in `home-<role>.nix` that writes the live dconf tree once
  per stamp-file version (documented incident:
  `.github/docs/subagent_docs/game_utilities_folder_stamp_spec.md` — forgetting to bump
  the stamp means existing installs never see the addition). Present in exactly the 4
  desktop-server roles: desktop, htpc, server, stateless.

## Problem Definition

Add TMOG as a proper Nix package (not a raw user-managed AppImage) so it:
1. Installs on desktop, htpc, server, and stateless (all non-vanilla, non-headless
   roles — confirmed with the user; headless-server has no display to run/show it).
2. Appears as an icon in the GNOME "Utilities" app-folder on those 4 roles.
3. Updates through the normal system-update path (`just update` / the "Up" GUI, both of
   which call `pkgs/vexos-update`) rather than requiring the user to manually
   re-download and swap the AppImage.

## Proposed Solution Architecture

Package TMOG using `pkgs.appimageTools.wrapType2`, which extracts the AppImage's
squashfs payload at *build* time into the Nix store and produces a normal wrapped ELF
binary at `$out/bin/tmog`. At runtime there is no FUSE mount and no `appimage-run`/binfmt
involvement — this sidesteps the exact class of problem the user hit with the print-app
AppImage. `appimageTools.extractType2` is used to pull the AppImage's own bundled
`.desktop` file (`com.tmog.taskmanager.desktop`) and hicolor icon set
(32/48/64/128/256/512px, confirmed present inside the AppImage) so no icon needs to be
hand-drawn or sourced separately, unlike `brave-origin` which had to synthesize both.

Verified by downloading and extracting the current AppImage
(`TaskManagerOG-0.1.3-x86_64.AppImage`, sha256
`a8aa11f5e30a273250bcfb9247cc3117e830d6cffaf502961e93f12b3dd85827`, Nix SRI
`sha256-qKoR9eMKJzJQvPuSR8wxF+gw1s/69QKWHpPxKz3YWCc=`):
- Binary name inside: `tmog-task-manager`
- Desktop id: `com.tmog.taskmanager.desktop` (`Name=Task Manager TMOG`,
  `Categories=System;Monitor;`, includes a `Summon` action for a GlobalShortcuts
  fallback — preserved as-is except for the `Exec=` line, which is rewritten from
  `tmog-task-manager` to the wrapped `tmog` binary name)
- Icons: `usr/share/icons/hicolor/{32,48,64,128,256,512}x*/apps/tmog-task-manager.png`
  plus a pixmaps fallback

### Update mechanism

TMOG has no GitHub releases API, so the `brave-origin` bump workflow's GitHub-API
approach isn't reusable verbatim. Instead, a weekly workflow scrapes
`https://tmog.org/` for the current AppImage filename (`TaskManagerOG-<ver>-x86_64.AppImage`),
compares it to the pinned `version` in `pkgs/tmog/default.nix`, and — same gate as
brave-origin — only rewrites the pin and commits if a `nix build` of the bumped package
succeeds. Once merged, the pin update reaches a host the same way brave-origin's does:
next `git pull` on the repo, then `just update` / the "Up" GUI to rebuild — no separate
manual AppImage re-download is ever required.

## Implementation Steps

1. **`pkgs/tmog/default.nix`** (new) — `appimageTools.wrapType2` derivation:
   `pname = "tmog"`, pinned `version`/`hash`, `fetchurl` from
   `https://tmog.org/downloads/TaskManagerOG-${version}-x86_64.AppImage`,
   `extraInstallCommands` installs the extracted `.desktop` (Exec rewritten to `tmog`)
   and the 6 icon sizes, `meta.mainProgram = "tmog"`, `meta.license = lib.licenses.unfree`
   (freeware, no OSS license published), `platforms = [ "x86_64-linux" ]`.
2. **`pkgs/default.nix`** — add `tmog = final.callPackage ./tmog { };` under a new
   `# ── Utilities ──` section (or nearest fitting comment block).
3. **`modules/packages-desktop.nix`** — add `vexos.tmog` to `environment.systemPackages`
   (covers desktop, htpc, server, stateless; headless-server and vanilla don't import
   this file, so no change needed there).
4. **Utilities app-folder — system dconf defaults**, add
   `"com.tmog.taskmanager.desktop"` to the `apps` list:
   - `modules/gnome-desktop.nix` (~line 115 block)
   - `modules/gnome-htpc.nix` (~line 52 block)
   - `modules/gnome-server.nix` (~line 50 block)
   - `modules/gnome-stateless.nix` (~line 52 block)
5. **Utilities app-folder — live home-manager oneshot**, same addition to the `apps`
   array, **and bump the stamp filename** so existing profiles re-run the write
   (per the documented `game_utilities_folder_stamp` precedent):
   - `home-desktop.nix` — apps list line ~237, stamp `-v4` → `-v5`
   - `home-htpc.nix` — apps list line ~92, stamp `-v2` → `-v3`
   - `home-server.nix` — apps list line ~161, stamp `-v2` → `-v3`
   - `home-stateless.nix` — apps list line ~241, stamp `-v2` → `-v3`
6. **`.github/workflows/update-tmog-weekly-<day>.yml`** (new) — weekly + manual-dispatch
   workflow scraping `https://tmog.org/` for the current AppImage version, rewriting
   `version`/`hash` in `pkgs/tmog/default.nix`, building before committing (mirrors
   `update-brave-origin-weekly-thursday.yml`'s structure and safety gate).

## Dependencies

No new flake inputs, no new external library/framework with a versioned API —
`appimageTools` is a standard `nixpkgs` library already used implicitly via
`stdenv`/`fetchurl` patterns elsewhere in this repo. Context7 lookup is not applicable
(internal Nix packaging only, per the "internal code changes with no new dependencies"
exemption).

## Configuration Changes

None beyond the module edits listed in Implementation Steps — no new NixOS option is
introduced (unlike `vexos.btrfs.enable`-style toggles), matching Module Architecture
Pattern Option B: the package is added unconditionally to the file that already scopes
it to the correct 4 roles.

## Risks and Mitigations

- **Past AppImage reliability issues (user-flagged, Crality print app).** Mitigated by
  not using `appimage-run`/binfmt at all — `wrapType2` produces a normal native binary.
  The only shared-library risk is the same class `autoPatchelfHook` already handles for
  `brave-origin`; if TMOG's bundled Qt/GTK libs are incomplete, `nix build` will fail
  loudly at Phase 3/6, not at runtime.
- **No GitHub releases / no versioned API for TMOG** means the auto-bump workflow is
  HTML-scraping-based and inherently more fragile than brave-origin's GitHub API
  lookup (a tmog.org page redesign could silently break the regex). Mitigated the same
  way brave-origin is: the workflow only commits after a successful `nix build`, so a
  broken scrape either finds nothing (no-op) or fails the build gate — it can't push a
  broken pin.
- **Vendor is freeware, not open source; no license grant for redistribution is
  published.** This mirrors `brave-origin` (also a proprietary/EULA'd pre-built binary
  fetched at build time from the vendor's own URL, not redistributed by this repo) —
  `fetchurl` at build time from the vendor's own domain, never vendored into the repo,
  is the same posture already accepted for that package. Flagged here for visibility,
  not blocking.
- **Beta software** ("Beta 3" per tmog.org, version string `0.1.3`) — no functional
  mitigation needed; noted so a bad rebuild-time crash isn't mistaken for a packaging
  bug.

## Build Validation Constraint (environment note)

This session runs on Windows with no NixOS host — `sudo nixos-rebuild dry-build` cannot
execute here (confirmed prior in this repo's memory: WSL has Nix 2.34.1 and validates
everything except `nixos-rebuild`). Phase 3/6 validation in this session is limited to
`nix flake show --impure` and `nix eval --impure` (via WSL) plus a direct
`nix build --impure` of `pkgs.vexos.tmog` against the flake's pinned nixpkgs, mirroring
exactly what the bump workflow's own build-gate step does. `sudo nixos-rebuild
dry-build` per role must be run by the user on an actual NixOS host before merging with
full confidence.
