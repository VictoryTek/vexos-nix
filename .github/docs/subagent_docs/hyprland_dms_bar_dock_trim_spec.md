# Hyprland / DMS — trim Dank Bar widgets + add OS-logo dock launcher

## Phase 1 — Research & Specification

### User request

On the Hyprland desktop (DankMaterialShell shell), change the shipped bar/dock
layout:

**Dank Bar — remove widgets:**

| Section | Remove |
|---------|--------|
| Left    | App Launcher (`launcherButton`) |
| Center  | Weather (`weather`) |
| Right   | Clipboard manager (`clipboard`), CPU Usage (`cpuUsage`), Memory Usage (`memUsage`), Notification Center (`notificationButton`) |

**Keep** on the right: System Tray (`systemTray` — required so Sunshine, Vesktop,
gamemode etc. surface a tray icon), Battery (`battery`), Control Center
(`controlCenterButton`).

**Dock:**
- Add a launcher button showing the OS logo (VexOS shield).
- "Overlay layer" — decided: **leave disabled** (existing `dockAutoHide` +
  `dockSmartAutoHide` already give GNOME-intellihide-style reachability; the
  overlay layer would force the dock above fullscreen windows, which is not
  wanted).

### Current state analysis

`home/dank-material-shell.nix` sets `programs.dank-material-shell.settings` to a
small attrset (`clockFormat`, `showDock`, `dockPosition`, `dockAutoHide`,
`dockSmartAutoHide`, `currentThemeName`, `customThemeFile`). It does **not** set
any bar-widget layout — the comment at lines 48–49 explicitly defers "Bar/widget
layout and plugins" to a later phase. This is that phase.

The DMS Home-Manager module (`inputs.dms`, rev `069ddab`,
`distro/nix/home.nix:108`) writes `~/.config/DankMaterialShell/settings.json` via
`xdg.configFile."DankMaterialShell/settings.json".source = jsonFormat.generate …`
whenever `cfg.settings != {}` — an immutable store symlink. The repo already sets
`settings`, so on the installed machine that file is read-only; DMS settings-GUI
edits to the bar/dock apply to the running session only and are dropped on the
next DMS restart or `nixos-rebuild`. Declarative Nix is therefore the only
durable way to change these keys.

#### How DMS decides which bar widgets render (rev `069ddab`)

- `Common/SettingsData.qml:977` — `property var barConfigs` is an array of
  per-bar objects. The default (single) entry `id: "default"` carries:
  - `leftWidgets:   ["launcherButton", "workspaceSwitcher", "focusedWindow"]`
  - `centerWidgets: ["music", "clock", "weather"]`
  - `rightWidgets:  ["systemTray", "clipboard", "cpuUsage", "memUsage", "notificationButton", "battery", "controlCenterButton"]`
- `Modules/DankBar/DankBarContent.qml:585` — `getWidgetVisible(widgetId)` returns
  `true` for every widget **except** the dgop-backed ones
  (`cpuUsage`, `memUsage`, `cpuTemp`, `gpuTemp`, `network_speed_monitor`), which
  are gated only on `DgopService.dgopAvailable`.
- `Modules/DankBar/WidgetHost.qml:39` — a widget Loader is `active` iff its id is
  present in the section's list AND `getWidgetVisible` passes.
- The legacy `show*` booleans in `SettingsData.qml`
  (`showLauncherButton:336`, `showWeather:339`, `showClipboard:341`,
  `showSystemTray:348`, `showNotificationButton:353`) are **not** consulted by
  the current bar-rendering path — `barConfigs[*].{left,center,right}Widgets`
  is authoritative. `cpuUsage` / `memUsage` have no `show*` equivalent at all.

  → **Removing a widget = removing its id from the relevant `*Widgets` array in
  `barConfigs[0]`.** The `show*` booleans are a dead end.

#### settings.json schema version / migrations

- `SettingsData.qml:18` — `readonly property int settingsConfigVersion: 13`.
- `SettingsData.qml:1738-1744` — on load, `const oldVersion = obj?.configVersion ?? 0`;
  if `oldVersion < settingsConfigVersion`, `Store.migrateToVersion(obj, 13)` runs
  and its result replaces the parsed object in memory. The repo's current
  settings.json has **no** `configVersion` key, so `oldVersion == 0` and a full
  v0→13 migration pass runs on every shell start (it cannot be written back —
  read-only symlink). A v0→13 migration that synthesises `barConfigs` from
  legacy `dankBar*` keys could clobber a hand-written `barConfigs`.

  → The declarative `settings` attrset MUST include `configVersion = 13` so DMS
  treats it as current and skips migration entirely.

#### Dock launcher button (rev `069ddab`)

- `Common/SettingsData.qml:842-848`:
  - `dockLauncherEnabled: false` — master toggle for the dock launcher button.
  - `dockLauncherLogoMode: "apps"` — `"apps" | "os" | "dank" | "compositor" | "custom"`.
  - plus `dockLauncherLogoCustomPath`, `dockLauncherLogoColorOverride`,
    `dockLauncherLogoSizeOffset`, `dockLauncherLogoBrightness`,
    `dockLauncherLogoContrast` (all left at default).
- `Modules/Dock/DockLauncherButton.qml:207-215` — `dockLauncherLogoMode === "os"`
  renders the `SystemLogo` component, which resolves the distro logo from
  `/etc/os-release`. The user has already verified in the live settings GUI that
  `"os"` renders the VexOS shield (not the DMS "dank" logo), so VexOS branding
  (`modules/branding-display.nix`) already publishes the right logo — no
  branding change needed.
- Current repo dock keys: `showDock = true`, `dockPosition = 2` (Left),
  `dockAutoHide = true`, `dockSmartAutoHide = true`. `dockUseOverlayLayer`
  (`SettingsData.qml:827`, default `false`) stays unset → stays `false`.

#### Keybind coverage for removed buttons

`files/hypr/hyprland.conf` already binds every function whose bar button is being
removed:
- `$mod+Space` → `dms ipc call spotlight toggle` (app launcher)
- `$mod+V` → `dms ipc call clipboard toggle`
- `$mod+N` → `dms ipc call notifications toggle` (+ `$mod+X` dash, `$mod+Shift+,`
  dismiss popups)

CPU / memory usage have no replacement surface, but the user does not want them.
→ **No `hyprland.conf` change required.** No loss of function.

### Problem definition

`home/dank-material-shell.nix` must declaratively pin the DMS bar widget layout
(dropping 6 widgets across 3 sections) and enable an OS-logo dock launcher
button, in a way that:
- survives DMS restarts and `nixos-rebuild` (it already will — immutable file);
- does not get mangled by DMS's settings-version migration;
- follows the repo's Module Architecture Pattern and existing file conventions.

### Proposed solution

**Single file touched: `home/dank-material-shell.nix`** — extend the existing
`programs.dank-material-shell.settings` attrset inside the current
`lib.mkIf (osConfig.vexos.desktop.environment == "hyprland")` block. No new
modules, no new files, no imports, no `hyprland.conf` change, no system-side
change. This is consistent with the Module Architecture Pattern: the setting is
already gated by the same-module DE check (an accepted carve-out), and the whole
`home/dank-material-shell.nix` module is Hyprland-only by construction.

#### Change 1 — pin `barConfigs` with the trimmed widget lists

Add a `barConfigs` key to `settings` — a one-element list. The element carries
only the **structural keys DMS reads without a `?? default` fallback** plus the
three trimmed widget arrays. Every other per-bar appearance key
(`spacing`, `innerPadding`, `transparency`, `autoHide`, `useOverlayLayer`,
borders, shadows, goth corners, …) is deliberately **omitted** — DMS reads all of
those as `defaultBar?.<key> ?? <hardcoded default>` (e.g.
`DankBarContent`/geometry: `defaultBar?.spacing ?? 4`), so omitting them yields
exactly the upstream default and keeps the block small and surgical.

Structural keys included (each read unguarded by DMS to decide the bar exists /
where it sits):

```nix
barConfigs = [{
  id                = "default";
  name              = "Main Bar";
  enabled           = true;
  visible           = true;
  position          = 0;              # DMS Position enum: Top=0 (dock, separately, is Left=2)
  screenPreferences = [ "all" ];
  showOnLastDisplay = true;
  leftWidgets   = [ "workspaceSwitcher" "focusedWindow" ];
  centerWidgets = [ "music" "clock" ];
  rightWidgets  = [ "systemTray" "battery" "controlCenterButton" ];
}];
```

`id = "default"` matters: DMS resolves the primary bar as
`barConfigs[0] || getBarConfig("default")` and several code paths look it up by
that id.

> Implementation note: DMS `Position` enum — `Top=0, Bottom=1, Left=2, Right=3`.
> The bar object's `position` is `0` (Top), matching the current shipped default
> (only the *dock* is on the Left, via `dockPosition = 2`).

#### Change 2 — `configVersion = 13`

Add `configVersion = 13;` at the top level of `settings`, with a comment: DMS
`settingsConfigVersion` as of `inputs.dms` rev `069ddab`; keeps DMS from running
its v0→N settings migration against this file on every shell start (the file is a
read-only store symlink so a migration can never be persisted, and a
`barConfigs`-synthesising migration step could otherwise override the block
above). Must be re-checked on every `inputs.dms` bump.

#### Change 3 — dock launcher button

Add to `settings`:

```nix
dockLauncherEnabled  = true;
dockLauncherLogoMode = "os";   # SystemLogo → /etc/os-release → VexOS shield
```

Leave `dockUseOverlayLayer` unset (defaults `false`).

### Implementation steps

1. `home/dank-material-shell.nix` — in the `settings` attrset:
   1. add `configVersion = 13;` with explanatory comment → verify: key present,
      value `13`.
   2. add `dockLauncherEnabled = true;` and `dockLauncherLogoMode = "os";` next
      to the existing `dock*` keys, with comment → verify: keys present.
   3. add `barConfigs = [ { … } ];` — structural subset + 3 trimmed widget
      arrays per above, with a header comment citing source rev `069ddab`,
      listing the 6 removed widget ids, and noting that appearance keys are
      omitted on purpose (DMS `?? default` fallback) → verify:
      `nix eval` of `…config.home-manager.users.<u>.xdg.configFile."DankMaterialShell/settings.json"`
      generated JSON shows
      `barConfigs[0].rightWidgets == ["systemTray","battery","controlCenterButton"]`.
2. No other files. Confirm `files/hypr/hyprland.conf` already binds
   spotlight/clipboard/notifications (it does) → no edit.

### Dependencies

None. No new flake inputs, no new packages. `inputs.dms` unchanged. All keys are
part of the DMS Home-Manager module's free-form `settings` JSON option
(`pkgs.formats.json` — accepts arbitrary attrsets/lists). Context7: not
applicable — no new external dependency; DMS API surface verified directly
against the pinned `inputs.dms` source rev `069ddab`.

### Configuration changes

`~/.config/DankMaterialShell/settings.json` (generated, immutable) gains
`configVersion`, `barConfigs`, `dockLauncherEnabled`, `dockLauncherLogoMode`.
No system-level (`configuration-*.nix`) change. No `stateVersion` impact. No
new secret. No new world-writable path.

### Migration / scope of effect

- Hyprland desktop only (`home/dank-material-shell.nix` is inert on GNOME/COSMIC
  — `config = lib.mkIf (…environment == "hyprland")`).
- On next `home-manager`/`nixos-rebuild` the settings.json symlink is replaced
  and `dms.service` restarts (`restartIfChanged`), picking up the new layout.
- If the user had made live GUI bar tweaks, those were never persisted and are
  superseded by this block.
- No effect on `barPinnedApps` / `pinnedApps` (dock/app pins) — those are in
  `session`, untouched.

### Sources consulted

1. `inputs.dms` `Common/SettingsData.qml` @ `069ddab` — `barConfigs` default
   object, `settingsConfigVersion`, all `dock*` / `show*` properties.
2. `inputs.dms` `Modules/DankBar/DankBarContent.qml` @ `069ddab` —
   `getWidgetVisible`, `componentMap` (widget-id → component); proves the bar is
   rendered strictly from the `*Widgets` arrays.
3. `inputs.dms` `Modules/DankBar/WidgetHost.qml` @ `069ddab` — Loader `active`
   condition.
4. `inputs.dms` `distro/nix/home.nix` @ `069ddab` — `settings` option, immutable
   `xdg.configFile` symlink mechanism.
5. `inputs.dms` `Modules/Dock/DockLauncherButton.qml` @ `069ddab` —
   `dockLauncherLogoMode === "os"` → `SystemLogo`.
6. `inputs.dms` `SettingsData.qml:1725-1770` (`loadSettings`) — `configVersion`
   gate and migration trigger.
7. Repo: `home/dank-material-shell.nix`, `files/hypr/hyprland.conf`,
   `.github/docs/subagent_docs/hyprland_dms_gnome_parity_spec.md`,
   `.github/docs/subagent_docs/hyprland_dms_double_bar_fix_spec.md`.

### Risks and mitigations

| Risk | Mitigation |
|------|------------|
| `inputs.dms` bump raises `settingsConfigVersion` past 13 → stale `configVersion` re-triggers migration | Spec + code comment both flag `configVersion = 13` as a per-bump check item. Migration is in-memory only; worst case is the pre-069ddab behaviour (migration each start), not data loss. |
| `inputs.dms` bump adds/renames keys in the `default` bar object → our subset drifts | Subset is limited to unguarded structural keys; appearance keys already rely on DMS's `?? default` fallback, so upstream default changes flow through automatically. Source-rev comment flags it for bump review. |
| `inputs.dms` bump renames a widget id (e.g. `notificationButton`) | Our arrays would keep an old id (ignored → widget just absent) or miss a renamed kept one. Widget-id list is short and commented; re-check on bump. |
| Removing `systemTray` by mistake breaks Sunshine/Vesktop/gamemode tray icons | Explicitly retained in `rightWidgets`; called out in spec + code comment. |
| User later wants CPU/mem back | One-line array edit; `cpuUsage`/`memUsage` still in `componentMap`, dgop already enabled (`enableSystemMonitoring = true`). |
| Dock launcher `"os"` renders wrong/blank logo on a fresh install where branding not yet applied | User verified live it shows the VexOS shield; `SystemLogo` falls back to a generic icon, never blank/crash. Non-fatal. |
| `nix flake check` accidentally used to validate | FORBIDDEN — use `nix flake show --impure` + per-target `nixos-rebuild dry-build` / `nix eval`. |

### Out of scope (mentioned, not done)

- `battery` widget on `vexos-desktop-*` (desktop has no battery) — pre-existing
  in the upstream default, user did not ask to remove it, left untouched per the
  Surgical-Changes principle.
- Bar `show*` boolean cleanup in any future DMS-side PR — not ours.
