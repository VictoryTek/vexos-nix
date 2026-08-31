# Hyprland + DankMaterialShell — Review & QA

Reviews the implementation of `hyprland_dms_session_spec.md`.

## Files changed

| File | Change |
|---|---|
| `flake.nix` | `noctalia` + `noctalia-greeter` inputs removed; single `dms` input added (`github:AvengeMedia/DankMaterialShell/stable`, `inputs.nixpkgs.follows = "nixpkgs"`). `noctaliaBase` → `dmsBase` = `[ inputs.dms.nixosModules.dank-material-shell inputs.dms.nixosModules.greeter ]` (no `nixpkgs.overlays` — DMS ships none). Wired into `roles.desktop.baseModules`. Comments rewritten. |
| `flake.lock` | Regenerated via `nix flake lock`: removed `noctalia`, `noctalia/nixpkgs`, `noctalia-greeter`, `noctalia-greeter/nixpkgs`; added `dms`, `dms/flake-compat`, `dms/nixpkgs` (follows `nixpkgs`). |
| `home/dank-material-shell.nix` | **new** — imports `inputs.dms.homeModules.dank-material-shell`; `config = lib.mkIf (env == "hyprland")` sets `programs.dank-material-shell` (enable, systemd.enable, `quickshell.package = pkgs.quickshell`, `dgop.package = pkgs.dgop`, feature toggles), keeps `services.hyprpolkitagent` + `services.udiskie`, adds `home.activation.seedHyprlandConf`. |
| `home/noctalia.nix` | **deleted** |
| `home-desktop.nix` | import swap `./home/noctalia.nix` → `./home/dank-material-shell.nix` |
| `files/hypr/hyprland.conf` | **new** — minimal DMS-focused compositor config (exec-once `dms run`, cliphist watcher, DMS IPC keybinds, screenshots, minimal WM) |
| `modules/hyprland-desktop.nix` | header + inline comments rewritten; greeter block `programs.noctalia-greeter` → `programs.dank-material-shell.greeter` (`enable`, `compositor.name = "hyprland"`, `quickshell.package`); `+ services.accounts-daemon.enable`; `+ fonts.packages = [ material-symbols inter ]`; `+ cliphist` in `environment.systemPackages`; comment text updated (Secret Service rationale, package-set header). Compositor / UWSM blocks unchanged. |
| `modules/branding-display.nix` | comment: "Hyprland uses noctalia-greeter" → "Hyprland uses the DankMaterialShell greeter" |
| `scripts/install.sh` | DE-picker label (2 places): "+ Noctalia shell" → "+ DankMaterialShell" |
| `justfile` | DE-picker label: "+ Noctalia shell" → "+ DankMaterialShell" |
| `modules/gpu/vm.nix` | **not changed** — `needsRenderNode` / `before = [ "greetd.service" ]` verified still correct (greetd is still the display manager; Hyprland is still the compositor). |

## Review against the checklist

### 1. Specification compliance — PASS

Every spec step implemented as written. Deviations, all minor and within spec latitude:

- **Seed activation placed in `home/dank-material-shell.nix`** (spec Step 5 left the layer open "decide during implementation"). HM `home.activation` is the right layer — it is where `$HOME` is known and matches the repo's other one-shot user-state seeders.
- **`services.accounts-daemon.enable = true` set unconditionally** rather than "if Phase 3 finds the greeter needs it" (spec §3.3). Set proactively — it is cheap, GNOME provided it implicitly, and the greeter reads the user list through it. No downside.
- **`fonts.packages` block** added per spec §3.6 ("Phase 2 check"). See finding F-1 — it is partly redundant with a contribution from the greeter module, but harmless and clearer as an explicit declaration.

### 2. Best practices (Nix / NixOS / nixpkgs) — PASS

- `inputs.nixpkgs.follows = "nixpkgs"` on the new input, per CLAUDE.md. **Verified to actually build** — see Build Validation; the `follows = "nixpkgs-unstable"` fallback in the spec's risk table is **not needed**.
- `imports` sits outside the `mkIf` in `home/dank-material-shell.nix` (imports cannot be conditional); upstream module inert until `enable`.
- No new flake input without `follows` (the `dms/flake-compat` transitive node is upstream's, not ours to pin).
- `pkgs.quickshell` / `pkgs.dgop` from the 26.05 pin — both confirmed present (quickshell 0.3.0, dgop 0.2.2) and the DMS module's own recommendation ("at least 0.3.0, currently in nixos-unstable") is satisfied by 26.05.

### 3. Module Architecture Pattern (Option B) — PASS

- `modules/hyprland-desktop.nix` keeps its single `lib.mkIf (config.vexos.desktop.environment == "hyprland")` guard — the CLAUDE.md carve-out (toggleable subsystem gated on an option its own module family declares) and identical in shape to `gnome.nix` / `cosmic-desktop.nix`. **No new** role-/flag-gating `mkIf` added to any shared module.
- `home/dank-material-shell.nix` is `{ imports = …; config = lib.mkIf cond { … }; }` — a valid module, gated internally, imported unconditionally by `home-desktop.nix`. Exactly the shape of the deleted `home/noctalia.nix` and of `home/gnome-common.nix`.
- `fonts.packages` in `modules/hyprland-desktop.nix` (role addition), not `modules/desktop-common.nix` (DE-agnostic base) — correct per the naming/placement rule.

### 4. Maintainability — PASS

Comments rewritten to describe the DMS reality (greeter runs Hyprland itself; UWSM still load-bearing; the seeded-once config and why). The `files/hypr/hyprland.conf` header tells the user the file is theirs to edit. Two residual "noctalia" mentions remain and are deliberate historical context ("GNOME pulled this in implicitly" / "unlike vexboardBase") — not stale references to removed code.

### 5. Completeness — PASS

Shell, greeter, compositor keybinds, clipboard backend, fonts, Secret Service, polkit, automount, portals, Flatpak parity all present. `nix flake show` still lists exactly **30** `nixosConfigurations`. CI matrix (`.github/workflows/ci.yml`) unchanged — no config renamed.

### 6. Performance — PASS

No evaluation regression (hyprland branch evals in ~35 s cold). DMS pulls a Qt/Quickshell closure the previous Noctalia shell did not, but that is the intended trade of the change, and `dms-shell` + `quickshell` are both in `cache.nixos.org` (fetched, not built, during validation — only the tiny `dms-shell` Go wrapper builds locally).

### 7. Security — PASS

No secrets, no world-writable files, no plaintext credential assignments. `seedHyprlandConf` runs as the user, writes only under `$HOME/.config/hypr`, and is guarded by `[ ! -e ]` so it can never clobber user edits. `preflight.sh` stage 7 (secret scan, plaintext-path guards, sops consistency) unaffected — no server modules touched.

### 8. API currency — PASS

DMS module surface read directly from the `stable` branch at implementation time (`flake.nix`, `distro/nix/{home,options,nixos,greeter,common}.nix`). Option names used (`programs.dank-material-shell.{enable,systemd.enable,quickshell.package,dgop.package,enableSystemMonitoring,enableCalendarEvents,enableDynamicTheming,enableAudioWavelength,enableVPN}` and `programs.dank-material-shell.greeter.{enable,compositor.name,quickshell.package}`) all resolve without "unknown option" errors in a full eval. Context7 N/A (Nix flake input, not a documented library).

## 9. Build Validation (WSL, Nix 2.34.1)

`nixos-rebuild` cannot run off-NixOS; all other stages executed. Because the new files are not yet `git add`ed, a git-flake eval cannot see them — validation was run against a `.git`-excluded working-tree copy (`rsync` to a scratch dir), which is byte-identical to what a commit will contain.

| Check | Command | Result |
|---|---|---|
| Flake structure | `nix flake show --impure` | **PASS** — 30 `nixosConfigurations`, no eval errors |
| Full eval — hyprland/DMS branch | `extendModules { vexos.desktop.environment = "hyprland"; }` → `config.system.build.toplevel.drvPath` | **PASS** — `nixos-system-vexos-26.05.drv` produced |
| Full eval — `vexos-desktop-vm` (default env) | `…toplevel.drvPath` | **PASS** |
| Full eval — `vexos-desktop-amd` | `…toplevel.drvPath` | **PASS** |
| Full eval — `vexos-desktop-nvidia` | `…toplevel.drvPath` | **PASS** |
| Greeter wiring | eval `services.greetd.enable` / `programs.dank-material-shell.greeter.enable` / `services.greetd.settings.default_session.command` | **PASS** — `true` / `true` / `…/dms-greeter/bin/dms-greeter` |
| Shell service | eval `home-manager.users.<u>.systemd.user.services.dms` | **PASS** — unit present ("DankMaterialShell") |
| Seed activation | eval `home-manager.users.<u>.home.activation.seedHyprlandConf` | **PASS** — entry present |
| Secret Service / accounts-daemon / UWSM | eval | **PASS** — `gnome-keyring` true, `accounts-daemon` true, `uwsm.waylandCompositors = ["hyprland"]` |
| Fonts | eval `fonts.packages` | **PASS** — `material-symbols` + `inter` present (see F-1) |
| **`dms-shell` builds against 26.05** | `nix build …programs.dank-material-shell.package` | **PASS** — `dms-shell-1.5.3+date=2026-07-27_069ddab` built; **settles the `follows` risk — no fallback needed** |
| Full closure dry-run — hyprland branch | `nix build --dry-run` on the extended toplevel | **PASS** — entire closure resolves, nothing unbuildable |
| `hardware-configuration.nix` not tracked | `git ls-files` | **PASS** — empty |
| `system.stateVersion` unchanged | no `configuration-*.nix` touched | **PASS** |
| Nix formatting | `nixpkgs-fmt --check` | **N/A** — pristine repo files also fail it; repo uses a columnar house style, CI runs no formatter, preflight stage 6 is WARN-only. New files match the surrounding house style. |

## 10. Findings

### F-1 (RECOMMENDED, cosmetic) — `fonts.packages` partly redundant

`material-symbols` and `inter` appear twice in the evaluated `fonts.packages`: once from the explicit block added to `modules/hyprland-desktop.nix`, once from a contribution by `inputs.dms.nixosModules.greeter` (the greeter needs the same faces to render). Duplicate entries are de-duplicated by Nix at the store level — **zero runtime effect**. Keeping the explicit declaration is the right call: it states the shell's font requirement independently of the greeter, so the shell stays correctly fonted if the greeter is ever disabled or upstream stops contributing them. No change required; recorded for awareness.

### F-2 (INFORMATIONAL) — new files must be staged before the commit evaluates

`home/dank-material-shell.nix` and `files/hypr/hyprland.conf` are new and currently untracked. A git-flake `nix` command (and CI) will not see them until they are added to the index. This resolves itself when the user runs `git add` as part of committing (Phase 7), but a `nixos-rebuild` attempted from the working tree *before* committing would fail with `path '…/home/dank-material-shell.nix' does not exist`. Called out in the Phase 7 notes.

### F-3 (INFORMATIONAL) — `dms` `stable` is ~5 weeks behind at lock time

`nix flake lock` pinned `dms` to a `stable` commit dated 2026-07-27 (`dms-shell` 1.5.3). This is expected for a `stable` branch and the daily `chore: update flake inputs` job will advance it. `preflight.sh` stage 5c will emit a freshness **WARN** (>30 days) on the very first push until that job runs; WARN does not fail preflight.

## Verdict

**PASS** — proceed to Phase 6 (Preflight).

No CRITICAL or RECOMMENDED-blocking issues. All build/eval validation green, including the one empirical question the spec flagged (DMS building against the 26.05 pin — it does). F-1 is cosmetic, F-2/F-3 are informational.

| Category | Score | Grade |
|----------|-------|-------|
| Specification Compliance | 98% | A |
| Best Practices | 97% | A |
| Functionality | 95% | A |
| Code Quality | 96% | A |
| Security | 100% | A |
| Performance | 95% | A |
| Consistency | 100% | A |
| Build Success | 100% | A |

**Overall Grade: A (97%)**
