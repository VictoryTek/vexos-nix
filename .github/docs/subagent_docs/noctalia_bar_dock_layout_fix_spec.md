# Noctalia Bar/Dock Layout Fix — Specification

Feature: fix three post-migration layout regressions in `home/noctalia.nix`
(bar + dock), introduced by the DMS → Noctalia v5 migration
(`.github/docs/subagent_docs/noctalia_v5_migration_spec.md`).

Status: Phase 1 (Research & Specification)

---

## 1. Current state analysis

`home/noctalia.nix` (`bar.default` and `dock` sections) currently configures:

- **Bar** — three capsule groups: `nav` (workspaces, start lane), `media`
  (media widget, center lane), `status` (tray + clock, end lane).
- **Dock** — `enabled = true`, `position = "left"`, `auto_hide = true`,
  `smart_auto_hide = true`. No `reserve_space` key is set, so it falls back to
  the upstream default.

User-reported symptoms (screenshot + text, 2026-09-11):

1. The usable screen area is shifted right, as if space is reserved for the
   dock, even though the dock is set to auto-hide.
2. The clock renders on the right side of the bar instead of centered.
3. There is no widget on the bar for session actions (shutdown / restart /
   log off).

## 2. Problem definition

Verified against upstream docs at the pinned tag (`v5.1.0`,
`github:noctalia-dev/noctalia-shell`, rev `c7b9197`):

- **Symptom 1 — root cause confirmed.** `docs/user/dock/index.mdx`: the dock
  has a `reserve_space` setting. When `auto_hide = true` **and**
  `reserve_space = true` (upstream default), the compositor still maintains
  an exclusive zone for the dock so that a gap remains while it is hidden —
  this is exactly the "full screen but shifted right" symptom. Because
  `home/noctalia.nix` never sets `reserve_space`, it inherits the default
  that causes this. Fix: explicitns `reserve_space = false`, so an
  auto-hidden dock retracts as a pure overlay with no reserved gap.
- **Symptom 2 — confirmed by config inspection.** The `clock` widget is
  currently a member of the `status` capsule group, which sits in the `end`
  lane (`bar.default.end = [ "group:status" ]`). There is no widget in
  `center` other than `media`. Fix: move `clock` into its own capsule group
  and place that group in the `center` lane.
- **Symptom 3 — confirmed, widget exists.** `docs/user/bar/widgets/session.mdx`:
  a built-in `session` widget ("Shows a power glyph and opens the session menu
  panel on click") is available (`widget.session`, default `glyph =
  "shutdown"`). It is not referenced anywhere in `bar.default`. Fix: add
  `session` as a member of the right-hand capsule group.

## 3. Proposed solution architecture

Edit only `home/noctalia.nix`, inside the existing `settings.bar.default` and
`settings.dock` attrsets. No new files, no new module (Module Architecture
Pattern: this is a role-module settings tweak, not a shared-module change —
no `lib.mkIf` guard is added or removed).

### 3.1 Bar — lane/group changes

| Lane | Before | After |
|---|---|---|
| `start` | `[ "group:nav" ]` | unchanged |
| `center` | `[ "group:media" ]` | `[ "group:clock" ]` |
| `end` | `[ "group:status" ]` | `[ "group:media" "group:status" ]` |

`capsule_group` changes:
- `nav` (workspaces) — unchanged.
- `media` — unchanged contents (`members = [ "media" ]`); only its lane
  changes (center → end, ordered before `status`), per the same capsule
  styling already defined.
- New group `clock` — `members = [ "clock" ]`, same capsule styling
  (`fill = "surface_variant"`, `border = "outline"`) as the other groups, now
  the sole occupant of `center`.
- `status` — `members` changes from `[ "tray" "clock" ]` to
  `[ "tray" "session" ]` (clock moves out to its own group; `session` is the
  new power/logout/restart widget the user asked for).

### 3.2 Dock — reserved space

Add `reserve_space = false;` to `settings.dock`, alongside the existing
`auto_hide`/`smart_auto_hide` keys, so an auto-hidden dock no longer reserves
an exclusive zone that shifts the visible workspace area.

### 3.3 Session widget defaults

No explicit `[widget.session]` table is required — defaults
(`glyph = "shutdown"`, no custom image) match what the user asked for (a
button that opens the session/power menu). Left at defaults per the
Simplicity First principle (no configurability the user didn't request).

## 4. Implementation steps

1. `home/noctalia.nix` — `bar.default.center`/`end` lane arrays, `capsule_group`
   list (rename/restructure `media`'s lane placement, add `clock` group,
   update `status` members).
   → verify: `noctalia config validate` reports 0 errors/0 warnings (existing
   project convention, see file header); TOML structurally identical shape to
   existing groups.
2. `home/noctalia.nix` — `dock.reserve_space = false;`.
   → verify: key present in generated `config.toml` at
   `[dock]` section.

No other files change. This is a settings-only edit inside an existing
`osConfig.vexos.desktop.environment == "hyprland"`-gated `mkIf` block — no new
guard, consistent with Module Architecture Pattern.

## 5. Dependencies

None (styling/settings-only change to an already-pinned input). Per
CLAUDE.md Dependency Policy, Context7 is not required for styling/UI-only
changes with no new dependency. Widget/setting names (`session`,
`reserve_space`) were verified directly against the pinned upstream tag's own
docs (`docs/user/bar/widgets/session.mdx`, `docs/user/dock/index.mdx`), the
same verification method already used and documented for this module by the
prior migration spec.

## 6. Configuration changes

Confined to `home/noctalia.nix`, `settings.bar.default` and `settings.dock`.
No flake input, module import, or NixOS-level change.

## 7. Risks and mitigations

| Risk | Impact | Mitigation |
|---|---|---|
| `reserve_space` name/default assumed from docs, not runtime-tested (no NixOS host reachable from this environment) | Setting could be a no-op if misnamed | Verified against upstream docs at the exact pinned tag; build-time `checkConfig` validator will flag an unknown key as a warning — re-run `noctalia config validate` after rebuild, per existing file-header convention. Flagged explicitly to user in delivery notes. |
| Moving `clock` out of `status` changes the visual grouping the prior migration spec documented | Cosmetic only | Header comment above `bar.default` updated to reflect new grouping so the rationale isn't lost. |
| This environment is Windows; `sudo nixos-rebuild dry-build` cannot run here (no NixOS host) | Phase 3/6 build validation is structurally limited | `nix flake show --impure` and `nix eval --impure` for the affected `nixosConfigurations.*.config.system.build.toplevel.drvPath` run via WSL Ubuntu (has Nix 2.34.1, repo mounted at `/mnt/c/Projects/vexos-nix`) as the closest available equivalent — same substitute already used successfully in this project (see memory: `nix_validation_via_wsl`). `nixos-rebuild dry-build` itself and the runtime `noctalia config validate` check are out of reach until run on the actual NixOS host; called out explicitly to the user rather than asserted as passing. |

## 8. Out of scope

- Any other bar/dock widget, theme, or launcher setting untouched by this
  request.
- Adding a `[widget.session]` customization table (defaults suffice).
- Testing on the actual NixOS host (`vextop`) — user verifies visually after
  `nixos-rebuild switch`, which per FORBIDDEN COMMANDS is user-initiated only.
