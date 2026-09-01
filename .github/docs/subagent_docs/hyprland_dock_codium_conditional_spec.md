# Hyprland dock: conditional Codium pin — Spec

## Current state analysis

`home/dank-material-shell.nix` hardcodes `"codium"` into both
`session.pinnedApps` and `session.barPinnedApps` ([lines 84-101](../../../home/dank-material-shell.nix)),
unconditionally, regardless of whether VSCodium is actually installed.
VSCodium (`pkgs.vscodium-fhs`) is only installed when
`vexos.features.development.enable = true` (`modules/development.nix`, a
per-host opt-in flag set in `/etc/nixos/features.nix`, not part of the
`configuration-desktop.nix` base).

## Problem definition

Observed behavior: on a host with `development.enable = false`, DMS's dock
still shows a Codium entry (placeholder icon, doesn't launch, because nothing
is installed to resolve). This is confirmed to be a direct consequence of the
static pin list having no gate on the feature flag that controls whether the
package exists.

## Proposed solution

Read `osConfig.vexos.features.development.enable` (the file already reads
`osConfig.vexos.desktop.environment` the same way, so `osConfig` is already in
scope) and append `"codium"` to both pin lists only when true, via
`lib.optional`.

```nix
let
  isHyprland  = osConfig.vexos.desktop.environment == "hyprland";
  hasDevTools = osConfig.vexos.features.development.enable;
  basePinnedApps = [
    "brave-origin"
    "app.zen_browser.zen"
    "org.gnome.Nautilus"
    "com.mitchellh.ghostty"
    "io.github.up"
    "org.gnome.Boxes"
  ] ++ lib.optional hasDevTools "codium";
in
{
  ...
  config = lib.mkIf isHyprland {
    ...
    session = {
      ...
      pinnedApps    = basePinnedApps;
      barPinnedApps = basePinnedApps;
    };
  };
}
```

Since `pinnedApps` and `barPinnedApps` are identical lists today, this also
removes the duplication (single source of truth), which is in scope because it
is a direct consequence of the requested fix — not an unrelated cleanup.

## Implementation steps

1. Edit `home/dank-material-shell.nix`:
   - Add a `let` block (the file currently opens straight into the function
     body — introduce `let isHyprland = ...; in` if not already factored, or
     add alongside existing pattern) defining `basePinnedApps` as shown above.
   - Replace both `pinnedApps` and `barPinnedApps` literal lists with
     `basePinnedApps`.
2. No other files change. `modules/development.nix` and
   `modules/desktop-environment.nix` already declare the two options being
   read; no new option needs to be declared.

## Dependencies

None — internal option composition only, no new package or external API.

## Configuration changes

`home/dank-material-shell.nix` only.

## Risks and mitigations

- **Risk:** `osConfig.vexos.features.development` might not exist on non-desktop
  roles evaluating this file. **Mitigation:** the whole file's `config` block is
  already gated by `lib.mkIf (osConfig.vexos.desktop.environment == "hyprland")`,
  and `vexos.features.development.enable` is declared globally in
  `modules/development.nix` with `lib.mkEnableOption` (default `false`), which
  is imported at the top level for every role that can also be Hyprland (the
  desktop role) — so the option always exists with a real default, never throws
  `attribute missing`.
- **Risk:** Removing the literal duplication changes indentation/diff shape.
  **Mitigation:** keep the change minimal — just extract the shared list, don't
  reformat surrounding code.
