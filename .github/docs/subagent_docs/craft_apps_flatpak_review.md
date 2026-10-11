# Craft apps Flatpak bundles — Phase 3 review

Spec: `.github/docs/subagent_docs/craft_apps_flatpak_spec.md`

## Files reviewed

- `pkgs/craft-apps/pins.json` (new)
- `pkgs/craft-apps/default.nix` (new)
- `pkgs/default.nix`
- `modules/flatpak-bundles.nix` (new)
- `modules/flatpak-desktop.nix`
- `configuration-desktop.nix`
- `modules/gnome-desktop.nix`
- `home-desktop.nix`
- `.github/workflows/update-craft-apps-daily.yml` (new)

## Validation performed

| Check | Result |
|---|---|
| `nix eval` toplevel drvPath `vexos-desktop-amd` / `-nvidia` / `-vm` | PASS (before and after the final overlay fix) |
| `nix eval` `vexos-htpc-amd`, `vexos-stateless-amd` (shared overlay touched) | PASS |
| `nix eval` `vexos-server-amd` | FAIL — **pre-existing**: identical `networking.hostId` placeholder assertion at unmodified `HEAD` (`d692b38`); server roles import none of the changed modules |
| `nix build --dry-run --impure` for this host's variant (`vexos-desktop-nvidia`) | PASS |
| Real build of all four pinned bundles (fetchurl verifies hashes) | PASS |
| Workflow gate logic (`app/ai.storyteller.<n>/x86_64/stable` in bundle header) run against the built bundles | PASS ×4 |
| Workflow bump logic (`nix-prefetch-url` → SRI → `jq`) on a scratch copy of the pins using v0.4.0 | PASS; hash equals independently computed hash |
| Generated `flatpak-install-bundles` script + unit (`after`, `requires`, `path`) inspected | PASS |
| Empirical bundle semantics in a throwaway `FLATPAK_USER_DIR` | newer bundle upgrades in place ✔; same version → "already installed" (handled) ✔ |
| Workflow YAML parses (yq) | PASS |
| `git ls-files hardware-configuration.nix` | empty ✔ |
| `system.stateVersion` untouched in `configuration-*.nix` | ✔ |
| `flake.nix` / `flake.lock` untouched, no new inputs | ✔ |
| `nixpkgs-fmt --check` | would reformat, but the changed pre-existing files are already unformatted at `HEAD` and the repo uses aligned-`=` style; preflight stage 6 is WARN-only |
| Full `scripts/preflight.sh` | **NOT RUN YET** — new files are untracked, flake evaluation by git ref cannot see them; needs staging by the user (Phase 6) |
| Runtime-dependency pull of `flatpak install --bundle` from the `flathub` remote | **NOT TESTED** — the test command was declined; only `--no-deps` behaviour was verified |

## Findings

### CRITICAL
None.

### RECOMMENDED / noted
1. **Fixed during review:** `callPackage` wraps its result with `override` /
   `overrideDerivation`, which broke iteration over `pkgs.vexos.craft-apps` in the CI gate.
   Switched to a plain `import` in `pkgs/default.nix` (commented).
2. **Fixed during review:** `vexos-notify` is not on a systemd service's PATH on this host
   (verified with `systemctl show flatpak-install-apps -p Environment`). The new service adds
   `/run/current-system/sw` to `path` and guards the call with `|| true`.
3. **Pre-existing, not touched (surgical-changes rule):** the same missing-PATH problem exists in
   `modules/flatpak.nix` and `modules/gnome-flatpak-install.nix` — their failure branches would
   exit 127 instead of notifying.
4. **Pre-existing, not touched:** `modules/gnome-desktop.nix` system dconf defaults lack the `3D`
   folder that `home-desktop.nix` creates.
5. **Behavioural note:** bumping the `home-desktop.nix` stamp `v5` → `v6` re-applies the folder
   layout once per existing desktop user and overwrites manual folder edits.
6. **Open risk:** first real install on a host exercises the runtime pull
   (`org.freedesktop.Platform` 25.08 and, for PhotoCraft, 26.08 — both already present on the
   dev host). On failure the stamp stays unwritten, the unit retries each boot, and the switch is
   not affected.
7. **Closure size:** ~190 MB of bundles join the desktop closure (accepted by the user when
   choosing the pinned-fetchurl approach).

## Score

| Category | Score | Grade |
|----------|-------|-------|
| Specification Compliance | 100% | A+ |
| Best Practices | 93% | A |
| Functionality | 90% | A- |
| Code Quality | 94% | A |
| Security | 96% | A |
| Performance | 92% | A- |
| Consistency | 95% | A |
| Build Success | 100% | A+ |

**Overall Grade: A (95%)**

Functionality is capped below 100% only by the untested dependency-pull path.

## Result

**PASS** — proceed to Phase 6 (preflight), which is blocked on the user staging the new files.
