# Attic Bootstrap Automation — Spec

## Current State Analysis

- `modules/server/attic.nix` enables `services.atticd` when `vexos.server.attic.enable = true`.
  It reads `ATTIC_SERVER_TOKEN_RS256_SECRET_BASE64` from `cfg.environmentFile`
  (default `/etc/nixos/secrets/attic-credentials`), a file the operator must
  create manually (`openssl genrsa -traditional 4096 | base64 -w0`) before the
  service can start.
- `modules/server/vexboard.nix` already solves the identical problem for its own
  secret (`VEXBOARD_AUTH__SECRET`) via `system.activationScripts.vexboardSecret`,
  guarded by `config.vexos.secrets.backend != "sops"` (sops backend populates the
  secret itself at activation via sops-nix).
- No `attic` CLI is installed anywhere by default — the operator must
  `nix profile install nixpkgs#attic-client` manually on the server before they
  can run `attic login` / `attic cache create` / mint tokens.
- `justfile` already has an `attic-push` recipe (Binary Cache group) that assumes
  `attic login` has already been run. There is no recipe that performs the
  one-time cache bootstrap (login as admin, create the cache, mint a
  restricted push token for CI, print the public key for client config).
- Confirmed upstream (zhaofengli/attic) behavior via `nixos/atticd.nix` and
  `docs.attic.rs/tutorial.html`:
  - `atticd-atticadm` is installed via `environment.systemPackages` as a
    `systemd-run` wrapper that inherits the same config/EnvironmentFile as the
    `atticd` unit — running `sudo atticd-atticadm make-token ...` needs no
    extra flags to reach the RS256 secret.
  - `attic cache info <cache>` output includes a `Public Key: <cache>:<base64>`
    line (right-aligned label, but consistently matchable with a substring grep).
  - `atticadm make-token` flags: `--sub <name> --pull/--push/--delete/--create-cache
    <cache-pattern> --validity "<duration>"` (duration examples: `"3 months"`, `"1s"`).

## Problem Definition

Enabling Attic today requires 8 manual steps split across generating a secret,
installing a CLI, and minting/copying multiple tokens by hand. Two of these are
mechanical and safe to automate:

1. Secret generation for the plaintext backend (steps 1.1–1.2 of the walkthrough).
2. CLI installation, cache bootstrap, and token minting (steps 1.4–1.8).

Step 1.3 (service restart) and Part 2 (network exposure) remain inherently
operator-driven and are out of scope here.

## Proposed Solution

### 1. Auto-generate the RS256 secret (`modules/server/attic.nix`)

Add a `system.activationScripts.atticSecret` entry, directly modeled on
`vexboardSecret`, guarded the same way (`vexos.secrets.backend != "sops"`):

```nix
system.activationScripts.atticSecret =
  lib.mkIf (config.vexos.secrets.backend != "sops") ''
    if [ ! -e "${cfg.environmentFile}" ]; then
      mkdir -p "$(dirname "${cfg.environmentFile}")"
      echo "ATTIC_SERVER_TOKEN_RS256_SECRET_BASE64=$(${pkgs.openssl}/bin/openssl genrsa -traditional 4096 2>/dev/null | ${pkgs.coreutils}/bin/base64 -w0)" \
        > "${cfg.environmentFile}"
      chmod 0600 "${cfg.environmentFile}"
    fi
  '';
```

This only fires when `cfg.environmentFile` doesn't already exist, so it never
clobbers an operator-supplied or sops-managed credentials file. Requires
`pkgs` in the module's function args (already present).

### 2. Install the `attic` CLI automatically

Add `environment.systemPackages = [ pkgs.attic-client ];` inside the existing
`config = lib.mkIf cfg.enable { ... }` block, so the CLI is present on the
server the moment Attic is enabled and rebuilt — no manual `nix profile
install` step.

### 3. `just attic-bootstrap` recipe (`justfile`, Binary Cache group)

New recipe, placed after the existing `attic-push` recipe:

- Preconditions checked with clear errors (not assertions — this is a runtime
  script): `atticd.service` must be active; `attic` CLI must be on PATH.
- Mint a full-access admin token via `atticd-atticadm make-token` and use it
  for a local `attic login` (not persisted anywhere but the local attic client
  config, same as today's manual flow).
- Create the cache (default name `vexos`, overridable via recipe arg) if it
  doesn't already exist — idempotent, so re-running the recipe is safe.
- Fetch the public key via `attic cache info <cache>`.
- Mint a push-only, single-cache token for CI (`--push <cache>`, 1 year
  validity, `--sub "github-actions"`).
- Print a copy-pasteable summary: admin token (private), ready-to-paste Nix
  snippet for `vexos.attic.cacheUrl`/`vexos.attic.publicKey` (safe to commit),
  and the CI push token (secret, goes into a GitHub Actions repo secret).

### 4. Update in-repo guidance text

- `modules/server/attic.nix` header comment: remove the "create this file
  manually" instruction, replace with a note that it's auto-generated, and
  point to `just attic-bootstrap`.
- `justfile`'s `just enable attic` post-enable info block (~line 2225): same
  update — drop the manual `openssl genrsa` step, mention `just
  attic-bootstrap` for cache creation and token minting.

## Implementation Steps (Module Architecture Pattern — Option B)

This is a change to an existing role-agnostic server-service module
(`modules/server/attic.nix`) that only adds content inside its own
`lib.mkIf cfg.enable` block, gated by an option the *same module* declares
(`cfg.enable`) — this is the documented carve-out, not new role-smuggling.
No new module file is needed. `justfile` changes are tooling, not a NixOS
module, so the Option B pattern doesn't apply there.

1. Edit `modules/server/attic.nix`: add activation script + systemPackages.
2. Edit `justfile`: add `attic-bootstrap` recipe; update `enable attic` info text.
3. Edit `modules/server/attic.nix` header comment.

## Dependencies

No new flake inputs or external libraries. Uses only packages already in
nixpkgs (`pkgs.openssl`, `pkgs.coreutils`, `pkgs.attic-client`) — all resolved
via the existing `nixpkgs` input already pinned in this flake. Context7/new-dependency
research is not applicable (internal change, no new external library).

## Configuration Changes

None to existing option defaults or NixOS module interfaces — `cfg.environmentFile`
keeps its current default and type. No new user-facing options are introduced;
this only changes what happens automatically when the existing `enable` option
is set.

## Risks and Mitigations

- **Risk:** activation script silently overwrites a secret an operator is
  mid-way through configuring manually.
  **Mitigation:** guarded by `[ ! -e "${cfg.environmentFile}" ]` — never
  touches an existing file, and skipped entirely under the sops backend.
- **Risk:** `just attic-bootstrap` re-run mints a fresh admin token every time,
  which is harmless but noisy.
  **Mitigation:** documented as expected in the recipe's help text; cache
  creation itself is idempotent (checked via `attic cache info` before
  creating).
- **Risk:** RSA key generation (`genrsa -traditional 4096`) is CPU-heavy but
  runs once, at first activation, on a server role — acceptable one-time cost
  during `nixos-rebuild switch`, not on every activation.
- **Risk:** exposing an admin-scoped token in terminal scrollback.
  **Mitigation:** unavoidable for a CLI tool; the recipe labels it clearly as
  private and the walkthrough already treats prior manually-minted tokens the
  same way. No regression versus the manual process.

## Verification Plan

1. `nix flake show --impure` — flake structure still valid.
2. `sudo nixos-rebuild dry-build --flake .#vexos-desktop-amd` — unaffected role, sanity check.
3. `sudo nixos-rebuild dry-build --flake .#vexos-desktop-nvidia`
4. `sudo nixos-rebuild dry-build --flake .#vexos-desktop-vm`
5. `sudo nixos-rebuild dry-build --flake .#vexos-server-amd` — touches `modules/server/attic.nix`, required per Phase 3 rules for server-module changes.
6. `sudo nixos-rebuild dry-build --flake .#vexos-headless-server-amd` — same reason.
7. `git ls-files hardware-configuration.nix` — must return empty.
8. Confirm no `system.stateVersion` changes in any `configuration-*.nix`.
9. `just --list` / `just --fmt --check` (if available) or manual syntax review of the new justfile recipe — justfile has no dry-run; correctness verified by inspection since it cannot run against a live atticd in this environment.
