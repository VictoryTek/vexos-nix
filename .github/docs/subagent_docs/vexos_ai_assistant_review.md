# VexOS AI Assistant — Review (Phase 3)

Spec: `.github/docs/subagent_docs/vexos_ai_assistant_spec.md` (§4.7 lists implementation deviations)
Date: 2026-10-05
Validated in WSL (Nix 2.34.1). `nixos-rebuild dry-build` is not available there, so full evaluation via `nix eval … toplevel.drvPath` was used, the same check CI runs.

## Files

New:
- `modules/ai.nix`
- `pkgs/vexos-ai/default.nix`, `pkgs/vexos-ai/vexos-ai.sh`
- `files/ai/skills/vexos/SKILL.md`, `files/ai/skills/vexos-diagnose/SKILL.md`
- `template/local.nix`
- this review, and the spec

Modified:
- `configuration-{desktop,htpc,server}.nix` (import)
- `pkgs/default.nix`
- `pkgs/vexos-update/default.nix` (`local.nix` auto-heal + git tracking)
- `template/etc-nixos-flake.nix`
- `template/features.nix`
- `justfile` (`ai` feature, vanilla guard, `agent`, `diagnose`, rebuild failure hint)
- `modules/gnome-desktop.nix` (Super+Shift+A)
- `files/hypr/hyprland.conf` (Super+Shift+A)

## Build validation

| Check | Result |
|---|---|
| `vexos-ai` package build (writeShellApplication shellcheck) | PASS |
| `vexos-update` build (shellcheck), path mode | PASS |
| Eval `vexos-desktop-amd` ai=on / ai=off | PASS / PASS |
| Eval `vexos-desktop-nvidia`, `vexos-desktop-vm`, `vexos-htpc-amd`, `vexos-server-amd`, all ai=on | PASS |
| Eval `vexos-headless-server-amd`, `vexos-stateless-amd`, `vexos-vanilla-amd` (unaffected) | PASS |
| Generated Claude managed settings, OpenCode managed config, tmpfiles links, user services and timer | Inspected, correct |
| Usage parser on percent, fraction, empty and string payloads | PASS |
| Accounts, mode, threshold validation, theme files, crash-mute (temp HOME) | PASS |
| Wrapper auto-heal sed on the HEAD template: patches, idempotent, `nix-instantiate --parse` | PASS |
| `just --list` / `--show` / `--evaluate` | PASS |
| `hardware-configuration.nix` untracked; `stateVersion` unchanged; no new flake inputs | PASS |

## Findings

- **Fixed during review:**
  - The `local.nix` detection matched `hardware-local.nix` (`./local.nix` is now matched exactly).
  - `if ! cmd; then _rc=$?` always yields 0 (the `rebuild` hint now uses `cmd || { _rc=$?; … }`).
  - The zenity extra button cannot report the selected row (Remove now asks which account).
  - `just --list` showed the wrong comment line.
- **Pre-existing, not changed:** the `switch` recipe in the justfile uses the same `if ! …; then _rc=$?` pattern, so its exit-code-4 branch can never trigger.
- **Needs a real host (manual):**
  - the zenity and notify-send `--action` flows on GNOME, COSMIC and Hyprland
  - whether a desktop user can read coredump journal entries (journal ACLs) for the crash watcher
  - `nixos-rebuild dry-build` as a non-root user against `path:/etc/nixos`
  - `claude auth login` with `CLAUDE_CONFIG_DIR` for extra accounts
  - the Anthropic usage endpoint (undocumented; failures degrade to "unknown")
- **Security:**
  - No secrets are stored. The OAuth token is passed to curl on stdin, never in argv.
  - Diagnose facts are written to a mode-0600 `mktemp` file.
  - Deny rules are a guardrail. The enforced boundary is root and a password prompt (pkexec/sudo), and the spec documents this.
- **Option B:** `lib.mkIf` only on the module's own `vexos.features.ai.enable` (carve-out). No role gating was added to shared modules. The GNOME keybinding entry is unconditional and inert without the feature.

| Category | Score | Grade |
|---|---|---|
| Specification Compliance | 92% | A- |
| Best Practices | 92% | A- |
| Functionality | 88% | B+ |
| Code Quality | 92% | A- |
| Security | 93% | A |
| Performance | 95% | A |
| Consistency | 93% | A |
| Build Success | 100% | A |

**Overall Grade: A- (93%)**. Functionality is capped until the manual host checks above are done.

**Result: PASS.** Preflight (Phase 6) is blocked only because the new files are untracked: git-mode flake evaluation cannot see them until they are added with `git add`.
