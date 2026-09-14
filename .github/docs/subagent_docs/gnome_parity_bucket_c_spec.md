# Bucket C — GNOME→Noctalia Parity: Mic-Mute Feedback + Privacy Indicator

Source: `.github/docs/subagent_docs/gnome_to_noctalia_parity_audit.md`, bucket C
(C1, C2). User decision on C2 (asked directly): accept the native `privacy`
widget as the substitute for GNOME's always-visible mic-mute indicator — no
custom polling widget, no plugin.

## Current state

- **GNOME side** (`modules/gnome-desktop.nix:48-73`): a custom
  `org.gnome.settings-daemon` keybinding runs a `writeShellScript` wrapper on
  `<Super>backslash` that:
  1. Takes an flock (`-n 9` on `$XDG_RUNTIME_DIR/mic-toggle.lock`) so key
     autorepeat only fires the toggle once per physical press.
  2. Toggles mute via `wpctl set-mute @DEFAULT_AUDIO_SOURCE@ toggle`.
  3. Checks the resulting state (`wpctl get-volume ... | grep -q MUTED`) and
     plays the matching freedesktop sound
     (`device-removed.oga` on mute, `device-added.oga` on unmute) via
     `pw-play`.
  4. `sleep 0.3` before releasing the lock, to cover the sound's playback
     window.

- **Hyprland/Noctalia side** (`files/hypr/hyprland.conf:179,191`): both the
  `$mod+backslash` keybind and the `XF86AudioMicMute` media key call
  `noctalia msg mic-mute` directly — no sound, no debounce.
  `files/hypr/hyprland.conf` is a **seeded-once** dotfile (copied by
  `home/dank-material-shell.nix`'s `seedHyprlandConf` activation script only
  if `~/.config/hypr/hyprland.conf` does not already exist — see that file,
  lines 262-278). It is plain text, not templated by Nix: any command it
  references must already be resolvable on `$PATH`, not a `${pkgs.foo}`
  interpolation. This is why the fix needs a named package on `PATH`, not an
  inline store-path script referenced directly from the conf file.

- Confirmed via the pinned Noctalia v5.1.0 source
  (`/nix/store/28k1r6zxsvqhdjrcvy3xhdyvszilv4wm-source`):
  - `noctalia msg mic-mute` (`src/pipewire/pipewire_service.cpp:2383-2389`)
    is synchronous: it calls `setMicMuted(!source->muted)` on the same
    PipeWire graph `wpctl` reads, then returns `"ok\n"` — the mute state is
    already committed by the time the CLI call returns, so a `wpctl
    get-volume` check immediately afterward is not racing the toggle.
  - The `privacy` bar widget (`src/shell/bar/widgets/privacy_widget.h:19`)
    defaults `hide_inactive = false` — i.e. it is **already always-visible
    by default**: mic/camera/screen-share glyphs each render permanently,
    switching between an active glyph+color and a dimmed inactive
    glyph+color as PipeWire capture state changes. No extra options are
    needed to get "always visible" behavior; adding the widget with no
    settings block is sufficient.
  - `home/noctalia.nix`'s `bar.default.end` does not currently include
    `"privacy"`.

## Problem

- **C1**: the Hyprland mic-mute bind lost GNOME's audio feedback and
  autorepeat debounce when it moved to `noctalia msg mic-mute`.
- **C2**: there is no always-visible mic-state indicator on the Hyprland bar
  at all today (only the `$mod+N` notification panel touches mic state
  indirectly). GNOME had one permanently in view.

## Proposed solution

### C1 — restore sound + debounce, keep Noctalia's IPC (so the OSD still fires)

Add a named wrapper script to `PATH` via `home.packages` in
`home/dank-material-shell.nix`, next to the existing shell-agnostic mic
plumbing (`mute-mic-on-login`, `services.udiskie`, `tail-tray` — all already
living outside the DMS-specific attrset in that file, per its own comment at
line 60-62 that this section stays active for Noctalia). Use
`pkgs.writeShellScriptBin` so it is a single self-contained package, matching
the idiom `pkgs.writeShellScript` already used for the GNOME variant.

```nix
home.packages = [
  pkgs.tail-tray
  (pkgs.writeShellScriptBin "vexos-mic-toggle" ''
    set -euo pipefail
    (
      flock -n 9 || exit 0
      ${config.programs.noctalia.package}/bin/noctalia msg mic-mute >/dev/null
      if ${pkgs.wireplumber}/bin/wpctl get-volume @DEFAULT_AUDIO_SOURCE@ \
          | grep -q MUTED; then
        ${pkgs.pipewire}/bin/pw-play \
          ${pkgs.sound-theme-freedesktop}/share/sounds/freedesktop/stereo/device-removed.oga
      else
        ${pkgs.pipewire}/bin/pw-play \
          ${pkgs.sound-theme-freedesktop}/share/sounds/freedesktop/stereo/device-added.oga
      fi
      sleep 0.3
    ) 9>"''${XDG_RUNTIME_DIR}/mic-toggle.lock"
  '')
];
```

Same flock path (`mic-toggle.lock`) and sound pair as the GNOME script —
deliberate parity, not a new pattern. `config.programs.noctalia.package` is
already used elsewhere in `home/noctalia.nix` (the `hooks.theme_mode_changed`
hook), so referencing it from `dank-material-shell.nix` needs
`osConfig`/`config` only — no cross-module coupling beyond what already
exists (both files already read `osConfig.vexos.desktop.environment`).

Then in `files/hypr/hyprland.conf`, change both mic-mute binds from calling
`noctalia msg mic-mute` directly to calling the wrapper:

```
bind = $mod,       backslash, exec, vexos-mic-toggle
...
bindl  = ,      XF86AudioMicMute,      exec, vexos-mic-toggle
```

Same seeded-file caveat as B5/B6 applies: a host that already has
`~/.config/hypr/hyprland.conf` seeded will not pick this up automatically —
call this out in the commit and in the review, same as prior bucket-B rows.

### C2 — surface the `privacy` widget as the accepted substitute

Add `"privacy"` to `home/noctalia.nix`'s `bar.default.end`, no options block
(defaults already give always-visible dimmed/active glyphs). Placed next to
`notifications`/`caffeine` in the status-icon cluster, before the
functional/session cluster — matches the "appindicator-extension-style"
grouping comment already on that line.

```nix
end = [ "tray" "caffeine" "notifications" "privacy" "network" "bluetooth" "volume" "battery" "theme_mode" "screenshot" "session" ];
```

Update the audit doc's C2 row to close it as "accepted — `privacy` widget
shipped" rather than leaving it open, since this was a real (if partial)
implementation, not a no-op decision.

## Implementation steps (Option B module pattern)

No new files needed — both edits are additions inside existing home-manager
modules that are already gated `lib.mkIf (osConfig.vexos.desktop.environment
== "hyprland")`, i.e. already role-scoped correctly. No `lib.mkIf` role/flag
guards are being added.

1. `home/dank-material-shell.nix` — add the `vexos-mic-toggle`
   `writeShellScriptBin` package to the existing (non-DMS-specific)
   `home.packages` list.
2. `files/hypr/hyprland.conf` — repoint both mic-mute binds at
   `vexos-mic-toggle`.
3. `home/noctalia.nix` — add `"privacy"` to `bar.default.end`.
4. `.github/docs/subagent_docs/gnome_to_noctalia_parity_audit.md` — mark C1
   and C2 closed with the same style used for bucket B.

## Dependencies

No new flake inputs, no new external libraries. All packages referenced
(`wireplumber`, `pipewire`, `sound-theme-freedesktop`) are already used
verbatim in `modules/gnome-desktop.nix`'s existing script; Context7 is not
applicable (internal Nix module change, no external API).

## Risks and mitigations

| Risk | Mitigation |
|---|---|
| Seeded `hyprland.conf` on existing hosts won't pick up the new bind. | Same accepted caveat as B5/B6; call out in commit message. New installs get it automatically via the seeder. |
| `noctalia msg mic-mute` failing silently (e.g. "error: no default input") would still let the script fall through to a `wpctl get-volume` check on a source that may not exist. | Matches GNOME's own script, which has no explicit error handling either — acceptable parity-level robustness, not a regression. |
| `set -euo pipefail` + the script exiting non-zero from `grep -q` finding no match combined with `if` context — `grep -q` inside an `if` never trips `set -e` (it's the condition), so this is safe; confirmed shape matches the GNOME script (also no `if grep -q MUTED; then ... fi` issue there). | No action needed — verified during spec, not left as an assumption. |
| Widget count on the bar keeps growing (now 10 items in `end`). | Out of scope for bucket C; a layout/overflow concern belongs to a future pass, not blocking here. |

## Verification plan

- `Hyprland --verify-config` (or `nix eval`/manual read) on the edited
  `files/hypr/hyprland.conf` for syntax.
- `noctalia config validate` semantics: `home/noctalia.nix`'s own comment says
  an unknown key/enum only warns, doesn't fail build — confirm `privacy` is
  a real widget type (already confirmed above) so no silent no-op.
- Standard Phase 3 build validation (`nix flake show --impure`,
  `nixos-rebuild dry-build` for desktop-amd/nvidia/vm) since this only
  touches Hyprland desktop role, per CLAUDE.md's build-step gating rules for
  desktop-only changes (server/stateless/htpc dry-builds not required — no
  server or htpc modules touched).
