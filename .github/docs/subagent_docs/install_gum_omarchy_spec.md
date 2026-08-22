# install_gum_omarchy_spec.md

## Current State Analysis

`scripts/install.sh` is a single self-contained 521-line bash script distributed via
`curl -fsSL .../scripts/install.sh | bash` and run directly on a bare NixOS live ISO,
before any repo is cloned. Key properties that must be preserved:

- Resolves and pins one commit (`VEXOS_REV`) for the entire run, so a moving `main`
  branch can't mix code from two commits mid-install (this also gates
  `stateless-setup.sh` / `migrate-to-stateless.sh` handoffs).
- All user interaction is plain `read -r ... </dev/tty` with numbered menus
  (role, server sub-type, GPU variant, NVIDIA branch, ASUS y/n ×2, GRUB device,
  EFI device, final reboot y/n).
- Color output is hand-rolled ANSI codes gated on `[ -t 1 ]` + `tput colors`.
- Missing `git` is handled today by fetching it from the nixpkgs binary cache via
  `nix build nixpkgs#git --no-link --print-out-paths` and prepending its `bin/` to
  `PATH` — this is the existing precedent for "fetch a tool at runtime on a bare ISO".
- Numerous hard-won, narrowly-scoped fixes already exist in this file (GRUB/UEFI
  detection, ASUS hardwareModule patch, hostId substitution, git-tracking
  `/etc/nixos`, flake-lock refresh, dry-build cache reporting) — see the dozens of
  `install_*_spec.md` / `install_*_review.md` files in this directory. These are not
  to be touched.

## Problem Definition

The user tried Omarchy's installer (basecamp/omarchy) on a VM and liked the polish
of its interactive experience, and asked to adapt vexos-nix's installer around it.

Research into Omarchy's actual `install.sh` (fetched from
`github.com/basecamp/omarchy`, branch `quattro`) shows it is **not** a single
script: it's a thin bootstrap that assumes the whole repo is already git-cloned to
`~/.local/share/omarchy`, then `source`s ~30 small files across
`preflight/`, `provisioning/`, `config/`, `login/`, `post-install/` directories via a
`run_logged()` helper that timestamps each step into `/var/log/omarchy-install.log`.
The actual "nice experience" the user is reacting to comes from Omarchy's use of
**`gum`** (charmbracelet/gum, MIT-licensed, packaged in nixpkgs as `gum` v0.17.0) for
every interactive prompt — arrow-key-navigable `gum choose` menus, `gum confirm`
yes/no prompts, `gum input` text fields, and `gum spin` progress spinners — instead
of raw numbered `read -r` prompts.

Literally copying Omarchy's multi-file `source`-from-local-clone structure is
incompatible with vexos-nix's distribution model: it would require either
curl-fetching a dozen files individually (slower, and reintroduces the exact
mid-run cross-commit race `VEXOS_REV` exists to prevent) or requiring a git clone
up front (changes the one-liner UX). This was raised with the user; they confirmed
they mainly want the polished interaction experience, not the literal file layout.

## Proposed Solution

Keep `scripts/install.sh` a single file (preserve `curl | bash` and `VEXOS_REV`
pinning exactly as-is). Add a `gum`-backed interaction layer with automatic
fallback to the existing `read -r` prompts, and use `gum spin` around the two
long-running steps (flake update, dry-build cache check) for visual feedback
matching Omarchy's feel.

### 1. Fetch `gum` at runtime (mirrors the existing git-fallback pattern)

```bash
GUM=""
if command -v gum >/dev/null 2>&1; then
  GUM="gum"
else
  _GUM_STORE="$(nix --extra-experimental-features 'nix-command flakes' \
    build nixpkgs#gum --no-link --print-out-paths 2>/dev/null || true)"
  if [ -n "$_GUM_STORE" ] && [ -x "$_GUM_STORE/bin/gum" ]; then
    GUM="$_GUM_STORE/bin/gum"
  fi
fi
```

If `$GUM` is empty (offline, cache unreachable, etc.), every helper below falls
back to the script's current `read -r` logic unchanged — no behavior regression,
matching the Simplicity/Surgical principles: don't add error handling for a case
that breaks the rest of the installer too (the flake fetch itself needs network),
but don't hard-fail on gum specifically either since it's cosmetic.

### 2. Small prompt helpers, used only where `$GUM` is set

- `ui_choose "$title" opt1:label1 opt2:label2 ...` → wraps `gum choose --header`,
  returns the selected value; falls back to the existing numbered
  `while [ -z "$X" ]; do read ...; case ...; done` block.
- `ui_confirm "$prompt"` → wraps `gum confirm`; exit status 0/1 used directly in the
  existing `if`/`case` sites (ASUS y/n, ASUS laptop y/n, final reboot).
- `ui_input "$prompt" "$placeholder"` → wraps `gum input --placeholder`; falls back
  to `read -r` (GRUB device path, EFI device path).

These are additive helper functions placed near the existing color-helper block;
the existing `read`-based logic in each selection site is kept as the `else`
branch, not deleted, so a no-network/no-gum environment behaves exactly as today.

### 3. `gum spin` around long-running steps

Wrap only the two steps that currently print "Refreshing flake inputs..." /
"Checking what will be fetched vs built locally..." with
`gum spin --title "..." -- <command>` when `$GUM` is set (their output is captured
to a temp file and printed after, since these steps' output is parsed/inspected
afterward — spinner must not swallow the data the script depends on). Falls back
to the current plain synchronous execution when `$GUM` is empty.

### 4. Everything else unchanged

No changes to: role/variant naming, `FLAKE_TARGET` construction, UEFI/GRUB patch
logic, ASUS hardwareModule patch, hostId substitution, git-tracking of
`/etc/nixos`, flake-lock refresh command, dry-build cache-report parsing,
`nixos-rebuild` invocation, or the `VEXOS_REV` pinning mechanism.

## Implementation Steps

1. Add the `gum` fetch block (section 1) directly after the existing git-fallback
   block (~line 379), so both runtime-tool-fetch patterns sit together.
2. Add `ui_choose` / `ui_confirm` / `ui_input` helper functions after the color
   block (~line 57).
3. Replace each existing prompt site's body with `if [ -n "$GUM" ]; then ui_...;
   else <existing read block>; fi`:
   - Role selection (~line 70-92)
   - Server sub-type selection (~line 96-118)
   - GPU variant selection (~line 150-174)
   - NVIDIA driver branch selection (~line 176-200)
   - ASUS y/n + laptop y/n (~line 202-227)
   - GRUB device input (~line 258-266)
   - EFI device input (~line 312-323)
   - Final reboot y/n (~line 502-513)
4. Wrap the flake-update and dry-build-check commands in `gum spin` per section 3,
   preserving their captured output for existing downstream parsing
   (`SOURCE_BUILDS` awk pipeline, etc.).
5. No changes to any `.nix` file — this is a `scripts/install.sh`-only change, so
   the Module Architecture Pattern (Option B) does not apply here.

## Dependencies

- `gum` (charmbracelet/gum), MIT License, packaged in nixpkgs as `gum`
  (verified present, v0.17.0, via the nixos MCP tool against the `unstable`
  channel). Not added as a flake input — fetched at runtime via
  `nix build nixpkgs#gum`, identical in spirit to the existing `nixpkgs#git`
  runtime-fetch fallback already in this script. No `flake.nix` change needed.
- API usage verified via Context7 (`/charmbracelet/gum`): `gum choose`,
  `gum confirm` (exit-status idiom: `if gum confirm "..."; then`), `gum input
  --placeholder`, `gum spin --title "..." -- <cmd>`.

## Configuration Changes

None. `scripts/install.sh` only.

## Risks and Mitigations

- **Risk:** `gum` fetch fails or hangs on a flaky connection.
  **Mitigation:** `2>/dev/null || true` fallback to empty `$GUM`, script proceeds
  with the existing plain-`read` UX exactly as today — never a hard failure.
- **Risk:** `gum spin` swallows output needed by the `SOURCE_BUILDS` awk/grep
  parsing after the dry-build step.
  **Mitigation:** capture command output to a variable/temp file exactly as done
  today; `gum spin` only wraps the *display* of a progress indicator around the
  command, the command's stdout is still captured the same way regardless of
  whether `gum spin` or plain execution runs it.
- **Risk:** Regressing the well-tested plain-bash flow for non-interactive/offline
  environments (e.g. CI, testing harnesses that pipe answers via stdin).
  **Mitigation:** `$GUM` gate is all-or-nothing per prompt call, existing `read`
  fallback branch is byte-for-byte the current code, not rewritten.
- **Risk:** Touching 8 separate prompt sites in one pass increases surface area
  for a regression in a script with a long history of narrow hard-won fixes.
  **Mitigation:** Phase 3 review re-runs `nix flake show --impure` and the
  required `dry-build` targets; additionally, manually trace each modified
  prompt site's fallback branch against the original file diff to confirm it's
  unchanged.
