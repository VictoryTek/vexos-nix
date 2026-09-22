# Sunshine default-enable — spec

## Current state analysis

`modules/sunshine.nix` gates Sunshine (the project's RDP replacement) behind
`vexos.features.sunshine.enable`, an `lib.mkEnableOption` (default `false`).
It is imported unconditionally by:

- `configuration-desktop.nix`
- `configuration-server.nix`
- `configuration-htpc.nix`
- `configuration-vanilla.nix`

`template/features.nix` ships the toggle commented out (`# ... = false;`),
so every host's `/etc/nixos/features.nix` starts with Sunshine off. On a
fresh install/VM test, Sunshine is never running unless the user manually
runs `just enable-feature sunshine` — which requires knowing the feature
exists and remembering to do it. This is why the user never sees it
installed in VM testing despite it having replaced RDP as the project's
remote-access story.

`configuration-vanilla.nix` is documented as an intentional stock-NixOS
mirror ("stays stock until [opted into]") and already overrides one
module default the same way, for the same reason:
`vexos.flatpak.enable = lib.mkDefault false;` even though
`modules/flatpak.nix` defaults that option to `true`.

`configuration-stateless.nix` does not import `modules/sunshine.nix` at
all (documented reason: tmpfs home, no persistent pairing state) and
`configuration-headless-server.nix` does not import it either (no GUI,
nothing to stream). Neither needs a change.

`just features` (justfile:1417-1423) determines enabled/disabled status
by grepping `/etc/nixos/features.nix` for a literal `= true` line. If the
module default flips to `true` while the template stays commented out,
`just features` would incorrectly report Sunshine as disabled (✗) even
though it is actually running.

## Problem definition

Sunshine should be installed and running out of the box on every
GUI-capable role that is meant to keep it (desktop, server, htpc),
while vanilla (intentionally stock) and stateless/headless-server
(documented exclusions, unchanged) remain as they are.

## Proposed solution

1. **`modules/sunshine.nix`** — flip the `mkEnableOption` default to
   `true` via `lib.mkEnableOption "..." // { default = true; }`. This is
   the single option declaration site; every importer inherits the new
   default except where explicitly overridden (Option B pattern: no new
   `lib.mkIf` role guards needed since the override happens in the
   role's own `configuration-*.nix`, same technique vanilla already uses
   for flatpak).
2. **`configuration-vanilla.nix`** — add
   `vexos.features.sunshine.enable = lib.mkDefault false;` next to the
   existing `vexos.flatpak.enable = lib.mkDefault false;` override, with
   a matching comment, to preserve vanilla's "stays stock" contract.
3. **`template/features.nix`** — update the header comment and the
   commented `sunshine` line to reflect the new default (`true`), so a
   user reading the file understands the toggle now needs to be set to
   `false` to opt out, not `true` to opt in.
4. **`justfile` `features` recipe (`_check` helper, ~line 1417)** — make
   the status check default-aware: if the line is explicitly `true` or
   `false` in the file, use that; otherwise fall back to the feature's
   known default. Pass `on` for `sunshine`, keep existing (off) behavior
   for `gaming`/`development`/`print3d`/`virtualization`.

No other GPU-encoder modules (`modules/gpu/{amd,nvidia,intel}.nix`) need
changes — they set `services.sunshine.settings.encoder` unconditionally,
which is inert unless `services.sunshine.enable` is true.

## Implementation steps (Option B pattern)

- Universal option default lives in `modules/sunshine.nix` (the module
  that declares the option) — this is the standard "same module declares
  the option it gates" carve-out, not role-smuggling.
- Role opt-out lives in the role's own `configuration-vanilla.nix` file,
  matching the existing flatpak precedent exactly.
- No new `lib.mkIf` guards added to any shared module.

## Dependencies

None — no new packages or flake inputs. `services.sunshine` is an
existing NixOS module already in use; only its default enablement
changes.

## Configuration changes

- `modules/sunshine.nix`: option default `false` → `true`.
- `configuration-vanilla.nix`: explicit `lib.mkDefault false` override.
- `template/features.nix`: comment/documentation update only (no
  behavior change from this file alone, since the option's own default
  now governs the commented-out state).
- `justfile`: `_check` helper gains a default-awareness parameter.

## Risks and mitigations

- **Risk:** Existing hosts that never touched `features.nix` will pick
  up Sunshine (open Moonlight port, uinput group membership, capSysAdmin
  wrapper) on their next rebuild without having opted in.
  **Mitigation:** This is the explicit intent of the change — Sunshine
  is the project's remote-access story and should be on by default. The
  toggle still exists for hosts that want to opt out
  (`vexos.features.sunshine.enable = false;` in their own
  `/etc/nixos/features.nix`).
- **Risk:** `just features` misreporting status.
  **Mitigation:** addressed directly in step 4 above.
- **Risk:** Vanilla accidentally picking up Sunshine and breaking its
  "stock NixOS" contract.
  **Mitigation:** explicit `lib.mkDefault false` override, same pattern
  as the existing flatpak override in the same file.
