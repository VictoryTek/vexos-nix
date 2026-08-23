# install_branding_takeover_spec.md

## Current State Analysis

Following `install_gum_omarchy_spec.md` / `install_gum_omarchy_review.md`,
`scripts/install.sh` now uses `gum choose` / `gum confirm` / `gum input` for
every interactive prompt, with automatic fallback to the original `read -r`
prompts when `gum` is unavailable. Colors are Omarchy-style generic ANSI
(`RED`/`GREEN`/`YELLOW`/`CYAN`), and the script prints its header once at the
top, then scrolls linearly — prompts appear and remain on screen as the script
progresses, rather than the screen being redrawn per step.

The user tried Omarchy's actual installer on a VM and shared 4 screenshots:
a full-screen logo splash ("Press Return to Start Install"), a full-screen
keyboard-layout `gum choose` menu with the logo pinned above it, a full-screen
username `gum input` prompt with the logo still pinned above it, and a
full-screen progress bar ("Installing Omarchy") again with the logo pinned
above. Each screen is a full terminal clear + redraw: the logo banner never
scrolls away, and stale content from the previous step is never visible next
to the new step. This is what makes it read as a dedicated installer rather
than a shell script's stdout.

The user asked for two things:
1. Replace Omarchy's green/blue palette with vexos-nix's own brand colors.
2. Give the installer this same "takes over the whole terminal" feel: logo
   pinned at the top at all times, full clear between steps.

## Brand Color Research

No hex palette is documented in the repo (GNOME accent colors vary per role:
blue/orange/yellow/teal in `modules/gnome-*.nix`, which are OS-desktop accents,
not installer/CLI branding). Sampled the actual logo artwork instead
(`files/pixmaps/desktop/vex.png` and `files/pixmaps/server/vex.png`, via
`magick ... -unique-colors`):

- Teal (wordmark + shield outline): `#0D909E` / `#178690` — converged on
  **`#14A6B8`** for terminal legibility on a dark background (slightly
  brightened from the sampled ~`#0D909E`, same hue).
- Orange (shield accent / "SERVER" banner): `#BE5106` / `#C65C05` — converged
  on **`#E8790C`** for terminal legibility (same hue, brightened).
- These are used only for the brand logo and tagline. The existing semantic
  colors (`GREEN` = success, `RED` = error, `YELLOW` = warning) are unchanged —
  matching Omarchy's own convention of reserving its green/blue for the logo
  specifically while prompt chrome stays neutral.

## Logo Asset

Generated via `toilet -f mono12 "VEXOS"` (toilet is BSD/Affero-licensed,
`nixpkgs#toilet` — used only to *generate* the art at spec-writing time; the
output is hardcoded into the script, no runtime dependency added). Trimmed to
7 lines × 50 columns, fits comfortably in an 80×24 terminal:

```
 ▄▄    ▄▄  ▄▄▄▄▄▄▄▄  ▄▄▄  ▄▄▄    ▄▄▄▄      ▄▄▄▄
 ▀██  ██▀  ██▀▀▀▀▀▀   ██▄▄██    ██▀▀██   ▄█▀▀▀▀█
  ██  ██   ██          ████    ██    ██  ██▄
  ██  ██   ███████      ██     ██    ██   ▀████▄
   ████    ██          ████    ██    ██       ▀██
   ████    ██▄▄▄▄▄▄   ██  ██    ██▄▄██   █▄▄▄▄▄█▀
   ▀▀▀▀    ▀▀▀▀▀▀▀▀  ▀▀▀  ▀▀▀    ▀▀▀▀     ▀▀▀▀▀
```

Colored solid `VEXOS_TEAL`, matching the wordmark color in the real logo.

## Proposed Solution

### 1. New brand color constants

Add `VEXOS_TEAL` / `VEXOS_ORANGE` truecolor (24-bit ANSI) escape sequences
next to the existing `RED`/`GREEN`/`YELLOW`/`CYAN`/`BOLD`/`RESET` block, gated
by the same existing `[ -t 1 ] && tput colors -ge 8` check (no new terminal-
capability detection — reuses the existing gate per the Surgical-Changes
principle).

### 2. `render_header()` function

```bash
VEXOS_LOGO='... (7 lines above, single-quoted heredoc) ...'

render_header() {
  clear
  echo -e "${VEXOS_TEAL}${VEXOS_LOGO}${RESET}"
  echo -e "${BOLD}${VEXOS_ORANGE}VexOS Interactive Installer${RESET}"
  echo ""
}
```

`clear` (not `printf '\033c'`) — standard, terminfo-aware, matches what an
interactive live-ISO TTY expects; falls back harmlessly if `$TERM` is unset
(no-op / error to stderr, doesn't abort under `set -e` since `clear`'s exit
status isn't checked, matching how `echo` calls are used elsewhere).

### 3. Where `render_header` is called — full-screen takeover for standalone prompts

Called immediately before each self-contained interactive prompt (both the
`$GUM` branch and the `read`-fallback branch get the same header — the
clear-and-redraw behavior is independent of gum, so the plain-text fallback
gets the same polish):

- Role selection
- Server sub-type selection
- GPU variant selection
- NVIDIA driver branch selection
- ASUS y/n
- ASUS-laptop y/n

Also called once at the very start of the script (replacing the current
one-time inline header echo) and once more immediately before the "Building
${FLAKE_TARGET}..." message that kicks off the long build/dry-build/rebuild
tail — giving a clean "Installing VexOS" transition screen matching Omarchy's
4th screenshot.

**Deviation found during implementation:** GRUB device input, EFI device
input, and the final reboot confirmation were in the original candidate list
but are deliberately **not** preceded by `render_header`:

- The GRUB and EFI device prompts are the tail end of a multi-line diagnostic
  block (a warning, an explanation, and an `lsblk` device listing) that the
  user needs on screen *while* answering — clearing right before the prompt
  would erase the exact device list the prompt is asking them to read from.
- The final reboot confirmation directly follows the build-success summary
  (generation registered, NVIDIA driver-variant note, etc.) — clearing there
  would hide the summary the user needs to see before deciding whether to
  reboot immediately.

These three are a different kind of prompt from the six above: a
context+question unit rather than a standalone menu, so the "redraw wipes
useful context" risk from the spec's own Risks section applies to them
directly. They keep today's un-cleared, append-only behavior.

### 4. What does NOT get cleared — preserved exactly as-is

The long-running, information-dense sections are **not** wrapped in
`render_header`/`clear`:

- UEFI/GRUB detection and patch messages
- `/boot` mount check messages
- ASUS hardwareModule patch messages
- hostId substitution message
- git-tracking-of-`/etc/nixos` messages
- flake-lock refresh (`gum spin` output)
- dry-build cache-check report (the `UNAVOIDABLE`/`OTHER` package lists) —
  this is deliberately kept scrollable; it's diagnostic output the user is
  meant to review/scroll, not a transient step. Clearing it away the instant
  it appears would remove information the cache-check step exists to show.
- the live `nixos-rebuild` streaming output itself

This mirrors what the screenshots actually show: Omarchy's full-screen clears
apply to *input* screens (keyboard, username) and to a *summary progress bar*
(a single "Installing Omarchy" line + bar, not raw package-manager output).
vexos-nix's dry-build/build output is intentionally verbose (the existing
cache-transparency feature from a prior spec) and must keep scrolling, not
flash and vanish.

### 5. Header re-shown after invalid input

Existing `read`-fallback loops that print `"Invalid selection ..."` and
re-prompt in a `while` loop should also re-run `render_header` at the top of
each loop iteration, so an invalid entry redraws the full screen (logo +
question) rather than stacking an error line under the old prompt. Only
applies to the fallback branches with retry loops (role, server-type, GPU
variant, NVIDIA branch, GRUB/EFI device validation); `gum choose`/`confirm`
already do not need this since they don't have an "invalid input" state.

## Implementation Steps

1. Add `VEXOS_TEAL` / `VEXOS_ORANGE` to the existing color block.
2. Add `VEXOS_LOGO` (single-quoted, literal box-drawing characters) and
   `render_header()` right after the color block, before the `gum` fetch
   block.
3. Replace the current one-time header (lines printing the box-art `======`
   banner, "vexos-nix Interactive Installer", Source/Verify lines) with
   `render_header` + the Source/Verify lines printed once directly beneath it.
4. Insert `render_header` calls at the 8 prompt sites and the 2 phase-
   transition points listed above.
5. Add `render_header` to the top of each `while` retry loop in the fallback
   branches, re-printing the section's own prompt text after it (so the
   question is still visible after the redraw, just without a stale
   "Invalid selection" trail).
6. No `.nix` changes.

## Dependencies

None added. `toilet` was used only to generate the hardcoded ASCII art at
spec-writing time and is not referenced by the script.

## Risks and Mitigations

- **Risk:** `clear` on a non-standard `$TERM` (rare on a live ISO, but
  possible over serial console) prints garbage or errors.
  **Mitigation:** `clear`'s exit status is never checked (matches how the
  rest of the script treats cosmetic output), so a failed `clear` is silently
  a no-op — worst case, the next screen prints below whatever was already
  there, identical to today's behavior.
- **Risk:** Clearing the screen mid-flow could hide an error message from a
  previous step before the user reads it.
  **Mitigation:** `render_header` is only inserted at clean phase boundaries
  (start of the *next* prompt, not immediately after an error) — a failed
  validation (e.g. "not a block device") re-renders the header **and**
  re-prints the question, so the error's *consequence* (being asked again) is
  visible even though the literal error text scrolled away; this matches
  Omarchy's own behavior (invalid keyboard layout just redraws the same
  screen).
- **Risk:** Losing the cache-check / build output to a stray `clear` would
  regress the hard-won dry-build transparency feature.
  **Mitigation:** explicitly scoped out in section 4 above — verified by
  listing every `clear` insertion point in the implementation and confirming
  none falls inside the dry-build/rebuild code path.
