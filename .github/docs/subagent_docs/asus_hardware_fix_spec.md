# asus_hardware_fix — Specification

## Current State Analysis

### The Bug
Three shared desktop host files hardcode personal ASUS laptop settings:
- `hosts/desktop-amd.nix:11-12`
- `hosts/desktop-nvidia.nix:11-12`
- `hosts/desktop-intel.nix:11-12`

All three contain:
```nix
vexos.hardware.asus.enable = true;
vexos.hardware.asus.batteryChargeLimit = 80;
```

These are personal settings that belong to the user's specific machine, not in shared
repo host variants that represent any machine of that GPU type.

### How It Should Work (the designed system)
The installer (`scripts/install.sh`) already has the correct mechanism:
1. Prompts the user about ASUS hardware
2. If Y, patches `hardwareModule` in `/etc/nixos/flake.nix` (the per-machine local config)
3. `hardwareModule` is applied to every builder call in `template/etc-nixos-flake.nix`

The repo-level `hosts/` files are used for CI evaluation and direct repo builds. They
must NOT contain any per-machine hardware settings.

### Other Host Files
All other roles (stateless, server, headless-server, htpc, vanilla) are clean — no
hardcoded ASUS settings. The VM desktop file also has it correctly as a commented-out line.

### The Battery Charge Limit Gap
The installer currently only patches `asus.enable = true`. It never sets
`batteryChargeLimit`. Once the hardcoded `= 80` is removed from the host files, ASUS
users who answer Y will get the option default of 100% (no limit). The installer needs
to ask the follow-up laptop question and patch accordingly.

### Stateless Note
Stateless has three code paths:
- **Live ISO path** (`ROOT_FSTYPE=tmpfs`, no `/nix`): exits via `stateless-setup.sh` — never reaches ASUS block.
- **Migration path** (existing NixOS): exits via `migrate-to-stateless.sh` — never reaches ASUS block.
- **Fall-through path** (already running stateless, switching GPU variant): falls through to GPU selection and the full installer, including the ASUS block.

The `[ "$ROLE" != "stateless" ]` guard explicitly skips ASUS for the fall-through case, which is wrong — a stateless ASUS laptop switching GPU variant should be asked. The guard must be removed.

The live ISO and migration paths going to separate scripts are a separate future item.

---

## Problem Definition

1. `hosts/desktop-{amd,nvidia,intel}.nix` bake personal ASUS settings into shared
   files — any non-ASUS machine that uses these variants gets `asusd`, `supergfxd`,
   and `power-profiles-daemon` running unnecessarily.
2. The installer question says "laptop" but should say "device" (ASUS makes ROG desktops too).
3. `batteryChargeLimit = 80` is only meaningful for laptops — desktops have no battery.
   The installer has no mechanism to set it, so it was silently lost from the designed flow.

---

## Proposed Solution

### Change 1 — Remove hardcoded ASUS settings from 3 repo host files

In each of `hosts/desktop-amd.nix`, `hosts/desktop-nvidia.nix`, `hosts/desktop-intel.nix`:
- Remove line: `vexos.hardware.asus.enable = true;`
- Remove line: `vexos.hardware.asus.batteryChargeLimit = 80;`

The option default (`enable = false`, `batteryChargeLimit = 100`) takes over.
CI evaluations will no longer include ASUS packages in desktop builds.

The commented-out line in `hosts/desktop-vm.nix` is benign documentation; leave it.

### Change 2 — Update installer ASUS question flow

**Current flow (lines 183–196):**
```
"Is this an ASUS ROG/TUF laptop?" → Y sets ASUS_ENABLE=true
```
Single question, no follow-up, never sets batteryChargeLimit.

**New flow:**
```
"Is this an ASUS ROG/TUF device?" → Y sets ASUS_ENABLE=true
  └─ "Is this device a laptop?" → Y sets ASUS_LAPTOP=true
```

Guard change: `if [ "$VARIANT" != "vm" ] && [ "$ROLE" != "stateless" ]`
         → `if [ "$VARIANT" != "vm" ]`
(stateless fall-through path correctly gets the question)

### Change 3 — Update installer ASUS patch block to handle laptop sub-case

**Current patch (lines 302–317):**
```bash
sed -i 's/hardwareModule = { \.\.\. }: { };/hardwareModule = { ... }: { vexos.hardware.asus.enable = true; };/'
```

**New patch logic:**
- If ASUS_ENABLE=true AND ASUS_LAPTOP=true:
  ```bash
  sed -i 's/.../hardwareModule = { ... }: { vexos.hardware.asus.enable = true; vexos.hardware.asus.batteryChargeLimit = 80; };/'
  ```
- If ASUS_ENABLE=true AND ASUS_LAPTOP=false (desktop):
  ```bash
  sed -i 's/.../hardwareModule = { ... }: { vexos.hardware.asus.enable = true; };/'
  ```

### Change 4 — Update template comment

In `template/etc-nixos-flake.nix`, update the `hardwareModule` comment to show both forms:
```nix
# To enable ASUS ROG/TUF support manually, change this to:
#   ASUS device (any):  { vexos.hardware.asus.enable = true; }
#   ASUS laptop:        { vexos.hardware.asus.enable = true; vexos.hardware.asus.batteryChargeLimit = 80; }
```

---

## Implementation Steps

1. Edit `hosts/desktop-amd.nix` — remove 2 ASUS lines
   Verify: file contains only imports + `system.nixos.distroName`

2. Edit `hosts/desktop-nvidia.nix` — remove 2 ASUS lines
   Verify: same as above

3. Edit `hosts/desktop-intel.nix` — remove 2 ASUS lines
   Verify: same as above

4. Edit `scripts/install.sh` — update ASUS prompt block (lines 183–196):
   - Change guard: remove `&& [ "$ROLE" != "stateless" ]`
   - Change question text: "laptop" → "device"
   - Add follow-up laptop question when ASUS_ENABLE=true
   Verify: new variables `ASUS_ENABLE` and `ASUS_LAPTOP` set correctly per input

5. Edit `scripts/install.sh` — update ASUS patch block (lines 302–317) to branch on ASUS_LAPTOP
   Verify: correct sed string for laptop vs desktop case

6. Edit `template/etc-nixos-flake.nix` — update hardwareModule comment (lines 112–113)
   Verify: comment shows both forms

---

## Dependencies

None — no new Nix packages or flake inputs.

---

## Risks and Mitigations

| Risk | Mitigation |
|---|---|
| Existing ASUS installs lose `batteryChargeLimit = 80` from repo host files | They won't — they use `template/etc-nixos-flake.nix` via `/etc/nixos/flake.nix`, not the repo hosts directly. The hardwareModule in their local config already has `enable = true`. After this change the repo host files just stop overriding it. Existing installs are unaffected. |
| `sed` pattern must match exactly | The patch block already uses this exact pattern and works. We're extending it, not replacing it. |
| `batteryChargeLimit` default changes | It doesn't — we leave `asus-opt.nix` default at 100. Desktops explicitly don't get 80. |
