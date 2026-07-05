# M-37 — NixOS VM boot test to gate `nixpkgs-unstable` bumps

Status: Phase 1 (Research & Specification)
Source: MASTER_PLAN M-37 (FEATURES 4.2)

## Current State

`README.md`'s "Updating nixpkgs-unstable (GNOME stack)" section documents a
manual procedure: bump `nixpkgs-unstable`, dry-build `vexos-desktop-vm`, then
**manually** boot the VM in GNOME Boxes/virt-manager and eyeball whether GDM
shows a black screen. H-01 (this session, earlier) confirmed CI already
auto-updates `nixpkgs-unstable` daily with no gate — this item automates the
manual visual-inspection step with a real, scriptable boot test.

Checked the relevant APIs/tooling directly against the pinned nixpkgs rather
than assuming:
- `pkgs.nixosTest` (the classic top-level name) now `throw`s:
  `"'nixosTest' has been renamed to/replaced by 'testers.nixosTest'"` — the
  spec's exact suggested attribute name (`checks.x86_64-linux.gnome-boot`)
  still applies, just needs `pkgs.testers.nixosTest` internally.
- Confirmed `testers.nixosTest`'s calling convention against its own
  source (`pkgs/build-support/testers/default.nix`) — same
  `{ name, nodes, testScript, ... }` shape the classic API used, just
  reached via `testers.nixosTest { ... }` instead of the removed alias.
- `modules/gnome.nix` **already** configures `services.displayManager.gdm.enable`
  and `services.displayManager.autoLogin.user = config.vexos.user.name`
  unconditionally — the real `vexos-desktop-vm` config already boots
  straight to an auto-logged-in GNOME session. No test-only autologin
  override is needed; the test can reuse the exact real module composition.
- `roles.desktop.baseModules` (used by `mkHost`) is just
  `commonBase ++ [ upModule ]` (`commonBase` = the two overlay modules) —
  GNOME/display-manager setup lives entirely in `configuration-desktop.nix`
  (imported by `hosts/desktop-vm.nix`), so reusing
  `roles.desktop.baseModules ++ [ (mkHomeManagerModule roles.desktop.homeFile) ] ++ roles.desktop.extraModules ++ roles.desktop.hostLocalModules ++ [ ./hosts/desktop-vm.nix ]`
  reproduces `vexos-desktop-vm`'s exact composition, minus the one thing
  that must be excluded: `/etc/nixos/hardware-configuration.nix` (impure,
  host-specific — nixosTest supplies its own QEMU-appropriate virtual
  hardware automatically, same as every other NixOS test).
- No other nixpkgs GNOME/Plasma test (`nixos/tests/gnome.nix`,
  `gnome-extensions.nix`, `plasma6.nix`) overrides
  `virtualisation.memorySize` — the testing framework's own default is
  already sufficient even for full desktop-environment tests, so no
  override was added here either (avoids un-demonstrated speculative
  tuning).

## Problem Definition

The only way to catch a GNOME-stack regression from an `nixpkgs-unstable`
bump today is a human manually booting a VM and looking at the screen. This
can't run in CI (or be run quickly/repeatably locally) and is easy to skip.

## Proposed Solution

Add `checks.x86_64-linux.gnome-boot` using `pkgs.testers.nixosTest`,
reusing `vexos-desktop-vm`'s real module composition (see above). The test
script boots the VM and checks for the specific failure mode a "black
screen" regression produces: `display-manager.service` and
`graphical.target` can both report "active" while the actual compositor
session never starts, so the meaningful signal is the appearance of the
logged-in user's Wayland socket (`/run/user/<uid>/wayland-0`) and a live
`gnome-shell` process — not just systemd unit state.

Per CLAUDE.md, `nix flake check` (which would build every check for every
config in parallel) stays forbidden; this new check is invoked as a single
named target only: `nix build .#checks.x86_64-linux.gnome-boot`. Updated
`README.md`'s manual procedure to run this command as an added
automated step before the manual visual VM check (kept as a fallback/final
confirmation, not removed — the automated test catches the specific
black-screen regression class, but a human check remains valuable for
anything else).

## Implementation Steps

1. `flake.nix` — add `checks.x86_64-linux.gnome-boot`, reusing
   `roles.desktop`/`mkHomeManagerModule` already bound in the same `let`.
2. `README.md` — add the `nix build .#checks.x86_64-linux.gnome-boot` step
   to the existing manual "bump nixpkgs-unstable" procedure.

## Configuration Changes

None — a new flake `checks` output only; zero change to any
`nixosConfigurations` output or its evaluated behavior.

## Risks and Mitigations

- **Risk:** the test could be flaky if GNOME Shell takes longer to start
  under the test framework's default VM resources than the wait timeout
  allows.
  **Mitigation:** used a generous 180s timeout on the Wayland-socket wait
  (vs. no explicit timeout override in nixpkgs's own, much lighter
  `gnome.nix` test) since this test boots the repo's full desktop package
  set, not a minimal GNOME Shell-only configuration. Verified in Phase 3 by
  actually running the test to completion.
- **Risk:** duplicating `mkHost`'s module-composition logic (rather than
  refactoring it into a shared helper) could drift from the real
  `vexos-desktop-vm` composition over time.
  **Mitigation:** the duplicated list is short (6 lines), directly
  references the same `roles.desktop`/`mkHomeManagerModule` bindings
  `mkHost` itself uses (not copies of their *contents*), and is scoped to
  this one specific test — a full refactor of `mkHost` to share a
  "modules-minus-hardware-config" helper was considered but rejected as
  disproportionate risk to well-tested, working code for a single new
  test's benefit (Surgical Changes principle).
