# Hyprland + Noctalia v5 shell and greeter — Specification

Supersedes `hyprland_traditional_session_spec.md` (SDDM design, rejected).

## 1. Current state analysis

`vexos.desktop.environment = "hyprland"` currently produces an Omarchy clone
(`modules/hyprland-desktop.nix`, commits `6ab1ae2` → `3b82278`):

| Concern | Current | Fate |
|---|---|---|
| Compositor | `programs.hyprland` + UWSM | **kept** |
| Shell | `programs.dms-shell` (DankMaterialShell, Quickshell) | **removed** → Noctalia v5 |
| Greeter | none — greetd `initial_session` autologin | **removed** → `noctalia-greeter` |
| Wallpaper | shell-script seeder writing `hyprpaper.conf` | **removed** — Noctalia owns wallpaper |
| `WLR_RENDERER_ALLOW_SOFTWARE` | set | **removed** — dead code, see §2 |
| Session apps | none | **added** — see §4 |

`configuration-desktop.nix` imports `modules/gnome.nix` unconditionally but
gates its `config` on `isGnome`, so everything GNOME supplies implicitly is
absent under Hyprland: file manager, keyring/Secret Service, gvfs, udisks2
automount, polkit agent, portals beyond the Hyprland one, and the GNOME
default-app Flatpaks.

Ghostty (terminal) and GTK/icon/cursor theming already carry over — they come
from `home-desktop.nix` and `home/gnome-common.nix`, both DE-agnostic.

## 2. Two corrections carried forward from the prior investigation

**`WLR_RENDERER_ALLOW_SOFTWARE = "1"` is dead code.** It is a *wlroots*
variable. Our pin is `hyprland 0.55.4`, which uses **Aquamarine** — wlroots was
dropped in 0.42. It has never had any effect, and its presence has been
propping up a false diagnosis. Deleted.

**The render-node theory is not established.** `modules/gpu/vm.nix` asserts, in
both a comment and a user-facing Plymouth warning, that Proxmox's default
display device exposes no `/dev/dri/renderD128` and that this is why Hyprland
black-screens. The user reports Omarchy and CachyOS Hyprland both boot in the
same Proxmox environment, which contradicts the general claim. The warning is
retained (it is genuinely useful when a render node *is* missing) but its text
is corrected from "will fail to start" to a conditional phrasing, since we no
longer have evidence it is the cause here.

The `before = [ "greetd.service" ]` ordering in that unit **remains correct** —
`noctalia-greeter` is a greetd greeter, so greetd is still the display manager.

## 3. Proposed solution architecture

### 3.1 Compositor: Hyprland, unconfigured

Hyprland stays. Noctalia is a *shell*, not a compositor. No `hyprland.conf` is
written, managed, or seeded — Hyprland autogenerates its default at
`~/.config/hypr/hyprland.conf` on first launch. Customisation is explicitly a
later phase.

Umbriel (Noctalia's own compositor) was considered and rejected for now: it is
in early development, upstream warns that config keys, keybinds and behaviour
change between releases, and stacking it under a VM that has never booted a
Wayland session would put two moving betas in the critical path. Revisit as a
fourth `vexos.desktop.environment` value once this baseline boots.

### 3.2 UWSM is retained — and is load-bearing

`programs.hyprland.withUWSM = true` plus the
`programs.uwsm.waylandCompositors.hyprland` registration (the genuine fix from
commit `24894c3`) stay.

This is not incidental. UWSM is what activates `graphical-session.target`, and
Noctalia's Home Manager module binds its systemd user service to
`config.wayland.systemd.target` — which resolves to `graphical-session.target`.
Without UWSM, Hyprland launched from a display manager never activates that
target and **the shell would never start**, producing a bare compositor with no
bar, launcher or notifications.

greetd will list two sessions (`hyprland.desktop` and `hyprland-uwsm.desktop`).
**The UWSM entry is the one to select.** Documented in the module header.

### 3.3 Greeter: `noctalia-greeter`

Upstream's NixOS module (`nix/nixos-module.nix`, option path
`programs.noctalia-greeter`) does the wiring itself:

- sets `services.greetd` with
  `command = "${package}/bin/noctalia-greeter-session -- ${greeter-args}"`
- enables `services.accounts-daemon` (`mkDefault`)
- creates `/var/lib/noctalia-greeter`
- symlinks a generated `greeter.toml` when `settings` is set
- asserts the `greetd` user exists

`package` is a **required** option with no default, so it must be set
explicitly from the greeter flake's overlay.

The greeter runs inside its own bundled wlroots compositor
(`noctalia-greeter-session`), independent of Hyprland. Autologin is not
configured — a greeter is the point.

### 3.4 Shell: Noctalia v5 via the Home Manager module

Two modules exist upstream and they are **not interchangeable**:

| Module | Path | Provides |
|---|---|---|
| `nixosModules.default` | `programs.noctalia` | package in systemPackages, `hardware.graphics`, `recommendedServices` (NetworkManager/Bluetooth/UPower/power-profiles), optional systemd user service |
| `homeModules.default` | `programs.noctalia` | systemd user service bound to the Wayland target, **`settings`** (TOML), **`customPalettes`**, `checkConfig`, restart-triggers on config change |

**Use the Home Manager module only.** It is the one that carries `settings` and
`customPalettes` — the entire surface the later customisation phase will need —
and its service has restart triggers on config change. The NixOS module's
`recommendedServices` are all already enabled elsewhere in this repo
(NetworkManager in `modules/network.nix`, Bluetooth in
`modules/desktop-common.nix`, `hardware.graphics` in `modules/gpu.nix`), so
importing it would add nothing but a second definition of the same option path.

`settings` is left empty in this change — stock Noctalia, matching the
"get it booting, then customise" goal.

### 3.5 Flake input wiring

Neither package is in nixpkgs. No module in `modules/` or `home/` currently
takes `inputs`; the established pattern is to wire inputs in `flake.nix` via the
role table (`vexboardBase` at `flake.nix:172-178` is the exact precedent).
Followed here — the DE module stays pure and merely sets options.

```nix
# inputs
noctalia = {
  url = "github:noctalia-dev/noctalia";
  inputs.nixpkgs.follows = "nixpkgs";
};
noctalia-greeter = {
  url = "github:noctalia-dev/noctalia-greeter";
  inputs.nixpkgs.follows = "nixpkgs";
};

# alongside vexboardBase
noctaliaBase = [
  { nixpkgs.overlays = [
      inputs.noctalia.overlays.default
      inputs.noctalia-greeter.overlays.default
    ]; }
  inputs.noctalia-greeter.nixosModules.default
];
```

Added to the **desktop role only** (`roles.desktop.baseModules`). The greeter
module is inert until `programs.noctalia-greeter.enable` is set, which happens
only inside the `isHyprland` guard, so GNOME and COSMIC desktop hosts are
unaffected.

`inputs.nixpkgs.follows = "nixpkgs"` on both, per CLAUDE.md. Note both upstreams
declare `nixpkgs` as `channels.nixos.org/nixos-unstable`; `follows` overrides
that to our 26.05 pin. See §7 for the fallback if they fail to build against it.

**Both inputs track `main`** (user decision). The repo's daily
`chore: update flake inputs` job will therefore bump them automatically. §7
records the consequence.

The Home Manager module is imported in `home-desktop.nix`.
`mkHomeManagerModule` already passes `extraSpecialArgs = { inherit inputs; … }`
and `home-desktop.nix` already takes `inputs` in its argument set, so
`inputs.noctalia.homeModules.default` is directly importable with no plumbing
change.

### 3.6 What Noctalia replaces, and what still has to be added

Noctalia v5 provides: bars, widgets, dock, launcher, control center,
notifications, wallpaper, lock screen, session actions, clipboard history,
OSDs, tray integration, desktop widgets.

**Therefore NOT installed** (the prior SDDM spec's list, now redundant):
`waybar`, `fuzzel`, `swaynotificationcenter`, `hyprpaper`, `hyprlock`,
`cliphist`, `nm-applet`.

**Still required — Noctalia does not provide these:**

| Gap | Package / option | Note |
|---|---|---|
| Secret Service | `services.gnome.gnome-keyring.enable` + `programs.seahorse.enable` | **Hard dependency** — Noctalia v5's `BUILDING.md` lists a Secret Service provider as a runtime requirement |
| Polkit auth agent | `hyprpolkitagent` (HM `services.hyprpolkitagent`) | not part of Noctalia |
| File manager | `nautilus` + `services.gvfs` + `services.udisks2` | GNOME parity |
| Removable-media automount | HM `services.udiskie` | GNOME parity |
| Screenshot | `hyprshot`, `grim`, `slurp` | not listed in Noctalia's feature set |
| Colour picker | `hyprpicker` | |
| Display arrangement | `nwg-displays` | |
| GTK theme/font settings | `nwg-look` + `programs.dconf.enable` | |
| Audio detail panel | `pavucontrol` | Noctalia's control center covers volume, not per-app routing |
| XDG portal | `xdg-desktop-portal-gtk` | `xdg-desktop-portal-hyprland` is added automatically by `programs.hyprland` — verified in nixpkgs `programs/wayland/hyprland.nix`, which sets `xdg.portal.extraPortals = [ cfg.portalPackage ]`. Only the GTK backend needs adding, for file chooser and settings. |
| Noctalia optional integrations | `upower`, `ddcutil`, `brightnessctl`, `playerctl`, `wl-clipboard` | named in Noctalia's own runtime dependency list |
| GNOME apps | `file-roller`, `gnome-disk-utility`, `gnome-system-monitor`, `baobab`, `gnome-font-viewer`, `gnome-logs` | run fine outside GNOME Shell |
| GTK app support | `gsettings-desktop-schemas`, `adwaita-icon-theme` | schemas/icons GNOME would otherwise supply |
| Default-app Flatpaks | `vexos.gnome.flatpakInstall.apps` | see below |

**Flatpak parity.** `modules/gnome-flatpak-install.nix` declares
`vexos.gnome.flatpakInstall.{apps,extraRemoves}` and is imported via
`modules/gnome.nix`'s *import list*, which is unconditional — only `gnome.nix`'s
`config` is gated. The service activates on
`services.flatpak.enable && apps != []`, with no GNOME gate. So
`modules/hyprland-desktop.nix` can set the same option to get the identical app
set (TextEditor, Loupe, Calculator, Calendar, Papers, Snapshot). The
`vexos.gnome.*` namespace is historically misnamed for this use; renaming it
would touch four `gnome-*.nix` files and is out of scope. Recorded as tech debt.

## 4. Implementation steps

Module Architecture Pattern: `modules/hyprland-desktop.nix` keeps its
`lib.mkIf (config.vexos.desktop.environment == "hyprland")` guard. Per CLAUDE.md's
carve-out this is a toggleable subsystem gated on an option its own module
family declares (`modules/desktop-environment.nix`), and it is the established
shape of all three DE modules. No new role-gating `mkIf` enters a shared module.

### Step 1 — `flake.nix`

Add the two inputs and the `noctaliaBase` list; append it to
`roles.desktop.baseModules`.

*Verify:* `nix flake show --impure` still lists exactly 30 `nixosConfigurations`;
`nix flake metadata` shows both new inputs resolving with `follows` applied.

### Step 2 — Rewrite `modules/hyprland-desktop.nix`

Remove `programs.dms-shell`, the `services.greetd` block, the
`WLR_RENDERER_ALLOW_SOFTWARE` line, the redundant
`xdg.portal.extraPortals = [ xdg-desktop-portal-hyprland ]`, and the
`vexos-hyprland-wallpaper` unit with its stamp-file script.

Keep `programs.hyprland` and `programs.uwsm.waylandCompositors.hyprland`.

Add: `programs.noctalia-greeter.{enable, package}`, the §3.6 services and
package set, `xdg.portal.extraPortals = [ pkgs.xdg-desktop-portal-gtk ]` with
`xdg.portal.config.common.default = [ "hyprland" "gtk" ]`, and the
`vexos.gnome.flatpakInstall.apps` parity line.

*Verify:* `nix eval` on the Hyprland branch — `services.greetd.enable` → `true`
(now set by the greeter module, not by us), `programs.noctalia-greeter.enable`
→ `true`, `services.gnome.gnome-keyring.enable` → `true`.

### Step 3 — Add `home/noctalia.nix`

New Home Manager sub-module in the shape of `home/gnome-common.nix`, guarded
internally so it can be imported unconditionally. Must be
`{ config = lib.mkIf cond { … }; }` — a bare top-level `lib.mkIf` is not a valid
module.

```nix
{ pkgs, lib, inputs, osConfig, ... }:
{
  imports = [ inputs.noctalia.homeModules.default ];
  config = lib.mkIf (osConfig.vexos.desktop.environment == "hyprland") {
    programs.noctalia = {
      enable         = true;
      systemd.enable = true;
      package        = pkgs.noctalia;
      # settings intentionally empty — stock shell, customisation is a later phase
    };
    services.hyprpolkitagent.enable = true;
    services.udiskie = { enable = true; automount = true; tray = "auto"; };
  };
}
```

The `imports` line sits **outside** the `mkIf` — imports are resolved before
option values exist and cannot be conditional. The upstream module is inert
until `programs.noctalia.enable` is set.

*Verify:* `nix eval` resolves
`…home-manager.users.<user>.systemd.user.services.noctalia`.

### Step 4 — `home-desktop.nix`

Add `./home/noctalia.nix` to the `imports` list.

### Step 5 — Correct references this change invalidates

- `modules/branding-display.nix:37` — comment says "Hyprland uses dms-greeter".
- `justfile:221` and `scripts/install.sh:356,363` — DE picker text says
  "Tiling Wayland compositor + Quickshell shell". Both the greeter and Quickshell
  are gone; `noctalia-qs` is archived upstream.
- `modules/gpu/vm.nix` — soften the render-node warning per §2. Behaviour
  unchanged; text only.

*Verify:* `grep -rn "dms-greeter\|dms-shell\|Quickshell"` returns nothing outside
`.github/docs/`.

### Step 6 — Build validation

Beyond evaluation, **actually build the two new packages** in WSL:
`nix build .#nixosConfigurations.vexos-desktop-vm.pkgs.noctalia` and the
greeter. This is the only way to settle §7's `follows` question, and it is
cheap relative to discovering it on the target host.

## 5. Dependencies

Two new flake inputs, both tracking `main`, neither in nixpkgs:

| Input | Repo | Provides |
|---|---|---|
| `noctalia` | `noctalia-dev/noctalia` | `packages.default`, `overlays.default`, `homeModules.default`, `nixosModules.default`, `hjemModules.default` |
| `noctalia-greeter` | `noctalia-dev/noctalia-greeter` | `packages.default`, `overlays.default`, `nixosModules.default` |

Upstream version at spec time: **v5.0.0-beta.9**, released 2026-08-20.
`noctalia-qs` (the v4 Quickshell toolkit) is **archived** upstream, confirming
v5 has no Qt/Quickshell dependency: it is C++23 + Meson rendering directly to
Wayland + OpenGL ES.

Everything else comes from the existing nixpkgs 26.05 pin. Context7 was not
used: it resolves library *documentation*, and these are Nix flake inputs whose
authoritative interface is their own `nix/` modules, which were read directly.

## 6. Configuration changes

No change to `/etc/nixos/features.nix` semantics —
`vexos.desktop.environment = "hyprland"` keeps its meaning. `system.stateVersion`
untouched. `vexos.vm.platform` (previous change) untouched.

## 7. Risks and mitigations

| Risk | Mitigation |
|---|---|
| **`follows = "nixpkgs"` (26.05) may not build** — both upstreams target nixos-unstable. | Settled empirically in Step 6 by building both packages, not by assumption. If it fails, the documented fallback is `follows = "nixpkgs-unstable"`, which is the existing precedent in this repo (`vexboard` does exactly this) and satisfies CLAUDE.md's rule. Preferring `nixpkgs` first avoids a mixed-Mesa/libglvnd closure. |
| **Tracking `main` on beta software.** The daily flake-update job can land an upstream change on the login screen or shell with no review. | User's explicit decision, made with this tradeoff stated. Mitigation if it bites: pin to a release tag (`…/noctalia/v5.0.0-beta.9`), a one-line change. Worth noting the greeter failing is a *login* failure, not just a cosmetic one. |
| **If UWSM is bypassed the shell silently never starts.** greetd offers both session entries. | §3.2; documented in the module header. Symptom is a bare Hyprland with no bar — distinctive and easy to recognise. |
| **The VM may still black-screen.** Root cause remains unconfirmed; this change does not claim to fix it. | The previous commit's kernel change (`desktop-vm` 6.18 → 7.2) is the leading lever and should be tested first/simultaneously. The greeter is also diagnostic: it runs in its own wlroots compositor, so "greeter renders but Hyprland doesn't" isolates the fault to Hyprland, while "neither renders" points at the display stack. |
| Noctalia may ship its own idle daemon, conflicting with `hypridle`. | `hypridle` deliberately **not** installed. Noctalia advertises lock screen and session actions; adding a second idle manager risks double-locking. Revisit if idle-to-lock does not work. |
| `services.greetd` set by the upstream greeter module rather than by us — an option-priority collision if anything else sets it. | The old in-repo `services.greetd` block is removed in the same change, so there is exactly one definition. Verified by eval in Step 2. |
| GNOME apps outside GNOME Shell miss schemas/icons. | `gsettings-desktop-schemas`, `adwaita-icon-theme`, `programs.dconf.enable` included. |
| Switching a live host between DEs. | `just switch` already forces any DE change through `nixos-rebuild boot` + reboot (`justfile:281`), never a live display-manager swap. |

## 8. Deliberately out of scope

- **Keybinds and `hyprland.conf`.** Stock Hyprland config by design (§3.1).
  Screenshot/media/brightness tools are installed and ready; binding them is the
  customisation phase.
- **Noctalia `settings` / `customPalettes` / plugins.** The HM module exposes
  all three; left empty deliberately. This is where the "customise like GNOME"
  work will happen.
- **Umbriel** as a fourth DE (§3.1).
- **`mute-mic-on-login`** — a GNOME-layer personal tweak, grouped with keybinds.
- **Renaming `vexos.gnome.flatpakInstall`** to a DE-neutral namespace (§3.6).
