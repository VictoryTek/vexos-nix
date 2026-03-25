# vexos-nix

Gaming-focused NixOS config (GNOME, Steam, Proton, PipeWire, zen kernel). No cloning required — `/etc/nixos` is the only working directory you need.

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

**3. Switch**

```bash
sudo nixos-rebuild switch --flake /etc/nixos#vexos-nvidia  # NVIDIA GPU

sudo nixos-rebuild switch --flake /etc/nixos#vexos-amd     # AMD GPU

sudo nixos-rebuild switch --flake /etc/nixos#vexos-vm      # VM (QEMU / VirtualBox)
```

Log out and back in after the first switch.

## How it works

`/etc/nixos/flake.nix` is a tiny wrapper that pulls the full config from GitHub. Your `hardware-configuration.nix` never leaves `/etc/nixos`. On every rebuild NixOS uses the pinned version in `/etc/nixos/flake.lock`.

## Variants

| Target | Use for |
|---|---|
| `vexos-amd` | AMD GPU (RADV, ROCm, LACT) |
| `vexos-nvidia` | NVIDIA GPU (proprietary, open kernel modules) |
| `vexos-vm` | QEMU/KVM or VirtualBox guest |

## Updating to the latest config

```bash
cd /etc/nixos && sudo nix flake update
sudo nixos-rebuild switch --flake /etc/nixos#vexos-nvidia

cd /etc/nixos && sudo nix flake update
sudo nixos-rebuild switch --flake /etc/nixos#vexos-amd

cd /etc/nixos && sudo nix flake update
sudo nixos-rebuild switch --flake /etc/nixos#vexos-vm
```