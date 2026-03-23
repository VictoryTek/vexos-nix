# vexos-nix

Gaming-focused NixOS config (GNOME, Steam, Proton, PipeWire, zen kernel). Pick the variant that matches your hardware.

## Fresh install

> Assumes NixOS is installed and `nixos-generate-config` has already run (hardware config lives at `/etc/nixos/hardware-configuration.nix`).

```bash
nix-shell -p git
git clone <this-repo> ~/vexos-nix
cd ~/vexos-nix
sudo nixos-rebuild switch --flake .#vexos-amd     # AMD GPU
# sudo nixos-rebuild switch --flake .#vexos-nvidia  # NVIDIA GPU
# sudo nixos-rebuild switch --flake .#vexos-vm      # VM (QEMU / VirtualBox)
```

That's it. Log out and back in after the first switch.

## Variants

| Target | Use for |
|---|---|
| `.#vexos-amd` | AMD GPU (RADV, ROCm, LACT) |
| `.#vexos-nvidia` | NVIDIA GPU (proprietary, open kernel modules) |
| `.#vexos-vm` | QEMU/KVM or VirtualBox guest |

## Updating

```bash
nix flake update && sudo nixos-rebuild switch --flake .#vexos-amd
```