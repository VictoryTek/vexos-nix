# Sunshine (Moonlight host) — Specification

**Feature name:** `sunshine_remote_desktop`
**Date:** 2026-07-19

## Current State Analysis

vexos already has GNOME Remote Desktop (RDP) via `modules/remote-desktop.nix`, now
working after two root-cause fixes (keyring/grd rebind ordering; the
`allow-locked-remote-desktop` extension). User wants an additional, simpler-to-reason-
about option: Sunshine (self-hosted Moonlight game-stream host), explicitly accepting
reduced security for reliability/simplicity, and explicitly requiring it to work
across every GPU variant this distro supports (`amd`, `nvidia`, `nvidia-legacy535`,
`intel`, `vm`) since vexos targets arbitrary hardware.

Verified via nixpkgs, the actual NixOS module source, and vendor docs:
- `pkgs.sunshine` — nixpkgs version 2026.516.143833, **binary cached** (9.8 MB, no
  local compile).
- NixOS ships a real `services.sunshine` module
  (`nixos/modules/services/networking/sunshine.nix`, inspected directly from the
  nixpkgs source tree pinned by this flake). Key facts from reading the module:
  - Runs as a **systemd user service** (`systemd.user.services.sunshine`) wired to
    `graphical-session.target` — starts automatically with the graphical session,
    no custom root service or D-Bus keyring dance needed (unlike RDP).
  - `hardware.uinput.enable = true` is set **unconditionally by the module itself**
    when `services.sunshine.enable = true` — no need to set it ourselves. The user's
    account still needs `extraGroups = [ "uinput" ]` added manually — the module
    does not do this.
  - `openFirewall = true` opens the full correct TCP/UDP port set computed as
    offsets from `settings.port` (default 47989) — do not hand-roll firewall rules.
  - `capSysAdmin = true` wraps the binary with `cap_sys_admin+p` via
    `security.wrappers.sunshine`, required for DRM/KMS screen capture on Wayland.
  - `services.avahi` is enabled by the module (`mkDefault true`) for LAN discovery;
    harmless alongside this repo's existing Avahi/mDNS baseline
    (`modules/network.nix`).
  - **No declarative WebUI admin credentials** — confirmed from Sunshine's own docs.
    First-run web wizard creates the admin account; this is an unavoidable one-time
    manual step, not something Nix or a `just` recipe can automate away.
- Capture method: on GNOME/Mutter (non-wlroots) Wayland, **KMS is the only reliable
  capture path** — the portal-based (`xdg-desktop-portal`) path has multiple open
  upstream issues on GNOME specifically ("fails to detect display and encoder on
  nvidia + wayland", "None working encoder is usable on wayland"). `capture = "kms"`
  is therefore set universally, not per-GPU.
- Encoder is GPU-brand-specific and belongs in `modules/gpu/*.nix`, matching this
  repo's existing pattern for GPU-brand config:
  - NVIDIA (`nvidia.nix`, also covers `nvidia-legacy535` via the existing
    `nvidiaVariant` parameter — confirmed in `flake.nix`, no separate legacy535
    module file exists) → `encoder = "nvenc"`.
  - AMD (`amd.nix`) → `encoder = "vaapi"` (AMD has no Linux-native "amf" encoder
    path in Sunshine; VA-API is the correct Linux AMD hardware-encode route).
  - Intel (`intel.nix`) → `encoder = "quicksync"`.
  - VM (`vm.nix`, `vanilla-vm.nix`) → **left unset** (auto-detect/software
    fallback). See Risks below — this is a real, documented, unresolved-by-config
    limitation, not an oversight.
- **Lock-screen correction**: earlier tonight this repo's `modules/gnome.nix` was
  incorrectly described as auto-locking the screen after idle. Re-verified directly:
  `org/gnome/desktop/screensaver.lock-enabled = false` — locking is already
  disabled. `org/gnome/session.idle-delay = 300` only affects idle/blank state, not
  locking. User explicitly declined to also disable idle-delay tonight; left as-is.

## Problem Definition

Add Sunshine as a Moonlight-compatible remote desktop / game-stream host across all
GPU variants, alongside (not replacing) the existing RDP setup, with a `just`
recipe to help with first-time setup.

## Proposed Solution Architecture

New universal module `modules/sunshine.nix`, imported by the same three roles as
`modules/remote-desktop.nix` (`configuration-desktop.nix`,
`configuration-server.nix`, `configuration-htpc.nix` — not stateless, matching
`remote-desktop.nix`'s precedent of excluding tmpfs-home roles where state
[Sunshine's paired-client list] would not persist across reboots without extra
impermanence config):

```nix
services.sunshine = {
  enable = true;
  autoStart = true;
  capSysAdmin = true;
  openFirewall = true;
  settings.capture = "kms";
};
users.users.${config.vexos.user.name}.extraGroups = [ "uinput" ];
```

GPU-specific `encoder` settings added to the respective `modules/gpu/*.nix` files
(Module Architecture Pattern Option B: this is exactly the kind of GPU-brand-specific
addition those files already exist for — no `lib.mkIf` role-gating, just per-file
brand-specific config, matching every existing example in those files).

`just enable-sunshine` recipe (System Administration group, matching `setup-rdp`'s
placement): Sunshine has no per-host Nix-level "enable" toggle to flip (it's always
on wherever the module is imported, matching RDP's existing precedent) and no
credential file to write — so unlike `setup-rdp`, there is nothing for this recipe
to configure. Its job is to surface the two things a user must do manually and
cannot be scripted: open the WebUI to create the admin account, and note this
machine's Tailscale IP for adding the host in Moonlight.

## Implementation Steps

1. Create `modules/sunshine.nix` (universal base for desktop/server/htpc).
2. Import it in `configuration-desktop.nix`, `configuration-server.nix`,
   `configuration-htpc.nix`, alongside the existing `remote-desktop.nix` import.
3. Add `services.sunshine.settings.encoder = "nvenc";` to `modules/gpu/nvidia.nix`.
4. Add `services.sunshine.settings.encoder = "vaapi";` to `modules/gpu/amd.nix`.
5. Add `services.sunshine.settings.encoder = "quicksync";` to
   `modules/gpu/intel.nix`.
6. Add a comment (no encoder override) to `modules/gpu/vm.nix` and
   `modules/gpu/vanilla-vm.nix` documenting the known KMS-in-VM capture risk.
7. Add `enable-sunshine` recipe to `justfile`, System Administration group.

## Dependencies

- `pkgs.sunshine` — nixpkgs, binary cached, no new flake inputs.

## Risks and Mitigations

- **Risk (real, not fully resolved by this change): VM/virtio-GPU KMS capture
  reliability.** Multiple sources report Sunshine's KMS capture struggling on
  virtio-GPU VMs — some setups need a dummy HDMI plug just to have a display
  surface to grab; Wayland-specific guidance for VMs is thin compared to bare
  metal. This cannot be verified without live-testing on an actual VM instance,
  which was not available during this session. **Mitigation:** `vm.nix` /
  `vanilla-vm.nix` deliberately do not force an encoder (let Sunshine
  auto-detect/fall back to software encoding rather than hard-fail on a forced
  hardware encoder that may not exist), and the user is explicitly told this needs
  a live test on `vexos-vmc` specifically before being trusted.
- **Risk: no declarative WebUI credentials.** Confirmed from Sunshine's own docs —
  genuinely not possible to automate. Documented as a manual step in the `just`
  recipe's output rather than silently omitted.
- **Risk: KMS + `cap_sys_admin` is a broad privilege escalation surface.**
  Accepted per the user's explicit "simplify even if not secure, Tailscale-only"
  stance stated repeatedly tonight.
- **Not a risk, but worth flagging:** this coexists with the already-working RDP
  setup, not a replacement. Both `gnome-remote-desktop` and `sunshine` will be
  enabled and running simultaneously on desktop/server/htpc roles. No known
  conflict between the two (different ports, different capture/session models).

## Validation

- `nix flake show --impure`.
- `nix eval --impure` forced evaluation of `vexos-desktop-{amd,nvidia,vm}`,
  `vexos-server-amd`, `vexos-htpc-amd` (touches GPU modules + all three importing
  roles).
- `git ls-files hardware-configuration.nix` empty; `system.stateVersion` unchanged.
- `bash scripts/preflight.sh`.
- Explicitly **not** validated: live KMS capture on real hardware or in a VM (no
  such environment available in this session). Flagged to the user as a required
  live-test step before relying on this for unattended VM access.
