# Queue desktop-environment switches for reboot instead of a live restart — Spec

## Current state analysis

`justfile`'s `switch` recipe always runs `sudo nixos-rebuild switch`, which
builds the new generation AND immediately activates it in the running
session — including restarting any systemd unit whose definition changed,
such as the display manager. This thread directly observed the consequence
of a live display-manager restart during a GNOME→Hyprland switch:
`coredumpctl` showed the GDM binary still running, under the newly-aliased
`greetd.service` unit name, for the unit's entire lifetime before segfaulting
— i.e. the live activation could not cleanly hand the console over from the
old display manager to the new one. A clean reboot resolved it every time it
was tried. The same class of risk applies to any GDM↔greetd switch
(GNOME↔Hyprland, GNOME↔COSMIC), not just the one instance already observed.

`switch` currently ends by asking `Reboot now? [y/N]:` (default no) regardless
of what changed — appropriate for an ordinary config change (most services
tolerate a live restart fine), but not for a display-manager change, where a
live restart is close to guaranteed to misbehave and a "no" answer leaves the
host in exactly the broken state this whole thread has been debugging.

## Problem definition

User request: `just switch` to a different desktop environment should not
attempt a live in-session switch at all. It should build the new
configuration, queue it for the next boot, tell the user plainly that it's
ready, and reboot — without dropping the current session to a black screen
first.

## Proposed solution architecture

Detect whether this invocation is actually changing
`vexos.desktop.environment` (not just re-running `just switch desktop <gpu>`
with the same DE), and branch:

- **DE unchanged** (including every non-desktop role, where this concept
  doesn't apply): behaviour is **byte-for-byte unchanged** —
  `nixos-rebuild switch`, existing exit-code-4 handling, existing
  `Reboot now? [y/N]:` prompt.
- **DE changed**: use `sudo nixos-rebuild boot` instead of `switch`. `boot`
  builds the configuration and sets it as the default boot entry, running the
  activation script's static parts (users, `/etc` files, bootloader entry)
  but — critically — it does **not** restart any running systemd services,
  which is the entire class of behaviour that caused the black screens
  investigated in this thread. Print a clear "ready, rebooting" message, then
  reboot unconditionally (no `[y/N]` prompt) — the current session cannot
  reach the new DE without a reboot regardless of what the user answers, so
  asking only reintroduces the chance of leaving the host in the broken
  live-switched state this fix exists to prevent.

To detect "DE changed", capture the **currently active** value of
`vexos.desktop.environment` from `/etc/nixos/features.nix` before the
existing write step overwrites it — matching only an *uncommented* line
(a commented line has no effect on the running system, so the true active
value in that case is still the NixOS default, `"gnome"`) — and compare it to
the newly selected `$DESKTOP_ENV`.

## Implementation steps

- `justfile`, `switch` recipe only:
  - Capture `OLD_DESKTOP_ENV` (default `"gnome"`) at the start of the
    `if [ "$ROLE" = "desktop" ]` block, before any interactive prompt or file
    write.
  - After `$DESKTOP_ENV` is validated, compute `DE_CHANGED`.
  - At the point the recipe currently runs `nixos-rebuild switch`
    unconditionally, branch: `boot` + forced reboot when `DE_CHANGED=true`;
    otherwise the existing `switch` + optional-reboot path, untouched.
- No `.nix` files touched — this is tooling, not NixOS configuration, so no
  Nix eval/build validation applies; verified instead with `bash -n` (no
  `just` binary available in this environment) and manual trace-through of
  both branches.

## Risks and mitigations

- **Risk:** `nixos-rebuild boot` failures are reported differently than
  `switch`'s exit-code-4 case (which is specific to a live restart failing —
  a failure mode `boot` cannot hit, since it never restarts services).
  **Mitigation:** kept simple — any non-zero exit from `boot` aborts with the
  raw exit code, same as the generic (non-4) failure path `switch` already
  has.
- **Risk:** unconditional reboot with no confirmation is a more forceful UX
  than the rest of this justfile. **Mitigation:** explicitly what the user
  asked for, and the alternative (asking, defaulting to no) is the exact
  behaviour that left hosts in the broken live-switched state throughout this
  investigation. Scoped narrowly to only the DE-changed case, not to `switch`
  in general.
- **Risk:** `OLD_DESKTOP_ENV` detection could misfire if `features.nix` has
  unusual formatting. **Mitigation:** reuses the same `vexos\.desktop\.environment\s*=\s*"[a-z]+"` shape the recipe's own existing sed rewrite already
  depends on and has been running against in production — not a new pattern.
- **Not verified**: this environment has no `just` binary (confirmed — `which
  just` not found in WSL) and no NixOS host to actually run the recipe.
  Verified via `bash -n` syntax check and manual trace of both branches only;
  a real `just switch` invocation on the target host is the only way to fully
  confirm this.
