# Specification: Interactive Install Script (`scripts/install.sh`)

**Feature:** `install_script`  
**Phase:** 1 — Research & Specification  
**Date:** 2026-04-07  

---

## 1. Current State Analysis

### README Step 3 (current)

```
**3. Apply (first build — `#variant` target required once)**

```bash
sudo nixos-rebuild switch --flake /etc/nixos#vexos-desktop-amd     # AMD GPU
sudo nixos-rebuild switch --flake /etc/nixos#vexos-desktop-nvidia  # NVIDIA GPU
sudo nixos-rebuild switch --flake /etc/nixos#vexos-desktop-intel   # Intel GPU
sudo nixos-rebuild switch --flake /etc/nixos#vexos-desktop-vm      # VM (QEMU / VirtualBox)
```
```

The user must:
1. Identify their GPU type manually.
2. Copy the correct `nixos-rebuild` command.
3. Know to substitute `/etc/nixos` if their path differs.
4. Optionally reboot manually afterward.

### Existing scripts

- `scripts/preflight.sh` — pre-push validation (not end-user facing). Establishes the project's shell scripting conventions: `#!/usr/bin/env bash`, `set -uo pipefail`, inline color helpers, `pass`/`fail`/`warn` output functions.

### Flake outputs (from `flake.nix`)

| Internal target | GPU |
|---|---|
| `vexos-desktop-amd` | AMD (RADV, ROCm, LACT) |
| `vexos-desktop-nvidia` | NVIDIA proprietary |
| `vexos-desktop-intel` | Intel iGPU / Arc |
| `vexos-desktop-vm` | QEMU/KVM, VirtualBox |

### Thin wrapper (`template/etc-nixos-flake.nix`)

Installed by the user from the GitHub raw URL to `/etc/nixos/flake.nix`.  
Step 3 is the only step where the user must know their variant.

---

## 2. Problem Definition

- Step 3 exposes four commands forcing the user to pick correctly without guidance.
- A new user may not know which variant applies to them (particularly Intel vs AMD vs VM).
- There is no error handling — a typo silently runs the wrong target.
- There is no post-build reboot prompt; the README note ("log out and back in") is easily missed.
- Shell-script piping (`curl | bash`) carries a well-understood MITM/supply-chain risk that requires clear communication to the user.

---

## 3. Proposed Solution Architecture

### 3.1 Script location

```
scripts/install.sh
```

Hosted at:
```
https://raw.githubusercontent.com/VictoryTek/vexos-nix/main/scripts/install.sh
```

### 3.2 Invocation pattern (README replacement)

```bash
bash <(curl -fsSL https://raw.githubusercontent.com/VictoryTek/vexos-nix/main/scripts/install.sh)
```

`bash <(...)` (process substitution) is preferred over `curl ... | bash` because:
- The shell reads the script as a file, which allows `read` built-ins to work with the user's TTY (stdin is not consumed by the pipe).
- It is functionally equivalent security-wise but resolves the stdin-consumed-by-pipe problem that makes interactive scripts impossible with `| bash`.

> **Security note (documented in §6):** Both forms download and execute remote code. The user must trust the source. The script echos its own URL on startup so the user always knows what they are running.

### 3.3 Script behaviour (flow)

```
START
  │
  ├─ Print header + source URL (transparency)
  │
  ├─ Print numbered GPU menu:
  │     1) AMD
  │     2) NVIDIA
  │     3) Intel
  │     4) VM
  │
  ├─ Loop until valid input received:
  │     Accept: 1/2/3/4  OR  amd/nvidia/intel/vm  (case-insensitive)
  │     Reject anything else with a clear error message
  │
  ├─ Map selection → FLAKE_TARGET (e.g. "vexos-desktop-amd")
  │
  ├─ Print: "Building vexos-desktop-<variant>..."
  │
  ├─ Execute: sudo nixos-rebuild switch --flake "/etc/nixos#${FLAKE_TARGET}"
  │
  ├─ On SUCCESS:
  │     Print: green "✓ Build and switch successful!"
  │     Prompt: "Reboot now? [y/N]"
  │       ├─ y/Y → sudo reboot
  │       └─ n/N/<enter> → print advisory and exit 0
  │
  └─ On FAILURE:
        Print: red "✗ nixos-rebuild failed. Reboot skipped."
        Print: "Review the output above for errors and retry."
        exit 1
END
```

### 3.4 Shell compatibility

The script targets **bash** (`#!/usr/bin/env bash`).  
Rationale: NixOS always provides bash; bash process substitution (`<(...)`) is used in the invocation pattern; bash `read -r` is universally available on all NixOS installs. POSIX sh compatibility is not required.

---

## 4. Complete Proposed Script

```bash
#!/usr/bin/env bash
# =============================================================================
# install.sh — vexos-nix Interactive First-Boot Installer
# Repository: https://github.com/VictoryTek/vexos-nix
#
# Usage (one-liner, recommended):
#   bash <(curl -fsSL https://raw.githubusercontent.com/VictoryTek/vexos-nix/main/scripts/install.sh)
#
# Or clone first and run locally:
#   bash scripts/install.sh
#
# SECURITY NOTICE:
#   This script is fetched from raw.githubusercontent.com and executed directly.
#   Always verify the source URL above before running.
#   Source code: https://github.com/VictoryTek/vexos-nix/blob/main/scripts/install.sh
# =============================================================================

set -uo pipefail

SCRIPT_URL="https://raw.githubusercontent.com/VictoryTek/vexos-nix/main/scripts/install.sh"

# ---------- Color helpers (only if stdout is a TTY with color support) -------
if [ -t 1 ] && [ "$(tput colors 2>/dev/null || echo 0)" -ge 8 ]; then
  RED='\033[0;31m'
  GREEN='\033[0;32m'
  YELLOW='\033[0;33m'
  CYAN='\033[0;36m'
  BOLD='\033[1m'
  RESET='\033[0m'
else
  RED='' GREEN='' YELLOW='' CYAN='' BOLD='' RESET=''
fi

# ---------- Header -----------------------------------------------------------
echo ""
echo -e "${BOLD}${CYAN}============================================${RESET}"
echo -e "${BOLD}${CYAN}   vexos-nix Interactive Installer${RESET}"
echo -e "${BOLD}${CYAN}============================================${RESET}"
echo ""
echo -e "${YELLOW}Source: ${SCRIPT_URL}${RESET}"
echo -e "${YELLOW}Verify: https://github.com/VictoryTek/vexos-nix/blob/main/scripts/install.sh${RESET}"
echo ""

# ---------- GPU variant selection --------------------------------------------
echo -e "${BOLD}Select your GPU variant:${RESET}"
echo "  1) AMD    — AMD GPU (RADV, ROCm, LACT)"
echo "  2) NVIDIA — NVIDIA GPU (proprietary, open kernel modules)"
echo "  3) Intel  — Intel iGPU or Arc dGPU"
echo "  4) VM     — QEMU/KVM or VirtualBox guest"
echo ""

VARIANT=""
while [ -z "$VARIANT" ]; do
  printf "Enter choice [1-4] or name (amd / nvidia / intel / vm): "
  read -r INPUT
  case "${INPUT,,}" in          # ${var,,} = lowercase (bash 4+)
    1|amd)    VARIANT="amd"    ;;
    2|nvidia) VARIANT="nvidia" ;;
    3|intel)  VARIANT="intel"  ;;
    4|vm)     VARIANT="vm"     ;;
    *)
      echo -e "${RED}Invalid selection '${INPUT}'. Please enter 1, 2, 3, 4, amd, nvidia, intel, or vm.${RESET}"
      ;;
  esac
done

FLAKE_TARGET="vexos-desktop-${VARIANT}"

# ---------- Build & switch ---------------------------------------------------
echo ""
echo -e "${BOLD}Building ${CYAN}${FLAKE_TARGET}${RESET}${BOLD}...${RESET}"
echo ""

if sudo nixos-rebuild switch --flake "/etc/nixos#${FLAKE_TARGET}"; then
  echo ""
  echo -e "${GREEN}${BOLD}✓ Build and switch successful!${RESET}"
  echo ""
  printf "Reboot now? [y/N] "
  read -r REBOOT_CHOICE
  case "${REBOOT_CHOICE,,}" in
    y|yes)
      echo "Rebooting..."
      sudo reboot
      ;;
    *)
      echo ""
      echo -e "${YELLOW}Skipping reboot. Log out and back in to apply session changes.${RESET}"
      echo ""
      ;;
  esac
else
  echo ""
  echo -e "${RED}${BOLD}✗ nixos-rebuild failed. Reboot skipped.${RESET}"
  echo "  Review the output above for errors and retry:"
  echo "    sudo nixos-rebuild switch --flake /etc/nixos#${FLAKE_TARGET}"
  echo ""
  exit 1
fi
```

---

## 5. README Step 3 Replacement Text

### Current (to be replaced)

```markdown
**3. Apply (first build — `#variant` target required once)**

```bash
sudo nixos-rebuild switch --flake /etc/nixos#vexos-desktop-amd     # AMD GPU
sudo nixos-rebuild switch --flake /etc/nixos#vexos-desktop-nvidia  # NVIDIA GPU
sudo nixos-rebuild switch --flake /etc/nixos#vexos-desktop-intel   # Intel GPU
sudo nixos-rebuild switch --flake /etc/nixos#vexos-desktop-vm      # VM (QEMU / VirtualBox)
```
```

### Replacement

```markdown
**3. Apply (first build)**

```bash
bash <(curl -fsSL https://raw.githubusercontent.com/VictoryTek/vexos-nix/main/scripts/install.sh)
```

The script asks which GPU variant to install, runs `nixos-rebuild switch`, and optionally reboots.  
To apply manually instead: pick the command matching your hardware from the [Variants](#variants) table below.
```

---

## 6. Security Considerations

### 6.1 `curl | bash` / process substitution risk

Downloading and executing a remote script is a widely-debated practice. The risks are:

| Threat | Description |
|---|---|
| MITM attack | An attacker intercepts the HTTPS connection and serves a malicious script. Mitigated by TLS + GitHub's certificate pinning. |
| Supply-chain compromise | The GitHub repository or your GitHub account is compromised. Mitigated by keeping the repo private/locked, using 2FA, and pinning to a specific commit SHA if required. |
| CDN / raw.githubusercontent.com outage | Script unavailable. Non-security risk; user falls back to manual commands. |

**Mitigations implemented in the script:**

1. The script prints its own source URL and the GitHub viewer URL on startup before doing anything. The user can Ctrl-C and verify the source.
2. `curl -fsSL` uses HTTPS with TLS certificate validation (`-f` = fail on HTTP errors, `-s` = silent progress, `-S` = show errors, `-L` = follow redirects). Redirects stay within `raw.githubusercontent.com`.
3. The script contains no `sudo` except for the two explicit operations: `nixos-rebuild switch` and optionally `reboot`. There are no curl/wget calls inside the script, no package installation, and no file writes other than what `nixos-rebuild` itself performs.

**For users who prefer not to pipe from the internet:**

```bash
# Alternative: inspect first, then run
curl -fsSL https://raw.githubusercontent.com/VictoryTek/vexos-nix/main/scripts/install.sh -o /tmp/install.sh
less /tmp/install.sh          # review
bash /tmp/install.sh
```

This should be noted in the README as an alternative in the security advisory.

### 6.2 Script hardening

- `set -uo pipefail`: exits on unset variable use, undefined pipeline errors.  
- No `eval` or dynamic code execution.  
- `VARIANT` is constrained to exactly four known strings before being interpolated into the `nixos-rebuild` command (prevents injection via user input).  
- Color variables are initialized to empty strings when not in a color-capable TTY (avoids escape code injection in non-TTY contexts).

---

## 7. Implementation Steps

1. **Create `scripts/install.sh`** — exact content from §4.
2. **Set executable bit** — `chmod +x scripts/install.sh` (committed with `git update-index --chmod=+x`).
3. **Update `README.md`** — replace Step 3 block with the text from §5.
4. **No changes required** to `flake.nix`, `configuration.nix`, host configs, or preflight.

---

## 8. Files Modified

| File | Change |
|---|---|
| `scripts/install.sh` | Create (new file) |
| `README.md` | Replace Step 3 block |

---

## 9. Risks and Mitigations

| Risk | Severity | Mitigation |
|---|---|---|
| User blindly runs the script over HTTP | High | HTTPS enforced; `curl -fsSL` rejects non-TLS and HTTP errors. |
| Wrong variant selected | Low | Menu is numbered with descriptions; variant name printed before build begins; user can re-run. |
| `nixos-rebuild` fails mid-switch | Medium | NixOS switch is atomic; failure leaves the system on the previous generation. Script exits non-zero, no reboot prompted. |
| Script runs on non-NixOS system | Low | `nixos-rebuild` not found → clear error from nixos-rebuild itself; script exits 1. No destructive side-effects before that point. |
| read built-in fails when stdin is a pipe | N/A | `bash <(...)` preserves TTY stdin; this is why process substitution is used instead of `curl ... \| bash`. |
| Upstream raw.githubusercontent.com URL changes (repo rename) | Low | URL is hardcoded; update if repo is renamed. The script URL is also echoed at runtime for discoverability. |

---

## 10. Dependencies

No new Nix packages, flake inputs, or system configuration changes required.  
The script depends only on:
- `bash` (always present on NixOS)
- `curl` (present on NixOS minimal installer and all desktop installs)
- `sudo` (present on all NixOS installs)
- `nixos-rebuild` (present on all NixOS installs)
- `tput` (present via `ncurses`, always present on NixOS)

---

*Spec written by Research Subagent — Phase 1 complete.*
