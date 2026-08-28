# Installer Logo — Render Actual Brand Mark via chafa

## Current state analysis

`scripts/install.sh` renders a hardcoded block-character `VEXOS_LOGO` string
(lines 64-76), generated once via `toilet -f mono12 "VEXOS"`. It is a generic
wordmark render and does not resemble the actual VexOS brand mark — the
shield-with-V icon plus "VEX-OS" wordmark with a snowflake/hex accent between
"EX" and "S", as shipped at `files/pixmaps/*/vex.png`.

`render_header()` (line 102) clears the screen and echoes `$VEXOS_LOGO`
followed by "VexOS Interactive Installer"; it is called ~9 times per run
(once per prompt screen) so whatever replaces it must be cheap to redraw
(precompute once, echo a cached string thereafter — same pattern already
used for `$VEXOS_LOGO` itself).

The script already has an established pattern for optional runtime tools
fetched from the nixpkgs binary cache with a graceful no-op fallback: `gum`
(lines 225-238) and `git` (lines 802-815), both via
`nix build nixpkgs#<pkg> --no-link --print-out-paths`, guarded by
`command -v` first.

The four `files/pixmaps/*/vex.png` copies (desktop/stateless/server/htpc)
have different checksums (per-role variants for GDM/branding use elsewhere)
but the desktop copy is representative of the canonical brand mark and was
visually confirmed to show the shield+V icon and "VEX-OS" wordmark correctly.

`install.sh` runs via `curl | bash` before any local clone exists (see the
`VEXOS_REV` pinning logic at the top of the file), so the logo PNG must be
fetched over HTTP from `raw.githubusercontent.com`, pinned to `$VEXOS_REV`,
the same way `stateless-setup.sh` / `migrate-to-stateless.sh` are fetched.

## Problem definition

Replace the generic toilet-font `VEXOS_LOGO` with a rendering of the actual
brand PNG (`files/pixmaps/desktop/vex.png`), using `chafa` to convert it to
terminal art at runtime, while:

- Not adding a hard dependency — `chafa` unavailable (offline / cache
  unreachable) or the PNG fetch failing must fall back to the existing
  hardcoded block-text logo, never a hard error.
- Not degrading redraw performance — render once, cache the result, reuse it
  across all `render_header()` calls.
- Working acceptably on the minimal live-ISO console (limited font/no true
  color in the worst case) as well as a full terminal emulator — chafa
  auto-negotiates its best supported protocol/symbol set per terminal, so no
  manual capability detection is needed beyond what chafa already does.

## Proposed solution architecture

1. **Fetch chafa** (best-effort), mirroring the existing `gum` block:
   - `command -v chafa` first.
   - Else `nix --extra-experimental-features 'nix-command flakes' build nixpkgs#chafa --no-link --print-out-paths 2>/dev/null || true`.
   - On failure, `CHAFA=""` and the script proceeds straight to the existing
     hardcoded-art fallback (no behavior change from today).

2. **Fetch the logo PNG** (best-effort) to a temp file:
   - `curl -fsSL "https://raw.githubusercontent.com/VictoryTek/vexos-nix/${VEXOS_REV}/files/pixmaps/desktop/vex.png" -o "$tmp" 2>/dev/null || true`
   - Reuses the already-pinned `$VEXOS_REV` so the fetched asset matches the
     running script's commit (same rationale as the top-of-file pinning
     comment).

3. **Render once, cache the result:**
   - If both `$CHAFA` and the downloaded PNG are present, run chafa once at
     script startup (near where `VEXOS_LOGO` is currently defined) with a
     fixed target size tuned for a centered header (e.g.
     `chafa --size=50x16 --animate=off "$tmp"`), capture stdout into
     `VEXOS_LOGO_RENDERED`.
   - `render_header()` echoes `VEXOS_LOGO_RENDERED` if non-empty, otherwise
     falls back to the existing hardcoded `$VEXOS_LOGO` block exactly as
     today.
   - Clean up the temp PNG after rendering (`rm -f "$tmp"`).

4. **Keep the hardcoded `VEXOS_LOGO` string as-is** — it remains the offline
   fallback; do not delete it.

5. **Centering:** chafa output already contains ANSI color codes per line;
   `center_block()` already strips ANSI (`sed 's/\x1b\[[0-9;]*m//g'`) for
   width measurement, so it works unmodified on chafa's output as long as
   each terminal line from chafa doesn't itself contain embedded newlines
   (it doesn't — chafa emits one `\n`-joined line per row).

## Implementation steps (Option B module pattern — N/A)

This is a single bash script change, not a Nix module; the Module
Architecture Pattern (Option B) does not apply. Steps:

1. In `scripts/install.sh`, directly below the existing `gum` fetch block
   (after line 238), add a new `chafa` fetch block following the same
   command-v/nix-build/fallback shape.
2. Directly below that, add the PNG fetch + chafa render step, producing
   `VEXOS_LOGO_RENDERED` (empty string on any failure).
3. Modify `render_header()` (line 107) to prefer `VEXOS_LOGO_RENDERED` when
   non-empty, else use the existing `VEXOS_LOGO` block.
4. No other call sites change — `run_live_build`, `render_progress`, etc.
   are untouched.

## Dependencies

- `chafa` (nixpkgs, `nixpkgs#chafa`) — terminal image renderer, fetched at
  runtime via `nix build`, same mechanism as the existing `gum` dependency.
  No versioned API surface (stable CLI, PNG in / ANSI out) — not applicable
  to Context7 library-doc verification, and no Context7 tool is available in
  this environment.
- No new flake inputs — this is a runtime-fetched CLI tool via
  `nix build nixpkgs#chafa`, not a flake input change, so the
  `follows = "nixpkgs"` requirement in the Repository Notes does not apply.

## Configuration changes

None. No NixOS module, no `configuration-*.nix`, no `flake.nix` changes.

## Post-deploy fix (real-VM report)

A fresh-VM run via the `curl | bash` README path still showed the old
hardcoded ASCII logo. Root cause: `nix build nixpkgs#chafa --no-link
--print-out-paths` prints **one line per derivation output**, and chafa's
nixpkgs derivation has two outputs (`bin`, `man`) — unlike `gum`'s single
output. `_CHAFA_STORE` therefore captured a two-line string, and
`"$_CHAFA_STORE/bin/chafa"` became a garbled multi-line path, so the
`[ -x ... ]` guard failed silently and the script always fell back to
`VEXOS_LOGO`, indistinguishable from the intended offline fallback path.
Fixed by pinning the flake output selector to `nixpkgs#chafa^bin`, which
prints only the binary output's store path. Verified locally
(`nix build nixpkgs#chafa^bin --no-link --print-out-paths` → single line).

## Post-deploy fix #2 (visual quality)

User feedback on a real VM: the rendered logo looked coarse/blocky at the
original fixed `--size=50x16`. Two separate questions were resolved:

- **Sixel/kitty graphics protocol**: already worked with no code change.
  Verified directly: `TERM=xterm-kitty chafa --size=20x10 file.png` run
  through a command-substitution pipe (not a live tty) correctly emitted
  Kitty APC image escape sequences instead of symbol art — chafa's format
  auto-detection reads `$TERM`/`$COLORTERM`/similar env vars, which survive
  piping. The blocky result in the screenshot was chafa correctly falling
  back to symbol mode because that particular terminal (VTE-based, as used
  on the live ISO) doesn't advertise sixel/kitty support — not a detection
  bug.
- **Resolution**: the actual fixable issue. `--size=50x16` was a small
  fixed box regardless of the real terminal's width, capping symbol-mode
  detail well below what the terminal could actually display. Changed to
  size the box to the live terminal width (`tput cols`, minus a 6-column
  margin, capped at 110 to avoid an absurdly large render on ultrawide
  terminals), height capped at 20 rows. Verified: at a realistic 84-column
  width the rendered output grew from ~6.3K chars/~10 rows to ~16K
  chars/~17 rows of block-symbol detail — over 2x the resolution.

## Post-deploy fix #3 (too large)

The 110x20 box from fix #2 rendered a logo tall enough to get cropped at
the top of the terminal window on a real VM. Reduced the cap to 60 cols /
14 rows (closer to, but still denser than, the original 50x16). Verified:
at a representative 54-column width the render is 11 rows / ~6.8K chars —
comparable footprint to the very first attempt, still notably denser than
the original fixed 50x16 since width now tracks the real terminal instead
of being hardcoded.

## Risks and mitigations

- **chafa unavailable / offline install:** falls back to existing hardcoded
  ASCII art — no functional regression versus today.
- **PNG fetch fails (network hiccup, GitHub outage):** same fallback path.
- **Rendering looks poor on very narrow/minimal TTYs (live ISO console,
  8-color, no truetype font):** chafa auto-negotiates symbols-only output
  for limited terminals; worst case is a lower-fidelity but still
  recognizable rendering, not a crash. Fixed `--size=50x16` keeps it inside
  the same footprint `center_block`/`HEADER_PAD` already assume for the
  current 50-column-wide hardcoded logo.
- **Redraw cost:** chafa runs exactly once at startup; all ~9 `render_header`
  calls reuse the cached `VEXOS_LOGO_RENDERED` string, so no added latency
  on redraws.
- **Temp file cleanup:** PNG temp file removed immediately after rendering;
  not left behind on disk.
