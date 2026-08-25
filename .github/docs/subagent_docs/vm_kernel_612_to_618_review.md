# Bump VM guest kernel pin from 6.12 to 6.18 LTS — Review

## Modified files
- `modules/gpu/vm-guest-additions.nix`
- `modules/system-custom-kernel.nix` (one stale comment)

## Verification (WSL, nix 2.34.1)

| Check | Result |
|---|---|
| `nix eval` — `vexos-desktop-vm` (hyprland override) resolved kernel | `6.12.105` → **`6.18.46`** |
| `nix eval` — toplevel still evaluates | ✓ |
| **`nix build`** (not just eval) — `virtualboxGuestAdditions` under the new pin | ✓ **`VirtualBox-GuestAdditions-7.2.14-6.18.46`, exit 0** — the actual failure mode this file exists to prevent, directly tested, not assumed |
| `vexos-server-vm` resolved kernel | `6.18.46` |
| `vexos-headless-server-vm` resolved kernel | `6.18.46` |
| `vexos-htpc-vm` resolved kernel | `6.18.46` |
| `vexos-stateless-vm` resolved kernel | `6.18.46` |
| `vexos-desktop-vm` resolved kernel | `6.18.46` |
| `vexos-vanilla-vm` | Unaffected — does not import this file (pre-existing, separate inconsistency; noted, not touched) |
| `bash scripts/preflight.sh` | ✓ **PASSED, exit 0** |

## Why 6.18 over `linuxPackages_latest`

The user asked specifically about the LTS angle. Confirmed via search:
kernel.org extended 6.18's LTS support to December 2028 in a February 2026
announcement — the same end-of-life date as 6.12. This is a same-tier LTS
swap, not a move to the less conservative `linuxPackages_latest`/mainline
track that `system-latest-kernel.nix` uses for non-VM desktop/stateless hosts.
6.18 is six minor kernel versions newer than 6.12 — substantially closer to
the confirmed-working comparison VM's 7.1.9 — while keeping the LTS posture.

## What this does NOT confirm

This is still a hypothesis, clearly stated as such. It is well-evidenced (a
real comparison VM on the same hypervisor, same "Default" display, same
Aquamarine-based Hyprland, working on a much newer kernel) but not proven.
Evaluation and an actual package build confirm this change is *safe* — it
does not break anything, on any of the five affected roles, and the specific
build failure this pin exists to prevent does not reappear on 6.18. Whether it
actually produces `/dev/dri/renderD128` on this VM's bochs-drm device, and
whether Hyprland/COSMIC then render correctly, can only be confirmed by a real
boot — which cannot happen from this environment.

## Checklist

| Category | Result |
|---|---|
| Specification compliance | Matches spec |
| Best practices | Reuses the exact existing overlay/pin pattern, just retargeted; no new abstraction |
| Consistency | No new `lib.mkIf` guard; priority ladder (documented in `system-custom-kernel.nix`) unchanged, only the value at priority 50 changed |
| Blast radius | Scoped correctly — confirmed via inspection that `vanilla-vm` doesn't import this file, so it's unaffected; the four other roles' shift from 6.12→6.18 is a direct, expected, and verified consequence of the shared pin, not a surprise |
| Maintainability | Comment explains the *why* with the actual evidence (Omarchy comparison, EGL error text, LTS EOL parity), not a restatement |
| `hardware-configuration.nix` / `stateVersion` | Untouched |
| Flake inputs | None added |

## Verdict

**APPROVED**, pending a real boot test — which the user cannot currently
perform since the VM in question won't boot into a usable state. Safety of
the change itself (evaluates cleanly, the one real build-failure risk
directly tested and confirmed clean, no regression across five roles,
preflight exit 0) is fully verified from this environment. Whether it
actually resolves the render-node problem is not yet known and is stated as
such, not claimed.
