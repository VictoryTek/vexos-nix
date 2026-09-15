# Remove PurpleAdBlock, add Alternate Player for Twitch.tv — Review

## Summary
Reviewed the single-file change to `home/browser-extensions.nix`: removal of
the `purpleads` (PurpleAdBlock) entry from the shared Brave+LibreWolf
extension list, and addition of "Alternate Player for Twitch.tv" as a
LibreWolf-only entry (no Chrome Web Store listing exists for it).

## Findings

1. **Specification Compliance** — Matches spec exactly: `purpleads` entry
   deleted; `firefoxOnlyExtensions` list added with the AMO-verified GUID
   (`twitch5@coolcmd`) and slug (`twitch_5`); merged into
   `ExtensionSettings` via `extensions ++ firefoxOnlyExtensions`, leaving
   Brave's `home.file` block (which only consumes `extensions`) unaffected.
2. **Best Practices** — Follows the existing idiom in the file exactly
   (list of attrsets consumed generically via `map`/`listToAttrs`); no new
   patterns introduced.
3. **Consistency (Module Architecture Pattern)** — No `lib.mkIf` guards
   added; this is a data-only edit inside an existing role-addition file.
   Option B pattern unaffected.
4. **Maintainability** — Header comment updated to reflect the new
   4-shared + 1-Firefox-only-extension count/shape, and a short comment
   explains why the new list is separate (no Chrome Web Store listing).
5. **Completeness** — Both the removal and the addition are fully wired
   through to the one consumer that matters (LibreWolf's
   `ExtensionSettings`); Brave correctly excludes the Firefox-only entry.
6. **Performance** — No regressions; trivial list-length change.
7. **Security** — No secrets, no world-writable files, no credential
   assignments. `installation_mode = "normal_installed"` keeps the new
   extension editable/removable, matching the existing non-locked policy
   tier for all other entries.
8. **API Currency** — GUID and slug independently verified against the
   live AMO v5 API (`/addons/search/` and `/addons/addon/twitch_5/`):
   status public/listed/active, current version 2026.6.21.
9. **Build Validation** (vexos-nix specific steps):
   - `nix flake show --impure` — passed, all 30 `nixosConfigurations` plus
     other outputs enumerate without evaluation errors.
   - `nixos-rebuild dry-build` is unavailable in this environment (no
     NixOS host at `/etc/nixos`, dev environment is Windows+WSL) — used
     the documented safe alternative, `nix eval --impure
     .#nixosConfigurations.<name>.config.system.build.toplevel.drvPath`,
     for every role touched by this file:
     - vexos-desktop-amd — OK
     - vexos-desktop-nvidia — OK
     - vexos-desktop-vm — OK
     - vexos-server-amd — OK
     - vexos-headless-server-amd — OK
     - vexos-stateless-amd — OK
     - vexos-htpc-amd — OK
     All 7 evaluated to a valid `.drv` path, exit code 0, no errors.
   - `git ls-files hardware-configuration.nix` — empty (not tracked). OK.
   - `system.stateVersion` unchanged in all `configuration-*.nix` (file
     not touched by this change). OK.
   - No new flake inputs added — `follows` check N/A.

No CRITICAL or RECOMMENDED issues found.

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

## Returns
- Build result: PASS (flake show clean; 7/7 targeted role evaluations
  succeeded)
- **PASS**
