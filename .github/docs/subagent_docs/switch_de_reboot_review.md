# Queue desktop-environment switches for reboot instead of a live restart — Review

## Modified files
- `justfile` (`switch` recipe only)

## What changed

- Captures `OLD_DESKTOP_ENV` from the currently *active* (uncommented) line
  in `/etc/nixos/features.nix` before any write happens, defaulting to
  `"gnome"` when absent/commented (matching the real NixOS default).
- Computes `DE_CHANGED` after the new `$DESKTOP_ENV` is validated.
- Branches at the point the recipe invokes `nixos-rebuild`:
  - `DE_CHANGED = true` → `nixos-rebuild boot` (never restarts running
    services) + a clear "queued, rebooting" message + unconditional
    `sudo systemctl reboot`, no prompt.
  - Otherwise → **exactly the pre-existing code**, byte-for-byte
    (`nixos-rebuild switch`, exit-code-4 handling, `Reboot now? [y/N]:`
    prompt).

## Why this addresses the actual bug

Confirmed on real hardware earlier in this session: a live `nixos-rebuild
switch` between GDM and greetd left the old display manager (GDM) running
under the newly-aliased `greetd.service` unit name; `coredumpctl` showed the
GDM binary itself crashing there. `nixos-rebuild boot` never attempts to
restart any running service — it only updates static activation state and the
bootloader entry — so this class of failure cannot occur on the path this
change adds. The DE only ever takes effect via a real, clean boot.

## Verification

No `.nix` files were touched, so Nix eval/dry-build/preflight (which validate
NixOS configuration) don't apply here — this is shell tooling. `just` itself
is not installed in this environment (`which just` → not found, WSL), so
verification was done at the level that's actually available:

1. **`bash -n`** on the extracted recipe body — syntactically valid.
2. **Manual execution trace**, with `sudo`/`nixos-rebuild`/`systemctl`/`just`
   stubbed to no-ops, across four scenarios:

| Scenario | Expected | Observed |
|---|---|---|
| No `features.nix`, request `hyprland` (gnome→hyprland, a real change) | `boot` + forced reboot | ✓ `Desktop environment is changing: gnome -> hyprland`, `nixos-rebuild boot`, `sudo systemctl reboot` fired |
| `features.nix` already `hyprland`, request `hyprland` again (no change) | untouched `switch` path | ✓ `nixos-rebuild switch`, `Reboot now?` prompt reached, "Skipped" on stubbed "no" |
| `features.nix` has `hyprland`, request `gnome` (a real change, reverse direction) | `boot` + forced reboot | ✓ `Desktop environment is changing: hyprland -> gnome`, `nixos-rebuild boot` fired |
| Non-desktop role (`server`) | DE logic never runs at all | ✓ went straight to normal `switch` path, no DE branch entered |

All four match the intended design. The reverse-direction case (scenario 3)
matters specifically because it proves this isn't a one-way "entering
Hyprland/COSMIC" special case — it correctly protects a switch back to GNOME
too, which is exactly the direction the user needed after Hyprland/COSMIC
failed in this thread.

## Checklist

| Category | Result |
|---|---|
| Specification compliance | Matches spec |
| Best practices | Reuses the existing `vexos\.desktop\.environment\s*=\s*"[a-z]+"` shape already depended on by the recipe's own pre-existing sed rewrite, not a new pattern |
| Consistency | Non-DE-changing path is untouched, not just "equivalent" — same code, same lines |
| Blast radius | Only fires when `ROLE=desktop` AND the DE is actually changing; every other invocation of `just switch` behaves exactly as before |
| Maintainability | Comment states the *why* (the specific coredump evidence from earlier in this session), not a restatement of the code |

## What is NOT verified

No `just` binary and no NixOS host in this environment means the recipe has
never actually been run by `just` itself — only via a hand-built stub harness
that reproduces its control flow. The real `nixos-rebuild boot` behavior
(does it actually set the correct boot entry, does the subsequent reboot
actually land on the new DE) has not been observed. Confirm with a real
`just switch desktop vm "" hyprland` on the target host.

## Verdict

**APPROVED**, pending a real run on the target host. Logic verified correct
across four scenarios including the reverse-direction case; syntax verified;
root cause (live display-manager restart) directly ties back to evidence
already gathered in this session, not new speculation.
