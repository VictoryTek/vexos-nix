> **SUPERSEDED — do not implement.** This spec proposed SDDM + sddm-astronaut as the
> greeter. The user subsequently chose the Noctalia family (v5) instead. The live spec is
> `hyprland_noctalia_session_spec.md`. Retained only for the research it records (GNOME
> capability mapping, the dead `WLR_RENDERER_ALLOW_SOFTWARE` finding, portal redundancy).

# Hyprland: traditional stock session + SDDM greeter — Specification

## 1. Current state analysis

`vexos.desktop.environment = "hyprland"` currently produces an **Omarchy clone**,
built by commits `6ab1ae2` → `7fbb03d` → `24894c3` → `3b82278`:

| Concern | Current implementation | Source |
|---|---|---|
| Compositor | `programs.hyprland` + UWSM | `modules/hyprland-desktop.nix` |
| Shell / bar | `programs.dms-shell` (DankMaterialShell, Quickshell) | same |
| Greeter | **none** — greetd `initial_session` autologin | same |
| Wallpaper | shell-script seeder writing `~/.config/hypr/hyprpaper.conf` | same |
| Session apps | none — no launcher, no notifications, no polkit agent, no keyring | — |

The compositor is deliberately unconfigured (`hyprland.conf` is left to
Hyprland's own first-run autogeneration), but `hyprpaper` is installed with no
process to launch it, so the wallpaper seeder is inert.

### What Hyprland does *not* inherit from the GNOME role

`configuration-desktop.nix` imports `modules/gnome.nix` unconditionally but its
`config` is gated on `isGnome`. Everything GNOME supplies *implicitly* — via
`services.desktopManager.gnome.enable` — is therefore absent under Hyprland:

file manager, application launcher, status bar, notification daemon, screen
lock, idle handling, screenshot UI, polkit authentication agent, GNOME Keyring
(Secret Service), gvfs, udisks2 automount, network/bluetooth applets, audio and
display control panels, GTK settings, and the GNOME default-app Flatpaks
(`vexos.gnome.flatpakInstall.apps`, set inside `lib.mkIf isGnome` in
`modules/gnome-desktop.nix`).

Ghostty is the exception — it is installed from `home-desktop.nix`
(`home.packages`), which is DE-agnostic, so the terminal is already present.
GTK theming, icon theme and cursor likewise already carry over from
`home/gnome-common.nix`, which `home-desktop.nix` imports unconditionally.

## 2. Problem definition

Two requirements, from the user:

1. **Replace the Omarchy/Quickshell arrangement with a traditional Hyprland
   setup**: stock, unconfigured Hyprland behind a real graphical greeter.
   Customisation is explicitly deferred to a later phase, the way the GNOME
   role was built up.
2. **Feature parity with the GNOME desktop role.** Anything available on GNOME
   must be available on Hyprland; where the GNOME implementation is
   GNOME-only, install the Hyprland-ecosystem equivalent.

Blocking symptom: `vexos-desktop-vm` has never successfully booted into
Hyprland, so none of this has been testable.

### On the VM black screen — correcting a wrong assumption in this repo

`modules/gpu/vm.nix` and `modules/gpu/vm-guest-additions.nix` currently attribute
the black screen to a missing DRM render node (`/dev/dri/renderD128`) on
Proxmox's default bochs-drm display device.

**The user reports that Omarchy and CachyOS Hyprland both boot correctly in the
same Proxmox VM environment.** That falsifies "the hypervisor cannot run
Hyprland" as a general claim and relocates the fault to this repository's
configuration. This spec therefore does **not** treat the render node as the
root cause, and does not design around it.

Two concrete, checkable differences between this repo's VM build and those
distros, recorded here as leads rather than as changes:

- **Kernel.** `modules/gpu/vm-guest-additions.nix:73` sets
  `boot.kernelPackages = lib.mkForce pkgs.linuxPackages_6_18`, overriding the
  desktop role's `linuxPackages_latest` (7.x) from
  `modules/system-latest-kernel.nix`. That same file records that a comparison
  VM on **kernel 7.1.9 worked** on the same Proxmox display setting, while 6.12
  did not; 6.18 was picked as an untested midpoint. Omarchy and CachyOS both
  ship current (7.x) kernels. This is the single largest unverified difference.
- **Dead environment variable.** The current module sets
  `WLR_RENDERER_ALLOW_SOFTWARE = "1"`. That is a **wlroots** variable. Our pin
  is `hyprland 0.55.4`, which uses **Aquamarine**, not wlroots — wlroots was
  dropped in 0.42. The variable has no effect and its presence has been
  misleading the diagnosis.

Both are addressed below (the second by deletion; the first as a documented
follow-up, since changing the VM kernel pin is a separate, deliberate decision
made in commit `32c1c31` and is out of scope for this change).

## 3. Proposed solution architecture

### 3.1 Greeter: SDDM with the `sddm-astronaut` theme

Chosen over greetd+tuigreet (text-mode) and greetd+ReGreet (plain GTK4) on the
user's stated criteria — nice, modern, polished, customisable:

- SDDM themes are **QML/Qt6 applications**, not stylesheets, so "customisable"
  means arbitrary UI, not colour tweaks. It is the most themeable greeter in
  the Linux ecosystem by a wide margin.
- `sddm-astronaut` (`0-unstable-2026-05-12`) is present in our nixpkgs 26.05
  pin. It is the modern blurred-background theme with multiple embedded
  variants, selectable via the package's `embeddedTheme` override argument.
- It is also what CachyOS ships for its Hyprland edition, so it is a
  well-travelled pairing rather than a novel one.

**X11 backend** (`wayland.enable = false`, the NixOS default). Rationale is
reliability and breadth of testing, not the render-node theory: SDDM's Wayland
mode is still marked *experimental* upstream and requires pulling in a whole
second compositor (kwin or weston) purely to draw a login box. The session SDDM
launches is still Wayland — only the greeter is X11. Flipping to
`wayland.enable = true` later is a one-line change.

Autologin is deliberately **not** configured for Hyprland; a greeter is the
point of this change. `services.displayManager.autoLogin` remains set only in
`modules/gnome.nix` (GDM) and `modules/cosmic-desktop.nix` (cosmic-greeter).

### 3.2 Session model: keep UWSM, drop greetd

`programs.hyprland.withUWSM = true` and the
`programs.uwsm.waylandCompositors.hyprland` registration from commit `24894c3`
are **retained**. That registration was a genuine bug fix, and UWSM is what
starts `graphical-session.target` — without it, every systemd user service in
this design (waybar, swaync, hyprpaper, cliphist, udiskie, polkit agent) would
never start, because plain Hyprland launched from a display manager does not
activate that target.

`services.greetd` is removed entirely — SDDM replaces it, and the module's own
comments note that greetd declares `aliases = [ "display-manager.service" ]`
with no assertion guarding a second display manager claiming the same alias.

SDDM will list two Hyprland entries (`hyprland.desktop` from
`services.displayManager.sessionPackages`, and `hyprland-uwsm.desktop` from the
UWSM registration). This is expected; **the UWSM entry is the one to select**,
and SDDM remembers the last choice. Documented in the module header.

### 3.3 Hyprland configuration: none

No `hyprland.conf` is written, managed, or seeded. Hyprland autogenerates its
own default at `~/.config/hypr/hyprland.conf` on first launch, per
`programs.hyprland.enable`'s own option description. This is the "default form"
the user asked for and the thing later customisation will build on.

Consequence, stated plainly: **the session daemons cannot be started from
`exec-once`**, because that would require managing the config file. They are
started as **systemd user services bound to `graphical-session.target`**
instead. This is strictly better here — it survives Hyprland regenerating or
the user rewriting `hyprland.conf`, and every one of these daemons already has
a first-class Home Manager module that does exactly this.

### 3.4 GNOME → Hyprland capability mapping

| GNOME capability | Hyprland equivalent | Layer |
|---|---|---|
| Nautilus file manager | `nautilus` + `gvfs` + `udisks2` | system |
| Terminal | `ghostty` — already present, DE-agnostic | home (existing) |
| Shell app launcher | `fuzzel` | system |
| Top bar / panel | `waybar` (`programs.waybar.systemd.enable`) | home |
| Notifications | `swaynotificationcenter` (`services.swaync`) — has a GUI control centre, closest analogue to GNOME's | home |
| Screen lock | `programs.hyprlock.enable` (wires PAM) | system |
| Idle / auto-lock | `services.hypridle.enable` | system |
| Wallpaper | `services.hyprpaper` pointed at the existing `vexos-wallpapers` store path | home |
| Screenshot UI | `hyprshot` + `grim` + `slurp` | system |
| Colour picker | `hyprpicker` | system |
| Polkit auth agent | `services.hyprpolkitagent` | home |
| Keyring / Secret Service | `services.gnome.gnome-keyring.enable` + `programs.seahorse.enable` + `security.pam.services.sddm.enableGnomeKeyring` | system |
| Removable-media automount | `services.udiskie` (+ system `udisks2`) | home + system |
| Network applet | `services.network-manager-applet` | home |
| Bluetooth applet | `services.blueman` — already in `desktop-common.nix` | system (existing) |
| Audio control panel | `pavucontrol` | system |
| Display arrangement | `nwg-displays` | system |
| GTK theme/font/cursor settings | `nwg-look` (+ `programs.dconf.enable`) | system |
| Clipboard history | `cliphist` + `wl-clipboard` (`services.cliphist`) | home |
| Brightness / media keys | `brightnessctl` + `playerctl` (binds deferred — see §7) | system |
| XDG portal | `xdg-desktop-portal-hyprland` (auto, from `programs.hyprland`) + `xdg-desktop-portal-gtk` for GTK file chooser & settings | system |
| Archive manager | `file-roller` | system |
| Disks / System Monitor / Baobab / Font Viewer / Logs | same GNOME apps — they run fine outside GNOME Shell | system |
| Default-app Flatpaks (TextEditor, Loupe, Calculator, Calendar, Papers, Snapshot) | identical Flatpaks via `vexos.gnome.flatpakInstall.apps` | system |

## 4. Implementation steps

Module Architecture Pattern note: `modules/hyprland-desktop.nix` keeps its
existing `lib.mkIf (config.vexos.desktop.environment == "hyprland")` guard. Per
CLAUDE.md's carve-out this is the standard toggleable-subsystem pattern — the
option is declared by `modules/desktop-environment.nix`, which is part of this
same DE module family — and it is the established shape of all three DE modules
(`gnome.nix`, `cosmic-desktop.nix`, `hyprland-desktop.nix`). No new role-gating
`mkIf` is introduced into any shared module.

### Step 1 — Rewrite `modules/hyprland-desktop.nix` (system layer)

**Remove:** `programs.dms-shell.enable`, the entire `services.greetd` block, the
`environment.sessionVariables.WLR_RENDERER_ALLOW_SOFTWARE` line (dead — see
§2), the redundant `xdg.portal.extraPortals = [ xdg-desktop-portal-hyprland ]`
(nixpkgs' `programs/wayland/hyprland.nix` already sets
`xdg.portal.extraPortals = [ cfg.portalPackage ]`), and the
`vexos-hyprland-wallpaper` systemd unit and its stamp-file script.

**Keep:** `programs.hyprland` (enable / xwayland / withUWSM) and
`programs.uwsm.waylandCompositors.hyprland`.

**Add:** the SDDM greeter block, the implicit-GNOME services, the portal
addition, the package set, and the Flatpak parity line.

*Verify:* `nix flake show --impure` lists all 30 outputs unchanged;
`nix eval --impure '.#nixosConfigurations.vexos-desktop-vm.config.services.displayManager.sddm.enable'` → `true`;
`…config.services.greetd.enable` → `false`.

Key details fixed at spec time against the nixpkgs 26.05 pin:

- SDDM resolves themes from `/run/current-system/sw/share/sddm/themes`, so
  `pkgs.sddm-astronaut` must go in **`environment.systemPackages`**, while
  `services.displayManager.sddm.extraPackages` takes only the Qt6 runtime deps
  the theme needs: `kdePackages.qtsvg`, `kdePackages.qtmultimedia`,
  `kdePackages.qtvirtualkeyboard` (the three listed in the package's own
  runtime inputs).
- `services.displayManager.sddm.theme = "sddm-astronaut-theme"` — the directory
  name the package installs, not the package name.
- `Theme.CursorTheme = "Bibata-Modern-Classic"` for continuity with
  `home/gnome-common.nix`; `pkgs.bibata-cursors` must be in
  `environment.systemPackages` for the greeter (which runs before any user
  session) to resolve it.

### Step 2 — Add `home/hyprland-common.nix` (user session layer)

New Home Manager sub-module, following the shape of `home/gnome-common.nix`.
Guarded internally on `osConfig.vexos.desktop.environment == "hyprland"`, so it
can be imported unconditionally.

Structure — must be `{ config = lib.mkIf cond { … }; }`; a bare top-level
`lib.mkIf` is not a valid module:

```nix
{ pkgs, lib, osConfig, ... }:
{
  config = lib.mkIf (osConfig.vexos.desktop.environment == "hyprland") {
    programs.waybar = { enable = true; systemd.enable = true; };
    services.swaync.enable                = true;
    services.hyprpolkitagent.enable       = true;
    services.cliphist.enable              = true;
    services.network-manager-applet.enable = true;
    services.udiskie = { enable = true; automount = true; tray = "auto"; };
    services.hyprpaper = { … };
  };
}
```

All of these default `systemdTarget` / `systemdTargets` to
`graphical-session.target`, which UWSM activates.

`services.hyprpaper.settings` points `preload` and `wallpaper` at
`/run/current-system/sw/share/backgrounds/vexos/vex-bb-dark.jxl` — the same
stable store path `modules/branding-display.nix` already builds, replacing the
removed shell-script seeder with a declarative equivalent.

*Verify:* `nix eval --impure` on
`…config.home-manager.users.<user>.systemd.user.services.waybar` resolves.

### Step 3 — Import it from `home-desktop.nix`

Add `./home/hyprland-common.nix` to the existing `imports` list.

### Step 4 — Correct now-stale references caused by this change

- `modules/branding-display.nix:37` — comment says "Hyprland uses dms-greeter".
  Change to SDDM. One comment line; it becomes factually wrong *because of*
  this change, so it is in scope.
- `justfile:221` and `scripts/install.sh:356,363` — the DE picker describes
  hyprland as "Tiling Wayland compositor + Quickshell shell". Quickshell is
  being removed; update the wording.

*Verify:* `grep -rn "dms-greeter\|dms-shell\|Quickshell" --include=*.nix --include=justfile scripts/ modules/ *.nix` returns nothing outside `.github/docs/`.

### Step 5 — Phase 3 build validation

`nix flake show --impure`, then `sudo nixos-rebuild dry-build` for
`vexos-desktop-amd`, `vexos-desktop-nvidia`, `vexos-desktop-vm`. Note that
`dry-build` exercises the **default** `vexos.desktop.environment = "gnome"`
path; the Hyprland branch must additionally be forced via `nix eval --impure`
with the option overridden, or the change is untested at eval time.

## 5. Dependencies

**No new flake inputs.** Every package and option below is in the existing
`nixpkgs` 26.05 pin (`inputs.nixpkgs`) or `home-manager` `release-26.05`.
Context7 is therefore not required for this change — the Dependency Policy
exempts "projects where all dependencies are managed by a lock file with no new
additions". Verified live against the 26.05 channel index:

| Name | Version / kind |
|---|---|
| `hyprland` | 0.55.4 (pkg) |
| `sddm-astronaut` | 0-unstable-2026-05-12 (pkg) |
| `waybar` | 0.15.0 (pkg) |
| `fuzzel` | 1.14.1 (pkg) |
| `swaynotificationcenter` | 0.12.6 (pkg) |
| `hyprpaper` / `hyprlock` / `hypridle` | 0.8.4 / 0.9.5 / 0.1.7 (pkg) |
| `hyprshot` / `hyprpicker` / `hyprpolkitagent` | 1.3.0 / 0.4.7 / 0.1.3 (pkg) |
| `cliphist` / `nwg-look` | 0.7.0 / 1.1.1 (pkg) |
| `programs.hyprlock.enable`, `services.hypridle.enable` | NixOS option |
| `services.displayManager.sddm.*` | NixOS option |
| `services.gnome.gnome-keyring.enable`, `programs.seahorse.enable`, `services.gvfs.enable`, `services.udisks2.enable` | NixOS option |
| `programs.waybar.systemd.enable`, `services.swaync.*`, `services.hyprpaper.*`, `services.hyprpolkitagent.*`, `services.cliphist.*`, `services.udiskie.*` | Home Manager option |

## 6. Configuration changes

None to `/etc/nixos/features.nix` semantics — `vexos.desktop.environment =
"hyprland"` keeps its meaning. `system.stateVersion` is untouched in every
`configuration-*.nix`. No new flake input, so no `follows` declaration is
needed.

## 7. Deliberately out of scope

Named explicitly so the boundary is the user's to move, not silently drawn:

- **Keybinds.** Everything bound to a key under GNOME (the `<Super>backslash`
  mic-mute toggle in `modules/gnome-desktop.nix`, volume/brightness/media keys,
  screenshot shortcuts, launcher hotkey) requires a managed `hyprland.conf`,
  which §3.3 deliberately avoids. `brightnessctl`, `playerctl`, `hyprshot` and
  `fuzzel` are installed and ready; wiring keys to them belongs to the
  customisation phase. Hyprland's own default config already binds
  `SUPER+Q` / `SUPER+R` / `SUPER+E`.
- **`mute-mic-on-login`.** The GNOME role mutes the microphone at every session
  start. It is a personal tweak from the GNOME customisation layer rather than
  a capability, so it is grouped with the keybinds above. Trivially added later
  by extracting the existing unit into a shared module.
- **VexOS branding on the SDDM greeter.** `sddm-astronaut` accepts a
  `themeConfig` override for the background, but the repo's wallpapers are
  `.jxl`, which Qt6 will not load. Needs a PNG/JPEG variant first.
- **The VM kernel pin.** See §2. Reverting
  `modules/gpu/vm-guest-additions.nix:73` from `linuxPackages_6_18` to the
  desktop role's `linuxPackages_latest` is the top suspect for the VM black
  screen, but it was a deliberate decision in commit `32c1c31` made for
  VirtualBox Guest Additions reasons, and undoing it is a separate change with
  its own risk surface.

## 8. Risks and mitigations

| Risk | Mitigation |
|---|---|
| **The VM still black-screens.** This change removes several failure modes but is not a proven fix; the root cause remains unconfirmed. | SDDM's X11 greeter is itself the diagnostic: if the login screen renders, the display stack is healthy and the fault is isolated to the compositor, which is exactly the information the previous four attempts never produced. If the greeter also fails, §7's kernel pin is the next lever. |
| Two Hyprland entries in the SDDM session list; picking the non-UWSM one silently breaks every session daemon. | Documented in the module header. If it proves confusing in practice, drop `withUWSM` and start `graphical-session.target` explicitly instead — a contained follow-up. |
| `hyprpaper` may not decode `.jxl`. JXL support comes via `hyprgraphics`; not verified on this pin. | Fails soft — no wallpaper, session still usable. Confirm on first boot; converting the wallpaper to PNG is the fallback. |
| Home Manager option names verified against the MCP index, which tracks master rather than `release-26.05`. | All six modules used are long-standing and stable. Any drift surfaces immediately as an eval error in Phase 3 dry-build, not at runtime. |
| GNOME apps (`nautilus`, `file-roller`, …) outside GNOME Shell can miss GSettings schemas or icons. | `gsettings-desktop-schemas` and `adwaita-icon-theme` included in the system package set; `programs.dconf.enable = true`. |
| Removing `services.greetd` while a host is running it. | `just switch` already forces any DE change through `nixos-rebuild boot` + reboot (`justfile:281`), never a live display-manager swap. |
