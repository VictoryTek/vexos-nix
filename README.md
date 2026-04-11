# vexos-nix

Personal NixOS config (GNOME, PipeWire, zen kernel). Comes in four roles — **Desktop** (full gaming/workstation stack), **Stateless** (minimal daily-driver), **Server** (GUI service stack), and **HTPC** (media centre build). No cloning required — `/etc/nixos` is the only working directory you need.

## Fresh install

> Assumes NixOS is installed and `hardware-configuration.nix` already exists at `/etc/nixos/`.

**1. Install git**
   ```bash
   nix-shell -p git
   ```

**2. Drop the flake wrapper into `/etc/nixos`**

```bash
sudo curl -fsSL -o /etc/nixos/flake.nix \
  https://raw.githubusercontent.com/VictoryTek/vexos-nix/main/template/etc-nixos-flake.nix
```

**3. Apply your role and GPU variant**

```bash
bash <(curl -fsSL https://raw.githubusercontent.com/VictoryTek/vexos-nix/main/scripts/install.sh)
```

The script asks which role (desktop or stateless) and which GPU variant to install (AMD, NVIDIA, Intel, or VM), runs the build, and offers to reboot when complete. After this first build, `/etc/nixos/vexos-variant` is written automatically and kept in sync on every future rebuild — the `#target` is never needed again.

> **Prefer to run manually?** See the [Variants](#variants) table and run the matching `nixos-rebuild switch` command directly.

Log out and back in after the first switch (or reboot when prompted).

## How it works

`/etc/nixos/flake.nix` is a tiny wrapper that pulls the full config from GitHub. Your `hardware-configuration.nix` never leaves `/etc/nixos`. On every rebuild NixOS uses the pinned version in `/etc/nixos/flake.lock`.

The running config writes `/etc/nixos/vexos-variant` (a one-word file, e.g. `vexos-desktop-amd`) on every build so tooling like vexos-updater always knows which variant is active.

## Variants

### Desktop role — full gaming/workstation stack

| Variant | Use for |
|---|---|
| `vexos-desktop-amd` | AMD GPU (RADV, ROCm, LACT) |
| `vexos-desktop-nvidia` | NVIDIA GPU (proprietary, open kernel modules) |
| `vexos-desktop-intel` | Intel iGPU or Arc dGPU |
| `vexos-desktop-vm` | QEMU/KVM or VirtualBox guest |

### Stateless role — minimal build (no gaming / dev / virt / ASUS)

| Variant | Use for |
|---|---|
| `vexos-stateless-amd` | AMD GPU, minimal stack |
| `vexos-stateless-nvidia` | NVIDIA GPU, minimal stack |
| `vexos-stateless-intel` | Intel iGPU or Arc dGPU, minimal stack |
| `vexos-stateless-vm` | QEMU/KVM or VirtualBox guest, minimal stack |

### Server role — GUI service stack

| Variant | Use for |
|---|---|
| `vexos-server-amd` | AMD GPU |
| `vexos-server-nvidia` | NVIDIA GPU |
| `vexos-server-intel` | Intel iGPU or Arc dGPU |
| `vexos-server-vm` | QEMU/KVM or VirtualBox guest |

### HTPC role — media centre build

| Variant | Use for |
|---|---|
| `vexos-htpc-amd` | AMD GPU |
| `vexos-htpc-nvidia` | NVIDIA GPU |
| `vexos-htpc-intel` | Intel iGPU or Arc dGPU |
| `vexos-htpc-vm` | QEMU/KVM or VirtualBox guest |

## Switching variants

You can switch between variants (and roles) at any time — no reinstall required. Just rebuild with the new variant target:

```bash
# Switch to a different desktop GPU variant
sudo nixos-rebuild switch --flake /etc/nixos#vexos-desktop-amd

# Switch to another role
sudo nixos-rebuild switch --flake /etc/nixos#vexos-stateless-amd
sudo nixos-rebuild switch --flake /etc/nixos#vexos-server-amd
sudo nixos-rebuild switch --flake /etc/nixos#vexos-htpc-amd
```

Replace the target with whichever variant matches your hardware and desired role (see the [Variants](#variants) table above). The `/etc/nixos/vexos-variant` file is updated automatically so vexos-updater and future updates use the new target going forward.

> **Switching GPU drivers?** A reboot is recommended after switching between AMD, NVIDIA, and Intel variants so the kernel modules load cleanly.

## Updating to the latest config

```bash
cd /etc/nixos && sudo nix flake update
sudo nixos-rebuild switch --flake /etc/nixos#$(cat /etc/nixos/vexos-variant)
```

Or with vexos-updater — no command needed, it reads `/etc/nixos/vexos-variant` automatically.

## Existing installs: migrating to the new wrapper

If you set up vexos-nix before the `vexos-variant` file was introduced, re-download the wrapper once to get the new template:

```bash
sudo curl -fsSL -o /etc/nixos/flake.nix \
  https://raw.githubusercontent.com/VictoryTek/vexos-nix/main/template/etc-nixos-flake.nix
```

Edit `variant`, `hostname`, and `bootloaderModule` in the `let` block, then rebuild once with the explicit target (e.g. `#vexos-desktop-vm`). After that, `/etc/nixos/vexos-variant` is managed automatically.

## Notes
```bash
sudo nix --extra-experimental-features 'nix-command flakes' flake update --flake /etc/nixos

# Desktop variants
sudo nixos-rebuild switch --flake /etc/nixos#vexos-desktop-amd
sudo nixos-rebuild switch --flake /etc/nixos#vexos-desktop-nvidia
sudo nixos-rebuild switch --flake /etc/nixos#vexos-desktop-intel
sudo nixos-rebuild switch --flake /etc/nixos#vexos-desktop-vm

# Stateless variants
sudo nixos-rebuild switch --flake /etc/nixos#vexos-stateless-amd
sudo nixos-rebuild switch --flake /etc/nixos#vexos-stateless-nvidia
sudo nixos-rebuild switch --flake /etc/nixos#vexos-stateless-intel
sudo nixos-rebuild switch --flake /etc/nixos#vexos-stateless-vm

# Server variants
sudo nixos-rebuild switch --flake /etc/nixos#vexos-server-amd
sudo nixos-rebuild switch --flake /etc/nixos#vexos-server-nvidia
sudo nixos-rebuild switch --flake /etc/nixos#vexos-server-intel
sudo nixos-rebuild switch --flake /etc/nixos#vexos-server-vm

# HTPC variants
sudo nixos-rebuild switch --flake /etc/nixos#vexos-htpc-amd
sudo nixos-rebuild switch --flake /etc/nixos#vexos-htpc-nvidia
sudo nixos-rebuild switch --flake /etc/nixos#vexos-htpc-intel
sudo nixos-rebuild switch --flake /etc/nixos#vexos-htpc-vm
```  

## Rollback

```bash
sudo nixos-rebuild switch --rollback
```
