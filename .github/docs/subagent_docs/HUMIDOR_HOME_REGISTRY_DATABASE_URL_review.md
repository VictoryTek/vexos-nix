# Review — humidor / home-registry DATABASE_URL stopgap

Result: **PASS** (no refinement cycles needed)

Scope: `modules/server/humidor.nix`, `modules/server/home-registry.nix`.
No spec file was written for this change; the approach was agreed with the
user in conversation before implementation.

## Change

The app containers now read a composed `DATABASE_URL` from a generated env
file (`dataDir/secrets/<name>-app-env`) written by a new
`<name>-app-env-init` oneshot. The db containers, secrets-init and tmpfiles
are unchanged. joplin and grimmory are untouched.

Schemes were taken from the pre-fix upstream source (humidor before
`27cfd31`, home-registry before `4c9dfc4`):

| Module | Scheme | Password handling |
|--------|--------|-------------------|
| humidor | `postgresql://` | percent-encoded via `jq @uri` (tokio-postgres decodes) |
| home-registry | `postgres://` (hard requirement) | verbatim; unit fails if it contains `@`, `:` or `/` (parser splits on them and does not decode) |

## Validation

| Check | Result |
|-------|--------|
| `nix-instantiate --parse` on both modules | pass |
| Eval `vexos-server-amd` + both services enabled (units, container env, ordering inspected) | pass |
| Eval `vexos-headless-server-amd` + both services enabled | pass |
| Eval `vexos-desktop-amd`, `-nvidia`, `-vm`, `vexos-stateless-amd`, `vexos-htpc-amd` | pass |
| Script logic run on hex, `p@ss:w/rd`, and `sp ace#%$&+=?` passwords | encoding/guard behave as designed |
| `scripts/preflight.sh` | exit 0 |
| `hardware-configuration.nix` not tracked | pass |
| `system.stateVersion` in all configuration-*.nix | present, unchanged (no diff) |
| No new flake inputs; flake.nix / flake.lock unchanged | pass |

Not run: `sudo nixos-rebuild dry-build` (WSL is not NixOS, and the command is
sudo-gated). `nix eval ...toplevel.drvPath`, the CI-equivalent, was used
instead. Preflight stages skipped for missing tools in WSL: flake.lock
pinning/freshness and CI matrix (`jq` not on PATH), format check
(`nixpkgs-fmt`), gitleaks, and the dry-build stage (`vexos-variant` absent).

## Findings

- Option B: no new `lib.mkIf` role-gating; the only conditionals are on
  `cfg.environmentFile`, an option the module declares (permitted carve-out).
- No secrets in the Nix store: the password is read at runtime; the files are
  0600 (`umask 077`) under a 0700 directory.
- Accepted limitation: not exercised against the live images. The scheme
  findings come from upstream source read via WebFetch summaries, and it is
  assumed the published images were built from those pre-fix commits.
- Accepted limitation: home-registry passwords containing `@`, `:` or `/`
  are rejected rather than encoded; lifted once the upstream fix ships.
- Pre-existing, unrelated: `modules/server/vexboard.nix:92` trips the preflight
  secret scan (placeholder string). Not touched.
