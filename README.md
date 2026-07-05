
<div align="center">
   <img src="files/pixmaps/desktop/system-logo-white.png" alt="vexos-nix logo" width="200" style="height:auto;"/>
</div>

<div align="center">

# vexos-nix

</div>

Personal NixOS config (GNOME, PipeWire, latest kernel). 
Comes in five roles:
**Desktop** (full gaming/workstation stack),
**Stateless** (impermanent, minimal build, security-focused),
**Server** (GUI server with GNOME desktop + service stack),
**Headless Server** (CLI-only service stack, no GUI),
**HTPC** (media centre build).
No cloning required — `/etc/nixos` is the only working directory you need.

Each role utilizes "just" to give a variety of options. Simply type "just" in a terminal to see the options.


## Fresh install

> Assumes NixOS is installed and `hardware-configuration.nix` already exists at `/etc/nixos/`.

**1. Drop the flake wrapper into `/etc/nixos`**
   ```bash
sudo curl -fsSL -o /etc/nixos/flake.nix \
  https://raw.githubusercontent.com/VictoryTek/vexos-nix/main/template/etc-nixos-flake.nix
   ```

**2. Apply your role and GPU variant**

```bash
curl -fsSL https://raw.githubusercontent.com/VictoryTek/vexos-nix/main/scripts/install.sh | bash
```


The script asks which role and which GPU variant to install (AMD, NVIDIA, Intel, or VM), runs the build, and offers to reboot when complete. After this first build, `/etc/nixos/vexos-variant` is written automatically and kept in sync on every future rebuild.


## How it works

`/etc/nixos/flake.nix` is a tiny wrapper that pulls the full config from GitHub. Your `hardware-configuration.nix` never leaves `/etc/nixos`. On every rebuild NixOS uses the pinned version in `/etc/nixos/flake.lock`.

The running config writes `/etc/nixos/vexos-variant` (a one-line file, e.g. `vexos-desktop-amd`) on every build so tooling like vexos-updater "Up" always knows which variant is active.


## Variants
# Switching variants

You can switch between variants (and roles) at any time — no reinstall required. Simply rebuild with the new variant target using "just":


<div align="center">
   <img src="files/background_logos/desktop/fedora_darkbackground.svg" alt="Desktop Role Logo" width="300"/>
</div>

### Desktop role — full gaming/workstation stack

| Variant | Use for |
|---|---|
| `vexos-desktop-amd` | AMD GPU (RADV, ROCm, LACT) |
| `vexos-desktop-nvidia` | NVIDIA GPU (proprietary, open kernel modules) |
| `vexos-desktop-nvidia-legacy535` | NVIDIA Maxwell/Pascal/Volta legacy — LTS alternative (535.x driver) |
| `vexos-desktop-intel` | Intel iGPU or Arc dGPU |
| `vexos-desktop-vm` | QEMU/KVM or VirtualBox guest |

> just switch desktop amd          # direct (any GPU variant)
> just switch                      # interactive prompt





<div align="center">
   <img src="files/background_logos/stateless/fedora_darkbackground.svg" alt="Stateless Role Logo" width="300"/>
</div>

### Stateless role — minimal build (no gaming / dev / virt / ASUS)

| Variant | Use for |
|---|---|
| `vexos-stateless-amd` | AMD GPU, minimal stack |
| `vexos-stateless-nvidia` | NVIDIA GPU, minimal stack |
| `vexos-stateless-nvidia-legacy535` | NVIDIA Maxwell/Pascal/Volta legacy, minimal stack |
| `vexos-stateless-intel` | Intel iGPU or Arc dGPU, minimal stack |
| `vexos-stateless-vm` | QEMU/KVM or VirtualBox guest, minimal stack |

> just switch stateless amd        # direct (any GPU variant)
> just switch                      # interactive prompt





<div align="center">
   <img src="files/background_logos/server/fedora_darkbackground.svg" alt="Server Role Logo" width="300"/>
</div>

### GUI Server role — GNOME desktop + service stack

| Variant | Use for |
|---|---|
| `vexos-server-amd` | AMD GPU |
| `vexos-server-nvidia` | NVIDIA GPU |
| `vexos-server-nvidia-legacy535` | NVIDIA Maxwell/Pascal/Volta legacy |
| `vexos-server-intel` | Intel iGPU or Arc dGPU |
| `vexos-server-vm` | QEMU/KVM or VirtualBox guest |

### Headless Server role — CLI only service stack

| Variant | Use for |
|---|---|
| `vexos-headless-server-amd` | AMD GPU |
| `vexos-headless-server-nvidia` | NVIDIA GPU |
| `vexos-headless-server-nvidia-legacy535` | NVIDIA Maxwell/Pascal/Volta legacy |
| `vexos-headless-server-intel` | Intel iGPU or Arc dGPU |
| `vexos-headless-server-vm` | QEMU/KVM or VirtualBox guest |

> just switch server amd           # direct (any GPU variant)
> just switch                      # interactive prompt





<div align="center">
   <img src="files/background_logos/htpc/fedora_darkbackground.svg" alt="HTPC Role Logo" width="300"/>
</div>

### HTPC role — media centre build

| Variant | Use for |
|---|---|
| `vexos-htpc-amd` | AMD GPU |
| `vexos-htpc-nvidia` | NVIDIA GPU |
| `vexos-htpc-nvidia-legacy535` | NVIDIA Maxwell/Pascal/Volta legacy |
| `vexos-htpc-intel` | Intel iGPU or Arc dGPU |
| `vexos-htpc-vm` | QEMU/KVM or VirtualBox guest |

> just switch htpc amd             # direct (any GPU variant)
> just switch                      # interactive prompt


> **Switching GPU drivers?** A reboot is recommended after switching between AMD, NVIDIA, and Intel variants so the kernel modules load cleanly.


## Updating to the latest config

The canonical update paths are `just update` (terminal) and the **Up** app (GUI).
Both run the same `vexos-update` script from `modules/nix.nix`, which uses a
known-heavy block engine before applying any change:

- **Non-heavy local builds** (system glue, custom vexos scripts, Rust crates,
  binary wrappers like Discord/Steam) — build locally in seconds to minutes;
  logged as `VEXOS_LOCAL_BUILD`; update proceeds normally.
- **Heavy builds** (kernel modules, NVIDIA driver, OpenRazer DKMS module) —
  compile against the kernel and take hours if not pre-built by Hydra; update
  paused; `flake.lock` restored; logged as `VEXOS_CACHE_BLOCK`.

When a heavy-build block occurs, use `just deploy` to apply config-only changes
from the repo without bumping flake inputs, then retry `just update` in 1-3 days
once the Hydra binary cache catches up.

### Manual / emergency update (advanced)

> **Warning:** The commands below bypass miss classification and cache safety
> checks. Use only for recovery or advanced troubleshooting.

```bash
cd /etc/nixos && sudo nix flake update
sudo nixos-rebuild switch --flake /etc/nixos#$(cat /etc/nixos/vexos-variant)
```


## Notes

```bash
sudo nix --extra-experimental-features 'nix-command flakes' flake update --flake /etc/nixos
```

## Rollback

```bash
sudo nixos-rebuild switch --rollback
```

Reset NixOS back to default configuration:

```bash
sudo rm -f /etc/nixos/flake.nix /etc/nixos/flake.lock && sudo nixos-generate-config --root / && sudo nixos-rebuild switch
```


## Updating nixpkgs-unstable (GNOME stack)

The GNOME shell, mutter, GDM, and related packages are sourced from `nixpkgs-unstable` to track the latest GNOME releases. The daily CI auto-update job updates **all** flake inputs, including `nixpkgs-unstable`. Because GNOME stack updates occasionally introduce regressions that break Wayland session startup on VM guests (black screen on boot), it is worth verifying a VM build boots correctly after any unstable bump lands.

If a regression is introduced by a daily bump, roll it back with:

```bash
git revert HEAD  # or manually restore the previous flake.lock revision
```

**To bump nixpkgs-unstable outside the daily schedule:**

```bash
# 1. Bump nixpkgs-unstable in the flake.lock
cd /path/to/vexos-nix
nix flake update nixpkgs-unstable

# 2. Verify a VM variant dry-builds
sudo nixos-rebuild dry-build --flake .#vexos-desktop-vm

# 3. Run the automated GNOME boot test — boots a VM in QEMU and checks that
#    a real Wayland session actually starts (the specific signal a "black
#    screen" regression breaks; NEVER use `nix flake check` — see FORBIDDEN
#    COMMANDS — this builds only the one named check):
nix build .#checks.x86_64-linux.gnome-boot

# 4. Optionally, also do a live VM test (GNOME Boxes or virt-manager) as a
#    final human check for anything the automated test doesn't cover.
#    A black screen means the new nixpkgs-unstable has a GNOME regression.
#    Roll back with:
git revert HEAD  # or manually restore the previous flake.lock revision

# 5. If the automated test (and any manual check) pass, the bump is safe to leave in place.
```


## NixOS stable channel upgrades (e.g. 25.11 → 26.05)

When a new NixOS stable release ships, update the `nixpkgs` input and the
`system.stateVersion` comment (do **not** change the value itself — it must
stay at the version the system was first installed on):

```bash
# 1. Update the stable nixpkgs input to the new release branch
cd /path/to/vexos-nix
nix flake update nixpkgs

# 2. Update the flake.nix input ref from nixos-25.11 → nixos-26.05
#    (edit flake.nix: inputs.nixpkgs.url = "github:NixOS/nixpkgs/nixos-26.05")

# 3. Dry-build to catch any breakage before switching
sudo nixos-rebuild dry-build --flake .#vexos-desktop-amd

# 4. Switch when ready
just switch
```

> **Do NOT change `system.stateVersion`** even when upgrading to a new
> NixOS release. It must remain at the version the system was *first installed*
> on. Changing it can corrupt stateful data managed by NixOS activation scripts.

