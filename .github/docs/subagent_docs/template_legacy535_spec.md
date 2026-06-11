# template_legacy535 — Specification

## Problem

`template/etc-nixos-flake.nix` is missing all 6 `nvidia-legacy535` outputs.
The installer offers `vexos-<role>-nvidia-legacy535` for 5 roles and (after this fix)
all 6 including vanilla, but the template on each installed machine doesn't define those
outputs — causing `nixos-rebuild` to fail with "attribute missing" on any machine that
chose the legacy535 driver.

The main `flake.nix` also lacks `vexos-vanilla-nvidia-legacy535`, and the installer
explicitly excluded vanilla from the NVIDIA driver branch selection menu.
Per user instruction, vanilla should have the legacy535 variant identical to all other roles.

## Files to Change

### 1. `flake.nix`

Add to hostList (after `vexos-vanilla-nvidia`):
```nix
{ name = "vexos-vanilla-nvidia-legacy535"; role = "vanilla"; gpu = "nvidia"; nvidiaVariant = "legacy_535"; }
```

Update count comment: "29 outputs total: 25 role/GPU variants + 4 vanilla role variants"
→ "30 outputs total: 25 role/GPU variants + 5 vanilla role variants"

### 2. `.github/workflows/ci.yml`

Add `vexos-vanilla-nvidia-legacy535` to the vanilla eval group.

### 3. `template/etc-nixos-flake.nix`

Add to comment header (Vanilla section):
```
#        sudo nixos-rebuild switch --flake /etc/nixos#vexos-vanilla-nvidia-legacy535  (Maxwell/Pascal/Volta — LTS alt.)
```

Add to nixosConfigurations block — all 6 missing entries:
```nix
vexos-desktop-nvidia-legacy535 =
  mkVariant "vexos-desktop-nvidia-legacy535"
    [ vexos-nix.nixosModules.gpuNvidia { vexos.gpu.nvidiaDriverVariant = "legacy_535"; } ];
vexos-stateless-nvidia-legacy535 =
  mkStatelessVariant "vexos-stateless-nvidia-legacy535"
    [ vexos-nix.nixosModules.gpuNvidia { vexos.gpu.nvidiaDriverVariant = "legacy_535"; } ];
vexos-htpc-nvidia-legacy535 =
  mkHtpcVariant "vexos-htpc-nvidia-legacy535"
    [ vexos-nix.nixosModules.gpuNvidia { vexos.gpu.nvidiaDriverVariant = "legacy_535"; } ];
vexos-server-nvidia-legacy535 =
  mkServerVariant "vexos-server-nvidia-legacy535"
    [ vexos-nix.nixosModules.gpuNvidia { vexos.gpu.nvidiaDriverVariant = "legacy_535"; } ];
vexos-headless-server-nvidia-legacy535 =
  mkHeadlessServerVariant "vexos-headless-server-nvidia-legacy535"
    [ vexos-nix.nixosModules.gpuNvidia { vexos.gpu.nvidiaDriverVariant = "legacy_535"; } ];
vexos-vanilla-nvidia-legacy535 =
  mkVanillaVariant "vexos-vanilla-nvidia-legacy535"
    [ vexos-nix.nixosModules.gpuNvidia { vexos.gpu.nvidiaDriverVariant = "legacy_535"; } ];
```

### 4. `scripts/install.sh`

Remove `&& [ "$ROLE" != "vanilla" ]` from the NVIDIA driver branch guard (line ~160):
```bash
# BEFORE:
if [ "$VARIANT" = "nvidia" ] && [ "$ROLE" != "vanilla" ]; then
# AFTER:
if [ "$VARIANT" = "nvidia" ]; then
```

## No Context7 Required

No new external dependencies. Pure Nix attribute additions and a shell condition removal.
