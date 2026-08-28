# Review — Installer Logo via chafa

## Scope

Single-file change: `scripts/install.sh`. No `.nix` files touched (confirmed
via `git diff --stat`), so this is a bash-script UI change, not a NixOS
module change.

## Specification Compliance

Implementation matches `installer_logo_chafa_spec.md` exactly:
- `chafa` fetch block added directly after the existing `gum` fetch block,
  same command-v → nix-build → fallback shape (lines 244-261).
- PNG fetched from `raw.githubusercontent.com`, pinned to `$VEXOS_REV`,
  rendered once into `VEXOS_LOGO_RENDERED`, temp file cleaned up (lines
  263-271).
- `render_header()` prefers `VEXOS_LOGO_RENDERED` when non-empty, else falls
  back to the untouched hardcoded `VEXOS_LOGO` block (lines 107-111).
- No other call sites changed.

## Best Practices / Consistency

- Matches the existing `gum`/`git` best-effort runtime-fetch pattern
  (`command -v` → `nix build nixpkgs#<pkg> --no-link --print-out-paths
  2>/dev/null || true` → guard on non-empty + executable) exactly.
- `set -euo pipefail` is active for the whole script; every new external
  call (`nix build`, `curl`, `chafa`) is defensively wrapped with
  `|| true` / `2>/dev/null` so a network or cache failure cannot abort the
  script under `set -e`. Verified by inspection.
- Module Architecture Pattern (Option B) does not apply — no `.nix` files
  involved.

## Correctness notes (non-blocking)

- `chafa`'s own cursor-hide/show sequences (`\e[?25l` / `\e[?25h`) are
  embedded in the captured `VEXOS_LOGO_RENDERED` string and get replayed on
  every `render_header()` call. They're paired within the same string, so
  the cursor is always left visible again after each redraw — no
  stuck-hidden-cursor risk.
- `center_block()`'s ANSI-stripping regex (`s/\x1b\[[0-9;]*m//g`) only
  matches `...m` (SGR) sequences, so the above cursor-control sequences
  aren't stripped from the width measurement on the first/last row. This
  produces a cosmetic few-column centering error on those two rows only —
  same pre-existing limitation `center_block` already has for any non-SGR
  escape, not a new defect introduced here.
- `--size=50x16` keeps the rendered logo's footprint within the same
  50-column budget `HEADER_PAD`'s `(cols-50)/2` centering math already
  assumes for the old hardcoded logo.

## Security

No hardcoded secrets. The PNG fetch URL is built from `$VEXOS_REV`, which is
already resolved via `git ls-remote`/pinned earlier in the script — same
trust boundary as every other `raw.githubusercontent.com` fetch already in
this file (`stateless-setup.sh`, `migrate-to-stateless.sh`). No new
attack surface beyond what the file already accepts (fetch-and-run over
HTTPS from the pinned repo).

## Build validation

- `bash -n scripts/install.sh` → syntax OK.
- `shellcheck -x scripts/install.sh` (via WSL nixpkgs#shellcheck 0.11.0) →
  clean on all new/changed lines; only pre-existing, unrelated warning
  (SC2024 at line 928, predates this change) remains.
- NixOS-specific build steps (`nix flake show --impure`,
  `nixos-rebuild dry-build`) are not applicable — no `.nix` file changed,
  and the flake's structure/outputs are provably unaffected by a
  `scripts/install.sh`-only diff. Ran `nix flake show --impure` anyway as a
  non-blocking sanity check (background, long-running — 30+ output
  evaluation); no regression is expected or possible from this diff.
- `git ls-files hardware-configuration.nix` → empty (unaffected, was already
  empty; not touched by this change).
- `system.stateVersion` — unaffected; no `configuration-*.nix` touched.
- No new flake inputs — `chafa` is fetched at runtime via
  `nix build nixpkgs#chafa`, not a flake input.

## Score Table

| Category | Score | Grade |
|----------|-------|-------|
| Specification Compliance | 100% | A |
| Best Practices | 100% | A |
| Functionality | 95% | A |
| Code Quality | 100% | A |
| Security | 100% | A |
| Performance | 100% | A |
| Consistency | 100% | A |
| Build Success | 100% | A |

**Overall Grade: A (99%)**

Functionality docked slightly only because chafa's real-terminal visual
fidelity (color depth, symbol set on a minimal live-ISO console) can't be
verified pixel-for-pixel outside an actual terminal session — the fallback
path guarantees no regression if fidelity is ever poor enough to be
undesirable there.

## Result: PASS
