# Runtime warning for missing GPU render node on VM Hyprland/COSMIC hosts — Spec

## Current state analysis

Confirmed by direct log evidence on a real Proxmox guest (not inferred): with
the VM's display device set to Proxmox's default "Standard VGA" (`bochs-drm`),
`/dev/dri/` contains only `card1` — no `renderD128`. COSMIC's session fails
with explicit EGL/MESA errors:

```
cosmic-session: libEGL warning: failed to get driver name for fd -1
cosmic-panel:   [EGL] 0x3003 (BAD_ALLOC) eglInitialize: DRI2: failed to get driver name
cosmic-session: libEGL warning: MESA-LOADER: failed to retrieve device information
cosmic-session: MESA: error: ZINK: failed to choose pdev
cosmic-session: libEGL warning: egl: failed to create dri2 screen
```

`xdg-desktop-portal-cosmic` then SIGABRTs. The prior Hyprland investigation in
this same thread almost certainly hit the same underlying cause. GNOME/Mutter
is confirmed to work on the identical guest/device — it tolerates the missing
render node via a more permissive software (llvmpipe) fallback path that
wlroots (Hyprland) and Smithay/cosmic-comp (COSMIC) do not have.

This is a hypervisor display-device setting (Proxmox: VM → Hardware → Display
→ VirtIO-GPU with 3D/VirGL), not something any NixOS config can create. It
cannot be detected at Nix eval time — render-node availability is a property
of the running hypervisor's virtual hardware, not of anything declared in this
flake.

## Problem definition

Without a render node, Hyprland/COSMIC currently fail silently at the
compositor/portal level: black screen, blinking cursor, with the actual EGL
error only visible via `journalctl` after SSHing in — exactly what made this
thread's live investigation slow. The user asked for this not to silently
happen to future VMs.

## Proposed solution architecture

A systemd runtime check, not a build-time assertion (the latter is impossible
here — eval has no access to the target machine's virtual hardware). Added to
`modules/gpu/vm.nix` (the shared base every `gpu=vm` host imports):

```nix
let
  needsRenderNode = config.programs.hyprland.enable
                  || config.services.desktopManager.cosmic.enable;
in
{
  systemd.services.vexos-vm-render-node-check = lib.mkIf needsRenderNode {
    wantedBy = [ "graphical.target" ];
    before   = [ "greetd.service" ];
    unitConfig.ConditionPathExists = "!/dev/dri/renderD128";
    serviceConfig = { Type = "oneshot"; RemainAfterExit = true; };
    script = ''
      MSG="No GPU render node (/dev/dri/renderD128) found. ..."
      echo "vexos: $MSG" >&2
      if ${pkgs.plymouth}/bin/plymouth --ping 2>/dev/null; then
        ${pkgs.plymouth}/bin/plymouth display-message --text="$MSG"
        ${pkgs.coreutils}/bin/sleep 15
      fi
    '';
  };
}
```

Design choices, and why:

- **Gated on `programs.hyprland.enable` / `services.desktopManager.cosmic.enable`
  directly, not `vexos.desktop.environment`.** Those two nixpkgs options are
  always declared (core NixOS modules, default `false`) regardless of which
  vexos role/config imports what, and they only become `true` when the actual
  compositor is wired up (`hyprland-desktop.nix`/`cosmic-desktop.nix`, imported
  only by `configuration-desktop.nix`). Using `vexos.desktop.environment`
  instead would risk a false-positive warning on a role where that option is
  set but the corresponding DE module was never imported, and would also
  require an `or "gnome"` eval-safety fallback for roles (headless-server,
  vanilla) that never declare it at all. Checking the real "is it actually
  going to start" option avoids both problems.
- **`ConditionPathExists = "!/dev/dri/renderD128"`** — the unit only runs (and
  the check only fires) when the render node is genuinely absent. No effect at
  all on a correctly configured VirtIO-GPU-3D host.
- **Warns, does not block.** greetd starts exactly as it does today either way.
  This can only make a broken boot's failure visible sooner; it cannot turn a
  working boot into a broken one.
- **`plymouth --ping` guard before `display-message`** — confirmed via the
  Plymouth manpage that `--ping` checks whether `plymouthd` is running; skips
  the message cleanly (falls through to the `echo` already written to stderr,
  captured by the journal) if Plymouth isn't active for any reason, rather than
  erroring.
- **15-second sleep after the message** — long enough to actually read it
  before greetd's own (already-observed) crash-loop output starts scrolling.

## Implementation steps (Option B)

- `modules/gpu/vm.nix` only. NOT added to `modules/gpu/vanilla-vm.nix`: the
  vanilla role never imports `hyprland-desktop.nix`/`cosmic-desktop.nix` and
  hardcodes GDM directly in `configuration-vanilla.nix`, so
  `programs.hyprland.enable`/`services.desktopManager.cosmic.enable` can never
  be `true` there — the check would be permanently inert dead code in that
  file. Per the "surgical changes" principle, it isn't added where it can never
  fire.
- Function signature widened from `{ config, lib, ... }:` to
  `{ config, lib, pkgs, ... }:` (need `pkgs.plymouth`, `pkgs.coreutils`).
- No new `lib.mkIf` role/display/gaming guard on a *shared* module in the
  problematic sense — `modules/gpu/vm.nix` is already the VM-specific base, and
  the `mkIf needsRenderNode` here gates content by an option this same file's
  logic reads to decide its own runtime behaviour, not by role/display/gaming
  flags.

## Dependencies

None new. `pkgs.plymouth` is already pulled in by `boot.plymouth.enable = true`
(set in `configuration-desktop.nix`, the only role that currently imports the
Hyprland/COSMIC modules). `pkgs.coreutils` is always present.

## Risks and mitigations

- **Risk:** message could be missed if the user isn't watching the console at
  that exact moment. **Mitigation:** also written to `stderr`/journal via
  `echo`, so `journalctl -b` shows it regardless; not the primary delivery
  mechanism but a durable fallback.
- **Risk:** cannot be verified against real Plymouth rendering behaviour from
  this environment (no NixOS host, no Plymouth to actually observe). Verified
  only via `nix eval` (unit exists, condition/gating correct, builds) and
  preflight. Real on-screen behaviour needs a boot on real Proxmox hardware
  with the render node genuinely absent to fully confirm.
- **Risk:** false negative if `/dev/dri/renderD128` isn't the only possible
  render-node path on some hardware (e.g. `renderD129` on a multi-GPU host).
  **Mitigation:** scoped to `gpu=vm` hosts only, which have at most one virtual
  display device, so `renderD128` (the first render node) is the correct and
  only path to check in this context.
