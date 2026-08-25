# Bump VM guest kernel pin from 6.12 to 6.18 LTS — Spec

## Current state analysis

`modules/gpu/vm-guest-additions.nix` force-pins every `gpu=vm` host to
`linuxPackages_6_12` via `boot.kernelPackages = lib.mkForce ...`, for a reason
entirely about a VirtualBox Guest Additions build failure — unrelated to the
kernel's DRM driver behaviour. This pin currently overrides desktop/stateless
roles' intended `linuxPackages_latest` (via `system-latest-kernel.nix`) down to
6.12, and (via `mkForce`, priority 50, the highest in the repo's own documented
kernel-priority ladder) cannot be beaten by any role-level choice.

Directly confirmed on real hardware earlier in this investigation: a Proxmox
guest on this 6.12-pinned kernel, with the hypervisor's default (Standard VGA
/ bochs-drm, no 3D acceleration) display, exposes `/dev/dri/card1` but **no**
`/dev/dri/renderD128`. Hyprland (Aquamarine backend — confirmed to have no
software-rendering fallback via its own `docs/env.md`) and COSMIC
(Smithay/cosmic-comp — confirmed via direct EGL/MESA errors:
`failed to get driver name for fd -1`, `MESA: error: ZINK: failed to choose
pdev`) both fail to render as a result. GNOME/Mutter tolerates the missing
render node and works on the identical guest.

## Problem definition

A second VM on the **same Proxmox host**, same "Default" display setting,
running the same Aquamarine-based Hyprland (0.56.2 vs our 0.55.4 — comparable,
not older) but on kernel **7.1.9**, renders correctly. This points at the
kernel/DRM-driver version, not the hypervisor's display configuration, as the
actual variable between "works" and "doesn't."

## Proposed solution architecture

Bump the pin from 6.12 to **6.18** — confirmed via web search that kernel.org
extended LTS support for 6.18 to December 2028 in a February 2026 announcement
(the same EOL date as 6.12), so this is a like-for-like LTS swap, not a move
onto a less conservative track. 6.18 is far closer to the confirmed-working
7.1.9 than 6.12 is (6 minor kernel versions of DRM/driver work), while still
being the newest kernel on the LTS branch rather than jumping to
`linuxPackages_latest` (a legitimate alternative, but a materially different
stability posture the user did not ask for).

`vm-guest-additions.nix`'s own existing comment already answers whether 6.18
is safe for the VirtualBox Guest Additions build: *"does not build against ANY
kernel packaged in our nixpkgs pin (verified 6.6 / 6.12 / 6.18 / 7.1)"* — the
build failure is present on 6.18 exactly as it is on 6.12, and the existing
`KERN_MAJ = 99` patch that fixes it is kernel-version-agnostic (it just strips
a broken out-of-tree Makefile target, not a version-specific workaround). So
the fix is: point the same overlay at `linuxPackages_6_18` instead of
`linuxPackages_6_12`, and change the pin.

## Implementation steps

- `modules/gpu/vm-guest-additions.nix`: overlay's `linuxPackages_6_12` entry
  and the final `boot.kernelPackages` assignment both changed to `_6_18`.
  Comments updated to explain the swap and cite the specific evidence (the
  Omarchy comparison, the EGL error text, the LTS EOL-date parity).
- `modules/system-custom-kernel.nix`: one comment corrected (still said
  "6.12" describing this same pin).
- No new `lib.mkIf` guard, no new option, no new dependency — a value swap in
  an existing override plus its overlay target.

## Scope / blast radius

`modules/gpu/vm-guest-additions.nix` is imported only by `modules/gpu/vm.nix`
(NOT `vanilla-vm.nix` — confirmed by inspection that `hosts/vanilla-vm.nix`
does not import `modules/gpu/vanilla-vm.nix` at all and sets its VM-guest
settings inline, a pre-existing inconsistency noted but out of scope for this
change). Affects every role built on `gpu=vm` via `vm.nix`: desktop, server,
headless-server, htpc, stateless. `server`/`headless-server`/`htpc` also
import `system-lts-kernel.nix` (`linuxPackages_6_12`, priority 100) — the VM
pin (priority 50) already won over that before this change, so those three
roles move from 6.12 → 6.18 as a side effect of this same bump, not a separate
decision. `system-lts-kernel.nix` itself is untouched, so any non-VM host on
those roles is unaffected.

## Risks and mitigations

- **Risk: does 6.18 actually fix the render-node problem?** Not confirmed —
  this is still a hypothesis, strongly evidenced (kernel-version gap matches
  the working comparison VM, LTS-to-LTS swap is a conservative change) but not
  proven until a real boot. Cannot be tested further from this environment
  (no NixOS host).
- **Risk: does the VirtualBox Guest Additions build still work on 6.18?**
  **Directly verified**, not assumed — actually built (not just evaluated)
  `config.boot.kernelPackages.virtualboxGuestAdditions` for the hyprland
  override of `vexos-desktop-vm` in WSL; it compiled successfully
  (`VirtualBox-GuestAdditions-7.2.14-6.18.46`, exit 0). This is the one thing
  `nix eval` alone cannot prove (it doesn't compile anything), so it was
  checked with an actual `nix build`.
- **Risk: regression on non-desktop VM roles.** Checked via eval: all five
  affected configurations (desktop-vm, server-vm, headless-server-vm, htpc-vm,
  stateless-vm) now uniformly resolve to `6.18.46`; none regressed to a
  different or broken value.
