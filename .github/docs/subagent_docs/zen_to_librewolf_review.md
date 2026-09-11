# Zen Browser → LibreWolf Replacement — Review

## Specification Compliance

All 9 steps in `zen_to_librewolf_spec.md` implemented exactly as specified, no
extra changes:

| File | Change | Matches Spec |
|---|---|---|
| `modules/flatpak.nix` | `app.zen_browser.zen` → `io.gitlab.librewolf-community` | ✔ |
| `home/noctalia.nix` | `basePinnedApps` entry swapped | ✔ |
| `home/dank-material-shell.nix` | `basePinnedApps` entry swapped (dormant shell, kept in sync) | ✔ |
| `modules/gnome-desktop.nix` | `favorite-apps` entry swapped | ✔ |
| `modules/gnome-htpc.nix` | `favorite-apps` entry swapped | ✔ |
| `modules/gnome-server.nix` | `favorite-apps` entry swapped | ✔ |
| `modules/gnome-stateless.nix` | `favorite-apps` entry swapped | ✔ |
| `home-desktop.nix` | Comment: "Firefox/Zen" → "Firefox/LibreWolf" | ✔ |
| `home-htpc.nix` | Comment: "Firefox/Zen" → "Firefox/LibreWolf" | ✔ |

`git diff --stat`: 9 files changed, 9 insertions(+), 9 deletions(-) — exactly
one line per file, matching the spec's scope precisely.

Post-implementation grep for `zen_browser|app\.zen` across all `*.nix` files
returns zero matches — no remaining reference anywhere.

## Best Practices / Nix Conventions

Flatpak app IDs follow the same reverse-DNS convention already used
throughout these lists; `io.gitlab.librewolf-community` is LibreWolf's
official Flathub app ID (verified live against
https://flathub.org/en/apps/io.gitlab.librewolf-community). No new
derivations, options, or packages introduced.

## Consistency (Module Architecture Pattern — Option B)

No new `lib.mkIf` guards added. No new files created. No role reclassification.
This is a pure value substitution inside existing universal/role files —
fully consistent with the existing pattern. `basePinnedApps` parity between
`home/noctalia.nix` (active) and `home/dank-material-shell.nix` (disabled,
documented as deliberately kept in sync) is preserved.

## Maintainability

No structural change; readability unaffected. Comment updates
(`home-desktop.nix`, `home-htpc.nix`) keep documentation accurate rather than
stale.

## Completeness

All 7 functional references (1 flatpak install + 6 dock/favourites) and both
Zen-specific comments addressed. False positives (Ryzen "Zen" microarchitecture
in `modules/gaming.nix`, Linux-Zen kernel scheduler note in
`modules/system-gaming.nix`, `zenity` in `home/gnome-common-browser.nix`)
correctly left untouched — none reference Zen Browser.

## Performance

No regressions — same install mechanism (Flathub via the existing
`flatpak-install-apps` systemd service), same list sizes.

## Security

No hardcoded secrets, no new world-writable files, no plaintext credentials.
LibreWolf is a privacy/security-focused Firefox fork; no new attack surface
beyond swapping one Flathub-distributed browser for another via the existing
service.

## API Currency

Flatpak app ID confirmed current via live Flathub listing (Context7 not
applicable — Flathub app IDs are not Context7-indexed library docs).

## Build Validation (vexos-nix specific steps)

Environment note: no `nix` binary on this Windows host; validation run via
WSL Ubuntu (Nix 2.34.1), using the pre-existing CI-matching stub fixtures at
`/etc/nixos/hardware-configuration.nix` and
`/etc/nixos/stateless-user-override.nix` (already present from prior
validation work in this environment, format matches `.github/workflows/ci.yml`
exactly). `sudo nixos-rebuild dry-build` is unavailable outside a live NixOS
host, so per-target full evaluation via `nix eval --impure
.#nixosConfigurations.<config>.config.system.build.toplevel.drvPath` was used
instead — this is CI's own equivalent-to-`nix flake check --no-build` method,
named explicitly in the project's Test Commands. `nix flake check` itself was
never run (forbidden).

| Command | Result |
|---|---|
| `nix flake show --impure` | ✔ PASS — all 30 `nixosConfigurations` + `checks` enumerated, exit 0 |
| `nix eval --impure .../vexos-desktop-amd.../drvPath` | ✔ PASS, exit 0 |
| `nix eval --impure .../vexos-desktop-nvidia.../drvPath` | ✔ PASS, exit 0 |
| `nix eval --impure .../vexos-desktop-vm.../drvPath` | ✔ PASS, exit 0 |
| `nix eval --impure .../vexos-server-amd.../drvPath` (server module touched) | ✔ PASS, exit 0 |
| `nix eval --impure .../vexos-htpc-amd.../drvPath` (htpc module touched) | ✔ PASS, exit 0 |
| `nix eval --impure .../vexos-stateless-amd.../drvPath` (stateless module touched) | ✔ PASS, exit 0 |
| `git ls-files hardware-configuration.nix` | ✔ PASS — empty, not tracked |
| `system.stateVersion` presence, all 6 `configuration-*.nix` | ✔ PASS — none of these files were touched; all 6 still declare it |
| New flake inputs `follows` check | N/A — no new flake inputs added |

No evaluation errors or missing-attribute failures in any target.

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
| Build Success | 100% | A |

**Overall Grade: A (100%)**

## Result

**PASS** — no refinement cycle needed.
