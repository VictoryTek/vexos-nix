# M-10 — `elevator=kyber` boot parameter removed in kernel 5.0

Status: Phase 1 (Research & Specification)
Source: MASTER_PLAN M-10 · `modules/system.nix:91-95`

## Current State

```nix
boot.kernelParams = [
  # I/O scheduler: Kyber is low-latency; well suited for NVMe SSDs.
  # Override per-device via udev if mixing SSDs and HDDs.
  "elevator=kyber"
];
```

The `elevator=` kernel command-line parameter was removed upstream in Linux 5.0 (the
multi-queue block layer replaced the legacy single-queue scheduler framework that
parameter configured). This project runs kernel 6.x (`linuxPackages_latest` for
desktop/htpc/stateless roles, 6.12 LTS for server/htpc via
`system-lts-kernel.nix`) — well past that removal. The kernel silently ignores unknown
command-line parameters, so this is a no-op today: no I/O scheduler is being explicitly
set at all, contrary to the comment's stated intent.

## Problem Definition

Set the Kyber I/O scheduler using the current, supported mechanism.

## Proposed Solution

Replace the dead boot parameter with a udev rule that sets the scheduler via sysfs at
device-add time, exactly as the MASTER_PLAN specifies:
`ACTION=="add|change", KERNEL=="nvme*|sd*", ATTR{queue/scheduler}="kyber"`.
`services.udev.extraRules` is `type = lib.types.lines` (mergeable across multiple
module definitions, confirmed against the pinned nixpkgs udev module) — safe to add a
second definition here alongside `modules/gaming.nix`'s own unrelated
`services.udev.extraRules` block; NixOS concatenates them.

## Implementation Steps

1. `modules/system.nix` — remove `"elevator=kyber"` from `boot.kernelParams`; add a
   `services.udev.extraRules` entry with the rule above.

## Configuration Changes

None.

## Risks and Mitigations

- **Rotational (spinning) disks** — the rule matches `sd*` broadly (not just SSDs);
  Kyber is a low-latency scheduler generally tuned for fast (SSD/NVMe) devices, and
  rotational disks are typically better served by `bfq`/`mq-deadline`. The MASTER_PLAN's
  own suggested rule doesn't distinguish rotational vs non-rotational, and this project's
  existing comment already frames Kyber as "well suited for NVMe SSDs" without hedging
  for spinning disks — kept as specified rather than expanding scope to add a rotational
  check not present in the original request.
- **Verify the merge is actually safe** — confirmed via a synthetic build combining
  `modules/system.nix` and `modules/gaming.nix` together (as they already are in every
  real role config) and checking the final `services.udev.extraRules` string contains
  both this rule and gaming.nix's controller rules.
