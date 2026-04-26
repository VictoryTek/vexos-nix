# GNOME Module Role Split — Specification

**Spec file:** `.github/docs/subagent_docs/gnome_role_split_spec.md`
**Target module:** `modules/gnome.nix`
**Refactor type:** Pure Nix refactor — no new dependencies, no behavioural changes.

---

## 1. Current State Analysis

### 1.1 Role-conditional sites in `modules/gnome.nix`

Every site below reads (directly or indirectly) `config.vexos.branding.role` and
branches on it. Line numbers are approximate, taken from the current file.

| # | Lines | Construct | Description |
|---|-------|-----------|-------------|
| 1 | ~7–12  | `let gnomeBaseApps = […]` | Apps shared by all roles. Not itself role-conditional, but feeds (3). |
| 2 | ~15–20 | `let gnomeDesktopOnlyApps = […]` | Apps installed only on `desktop` (Calculator, Calendar, Papers, Snapshot). |
| 3 | ~24–29 | `gnomeAppsToInstall = (lib.filter (a: !(role == "htpc" && a == "org.gnome.Totem")) gnomeBaseApps) ++ lib.optionals (role == "desktop") gnomeDesktopOnlyApps` | Role-conditional Flatpak install list. |
| 4 | ~33     | `gnomeAppsHash = …` | Hash of (3); stamp file path used by the systemd service. |
| 5 | ~101    | `let role = config.vexos.branding.role;` | Reads the role inside the dconf-profile `let`. |
| 6 | ~102–108 | `accentColor = { desktop="blue"; htpc="orange"; server="yellow"; stateless="teal"; }.${role};` | Per-role accent. |
| 7 | ~110–123 | `commonExtensions = […]` plus `enabledExtensions = if role == "desktop" then commonExtensions ++ [ "gamemodeshellextension@trsnaqe.com" ] else commonExtensions;` | Per-role `enabled-extensions` list. |
| 8 | ~125–166 | `favApps = { desktop=…; stateless=…; htpc=…; server=…; }.${role};` | Per-role `favorite-apps` list. |
| 9 | ~183     | `accent-color = accentColor;` (inside `org/gnome/desktop/interface`) | Role-derived dconf value. |
| 10 | ~244–248 | `++ lib.optionals (role != "desktop") [ papers ]` in `environment.gnome.excludePackages` | Removes `papers` on every role except desktop. |
| 11 | ~292–298 | `lib.optionalString (role != "desktop") '' …uninstall desktop-only flatpaks… ''` (inside the systemd `script`) | Migration cleanup on htpc/server/stateless. |
| 12 | ~300–305 | `lib.optionalString (role == "htpc") '' …uninstall org.gnome.Totem… ''` | Migration cleanup on htpc only. |

In addition, the systemd service `flatpak-install-gnome-apps` itself is gated
by `lib.mkIf config.services.flatpak.enable { … }`. That guard is an
**option/feature** conditional, not a role conditional, and is **allowed** by
Option B; it stays as-is.

### 1.2 Files that import `modules/gnome.nix`

| Configuration | Imports `gnome.nix`? |
|---|---|
| `configuration-desktop.nix` | yes |
| `configuration-htpc.nix` | yes |
| `configuration-server.nix` | yes |
| `configuration-stateless.nix` | yes |
| `configuration-headless-server.nix` | **no** (verified — no display stack imported) |

### 1.3 Interaction with home-manager `home-*.nix`

`home/gnome-common.nix` and the per-role `home-<role>.nix` files set their own
`dconf.settings` for the user-level dconf database. The system dconf profile
defined in `modules/gnome.nix` is the lower layer in the lookup chain
(`user-db:user → system`). The split proposed in this spec does **not** alter
which keys are written to which database — it only relocates *system-side*
settings between Nix files. Home Manager behaviour is unaffected.

(`configuration-htpc.nix` separately writes a third copy of the same dconf
keys directly. This pre-existing duplication is **out of scope**, see §8.)

---

## 2. Problem Definition

`.github/copilot-instructions.md` mandates Option B:

> - **Universal base file** (`modules/foo.nix`): Contains only settings that
>   apply to ALL roles that import it. NO `lib.mkIf` guards inside that gate
>   content by role, display flag, or gaming flag.
> - **Role-specific addition file** (`modules/foo-desktop.nix`,
>   `modules/foo-gaming.nix`, etc.): Contains only additions for that
>   specific role or feature. Imported only by `configuration-*.nix` files
>   for roles that need it. NO conditional logic inside.
> - A `configuration-*.nix` expresses its role **entirely through its import
>   list** — if a file is imported, all its content applies unconditionally.
> - Existing `lib.mkIf` guards in shared modules are tech debt to be
>   eliminated.

`modules/gnome.nix` currently violates this rule in 12 places (§1.1):
`let`-level `if`/`lookup-by-role`, `lib.filter`, `lib.optionals`, and
`lib.optionalString` are all role-conditionals embedded in a shared module.
The role is read via `config.vexos.branding.role` directly inside the
universal file, which is exactly the pattern the instructions identify as
tech debt to remove.

---

## 3. Proposed Solution Architecture

### 3.1 File layout

```
modules/
  gnome.nix              ← universal base (no role reads, no role-conditionals)
  gnome-desktop.nix      ← desktop role additions   (NEW)
  gnome-htpc.nix         ← htpc role additions      (NEW)
  gnome-server.nix       ← server role additions    (NEW)
  gnome-stateless.nix    ← stateless role additions (NEW)
```

### 3.2 Per-file responsibility table

#### `modules/gnome.nix` (universal)

- Both nixpkgs overlays (unstable GNOME stack pin + `org.gnome.Extensions`
  desktop-file removal).
- `services.xserver.enable = true;`
- `services.xserver.excludePackages = lib.mkDefault [ pkgs.xterm ];`
- `services.desktopManager.gnome.enable = true;`
- `programs.dconf.enable = true;`
- A single `programs.dconf.profiles.user` entry containing **only universal
  dconf keys**:
  - `org/gnome/desktop/background` (wallpaper URIs — same for every role,
    deployed by `branding-display.nix`)
  - `org/gnome/desktop/interface` **without `accent-color`** — i.e. only
    `cursor-theme`, `icon-theme`, `clock-format`, `color-scheme`
  - `org/gnome/desktop/wm/preferences` (`button-layout`)
  - `org/fedorahosted/background-logo-extension` (logo paths)
  - `org/gnome/desktop/screensaver` (`lock-enabled = false`)
  - `org/gnome/settings-daemon/plugins/housekeeping`
    (`donation-reminder-enabled = false`)
- `services.displayManager.gdm = { enable = true; wayland = true; };`
- `services.displayManager.autoLogin = { enable = true; user = "nimda"; };`
- `xdg.portal` block (gnome portal + default).
- `environment.sessionVariables` (`NIXOS_OZONE_WL`, `ELECTRON_OZONE_PLATFORM_HINT`).
- `environment.gnome.excludePackages` — the **common** bloat list (every
  package currently in the unconditional list, i.e. **without** `papers`):
  `gnome-photos, gnome-tour, gnome-connections, gnome-weather, gnome-clocks,
  gnome-contacts, gnome-maps, gnome-characters, gnome-user-docs, yelp,
  simple-scan, epiphany, geary, xterm, gnome-music, rhythmbox, totem,
  showtime, gnome-calculator, gnome-calendar, snapshot`.
- `environment.systemPackages` for GNOME tooling and the **common** GNOME
  Shell extension packages: `unstable.gnome-tweaks, unstable.dconf-editor,
  unstable.gnome-extension-manager, bibata-cursors, kora-icon-theme,
  unstable.gnomeExtensions.appindicator,
  unstable.gnomeExtensions.alphabetical-app-grid,
  unstable.gnomeExtensions.gnome-40-ui-improvements,
  unstable.gnomeExtensions.nothing-to-say,
  unstable.gnomeExtensions.steal-my-focus-window,
  unstable.gnomeExtensions.tailscale-status,
  unstable.gnomeExtensions.caffeine,
  unstable.gnomeExtensions.restart-to,
  unstable.gnomeExtensions.blur-my-shell,
  unstable.gnomeExtensions.background-logo`.
  **`unstable.gnomeExtensions.gamemode-shell-extension` MOVES** to
  `gnome-desktop.nix`.
- Fonts block (unchanged).
- `services.printing.enable = true;`
- Bluetooth (`hardware.bluetooth.enable`, `services.blueman.enable`).
- **Removed:** `let role = …; let gnomeBaseApps = …; gnomeDesktopOnlyApps;
  gnomeAppsToInstall; gnomeAppsHash;` and the
  `systemd.services.flatpak-install-gnome-apps` definition. The systemd
  service is **owned by each role-addition file** so the apps list and
  migration scripts are role-local with no conditionals.

After this refactor, `modules/gnome.nix` contains **zero references** to
`config.vexos.branding.role`, **zero** `lib.optionals`/`lib.optionalString`,
and **zero** `if … then … else …` over role.

#### `modules/gnome-desktop.nix` (NEW)

- Adds the gamemode shell-extension package:
  `environment.systemPackages = [ pkgs.unstable.gnomeExtensions.gamemode-shell-extension ];`
- Adds a second entry to `programs.dconf.profiles.user.databases` containing
  the desktop-only role-specific keys:
  - `org/gnome/desktop/interface` → `accent-color = "blue";`
  - `org/gnome/shell` →
    - `enabled-extensions = commonExtensions ++ [ "gamemodeshellextension@trsnaqe.com" ];`
    - `favorite-apps = [ desktop list — see §5 ];`
- Defines the desktop variant of `systemd.services.flatpak-install-gnome-apps`
  (gated by `lib.mkIf config.services.flatpak.enable`):
  - apps list = `gnomeBaseApps ++ gnomeDesktopOnlyApps`
    = `[ TextEditor, Loupe, Totem, Calculator, Calendar, Papers, Snapshot ]`
  - hash = first 16 chars of `sha256` of comma-joined apps list
  - script: install only — **no** migration `optionalString` blocks.
- Does **not** touch `environment.gnome.excludePackages` (so `papers`
  remains installed on desktop, matching current behaviour).

#### `modules/gnome-htpc.nix` (NEW)

- Adds `papers` to `environment.gnome.excludePackages`.
- Adds a role-specific `programs.dconf.profiles.user.databases` entry:
  - `org/gnome/desktop/interface` → `accent-color = "orange";`
  - `org/gnome/shell` →
    - `enabled-extensions = commonExtensions;` (no gamemode)
    - `favorite-apps = [ htpc list — see §5 ];`
- Defines the htpc variant of `systemd.services.flatpak-install-gnome-apps`:
  - apps list = `gnomeBaseApps` minus `org.gnome.Totem`
    = `[ TextEditor, Loupe ]`
  - script includes the **Totem uninstall** migration block and the
    **desktop-only uninstall** migration block (both unconditional, since
    we are in the htpc-only file).

#### `modules/gnome-server.nix` (NEW)

- Adds `papers` to `environment.gnome.excludePackages`.
- Adds a role-specific dconf database entry:
  - `org/gnome/desktop/interface` → `accent-color = "yellow";`
  - `org/gnome/shell` →
    - `enabled-extensions = commonExtensions;`
    - `favorite-apps = [ server list — see §5 ];`
- Defines the server variant of the systemd flatpak service:
  - apps list = `gnomeBaseApps` = `[ TextEditor, Loupe, Totem ]`
  - script includes the **desktop-only uninstall** migration block; no
    Totem-uninstall block.

#### `modules/gnome-stateless.nix` (NEW)

- Adds `papers` to `environment.gnome.excludePackages`.
- Adds a role-specific dconf database entry:
  - `org/gnome/desktop/interface` → `accent-color = "teal";`
  - `org/gnome/shell` →
    - `enabled-extensions = commonExtensions;`
    - `favorite-apps = [ stateless list — see §5 ];`
- Defines the stateless variant of the systemd flatpak service:
  - apps list = `gnomeBaseApps` = `[ TextEditor, Loupe, Totem ]`
  - script includes the **desktop-only uninstall** migration block; no
    Totem-uninstall block.

> **Note on `commonExtensions`:** the literal list of common shell-extension
> identifiers can be defined as a Nix value either inline in each role
> file or in a tiny shared `let`-binding at the top of each role file
> (duplicated string literal). It MUST NOT live back in `gnome.nix` and be
> read from there by the role files, because the role files do not need
> any cross-file glue. A short duplicated literal is acceptable — exact
> contents listed in §5.

### 3.3 dconf merge semantics

`programs.dconf.profiles.user.databases` is a list type that concatenates
across modules. Defining a separate database in each role file produces a
two-database stack; later databases in the list shadow earlier ones at the
key level when keys overlap. The keys split between universal and role
files in this design **do not overlap**:

- Universal db sets `org/gnome/desktop/interface` keys
  `cursor-theme, icon-theme, clock-format, color-scheme`.
- Role db sets `org/gnome/desktop/interface` key `accent-color` only.
- Universal db does **not** set `org/gnome/shell` at all.
- Role db sets `org/gnome/shell` keys `enabled-extensions, favorite-apps`.

Because no key is written by both databases, dconf lookup-order behaviour is
irrelevant for correctness — every key has exactly one definition site
post-refactor, just as it has exactly one effective value pre-refactor.

### 3.4 Confirmation

After this refactor, `modules/gnome.nix` does not reference
`vexos.branding.role` in any form (no `let` binding, no attribute lookup,
no inline `config.vexos.branding.role`). The compliance grep is:

```
grep -n "vexos.branding.role\|lib.mkIf.*role\|lib.optional.*role" modules/gnome.nix
```

…must return zero matches.

---

## 4. Implementation Steps

Execute strictly in order. Each step is one commit-sized unit.

1. **Create `modules/gnome-desktop.nix`** with:
   - Header comment naming the file and stating "desktop-only GNOME additions".
   - `{ config, pkgs, lib, ... }: { … }` skeleton.
   - `environment.systemPackages = [ pkgs.unstable.gnomeExtensions.gamemode-shell-extension ];`
   - `environment.gnome.excludePackages = [];` (omit; not needed — papers stays).
   - Role-specific dconf `programs.dconf.profiles.user.databases` entry as
     described in §3.2, with the desktop accent, the
     `commonExtensions ++ [ gamemodeshellextension@trsnaqe.com ]` list, and
     the desktop favourites.
   - The systemd service block (apps list of 7 items, hash, install-only
     script — no migration `optionalString`).

2. **Create `modules/gnome-htpc.nix`** with:
   - Header comment.
   - `environment.gnome.excludePackages = with pkgs; [ papers ];`
   - Role-specific dconf db (orange, common extensions, htpc favourites).
   - systemd service: 2-app install list + Totem-uninstall + desktop-only-uninstall blocks.

3. **Create `modules/gnome-server.nix`** with:
   - Header comment.
   - `environment.gnome.excludePackages = with pkgs; [ papers ];`
   - Role-specific dconf db (yellow, common extensions, server favourites).
   - systemd service: 3-app install list + desktop-only-uninstall block.

4. **Create `modules/gnome-stateless.nix`** with:
   - Header comment.
   - `environment.gnome.excludePackages = with pkgs; [ papers ];`
   - Role-specific dconf db (teal, common extensions, stateless favourites).
   - systemd service: 3-app install list + desktop-only-uninstall block.

5. **Edit `modules/gnome.nix`**:
   - Delete the entire top-level `let` block (`gnomeBaseApps`,
     `gnomeDesktopOnlyApps`, `gnomeAppsToInstall`, `gnomeAppsHash`).
   - Inside `programs.dconf.profiles.user.databases`, delete the inner
     `let` (`role`, `accentColor`, `commonExtensions`, `enabledExtensions`,
     `favApps`).
   - From the universal database `settings`, delete the `org/gnome/shell`
     block entirely (no `enabled-extensions`, no `favorite-apps` here
     anymore) and delete the `accent-color = accentColor;` line from the
     `org/gnome/desktop/interface` block.
   - From `environment.gnome.excludePackages`, delete the
     `++ lib.optionals (config.vexos.branding.role != "desktop") [ papers ]`
     suffix; the list stays as the unconditional common bloat list.
   - From `environment.systemPackages`, delete the
     `unstable.gnomeExtensions.gamemode-shell-extension` line.
   - Delete the entire `systemd.services.flatpak-install-gnome-apps`
     definition.
   - Verify no `config.vexos.branding.role`, no `lib.optionals` over role,
     no `lib.optionalString` over role, and no `if … role == …` remains.

6. **Update `configuration-desktop.nix` imports** — append
   `./modules/gnome-desktop.nix` after `./modules/gnome.nix` in the imports
   list.

7. **Update `configuration-htpc.nix` imports** — append
   `./modules/gnome-htpc.nix` after `./modules/gnome.nix`.

8. **Update `configuration-server.nix` imports** — append
   `./modules/gnome-server.nix` after `./modules/gnome.nix`.

9. **Update `configuration-stateless.nix` imports** — append
   `./modules/gnome-stateless.nix` after `./modules/gnome.nix`.

10. **Verify `configuration-headless-server.nix` is untouched** — it does
    not import `modules/gnome.nix` and must not import any
    `modules/gnome-*.nix` file.

### 4.1 Import-list update table

| Configuration | New import to add | Position |
|---|---|---|
| `configuration-desktop.nix` | `./modules/gnome-desktop.nix` | immediately after `./modules/gnome.nix` |
| `configuration-htpc.nix`    | `./modules/gnome-htpc.nix`    | immediately after `./modules/gnome.nix` |
| `configuration-server.nix`  | `./modules/gnome-server.nix`  | immediately after `./modules/gnome.nix` |
| `configuration-stateless.nix` | `./modules/gnome-stateless.nix` | immediately after `./modules/gnome.nix` |
| `configuration-headless-server.nix` | (none — no display) | n/a |

### 4.2 Content sketches — exact key/package fragments to migrate

**Common shell extension list (used in every role file's `enabled-extensions`):**

```
"appindicatorsupport@rgcjonas.gmail.com"
"AlphabeticalAppGrid@stuarthayhurst"
"gnome-ui-tune@itstime.tech"
"nothing-to-say@extensions.gnome.wouter.bolsterl.ee"
"steal-my-focus-window@steal-my-focus-window"
"tailscale-status@maxgallup.github.com"
"caffeine@patapon.info"
"restartto@tiagoporsch.github.io"
"blur-my-shell@aunetx"
"background-logo@fedorahosted.org"
```

(The `dash-to-dock@micxgx.gmail.com` entry remains commented out in every
role file, exactly as in the pre-refactor source.)

**Desktop additional extension:** `"gamemodeshellextension@trsnaqe.com"`.

**Per-role flatpak install lists** (already enumerated in §5).

**Migration script fragments** (relocated verbatim, no `optionalString`
guards in the new files):

- *Totem-uninstall block* — present only in `gnome-htpc.nix`.
- *Desktop-only-app uninstall block* — present in `gnome-htpc.nix`,
  `gnome-server.nix`, `gnome-stateless.nix`. The list iterated in the
  shell loop is the **literal** desktop-only app set:
  `org.gnome.Calculator org.gnome.Calendar org.gnome.Papers org.gnome.Snapshot`.

---

## 5. Semantic-Equivalence Checklist

For every role, the **before** column is the effective value computed by
the current `modules/gnome.nix`; the **after** column is the value
produced by the universal file plus that role's addition file. The two
columns MUST be identical. (Roles are listed in the order
desktop / htpc / server / stateless.)

### 5.1 dconf key — `org/gnome/desktop/interface.accent-color`

| Role | Before | After |
|---|---|---|
| desktop   | `"blue"`   | `"blue"`   |
| htpc      | `"orange"` | `"orange"` |
| server    | `"yellow"` | `"yellow"` |
| stateless | `"teal"`   | `"teal"`   |

### 5.2 dconf key — `org/gnome/shell.enabled-extensions`

Common list (10 ids) is identical for every role. Desktop appends one extra.

| Role | Before | After |
|---|---|---|
| desktop   | common ++ `[ "gamemodeshellextension@trsnaqe.com" ]` | same |
| htpc      | common | common |
| server    | common | common |
| stateless | common | common |

### 5.3 dconf key — `org/gnome/shell.favorite-apps`

| Role | Before == After (full ordered list) |
|---|---|
| desktop | `brave-browser.desktop`, `app.zen_browser.zen.desktop`, `org.gnome.Nautilus.desktop`, `com.mitchellh.ghostty.desktop`, `io.github.up.desktop`, `org.gnome.Boxes.desktop`, `code.desktop` |
| htpc | `brave-browser.desktop`, `app.zen_browser.zen.desktop`, `plex-desktop.desktop`, `io.freetubeapp.FreeTube.desktop`, `org.gnome.Nautilus.desktop`, `io.github.up.desktop`, `com.mitchellh.ghostty.desktop`, `system-update.desktop` |
| server | `brave-browser.desktop`, `app.zen_browser.zen.desktop`, `org.gnome.Nautilus.desktop`, `com.mitchellh.ghostty.desktop`, `io.github.up.desktop` |
| stateless | `brave-browser.desktop`, `torbrowser.desktop`, `app.zen_browser.zen.desktop`, `org.gnome.Nautilus.desktop`, `com.mitchellh.ghostty.desktop`, `io.github.up.desktop` |

### 5.4 `environment.gnome.excludePackages`

Universal list (identical for all roles, before and after):
`gnome-photos, gnome-tour, gnome-connections, gnome-weather, gnome-clocks,
gnome-contacts, gnome-maps, gnome-characters, gnome-user-docs, yelp,
simple-scan, epiphany, geary, xterm, gnome-music, rhythmbox, totem,
showtime, gnome-calculator, gnome-calendar, snapshot`.

| Role | `papers` excluded? Before | After |
|---|---|---|
| desktop   | no  | no  |
| htpc      | yes | yes |
| server    | yes | yes |
| stateless | yes | yes |

### 5.5 `environment.systemPackages` — gamemode shell extension

| Role | `gnomeExtensions.gamemode-shell-extension` installed? Before | After |
|---|---|---|
| desktop   | yes (universal list) | yes (added by `gnome-desktop.nix`) |
| htpc      | yes (universal list) | **no** — removed; the package was previously installed but the extension was **never enabled** in dconf on this role, so closure shrinks slightly. This is an intentional, documented improvement, not a behavioural regression. |
| server    | yes (universal list) | **no** — same as htpc. |
| stateless | yes (universal list) | **no** — same as htpc. |

> **Reviewer note:** §5.5 is the *one* point where strict
> closure-equivalence is broken: three roles will no longer install an
> extension package they never enabled. If even this delta is
> unacceptable, keep the package in the universal `gnome.nix`
> `environment.systemPackages` list and only relocate the
> *enabled-extensions* dconf entry. Default in this spec: drop it from
> non-desktop closures, since installing an unused extension is
> dead weight.

### 5.6 Flatpak install list (`gnomeAppsToInstall` per role)

| Role | Before == After (set equality) |
|---|---|
| desktop   | `org.gnome.TextEditor, org.gnome.Loupe, org.gnome.Totem, org.gnome.Calculator, org.gnome.Calendar, org.gnome.Papers, org.gnome.Snapshot` |
| htpc      | `org.gnome.TextEditor, org.gnome.Loupe` |
| server    | `org.gnome.TextEditor, org.gnome.Loupe, org.gnome.Totem` |
| stateless | `org.gnome.TextEditor, org.gnome.Loupe, org.gnome.Totem` |

The `gnomeAppsHash` for each role is the first 16 hex chars of the SHA-256
of the comma-joined ordered list above. Because the list contents and
order are preserved verbatim, the hash — and therefore the on-disk stamp
file path `/var/lib/flatpak/.gnome-apps-installed-<hash>` — is identical
before and after the refactor. The systemd service therefore does **not**
re-trigger on first switch after deployment.

### 5.7 systemd unit `flatpak-install-gnome-apps`

| Role | Migration blocks present? Before | After |
|---|---|---|
| desktop   | none                          | none |
| htpc      | desktop-only uninstall + Totem | same |
| server    | desktop-only uninstall          | same |
| stateless | desktop-only uninstall          | same |

The `lib.mkIf config.services.flatpak.enable` guard is preserved on every
per-role unit definition.

---

## 6. Dependencies

None. This is a pure Nix refactor:

- No new flake inputs.
- No new nixpkgs packages.
- No new home-manager modules.
- No upstream/library API surface is touched.

Context7 documentation lookup is **not required** for this change.

---

## 7. Risks and Mitigations

| # | Risk | Mitigation |
|---|------|------------|
| 1 | A dconf key is dropped during migration (e.g. `accent-color` forgotten in one role file). | Section 5 enumerates every key and its value per role. The implementation subagent must tick every row. |
| 2 | A `configuration-*.nix` forgets to import its new `gnome-<role>.nix`. | Section 4.1 import-list table is mandatory; reviewer cross-checks all four configs. |
| 3 | dconf key collision between universal and role databases produces the wrong effective value. | §3.3 confirms the split is non-overlapping. The reviewer should grep both databases for any shared key path; expected result: zero overlap. |
| 4 | The systemd service unit name `flatpak-install-gnome-apps` is defined in multiple modules. | Each `configuration-<role>.nix` imports exactly one of `gnome-<role>.nix`, so only one definition is in scope per evaluation. (`nix flake check` validates this for every output.) |
| 5 | `gnomeAppsHash` changes inadvertently (e.g. list reordering), causing the flatpak install service to re-run on first switch and re-download apps. | §5.6 fixes the exact ordered list per role — implementation must preserve order character-for-character. |
| 6 | `papers` accidentally remains in the universal exclude list (causing it to be excluded on desktop too). | §5.4 explicitly tabulates desktop = "no exclusion"; reviewer verifies. |
| 7 | The `commonExtensions` list literal is duplicated four times and drifts out of sync if edited later. | Documented behaviour: future edits to that list MUST be made in all four role files. This is the cost of Option B's no-cross-file-glue rule and is accepted. (A future extraction into a small shared *.nix data module is allowed but out of scope for this refactor.) |
| 8 | Closure regression on htpc/server/stateless from removing `gamemode-shell-extension` package (§5.5). | Documented as an intentional, harmless improvement. If unacceptable, keep the package universal — only relocate the dconf line. |
| 9 | A future contributor re-introduces a role conditional in `gnome.nix`. | Add the explicit grep guard in §3.4 to the project preflight as part of a follow-up; tracked separately. Out of scope here. |

---

## 8. Out of Scope

The following items are **explicitly out of scope** for this refactor and
must not be changed by the implementation subagent. They are tracked
separately and will be handled by their own spec/work item.

1. **`configuration-htpc.nix` dconf triple-write** — the file currently
   writes a third copy of `org/gnome/desktop/interface` and
   `org/gnome/shell` directly into
   `programs.dconf.profiles.user.databases`, duplicating data already
   present in `modules/gnome.nix` and in `home-htpc.nix`. The duplication
   is preserved as-is by this refactor; deduplication is a separate task.
2. **Home Manager `home-*.nix` dconf settings** — not modified.
3. **Thin flake template** (`template/etc-nixos-flake.nix`) — not modified.
4. **`mkHost` helper / `flake.nix` plumbing** — not modified.
5. **README, justfile, preflight script, CI workflows** — not modified.
6. **`system.stateVersion`** — must remain `"25.11"` in
   `configuration-desktop.nix` and every other `configuration-*.nix`.
   It is never to be changed post-install.
7. **All other audit findings** about `modules/gnome.nix` (e.g. ordering
   of overlays, font choice, autoLogin user being hard-coded) — out of
   scope; this refactor is a structural split only.

---

## 9. Validation Plan

Run after implementation, and again after any refinement cycle.

1. `nix flake check`
2. `sudo nixos-rebuild dry-build --flake .#vexos-desktop-amd`
3. `sudo nixos-rebuild dry-build --flake .#vexos-htpc-amd`
4. `sudo nixos-rebuild dry-build --flake .#vexos-server-amd`
5. `sudo nixos-rebuild dry-build --flake .#vexos-stateless-amd`
6. `sudo nixos-rebuild dry-build --flake .#vexos-headless-server-amd`
   — **must succeed unchanged**; this configuration does **not** import
   `modules/gnome.nix` or any of the new `modules/gnome-<role>.nix`
   files, so it is unaffected by the refactor. Build success here
   confirms the refactor did not leak any cross-cutting evaluation.
7. Static compliance check on the refactored universal module:
   `grep -nE "vexos\\.branding\\.role|lib\\.optionalString|lib\\.optionals|if .* role" modules/gnome.nix` must return **no matches**.
8. `scripts/preflight.sh` (project preflight) must exit 0.

A successful run of (1)–(8) is the gate for Phase 6 completion.
