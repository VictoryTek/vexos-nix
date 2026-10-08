# Review — `just` menu stays open after read-only actions

Spec: `.github/docs/subagent_docs/just_menu_stay_spec.md`
Modified: `justfile` (`_menu` helper + `stay` markers on service/vpn/feature/kernel/cache items)

## Findings

- **Spec compliance:** implemented as specified — 4th `stay` field, `stays` array,
  `while true` loop, `picked` gate, child run with `|| true`, cancel-on-stay returns to menu.
- **Module Architecture Pattern:** not applicable (justfile only); no Nix modules touched,
  no new `lib.mkIf`.
- **Regression surface:** direct calls (`just demo ls`) and non-stay items still reach the
  unchanged `exec` path; non-TTY path unchanged.
- **Minor behaviour change (intentional/benign):** EOF at an argument prompt now prints
  "cancelled" before exiting 1 (previously exited 1 silently).
- **Security:** no secrets, no new privilege use.

## Functional test (real `_menu` extracted into a temp justfile, run under a pty in WSL, `just` from nixos-26.05)

| Case | Result |
|------|--------|
| stay item ×2 then Quit | menu redrawn after each; exit 0 |
| non-stay item | runs, exits (no redraw) |
| stay item with arg prompt, valid arg | runs, menu redrawn |
| stay item with arg prompt, empty arg | "cancelled", menu redrawn |
| non-stay item with arg prompt, empty arg | "cancelled", exit 1 (unchanged) |
| direct `just demo ls` | runs, no menu |

## Build validation

`nix flake show` / `nixos-rebuild dry-build`: the change touches only `justfile`; no Nix
evaluation input changed. Covered by the full `scripts/preflight.sh` run in Phase 6.

## Score

| Category | Score | Grade |
|----------|-------|-------|
| Specification Compliance | 100% | A+ |
| Best Practices | 95% | A |
| Functionality | 100% | A+ |
| Code Quality | 95% | A |
| Security | 100% | A+ |
| Performance | 100% | A+ |
| Consistency | 100% | A+ |
| Build Success | 100% | A+ |

**Overall Grade: A+ (99%)**

**Result: PASS** — Phase 6 `scripts/preflight.sh` (WSL, all 10 stages) exited 0: "Preflight PASSED — safe to push."
