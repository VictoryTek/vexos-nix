# Specification: Reboot Prompt After `just switch`

## Current State Analysis

### Current `switch` Recipe (justfile lines 72–131)

```just
# Rebuild and switch interactively, or pass role + variant directly.
# Examples:
#   just switch                  — interactive prompt
#   just switch desktop amd      — direct switch
#   just switch desktop amd .    — explicit flake override
switch role="" variant="" flake="":
    #!/usr/bin/env bash
    set -euo pipefail

    if ! command -v nix >/dev/null 2>&1; then
        echo "error: 'nix' command not found. Run this recipe on a Nix-enabled Linux host." >&2
        exit 127
    fi
    if ! command -v sudo >/dev/null 2>&1; then
        echo "error: 'sudo' command not found. Use a Linux host with sudo configured." >&2
        exit 127
    fi
    if [ "$(uname -s 2>/dev/null || echo unknown)" != "Linux" ]; then
        echo "error: just switch must be run on Linux (NixOS target host)." >&2
        exit 1
    fi

    ROLE="{{role}}"
    VARIANT="{{variant}}"
    FLAKE_OVERRIDE="{{flake}}"

    if [ -z "$ROLE" ]; then
        echo ""
        echo "Select role:"
        echo "  1) desktop"
        echo "  2) stateless"
        echo "  3) htpc"
        echo "  4) server"
        echo ""
        while [ -z "$ROLE" ]; do
            printf "Choice [1-4] or name: "
            read -r INPUT
            case "${INPUT,,}" in
                1|desktop) ROLE="desktop" ;;
                2|stateless) ROLE="stateless" ;;
                3|htpc)    ROLE="htpc"    ;;
                4|server)  ROLE="server"  ;;
                *) echo "Invalid — enter 1-4 or desktop/stateless/htpc/server" ;;
            esac
        done
    fi

    if [ -z "$VARIANT" ]; then
        echo ""
        echo "Select GPU variant:"
        echo "  1) amd"
        echo "  2) nvidia"
        echo "  3) intel"
        echo "  4) vm"
        echo ""
        while [ -z "$VARIANT" ]; do
            printf "Choice [1-4] or name: "
            read -r INPUT
            case "${INPUT,,}" in
                1|amd)    VARIANT="amd"    ;;
                2|nvidia) VARIANT="nvidia" ;;
                3|intel)  VARIANT="intel"  ;;
                4|vm)     VARIANT="vm"     ;;
                *) echo "Invalid — enter 1-4 or amd/nvidia/intel/vm" ;;
            esac
        done
    fi

    TARGET="vexos-${ROLE}-${VARIANT}"
    echo ""
    echo "Switching to: ${TARGET}"
    echo ""
    _flake_dir=$(just _resolve-flake-dir "${TARGET}" "${FLAKE_OVERRIDE}")
    sudo nixos-rebuild switch --flake "${_flake_dir}#${TARGET}"
```

The recipe currently ends immediately after `nixos-rebuild switch` completes. Due to `set -euo pipefail`, if the rebuild fails the script exits non-zero and no subsequent code runs — this is the desired safety behavior.

### Other Recipes That Perform `nixos-rebuild switch`

- **`update`** — runs `nix flake update` then `nixos-rebuild switch`. Same reboot applicability.
- **`rollback`** / **`rollforward`** — switch NixOS generations. Same reboot applicability.

This spec focuses on the `switch` recipe only. The pattern can be extended to `update`, `rollback`, and `rollforward` in a follow-up if desired.

---

## Problem Definition

After `just switch` completes a successful `nixos-rebuild switch`, certain configuration changes (kernel upgrades, driver changes, systemd service overhauls, boot loader updates) only take full effect after a reboot. Currently the user must manually run `reboot` or `systemctl reboot` afterward. There is no integrated prompt asking whether to reboot, which is:

1. An extra manual step that's easy to forget.
2. Inconsistent with the interactive UX the `switch` recipe already provides (role/variant prompts).

---

## Proposed Solution Architecture

### Approach: Inline Post-Switch Prompt

Add a y/n reboot prompt **inline at the end of the existing `switch` recipe's shebang script**, immediately after the successful `nixos-rebuild switch` line.

**Why inline (not a separate recipe or flag):**

| Alternative | Rejected Because |
|---|---|
| Separate `reboot` recipe called as a dependency | `just` dependencies run *before* the parent recipe, not after. A post-dependency pattern would require `just switch && just reboot-prompt`, losing single-command UX. |
| `just switch --reboot` flag | `just` does not support arbitrary flags on recipes; recipe parameters are positional. Adding a `reboot` parameter would clutter the existing `role variant flake` signature. |
| `[confirm]` attribute on a separate recipe | `[confirm]` runs *before* the recipe body, not after. It cannot gate a post-build action. |

**Inline is the cleanest approach** because:
- The reboot prompt is only meaningful after a *successful* build.
- `set -euo pipefail` already guarantees the script exits on failure — the prompt code is unreachable if the build fails.
- It keeps the single `just switch` invocation UX intact.
- It matches the existing interactive prompt style (role/variant selection uses the same `read -r` pattern).

### Reboot Command

Use `systemctl reboot` rather than the bare `reboot` command:
- `systemctl reboot` is the canonical systemd method on NixOS.
- It gracefully stops services and unmounts filesystems.
- It is already available on all NixOS systems (no extra dependency).

### Prompt Design

```
Switch complete.

Reboot now? [y/N]:
```

- **Default is No** (`[y/N]` convention) — pressing Enter without input skips the reboot. This is the safe default; an accidental Enter should never trigger a reboot.
- Accept `y` or `Y` as confirmation; everything else (including empty input) is treated as "no".
- On "no", print a brief reminder: `Skipped — reboot manually when ready.`

---

## Implementation Steps

### Step 1: Modify the `switch` Recipe in `justfile`

Append the following block **after** the `sudo nixos-rebuild switch` line (still inside the same shebang script):

```bash
    echo ""
    echo "Switch complete."
    echo ""
    printf "Reboot now? [y/N]: "
    read -r REBOOT_ANSWER || true
    case "${REBOOT_ANSWER,,}" in
        y|yes) echo "Rebooting..."; sudo systemctl reboot ;;
        *)     echo "Skipped — reboot manually when ready." ;;
    esac
```

**Key details:**

- `read -r REBOOT_ANSWER || true` — the `|| true` prevents `set -e` from killing the script if stdin is closed or the user sends EOF (Ctrl+D). In that edge case `REBOOT_ANSWER` is empty, which falls through to the `*` (skip) branch.
- `${REBOOT_ANSWER,,}` — bash lowercase expansion, matching the existing pattern used for role/variant input.
- `sudo systemctl reboot` — uses `sudo` because the user may not be root (the earlier `sudo nixos-rebuild` already established sudo credentials, so this won't re-prompt in most cases).

### Step 2: Exact Modified Recipe

The full `switch` recipe after modification:

```just
# Rebuild and switch interactively, or pass role + variant directly.
# Examples:
#   just switch                  — interactive prompt
#   just switch desktop amd      — direct switch
#   just switch desktop amd .    — explicit flake override
switch role="" variant="" flake="":
    #!/usr/bin/env bash
    set -euo pipefail

    if ! command -v nix >/dev/null 2>&1; then
        echo "error: 'nix' command not found. Run this recipe on a Nix-enabled Linux host." >&2
        exit 127
    fi
    if ! command -v sudo >/dev/null 2>&1; then
        echo "error: 'sudo' command not found. Use a Linux host with sudo configured." >&2
        exit 127
    fi
    if [ "$(uname -s 2>/dev/null || echo unknown)" != "Linux" ]; then
        echo "error: just switch must be run on Linux (NixOS target host)." >&2
        exit 1
    fi

    ROLE="{{role}}"
    VARIANT="{{variant}}"
    FLAKE_OVERRIDE="{{flake}}"

    if [ -z "$ROLE" ]; then
        echo ""
        echo "Select role:"
        echo "  1) desktop"
        echo "  2) stateless"
        echo "  3) htpc"
        echo "  4) server"
        echo ""
        while [ -z "$ROLE" ]; do
            printf "Choice [1-4] or name: "
            read -r INPUT
            case "${INPUT,,}" in
                1|desktop) ROLE="desktop" ;;
                2|stateless) ROLE="stateless" ;;
                3|htpc)    ROLE="htpc"    ;;
                4|server)  ROLE="server"  ;;
                *) echo "Invalid — enter 1-4 or desktop/stateless/htpc/server" ;;
            esac
        done
    fi

    if [ -z "$VARIANT" ]; then
        echo ""
        echo "Select GPU variant:"
        echo "  1) amd"
        echo "  2) nvidia"
        echo "  3) intel"
        echo "  4) vm"
        echo ""
        while [ -z "$VARIANT" ]; do
            printf "Choice [1-4] or name: "
            read -r INPUT
            case "${INPUT,,}" in
                1|amd)    VARIANT="amd"    ;;
                2|nvidia) VARIANT="nvidia" ;;
                3|intel)  VARIANT="intel"  ;;
                4|vm)     VARIANT="vm"     ;;
                *) echo "Invalid — enter 1-4 or amd/nvidia/intel/vm" ;;
            esac
        done
    fi

    TARGET="vexos-${ROLE}-${VARIANT}"
    echo ""
    echo "Switching to: ${TARGET}"
    echo ""
    _flake_dir=$(just _resolve-flake-dir "${TARGET}" "${FLAKE_OVERRIDE}")
    sudo nixos-rebuild switch --flake "${_flake_dir}#${TARGET}"

    echo ""
    echo "Switch complete."
    echo ""
    printf "Reboot now? [y/N]: "
    read -r REBOOT_ANSWER || true
    case "${REBOOT_ANSWER,,}" in
        y|yes) echo "Rebooting..."; sudo systemctl reboot ;;
        *)     echo "Skipped — reboot manually when ready." ;;
    esac
```

### Files Modified

| File | Change |
|---|---|
| `justfile` | Append reboot prompt block after `sudo nixos-rebuild switch` line in the `switch` recipe |

No new files are created. No other recipes are modified.

---

## Dependencies

None. The implementation uses only:
- `bash` builtins (`read`, `echo`, `printf`, `case`)
- `systemctl` (present on all NixOS systems)
- `sudo` (already validated earlier in the recipe)

---

## Risks and Mitigations

| Risk | Likelihood | Impact | Mitigation |
|---|---|---|---|
| Accidental reboot from stray Enter keypress | Low | High | Default is **No** (`[y/N]`). Empty input maps to skip. Only explicit `y`/`yes` triggers reboot. |
| Prompt hangs in non-interactive/piped contexts | Low | Low | `read -r REBOOT_ANSWER \|\| true` handles EOF/closed stdin gracefully — falls through to skip. |
| `sudo systemctl reboot` fails or is denied | Very Low | Low | `sudo` credentials are already cached from the `nixos-rebuild` call. If sudo is somehow revoked, the error is visible and non-destructive. |
| `set -e` kills script on `read` EOF | Medium | Medium | Mitigated by `\|\| true` suffix on the `read` command. |
| Line ending issues (CRLF on Windows checkout) | Low | Medium | Existing `.gitattributes` enforces `*.sh text eol=lf`. The justfile should also use LF; verify after edit. The justfile is not a `.sh` file but is interpreted by bash via shebang — CRLF would break it. Ensure the justfile stays LF. |
| Reboot prompt appears even when no reboot is needed | N/A | None | This is acceptable — the prompt is informational. The user can always decline. Detecting whether a reboot is *actually required* is complex (comparing kernel versions, initrd hashes, etc.) and out of scope for this change. |

---

## Out of Scope

- Adding the same reboot prompt to `update`, `rollback`, or `rollforward` recipes (future follow-up).
- Detecting whether a reboot is actually required (kernel change detection).
- Adding a `--yes` / `--no-reboot` flag (would require restructuring recipe parameters).
