# VexOS AI Assistant — Specification (Phase 1)

Status: DRAFT, awaiting user review before Phase 2
Date: 2026-10-05
Decisions made by the user:
- Scope: all four pieces (skill + launcher, local.nix, diagnose hooks, picker UI)
- Agents: Claude Code + OpenCode
- Autonomy: the agent edits and dry-builds; the user applies with `just rebuild`

---

## 1. What Omarchy does (reference design)

Source: `omacom/omarchy` branch `quattro`, read directly from the repo.

| Piece | Omarchy implementation | What it achieves |
|---|---|---|
| Agent install | mise stubs in `~/.local/bin/<agent>`, installed on first use | No cost until an agent is chosen |
| Default agent | `bin/omarchy-default-agent` writes `~/.config/omarchy/defaults/agent` | One place to store the choice |
| Launcher | `bin/omarchy-agent [--prompt]`: cds to `~/Work`, maps each agent to its own "auto-approve" flag, opens a terminal | Any feature can hand a task to the agent of choice |
| OS knowledge | `default/agents/skills/omarchy/SKILL.md`, symlinked into `~/.claude/skills`, `~/.codex/skills`, `~/.agents/skills`, … | The agent knows read-only paths (`/usr/share/omarchy`), safe paths (`~/.config`), the CLI (`omarchy commands --json`), and sudo vs pkexec |
| Crash help | `omarchy-crash-watch.service` (user) tails `journalctl MESSAGE_ID=fc2e22bc6ee647b6b90729ab34a250b1` and sends a toast; a click runs `omarchy-agent-crash <pid>`, which builds a prompt that points at the `diagnose-crash` skill | One click from "something broke" to an explanation |
| First run | `install/user/first-run/setup-agent.hook` sends a one-time "Set your default agent" notification that opens the picker menu | Discoverability |
| Sign-in | Delegated to each agent's own OAuth on first launch | No credential handling in the OS |

Omarchy's **diagnose-crash** skill rules are worth keeping verbatim in spirit: work from evidence; diagnosis is read-only; extract the core to `mktemp` and delete it afterwards; never invent symbol names; offer (never apply unprompted) to mute a program.

Omarchy's **autonomy model** runs agents in auto-approve (`claude --permission-mode auto`, `opencode --auto`, …). **VexOS will not copy this** (see §3).

## 2. Current state of VexOS

- `modules/development.nix:65-66` already ships `pkgs.claude-code` and `pkgs.mcp-nixos` behind `vexos.features.development.enable`. There is no OS skill, launcher, guardrail, or diagnose flow.
- On an installed host, `/etc/nixos/flake.nix` is a thin wrapper (`template/etc-nixos-flake.nix`) that pulls the upstream config from GitHub. **The upstream config is effectively read-only on the host**, the same role `/usr/share/omarchy` plays.
- The host's **editable surface** is the `/etc/nixos` side-files, each loaded with `builtins.pathExists`:
  - `features.nix` (written by `just enable-feature`)
  - `hostname.nix`, `bootloader.nix`, `hardware-local.nix`, `vm-platform.nix`, `user-override.nix`
  - `server-services.nix`, `storage-*.nix`, `zfs-pools.nix`
- **The CLI equivalent** of `omarchy commands` is the `justfile` (`just --list`, `just --dump --dump-format json`). Recipes include `features`, `enable-feature`, `rebuild`, `rollback`, `services`, `enable <svc>`, `status <svc>`.
- **Gap:** no side-file accepts arbitrary configuration (extra packages, udev rules, tweaks). An agent asked to "install htop" has no correct place to write.
- Desktop environments: desktop uses GNOME (default), COSMIC, or Hyprland with the Noctalia shell. HTPC, server (GUI), and vanilla use GNOME or none. `files/hypr/hyprland.conf:219` binds `$mod+Return` to the terminal.
- Feature modules (`development.nix`) are imported by `configuration-{desktop,htpc,server,vanilla}.nix`. Stateless and headless-server have no `features.nix`.

## 3. Key design difference from Omarchy

| | Omarchy | VexOS |
|---|---|---|
| What the agent edits | Live dotfiles in `~/.config` | Nix side-files in `/etc/nixos` |
| When the change applies | Immediately | Only after `just rebuild` |
| Undo | `omarchy refresh` / manual | NixOS generations: `just rollback` or the boot menu |
| Agent autonomy | Auto-approve | Default (asks), with switch/boot denied |

**Trust boundary:** the agent may read anything, edit `/etc/nixos/*.nix` side-files (requires sudo, so it asks), and run `nixos-rebuild dry-build`. It may **not** run `nixos-rebuild switch|boot`, `just rebuild|switch|update`, or `nix flake check`. The user applies changes. This matches the existing rule in `CLAUDE.md`.

The deny-lists are guardrails, not a sandbox: an agent could still write a script that calls switch. The real boundary is that switching needs `sudo`, and sudo prompts for the user's password in the terminal. Phase 2 must confirm `security.sudo.wheelNeedsPassword` is not disabled anywhere.

## 4. Proposed solution

### 4.1 New feature: `vexos.features.ai.enable` — `modules/ai.nix`

This is a feature module like `development.nix`. `lib.mkIf` on its own declared option falls under the carve-out in the Option B rules. Imported by `configuration-{desktop,htpc,server,vanilla}.nix`, the same set as `development.nix`. It contains:

1. **Packages:** `pkgs.unstable.claude-code`, `pkgs.unstable.opencode`, `pkgs.vexos.vexos-ai`, `pkgs.xdg-terminal-exec`, `pkgs.zenity`, `pkgs.libnotify`.
   - Unstable, because agent CLIs ship weekly: stable opencode is 1.15.10 and unstable is 1.18.34.
   - `development.nix` keeps its `claude-code` line. Listing it twice is harmless; Phase 2 must confirm the evaluated version doesn't conflict.
2. **Skills installed system-wide:** `environment.etc."vexos/ai/skills".source = ../files/ai/skills;`.
3. **Per-user symlink, one for both agents:** `systemd.user.tmpfiles.rules = [ "L+ %h/.claude/skills/vexos - - - - /etc/vexos/ai/skills/vexos" "L+ %h/.claude/skills/vexos-diagnose - - - - /etc/vexos/ai/skills/vexos-diagnose" ];`
   - OpenCode loads `~/.claude/skills/*/SKILL.md` (opencode.ai/docs/skills), so one link covers both.
   - `L+` replaces only the link and leaves other user skills alone.
4. **Claude guardrails:** `environment.etc."claude-code/managed-settings.json".text = builtins.toJSON { permissions.deny = [ "Bash(sudo nixos-rebuild switch:*)" "Bash(sudo nixos-rebuild boot:*)" "Bash(nixos-rebuild switch:*)" "Bash(nixos-rebuild boot:*)" "Bash(just rebuild:*)" "Bash(just switch:*)" "Bash(just update:*)" "Bash(nix flake check:*)" ]; };`
   - Managed settings cannot be overridden by the user's `~/.claude/settings.json`.
   - Phase 2 must verify the managed-settings path and rule syntax against the current Claude Code docs.
5. **OpenCode guardrails:** `environment.etc."vexos/ai/opencode.json"` with `permission.bash = { "*" = "ask"; "sudo nixos-rebuild switch*" = "deny"; … }`. The last matching rule wins, so `"*"` goes first.
   - Wired with `environment.sessionVariables.OPENCODE_CONFIG = "/etc/vexos/ai/opencode.json";`.
   - **Verify in Phase 2** that `OPENCODE_CONFIG` merges with, rather than replaces, `~/.config/opencode/opencode.json`. If it doesn't, fall back to `home-manager.sharedModules` setting `programs.opencode.settings.permission`.
6. **Crash watcher:** `systemd.user.services.vexos-crash-watch` (wantedBy `graphical-session.target`) runs `vexos-ai crash-watch` (§4.3).
7. **Desktop entry:** "VexOS Assistant" `.desktop` file shipped by the package. It appears in the GNOME, COSMIC, and Noctalia launchers and has a "Change AI assistant" desktop action.

Not included: stateless (impermanence wipes `~/.claude` sign-in on every boot) and headless-server (no `features.nix`; headless users can run `claude` directly). Both are listed as follow-ups.

### 4.2 Escape hatch: `/etc/nixos/local.nix`

- `template/etc-nixos-flake.nix`: add `localFile = ./local.nix; hasLocal = builtins.pathExists localFile;` and append to `localFiles`, following the exact pattern of `hostnameFile`.
- `flake.nix`: add a matching `localModule` (`/etc/nixos/local.nix`, the same pattern as `featuresModule`) to the direct-checkout `mkHost` path for all roles.
- `template/local.nix`: a commented starter (`{ pkgs, ... }: { environment.systemPackages = [ ]; }`) with a header that says it is user- and agent-owned and never overwritten.
- **Existing hosts:** the wrapper is written once and never resynced (see `scripts/upgrade-wrapper.sh` header). `pkgs/vexos-update` already auto-heals missing `features.nix` wiring. Add the same for `local.nix`:
  - if the wrapper has a `localFiles =` definition but no `local.nix`, insert `(lib.optional (builtins.pathExists ./local.nix) ./local.nix) ++` after it;
  - add `local.nix` to the force-`git add` list (vexos-update builds with `git+file:///etc/nixos`, which ignores untracked files).

  The skill tells the agent to check `grep local.nix /etc/nixos/flake.nix` before writing the file.

### 4.3 Launcher and picker: `pkgs/vexos-ai` (writeShellApplication)

Registered in `pkgs/default.nix` as `pkgs.vexos.vexos-ai`.

```
vexos-ai                      open default agent in a terminal, cwd /etc/nixos
vexos-ai --prompt "<text>"    same, seeded with a task
vexos-ai pick                 zenity list: Claude Code | OpenCode → ~/.config/vexos/agent
vexos-ai diagnose [unit]      gather facts → --prompt pointing at vexos-diagnose skill
vexos-ai crash <pid> [...]    coredump facts → --prompt
vexos-ai crash-watch          journal follower (service entrypoint)
```

- **First run:** if `~/.config/vexos/agent` is missing, run `pick` first. After the pick, the first launch shows each agent's own sign-in (Claude's `/login` browser OAuth; `opencode auth login`), so VexOS never handles credentials.
- **Agent invocation:** use the agents' **default, asking** modes: `claude [-- "<prompt>"]` and `opencode [--prompt "<prompt>"]`. No auto-approve flags.
- **Terminal:** `xdg-terminal-exec` (works on GNOME, COSMIC, and Hyprland) when not already in a TTY.
- **diagnose:** collects:
  - `systemctl --failed`
  - `journalctl -b -p err -n 200`
  - for a named unit: `systemctl status <unit>` and `journalctl -u <unit> -b -n 200`
  - variant: `/etc/nixos/vexos-variant`
  - current generation: `nixos-rebuild list-generations | tail -3`

  It writes these to a `mktemp` file and passes its path in the prompt instead of inlining logs.
- **crash-watch:** a port of `omarchy-crash-watch`. It keeps the same safeguards: same-UID only, 60-second dedupe, a name-sanitised mute flag under `~/.config/vexos/crash-ignore/`, and it ignores its own processes. It uses `notify-send --action=diagnose="Diagnose with AI" --wait`. libnotify 0.8+ prints the chosen action. On click it runs `vexos-ai crash …`.
- **justfile:** add `agent` and `diagnose unit=""` recipes as thin wrappers.
  - In the `switch`/`rebuild` failure branches, print one hint line: "Run `just diagnose` to have the AI explain this failure."
  - Add `ai` to `_feature_names` (justfile:1423), the `features` listing, and `template/features.nix`.

### 4.4 Keybinding

- Hyprland: `bind = $mod SHIFT, A, exec, vexos-ai` in `files/hypr/hyprland.conf`. First check the chord is free.
- GNOME: a custom keybinding. **Risk:** `modules/gnome-desktop.nix:53` sets `custom-keybindings` as a full list, so a second module that sets the same key would replace it rather than add to it. Phase 2 reads how the dconf databases merge there, then either makes that key a merged list `modules/ai.nix` can append to, or skips the GNOME keybind. The desktop entry in §4.1 still makes the assistant launchable without it.

### 4.5 Skills (content lives in `files/ai/skills/`)

**`vexos/SKILL.md`**: frontmatter description triggers on "change/install/enable/configure anything on this VexOS/NixOS system". Body:

- **Identify the system:** `cat /etc/nixos/vexos-variant` (role + GPU) and `just features`.
- **Read-only:** the upstream VexOS config. Locate the source with `nix flake metadata /etc/nixos --json | jq -r '.locks.nodes."vexos-nix".locked'` or the store path, and read modules to understand options. Never edit the Nix store or attempt to edit upstream.
- **Editable, in order of preference:**
  1. A `just` recipe if one exists (`just --list`), e.g. `just enable-feature gaming`.
  2. The matching side-file (`features.nix`, `hostname.nix`, …). The skill includes a table of what each holds.
  3. `/etc/nixos/local.nix` for anything else.
- **Never:** `hardware-configuration.nix`, `system.stateVersion`, `vexos-variant`, `user-override.nix`, secrets.
- **Home-manager owns dotfiles.** Editing `~/.config/*` files that are store symlinks is lost on rebuild; say so and use Nix instead.
- **Find packages and options:** `nix search nixpkgs <x>`, plus `mcp-nixos` if available.
- **Validate:** `nixos-rebuild dry-build --impure --flake path:/etc/nixos#$(cat /etc/nixos/vexos-variant)`. Phase 2 confirms whether this needs sudo.
- **Hand-off:** show `sudo diff`/`git diff` of side-files, then tell the user to run `just rebuild`. Undo is `just rollback`. Never run switch/boot yourself.
- **Privilege:** sudo in the visible terminal only.

**`vexos-diagnose/SKILL.md`**: adapted from Omarchy's diagnose-crash, and also covers failed units and failed rebuilds:

- evidence first; rule out OOM (`journalctl -k | grep -i oom`)
- correlate with the generation timeline (a regression right after a rebuild points at the rebuild; `nixos-rebuild list-generations`)
- NixOS has no public debuginfod by default, so expect unsymbolised frames and never invent names
- delete extracted cores
- read-only; the only allowed change is the offered mute
- if a fix is warranted, hand off to the `vexos` skill workflow

### 4.6 Accounts, usage limits, theme sync (added after user review)

The user asked for Omarchy's three remaining features as well.

**Multiple Claude accounts.** This is Omarchy's model: one `CLAUDE_CONFIG_DIR` per account.
- Main account: `~/.claude`. It stays implicit, because Claude ties `~/.claude.json` to the default home.
- Extra accounts live in `~/.local/share/vexos/ai/claude-accounts/<label>/`.
- The active account is stored in `~/.config/vexos/ai/claude-account` (missing = main).
- Commands:
  - `vexos-ai account list|add <label>|use <label|next>|remove <label>`
  - `add` creates the home, symlinks `skills` → `~/.claude/skills`, and runs `CLAUDE_CONFIG_DIR=… claude auth login`
  - `vexos-ai` exports `CLAUDE_CONFIG_DIR` only for non-main accounts
- Running sessions keep the account they started with.
- OpenCode is provider-based (`opencode auth login` can store several providers), so it gets no account switcher.

**Usage limits** (Claude subscription accounts only).
- Source: `GET https://api.anthropic.com/api/oauth/usage` with `Authorization: Bearer <claudeAiOauth.accessToken from <home>/.credentials.json>` and `anthropic-beta: oauth-2025-04-20`. Omarchy uses the same call in `bin/omarchy-agent-usage-claude`.
- Fields: `five_hour.utilization`, `seven_day.utilization` (percent, or fractions in older payloads; a value ≥1 means percent), and `resets_at`.
- **Undocumented endpoint:** every failure (401/429/transport/missing token) degrades to "unknown" and never errors the launcher.
- Results are cached in `~/.cache/vexos/ai/usage-<account>.json` and re-probed at most every 5 minutes.
- The token goes only into the Authorization header; it is never logged or written elsewhere.

**Warnings and autoswitch.**
- A `systemd.user.timers.vexos-ai-usage` timer runs every 10 minutes and calls `vexos-ai usage-check`.
- If the active account is at or above the threshold (`~/.config/vexos/ai/threshold`, default 95), it sends one notification per account and window, keyed on `resets_at`.
- When `~/.config/vexos/ai/mode` = `auto`, it also switches the active account to the one with the most headroom below the threshold and notifies.
- `vexos-ai account mode manual|auto [threshold]` changes the mode.

**Panel.** `vexos-ai panel` is the point-and-click view, launched from the desktop entry's "Accounts & usage" action.
- A zenity list: one row per account, with ●active, session % and weekly %.
- Buttons: Open assistant, Use selected, Add account, Change AI tool, Toggle autoswitch.

**Theme sync.** VexOS has no Omarchy-style themes. The equivalent is GNOME's `color-scheme` and the per-role `accent-color` (blue/orange/yellow/teal; `modules/gnome-*.nix`).
- `vexos-ai theme` writes `~/.claude/themes/vexos.json` (`{"name":"VexOS","base":"dark|light","overrides":{"claude":<accent hex>,"promptBorder":<accent>,…}}`, the same format as Omarchy's `default/themed/claude.json.tpl`) and sets `"theme":"custom:vexos"` in each account's `settings.json` via jq.
- Claude hot-reloads `themes/`.
- A user service `vexos-ai-theme-watch` runs `gsettings monitor org.gnome.desktop.interface` and re-runs `theme` on changes. Without gsettings it falls back to dark + blue.
- OpenCode: the system config sets `"theme": "system"`, so it follows the terminal palette.

### 4.7 Implementation deviations (recorded during Phase 2)

| Spec said | Implemented | Why |
|---|---|---|
| Import from desktop, htpc, server, **vanilla** | desktop, htpc, server | Vanilla has no `pkgs.unstable` / `pkgs.vexos` overlays; `just enable-feature ai` skips vanilla with a message |
| `local.nix` also in `flake.nix` mkHost path | Wrapper template + vexos-update auto-heal only | Matches `hostname.nix`/`bootloader.nix`, which are wrapper-only side-files too |
| OpenCode policy via `OPENCODE_CONFIG` | `/etc/opencode/opencode.json` (OpenCode's managed config path) | Docs: managed config merges above the user's and cannot be overridden; deny entries only |
| Claude `managed-settings.json` | `/etc/claude-code/managed-settings.d/50-vexos.json` drop-in, rules in `Bash(cmd *)` form | Docs (code.claude.com/docs/en/managed-settings): drop-ins merge with other admin policy; space-wildcard is the current syntax |
| Agent edits with sudo | `pkexec` | The agent's shell has no TTY for a sudo password; pkexec shows a graphical prompt (polkit agents exist on GNOME, COSMIC, Hyprland) |
| GNOME keybind TBD | Second entry in the existing `custom-keybindings` list in `modules/gnome-desktop.nix` (desktop role) | One list, one owner; the command is looked up on PATH so it is inert when the feature is off. HTPC/server use the app menu |
| `diagnose [unit]` | `diagnose [unit\|rebuild]` | Rebuild errors are printed, not journaled; `rebuild` reproduces them with a dry-build. `just rebuild` prints the hint on failure |

## 5. Implementation steps (Phase 2 order)

1. `files/ai/skills/vexos/SKILL.md`, `files/ai/skills/vexos-diagnose/SKILL.md` → verify: frontmatter parses (name + description).
2. `pkgs/vexos-ai/default.nix` plus registration in `pkgs/default.nix` → verify: `nix build .#…vexos-ai` in WSL; shellcheck passes (writeShellApplication runs it).
3. `modules/ai.nix`, imported from the four `configuration-*.nix` → verify: `nix eval` of `vexos-desktop-amd` toplevel with the feature on and off.
4. `local.nix` wiring in `template/etc-nixos-flake.nix`, `flake.nix`, `template/local.nix` → verify: eval with and without the file present.
5. justfile: `agent`, `diagnose`, `_feature_names`, `features`, rebuild failure hint; `template/features.nix` entry → verify: `just --list` and `just --dump` parse.
6. Keybindings (Hyprland, GNOME) → verify: no duplicate chord; dconf eval.
7. Docs: README feature list.

## 6. Validation (Phase 3/6)

- `nix flake show --impure`
- dry-build or `nix eval … toplevel.drvPath` for `vexos-desktop-{amd,nvidia,vm}`, `vexos-htpc-amd`, `vexos-server-amd`, `vexos-vanilla-amd`, `vexos-stateless-amd`, `vexos-headless-server-amd` (the last two must be unaffected)
- `bash scripts/preflight.sh`
- Manual on a real host (user): `just enable-feature ai && just rebuild`. Then:
  - Super+Shift+A → the picker appears → sign in
  - ask "install htop" → the agent writes `local.nix`, dry-builds, and refuses to switch
  - `just diagnose` against a deliberately failing unit
  - `sh -c 'kill -SEGV $$'` → toast → diagnosis

## 7. Risks and mitigations

| Risk | Mitigation |
|---|---|
| Agent runs switch anyway, e.g. via a script | sudo password prompt is the real gate; deny-lists catch the obvious cases; the skill states the rule |
| Agent edits upstream or the Nix store | The store is read-only; the skill says so explicitly |
| `OPENCODE_CONFIG` replaces the user's config | Verify in Phase 2; fall back to home-manager `sharedModules` |
| GNOME `custom-keybindings` list collision | Decide merge strategy in Phase 2 (§4.4) |
| Old host wrappers lack `local.nix` | The skill checks the wrapper; document the refresh |
| Unfree `claude-code` | Already allowed (development.nix ships it) |
| Unstable agent versions break | They only affect the CLI tool, not the system; pin to stable is a one-line change |
| Core dumps contain secrets | Skill mandates `mktemp` and deletion (from Omarchy) |

## 8. Dependencies

There are no new flake inputs. New nixpkgs packages are `opencode` (MIT), `xdg-terminal-exec`, `zenity`, and `libnotify`, plus the existing `claude-code` (unfree). All come from the existing locked nixpkgs and nixpkgs-unstable. Context7 was unavailable this session (connection timeout), so the Claude managed-settings syntax and OpenCode config behaviour must be checked against live docs at the start of Phase 2.

## 9. Sources

1. Omarchy manual, AI chapter: https://github.com/omacom/omarchy/blob/quattro/manual/17-ai.md
2. Omarchy source: `bin/omarchy-agent`, `bin/omarchy-default-agent`, `bin/omarchy-agent-crash`, `bin/omarchy-crash-watch`, `install/user/first-run/setup-agent.hook` (raw.githubusercontent.com/omacom/omarchy/quattro/…)
3. Omarchy skills: `default/agents/skills/omarchy/SKILL.md`, `default/agents/skills/diagnose-crash/SKILL.md`
4. OpenCode skills discovery: https://opencode.ai/docs/skills/
5. OpenCode permissions: https://opencode.ai/docs/permissions/
6. Claude Code on Omarchy (permissions and managed settings): https://yeet.cx/topical-takes/claude-code-on-omarchy
7. nixpkgs package data (claude-code 2.1.287, opencode 1.15.10 stable / 1.18.34 unstable) and the home-manager `programs.claude-code` / `programs.opencode` options, via search.nixos.org
