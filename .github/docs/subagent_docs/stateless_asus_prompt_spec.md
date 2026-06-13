# Phase 1 Spec — stateless_asus_prompt

## Problem Definition

`stateless-setup.sh` never asks whether the target machine is an ASUS ROG/TUF device.
As a result, users with ASUS hardware who run the stateless install get a system with
`vexos.hardware.asus.enable = false` and no asusd/supergfxctl/power-profiles-daemon —
even though `configuration-stateless.nix` already imports `modules/asus-opt.nix` and
the option is fully declared.

## Current State Analysis

### install.sh — has full ASUS flow

`scripts/install.sh` lines 183-207 (prompt) and 313-335 (patch):

1. Prompts "Is this an ASUS ROG/TUF device? [y/N]" — skipped for `vm` variant.
2. If yes, prompts "Is this device a laptop? [y/N]" (to set battery charge limit).
3. After the template flake is downloaded to `/etc/nixos/flake.nix`, patches:
   - Non-laptop: `hardwareModule = { ... }: { vexos.hardware.asus.enable = true; }`
   - Laptop: additionally sets `vexos.hardware.asus.batteryChargeLimit = 80`
   - Uses `grep -qF 'hardwareModule = { ... }: { };'` to guard the sed (no-op if already patched).

### stateless-setup.sh — missing ASUS flow entirely

`scripts/stateless-setup.sh` has:
- GPU variant prompt (lines 92-114)
- Password prompt (lines 116-156)
- Template flake download: `sudo curl -fsSL "${TEMPLATE_URL}" -o /mnt/etc/nixos/flake.nix` (line 265)
- Git init + add: lines 296-297

No ASUS prompt and no ASUS patch.

### template/etc-nixos-flake.nix — same hardwareModule target

Line 115 of the template:
```nix
hardwareModule = { ... }: { };
```

This is the identical placeholder that `install.sh` patches with `sed`.

### modules/asus-opt.nix — option is declared for all roles

`configuration-stateless.nix` imports `./modules/asus-opt.nix` (line 25). The option
`vexos.hardware.asus.enable` is already declared; it just needs to be set `true` in
`hardwareModule` to activate the asusd/supergfxctl stack.

## Affected Files

- `scripts/stateless-setup.sh` — add ASUS prompt block + ASUS patch block

No other files change. The template flake already has the correct placeholder.

## Proposed Solution

### 1. Add ASUS prompt block (after GPU variant prompt, before password prompt)

Mirror `install.sh` lines 183-207 exactly:
- Skip for `VARIANT = "vm"` (VM guests have no ASUS platform devices)
- Prompt "Is this an ASUS ROG/TUF device? [y/N]"
- If yes, prompt "Is this device a laptop? [y/N]"

Variables: `ASUS_ENABLE=false`, `ASUS_LAPTOP=false`

### 2. Add ASUS patch block (after template flake download, before git init)

Mirror `install.sh` lines 313-335, but targeting `/mnt/etc/nixos/flake.nix`
(not `/etc/nixos/flake.nix`):

```bash
# ---------- ASUS hardware patch ---------------------------------------------
if [ "$ASUS_ENABLE" = "true" ]; then
  if grep -qF 'hardwareModule = { ... }: { };' /mnt/etc/nixos/flake.nix 2>/dev/null; then
    echo ""
    echo -e "${BOLD}Patching flake.nix to enable ASUS ROG/TUF support...${RESET}"
    if [ "$ASUS_LAPTOP" = "true" ]; then
      sudo sed -i 's/hardwareModule = { \.\.\. }: { };/hardwareModule = { ... }: { vexos.hardware.asus.enable = true; vexos.hardware.asus.batteryChargeLimit = 80; };/' /mnt/etc/nixos/flake.nix
      echo -e "  ${GREEN}✓ ASUS hardware support enabled (laptop — battery charge limit set to 80%).${RESET}"
    else
      sudo sed -i 's/hardwareModule = { \.\.\. }: { };/hardwareModule = { ... }: { vexos.hardware.asus.enable = true; };/' /mnt/etc/nixos/flake.nix
      echo -e "  ${GREEN}✓ ASUS hardware support enabled.${RESET}"
    fi
  else
    echo ""
    echo -e "  ${YELLOW}⚠ hardwareModule not found in flake.nix — skipping ASUS patch.${RESET}"
    echo "    To enable ASUS support manually, add to /etc/nixos/flake.nix:"
    echo "      vexos.hardware.asus.enable = true;"
    if [ "$ASUS_LAPTOP" = "true" ]; then
      echo "      vexos.hardware.asus.batteryChargeLimit = 80;"
    fi
  fi
fi
```

### Insertion points in stateless-setup.sh

- **Prompt block**: after the GPU variant `while` loop ends (after line 114), before the
  password section (before line 116 `# ---------- Prompt: nimda user password`).
- **Patch block**: after the template flake download echo line (after line 266
  `echo -e "${GREEN}✓ /mnt/etc/nixos/flake.nix downloaded.${RESET}"`), before the
  `# ---------- Write stateless-user-override.nix` section.

The patch must occur BEFORE `sudo git -C /mnt/etc/nixos add .` (line 297) so that git
stages the patched file — not the unpatched one.

## Implementation Steps

1. Edit `scripts/stateless-setup.sh`:
   a. Insert ASUS prompt block after the GPU variant loop (after line 114)
   b. Insert ASUS patch block after the template flake download (after line 266)

## Dependencies

No new dependencies. Uses `grep`, `sed`, and `sudo` — all available on the NixOS live ISO.

## Context7

Not required — no external libraries involved.

## Risks and Mitigations

- **Risk:** `sed` pattern mismatch if the template is edited in future.
  **Mitigation:** Same risk exists in `install.sh` (unchanged). The `grep -qF` guard
  makes the sed a no-op if the pattern isn't found, with a manual instructions fallback.

- **Risk:** Forgetting to copy the patched flake to `/mnt/persistent/etc/nixos/`.
  **Mitigation:** The existing `sudo cp /mnt/etc/nixos/flake.nix /mnt/persistent/etc/nixos/`
  (line 330 in the current script) already copies the flake to persistent storage — so
  the patched version is automatically included.
