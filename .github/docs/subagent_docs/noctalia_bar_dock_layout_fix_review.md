# Noctalia Bar/Dock Layout Fix — Review

Status: Phase 3 (Review & Quality Assurance)

---

## 1. Specification compliance

| Item | Spec | Implemented | Match |
|---|---|---|---|
| Clock → center lane, own capsule group | `center = [ "group:clock" ]`, new `clock` group | Done, `home/noctalia.nix` lines 185, 196-202 | ✅ |
| Media relocated to end lane (before status) | `end = [ "group:media" "group:status" ]` | Done, line 186 | ✅ |
| `status` group: remove `clock`, add `session` | `members = [ "tray" "session" ]` | Done, line 214 | ✅ |
| Dock: `reserve_space = false` | added under `dock` | Done, line ~231 | ✅ |
| No `[widget.session]` override | defaults only | Not added | ✅ |
| No new files/modules, no new `lib.mkIf` guard | settings-only edit inside existing gate | Confirmed — only `home/noctalia.nix` changed | ✅ |

## 2. Best practices / Nix & NixOS conventions

- Follows existing file style: capsule-group pattern, comment density, and
  attribute ordering match the surrounding code exactly.
- `session` and `clock` widget/group names verified against upstream docs at
  the pinned tag (`v5.1.0`) rather than guessed.

## 3. Consistency (Module Architecture Pattern — Option B)

- `home/noctalia.nix` is a role module (`home/` sub-module gated on
  `osConfig.vexos.desktop.environment == "hyprland"`), not a shared base
  module — its existing `lib.mkIf` gate is the pre-existing carve-out
  documented in the original migration spec. No new guard was added or
  removed by this change.

## 4. Maintainability

- Comments updated in place (`# Clock, centered on its own.`, `# System tray
  + session (power/logout/restart) share one capsule on the right.`, and the
  `reserve_space` rationale comment) so the "why" survives for the next
  editor, consistent with file's existing comment density.

## 5. Completeness

All three reported symptoms addressed:
1. Dock exclusive-zone shift → `dock.reserve_space = false`.
2. Clock off-center → moved to its own `center`-lane capsule group.
3. No system/power button → `session` widget added to the right capsule.

## 6. Performance

No regressions — pure settings/TOML-shape change, no new widgets requiring
extra polling, no new packages.

## 7. Security

No secrets, no world-writable files, no plaintext credentials. N/A for this
change.

## 8. API currency

`session` and `reserve_space` verified directly against
`docs/user/bar/widgets/session.mdx` and `docs/user/dock/index.mdx` at the
exact pinned tag (`v5.1.0`, rev `c7b9197`) — not inferred from memory.

## 9. Build validation

Environment note: this session runs on Windows (no NixOS host reachable), so
`sudo nixos-rebuild dry-build` cannot execute here — consistent with prior
work in this repo (see `nix_validation_via_wsl` memory). WSL Ubuntu (Nix
2.34.1, repo mounted read/write at `/mnt/c/Projects/vexos-nix`) was used for
the nearest available equivalent, per the project's own established
precedent for exercising the Hyprland/Noctalia branch (see
`hyprland_dms_session_review.md`, `noctalia_v5_migration_review.md`).

| Check | Command | Result |
|---|---|---|
| Flake structure | `nix flake show --impure` (WSL) | ✅ all `nixosConfigurations` list; only pre-existing unrelated warnings (`kernel-override` not a derivation) |
| Default-branch full eval | `nix eval --impure` `vexos-desktop-amd` toplevel drvPath (WSL) | ✅ `nixos-system-vexos-26.05.drv` produced |
| **Hyprland/Noctalia branch full eval** (exercises this change) | `nix eval --impure` on `vexos-desktop-amd.extendModules { vexos.desktop.environment = "hyprland"; }` toplevel drvPath (WSL) | ✅ `nixos-system-vexos-26.05.drv` produced, no errors |
| `hardware-configuration.nix` not committed | `git ls-files hardware-configuration.nix` | ✅ empty |
| `stateVersion` unchanged | `grep stateVersion configuration-*.nix` | ✅ all still `"25.11"`, no diff |
| Flake inputs / `follows` | not touched by this change | N/A |
| `git status` scope | `git status --short` | ✅ only `home/noctalia.nix` modified + new spec/review docs |

**Not runnable from this environment** (no NixOS host):
- `sudo nixos-rebuild dry-build --flake .#vexos-desktop-amd/-nvidia/-vm`
- Noctalia's own build-time `checkConfig` validator (`noctalia config
  validate`) — this only runs as part of a real Home Manager activation on a
  NixOS host with the `noctalia` package built.

These gaps are inherited from the environment (Windows, no NixOS host), not
from this change, and are called out per CLAUDE.md's "verify before
asserting" rule rather than claimed as passing.

## Score table

| Category | Score | Grade |
|----------|-------|-------|
| Specification Compliance | 100% | A |
| Best Practices | 100% | A |
| Functionality | 95% | A (session/reserve_space behavior confirmed only via upstream docs, not a live NixOS activation) |
| Code Quality | 100% | A |
| Security | 100% | A |
| Performance | 100% | A |
| Consistency | 100% | A |
| Build Success | 90% | A- (full eval passes on both branches; `nixos-rebuild dry-build` and runtime `checkConfig` unreachable from this environment) |

**Overall Grade: A (98%)**

## Returns

- **PASS** — no CRITICAL issues. The two environment-limited checks
  (`dry-build`, `checkConfig`) are informational gaps, not failures; they
  could not be attempted at all in this environment, not attempted-and-failed.
