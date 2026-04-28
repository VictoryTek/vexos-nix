# Change #10 — Bundle Specification

Three small audit findings bundled into a single change:
- **B12** — Justfile legacy NVIDIA variant selectors
- **D8** — Extract duplicated bash aliases into `home/bash-common.nix`
- **B5** — Minor documentation fixes

---

## B12: Justfile Legacy NVIDIA Variant Selectors

### Current State

The flake defines **30 nixosConfigurations** across 5 roles × 6 GPU variants.
For each role, the GPU variants are: `amd`, `nvidia`, `nvidia-legacy535`,
`nvidia-legacy470`, `intel`, `vm`.

The justfile's interactive `switch` recipe (line ~131) and `update` recipe
fallback selector (line ~221) both present only 4 GPU choices:

```
echo "  1) amd"
echo "  2) nvidia"
echo "  3) intel"
echo "  4) vm"
```

There is **no interactive path** to select `nvidia-legacy535` or
`nvidia-legacy470`. Direct invocation (`just switch desktop nvidia-legacy535`)
works because the target is composed as `vexos-${ROLE}-${VARIANT}`, but the
interactive flow has no sub-prompt for the NVIDIA driver branch.

`scripts/install.sh` has a NVIDIA sub-prompt but only offers two options
(Latest and Legacy 470); it **does not offer legacy535**.

### Problem

1. Users on legacy NVIDIA hardware cannot select `nvidia-legacy535` or
   `nvidia-legacy470` through the interactive `just switch` or `just update`
   flows.
2. `scripts/install.sh` is missing the `legacy535` option entirely.

### Proposed Changes

#### 1. `justfile` — `switch` recipe (interactive GPU selector)

After the existing GPU variant `while` loop (which sets `VARIANT`), insert a
NVIDIA driver branch sub-prompt that fires when `VARIANT="nvidia"`:

```bash
    # NVIDIA driver branch sub-selection
    if [ "$VARIANT" = "nvidia" ]; then
        echo ""
        echo "Select NVIDIA driver branch:"
        echo "  1) Latest     — RTX, GTX 16xx, GTX 750 and newer"
        echo "  2) Legacy 535 — Maxwell/Pascal/Volta (LTS 535.x)"
        echo "  3) Legacy 470 — Kepler, GeForce 600/700 (470.x)"
        echo ""
        while true; do
            printf "Choice [1-3]: "
            read -r INPUT
            case "${INPUT}" in
                1) break ;;
                2) VARIANT="nvidia-legacy535"; break ;;
                3) VARIANT="nvidia-legacy470"; break ;;
                *) echo "Invalid — enter 1, 2, or 3" ;;
            esac
        done
    fi
```

Insert location: immediately after the `done` that closes the GPU variant
`while` loop, before `fi` that closes `if [ -z "$VARIANT" ]`, and before
the `TARGET=` line.

#### 2. `justfile` — `update` recipe (fallback GPU selector)

Apply the identical NVIDIA driver branch sub-prompt block after the `update`
recipe's GPU variant `while` loop (same structure as `switch`).

Insert location: immediately after the `done` that closes the GPU variant
`while` loop inside the `update` recipe's fallback path, before the
`target="vexos-${ROLE}-${VARIANT}"` line.

#### 3. `scripts/install.sh` — NVIDIA driver branch selector

Replace the existing 2-option NVIDIA sub-prompt (lines ~155–175) with a
3-option prompt:

**Before:**
```bash
  echo -e "${BOLD}Select NVIDIA driver:${RESET}"
  echo "  1) Latest — RTX, GTX 16xx, GTX 750 and newer"
  echo "  2) Legacy — Everything older"
  echo ""
  echo -e "${YELLOW}Not sure? Check: https://www.nvidia.com/en-us/drivers/unix/legacy-gpu/${RESET}"
  echo -e "${YELLOW}Wrong choice? Run this installer again and switch.${RESET}"
  echo ""

  while [ -z "$NVIDIA_SUFFIX" ]; do
    printf "Enter choice [1-2]: "
    read -r INPUT </dev/tty
    case "${INPUT}" in
      1) NVIDIA_SUFFIX=""           ;;
      2) NVIDIA_SUFFIX="-legacy470" ;;
      *)
        echo -e "${RED}Invalid selection '${INPUT}'. Choose 1 or 2.${RESET}"
        ;;
    esac
    [[ -n "${INPUT}" ]] && break
  done
```

**After:**
```bash
  echo -e "${BOLD}Select NVIDIA driver branch:${RESET}"
  echo "  1) Latest     — RTX, GTX 16xx, GTX 750 and newer"
  echo "  2) Legacy 535 — Maxwell/Pascal/Volta (LTS 535.x)"
  echo "  3) Legacy 470 — Kepler, GeForce 600/700 (470.x)"
  echo ""
  echo -e "${YELLOW}Not sure? Check: https://www.nvidia.com/en-us/drivers/unix/legacy-gpu/${RESET}"
  echo -e "${YELLOW}Wrong choice? Run this installer again and switch.${RESET}"
  echo ""

  while [ -z "$NVIDIA_SUFFIX" ]; do
    printf "Enter choice [1-3]: "
    read -r INPUT </dev/tty
    case "${INPUT}" in
      1) NVIDIA_SUFFIX=""             ;;
      2) NVIDIA_SUFFIX="-legacy535"   ;;
      3) NVIDIA_SUFFIX="-legacy470"   ;;
      *)
        echo -e "${RED}Invalid selection '${INPUT}'. Choose 1, 2, or 3.${RESET}"
        ;;
    esac
    [[ -n "${INPUT}" ]] && break
  done
```

### Files Affected

| File | Action |
|------|--------|
| `justfile` | Modify — add NVIDIA sub-prompt to `switch` and `update` interactive selectors |
| `scripts/install.sh` | Modify — expand NVIDIA sub-prompt from 2 to 3 options |

---

## D8: Extract Duplicated Bash Aliases

### Current State

All five `home-*.nix` files contain an **identical** `programs.bash` block:

```nix
programs.bash = {
  enable = true;
  shellAliases = {
    ll  = "ls -la";
    ".." = "cd ..";
    ts   = "tailscale";
    tss  = "tailscale status";
    tsip = "tailscale ip";
    sshstatus = "systemctl status sshd";
    smbstatus = "systemctl status smbd";
  };
};
```

This block is duplicated verbatim in:
- `home-desktop.nix`
- `home-htpc.nix`
- `home-server.nix`
- `home-headless-server.nix`
- `home-stateless.nix`

There are **zero** role-specific aliases — all 7 aliases are common to every
role. No `home/bash-common.nix` exists.

### Problem

Seven aliases × five files = 35 duplicated alias lines (plus surrounding
boilerplate). Any future alias change must be made in 5 places.

### Proposed Changes

#### 1. Create `home/bash-common.nix`

```nix
# home/bash-common.nix
# Common bash shell configuration shared across all roles.
# Role-specific aliases (if any) can be added in the role's home-*.nix file;
# Home Manager merges shellAliases from all imported modules.
{ ... }:
{
  programs.bash = {
    enable = true;
    shellAliases = {
      ll  = "ls -la";
      ".." = "cd ..";

      # Tailscale shortcuts
      ts   = "tailscale";
      tss  = "tailscale status";
      tsip = "tailscale ip";

      # System service shortcuts
      sshstatus = "systemctl status sshd";
      smbstatus = "systemctl status smbd";
    };
  };
}
```

#### 2. Update each `home-*.nix`

For every home file:
- **Add** `./home/bash-common.nix` to the `imports` list.
- **Remove** the entire `programs.bash` block (including enable, shellAliases,
  and surrounding comments).

Specific per-file changes:

**`home-desktop.nix`** — already has `imports = [ ./home/photogimp.nix ./home/gnome-common.nix ];`
- Add `./home/bash-common.nix` to imports.
- Remove `# ── Shell ──…` section through the closing `};` of `programs.bash`.

**`home-htpc.nix`** — already has `imports = [ ./home/gnome-common.nix ];`
- Add `./home/bash-common.nix` to imports.
- Remove `# ── Shell ──…` section through the closing `};` of `programs.bash`.

**`home-server.nix`** — already has `imports = [ ./home/gnome-common.nix ];`
- Add `./home/bash-common.nix` to imports.
- Remove `# ── Shell ──…` section through the closing `};` of `programs.bash`.

**`home-headless-server.nix`** — currently has **no imports list**.
- Add `imports = [ ./home/bash-common.nix ];` after the opening `{`.
- Remove `# ── Shell ──…` section through the closing `};` of `programs.bash`.

**`home-stateless.nix`** — already has `imports = [ ./home/gnome-common.nix ];`
- Add `./home/bash-common.nix` to imports.
- Remove `# ── Shell ──…` section through the closing `};` of `programs.bash`.

### Files Affected

| File | Action |
|------|--------|
| `home/bash-common.nix` | **Create** — new shared module |
| `home-desktop.nix` | Modify — add import, remove inline bash block |
| `home-htpc.nix` | Modify — add import, remove inline bash block |
| `home-server.nix` | Modify — add import, remove inline bash block |
| `home-headless-server.nix` | Modify — add import, remove inline bash block |
| `home-stateless.nix` | Modify — add import, remove inline bash block |

---

## B5: Minor Documentation Fixes

### Current State & Problems

#### README.md

**Problem 1 — Role count mismatch (line ~11)**

Text says "Comes in five roles" then lists only four:
> Desktop, Stateless, Server (GUI & Headless service stack), HTPC

"Server (GUI & Headless service stack)" bundles two distinct roles
(`server` and `headless-server`) that have separate configurations, separate
host files, and separate flake outputs. The listing should enumerate all five.

**Problem 2 — Wrong `just switch` syntax (lines ~72, ~93, ~113, ~137, ~157)**

The README shows:
```
> just switch vexos-desktop-(gpu-choice)
```

The actual justfile `switch` recipe signature is `switch role="" variant=""
flake=""`, so the correct invocation is:
```
just switch desktop amd
```
or simply `just switch` for the interactive prompt. The `vexos-` prefix and
hyphenated form shown in the README would fail.

These incorrect hints appear in every role section.

**Problem 3 — Broken markdown in Notes / Rollback section (lines ~252–265)**

The `## Notes` section opens a code fence that is never closed. This causes
the `## Rollback` heading and its contents to render inside the code block.
Additionally, the Rollback section mixes prose ("Set Nixos back to default
configuration:") inside a code fence.

#### `.github/copilot-instructions.md`

**Problem 4 — Stale flake output count and examples (multiple locations)**

The file contains several references that were accurate when only desktop
outputs existed but are now stale:

| Location | Current text | Issue |
|----------|-------------|-------|
| Special Constraints | "The flake defines four outputs: `vexos-desktop-amd`, `vexos-desktop-nvidia`, `vexos-desktop-intel`, `vexos-desktop-vm`" | Flake has 30 outputs across 5 roles |
| Build Command(s) | Lists only 3 desktop variants (amd, nvidia, vm) | Missing intel, and all non-desktop roles |
| Test Command(s) | Lists only 3 desktop dry-build targets | Missing intel, and all non-desktop roles |
| Special Constraints | "All rebuild commands must target one of `.#vexos-desktop-amd`, `.#vexos-desktop-nvidia`, `.#vexos-desktop-intel`, or `.#vexos-desktop-vm`" | Should reference all roles |
| Special Constraints | "GPU-brand-specific configuration lives in `modules/gpu/{amd,nvidia,vm}.nix`" | Missing `intel.nix` and headless variants |
| Special Constraints | "Host configs live in `hosts/` and import `configuration-desktop.nix`" | Should reference all roles |

### Proposed Changes

#### README.md — Problem 1 (role listing)

**Before:**
```
Comes in five roles:
**Desktop** (full gaming/workstation stack), 
**Stateless** (impermanent, minimal build, security-focused), 
**Server** (GUI & Headless service stack), 
**HTPC** (media center build). 
```

**After:**
```
Comes in five roles:
**Desktop** (full gaming/workstation stack),
**Stateless** (impermanent, minimal build, security-focused),
**Server** (GUI server with GNOME desktop + service stack),
**Headless Server** (CLI-only service stack, no GUI),
**HTPC** (media centre build).
```

#### README.md — Problem 2 (just switch syntax)

Replace every occurrence of the incorrect `> just switch vexos-<role>-(gpu-choice)` pattern.

**Desktop section — before:**
```
> just switch vexos-desktop-(gpu-choice)
```
**After:**
```
> just switch desktop amd          # direct (any GPU variant)
> just switch                      # interactive prompt
```

**Stateless section — before:**
```
> just switch vexos-stateless-(gpu-choice)
```
**After:**
```
> just switch stateless amd        # direct (any GPU variant)
> just switch                      # interactive prompt
```

**Server section — before:**
```
> just switch vexos-server-(gpu-choice)
```
**After:**
```
> just switch server amd           # direct (any GPU variant)
> just switch                      # interactive prompt
```

**HTPC section — before:**
```
> just switch vexos-htpc-(gpu-choice)
```
**After:**
```
> just switch htpc amd             # direct (any GPU variant)
> just switch                      # interactive prompt
```

#### README.md — Problem 3 (Notes / Rollback markdown)

**Before (broken):**
```markdown
## Notes
```bash
sudo nix --extra-experimental-features 'nix-command flakes' flake update --flake /etc/nixos


## Rollback

```bash
sudo nixos-rebuild switch --rollback

Set Nixos back to default configuration:
sudo rm -f /etc/nixos/flake.nix /etc/nixos/flake.lock && sudo nixos-generate-config --root / && sudo nixos-rebuild switch
```
```

**After (fixed):**
````markdown
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
````

#### `.github/copilot-instructions.md` — Problem 4 (stale references)

**Change 1** — Special Constraints bullet about output count.

Before:
```
  - The flake defines four outputs: `vexos-desktop-amd`, `vexos-desktop-nvidia`, `vexos-desktop-intel`, `vexos-desktop-vm`
```
After:
```
  - The flake defines 30 outputs across five roles (`desktop`, `stateless`, `server`, `headless-server`, `htpc`) × six GPU variants (`amd`, `nvidia`, `nvidia-legacy535`, `nvidia-legacy470`, `intel`, `vm`)
```

**Change 2** — Build Command(s).

Before:
```
Build Command(s):  
- `sudo nixos-rebuild switch --flake .#vexos-desktop-amd` (AMD GPU)  
- `sudo nixos-rebuild switch --flake .#vexos-desktop-nvidia` (NVIDIA GPU)  
- `sudo nixos-rebuild switch --flake .#vexos-desktop-vm` (VM guest)  
```
After:
```
Build Command(s):  
- `sudo nixos-rebuild switch --flake .#vexos-<role>-<gpu>` (general form)  
- Example: `sudo nixos-rebuild switch --flake .#vexos-desktop-amd`  
- See `hostList` in `flake.nix` for the complete list of 30 output names  
```

**Change 3** — Test Command(s).

Before:
```
Test Command(s):  
- `nix flake check`  
- `sudo nixos-rebuild dry-build --flake .#vexos-desktop-amd`  
- `sudo nixos-rebuild dry-build --flake .#vexos-desktop-nvidia`  
- `sudo nixos-rebuild dry-build --flake .#vexos-desktop-vm`  
```
After:
```
Test Command(s):  
- `nix flake check`  
- `sudo nixos-rebuild dry-build --flake .#vexos-<role>-<gpu>` (per-variant validation)  
- At minimum, dry-build one variant per role to catch role-specific regressions  
```

**Change 4** — "All rebuild commands must target one of …".

Before:
```
  - All rebuild commands must target one of `.#vexos-desktop-amd`, `.#vexos-desktop-nvidia`, `.#vexos-desktop-intel`, or `.#vexos-desktop-vm`
```
After:
```
  - All rebuild commands must target a valid `nixosConfigurations` output (see `hostList` in `flake.nix` for the complete list)
```

**Change 5** — GPU module directory description.

Before:
```
  - GPU-brand-specific configuration lives in `modules/gpu/{amd,nvidia,vm}.nix`
```
After:
```
  - GPU-brand-specific configuration lives in `modules/gpu/` (`amd.nix`, `nvidia.nix`, `intel.nix`, `vm.nix`, plus `*-headless.nix` variants)
```

**Change 6** — Host config description.

Before:
```
  - Host configs live in `hosts/` and import `configuration-desktop.nix` + the appropriate `modules/gpu/` variant
```
After:
```
  - Host configs live in `hosts/` and import the role's `configuration-*.nix` + the appropriate `modules/gpu/` variant
```

### Files Affected

| File | Action |
|------|--------|
| `README.md` | Modify — fix role listing, `just switch` syntax, Notes/Rollback markdown |
| `.github/copilot-instructions.md` | Modify — update stale output count, build/test commands, constraints |

---

## Complete File List

| # | File | Action | Finding |
|---|------|--------|---------|
| 1 | `justfile` | Modify | B12 |
| 2 | `scripts/install.sh` | Modify | B12 |
| 3 | `home/bash-common.nix` | **Create** | D8 |
| 4 | `home-desktop.nix` | Modify | D8 |
| 5 | `home-htpc.nix` | Modify | D8 |
| 6 | `home-server.nix` | Modify | D8 |
| 7 | `home-headless-server.nix` | Modify | D8 |
| 8 | `home-stateless.nix` | Modify | D8 |
| 9 | `README.md` | Modify | B5 |
| 10 | `.github/copilot-instructions.md` | Modify | B5 |
