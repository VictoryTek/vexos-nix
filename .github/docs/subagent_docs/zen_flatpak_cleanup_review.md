# Zen Browser Flatpak Cleanup — Review

## Specification Compliance

Single step from `zen_flatpak_cleanup_spec.md` implemented exactly: added
`app.zen_browser.zen` to the "Remove globally banned apps" loop in
`modules/flatpak.nix`, alongside the existing `com.github.wwmm.easyeffects`
entry. `git diff --stat`: 1 file changed, 2 insertions(+), 1 deletion(-)
(line-continuation split, one new app ID). No other file touched — matches
spec scope precisely (dock/launcher pins already correct from the prior
Zen→LibreWolf migration; this fix only addresses the leftover-install gap).

## Best Practices / Nix Conventions

Reuses the exact existing pattern (unconditional-removal loop with an
idempotent `flatpak list | grep -qx` guard before each uninstall) rather than
inventing a new mechanism. No new derivations, options, or packages.

## Consistency (Module Architecture Pattern — Option B)

No new `lib.mkIf` guards, no new files, no role reclassification — a
one-line addition inside an existing unconditional block in a universal base
module. Fully consistent with the existing pattern.

## Maintainability

Minimal diff; the surrounding comment already documents the loop's intent
("uninstalled unconditionally, regardless of excludeApps"). No additional
comment needed — `com.github.wwmm.easyeffects` sits there with no per-entry
annotation either, and the entry is self-explanatory given the loop's header
comment and the app's own name.

## Completeness

Addresses the exact gap the prior migration's spec called out as accepted/
out-of-scope. Live verification (`flatpak list --app` on this host) confirmed
`app.zen_browser.zen` was present before the fix; the added uninstall line
will remove it on the next `nixos-rebuild switch` (or next boot, per the
service's stamp/retry logic) on this and any other host still carrying it.

## Performance

No regressions — one extra idempotent list/grep/uninstall check added to a
oneshot systemd service that already runs this exact pattern.

## Security

No hardcoded secrets, no new world-writable files, no plaintext credentials.

## API Currency

N/A — no external library/API involved; reuses the same Flatpak app ID
already verified against the live Flathub listing in the prior migration.

## Build Validation (vexos-nix specific steps)

Environment note: this session's Bash tool runs in a sandboxed container
(`sudo` refuses with "no new privileges flag is set") — `sudo nixos-rebuild
dry-build` is unavailable here. Substituted with `nix eval --impure
.#nixosConfigurations.<config>.config.system.build.toplevel.drvPath`, the
project's own documented CI-equivalent method (same substitution the prior
`zen_to_librewolf_review.md` used under its own environment constraint).
`nix flake check` was never run (forbidden).

| Command | Result |
|---|---|
| `nix flake show --impure` | ✔ PASS — flake structure evaluates, exit 0 |
| `nix eval --impure .../vexos-desktop-amd.../drvPath` | ✔ PASS |
| `nix eval --impure .../vexos-desktop-nvidia.../drvPath` | ✔ PASS |
| `nix eval --impure .../vexos-desktop-vm.../drvPath` | ✔ PASS |
| `nix eval --impure .../vexos-stateless-amd.../drvPath` (stateless imports flatpak.nix) | ✔ PASS |
| `nix eval --impure .../vexos-htpc-amd.../drvPath` (htpc imports flatpak.nix) | ✔ PASS |
| `nix eval --impure .../vexos-server-amd.../drvPath` (server imports flatpak.nix) | ⚠ Pre-existing, unrelated failure — see below |
| `nix eval --impure .../vexos-headless-server-amd.../drvPath` (headless-server imports flatpak.nix) | ⚠ Pre-existing, unrelated failure — see below |
| `git ls-files hardware-configuration.nix` | ✔ PASS — empty, not tracked |
| `system.stateVersion` presence, all 6 `configuration-*.nix` | ✔ PASS — all declare `"25.11"`, none touched |
| New flake inputs `follows` check | N/A — no new flake inputs added |

**server-amd / headless-server-amd failure detail:** both fail an assertion
unrelated to this change — `networking.hostId` in `hosts/server-amd.nix` and
`hosts/headless-server-amd.nix` is a committed template placeholder
(`"a0000001"` / `"b0000001"`) that the ZFS module's own assertion rejects as
non-unique. This is a pre-existing condition of the repo's generic template
values (confirmed via `grep hostId` on both host files, untouched by this
diff) — not a regression introduced by the `modules/flatpak.nix` edit, which
only adds a string to a shell loop with no relation to networking/ZFS.

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
| Build Success | 100% | A (pre-existing unrelated template-placeholder failures on server/headless-server, not caused by this change) |

**Overall Grade: A (100%)**

## Result

**PASS** — no refinement cycle needed.
