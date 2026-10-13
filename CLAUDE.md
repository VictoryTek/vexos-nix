# CLAUDE.md
**vexos-nix** — Personal NixOS system configuration (Nix flake, 30 `nixosConfigurations`). Languages: Nix, Bash. Frameworks: NixOS 26.05, nixpkgs (stable + unstable overlay), home-manager, impermanence, disko, sops-nix. Package manager(s): Nix (flakes, `flake.lock`).

## Commands

Build:
- `sudo nixos-rebuild dry-build --flake .#vexos-<role>-<gpu>` (outputs are listed in `hostList` in `flake.nix`)
- `nix eval --impure ".#nixosConfigurations.<config>.config.system.build.toplevel.drvPath"` (full evaluation without building; what CI runs per config)

Test:
- `nix flake show --impure` (flake structure check, low RAM)

Preflight (final gate): `bash scripts/preflight.sh`
Fast verify (also run by the Stop hook): `nix flake show --impure`

## Repository

- Key directories:
  - `.` — `flake.nix` (`hostList` → `mkHost`), `configuration-<role>.nix`, `home-<role>.nix`
  - `hosts/` — per-output host configs `<role>-<gpu>.nix`
  - `modules/` — universal base modules and role/feature additions; `modules/gpu/` per GPU; `modules/server/` one file per service
  - `home/` — shared home-manager modules; `pkgs/` — custom packages; `lib/` — shared Nix helpers
  - `just/` — justfile recipes (`*.just`) and `lib.sh`, imported by the root `justfile`
  - `scripts/` — install, storage and migration scripts, plus `preflight.sh`
- Architecture: Thin flake; host-generated `/etc/nixos/hardware-configuration.nix` is imported by reference. Modules follow "common base + role additions": `modules/<subsystem>.nix` applies to every role that imports it, `modules/<subsystem>-<qualifier>.nix` holds role/feature additions, and each `configuration-<role>.nix` expresses its role entirely through its import list.
- CI environment: GitHub Actions (`ubuntu-latest`); `.github/workflows/ci.yml` runs static checks, then evaluates every config in 6 parallel groups (one per role) with a stub `hardware-configuration.nix`
- OS requirements: Linux with Nix. `nixos-rebuild dry-build` needs `/etc/nixos/vexos-variant` and `/etc/nixos/hardware-configuration.nix` on the machine. On a Windows checkout, run Nix through WSL.
- Build layout constraints: 30 outputs; evaluating all of them at once exhausts RAM on any single machine, so validate per target. Untracked new files are invisible to a `git+file` flake ref; evaluate with `path:.#...` before they are staged.
- Large disk side-effects: None identified beyond normal Nix store growth
- Other constraints: `hardware-configuration.nix` is generated per host and must never be committed
- Special constraints:
  - Do not add `lib.mkIf` guards that gate shared-module content by role, display, or gaming flag; create a `modules/<subsystem>-<qualifier>.nix` file instead. `lib.mkIf` on an option the same module declares (e.g. `vexos.btrfs.enable`) is fine.
  - `system.stateVersion` in `configuration-*.nix` must never change
  - New flake inputs set `inputs.nixpkgs.follows = "nixpkgs"` unless a comment in `flake.nix` justifies the exception
  - Keep the inline `unstableOverlayModule` (`pkgs.unstable.*`); never make `nixpkgs-unstable` follow `nixpkgs`
  - Recipe names and parameter order in `just/` are a contract with VexPortal (`just --dump`); recipes may run with stdin closed (no terminal)

## Forbidden commands

Never run these. They are also blocked in `.claude/settings.json` where possible.

### Universal (all repositories)

- `git add` (any form)
- `git commit` (any form, including `--amend`)
- `git push` (any form, including `--force`)
- `git stash` (any form, including `pop`, `apply`, `drop`)
- Any other git command that stages, commits, pushes, or stashes changes

What gets staged, committed, pushed, or stashed is the user's decision; the commit message at the end of every change is what the user runs. Read-only git (`status`, `log`, `diff`, `show`) is allowed.

### Project-specific

- `nix flake check` (any form, any flags) — reason: evaluates all 30 `nixosConfigurations` in parallel and exhausts RAM on any single machine. Use instead: `nix flake show --impure` plus per-target `nix eval --impure ...drvPath` or `sudo nixos-rebuild dry-build`
- `nixos-rebuild switch` (with or without `sudo`) — reason: applies the configuration to the live system; user-initiated only. Use instead: `sudo nixos-rebuild dry-build --flake .#vexos-<role>-<gpu>`
- `nixos-rebuild boot` (with or without `sudo`) — reason: schedules activation on next boot; user-initiated only. Use instead: `sudo nixos-rebuild dry-build --flake .#vexos-<role>-<gpu>`

## How to work

### Task size

State the tier in one line before starting.

- **Tier 1 — ask or explore** (questions, reading code, anything that changes no files): just answer. No commit message.
- **Tier 2 — standard change** (bug fix, small feature, config or docs change, tests; a few files, no new dependency, no change to a public interface, schema, or build/CI config): brief plan in chat (goal, assumptions, steps with how each is verified) → implement → verify → preflight → commit message.
- **Tier 3 — major change** (new dependency; many files or modules; public interface, schema, or migration; security-sensitive code; build, CI, or deploy config; hard to reverse): full plan in chat and **wait for approval** → implement → verify → independent review → preflight → commit message.

If a task fits two tiers, use the larger. If a Tier 2 task grows, stop, say so, and continue as Tier 3. The user can ask for more or less process ("just do it", "full process"); verification, forbidden commands, and the commit message still apply.

### Principles

1. **Think before coding.** State your assumptions. If a request has several valid readings, present them or ask; never pick one silently. If a simpler approach exists, say so.
2. **Simplicity first.** Write the minimum code that solves the problem: no extra features, no abstractions for single-use code, no unrequested configurability, no handling for cases that cannot happen. If 200 lines could be 50, rewrite it.
3. **Surgical changes.** Every changed line must trace to the request. Do not refactor or tidy adjacent code; match the existing style. Remove only the imports, variables, and functions your change orphaned. Mention unrelated dead code instead of deleting it.
4. **Goal-driven.** Turn the task into a check you can run before you start: bug fix → a failing test first, then make it pass; new behaviour → tests for it; refactor → tests pass before and after. For multi-step work, list the steps with "→ verify: …" for each.

### Done means verified

- Do not call work finished until the build and tests have actually run and you have reported the real output. Never write "passes" for something you did not run.
- Final gate: run the preflight command; the exit code must be 0. If none exists, run the build and test commands instead, say so, and offer to create a preflight script (do not create it unasked). A failure means the work is not finished.
- A Stop hook (`.claude/hooks/verify.sh`) re-runs the fast verify command when files have changed and blocks finishing on failure. Treat its report as a failed verification: fix it and re-run.
- Tier 3: before preflight, have the `reviewer` subagent review the diff. Give it the approved plan and the changed files, not your conclusions. If it is unavailable, review `git diff` yourself and say it was a self-review. Fix CRITICAL findings only; list RECOMMENDED ones for the user without implementing them.
- After 2 failed fix cycles (a failed review or preflight, fixed, failed again), STOP and report everything. Do not loop silently.
- Do not create spec, plan, or review files in the repository unless asked.

### Do not guess state

Before saying what is committed, pushed, or up to date, check: `git status`; `git log --oneline origin/$(git branch --show-current)..HEAD` (empty output means fully pushed); `stat flake.lock`. Never tell the user to push, commit, or update without checking first.

### Dependencies and APIs

Before adding a dependency or relying on a versioned API you are unsure of, check current documentation (Context7 MCP if available, otherwise the official docs). Not needed for internal changes, UI-only changes, or dependencies already in the lock file.

### Commit message (final step of every change)

Every change that modifies files ends with a commit message, however small (a one-line typo fix included). It is the last thing in your reply. You never run `git commit`; the user does. Before the message you may add a brief note: RECOMMENDED review items you did not implement, and unrelated issues you noticed.

Format, ready to paste into `git commit`:

```
<type>(<scope>): <description — MAX 72 characters total>

<PARAGRAPH EXPLAINING WHAT CHANGED AND WHY>

Modified Files:
- path/to/file1
- path/to/file2
- path/to/file3

✔ Build successful
✔ Tests passed
✔ Review approved
✔ Preflight passed
```

Valid types: `feat`, `fix`, `chore`, `refactor`, `docs`, `test`, `perf`. Example first line: `fix(network): disable swap on ZFS server roles`

Inside the message: no "Commit Message" heading, no "Edited" summary, no diff statistics, nothing outside the template.

Checkmark lines appear only for checks that actually ran and passed in this session; never include a line for a skipped check. `✔ Review approved` means the Tier 3 review returned PASS (write `✔ Review approved (self-review)` if no independent reviewer was used). Omit the Preflight line if no preflight exists.

After the message, if every check that ran passed, add one line:
> All checks passed. Code is ready to push to GitHub.
