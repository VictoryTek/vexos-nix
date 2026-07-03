# H-15 — Complete the sops-nix phased migration

Status: Phase 1 (Research & Specification)
Source: MASTER_PLAN FEATURES 1.2, ARCH 4.2 · `modules/secrets-sops.nix`, `modules/server/vexboard.nix`

## Current State

- `modules/secrets-sops.nix` implements `vexos.secrets.backend` (`plaintext` | `sops`,
  default `plaintext`). When set to `sops`, it declares `sops.secrets`/`sops.templates`
  for exactly 5 secrets (nextcloud, photoprism, minio user+pass, attic) and force-overrides
  the corresponding service options. `sops-nix` is already a pinned flake input
  (`flake.nix:27`, `sopsBase` at `flake.nix:132`, included in server + headless-server
  `baseModules`).
- Nothing switches `vexos.secrets.backend` to `"sops"` anywhere — the backend is
  reachable only by hand-editing a host config, and no justfile recipe helps a user
  actually generate an age key / sops file / edit secrets. This is ARCH 4.2 ("sops
  unreachable by default").
- VexBoard (`modules/server/vexboard.nix`) ships a literal placeholder auth secret
  (`"change-me-set-vexos.server.vexboard.secretFile"`) unless the user manually creates
  `/etc/nixos/secrets/vexboard-secret` — a manual, easy-to-skip step (this is what H-09
  added the hard assertion for; it still requires manual secret creation).
- Per-service current secret plumbing, verified by reading each module and the upstream
  NixOS module source (nixpkgs pinned by this flake, checked directly in the Nix store):
  - `vexboard.nix`: `secretFile` (path, systemd `EnvironmentFile`, format `KEY=VALUE`) — sops-ready.
  - `kiji-proxy.nix`: `environmentFile` (string path, systemd `EnvironmentFile`) — sops-ready.
  - `listmonk.nix` (our wrapper) has no secret option, but the **upstream** NixOS
    `services.listmonk` module already has a native `secretFile` option
    (`nixos/modules/services/mail/listmonk.nix`) wired to `EnvironmentFile` — sops-ready
    with no wrapper changes.
  - `vaultwarden.nix`: no secret option exists at all. `ADMIN_TOKEN` is only mentioned in
    a comment; there is no `environmentFile`/`adminTokenFile` plumbed into
    `services.vaultwarden.environmentFile`.
  - `authelia.nix`: bare `oci-containers` wrapper; no secret handling of any kind. Config
    files (`configuration.yml`, `users_database.yml`) are expected to be hand-placed at
    `/var/lib/authelia/config`. Authelia's binary natively supports `*_FILE`-suffixed env
    vars (`AUTHELIA_JWT_SECRET_FILE`, `AUTHELIA_SESSION_SECRET_FILE`,
    `AUTHELIA_STORAGE_ENCRYPTION_KEY_FILE`) that point at a file it reads at container
    start — container-native and file-based, i.e. directly sops-compatible, but our
    wrapper doesn't expose it yet.
  - `code-server.nix`: upstream `services.code-server.hashedPassword` is a plain `str`
    baked directly into `environment.HASHED_PASSWORD` in the generated systemd unit
    (`nixos/modules/services/web-apps/code-server.nix`). There is no file-based input.
    Any value assigned — including one derived from a sops secret — still needs to exist
    as a plain Nix string at **eval time**, but sops-nix secrets only exist as decrypted
    files at **activation/runtime** on the target host. There is no way to get a
    runtime-only secret into an eval-time string. The only workaround is overriding the
    unit's own `Environment=`/`EnvironmentFile=` merge order, which depends on
    undocumented systemd directive-ordering behavior — a fragile hack. **Excluded from
    this pass** (see Risks).

## Problem Definition

The sops-nix backend exists but is dead code in practice: no automation reaches it, only
5 of the services that actually hold secrets are wired to it, and one of those five
(VexBoard) still requires a manual plaintext step before the hard assertion added in H-09
is satisfied.

## Proposed Solution

1. **Extend `modules/secrets-sops.nix`** with 3 more services, following the exact
   existing pattern (one `sops.secrets` entry or `sops.templates` entry per service, one
   assertion, one `lib.mkForce` override):
   - `vexboard-auth-secret` → template `vexboard-credentials` (`VEXBOARD_AUTH__SECRET=...`)
     → forces `vexos.server.vexboard.secretFile`.
   - `kiji-proxy-openai-key` → template `kiji-proxy-env` (`OPENAI_API_KEY=...`) → forces
     `vexos.server.kiji-proxy.environmentFile`.
   - `listmonk-admin-password` → template `listmonk-env`
     (`LISTMONK_ADMIN_USER=...` / `LISTMONK_ADMIN_PASSWORD=...`, per
     <https://listmonk.app/docs/configuration/#environment-variables>) → forces
     `services.listmonk.secretFile` directly (native upstream option, no wrapper change).

2. **Add a new option to `modules/server/vaultwarden.nix`**:
   `vexos.server.vaultwarden.environmentFile` (nullable path, default `null`), forced
   through to `services.vaultwarden.environmentFile`. Then add a
   `vaultwarden-admin-token` secret + template in `secrets-sops.nix` that forces this new
   option when `backend == "sops"`. Mirrors the existing plaintext option pattern used by
   every other service module in this repo (nothing new architecturally, just the
   plumbing vaultwarden.nix is currently missing).

3. **Add new options to `modules/server/authelia.nix`**:
   `jwtSecretFile`, `sessionSecretFile`, `storageEncryptionKeyFile` (nullable paths,
   default `null`). When any is non-null, mount it read-only into the container at a
   fixed path (e.g. `/secrets/<name>`) and set the matching `AUTHELIA_*_FILE` environment
   variable to that in-container path. This is Authelia's own documented mechanism, not a
   NixOS-level workaround. Then add 3 corresponding sops secrets in `secrets-sops.nix`.

4. **`just secrets-init` recipe** (new, in the "Server Services Management" section of
   `justfile`, alongside the existing `enable`/`status` recipe family): a guided one-time
   setup that:
   - Generates an age key at `/var/lib/sops-nix/key.txt` if absent (`age-keygen`), or
     reports the existing one's public key.
   - Prints the public key and a `.sops.yaml` snippet the user pastes in themselves
     (the private key must never be written into the tracked repo, so this stays manual).
   - Does **not** attempt to auto-encrypt a full secrets.yaml — sops's own `sops
     <file>.yaml` edit workflow is the correct tool for that and shouldn't be reimplemented
     in bash.

5. **Auto-generate the VexBoard secret at activation**: a `system.activationScripts` entry
   (gated on `vexos.secrets.backend == "sops"` being false and VexBoard being enabled,
   i.e. only for the plaintext path — the sops path already gets its secret from the sops
   file) that runs `openssl rand -base64 48` into
   `/etc/nixos/secrets/vexboard-secret` with `install -m 0600` if the file doesn't already
   exist. Placed in `modules/server/vexboard.nix` next to the existing assertion, not a
   new module.

## Implementation Steps (Module Architecture Pattern — Option B)

This is all additive changes to existing role-specific/server-service modules (each
`modules/server/*.nix` file is already a role addition, one file per service — no shared
base module is touched, no new `lib.mkIf` guards are added to shared files):

1. `modules/server/vaultwarden.nix` — add `environmentFile` option + wire to
   `services.vaultwarden.environmentFile`.
2. `modules/server/authelia.nix` — add 3 file options + container volume mounts + env vars.
3. `modules/server/vexboard.nix` — add activation-script secret generator (plaintext path only).
4. `modules/secrets-sops.nix` — add 3 new secrets/templates + assertions + force-overrides
   (vexboard, kiji-proxy, listmonk) + 4 more for vaultwarden/authelia (1 + 3).
5. `justfile` — add `secrets-init` recipe.

## Dependencies

`sops-nix` is already a pinned flake input (`github:Mic92/sops-nix`, `flake.nix:27`) — no
new dependency added. No Context7 lookup required per CLAUDE.md's exemption ("Projects
where all dependencies are managed by a lock file with no new additions"). Upstream
NixOS module APIs (`services.listmonk`, `services.code-server`,
`services.vaultwarden`) were verified directly against the nixpkgs revision this flake
is pinned to (via the local `/nix/store` source tree), not from training-data memory.

## Configuration Changes

None to `flake.nix` — all changes are within already-imported modules. No new flake
outputs, no new roles.

## Risks and Mitigations

- **code-server exclusion**: documented above. Mitigation: none needed — the value stored
  (`hashedPassword`) is already a one-way hash, not a raw secret, and it lives in
  `/etc/nixos` (untracked, per H-10), not the public repo. Revisit only if upstream adds
  a file-based option.
- **Authelia container secret mount**: mounting a sops-decrypted file into a container
  requires the file to be readable by the container's runtime user; sops-nix secrets
  default to `owner = "root"`, and `virtualisation.oci-containers` (docker backend) runs
  containers as root by default in this repo's existing authelia setup, so no permission
  change needed.
- **Backwards compatibility**: `vexos.secrets.backend` defaults to `"plaintext"` — none of
  this changes behavior for existing installs unless they explicitly opt into `"sops"`.
- **`secrets-init` scope**: kept deliberately thin (key generation + instructions only) to
  avoid reimplementing sops's own encrypt/edit workflow, per Simplicity First.
