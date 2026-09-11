# Noctalia v5 Migration — Specification

Feature: migrate the Hyprland desktop shell from DankMaterialShell (DMS) to
Noctalia v5, keeping DMS intact but inactive, and add hot corners + launcher
parity on top.

Status: Phase 1 (Research & Specification)

---

## 1. Current state analysis

### 1.1 Which host runs what

`vextop` (`/etc/nixos/vexos-variant` = `vexos-desktop-nvidia`) currently boots
**GNOME**, not Hyprland:

- `modules/desktop-environment.nix` declares `vexos.desktop.environment` with
  `default = "gnome"`.
- `/etc/nixos/features.nix` on this host does **not** override it.
- `systemctl --user is-enabled dms.service` → `not-found`; nothing DMS is running.
- `~/.config/hypr/` does not exist.

Therefore the entire Hyprland + DMS path in this repo is **inert on this host**.
Per user decision (2026-09-10), this migration is **repo-only**: no change to
`/etc/nixos/features.nix`. The user flips `vexos.desktop.environment = "hyprland"`
themselves when ready.

### 1.2 How DMS is wired today

| Layer | Location | Notes |
|---|---|---|
| Flake input | `flake.nix` `dms` | `github:AvengeMedia/DankMaterialShell/stable`, `follows = "nixpkgs"` |
| NixOS modules | `flake.nix` `dmsBase` | option declarations + greeter only; never sets `enable` |
| Home module | `home/dank-material-shell.nix` | the only place `enable = true` is set |
| Gate | `osConfig.vexos.desktop.environment == "hyprland"` | whole `config` block is `lib.mkIf`-gated |
| Import | `home-desktop.nix:12` | imported unconditionally, gated internally |

DMS is started by its **systemd user service** (`dms.service`), bound to
`graphical-session.target`. `files/hypr/hyprland.conf:84-86` states explicitly:

> The DMS shell itself is started by its systemd user service … Do NOT also
> `exec-once = dms run` here

### 1.3 Hyprland config is NOT declaratively managed

`files/hypr/hyprland.conf` is copied to `~/.config/hypr/hyprland.conf` **once**
by `home.activation.seedHyprlandConf` in `home/dank-material-shell.nix`, only if
the target does not already exist. After first boot the file is user-owned and
`nixos-rebuild` never touches it again.

Consequence: edits to the repo copy affect **fresh seeds only**. On `vextop`
`~/.config/hypr/` does not exist, so the edited file will be seeded intact on the
first Hyprland login. No conflict here, but this is a standing limitation.

The seeding activation lives inside the DMS module. Since that module's `config`
block stays gated on `hyprland` (only `enable` flips to `false`), seeding
continues to work. **The activation must not be removed.**

---

## 2. Problem definition

Five of the user's stated premises do not match the repository or upstream.
Each is resolved below rather than implemented as literally written.

| # | Premise as stated | Reality | Resolution |
|---|---|---|---|
| P1 | Noctalia v5 is the `v5` branch | No `v5` branch. Branches are `main`, `legacy-v4`, `cachix`. v5 ships as tags; latest `v5.1.0` | Pin tag `v5.1.0` (user decision) |
| P2 | Remove DMS's `exec-once` from Hyprland | No DMS `exec-once` exists — systemd user service starts it | Nothing to remove; `enable = false` drops the service. Document in-file |
| P3 | Add `exec-once = noctalia-shell` | Would double-start alongside `systemd.enable = true`; also the binary is `noctalia`, not `noctalia-shell` | Do **not** add `exec-once`. Service starts it. Document why |
| P4 | `launch_apps_as_systemd_services` is a module option | Module exposes only `enable`, `systemd.enable`, `package`, `checkConfig`, `settings`, `customPalettes` | Set as `settings.shell.launch_apps_as_systemd_services` |
| P5 | Package `hyprcorners` for hot corners | Noctalia v5 has a native `[hot_corners]` section | Use native (user decision). No new package |

### 2.1 Cachix vs `follows` — direct conflict

The user asked for **both**:

- `inputs.nixpkgs.follows = "nixpkgs"`, and
- the Noctalia Cachix cache "so I don't compile from source".

Upstream `docs/user/getting-started/nixos.mdx` states these are mutually exclusive:

> To use the binary cache, you have to omit `inputs.nixpkgs.follows` …
> Overriding any of Noctalia's inputs … changes the derivation hash, causing
> cache misses.

Noctalia is a C++/Qt/Quickshell build; a source build is expensive.
nixpkgs only carries `noctalia-shell` **4.7.5** (the v4 line), so there is no
cached-in-nixpkgs route to v5.

**Resolution:** honour the stated *intent* ("don't compile from source") — omit
`follows`, add the cache. Recorded as an explicit documented exception in
`flake.nix`, matching the existing precedent required by `CLAUDE.md`
(`nixpkgs-unstable`, `proxmox-nixos`, `vexboard`).

---

## 3. Proposed solution architecture

### 3.1 Upstream facts verified against source (tag `v5.1.0`)

- Home module import path: `inputs.noctalia.homeModules.default`
  (sets `programs.noctalia.package` via `mkDefault` from its own nixpkgs).
- Config target: `~/.config/noctalia/config.toml` (**not**
  `~/.local/state/noctalia/settings.toml` as stated in the request).
- `checkConfig` (default `true`) runs `noctalia config validate` at **build
  time**. **Verified empirically against noctalia 5.1.0** — it catches less than
  its name suggests: TOML *syntax* errors are errors (exit 1), but an unknown
  key (`dock.drag_to_reorder: unknown setting`) or an unknown enum value
  (`dock.position: unknown value "diagonal"`) is only a **warning**, and the
  command still exits 0. A typo therefore does **not** fail the rebuild; it
  silently does nothing.
  Consequently the real verification gate for this change was running the
  validator directly against the generated TOML and requiring **0 errors and
  0 warnings** — which the final config achieves.
- Binary / `meta.mainProgram`: `noctalia`. IPC form: `noctalia msg <command>`
  (**not** `noctalia-shell ipc call …`, which is v4/DMS-style).
- Cache: `https://noctalia.cachix.org`,
  key `noctalia.cachix.org-1:pCOR47nnMEo5thcxNDtzWpOxNFQsBRglJzxWPp3dkU4=`.

Config sections (`src/config/schema/config_sections.cpp`): `storage`, `shell`,
`accessibility`, `wallpaper`, `theme`, `backdrop`, `lockscreen`, `notification`,
`osd`, `system`, `weather`, `calendar`, `audio`, `brightness`, `battery`,
`nightlight`, `location`, `idle`, `keybinds`, `dock`, `hot_corners`,
`control_center`, `plugins`, `hooks`; plus root keys `bar`, `widget`,
`desktop_widgets`, `lockscreen_widgets`, `plugin_settings`, `include`,
`config_version`.

### 3.2 IPC vocabulary (from `docs/user/ipc/`)

| Action | Command |
|---|---|
| Launcher | `noctalia msg panel-toggle launcher` |
| Control center | `noctalia msg panel-toggle control-center` |
| Window overview | `noctalia msg window-switcher` |
| Lock | `noctalia msg session lock` |
| Session menu | `noctalia msg panel-toggle session` |
| Clipboard | `noctalia msg panel-toggle clipboard` |

Noctalia has **no workspace-grid overview**. `window-switcher` is an Alt+Tab-style
fullscreen window grid — the closest available equivalent, used for the
bottom-left corner.

### 3.3 Hot corners (`src/shell/hot_corners/hot_corners.cpp`)

Per corner: `action` + `command`.
- `action = "command"` → runs `command` as a shell command
- `action = "none"` → disabled
- any other value → internal shell action

**Chosen form:** `action = "command"` with `command = "noctalia msg …"`, so the
corner and the keybind execute byte-identical strings. This is what makes the
Task 6 parity table exact rather than approximate.

---

## 4. Implementation steps

Each step lists its verification.

1. **`flake.nix`** — add `noctalia` input pinned to `v5.1.0`, deliberately
   without `follows`, with a comment explaining the cache exception. Add the
   Cachix substituter + key to the existing `nixConfig` block (install-time
   coverage, mirroring the proxmox precedent).
   → verify: `nix flake show --impure` lists outputs; `nix flake metadata` resolves.

2. **`modules/nix-noctalia-cache.nix`** (new) — post-install substituter, a
   direct structural mirror of `modules/nix-proxmox-cache.nix`.
   → verify: file parses; imported in step 3.

3. **`configuration-desktop.nix`** — import the cache module.
   → verify: `nix eval` of the desktop config evaluates.

4. **`home/dank-material-shell.nix`** — flip `enable = true` → `enable = false`
   with an explanatory comment. Change **nothing else**: settings, session,
   theme deployment, polkit agent, udiskie, hypridle, mute-mic and the
   `seedHyprlandConf` activation all stay.
   → verify: `dms.service` no longer generated; grep shows one-line change.

5. **`home/noctalia.nix`** (new) — Noctalia home module + settings, structured
   to mirror `home/dank-material-shell.nix` (same `osConfig` gate, same comment
   style, `imports` outside the `mkIf`).
   → verify: build-time `noctalia config validate` passes.

6. **`home-desktop.nix`** — import `./home/noctalia.nix` next to the DMS import.
   → verify: evaluation succeeds.

7. **`files/hypr/hyprland.conf`** — comment out the DMS keybind block with a
   restore note; add the Noctalia keybind block; document why there is no
   `exec-once`. Touch nothing else (window rules, monitors, media keys that do
   not reference `dms`).
   → verify: `grep -c "^bind.*dms"` returns 0 live binds; diff is confined to
   the shell-keybind region.

### 4.1 Module Architecture Pattern compliance

`home/noctalia.nix` uses `lib.mkIf (osConfig.vexos.desktop.environment ==
"hyprland")`. This is a **pre-existing role gate**, identical in shape to
`home/dank-material-shell.nix` and `home/gnome-common.nix`. It is not a new
`lib.mkIf` guard added to a *shared* module, so it does not violate the Option B
rule; it matches the established convention for `home/` role modules.

---

## 5. Settings design (Task 3 / 5)

### 5.1 Bar — capsule segments + concave corners

Structure: `[bar.<name>]` subtables; lanes `start` / `center` / `end`.
Capsule groups are `[[bar.<name>.capsule_group]]` entries (`id`, `members`,
`fill`, `border`, `radius`, `padding`, `opacity`), referenced from a lane as the
token `"group:<id>"`.

Requested → delivered:
- grouped capsule/pill segments → `capsule_group` entries, three groups
- inverted/concave corners at screen edge → `concave_edge_corners = true`
  (**requires `margin_edge = 0`**)
- workspaces, media, tray, clock → widgets `workspaces`, `media`, `tray`, `clock`

### 5.2 Dock

`enabled`, `auto_hide`, `smart_auto_hide`, `pinned`, `border` + `border_width`,
`concave_edge_corners` — all declarative.

### 5.3 Theme — Material-You from wallpaper

`[theme] source = "wallpaper"` + `wallpaper_scheme`, with `[wallpaper]` pointing
at the existing `~/Pictures/Wallpapers/` files that `home-desktop.nix` already
deploys (same files DMS used).

### 5.4 Launcher

Calculator and Emoji are **built-in providers**, always present — there is no
`enabled` toggle. `[shell.launcher.providers.<name>]` exposes only `prefix` and
`global`. Global app search is inherent. So Task 5 is: tune `app_grid`,
`sort_by_usage`, `categories`, and confirm the calculator is global.

### 5.5 Declarative vs GUI-only — the Task 3 flag

| Item | Declarative? | Note |
|---|---|---|
| Bar layout, lanes, widgets | Yes | |
| Capsule groups | **Yes** | Docs claim "managed entirely from the Settings GUI", but the TOML schema (`capsule_group` + `group:` lane tokens) accepts them. Docs are incomplete, not the schema |
| Concave corners (bar + dock) | Yes | needs `margin_edge = 0` |
| Dock pinned / auto-hide / border | Yes | |
| Theme from wallpaper | Yes | |
| Hot corners | Yes | |
| **Dock drag-to-reorder** | **No** | No config key exists. Reordering is a runtime GUI gesture; the resulting order persists to `pinned`. Declarative `pinned` sets the initial order |
| Launcher provider enable/disable | **No** | Only `prefix` / `global` are configurable |

Runtime GUI edits are written back to `~/.config/noctalia/config.toml`. Because
home-manager makes that path a **read-only /nix/store symlink**, GUI changes
cannot persist. This is the same trade-off the DMS module already documents for
`settings.json`.

---

## 6. Dependencies

| Name | Version | Source | Context7 |
|---|---|---|---|
| noctalia | `v5.1.0` (tag) | `github:noctalia-dev/noctalia-shell` | N/A — not a Context7-indexed library; verified directly against upstream source + docs at the pinned tag |

No new nixpkgs packages. `hyprcorners` is **not** added (superseded by native
hot corners).

---

## 7. Risks and mitigations

| Risk | Impact | Mitigation |
|---|---|---|
| ~~Tag `v5.1.0` may not be in Cachix~~ | ~~Source build of a Qt/C++ shell~~ | **RESOLVED — verified.** `nix build --dry-run` against `noctalia.cachix.org` reports *"255 paths will be fetched (261.2 MiB), 0 will be built"*, and a real build fetched `noctalia-5.1.0` straight from the cache. No source build |
| Two nixpkgs copies (no `follows`) | Extra eval memory + download | Accepted; same trade-off already made for `proxmox-nixos` / `vexboard` |
| A typo'd key or enum value is only a warning, so it silently does nothing | A setting appears applied but is not | Validator run directly against the generated TOML; requires 0 errors **and** 0 warnings. Achieved. Re-run on every edit — `checkConfig` alone will not catch this |
| Double polkit agent (`hyprpolkitagent` + Noctalia's built-in) | Conflicting auth prompts | Set `shell.polkit_agent = false`; leave the existing working `hyprpolkitagent` untouched |
| Both shells enabled at once | Two bars | DMS `enable = false` removes `dms.service`; only `noctalia.service` remains |
| Repo edits to `hyprland.conf` do not reach an existing install | Stale keybinds | Seed-once by design. `~/.config/hypr` absent on `vextop`, so no drift today. Called out in delivery notes |
| No workspace-grid overview in Noctalia | Bottom-left corner is not a true GNOME Activities | `window-switcher` used as nearest equivalent; stated plainly |

---

## 8. Out of scope

- Flipping `vexos.desktop.environment` on any host (user does this).
- Removing the DMS input, module, settings, or keybinds (explicitly retained).
- `hyprcorners` packaging (superseded).
- Touching window rules, monitor setup, or non-shell keybinds.
