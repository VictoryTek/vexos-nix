# Hyprland Omarchy-Style Keybinds Spec

## Current State Analysis

`files/hypr/hyprland.conf` (seeded once via `home/dank-material-shell.nix`'s
`home.activation.seedHyprlandConf`, user-owned after first boot) currently has
a minimal, hand-picked keybind set: DMS shell shortcuts, media/brightness
keys, three `hyprshot` screenshot modes, and a small window-management subset
(close, fullscreen, float, 5 workspaces, arrow-key focus, mouse move/resize).

The user wants Hyprland's keybind scheme to match **Omarchy**'s (a
Hyprland-based distro), except for the existing mic-mute binding at
`$mod, backslash` (`dms ipc call mic mute`), which must not change in any way
— it is treated as this project's fixed "PTT" binding.

Scope, per user decision: port (1) Omarchy's window/workspace management
scheme verbatim (native Hyprland dispatchers, zero new dependencies) and (2)
Omarchy's utility/media bindings, adapted to call our existing DMS ipc /
hyprshot / wpctl / already-installed tools where a real equivalent exists —
dropping bindings whose Omarchy implementation depends on tooling we don't
have (`walker`, `mako`, `swayosd`, `omarchy-menu`, `voxtype`, etc.) rather
than fabricating a substitute.

## Source Verification

Omarchy's GitHub repo moved (`basecamp/omarchy` → `omacom/omarchy`, confirmed
via the GitHub API redirect) and its current default branch (`quattro`)
rewrote the Hyprland config to Lua (`bindings.lua` via a `hyprlua`-style
plugin) — incompatible with our classic `hyprland.conf` syntax and not
something we should add as a new dependency for this task. The `master`
branch of the original repo still serves the classic `.conf`-syntax config
this project actually uses, so it was used as the porting source:

- `https://raw.githubusercontent.com/basecamp/omarchy/master/config/hypr/hyprland.conf` — include structure
- `https://raw.githubusercontent.com/basecamp/omarchy/master/default/hypr/bindings/{media,clipboard,tiling-v2,utilities}.conf` — the actual default bindings (this is what "Omarchy's keybinds" means)
- `https://raw.githubusercontent.com/basecamp/omarchy/master/config/hypr/bindings.conf` — **excluded from scope**: this is Omarchy's own seeded *personal example* file (analogous to our own seeded `hyprland.conf`), bound to specific apps (Spotify, Obsidian, Signal, 1Password, Typora, ChatGPT/YouTube/X webapps) that aren't part of vexos. Porting it would create keybinds pointing at nothing. Not "the" Omarchy default scheme in the sense meant here.

Every DMS-side capability referenced below (ipc targets/functions) was
re-verified directly against the pinned `inputs.dms` source
(`quickshell/DMSShellIPC.qml`, `Services/AudioService.qml`,
`Services/DisplayService.qml`, `Modals/NotificationModal.qml`,
`Modules/Lock/Lock.qml`), not assumed from the earlier GNOME-parity work.

## Mapping: Omarchy default → vexos Hyprland binding

### Window/workspace management (`tiling-v2.conf`) — ported near-verbatim

| Omarchy | vexos |
|---|---|
| `SUPER, W` close window | **replaces** existing `$mod, Q` (moved to match Omarchy; Q becomes unbound) |
| `SUPER, J` togglesplit / `SUPER, P` pseudo / `SUPER, T` togglefloating | new — `$mod, T` **replaces** existing `$mod SHIFT, Space` for float-toggle |
| `SUPER, F` fullscreen / `SUPER CTRL, F` tiled fullscreen / `SUPER ALT, F` full width | `$mod,F` kept as-is; two new additions |
| `SUPER, {LEFT,RIGHT,UP,DOWN}` movefocus | kept as-is (already matched) |
| `SUPER, code:10-19` workspace 1-10 / `SUPER SHIFT, code:10-19` move / `SUPER SHIFT ALT, code:10-19` move silent | **replaces** existing symbolic `$mod,1-5` / `$mod SHIFT,1-5` (extends 5→10, switches to physical key codes so it works regardless of keyboard layout, matching Omarchy's own rationale) |
| `SUPER, S` scratchpad toggle / `SUPER ALT, S` move to scratchpad | new |
| `SUPER, TAB` / `SUPER SHIFT, TAB` / `SUPER CTRL, TAB` workspace next/prev/former | new |
| `SUPER SHIFT ALT, {arrows}` move workspace to monitor | new |
| `SUPER SHIFT, {arrows}` swapwindow | new |
| `ALT, TAB` / `ALT SHIFT, TAB` cyclenext + bringactivetotop | new |
| `CTRL ALT, TAB` / `CTRL ALT SHIFT, TAB` focusmonitor | new |
| `SUPER, code:20/21` / `SUPER SHIFT, code:20/21` resizeactive (`-`/`=` keys) | new |
| `SUPER, mouse_down/up` scroll workspace | new |
| Groups: `SUPER,G` `SUPER ALT,G` `SUPER ALT,{arrows}` `SUPER ALT,TAB/SHIFT+TAB` `SUPER CTRL,{LEFT,RIGHT}` `SUPER ALT,mouse_down/up` `SUPER ALT,code:10-14` | new, full set |
| `SUPER mouse:272/273` movewindow/resizewindow | kept as-is (already matched, `bindm`) |
| `SUPER, L` "toggle workspace layout" | **not ported** — calls an Omarchy-only script we don't have, and the key collides with our existing (far more important) `$mod,L` → `dms ipc call lock lock`. Lock keeps the key. |
| `CTRL ALT, DELETE` close-all / `SUPER, O` pop-out-float | **not ported** — both call Omarchy-only scripts (`omarchy-hyprland-window-close-all`, `omarchy-hyprland-window-pop`); no native or DMS equivalent, not fabricated |
| `SUPER, code:61` monitor-scaling cycle | **not ported** — Omarchy-only script, no equivalent tool |

### Clipboard (`clipboard.conf`) — not ported

Omarchy binds `SUPER,C`/`SUPER,V`/`SUPER,X` to `sendshortcut` (universal
copy/paste/cut passthrough to the active window). `SUPER,V` and `SUPER,X`
directly collide with pre-existing, more important DMS bindings already in
this file (`$mod,V` → clipboard-history viewer, `$mod,X` → dash toggle).
Hyprland fires every `bind` registered on a given combo, so keeping both
would have made two unrelated actions fire on the same keypress. Dropped
entirely rather than porting only the non-conflicting `SUPER,C` — a lone
"universal copy" with no matching paste/cut isn't worth the inconsistency.

### Utilities / media — adapted to DMS/existing tools

| Omarchy binding | vexos adaptation | Grounding |
|---|---|---|
| `SUPER,ESCAPE` system menu / `XF86PowerOff` power menu | `dms ipc call powermenu toggle` | `DMSShellIPC.qml` `target: "powermenu"` has `open`/`close`/`toggle` |
| `SUPER SHIFT,COMMA` dismiss all notifications | `dms ipc call notifications dismissAllPopups` | `Modals/NotificationModal.qml` `target: "notifications"` has `dismissAllPopups()` |
| `SUPER CTRL,N` toggle nightlight | **moves** existing `$mod SHIFT,N` → `$mod CTRL,N` (matches Omarchy's key; we already had this action, just on the wrong key) |
| `,XF86Calculator` | `gtk-launch org.gnome.Calculator` — **not** bare `gnome-calculator`: verified only the Flatpak (`org.gnome.Calculator`) is installed for this role, no native package |
| `SUPER CTRL,A` audio controls | `pavucontrol` (already installed, `home-desktop.nix`) |
| `SUPER CTRL,B` bluetooth controls | `blueman-manager` (verified: `services.blueman.enable` pulls in `pkgs.blueman` → `environment.systemPackages` automatically, per the upstream NixOS module) |
| `SUPER CTRL,W` wifi controls | `$terminal -e nmtui` (verified: `networking.networkmanager.enable` is set in `modules/network.nix`, imported by `configuration-desktop.nix`; `nmtui` ships with the networkmanager package) |
| `SUPER CTRL,T` activity | `$terminal -e btop` (already installed, `modules/packages-common.nix`) |
| `SUPER CTRL ALT,T` show time | `notify-send` one-liner — ported verbatim, zero new dependency (Omarchy's own version is already dependency-free) |
| `SUPER CTRL ALT,B` show battery | Adapted from `omarchy-battery-status` (script we don't have) to a `upower` one-liner — `upower` added to `environment.systemPackages` since only the daemon (`services.upower.enable`) was previously guaranteed, not necessarily the CLI on `$PATH` |
| `SUPER CTRL ALT,W` show weather | **not ported** — no data source/API equivalent, would be fabricated |
| `SUPER CTRL,Z` / `SUPER CTRL ALT,Z` cursor zoom | ported verbatim (`hyprctl keyword cursor:zoom_factor …`, native Hyprland, no Omarchy dependency) — needs `jq`, added to `environment.systemPackages` |
| `SUPER CTRL,L` lock system | **not ported** — redundant with existing `$mod,L` → `dms ipc call lock lock`, which is simpler and already there |
| `XF86AudioMicMute` mute mic | `dms ipc call mic mute` — a **separate, new** hardware-key binding, added purely for convenience on keyboards with a dedicated mic-mute key. Does **not** touch `$mod,backslash` in any way. |
| `XF86AudioPause` | `playerctl play-pause` — trivial addition alongside existing Play/Next/Prev |
| `ALT,XF86Audio{Raise,Lower}Volume` / `ALT,XF86MonBrightness{Up,Down}` precise ±1 steps | `dms ipc call audio increment/decrement 1` / `dms ipc call brightness increment/decrement 1` — verified `increment(step)`/`decrement(step)` accept a step arg in both `AudioService.qml` and `DisplayService.qml` |
| `SHIFT,XF86MonBrightness{Up,Down}` max/min | `dms ipc call brightness set 100` / `set 1` — verified `DisplayService.qml` has `set(percentage, device)` |
| Screenshots (`,PRINT` shot / `ALT,PRINT` record / `SUPER,PRINT` color-pick / `SUPER CTRL,PRINT` OCR) | Restructured to fit our existing 3-mode `hyprshot` setup plus `hyprpicker` (already installed, previously unbound): `,PRINT`→region (unchanged), `SUPER,PRINT`→**new** hyprpicker (matches Omarchy exactly), `SUPER SHIFT,PRINT`→output (unchanged), `SUPER CTRL,PRINT`→**window** (repurposed from Omarchy's OCR slot — we have no OCR tool, and this preserves our pre-existing window-capture mode rather than dropping it) |
| Screen recording (`ALT,PRINT`) | **not ported** — no recording tool installed (`wf-recorder` etc. is a real, separate feature decision, out of scope here) |
| `XF86Kbd*`, `XF86Touchpad*` | **not ported** — no verified, hardware-independent tool wired for either |
| `SUPER,XF86AudioMute` switch audio output | **not ported** — `dms ipc` has no audio-output-switch function; the `"outputs"` target that name suggests is actually **monitor/display** output profiles (verified in `DMSShellIPC.qml`), not audio devices — do not conflate the two |
| Emoji picker, root/hardware/capture/toggle menus, theme menus, transparency/gaps toggles, share, transcode, reminders, dictation (`voxtype`) | **not ported** — every one depends on an Omarchy-only tool (`walker`, `omarchy-menu`, `omarchy-*` scripts, `voxtype`) with no DMS or native equivalent |

### Mouse / pointer behavior — unaffected

Nothing in this change removes or alters mouse-driven interaction: `bindm`
window move/resize on `mouse:272`/`273` is kept exactly as-is, the DMS
dock/bar/spotlight/control-center remain fully mouse-operable (this port adds
keybinds, it doesn't add `general:allow_tearing`-style forced-tiling window
rules or anything that would make the session keyboard-only), and every
launched app (nautilus, pavucontrol, blueman-manager, etc.) is its normal
point-and-click self. This is a purely additive keybind change.

## Implementation Steps

1. **files/hypr/hyprland.conf** — reorganize into sections mirroring Omarchy's
   `media.conf` / `clipboard.conf` / `tiling-v2.conf` / `utilities.conf`
   split (as comments, not separate files — this project seeds one file), per
   the mapping tables above. Preserve the `$mod,backslash` line and its
   surrounding comment unchanged; add an explicit `# DO NOT reassign` note on
   it given this task's constraint.
2. **modules/hyprland-desktop.nix** — add `pkgs.jq`, `pkgs.upower` to
   `environment.systemPackages` (both newly required by ported bindings;
   `pavucontrol`, `blueman-manager`, `btop`, `nmtui`, `hyprpicker` already
   present/verified above, no change needed for those).

## Dependencies

No new flake inputs. Two new native nixpkgs packages (`jq`, `upower`) added
to an existing `environment.systemPackages` list — both tiny, no version
pinning concerns, no Context7 lookup needed (not a versioned library
integration).

## Risks and Mitigations

- **Workspace keybind churn**: switching from symbolic `1`-`5` to `code:10-19`
  and extending to 10 workspaces changes muscle memory but is required to
  match Omarchy's actual scheme (which deliberately uses physical codes for
  layout independence) — documented, not silent.
- **`$mod,Q` → `$mod,W` for close-window** and **`$mod SHIFT,Space` →
  `$mod,T` for float-toggle** are the two existing bindings this port moves
  (not adds) to match Omarchy; called out explicitly since "port keybinds"
  could be misread as purely additive — Omarchy's own scheme uses those keys
  for those actions, so full adoption means moving them.
- The mic-mute binding at `$mod,backslash` is untouched, and a second,
  independent hardware-key binding (`XF86AudioMicMute`) is added — verified
  this cannot collide with or shadow the `$mod,backslash` bind since they are
  different key combinations entirely.
