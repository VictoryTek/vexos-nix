# Hyprland + DankMaterialShell (DMS) shell and greeter — Specification

Supersedes the Noctalia layer defined in `hyprland_noctalia_session_spec.md`
(and its review). The compositor decisions from that spec are unchanged and are
restated here only where relevant.

## 1. Current state analysis

`vexos.desktop.environment = "hyprland"` currently produces:

| Concern | Current | Fate |
|---|---|---|
| Compositor | `programs.hyprland` + UWSM | **kept, unchanged** |
| Shell | Noctalia v5 via `inputs.noctalia.homeModules.default` (`programs.noctalia`) | **removed** → DankMaterialShell |
| Greeter | `noctalia-greeter` (greetd, own wlroots compositor) via `inputs.noctalia-greeter.nixosModules.default` | **removed** → `programs.dank-material-shell.greeter` (greetd, runs Hyprland) |
| `hyprland.conf` | none — Hyprland autogenerates its default | **changed** → seed a minimal managed-once config (user decision) |
| Polkit agent / udiskie / hyprpolkitagent | `home/noctalia.nix` | **kept** — not shell-specific |
| Secret Service, gvfs, udisks2, upower, dconf, portals, GNOME apps, Flatpak parity | `modules/hyprland-desktop.nix` | **kept** — GNOME-parity layer, shell-agnostic |
| Screenshot / picker / nwg-* / pavucontrol packages | `modules/hyprland-desktop.nix` | **kept** — DMS does not provide these |

Confirmed by user: **Noctalia + Hyprland currently boots and renders** on the
target machine. The Hyprland compositor, UWSM wiring, and greetd display-manager
path are therefore proven. This change swaps only the shell and the greeter.

Historical note: DMS (`programs.dms-shell`) was the original Hyprland shell in
this repo (commits `6ab1ae2`→`3b82278`) and was reported to never boot. DMS has
since had a major maturation (it is now a Quickshell 0.3.x + Go project with a
maintained Nix flake, `nixosTests`, and a greeter module). The prior failure is
treated as a fixed upstream bug, not a standing risk — but see §7.

## 2. Problem definition

Replace the Noctalia desktop shell and the `noctalia-greeter` login screen with
DankMaterialShell and its bundled greeter, keeping:

- the Hyprland compositor and its UWSM registration exactly as they are,
- the entire GNOME-parity system layer (`modules/hyprland-desktop.nix` minus the
  Noctalia-specific lines),
- the polkit agent and removable-media automount from the home layer.

Add a minimal, seeded-once `hyprland.conf` so the shell is usable on first boot
(DMS provides no clickable bar affordance for its launcher/lock/clipboard — those
are IPC calls that must be bound to keys).

## 3. Proposed solution architecture

### 3.1 Compositor: unchanged

`programs.hyprland` (`enable`, `xwayland.enable`, `withUWSM`) and
`programs.uwsm.waylandCompositors.hyprland` stay verbatim. UWSM remains
load-bearing: it activates `graphical-session.target`, and DMS's Home Manager
systemd user service binds to `config.wayland.systemd.target` (which resolves to
that target) exactly as Noctalia's did. Without UWSM the shell would silently
never start.

The greeter still lists two Hyprland sessions (`hyprland.desktop` and
`hyprland-uwsm.desktop`). **Select the UWSM entry.** Documented in the module
header, unchanged from the Noctalia design.

### 3.2 Shell: DankMaterialShell via the Home Manager module

Upstream flake: `github:AvengeMedia/DankMaterialShell/stable` (user decision —
`stable`, not `main`; the daily `chore: update flake inputs` job will still bump
it, but `stable` is the branch upstream designates for distro packaging).

Flake outputs used:

| Output | Path in repo | Role |
|---|---|---|
| `homeModules.dank-material-shell` | `distro/nix/home.nix` (+ `options.nix`, `common.nix`) | the shell, its systemd user service, `settings`/`session` JSON, feature toggles |
| `nixosModules.dank-material-shell` | `distro/nix/nixos.nix` (+ `options.nix`) | declares the NixOS-side `programs.dank-material-shell` option tree the greeter reads; installs nothing unless `enable` is set (which we do NOT set) |
| `nixosModules.greeter` | `distro/nix/greeter.nix` | `programs.dank-material-shell.greeter.*`; configures `services.greetd` |

**Use the Home Manager module for the shell**, mirroring the Noctalia decision:
it is the module that carries `settings` (`~/.config/DankMaterialShell/settings.json`),
`clipboardSettings`, `session`, and `plugins` — the surface a later customisation
phase needs — and its systemd user service has `restartIfChanged` triggers. The
NixOS module would install the shell binary system-wide with no `settings`
surface; we do not enable it.

`home/dank-material-shell.nix`, in the exact shape of the removed
`home/noctalia.nix`:

```nix
{ pkgs, lib, inputs, osConfig, ... }:
{
  # imports cannot be conditional; the upstream module is inert until
  # programs.dank-material-shell.enable is set.
  imports = [ inputs.dms.homeModules.dank-material-shell ];

  config = lib.mkIf (osConfig.vexos.desktop.environment == "hyprland") {
    programs.dank-material-shell = {
      enable                 = true;
      systemd.enable         = true;
      quickshell.package     = pkgs.quickshell;   # 0.3.0 in nixos-26.05 — verified
      dgop.package           = pkgs.dgop;         # set explicitly; no module default
      enableSystemMonitoring = true;   # dgop
      enableCalendarEvents   = true;   # khal
      enableDynamicTheming   = true;   # matugen
      enableAudioWavelength  = true;   # cava
      enableVPN              = true;   # networkmanager (already enabled system-side)
      # settings / session intentionally unset — stock shell, customisation later
    };

    # kept from home/noctalia.nix — shell-agnostic, DMS does not provide these
    services.hyprpolkitagent.enable = true;
    services.udiskie = { enable = true; automount = true; tray = "auto"; };
  };
}
```

`quickshell.package`, `dgop.package`, `matugen`, `cava`, `khal` are all in
`nixos-26.05` (verified via the nixos MCP: quickshell 0.3.0, dgop 0.2.2,
matugen 4.0.0). `dms-shell` itself is built from source by the module
(`cfg.package` default), which requires the `dmsPkgs` specialArg — supplied by
`inputs.dms.homeModules.dank-material-shell`, so nothing extra is plumbed.

`home-desktop.nix` already takes `inputs` and `mkHomeManagerModule` already
passes `extraSpecialArgs = { inherit inputs; … }`, so the import needs no
plumbing change — same as Noctalia.

### 3.3 Greeter: `programs.dank-material-shell.greeter`

`nixosModules.greeter` (`distro/nix/greeter.nix`, verified verbatim) declares
`options.programs.dank-material-shell.greeter`:

| Option | Set to | Note |
|---|---|---|
| `enable` | `true` | |
| `compositor.name` | `"hyprland"` | greeter resolves `compositorPackage` from `config.programs.hyprland.package` via `attrByPath ["programs" "hyprland" "package"]` — already set by `programs.hyprland.enable` |
| `package` | default (`dms-shell` from the flake) | greeter QML ships inside the shell package (`share/quickshell/dms/Modules/Greetd/assets/dms-greeter`) |
| `quickshell.package` | `pkgs.quickshell` | keep consistent with the shell |
| `configHome` | leave default | optional theme sync from a user's `settings.json`; out of scope for the baseline |

Its `config` block sets:

```nix
services.greetd = {
  enable = lib.mkDefault true;
  settings.default_session.command = lib.mkDefault (lib.getExe greeterScript);
  settings.initial_session = lib.mkIf (autoLogin.enable && autoLogin.user != null) { … };
};
```

So **we do not declare `services.greetd` ourselves** — exactly as with
`noctalia-greeter`. The old repo had no in-repo `services.greetd` block (the
greeter module owned it), so there is nothing to remove there; we only swap which
greeter module is imported.

`services.greetd.settings.default_session.user` is read for an assertion; the
NixOS `greetd` module defaults it to `"greeter"`, which exists — no action.

The greeter runs **Hyprland itself** as its compositor (not a separate bundled
wlroots compositor like `noctalia-greeter` did). This removes the
"greeter renders but Hyprland doesn't" diagnostic that the Noctalia spec §7
called out — acceptable, since Hyprland boot is now confirmed working.

`accounts-daemon`: `noctalia-greeter` enabled `services.accounts-daemon`
(`mkDefault`). Verify whether `greeter.nix` does the same; if not and the greeter
needs a user list, add `services.accounts-daemon.enable = true` explicitly.
(Recorded as a Phase 3 check, not assumed.)

### 3.4 Seeded `hyprland.conf` (user decision: "seed a minimal config")

DMS is unusable on first boot without keybinds — its launcher, clipboard,
notification center, control center and lock are all `dms ipc call …` targets
with no default bar button. Noctalia had a clickable bar, so the Noctalia spec
could leave Hyprland unconfigured; that is no longer acceptable.

**Mechanism — seed once, then hands-off.** A Home Manager activation script
copies `files/hypr/hyprland.conf` to `~/.config/hypr/hyprland.conf` **only if
that file does not already exist**. After first boot the user owns the file and
`nixos-rebuild` never touches it again. This matches the repo's prior pattern for
seeded-once user state (the removed `vexos-hyprland-wallpaper` stamp-file unit,
and the `vexos-init-*` oneshots in `home-desktop.nix`). It deliberately does NOT
use `xdg.configFile."hypr/hyprland.conf"` — that would be a read-only store
symlink and Hyprland users expect to edit their config live.

**Contents** (`files/hypr/hyprland.conf`) — minimal, DMS-focused:

```
# Seeded once by VexOS. Edit freely — nixos-rebuild will not overwrite this.
# Full reference: https://wiki.hypr.land/Configuring/

monitor = , preferred, auto, 1

exec-once = dms run
exec-once = bash -c "wl-paste --watch cliphist store &"

$mod = SUPER
$terminal = ghostty

# DMS shell
bind = $mod,       Space,  exec, dms ipc call spotlight toggle
bind = $mod,       V,      exec, dms ipc call clipboard toggle
bind = $mod,       N,      exec, dms ipc call notifications toggle
bind = $mod,       M,      exec, dms ipc call processlist toggle
bind = $mod,       comma,  exec, dms ipc call settings toggle
bind = $mod,       X,      exec, dms ipc call dash toggle ""
bind = $mod,       L,      exec, dms ipc call lock lock
bind = $mod SHIFT, N,      exec, dms ipc call night toggle

# Media / brightness keys → DMS (so the OSD shows)
bindel = , XF86AudioRaiseVolume,  exec, dms ipc call audio increment 5
bindel = , XF86AudioLowerVolume,  exec, dms ipc call audio decrement 5
bindl  = , XF86AudioMute,         exec, dms ipc call audio mute
bindel = , XF86MonBrightnessUp,   exec, dms ipc call brightness increment 10
bindel = , XF86MonBrightnessDown, exec, dms ipc call brightness decrement 10
bindl  = , XF86AudioPlay,         exec, playerctl play-pause
bindl  = , XF86AudioNext,         exec, playerctl next
bindl  = , XF86AudioPrev,         exec, playerctl previous

# Screenshots (tools already installed by modules/hyprland-desktop.nix)
bind = ,           Print,  exec, hyprshot -m region
bind = $mod,       Print,  exec, hyprshot -m window
bind = $mod SHIFT, Print,  exec, hyprshot -m output

# Window management — minimal
bind = $mod,       Return, exec, $terminal
bind = $mod,       Q,      killactive
bind = $mod,       E,      exec, nautilus
bind = $mod,       F,      fullscreen
bind = $mod,       Space,  # (reserved above)
bind = $mod SHIFT, Space,  togglefloating
bind = $mod,       1, workspace, 1
bind = $mod,       2, workspace, 2
bind = $mod,       3, workspace, 3
bind = $mod,       4, workspace, 4
bind = $mod,       5, workspace, 5
bind = $mod SHIFT, 1, movetoworkspace, 1
bind = $mod SHIFT, 2, movetoworkspace, 2
bind = $mod SHIFT, 3, movetoworkspace, 3
bind = $mod SHIFT, 4, movetoworkspace, 4
bind = $mod SHIFT, 5, movetoworkspace, 5
bind = $mod,       left,  movefocus, l
bind = $mod,       right, movefocus, r
bind = $mod,       up,    movefocus, u
bind = $mod,       down,  movefocus, d
bindm = $mod, mouse:272, movewindow
bindm = $mod, mouse:273, resizewindow
```

The duplicate `$mod, Space` line is a spec typo — the implementation must have
`Space` bound once (to spotlight) and use `$mod SHIFT, Space` for floating.
`dms keybinds show hyprland` (from the shell package) can be used later to
regenerate a fuller reference; not wired into the build.

**Cliphist**: `cliphist` is currently NOT installed (Noctalia owned clipboard
history). DMS's clipboard uses `cliphist` as its store backend. Add `cliphist`
to `modules/hyprland-desktop.nix`'s `environment.systemPackages`. `wl-clipboard`
is already present.

### 3.5 Flake input wiring

Replace the two Noctalia inputs with one DMS input. DMS ships **no overlays**
(confirmed from its `flake.nix`), so the `nixpkgs.overlays` half of `noctaliaBase`
is dropped entirely; packages are referenced as `pkgs.quickshell` / `pkgs.dgop`
(nixpkgs) and `inputs.dms.packages.${system}.default` (via the module default).

```nix
# inputs — replaces `noctalia` and `noctalia-greeter`
dms = {
  url = "github:AvengeMedia/DankMaterialShell/stable";
  inputs.nixpkgs.follows = "nixpkgs";
};

# replaces `noctaliaBase`
dmsBase = [
  inputs.dms.nixosModules.dank-material-shell   # declares programs.dank-material-shell (option tree only)
  inputs.dms.nixosModules.greeter               # programs.dank-material-shell.greeter + services.greetd
];
```

`dmsBase` is appended to `roles.desktop.baseModules` in place of `noctaliaBase`.
Both modules are inert on GNOME/COSMIC desktop hosts: `nixos.nix`'s `config` is
guarded by `programs.dank-material-shell.enable` (set only via the home module,
which is itself gated on `vexos.desktop.environment == "hyprland"`), and
`greeter.nix`'s `config` is guarded by `programs.dank-material-shell.greeter.enable`
(set only inside `modules/hyprland-desktop.nix`'s `isHyprland` guard).

`inputs.nixpkgs.follows = "nixpkgs"` per CLAUDE.md. DMS's `flake.nix` declares
`nixpkgs` as `nixos-unstable`; `follows` overrides it to the 26.05 pin. §7
records the fallback.

`flake.lock`: `nix flake lock` will drop the `noctalia` and `noctalia-greeter`
nodes and add `dms`. This is a lock-file change the user runs (Phase 7 note).

### 3.6 What DMS replaces, and what stays

DMS provides: top bar, control center, notification center, spotlight launcher,
app drawer, clipboard viewer, process list, dank dash, notepad, lock screen,
OSDs, dynamic Material-You theming, wallpaper, system tray, calendar, audio
visualiser, night mode, VPN/bluetooth/network widgets.

**Kept from `modules/hyprland-desktop.nix` unchanged** (GNOME-parity / not
provided by any shell):

- Secret Service: `services.gnome.gnome-keyring.enable`, `programs.seahorse.enable`
- `services.gvfs`, `services.udisks2`, `services.upower`, `programs.dconf`
- `xdg.portal.extraPortals = [ xdg-desktop-portal-gtk ]`,
  `xdg.portal.config.common.default = [ "hyprland" "gtk" ]`
- Package set: `hyprshot`, `grim`, `slurp`, `hyprpicker`, `wl-clipboard`,
  `nwg-look`, `nwg-displays`, `pavucontrol`, `brightnessctl`, `ddcutil`,
  `playerctl`, `nautilus`, `file-roller`, the GNOME utilities, GTK support
- `vexos.gnome.flatpakInstall.apps` parity list

**Added to that package set:** `cliphist` (§3.4).

**Removed** — Noctalia-specific, now redundant: nothing in the package set (the
old spec already excluded waybar/fuzzel/swaync/etc.). Only the `home/noctalia.nix`
comments referencing "Noctalia owns clipboard history" change.

**Fonts:** DMS renders its UI with **Material Symbols Rounded** and **Inter**.
Check `modules/desktop-common.nix` `fonts.packages` — if absent, add
`material-symbols` and `inter`. Missing Material Symbols makes the DMS bar show
tofu boxes for every icon. (Phase 2 check.)

### 3.7 `hypridle`

Still deliberately **not** installed. DMS ships its own lock (`dms ipc call lock`)
and idle handling via its settings; a second idle daemon risks double-locking.
Same reasoning as the Noctalia spec. Revisit only if idle-to-lock does not work.

## 4. Implementation steps

Module Architecture Pattern: `modules/hyprland-desktop.nix` keeps its
`lib.mkIf (config.vexos.desktop.environment == "hyprland")` guard — a toggleable
subsystem gated on an option its own module family (`modules/desktop-environment.nix`)
declares, which is the CLAUDE.md carve-out and the shape of all three DE modules.
No new role-gating `mkIf` enters a shared module.

### Step 1 — `flake.nix`

1. Delete the `noctalia` and `noctalia-greeter` inputs (lines ~60–82); add the
   `dms` input with the block comment updated to describe DMS/stable and the
   daily-update tradeoff.
2. Replace the `noctaliaBase` binding (lines ~204–222) with `dmsBase` as in §3.5,
   comment updated.
3. `roles.desktop.baseModules` (line ~242): `… ++ dmsBase`.

*Verify:* `nix flake show --impure` still lists exactly 30 `nixosConfigurations`;
`nix flake metadata` shows `dms` resolving with `follows` applied and no
`noctalia*` nodes.

### Step 2 — `home/dank-material-shell.nix` (new), delete `home/noctalia.nix`

Create the file from §3.2. Delete `home/noctalia.nix`.

*Verify:* `nix eval --impure ".#nixosConfigurations.vexos-desktop-vm.config.home-manager.users.<user>.systemd.user.services.dms"` resolves.

### Step 3 — `home-desktop.nix`

Swap the import: `./home/noctalia.nix` → `./home/dank-material-shell.nix`
(comment unchanged in meaning).

### Step 4 — `modules/hyprland-desktop.nix`

1. Header: rewrite the top comment block — DMS shell + DMS greeter running
   Hyprland; layer split now "flake = one `dms` input, no overlays".
2. Greeter block: replace `programs.noctalia-greeter = { enable; package; }`
   with:
   ```nix
   programs.dank-material-shell.greeter = {
     enable            = true;
     compositor.name   = "hyprland";
     quickshell.package = pkgs.quickshell;
   };
   ```
3. `environment.systemPackages`: add `cliphist`. Update the comment that says
   "Noctalia v5 already provides…" to "DankMaterialShell provides…" with the
   §3.6 list; keep the "therefore NOT installed" waybar/fuzzel/etc. note.
4. Add the seeded-config activation (or place it in `home/dank-material-shell.nix`
   — see Step 5; decide during implementation based on which layer already has
   the user's `$HOME`. HM `home.activation` is the cleaner home).
5. If Phase 3 finds the greeter needs it: `services.accounts-daemon.enable = true`.

*Verify:* `nix eval` on the Hyprland branch — `services.greetd.enable` → `true`
(set by the greeter module), `programs.dank-material-shell.greeter.enable` →
`true`, `services.gnome.gnome-keyring.enable` → `true`.

### Step 5 — `files/hypr/hyprland.conf` (new) + seeder

Add the file from §3.4. Add the seeder to `home/dank-material-shell.nix`:

```nix
home.activation.seedHyprlandConf = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
  target="$HOME/.config/hypr/hyprland.conf"
  if [ ! -e "$target" ]; then
    run mkdir -p "$HOME/.config/hypr"
    run cp ${./../files/hypr/hyprland.conf} "$target"
    run chmod u+w "$target"
  fi
'';
```

*Verify:* on a machine with no `~/.config/hypr/hyprland.conf`, activation creates
it writable; on one that already has the file, activation is a no-op (diff the
file before/after).

### Step 6 — Correct stale references

- `modules/branding-display.nix:37` — comment "Hyprland uses noctalia-greeter"
  → "Hyprland uses the DankMaterialShell greeter"; the "neither reads GDM's
  dconf" point still holds.
- `modules/desktop-common.nix:8,14` — greeter list mentions; update the
  Hyprland line.
- `scripts/install.sh:441,448` — "Hyprland — Tiling Wayland compositor +
  Noctalia shell" → "+ DankMaterialShell".
- `justfile:311` — same string.
- `modules/hyprland-desktop.nix` header + inline comments (Step 4).

*Verify:* `grep -rn "noctalia\|Noctalia" --include=*.nix --include=*.sh .` and
`grep -n -i noctalia justfile` return nothing outside `.github/docs/`.

### Step 7 — `modules/gpu/vm.nix`

`needsRenderNode = config.programs.hyprland.enable || …` and
`before = [ "greetd.service" ]` (line ~89) **stay correct** — DMS greeter is a
greetd greeter and Hyprland is still the compositor. No change. (Listed so the
reviewer confirms it, not to edit it.)

### Step 8 — Build validation (WSL, Nix 2.34)

- `nix flake show --impure` → 30 configs, no eval errors.
- `nix eval --impure ".#nixosConfigurations.vexos-desktop-vm.config.system.build.toplevel.drvPath"` — full eval of the Hyprland branch.
- Same for `vexos-desktop-amd` and `vexos-desktop-nvidia`.
- **Build the shell package** to settle the `follows` question:
  `nix build --impure ".#nixosConfigurations.vexos-desktop-vm.config.home-manager.users.<user>.programs.dank-material-shell.package"` (or `.#dms` via the input). Cheap relative to finding it broken on the target.
- `git ls-files hardware-configuration.nix` → empty.
- `system.stateVersion` unchanged in every `configuration-*.nix`.
- `bash scripts/preflight.sh` → exit 0.

## 5. Dependencies

One new flake input, replacing two:

| Input | Repo | Branch | Provides |
|---|---|---|---|
| `dms` | `AvengeMedia/DankMaterialShell` | `stable` | `packages.{dms-shell,default}`, `homeModules.{dank-material-shell,niri}`, `nixosModules.{dank-material-shell,greeter}`, `lib` |

Removed inputs: `noctalia`, `noctalia-greeter`.

From nixpkgs 26.05 (all verified present via the nixos MCP): `quickshell` 0.3.0,
`dgop` 0.2.2, `matugen` 4.0.0, `cava`, `khal`, `cliphist`, plus `material-symbols`
/ `inter` fonts if not already in `fonts.packages`.

Context7 not used: the authoritative interface for a Nix flake input is its own
`distro/nix/*.nix` modules, which were read directly from the `stable` branch
(`flake.nix`, `home.nix`, `options.nix`, `nixos.nix`, `greeter.nix`, `common.nix`).

## 6. Configuration changes

- `vexos.desktop.environment = "hyprland"` keeps its meaning. No new `vexos.*`
  option.
- `system.stateVersion` untouched.
- `flake.lock` changes (input swap) — user runs `nix flake lock` / it is
  regenerated; noted in Phase 7.
- New user-facing file after first boot: `~/.config/hypr/hyprland.conf` (seeded
  once, then user-owned).

## 7. Risks and mitigations

| Risk | Mitigation |
|---|---|
| **DMS never booted here before.** | User confirms Noctalia+Hyprland boots now, so the compositor/UWSM/greetd path is proven. DMS is a Quickshell app on top of that proven path; the old failure predates DMS's rewrite. If the DMS shell fails to start, the symptom is a bare Hyprland with the seeded keybinds still working (terminal via `$mod+Return`) — recoverable, not a lockout. |
| **`follows = "nixpkgs"` (26.05) may not build DMS** — upstream targets unstable. | Settled empirically in Step 8 by building `dms-shell`. Fallback: `inputs.nixpkgs.follows = "nixpkgs-unstable"` (existing repo precedent — `vexboard` does this) and/or `quickshell.package = pkgs.unstable.quickshell`. Prefer `nixpkgs` first to avoid a mixed-Mesa closure. |
| **Greeter runs Hyprland itself** — if Hyprland ever fails at the greeter stage, there is no login screen at all (unlike `noctalia-greeter`'s independent wlroots compositor). | Hyprland boot is confirmed working. `services.greetd` still has the `initial_session` autologin path available as a manual recovery lever. A TTY login remains reachable (`Ctrl+Alt+F2`). |
| **Tracking `stable` still auto-updates via the daily job.** | Lower churn than `main` (user's choice). Mitigation if it bites: pin to a tag (`…/DankMaterialShell/v<x.y.z>`), one-line change. |
| **Seeded `hyprland.conf` drift** — user edits it, then a future VexOS change wants new defaults in it. | Seeder is explicitly one-shot (`[ ! -e ]`). Future default changes are communicated in release notes, not force-written. Acceptable per the "user owns their compositor config" principle. |
| **Material Symbols font missing** → DMS bar shows tofu. | Step in §3.6 / Phase 2 adds `material-symbols` + `inter` to `fonts.packages` if absent. |
| **`dgop`/`khal`/`matugen` version skew** vs what DMS `stable` expects. | 26.05 versions are recent (dgop 0.2.2 vs 0.2.3 unstable; matugen 4.0.0 vs 4.2.0). If a widget errors at runtime, bump the individual package to `pkgs.unstable.<name>` — the repo's unstable overlay exists for exactly this. |
| **`services.greetd` double-definition** if anything else sets it. | Only the greeter module sets it (`mkDefault`); the old repo had no in-repo `services.greetd` block. Verified by eval in Step 4. |
| **`accounts-daemon`** — `noctalia-greeter` enabled it; DMS greeter may not. | Phase 3 check; add `services.accounts-daemon.enable = true` if the greeter needs the user list. |
| Switching a live host between shells. | `just switch` already forces any DE change through `nixos-rebuild boot` + reboot (`justfile`), never a live display-manager swap. |

## 8. Deliberately out of scope

- **DMS `settings` / `clipboardSettings` / `session` / `plugins` / theming.** The
  HM module exposes all of them; left unset — stock shell. This is the
  "customise like GNOME" follow-up phase.
- **Full `hyprland.conf`** — only a minimal DMS-usable seed. Window rules,
  animations, decoration, per-monitor layout, extended keybinds are the
  customisation phase. The seed is user-editable from first boot.
- **`configHome` theme sync** between the greeter and a user's DMS settings.
- **`dms-greeter` on non-Hyprland roles** — desktop role only.
- **Renaming `vexos.gnome.flatpakInstall`** to a DE-neutral namespace (carried
  over from the Noctalia spec as tech debt).
- **`home/dank-material-shell.nix` for GNOME/COSMIC** — the file is imported
  unconditionally but its `config` is `mkIf`-gated, identical to how
  `home/noctalia.nix` worked.
