# STATELESS_INSTALL_PROGRESS_BAR — Specification

## REVISION 2 (post-feedback)

The first implementation (committed `f7d1a75`) shipped a **trimmed single-line**
progress bar. User feedback: it must be the **full-screen brand-logo + centered
bar + centered rotating tip** screen, pixel-identical to `install.sh`. Decisions
taken (confirmed with user):

- **Shared `scripts/lib/progress.sh`** is now the single source of truth for the
  full-screen UI. Reverses REV-1's "self-contained port" and the
  `install.sh:991` "no sourced fragment" note — justified because all three
  installer scripts already `curl`-fetch pinned content, and a 3-way-duplicated
  180-line logo/header/animation block is unmaintainable.
- `install.sh` is refactored to source the lib (local checkout when present,
  else `curl` pinned to `$VEXOS_REV`), removing its inline copies.
- `stateless-setup.sh` and `migrate-to-stateless.sh` source the same lib and
  call `render_header` + `run_live_build` at their build sites. Each carries a
  small `_load_progress_lib` loader with a plain-output fallback (kept in sync,
  like the existing `UNAVOIDABLE_REGEX` convention).
- Logo: chafa PNG render with hardcoded-ASCII fallback (same as `install.sh`).
- `migrate-to-stateless.sh` gains the standard `VEXOS_REV` bootstrap block (it
  had none — a pre-existing gap for direct `curl | bash` runs).

Files (REV-2):
- `scripts/lib/progress.sh` — NEW, the shared UI
- `scripts/install.sh` — source the lib; delete ~210 inline lines
- `scripts/stateless-setup.sh` — swap trimmed block → loader + `run_live_build`
- `scripts/migrate-to-stateless.sh` — same, plus `VEXOS_REV` bootstrap

**Deployment note:** `scripts/lib/progress.sh` must be committed AND pushed to
`main` before the `curl`-path installers can fetch it (pinned by `$VEXOS_REV`).
Local `bash scripts/install.sh` runs use the checked-out file immediately.

Everything below is the original REV-1 spec, retained for context.

---

## Phase 1: Research & Specification

### Current state analysis

The "new style" build progress UI (a redrawn progress bar + rotating tips over a
persistent brand logo) lives **only** in `scripts/install.sh`:

| Element | Location | Purpose |
|---|---|---|
| `progress_bar <pct> <width>` | `install.sh:128-138` | Block-character filled/empty bar string |
| `render_progress "<label>" <cur> <total>` | `install.sh:146-150` | Compact `→ [n/m] label` phase line |
| `VEXOS_TIPS=(…)` | `install.sh:153-159` | 5 rotating tip strings |
| `run_live_build "<title>" <cmd…>` | `install.sh:180-263` | Backgrounds `<cmd>`, captures output to `$BUILD_LOG_PATH`, redraws a cursor-addressed bar/tip block below the logo every 0.5 s |
| Call site | `install.sh:1019-1021` | `render_header; run_live_build "Building …" sudo nixos-rebuild "$REBUILD_ACTION" …` |

`run_live_build` is **tightly coupled to the full-screen logo header**: it writes
with absolute cursor addressing (`\033[<dyn_row>;1H`) to the row directly below
the logo, and recomputes `dyn_row` from `HEADER_LINES` (set by `render_header`),
handling `SIGWINCH` to redraw the whole logo on resize.

The two stateless installers have **no logo header and no progress UI** — they
stream raw `nixos-rebuild` / `nixos-install` output:

| Script | Rebuild call | Lines |
|---|---|---|
| `scripts/migrate-to-stateless.sh` | `nixos-rebuild boot --flake "/etc/nixos#vexos-stateless-…"` | `452-462` |
| `scripts/stateless-setup.sh` | `sudo nixos-install --no-root-passwd --flake "/mnt/etc/nixos#…"` | `472-480` |

Both scripts:
- run via `curl -fsSL … | bash` with **no local repo checked out**
- have an identical `RED/GREEN/YELLOW/CYAN/BOLD/RESET` colour block (no `VEXOS_TEAL`)
- use `set -euo pipefail`
- `migrate-to-stateless.sh` runs as **root** (`sudo bash`); `stateless-setup.sh`
  uses `sudo` per-command
- currently run the rebuild **bare** — a non-zero exit aborts the script via
  `set -e` with the raw error already on screen

### Problem definition

The stateless install paths (`migrate-to-stateless.sh` in-place conversion, and
`stateless-setup.sh` fresh-ISO install) do not show the progress-bar UI that
`install.sh` shows for every other role. The user wants visual parity.

### Design decision — self-contained port, NOT a shared sourced library

**Chosen:** add a trimmed, self-contained progress helper directly to each of the
two target scripts.

Rationale (confirmed with user):
- `install.sh:991-992` already establishes the project rule: *"this script runs
  standalone via `curl | bash` … with no local repo present to source a shared
  fragment from"* — the `UNAVOIDABLE_REGEX` constant is deliberately duplicated
  with a manual-sync comment rather than extracted.
- A `scripts/lib/progress.sh` sourced over `curl` would add a network fetch to
  the critical path of scripts that perform disk surgery (subvolume creation,
  `hardware-configuration.nix` rewrite). A failed/oedited fetch mid-run is a new
  failure mode for no user-visible benefit.
- `run_live_build`'s logo/cursor machinery (`render_header`, `HEADER_LINES`,
  `center_block`, `dyn_row`, `SIGWINCH` handling, chafa logo) is not present in
  these scripts and porting it wholesale contradicts *Simplicity First* /
  *Surgical Changes*.

**Trimmed variant:** a single redrawn line (`\r\033[2K`) instead of a
cursor-addressed multi-line block anchored under a logo. These scripts scroll
their output, so `\r` in-place redraw is the correct primitive — no absolute row
math, no resize breakage, and the final line is overwritten with a ✓/✗ status.

### Proposed solution architecture

Add one identical block to **`scripts/migrate-to-stateless.sh`** (after its
colour block, ~line 41) and **`scripts/stateless-setup.sh`** (after its colour
block, ~line 67):

```sh
# ---------- Live build progress (single redrawn line) -----------------------
# Trimmed port of scripts/install.sh's run_live_build (install.sh:124-263).
# That version is cursor-addressed to a fixed row under the persistent
# full-screen logo; these scripts scroll their output, so this variant redraws
# a single line in place with \r. Kept self-contained (not a sourced lib)
# because these scripts run via `curl | bash` with no local repo checked out —
# same rationale as the manually-duplicated UNAVOIDABLE_REGEX in install.sh.
VEXOS_TIPS=(
  "Run 'just update' after reboot to pull the latest cached packages"
  "The Up app checks for and applies system updates from the desktop"
  "vexos-nix tracks /etc/nixos in git — 'sudo git -C /etc/nixos log' shows changes"
  "Re-run this installer any time to switch role or GPU variant"
  "Docs and updates: github.com/VictoryTek/vexos-nix"
)

# progress_bar <pct 0-100> <width> — filled/empty block-character bar string.
# printf's %.0s repeat trick is used instead of tr (which mangles multi-byte
# UTF-8 fill characters); printf runs its format once even with no args, so the
# zero cases are guarded.
progress_bar() {
  local pct="$1" width="$2" filled empty bar=""
  (( pct < 0 )) && pct=0
  (( pct > 100 )) && pct=100
  filled=$(( width * pct / 100 ))
  empty=$(( width - filled ))
  (( filled > 0 )) && bar+="$(printf '█%.0s' $(seq 1 "$filled"))"
  (( empty > 0 )) && bar+="$(printf '░%.0s' $(seq 1 "$empty"))"
  printf '%s' "$bar"
}

# run_build_progress "<label>" <command...> — runs <command...> in the
# background with all output captured to a temp log (exported as
# BUILD_LOG_PATH) while a one-line progress bar + rotating tip redraw in place.
# Progress is a time-based asymptotic curve (no reliable step count to grep, as
# in install.sh). Returns the command's exit code; the caller shows the log
# tail on failure.
run_build_progress() {
  local label="$1"; shift
  local build_log exit_code=0 bar_width=28 elapsed pct tip_idx tip
  local tip_count=${#VEXOS_TIPS[@]} cols tip_budget start_epoch build_pid
  build_log="$(mktemp "${TMPDIR:-/tmp}/vexos-build.XXXXXX.log")"
  BUILD_LOG_PATH="$build_log"

  # Refresh the sudo timestamp so a backgrounded job with redirected stdio does
  # not stall on an expired-sudo password prompt it cannot display.
  sudo -v 2>/dev/null || true

  "$@" >"$build_log" 2>&1 &
  build_pid=$!

  printf '\033[?25l'  # hide cursor
  start_epoch=$EPOCHSECONDS
  while kill -0 "$build_pid" 2>/dev/null; do
    cols=$(tput cols 2>/dev/null || echo 80)
    elapsed=$(( EPOCHSECONDS - start_epoch ))
    pct=$(( 92 * elapsed / (elapsed + 60) ))
    tip_idx=$(( (elapsed / 6) % tip_count ))
    # Fixed prefix ≈ bar_width + len("[]  100%  99m59s  ") → budget the tip so
    # the whole line fits one physical row at any width (a wrapped line leaves a
    # stale fragment when a shorter tip rotates in).
    tip_budget=$(( cols - bar_width - 20 ))
    (( tip_budget < 10 )) && tip_budget=10
    tip="Tip: ${VEXOS_TIPS[$tip_idx]}"
    (( ${#tip} > tip_budget )) && tip="${tip:0:$(( tip_budget - 1 ))}…"
    printf '\r\033[2K%b[%s]%b %3d%%  %dm%02ds  %s' \
      "${VEXOS_TEAL}" "$(progress_bar "$pct" "$bar_width")" "${RESET}" \
      "$pct" "$(( elapsed / 60 ))" "$(( elapsed % 60 ))" "$tip"
    sleep 0.5
  done
  wait "$build_pid" || exit_code=$?

  printf '\r\033[2K\033[?25h'  # clear line, show cursor
  return "$exit_code"
}
```

Add `VEXOS_TEAL` to both colour blocks (matching `install.sh:58`):

```sh
  # if-branch (colour supported):
  VEXOS_TEAL='\033[38;2;20;166;184m'
  # else-branch:
  RED='' GREEN='' YELLOW='' CYAN='' BOLD='' RESET='' VEXOS_TEAL=''
```

### Call-site changes

**`scripts/migrate-to-stateless.sh`** — replace the bare call at `462`:

```sh
if run_build_progress "Building vexos-stateless-${VARIANT}${NVIDIA_SUFFIX}" \
     nixos-rebuild boot --flake "/etc/nixos#vexos-stateless-${VARIANT}${NVIDIA_SUFFIX}"; then
  echo -e "${GREEN}  ✓ Build complete — new generation registered for next boot.${RESET}"
else
  echo ""
  echo -e "${RED}${BOLD}✗ nixos-rebuild boot failed.${RESET}"
  echo "  Last 60 lines of the build log (${BUILD_LOG_PATH}):"
  echo ""
  tail -n 60 "${BUILD_LOG_PATH}" 2>/dev/null || true
  echo ""
  echo -e "${RED}Migration incomplete — fix the error above and re-run this script.${RESET}"
  exit 1
fi
```

Behaviour delta: on failure the script now prints a labelled 60-line log tail
before exiting 1 (previously `set -e` aborted with only the live error visible).
Success path and the subsequent `/nix → @nix` sync are unchanged. The `echo`
lines at `458-461` ("Running nixos-rebuild boot…", "This may take a while…")
are kept.

**`scripts/stateless-setup.sh`** — replace the bare call at `478-480`:

```sh
if run_build_progress "Building ${FLAKE_TARGET}" \
     sudo nixos-install --no-root-passwd --flake "/mnt/etc/nixos#${FLAKE_TARGET}"; then
  echo -e "${GREEN}  ✓ nixos-install complete.${RESET}"
else
  echo ""
  echo -e "${RED}${BOLD}✗ nixos-install failed.${RESET}"
  echo "  Last 60 lines of the install log (${BUILD_LOG_PATH}):"
  echo ""
  tail -n 60 "${BUILD_LOG_PATH}" 2>/dev/null || true
  echo ""
  echo -e "${RED}Installation incomplete — review the log above and re-run.${RESET}"
  exit 1
fi
```

The `echo` lines at `474-476` are kept. `--no-root-passwd` means `nixos-install`
never needs an interactive prompt, so backgrounding it is safe.

### Implementation steps

1. `scripts/migrate-to-stateless.sh`
   1. Add `VEXOS_TEAL` to both branches of the colour block (`32-41`).
   2. Insert the progress block (`VEXOS_TIPS`, `progress_bar`, `run_build_progress`)
      immediately after the colour block.
   3. Wrap the `nixos-rebuild boot` call (`462`) with `run_build_progress` +
      failure handler.
2. `scripts/stateless-setup.sh`
   1. Add `VEXOS_TEAL` to both branches of the colour block (`58-67`).
   2. Insert the identical progress block after the colour block.
   3. Wrap the `sudo nixos-install` call (`478-480`) with `run_build_progress` +
      failure handler.
3. No change to `scripts/install.sh` (already has the UI) or any `.nix` file.

### Module Architecture Pattern (Option B)

Not applicable — this change touches only `scripts/*.sh`. No NixOS modules, no
`lib.mkIf`, no new flake inputs, no `configuration-*.nix` edits.

### Dependencies

None. No new external libraries. Uses only bash builtins + `coreutils`
(`mktemp`, `seq`, `tail`), `tput` (ncurses), all already required by these
scripts. `EPOCHSECONDS` requires bash ≥ 5 — the NixOS ISO ships bash 5.x and
`install.sh` already relies on it. Context7 not applicable (no versioned API).

### Configuration changes

None.

### Risks and mitigations

| Risk | Mitigation |
|---|---|
| Backgrounded `nixos-install` needs a TTY prompt | `--no-root-passwd` removes the only prompt; `install.sh` already backgrounds `nixos-rebuild` the same way |
| Hiding live build output reduces transparency | Full output captured to `$BUILD_LOG_PATH`; 60-line tail shown on failure — same tradeoff `install.sh` already makes |
| `\r` redraw corrupted if the child writes to the same TTY | Child stdout+stderr are redirected to the log file, not the TTY |
| Cursor left hidden if the script is killed mid-build | `printf '\033[?25h'` on the normal path; residual risk only on SIGKILL (acceptable, matches `install.sh` which has the same exposure between frames) |
| `sudo -v` prompts in `stateless-setup.sh` | Script has already run `sudo` commands before this point, so the timestamp is warm; `|| true` prevents `set -e` abort |
| Duplicated `VEXOS_TIPS` / `progress_bar` across 3 scripts drift apart | Header comment points back to `install.sh:124-263` as the source of truth, mirroring the existing `UNAVOIDABLE_REGEX` sync-comment convention |
| Behaviour change: explicit `exit 1` + log tail on rebuild failure | Strict improvement over bare `set -e` abort; documented above |

### Verification / success criteria

- `bash -n` clean on both modified scripts.
- `shellcheck` (via `nix run nixpkgs#shellcheck`) shows no **new** findings vs.
  the pre-change baseline for each file.
- `nix flake show --impure` still succeeds (no structural regression).
- Manual read-through: a simulated run (`run_build_progress "test" sleep 5`)
  renders a redrawing single-line bar and returns exit 0; `run_build_progress
  "test" false` returns 1 and leaves `$BUILD_LOG_PATH` set.
- `git ls-files hardware-configuration.nix` empty; no `system.stateVersion`
  edits (nothing `.nix` touched).
- `bash scripts/preflight.sh` exits 0.
