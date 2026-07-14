# Phase 6 Preflight — `arr_enable_menu` change

`bash scripts/preflight.sh` was executed and failed at stage `[0/8]`
("nix is not installed or not in PATH"). This is an environment constraint
of the current session (Windows/MSYS host, no Nix toolchain), not a defect
introduced by this change — the project's own CLAUDE.md documents that
`nixos-rebuild`/preflight require a NixOS host. All later stages of
preflight (dry-build, stateVersion check, hardware-configuration.nix check,
flake.lock check, formatting, secret scan, package build) could not be
reached and were substituted with the manual checks in
`arr_enable_menu_review.md` (git-tracked-file check, stateVersion grep,
`bash -n` shell syntax check on the modified block), all of which passed.

This change has zero `.nix` surface area (justfile-only diff), so the parts
of preflight that matter for it — `git ls-files hardware-configuration.nix`
and the `system.stateVersion` check — were verified directly and pass.

**Status: cannot be fully executed on this host. Escalating to user per
CLAUDE.md "STOP and report to user" rule for build/preflight failures that
cannot be resolved locally.**
