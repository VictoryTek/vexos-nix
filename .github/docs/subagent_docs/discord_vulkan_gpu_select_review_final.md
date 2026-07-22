# Discord/Vesktop crash fix — Final Review (Refinement Cycle 2)

## History

- **Initial implementation:** `MESA_VK_DEVICE_SELECT` only. Deployed, user
  reported no change.
- **Refinement cycle 1:** added `__EGL_VENDOR_LIBRARY_FILENAMES` pinned to
  the NVIDIA EGL vendor. This *did* fix the originally-diagnosed bug — the
  instant (~150ms) `failed to import supplied dmabufs: Could not bind the
  given EGLImage to a CoglTexture2D` crash on launch, verified by directly
  executing the deployed binary and the real session's `journalctl` logs.
  However the user again reported no visible improvement.
- **Root-caused via the user's actual session logs (not just synthetic
  tests) this cycle:** a second, different failure was occurring —
  `gnome-shell[1832]: WL: error in client communication (pid N)` — Mutter
  itself forcibly terminating the client's Wayland connection ~20-40
  seconds into an otherwise clean launch, producing a `Fatal Wayland
  communication error: Connection reset by peer` and a SIGTRAP coredump in
  Discord (the trap is Chromium's own `LOG(FATAL)` deliberately aborting
  after the disconnect — not a separate memory-safety bug; confirmed no
  kernel-level GPU/Xid errors in `dmesg` for the same window). This pattern
  predates all of today's changes — present in the journal since May 14,
  across multiple boots and gnome-shell instances — so it is a pre-existing
  GNOME Shell/Mutter issue, not something introduced by prior fixes.
- Web research found this exact error string reported against multiple
  other Electron apps on hybrid-NVIDIA Wayland systems (Cursor, VS Code,
  Brave), with `--ozone-platform=x11` (routing through XWayland instead of
  Mutter's native Wayland path) as the standard, cross-project workaround.

## Refinement applied (cycle 2)

Added `--add-flags "--ozone-platform=x11"` to the wrapper, plus
`__GLX_VENDOR_LIBRARY_NAME=nvidia` (the GLX-path analog of the EGL vendor
pin, relevant now that these apps render via XWayland/GLX). The existing
EGL/Vulkan pins are kept — harmless if unused by the X11 path, still
relevant to any Vulkan hardware-encode Vesktop performs for screen-share.

## Verification performed

Built both wrapped packages standalone (bypassing full system rebuild) and
ran them directly:

- **Discord:** previously died within ~20-40s of a clean launch (both under
  the cycle-1 fix and, per journal history, unpatched). With cycle 2: ran
  for 45+ seconds without the `WL: error in client communication` disconnect,
  no coredump generated (confirmed via `coredumpctl list --since`), reached
  the point of connecting to Discord's remote-auth websocket gateway — a
  full, stable, well-past-the-crash-window run.
- **Vesktop:** could not be run standalone in this test window because the
  user's real session already has a Vesktop instance running (confirmed via
  `ps aux`, PID 9664, alive and stable since prior testing) — Electron's
  single-instance lock correctly quit the second instance
  (`Vesktop is already running. Quitting...`), which is expected behavior,
  not a crash. Since Vesktop is wrapped through the identical mechanism
  as Discord and shares the same Electron/Chromium version family, the fix
  is expected to apply equally, but full screen-share behavior still
  requires the user's interactive confirmation (portal picker) after a real
  `nixos-rebuild switch`.

## Re-run build validation

- `nix eval --impure` on `vexos-desktop-nvidia` toplevel: PASS
- Standalone `nix build` of both wrapped packages: PASS
- `bash scripts/preflight.sh`: PASS (same pre-existing, unrelated WARN-level
  findings as prior cycles — repo-wide formatting gap, flake.lock staleness,
  vexboard placeholder secret string)
- No new flake inputs, no `hardware-configuration.nix` committed, no
  `stateVersion` changes.

## Score Table

| Category | Score | Grade |
|----------|-------|-------|
| Specification Compliance | 100% | A |
| Best Practices | 100% | A |
| Functionality | 95% | A (Discord crash resolved and runtime-verified past the failure window; Vesktop screen-share needs the user's interactive confirmation) |
| Code Quality | 100% | A |
| Security | 100% | A |
| Performance | 95% | A (XWayland path forgoes some native-Wayland niceties, e.g. fractional scaling, for these two apps only — acceptable tradeoff to avoid the Mutter compatibility bug) |
| Consistency | 100% | A |
| Build Success | 100% | A |

**Overall Grade: A (99%)**

## Result

**APPROVED**, with the caveat that full end-to-end confirmation (real
desktop launch, real screen-share attempt) is the user's to perform — this
session's sandbox cannot drive the GNOME session interactively. Root cause
for both original symptoms is now understood and addressed at the correct
layer (forcing XWayland to sidestep a Mutter-side Wayland protocol bug),
rather than continuing to guess at GPU-selection variables.
