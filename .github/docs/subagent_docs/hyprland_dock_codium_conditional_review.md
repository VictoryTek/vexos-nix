# Hyprland dock: conditional Codium pin — Review

## Spec compliance

Implemented as specified: `basePinnedApps` extracted as a `let`-bound list in
`home/dank-material-shell.nix`, with `"codium"` appended only via
`lib.optional osConfig.vexos.features.development.enable "codium"`. Both
`session.pinnedApps` and `session.barPinnedApps` now reference the single
shared list, removing the prior duplication (in scope — direct consequence of
the fix, not unrelated cleanup).

## Build validation

Validated via WSL Ubuntu (Nix 2.34.1), same approach as the prior hypridle
change (Windows host has no `nix`; `sudo nixos-rebuild dry-build` unavailable
without a real NixOS host, so full toplevel evaluation was forced instead with
the CI-style stub `hardware-configuration.nix`):

- `vexos-desktop-amd`, forced `vexos.desktop.environment = "hyprland"`,
  `development.enable` left at default (`false`) →
  `session.pinnedApps` evaluates to
  `["brave-origin" "app.zen_browser.zen" "org.gnome.Nautilus" "com.mitchellh.ghostty" "io.github.up" "org.gnome.Boxes"]`
  — **no `codium`**, confirming the fix.
- Same host, forced `development.enable = true` →
  `session.pinnedApps` evaluates to the same list **with `"codium"` appended**
  — confirms the flag correctly re-adds it.
- Full `config.system.build.toplevel.drvPath` forced and built successfully for
  both the dev-disabled and dev-enabled cases on `vexos-desktop-amd`
  (forced-hyprland) — no eval errors in either branch.
- `bash scripts/preflight.sh` (WSL, `nix shell nixpkgs#jq nixpkgs#nixpkgs-fmt`)
  → **exit 0, PASSED**. Same pre-existing non-blocking WARNs as the prior
  review (repo-wide `nixpkgs-fmt` drift, `impermanence`/`dms` flake input
  staleness, one placeholder secret string in `modules/server/vexboard.nix`) —
  none introduced by this change, none are HARD failures.
- `git ls-files hardware-configuration.nix` → empty (not tracked).
- `system.stateVersion` unchanged (preflight stage [4/8], all 6 configs pass).
- No new flake inputs — no `follows` declarations needed.
- **Caveat (per project memory):** WSL cannot run `sudo nixos-rebuild
  dry-build` — stage `[2/8]` always SKIPs there. Recommend a real dry-build on
  actual NixOS hardware before switching, though the forced full-evaluation
  above is a strong proxy (it already caught type/attribute errors in the
  earlier hypridle change during the same workflow).

## Best practices / consistency / maintainability

- No new `lib.mkIf` role-guard added to a shared module — this stays entirely
  inside the Home Manager file already scoped to the Hyprland role via
  `osConfig.vexos.desktop.environment == "hyprland"`.
- Reads `osConfig.vexos.features.development.enable`, an option declared
  globally by `modules/development.nix` (imported unconditionally by
  `configuration-desktop.nix`), so it always resolves with a real default —
  no risk of an "attribute missing" eval error on any host that can reach this
  file.
- `git diff --stat`: `home/dank-material-shell.nix | 33 +++++++++++++++------------------`
  (15 insertions, 18 deletions) — single file, surgical, net negative in line
  count from de-duplication.

## Security

No secrets, no new attack surface — pure list composition.

## Completeness vs. user's stated requirement

Dock/launcher no longer shows a Codium entry unless
`vexos.features.development.enable = true`, confirmed by direct evaluation of
both branches above.

## Score Table

| Category | Score | Grade |
|----------|-------|-------|
| Specification Compliance | 100% | A |
| Best Practices | 100% | A |
| Functionality | 100% | A |
| Code Quality | 100% | A |
| Security | 100% | A |
| Performance | 100% | A |
| Consistency | 100% | A |
| Build Success | 95% | A (WSL forced-eval PASS both branches; real-hardware dry-build not independently verifiable from this environment) |

**Overall Grade: A (99%)**

## Result: **PASS**
