# L-12 — nvidia-vaapi-driver incorrectly gated on variant == "latest"

Status: Phase 1 (Research & Specification)
Source: MASTER_PLAN L-12 (BUGS L16) · `modules/gpu/nvidia.nix:90-93`
(current file: the gate is at lines 66-71; line numbers have drifted
but the logic matches)

## Current State

`modules/gpu/nvidia.nix:14-24, 66-71`:
```nix
useOpen = variant == "latest";
...
# nvidia-vaapi-driver provides VA-API via NVDEC.
# NVDEC support is present only on Turing (RTX 20xx) and newer.
# Excluded for legacy_535 to avoid broken hardware acceleration.
hardware.graphics.extraPackages = lib.mkIf useOpen (
  with pkgs; [ nvidia-vaapi-driver ]
);
```

`nvidia-vaapi-driver` is only installed when `variant == "latest"`,
i.e. never for `legacy_535`.

The plan's suggested fix (`gate on variant != legacy_470`) targets a
variant value that **no longer exists in this codebase** — `legacy_470`
was removed entirely earlier this session (H-02, Kepler dropped to
match Bazzite's driver model). With `legacy_470` gone,
`vexos.gpu.nvidiaDriverVariant` only accepts two values: `"latest"` and
`"legacy_535"` (confirmed via the option's `enum` type at line 29).
Porting the plan's literal suggestion forward (`variant != legacy_470`)
against the current two-value enum evaluates to `true` unconditionally
— i.e. it is equivalent to removing the gate entirely.

**Verified the underlying hardware claim directly** (not assuming from
the file's own comment) via NVIDIA's official driver documentation:
NVIDIA's 535 driver branch — what this repo's `legacy_535` variant
maps to (`config.boot.kernelPackages.nvidiaPackages.legacy_535`) —
supports Maxwell, Pascal, Volta, **Turing, Ampere, and Ada Lovelace**.
It is not restricted to pre-Turing hardware; it is a broad,
still-actively-maintained production branch that happens to also cover
the older architectures nixpkgs' `"latest"`/stable branch has since
dropped. This repo's own option documentation already says as much for
the *other* direction ("These GPUs [Maxwell/Pascal/Volta] work equally
well with 'latest'; this variant is NOT required") — confirming variant
choice here is a **user preference** (LTS branch vs. current
production), not a hardware-capability boundary. A user with an RTX
30-series (Turing-successor Ampere) card can legitimately choose
`legacy_535` for LTS stability and still have full NVDEC hardware.

Also verified `nvidia-vaapi-driver` itself (upstream project docs/
issues): it targets Turing+ GPUs specifically, and gracefully falls
back to software decode when the underlying hardware/driver doesn't
support the NVDEC path it needs — it does not crash or misbehave on
unsupported hardware, it is simply inert.

So: (1) the variant a user chose carries no reliable signal about
whether their GPU has NVDEC, and (2) installing the package on hardware
that lacks NVDEC is harmless (software-decode fallback, matching the
behavior every other iGPU/dGPU vaapi package in this style of
repo already relies on). There is no safe, accurate condition left to
gate on with the information available at this module's scope —
the correct fix is to stop gating on `variant`/`useOpen` at all.

## Problem Definition

`nvidia-vaapi-driver` is withheld from every `legacy_535` user,
including those running Turing/Ampere/Ada hardware that fully supports
NVDEC and would benefit from it — because the gate conflates "which
driver release branch was chosen" with "which GPU generation is
installed," two things this repo does not actually track together.

## Proposed Solution

Install `nvidia-vaapi-driver` unconditionally for every user of this
module (both `"latest"` and `"legacy_535"`), since:
- it is safe/inert on hardware that lacks NVDEC (confirmed upstream
  behavior — software fallback, not a crash), and
- there is no variant-based signal left to gate on now that
  `legacy_470` (the one variant that reliably meant "no NVDEC") has
  been removed from this repo.

This differs from the plan's literal suggestion (`variant !=
legacy_470`) only in form, not outcome — that suggestion, applied to
the current two-value enum, is exactly equivalent to "always install."

## Implementation Steps

1. `modules/gpu/nvidia.nix` — remove the `lib.mkIf useOpen (...)`
   wrapper around `hardware.graphics.extraPackages`; assign
   `with pkgs; [ nvidia-vaapi-driver ]` unconditionally.
2. Update the stale comment above it (currently claims exclusion for
   `legacy_535` "to avoid broken hardware acceleration") to instead
   note that variant choice doesn't correlate with GPU generation here,
   and that the package is a documented no-op/software-fallback on
   hardware without NVDEC.
3. Leave `useOpen`/`open = useOpen` untouched — that gate is legitimate
   (open kernel modules genuinely do require Turing+ per NVIDIA's own
   `open` kernel module support matrix, a separate and correctly-scoped
   concern from VA-API package installation).

## Configuration Changes

None — no new NixOS options; only changes an existing package-list
condition.

## Risks and Mitigations

- **Risk:** installing `nvidia-vaapi-driver` for a genuinely pre-Turing
  `legacy_535` user (Maxwell/Pascal/Volta) adds a package that does
  nothing useful for them.
  **Mitigation:** confirmed upstream this is harmless — the driver
  detects lack of NVDEC support and falls back to software decode; it
  does not break existing hardware acceleration or introduce
  misbehavior. The cost is a few extra store-path bytes in
  `hardware.graphics.extraPackages`, not a functional regression.
- **Risk:** `useOpen`/proprietary-kernel-module interaction —
  confirmed NVDEC access via NVIDIA's userspace libraries functions
  independently of whether open or proprietary kernel modules are
  loaded; `useOpen` genuinely gates a different concern (open kernel
  module hardware support) and is correctly left untouched.
