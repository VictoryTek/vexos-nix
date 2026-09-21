# One-command install — Review

Files: `scripts/install.sh`, `README.md`. Spec: `one_command_install_spec.md`.

## Checks
- `bash -n scripts/install.sh` — OK
- `shellcheck -S warning scripts/install.sh` (nixpkgs 0.11.0) — clean
- `ensure_flake_wrapper` exercised in a sandbox (sudo/`/etc/nixos` stubbed):
  absent → installs byte-identical copy, mode 644; present → no-op, content
  preserved; download failure → exit 1, no file left behind.
- `scripts/preflight.sh` (WSL, Nix 2.34.1) — exit 0, "Preflight PASSED".
  Warnings (jq / nixpkgs-fmt / gitleaks not installed; placeholder string in
  vexboard.nix) are pre-existing and unrelated.
- No `.nix` files changed; stateVersion, hardware-configuration.nix, flake inputs
  untouched. No `lib.mkIf` added.

## Not verified
A real end-to-end run of install.sh on a NixOS host / live ISO (needs a
target machine; `nixos-rebuild` is user-initiated only). The fetched URL is
`raw.githubusercontent.com/.../${VEXOS_REV}/template/etc-nixos-flake.nix`, which
resolves only once this change's commit is on `main`-reachable history — the
template itself already exists there, so this is unaffected by the push.

## Result: PASS
| Category | Grade |
|---|---|
| Spec compliance | A |
| Best practices | A |
| Functionality | A- (no live-host run) |
| Security | A (pinned rev, temp-file + atomic install, no overwrite) |
| Consistency | A |
| Build success | A |
