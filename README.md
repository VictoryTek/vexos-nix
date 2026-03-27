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

**3. Edit `/etc/nixos/flake.nix`**

Open the file and set the three variables in the `let` block:

- `variant` — pick your hardware variant (see table below)
- `hostname` — any name you want for this machine on your network
- `bootloaderModule` — EFI (default) or BIOS

**4. Apply (first build — `#variant` target required once)**

```bash
sudo nixos-rebuild switch --flake /etc/nixos#vexos-amd     # AMD GPU
sudo nixos-rebuild switch --flake /etc/nixos#vexos-nvidia  # NVIDIA GPU
sudo nixos-rebuild switch --flake /etc/nixos#vexos-intel   # Intel GPU
sudo nixos-rebuild switch --flake /etc/nixos#vexos-vm      # VM (QEMU / VirtualBox)
```

After this first build, `/etc/nixos/vexos-variant` is written automatically and kept in sync on every future rebuild. The `#target` is never needed again.

Log out and back in after the first switch.

## How it works

`/etc/nixos/flake.nix` is a tiny wrapper that pulls the full config from GitHub. Your `hardware-configuration.nix` never leaves `/etc/nixos`. On every rebuild NixOS uses the pinned version in `/etc/nixos/flake.lock`.

The running config writes `/etc/nixos/vexos-variant` (a one-word file, e.g. `vexos-amd`) on every build so tooling like vexos-updater always knows which variant is active.

## Variants

| Variant | Use for |
|---|---|
| `vexos-amd` | AMD GPU (RADV, ROCm, LACT) |
| `vexos-nvidia` | NVIDIA GPU (proprietary, open kernel modules) |
| `vexos-intel` | Intel iGPU or Arc dGPU |
| `vexos-vm` | QEMU/KVM or VirtualBox guest |

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

Edit `variant`, `hostname`, and `bootloaderModule` in the `let` block, then rebuild once with the explicit target (e.g. `#vexos-vm`). After that, `/etc/nixos/vexos-variant` is managed automatically.

## Notes
```bash
sudo nix --extra-experimental-features 'nix-command flakes' flake update --flake /etc/nixos

sudo nixos-rebuild switch --flake /etc/nixos#vexos-vm
```  

## Rollback

```bash
sudo nixos-rebuild switch --rollback
```
