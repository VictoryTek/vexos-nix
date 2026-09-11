# DMS → ReGreet Greeter Migration — Specification

Feature: replace the DankMaterialShell (DMS) greetd greeter — orphaned since
the shell itself moved to Noctalia (`noctalia_v5_migration_spec.md`) — with
ReGreet, themed with this project's VexOS Neo-Cyberpunk Dark palette and its
existing logo mark, on a newly-authored (not reused) background.

Status: Phase 1 (Research & Specification)

---

## 1. Current state analysis

`modules/hyprland-desktop.nix`, gated `lib.mkIf isHyprland`, still configures:

```nix
programs.dank-material-shell.greeter = {
  enable             = true;
  compositor.name    = "hyprland";
  quickshell.package = pkgs.quickshell;
};
```

wired from `flake.nix`'s `dmsBase = [ inputs.dms.nixosModules.dank-material-shell
inputs.dms.nixosModules.greeter ];`. This predates the Noctalia migration,
which swapped the **shell** (`home/dank-material-shell.nix` → `enable =
false`, `home/noctalia.nix` → active) but never touched the **greeter**, a
separate subsystem — hence the user's report that login still shows DMS.

Root cause, verified against the exact locked `dms` rev
(`069ddab041c738236a8910e4c39b65d9628d3018`, `flake.lock`): the greeter is
not merely stale-but-working — `inputs.dms.nixosModules.greeter` at that
pinned rev is `mkModuleWithDmsPkgs ./distro/nix/greeter.nix`, a real,
functioning module. It genuinely still runs and renders the DMS UI, exactly
as configured; nothing broke, it was simply never migrated. (Aside, not
actionable now: upstream's live `stable` branch HEAD has since replaced this
with `nixosModules.greeter = builtins.warn "...moved to dank-greeter..." {
};` — an inert stub. If `dms` is ever updated past that point while this
module is still referenced, evaluation would hard-fail with "option does not
exist". Moot once this change removes the reference.)

## 2. Problem definition & option research

Two other greetd greeters were evaluated before choosing a path (2026-09-11
discussion with user):

| Candidate | Verdict |
|---|---|
| `dank-greeter` (DMS's greeter successor, separate repo `AvengeMedia/dank-greeter`, option `programs.dms-greeter`) | Rejected — requires a brand-new flake input to theme a shell (DMS) that is already disabled; NixOS module exposes only `enable`/`compositor.*`/`configHome` (pulls in DMS's own wallpaper), no deeper theming |
| `noctalia-greeter` (`noctalia-dev/noctalia-greeter`, `programs.noctalia-greeter`) | Matches the active shell, full TOML theming, but same logo limitation as below |
| **ReGreet** (`rharish101/ReGreet`) | **Chosen by user.** Already in nixpkgs (`programs.regreet` — no new flake input), full TOML settings **and** free-form GTK CSS (`extraCss`) for the deepest customization of the three |

**Logo limitation confirmed across all three**: none expose a "custom logo
image" config key. ReGreet's own widget template
(`src/gui/templates.rs`/`component.rs` read directly at the pinned nixpkgs
rev) has no image/logo widget at all — only `#background` (a `gtk::Picture`
filling the window) and named panels (`.background`-class `Frame`s: the
unnamed login card and `#clock_frame`). The only way to show this project's
mark is to paint it in via CSS `background-image` on an existing named
widget, or bake it into the background image. This spec uses the former
(placed on `#clock_frame`, see §3.3) so the login-card layout is undisturbed.

**User direction (2026-09-11, follow-up):** "nice modern... cyberpunk style
like this project" + **"Dont reuse any wallpapers"** — i.e. the background
must be freshly authored for the greeter, not `wallpapers/desktop/vex-bb-*`.

## 3. Proposed solution architecture

### 3.1 Verified against the exact pinned `nixpkgs` rev (`d58a46e3…`, `flake.lock` root `nixpkgs`)

Fetched `nixos/modules/programs/regreet.nix` directly at that revision (not
summarized) to avoid acting on a stale or unstable-channel option path:

- **Option namespace is `programs.regreet.*`**, not
  `services.displayManager.regreet.*` (a newer/unstable-channel path that
  does not exist at our pin — confirmed by reading the module file itself
  rather than trusting a generic search index).
- `programs.regreet.enable = true` sets `services.greetd.enable = lib.mkDefault
  true` and `services.greetd.settings.default_session.command = lib.mkDefault
  "dbus-run-session cage <cageArgs> -- regreet"` — both `mkDefault`, so **we
  must not declare `services.greetd` ourselves**, same rule the DMS greeter
  followed.
- `programs.regreet.settings` is a free-form TOML attrset
  (`pkgs.formats.toml`) — merges across modules at the leaf-key level, so our
  `settings.background = { … }` coexists cleanly with the module's own
  `settings.GTK = { cursor_theme_name = …; }` (built from the dedicated
  `cursorTheme`/`font`/`iconTheme`/`theme` options — **use those options, not
  a hand-written `settings.GTK`**, to avoid a duplicate-definition conflict
  on the `GTK` key).
- The module already sets `services.accounts-daemon.enable = true;` itself —
  the defensive duplicate in `modules/hyprland-desktop.nix`'s current DMS
  section becomes redundant and is dropped, not carried forward.
- `extraCss` type is `path or lines` — a plain multi-line Nix string works.
- Background `fit` values (from `regreet.sample.toml`): `"Fill"`,
  `"Contain"`, `"Cover"`, `"ScaleDown"`.
- Session list comes from the same XDG `.desktop` discovery every greetd
  greeter uses — `hyprland-uwsm.desktop` (registered by
  `programs.uwsm.waylandCompositors.hyprland`, already in
  `modules/hyprland-desktop.nix`) is unaffected by the greeter swap. The
  "SELECT THE UWSM ONE" gotcha documented there still applies and is
  reproduced in the new file's comments.
- Autologin (`services.displayManager.autoLogin`, `defaultSession =
  "hyprland-uwsm"`) is a generic `displayManager` option read by whichever
  greetd greeter is active — **not** DMS-specific, stays untouched in
  `modules/hyprland-desktop.nix`.

### 3.2 Background — newly authored art, not a reused wallpaper

`files/regreet/background.svg` (new): hand-authored vector art using the
`files/dms/vexos-neo-cyberpunk.json` "Dark" palette — navy base gradient
(`#050A14` → `#0B1526`), a soft cyan radial glow (`#05F4FA`, upper-right), a
faint orange glow (`#DD4014`, lower-left) for depth, a faded circuit-style
grid, and a few thin traced "circuit" lines with node dots. Rendered and
visually confirmed via `resvg` in this session — reads as a distinct,
purpose-built piece, not a copy of `wallpapers/desktop/vex-bb-{dark,light}.jxl`.

Rasterized at build time by a small `pkgs.runCommand` derivation using
`pkgs.resvg` (verified present in nixpkgs at this pin) → 1920×1080 PNG (GTK's
`gdk-pixbuf` PNG loader is always available; avoids depending on whichever
GStreamer plugins happen to be installed for less common formats).
`settings.background = { path = "<derivation>/background.png"; fit =
"Cover"; };`.

### 3.3 Logo — composited via CSS onto `#clock_frame`, not baked into the background

`files/pixmaps/${role}/vex.png` (existing asset, same one
`modules/branding-display.nix` already uses for the GDM logo, resolved
dynamically off `config.vexos.branding.role` the same way that module does —
`hyprland-desktop.nix`/the new greeter file is currently only reachable via
the `desktop` role, but this keeps the reference self-contained rather than
hardcoding `"desktop"`) is placed as a `background-image` on the `#clock_frame`
overlay panel (top-center, above the clock text, inside the same rounded
panel) via `extraCss`. This is additive to the existing frame — no template
change, no new widget, nothing the upstream project has to keep supporting.

### 3.4 CSS theming — `extraCss`, targeting verified widget names only

Read `src/gui/component.rs`/`templates.rs` at the ReGreet `main` HEAD
directly (raw source, not summarized) to get exact, real GTK widget names
before writing any selector — every ID below is confirmed to exist:

`#background` (Picture — background image widget), `.background` (CSS class
shared by the login-card `Frame` and `#clock_frame`), `#message_label`,
`#session_label`, `#input_label`, `#username_entry`, `#usernames_box`,
`#session_entry`, `#sessions_box`, `#secret_entry`, `#visible_entry`,
`#user_toggle`, `#sess_toggle`, `#cancel_button`, `#login_button`
(`.suggested-action`), `#clock_frame`, `#notif_info`, `#notif_label`,
`#reboot_button`/`#poweroff_button` (`.destructive-action`).

Styling plan, all colors from `vexos-neo-cyberpunk.json` "Dark":

- Login card + clock frame (`.background`): translucent navy panel
  (`alpha(#0B1526, .82)`), `1px` cyan-alpha border, soft cyan glow shadow,
  rounded corners.
- Entries/combo boxes: dark surface fill (`#16233A`), light text
  (`#E7EEF5`), cyan focus ring on `:focus`.
- `#login_button.suggested-action`: solid cyan (`#05F4FA`) on near-black text
  (`#00141A`) — the project's own "primary/on_primary" pair.
- `.destructive-action` (`#reboot_button`, `#poweroff_button`): translucent
  error-red (`#FF4D6D`) outline/fill.
- `#notif_info`/`#notif_label`: error-red, for failed-login feedback.
- `#clock_frame`: logo image (see §3.3) + cyan glow text.

One noted-but-non-blocking risk: `text-shadow` is used for the clock glow.
GTK CSS support for it is inconsistent across GTK4 point releases; if
unsupported the property is silently ignored by the CSS parser (not a build
or runtime failure) and the clock simply renders without the glow. Flagged
in the review rather than asserted as guaranteed to render.

## 4. Implementation steps

1. **`files/regreet/background.svg`** (done, this session) — verify:
   `resvg` renders it without error; visually inspected.
2. **`modules/hyprland-greeter.nix`** (new) — mirrors the existing
   `modules/gnome-desktop.nix`-style split (a role-scoped addition file
   reusing its parent's existing gate, not a new one):
   - `lib.mkIf (config.vexos.desktop.environment == "hyprland")` — the same
     pre-existing gate `modules/hyprland-desktop.nix` already uses.
   - Background derivation (`pkgs.runCommand` + `pkgs.resvg`).
   - `programs.regreet.enable = true;` + `settings.background`,
     `settings.appearance.greeting_msg`, `settings.GTK.application_prefer_dark_theme`.
   - `font.package = pkgs.inter; font.name = "Inter";` (matches the font
     already installed for the Noctalia bar in `hyprland-desktop.nix`).
   - `extraCss` (the theming from §3.4).
   - `systemd.services.greetd.restartIfChanged = false;` (moved from
     `hyprland-desktop.nix`, same rationale as today: a switch that restarts
     greetd mid-session blackscreens the running compositor).
   → verify: `nix eval` full closure on the forced-hyprland branch succeeds.
3. **`configuration-desktop.nix`** — import the new file alongside the
   existing `./modules/hyprland-desktop.nix` line.
   → verify: import list diff is one line.
4. **`modules/hyprland-desktop.nix`** — remove the "── Greeter ──" section
   (the `programs.dank-material-shell.greeter` block, its comment block, the
   now-redundant `services.accounts-daemon.enable = true;` line, and the
   `systemd.services.greetd.restartIfChanged = false;` line — the last two
   move into the new file). Update the file's own header comment (currently
   says "Hyprland compositor + DankMaterialShell (DMS) desktop shell + DMS
   greeter" and "Layer split: … greeter …") to stop describing itself as
   owning the greeter, since Noctalia is the shell and the greeter now lives
   in its own file. Leave autologin, PAM/keyring, and every non-greeter
   section untouched.
   → verify: `grep -c "dank-material-shell.greeter"` returns 0 in this file.
5. **`flake.nix`** — remove `inputs.dms.nixosModules.greeter` from
   `dmsBase`. Keep `inputs.dms.nixosModules.dank-material-shell` (out of
   scope — the shell's own NixOS-side option tree is a separate concern from
   this greeter swap, and `home/dank-material-shell.nix` already disables
   the shell itself; touching that module is not part of "fix the login
   manager").
   → verify: `nix flake show --impure` still lists all outputs.
6. **`modules/branding-display.nix`** — its comment says "Hyprland uses the
   DankMaterialShell greeter"; update the one word to ReGreet. No functional
   change (this file is GDM-only, gated to the `gnome` branch, genuinely
   inert for Hyprland either way) — comment accuracy only.
   → verify: comment diff only, `git diff --stat` shows no `config = ...`
   changes here.

### 4.1 Module Architecture Pattern compliance

`modules/hyprland-greeter.nix` reuses the *existing*
`config.vexos.desktop.environment == "hyprland"` gate — the same one
`modules/hyprland-desktop.nix` (its sibling) and `home/noctalia.nix` already
use. This is not a new guard added to a shared module; it is the established
per-role-file pattern (`gnome.nix`/`gnome-desktop.nix`,
`dank-material-shell.nix`/`noctalia.nix`) applied to split out a subsystem
(the greeter) that has outgrown living inline inside
`modules/hyprland-desktop.nix`.

## 5. Dependencies

| Name | Version | Source | Context7 |
|---|---|---|---|
| `regreet` (via `programs.regreet`) | nixpkgs, pinned rev `d58a46e3…` | in-tree `nixos/modules/programs/regreet.nix` | N/A — verified directly against the exact pinned module source, not a library with Context7 coverage |
| `resvg` | nixpkgs | build-time only (SVG→PNG rasterization) | N/A — single-purpose CLI, verified present via `mcp__nixos__nix` search at this pin |

No new flake input. `dank-greeter` and `noctalia-greeter` were both
evaluated and explicitly not chosen (see §2) — this avoids adding either as
an input.

## 6. Configuration changes

New: `files/regreet/background.svg`, `modules/hyprland-greeter.nix`.
Edited: `configuration-desktop.nix` (one import line), `modules/hyprland-desktop.nix`
(remove greeter section + header comment), `flake.nix` (`dmsBase` list),
`modules/branding-display.nix` (one comment word).

## 7. Risks and mitigations

| Risk | Impact | Mitigation |
|---|---|---|
| `programs.regreet.*` option path assumed from the pinned nixpkgs source, not runtime-tested (no NixOS host reachable from this Windows session) | A typo'd option name fails `nix eval`, which we *can* run | Read the exact module file at the exact pinned rev directly (not summarized, not unstable-channel docs); `nix eval --impure` on the forced-hyprland branch is run in Phase 3 as the closest available verification |
| `text-shadow` GTK CSS support is inconsistent | Clock loses its glow effect, cosmetic only | Non-fatal either way (bad/unsupported CSS properties are skipped by GTK's CSS parser, not a hard error); documented, not asserted as guaranteed |
| `#clock_frame` logo placement via `background-image` + padding is a CSS trick, not a first-class widget | Logo could clip or mis-size on very small/very large output scales until seen on real hardware | Sized conservatively with explicit `background-size`; called out to the user as something to eyeball after first real login, not guaranteed pixel-perfect sight-unseen |
| Removing `inputs.dms.nixosModules.greeter` from `dmsBase` | None — `dank-material-shell` (the option-tree module) stays; only the unused greeter module reference is dropped | `home/dank-material-shell.nix` already sets `enable = false`; nothing else in the repo references `programs.dank-material-shell.greeter` after step 4 |
| This environment (Windows, no NixOS host) cannot run `sudo nixos-rebuild dry-build` or actually render the login screen | Visual correctness (logo placement, CSS rendering) can't be confirmed pixel-for-pixel before the user reboots | Same limitation already surfaced and accepted in the prior Noctalia bar/dock fix this session; `nix eval --impure` on the forced-hyprland branch (via WSL) is the closest available substitute and is run in Phase 3 |

## 8. Out of scope

- Removing `inputs.dms` / `home/dank-material-shell.nix` entirely (DMS stays
  installed-but-inactive, as the original Noctalia migration spec decided).
- `noctalia-greeter` or `dank-greeter` (evaluated, not chosen).
- Testing the actual rendered login screen on `vextop` — user verifies after
  reboot; `sudo nixos-rebuild switch`/`boot` are FORBIDDEN COMMANDS
  (user-initiated only).
- Any change to the wallpapers used by the desktop session itself
  (`wallpapers/desktop/vex-bb-*.jxl`) — untouched, per "don't reuse
  wallpapers" this is a *new*, separate asset, not a replacement of those.
