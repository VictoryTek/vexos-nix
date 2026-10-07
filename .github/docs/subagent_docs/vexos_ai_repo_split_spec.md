# vexos-ai repo split — Specification (Phase 1)

Extract the AI assistant (`pkgs/vexos-ai`, `files/ai/skills`, and the body of
`modules/ai.nix`) into its own repo, `VictoryTek/vexos-ai` (cloned at
`~/Projects/vexos-ai`, currently only `LICENSE` + `README.md`), consumed by
this flake as an input — the same pattern as `vex-vpn`, `vexportal` and `up`.

**Scope of this change: stage 1 only — a behaviour-preserving move.** The
rewrite/refactor and the GTK4/libadwaita GUI are separate later specs that live
entirely in the new repo.

## 1. Current state

| Piece | Location | Notes |
|---|---|---|
| Launcher, picker, Claude accounts, usage, theme sync, crash watch, welcome | `pkgs/vexos-ai/vexos-ai.sh` (580 lines), `pkgs/vexos-ai/default.nix` | `writeShellApplication` + desktop item, exposed as `pkgs.vexos.vexos-ai` via `pkgs/default.nix:16` |
| Skills `vexos`, `vexos-diagnose` | `files/ai/skills/*/SKILL.md` | Linked into `~/.claude/skills` |
| Module | `modules/ai.nix` | Declares `vexos.features.ai.enable`; installs `pkgs.unstable.claude-code`/`opencode`; writes managed deny policy (Claude + OpenCode); skills symlinks; 4 user services + 1 timer |
| Role wiring | `configuration-{desktop,htpc,server}.nix` import `modules/ai.nix` | |
| Glue (stays) | `modules/gnome-desktop.nix:55-66` keybinding, `files/hypr/hyprland.conf`, `justfile` (`agent`, `diagnose`, lines ~710/1426/1434/1514/1633) | All call the `vexos-ai` command by name — unchanged |

## 2. Problem

The assistant has outgrown a bash script inside a system-config repo. It needs
its own tests, CI, release cadence and (later) a GUI. Every iteration today
costs a full vexos-nix preflight/dry-build cycle.

## 3. Design

### 3.1 Boundary

`vexos-ai` (new repo) owns everything about *how the assistant works*: package,
skills, agent deny-policy, user services, desktop item.
`vexos-nix` owns *whether and where it runs*: the `vexos.features.ai.enable`
toggle, role gating, nixpkgs-unstable package choice, keybinding/justfile glue.

This mirrors `vex-vpn`: its module (`programs.vex-vpn`) does install-only; the
feature toggle (`vexos.features.vpn.enable`) lives in `modules/vpn.nix` and sets
`programs.vex-vpn.enable`.

### 3.2 New repo layout (`~/Projects/vexos-ai`)

```
flake.nix            inputs: nixpkgs (nixos-26.05). outputs: packages, overlays.default,
                     nixosModules.default, checks (shellcheck via the package build), devShells
nix/package.nix      { pkgs } -> writeShellApplication + desktop item (moved from pkgs/vexos-ai/default.nix)
nix/module.nix       { mkVexosAi } -> NixOS module `programs.vexos-ai`
bin/vexos-ai.sh      moved verbatim from pkgs/vexos-ai/vexos-ai.sh
skills/vexos/SKILL.md, skills/vexos-diagnose/SKILL.md   moved verbatim
README.md, CLAUDE.md short architecture + versioning note
.github/workflows/ci.yml   nix build .#default, nix flake check is allowed here (single small flake)
```

`flake.nix` follows `vex-vpn/flake.nix` (`systems`, `forAllSystems`,
`mkVexosAi pkgs`, `overlays.default`, `nixosModules.default`). No crane — the
package is pure shell.

### 3.3 `programs.vexos-ai` options (new repo `nix/module.nix`)

- `enable` — `mkEnableOption`.
- `claudePackage` / `opencodePackage` — `types.package`, defaults `pkgs.claude-code` / `pkgs.opencode`.
  **Why:** the module cannot see vexos-nix's `pkgs.unstable`; the consumer injects it.
- Config when enabled (moved from `modules/ai.nix`, logic unchanged):
  systemPackages (both agents + vexos-ai); `environment.etc."vexos/ai/skills".source = ../skills`;
  `systemd.user.tmpfiles.rules` skill links; `claude-code/managed-settings.d/50-vexos.json`;
  `opencode/opencode.json`; user services `vexos-ai-{crash-watch,theme-watch,welcome}`;
  `vexos-ai-usage` service + timer. The `appliers`/`denied` list moves with it
  (it is the assistant's own safety policy).

### 3.4 vexos-nix changes

1. `flake.nix`: add input
   ```nix
   vexos-ai = {
     url = "github:VictoryTek/vexos-ai";
     inputs.nixpkgs.follows = "nixpkgs";
   };
   ```
   and `vexosAiModule = { imports = [ inputs.vexos-ai.nixosModules.default ]; };`
   (top-level, not in `modules/ai.nix`, for the same `inputs`-in-`imports`
   reason documented at `vexVpnModule`). Append it to `baseModules` of exactly
   the roles that import `modules/ai.nix` today: **desktop, htpc, server**
   (flake.nix lines ~343, 349/355 stay as-is; desktop/htpc/stateless share one
   list on 349/355, so confirm in Phase 2 that stateless — which does not
   import `modules/ai.nix` — only gets the *option declaration*, which is
   inert with `enable = false`).
2. `modules/ai.nix` shrinks to the vpn.nix pattern:
   ```nix
   options.vexos.features.ai.enable = lib.mkEnableOption "...";
   config = lib.mkIf cfg.enable {
     programs.vexos-ai = {
       enable = true;
       claudePackage = pkgs.unstable.claude-code;
       opencodePackage = pkgs.unstable.opencode;
     };
   };
   ```
   (`mkIf` on its own declared option — the Option B carve-out.)
3. Delete `pkgs/vexos-ai/`, `files/ai/skills/`, and the `vexos-ai` line in `pkgs/default.nix`.
4. `modules/gnome-desktop.nix`, `justfile`, `hyprland.conf`: **no change** (command name `vexos-ai` is preserved).
5. Historical docs (`vexos_ai_assistant_*.md`) are left untouched; this spec supersedes the module location.

### 3.5 Decisions / assumptions (surfaced, per CLAUDE.md §1)

- **Skills move with the repo.** They were not answered earlier; this is the
  default. Drift risk (they describe vexos-nix's justfile and `/etc/nixos`
  side-files) is bounded because `flake.lock` pins the pair, and the repo's
  CLAUDE.md will say "skills must be updated when vexos-nix's justfile changes".
- **Rust/GTK GUI deferred.** Stage 1 keeps bash so behaviour is verifiably identical.
- **Module default packages vs unstable:** option injection (above) chosen over
  adding `nixpkgs-unstable` as a second input of vexos-ai — simpler, no second eval.
- Follows `nixpkgs` (stable) — no binary-cache or toolchain reason to deviate.

## 4. Implementation steps

New repo (`~/Projects/vexos-ai`) — files only; **no git add/commit/push by Claude**:
1. `bin/vexos-ai.sh` ← `cp` of `pkgs/vexos-ai/vexos-ai.sh`; `skills/` ← `files/ai/skills/`.
2. `nix/package.nix` from `pkgs/vexos-ai/default.nix`, taking `{ pkgs }`, `readFile ../bin/vexos-ai.sh`.
3. `nix/module.nix` per §3.3 (skills source `../skills`).
4. `flake.nix`, `README.md`, `CLAUDE.md`, `.gitignore`, `.github/workflows/ci.yml`.
5. Verify in that repo: `nix build .#default`, `nix eval .#nixosModules.default`, `shellcheck` is already enforced by `writeShellApplication`.

vexos-nix: §3.4 edits, then `nix flake lock`-free validation using an override.

## 5. Validation (safe commands only)

The new input has no lock entry and no pushed commit yet, so Phase 3/6 validate
with an override (no `flake.lock` churn):

```
nix flake show --impure --override-input vexos-ai path:$HOME/Projects/vexos-ai
sudo nixos-rebuild dry-build --flake .#vexos-desktop-amd --override-input vexos-ai path:$HOME/Projects/vexos-ai
… desktop-nvidia, desktop-vm, htpc-amd, stateless-amd, server-amd (touches ai on server), headless-server-amd
```

Plus: an eval with `vexos.features.ai.enable = true` that asserts the same
`environment.etc` keys and `systemd.user.services` names exist before and after
(`nix eval` of `config.environment.etc."claude-code/managed-settings.d/50-vexos.json".text`
on the pre-change commit vs post-change — must be byte-identical).
Per memory, flake eval cannot see untracked files — use `path:$PWD#…` refs for
the vexos-nix side. `nix flake check` stays forbidden in vexos-nix.

## 6. Risks and mitigations

| Risk | Mitigation |
|---|---|
| **Ordering:** vexos-nix cannot lock/evaluate without a pushed `vexos-ai` main | Phase 7 commit message ordering: user commits+pushes `vexos-ai` first, then runs `nix flake update vexos-ai` here and commits `flake.lock`. CI in vexos-nix fails until then — state this in the delivery. |
| Policy regression (deny list silently lost) | Byte-identical JSON comparison in §5 |
| `programs.vexos-ai` option name collides | None existing (`grep programs.vexos-ai` empty) |
| Stateless/headless get an inert option | `enable` defaults false; no config produced |
| `claude-code` unfree: default `pkgs.claude-code` would fail eval in a consumer without allowUnfree | Always overridden here; documented in module option description |
| Skills drift from justfile | Repo CLAUDE.md rule + lock pin |
| Private/`gh` auth for fetching a new GitHub input on installed hosts | Repo is public like the others — confirm visibility before Phase 7 |

## 7. Dependencies

No new third-party dependencies. `nixpkgs` follows vexos-nix's pin. (Context7
not required: no new external libraries, only an in-house flake.)
