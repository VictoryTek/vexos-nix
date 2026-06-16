# push_to_talk_spec.md

## Current State Analysis

`gnomeExtensions.nothing-to-say` (v27) is **already** installed and enabled in:
- `modules/gnome.nix` line 208: package in `environment.systemPackages`
- `modules/gnome.nix` line 22: UUID `nothing-to-say@extensions.gnome.wouter.bolsterl.ee` in `commonExtensions`

GNOME Shell in nixpkgs is 50.1 (NixOS 26.05). Extension v27 supports GNOME 50. The extension is
therefore already functional after a rebuild — the user's 26.05 upgrade broke the EGO-installed copy,
not the nixpkgs-managed one.

No dconf configuration for the extension exists in any module. The extension's schema defaults
are `<Super>backslash` for the keybinding and `when-recording` for icon-visibility.

There is no mic-mute-on-login mechanism.

## Problem Definition

1. Mic mute keybinding and icon visibility are not declared declaratively — defaults are relied on
   implicitly.
2. Mic is not muted at session start, requiring manual action before each use.

## Proposed Solution

### Change 1: Declare nothing-to-say dconf settings in `modules/gnome.nix`

Add to the universal `programs.dconf.profiles.user.databases` settings block:

```nix
"org/gnome/shell/extensions/nothing-to-say" = {
  keybinding-toggle-mute = [ "<Super>backslash" ];
  icon-visibility        = "always";
};
```

Rationale:
- Extension is already universal (all GNOME roles import `gnome.nix`), so its config belongs here.
- `icon-visibility = "always"` surfaces the mute state in the panel at all times instead of only
  when recording — improves discoverability on a desktop where mic starts muted.
- Keybinding is the user's existing muscle memory; declaring it explicitly prevents silent drift.

### Change 2: Mute mic on login via systemd user service in `modules/gnome-desktop.nix`

```nix
systemd.user.services.mute-mic-on-login = {
  description = "Mute microphone at graphical session start";
  wantedBy    = [ "graphical-session.target" ];
  after       = [ "graphical-session.target" ];
  serviceConfig = {
    Type       = "oneshot";
    ExecStart  = "${pkgs.wireplumber}/bin/wpctl set-mute @DEFAULT_AUDIO_SOURCE@ 1";
  };
};
```

Rationale:
- Desktop-specific behavior (server/htpc roles should not auto-mute mic on login).
- WirePlumber is already on the system via `services.pipewire.wireplumber`.
- `@DEFAULT_AUDIO_SOURCE@` is the PipeWire virtual alias that resolves to the active input device.
- `graphical-session.target` ensures PipeWire/WirePlumber is running before the mute command fires.

## Implementation Steps

1. Edit `modules/gnome.nix`: add nothing-to-say dconf block to the existing
   `programs.dconf.profiles.user.databases` settings.
2. Edit `modules/gnome-desktop.nix`: add `systemd.user.services.mute-mic-on-login`.

## Modified Files

- `modules/gnome.nix`
- `modules/gnome-desktop.nix`

## Risks and Mitigations

| Risk | Mitigation |
|------|-----------|
| `graphical-session.target` not reached before wpctl runs | `after` ordering ensures WirePlumber is up |
| Wrong default audio source selected | `@DEFAULT_AUDIO_SOURCE@` always resolves to WirePlumber's configured default |
| dconf key type mismatch | Schema declares `keybinding-toggle-mute` as `as` (array of strings); Nix list `[ "<Super>backslash" ]` maps correctly |
