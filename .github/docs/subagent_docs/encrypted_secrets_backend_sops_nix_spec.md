# Specification: Encrypted Secrets Backend (sops-nix)

Feature: `encrypted-secrets-backend-sops-nix`
Status: Draft
Created: 2026-05-18
Severity: High (Security)

---

## 1. Current State Analysis

### 1.1 Triggering unresolved finding

`full_code_analysis.md` flags plaintext service secrets for server modules (target entry around line 703):

- `services.nextcloud.config.adminpassFile = "/etc/nixos/secrets/nextcloud-admin-pass"`
- `services.minio.rootCredentialsFile = "/etc/nixos/secrets/minio-credentials"`
- `services.photoprism.passwordFile = "/etc/nixos/secrets/photoprism-password"`
- `services.atticd.environmentFile = "/etc/nixos/secrets/attic-credentials"`

Source evidence:
- `.github/docs/subagent_docs/full_code_analysis.md:703`
- `modules/server/nextcloud.nix:55`
- `modules/server/minio.nix:36`
- `modules/server/photoprism.nix:27`
- `modules/server/attic.nix:34`

### 1.2 How secrets are currently handled

- `modules/secrets.nix` enforces filesystem permissions only:
  - creates `/etc/nixos/secrets` as `0700 root:root`
  - reapplies `0600 root:root` for files in that directory
- Secret material is manually created out-of-band via `sudo install ... /etc/nixos/secrets/<name>`.
- Comments already acknowledge future migration to `sops-nix` or `agenix`.

Source evidence:
- `modules/secrets.nix:2`
- `modules/secrets.nix:19`
- `modules/secrets.nix:25`
- `modules/secrets.nix:27`
- `modules/secrets.nix:31`

### 1.3 Scope and wiring in this repository

- Server roles import `./modules/secrets.nix` and `./modules/server`:
  - `configuration-server.nix:21`
  - `configuration-headless-server.nix:14`
- Optional service toggles are host-local (`/etc/nixos/server-services.nix`) via `serverServicesModule` in `flake.nix`.
- Preflight scans for hardcoded patterns but does not enforce encrypted backend adoption.

Source evidence:
- `flake.nix:78`
- `scripts/preflight.sh:297`
- `scripts/preflight.sh:302`

### 1.4 Security reality

Current state is permission-hardened plaintext-at-rest. This protects against accidental broad local read, but does not provide:

- cryptographic protection at rest
- auditable encrypted secret history in Git
- declarative secret wiring tied to service activation
- deterministic key ownership model for team/host access

---

## 2. Problem Definition and Threat Model

### 2.1 Problem definition

The server stack still depends on manually provisioned plaintext files under `/etc/nixos/secrets`. This is operationally fragile and fails the desired declarative security posture.

### 2.2 Threat model

Assets:
- admin credentials and API tokens for Nextcloud, MinIO, PhotoPrism, Attic
- service startup integrity (only intended secrets consumed)

Adversaries / failure modes:
- local non-root process reading misconfigured secret files
- accidental plaintext commit or shell history leakage during manual creation
- drift between documented and actual secret paths
- operator error during host bootstrap / service enable

Trust assumptions:
- root on target host is trusted
- host SSH key or dedicated age key can be protected
- encrypted files may be stored in Git if recipients are correct

Security objective:
- move from plaintext-at-rest to encrypted-at-rest with declarative runtime materialization and explicit ownership/permissions.

---

## 3. Research Summary (Credible Sources)

Mandatory Context7 requirement for `sops-nix` was completed first:
- Resolved library ID: `/mic92/sops-nix`
- Pulled docs for:
  - Flake/NixOS module integration
  - `sops.secrets` ownership/permissions/path usage
  - age key handling (`sops.age.*`, `ssh-to-age`, `age-keygen`)

Minimum-source requirement is satisfied with the following sources:

1. `sops-nix` README (integration, secret mapping, permissions, templates, age key config)
   - https://github.com/Mic92/sops-nix/blob/master/README.md
2. `sops` project docs/README (`.sops.yaml`, creation rules, age recipients, `updatekeys`)
   - https://github.com/getsops/sops/blob/main/README.rst
3. `age` README (key generation and recipient-based encryption model)
   - https://github.com/FiloSottile/age/blob/main/README.md
4. `age-keygen` manpage (`-o`, `-y`, `-pq`, recipient derivation)
   - https://github.com/FiloSottile/age/blob/main/doc/age-keygen.1.html
5. Nixpkgs Nextcloud module docs (`adminpassFile` pattern)
   - https://github.com/nixos/nixpkgs/blob/master/nixos/modules/services/web-apps/nextcloud.md
6. Nixpkgs MinIO module (`rootCredentialsFile` and EnvironmentFile format)
   - https://github.com/nixos/nixpkgs/blob/master/nixos/modules/services/web-servers/minio.nix
7. Nixpkgs PhotoPrism module (`passwordFile` mapped via `LoadCredential`)
   - https://github.com/nixos/nixpkgs/blob/master/nixos/modules/services/web-apps/photoprism.nix
8. Nixpkgs Atticd module (`environmentFile` required, assertion + hardening)
   - https://github.com/nixos/nixpkgs/blob/master/nixos/modules/services/networking/atticd.nix

---

## 4. Architecture Options and Tradeoffs

### Option A: Keep plaintext `/etc/nixos/secrets` (status quo)

Pros:
- zero migration effort
- no new dependencies

Cons:
- no cryptographic protection at rest
- manual, non-declarative lifecycle
- weak auditability and team scaling

Decision: Reject.

### Option B: Adopt `agenix`

Pros:
- age-native and popular in Nix ecosystems

Cons:
- introduces different workflow than requested target
- requires additional design decision beyond unresolved item request

Decision: Not selected for this feature.

### Option C: Adopt `sops-nix` with age backend (recommended)

Pros:
- declarative secret definitions (`sops.secrets`)
- per-secret path/owner/mode controls
- supports file templating for env-style credentials
- strong compatibility with NixOS module patterns and rollback model

Cons:
- key management bootstrap required
- migration sequencing needed to avoid abrupt breakage

Decision: Select.

### Option D: Use only `systemd-creds`

Pros:
- native systemd credential loading patterns

Cons:
- no standard encrypted-in-Git workflow by itself
- would require extra orchestration to match desired declarative encrypted-at-rest model

Decision: Not selected for primary migration.

---

## 5. Recommended Approach (Phased Rollout)

### Phase 0: Dependency and module wiring (non-breaking)

- Add `sops-nix` flake input with follows policy.
- Wire `sops-nix.nixosModules.sops` into server and headless-server pathways.
- Keep plaintext behavior as default to avoid abrupt deployment breakage.

### Phase 1: Dual-backend compatibility layer (default remains plaintext)

- Introduce a new secrets backend option:
  - `vexos.secrets.backend = "plaintext" | "sops"` (default `"plaintext"`)
- Add explicit service secret path options in server modules, defaulting to current plaintext paths.
- Add a new module (recommended name: `modules/secrets-sops.nix`) that, when backend is `sops`, sets:
  - `sops.defaultSopsFile`
  - `sops.age` key settings
  - `sops.secrets` declarations and secret owners/modes
  - `sops.templates` for env-style files (MinIO and Attic)

### Phase 2: Opt-in encrypted deployment

- Operators create `.sops.yaml` recipient rules and encrypted secret file(s).
- Flip backend in host-local service toggle file:
  - `/etc/nixos/server-services.nix` sets `vexos.secrets.backend = "sops"`.
- Rebuild and validate service starts against `/run/secrets`/templated credentials paths.

### Phase 3: Secure-by-default transition (after successful soak period)

- Change default backend from `plaintext` to `sops`.
- Keep plaintext mode available for emergency rollback during one deprecation window.
- Later remove plaintext compatibility once all hosts are migrated.

---

## 6. File-by-File Implementation Plan

### 6.1 `flake.nix`

Changes:
- Add input:
  - `inputs.sops-nix.url = "github:Mic92/sops-nix";`
  - `inputs.sops-nix.inputs.nixpkgs.follows = "nixpkgs";`
- Include `sops-nix` in outputs argument set.
- Wire module for server + headless-server role composition and `mkBaseModule` parity.

Why:
- ensures both direct repo builds and thin-wrapper `nixosModules.*Base` consumers receive identical secret backend capabilities.

### 6.2 `modules/secrets.nix`

Changes:
- Keep existing tmpfiles enforcement as legacy compatibility baseline.
- Clarify this module is backend-agnostic directory hardening and plaintext fallback support.

Why:
- preserves current behavior and rollback path.

### 6.3 New file: `modules/secrets-sops.nix`

Changes:
- Add `vexos.secrets.backend` option and `sops` backend configuration.
- Declare secret mappings for:
  - nextcloud admin password
  - photoprism admin password
  - minio root credentials (template)
  - attic credentials (template)
- Configure secret ownership and modes per service user needs.
- Add assertions when backend is `sops`:
  - required sops file path configured
  - expected secrets are defined

Why:
- centralizes encrypted backend logic and avoids role-conditional logic in shared modules.

### 6.4 `modules/server/nextcloud.nix`

Changes:
- Add `vexos.server.nextcloud.adminPassFile` option.
- Default remains `/etc/nixos/secrets/nextcloud-admin-pass`.
- Replace hardcoded path with option reference.

Why:
- enables backend swap without behavior change for existing deployments.

### 6.5 `modules/server/minio.nix`

Changes:
- Add `vexos.server.minio.rootCredentialsFile` option.
- Default remains `/etc/nixos/secrets/minio-credentials`.
- Replace hardcoded path with option reference.

Why:
- supports transition to `sops.templates.<...>.path` cleanly.

### 6.6 `modules/server/photoprism.nix`

Changes:
- Add `vexos.server.photoprism.passwordFile` option.
- Default remains `/etc/nixos/secrets/photoprism-password`.
- Replace hardcoded path with option reference.

Why:
- aligns with same migration pattern and explicit path ownership.

### 6.7 `modules/server/attic.nix`

Changes:
- Add `vexos.server.attic.environmentFile` option.
- Default remains `/etc/nixos/secrets/attic-credentials`.
- Replace hardcoded path with option reference.

Why:
- supports templated env file path from `sops-nix` while preserving current behavior.

### 6.8 `template/server-services.nix`

Changes:
- Add commented examples for backend selection and sops file path configuration.
- Document migration commands (`sops edit`, key setup, rebuild).

Why:
- this is the primary operator touchpoint for enabling server services in the current architecture.

### 6.9 `scripts/preflight.sh`

Changes:
- Extend secret checks to validate backend consistency:
  - if `vexos.secrets.backend = "sops"` appears in tracked configuration, verify required `sops` declarations exist
  - warn/fail on newly introduced plaintext secret file path hardcoding in server modules
- keep existing hardcoded-secret scan behavior, but add backend-aware checks.

Why:
- enforce migration integrity and prevent regressions to plaintext wiring.

### 6.10 New recommended repo files

- `.sops.yaml` (recipient + creation rules)
- encrypted secrets file(s), for example under `secrets/server/`

Note:
- To avoid abrupt breakage, these can be introduced while backend default remains `plaintext`.

---

## 7. Dependency Additions and Follows Policy Rationale

Dependency to add:
- `sops-nix` (flake input)

Required wiring:
- `inputs.sops-nix.inputs.nixpkgs.follows = "nixpkgs"`

Rationale:
- aligns with repository policy to avoid duplicate nixpkgs graphs for new inputs
- does not alter the existing intentional `nixpkgs-unstable` policy
- does not override upstream `proxmox-nixos` pinning policy

No additional flake dependency is required for this feature.
- `age`, `sops`, and `ssh-to-age` are operational tools available from nixpkgs packages when needed.

---

## 8. Risks and Mitigations

1. Risk: Services fail to start due to missing decrypt key/materialized secret.
   - Mitigation: backend-gated assertions and staged opt-in (`plaintext` default initially).

2. Risk: Incorrect owner/mode causes runtime permission failures.
   - Mitigation: set `sops.secrets.<name>.owner/group/mode` explicitly per service user.

3. Risk: Nextcloud path churn with rotating `/run/secrets.d/N` symlink generation.
   - Mitigation: preserve documented workaround and test with current Nextcloud module guidance.

4. Risk: Operator key loss blocks decryption.
   - Mitigation: multi-recipient `.sops.yaml` (admin key + host key), documented recovery process.

5. Risk: Drift between thin-wrapper host files and repo module wiring.
   - Mitigation: update both `mkHost` path and `mkBaseModule` path in `flake.nix`.

---

## 9. Validation Plan

### 9.1 Static/build validation

- `nix flake check`
- `sudo nixos-rebuild dry-build --flake .#vexos-server-amd`
- `sudo nixos-rebuild dry-build --flake .#vexos-headless-server-amd`
- `bash scripts/preflight.sh`

### 9.2 Functional validation (plaintext compatibility)

- Keep backend default `plaintext`.
- Confirm existing secrets in `/etc/nixos/secrets/*` continue to work for all four services.

### 9.3 Functional validation (sops backend)

- Set backend to `sops` in `/etc/nixos/server-services.nix`.
- Rebuild and verify service units resolve:
  - Nextcloud admin pass from `config.sops.secrets.*.path`
  - MinIO credentials from `config.sops.templates.*.path`
  - PhotoPrism password from `config.sops.secrets.*.path`
  - Attic env file from `config.sops.templates.*.path`

### 9.4 Regression validation

- Verify no target module retains hardcoded `/etc/nixos/secrets/...` values outside defaults/options.
- Confirm preflight catches regression patterns.

---

## 10. Rollback Plan

Immediate rollback (host-safe):
1. Set `vexos.secrets.backend = "plaintext"`.
2. Ensure `/etc/nixos/secrets/*` files still exist.
3. Rebuild with prior working target.

Code rollback:
1. Revert backend module wiring commit(s).
2. Re-run `nix flake check` and dry-build.

Because plaintext path defaults are preserved during phased rollout, rollback does not require emergency code surgery.

---

## 11. Recommended Phase 2 Action

Phase 2 should modify code now: **Yes**.

Reason:
- Research is complete.
- Mandatory Context7 verification for `sops-nix` is complete.
- A non-breaking phased implementation path is defined with explicit compatibility and rollback.
