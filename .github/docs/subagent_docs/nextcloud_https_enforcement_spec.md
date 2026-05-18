# Nextcloud HTTPS Enforcement Specification

Feature slug: `nextcloud-https-enforcement`
Date: 2026-05-18
Phase: 1 (Research and Specification)

## 1. Scope and Objective

Target unresolved entry:
- `[SECURITY] services.nextcloud.https = false (partially unresolved)`

Primary objective:
- Close plaintext transport exposure risk for Nextcloud while preserving practical deployment paths (direct HTTPS, local reverse proxy, and explicit LAN-only exception).

Out of scope:
- Secrets backend migration (plaintext vs sops) beyond preserving current behavior.
- Re-architecting unrelated server modules.

## 2. Current State Analysis (with file references)

### 2.1 Nextcloud module already defaults wrapper HTTPS to true
- `vexos.server.nextcloud.https` is defined with `default = true` in `modules/server/nextcloud.nix:38`.
- The wrapper forwards to upstream option via `services.nextcloud.https = cfg.https` in `modules/server/nextcloud.nix:67`.
- Header comments explicitly still permit plaintext exception: `Set https = false ONLY on fully-isolated LANs` in `modules/server/nextcloud.nix:22`.

### 2.2 Current firewall behavior still permits plaintext exposure path
- Nextcloud module opens TCP 80 unconditionally and adds 443 only when HTTPS is on:
  - `networking.firewall.allowedTCPPorts = [ 80 ] ++ lib.optional cfg.https 443;`
  - `modules/server/nextcloud.nix:72`
- Net effect: if `https = false`, plaintext HTTP on port 80 remains reachable.

### 2.3 Template does not document HTTPS risk controls
- Server template exposes only `vexos.server.nextcloud.enable` toggle in `template/server-services.nix:64`.
- No commented guidance for secure reverse proxy mode vs explicit insecure LAN mode.

### 2.4 Existing analysis still flags unresolved plaintext transport risk
- Prior analysis still records:
  - `[SECURITY] services.nextcloud.https = false` at `full_code_analysis.md:719`
  - rationale about plain HTTP token/password exposure at `full_code_analysis.md:721`
- This is now partially stale because wrapper default changed to `true`, but unresolved because insecure path remains available and broadly reachable.

### 2.5 Preflight currently guards secret paths, not transport policy
- `scripts/preflight.sh` hard-fails if hardcoded plaintext secret paths regress (`scripts/preflight.sh:314-334`, especially Nextcloud check at `scripts/preflight.sh:317-319`).
- There is no equivalent check for insecure Nextcloud transport policy.

### 2.6 Secrets backend compatibility baseline
- Plaintext backend permissions are enforced in `modules/secrets.nix` (`0700` dir and `0600` files at `modules/secrets.nix:27` and `modules/secrets.nix:31`).
- SOPS backend forcibly wires Nextcloud admin password runtime path via
  `vexos.server.nextcloud.adminPassFile = lib.mkForce ...` in `modules/secrets-sops.nix:140`.
- Any HTTPS enforcement change must not alter this backend behavior.

## 3. Problem Definition and Threat Model

### 3.1 Problem definition

Even with wrapper default HTTPS enabled, the current option model still allows:
- explicit `https = false`, and
- broad HTTP exposure on port 80

without an explicit risk acknowledgment or scoping guard. That keeps plaintext exposure as an easy misconfiguration path.

### 3.2 Threat model

Assets at risk:
- user credentials
- session/access tokens
- admin cookies and CSRF-protected session context

Threat actors:
- passive LAN observer (shared Wi-Fi, compromised client, hostile VLAN peer)
- active MITM on local/private networks
- misconfigured reverse proxy chain allowing spoofed protocol/IP headers

Attack paths:
- plaintext HTTP sniffing when `https = false`
- mixed HTTP/HTTPS confusion in proxy setups when overwrite/trusted proxy semantics are not explicit
- accidental broad bind/firewall exposure for deployments that only needed local reverse-proxy backend HTTP

Security goal:
- secure by default transport behavior, with explicit opt-in for insecure exceptions.

## 4. Research Sources (minimum 6 credible references)

1. Nixpkgs Nextcloud module source (NixOS 25.11 branch)
- URL: https://raw.githubusercontent.com/NixOS/nixpkgs/nixos-25.11/nixos/modules/services/web-apps/nextcloud.nix
- Key findings:
  - `services.nextcloud.https` upstream default is `false` and controls generated links plus HSTS behavior.
  - Nginx fastcgi `HTTPS` param and Strict-Transport-Security emission are tied to this option.

2. NixOS Wiki - Nextcloud
- URL: https://wiki.nixos.org/wiki/Nextcloud
- Key findings:
  - TLS guidance explicitly pairs `services.nextcloud.https = true` with nginx `forceSSL = true` and ACME.
  - Documents reverse-proxy/subdir patterns and warns about protocol correctness.

3. Nextcloud Admin Manual - Hardening and security guidance
- URL: https://docs.nextcloud.com/server/latest/admin_manual/installation/harden_server.html
- Key findings:
  - States always use HTTPS in production and never allow unencrypted HTTP.
  - Recommends redirecting all HTTP to HTTPS and enabling HSTS.

4. Nextcloud Admin Manual - Reverse proxy configuration
- URL: https://docs.nextcloud.com/server/latest/admin_manual/configuration_server/reverse_proxy_configuration.html
- Key findings:
  - Requires explicit `trusted_proxies` to prevent spoofing.
  - Recommends `overwriteprotocol = https` when TLS is terminated by proxy.

5. Nextcloud Admin Manual - Warnings on admin page
- URL: https://docs.nextcloud.com/server/latest/admin_manual/configuration_server/security_setup_warnings.html
- Key findings:
  - Explicit warning for HTTP access.
  - HSTS warning and `__Host-` cookie prefix warning when HTTPS/proxy signaling is wrong.

6. NixOS Wiki - Nginx
- URL: https://wiki.nixos.org/wiki/Nginx
- Key findings:
  - Standard NixOS reverse-proxy pattern uses `forceSSL`, `enableACME`, and recommended TLS/proxy settings.

7. NixOS Wiki - ACME
- URL: https://wiki.nixos.org/wiki/ACME
- Key findings:
  - DNS challenge supports private LAN/self-hosted setups without public service exposure.
  - Supports practical secure-by-default even for non-public deployments.

## 5. Architecture Options and Tradeoffs

### Option A: Hard assertion, always require HTTPS

Approach:
- Assert `vexos.server.nextcloud.https == true` and remove/disable insecure path.

Pros:
- Strongest security posture.
- Simple policy and review story.

Cons:
- Breaks practical reverse-proxy deployments that intentionally use local backend HTTP.
- Blocks isolated-lab/LAN-only exception workflows even when operator knowingly accepts risk.

Assessment:
- Too rigid for this repo's practical self-hosting model.

### Option B: Option policy only (explicit insecure override), no bind/scoping changes

Approach:
- Add `allowInsecureHttp` gate, but keep current listener/firewall behavior.

Pros:
- Better operator intent signaling.
- Minimal code churn.

Cons:
- If override is set, plaintext stays broadly exposed by default.
- Does not protect reverse-proxy local-backend cases from accidental LAN exposure.

Assessment:
- Improves governance but insufficient technical containment.

### Option C: Firewall/listen scoping only, no explicit policy switch

Approach:
- When `https = false`, bind loopback and avoid opening firewall.

Pros:
- Strong technical default for reverse-proxy backend HTTP.
- Reduces accidental plaintext exposure.

Cons:
- No explicit risk acknowledgement path for intentionally insecure LAN use.
- Can surprise operators expecting LAN HTTP after toggling `https = false`.

Assessment:
- Good containment but weaker intent clarity.

### Option D (Recommended): Hybrid policy + scoping

Approach:
- Keep `https` option.
- Add explicit insecure override option.
- Apply safe network scoping by default for non-HTTPS mode.

Pros:
- Secure-by-default in all common paths.
- Preserves reverse-proxy practicality.
- Allows explicit LAN plaintext with deliberate opt-in.

Cons:
- Slightly more module complexity.
- Requires template/documentation updates.

Assessment:
- Best balance for this repository.

## 6. Recommended Approach

Adopt Option D with the following policy:

1. Preserve `vexos.server.nextcloud.https = true` as default.
2. Introduce a new option (proposed):
   - `vexos.server.nextcloud.allowInsecureHttp` (bool, default `false`).
3. Behavior when `https = false`:
   - If `allowInsecureHttp = false` (default):
     - bind Nextcloud nginx vhost to loopback only
     - do not open firewall port 80 from this module
     - this supports same-host reverse proxy TLS termination safely
   - If `allowInsecureHttp = true`:
     - allow current LAN/plaintext behavior (port 80 exposure)
     - emit a strong warning in option description and docs
4. Keep existing secrets backend wiring unchanged (`modules/secrets.nix`, `modules/secrets-sops.nix`).
5. Add preflight policy check for explicit insecure exposure declarations (at least warning-level, optionally hard-fail by policy decision in Phase 2).

Why this closes the unresolved risk:
- Plaintext transport is no longer the accidental default path for `https = false`.
- Broad HTTP exposure requires explicit operator opt-in.
- Reverse-proxy workflows remain practical without adding dependencies.

## 7. File-by-File Implementation Plan (Phase 2)

### 7.1 `modules/server/nextcloud.nix`

Planned changes:
- Add option:
  - `allowInsecureHttp` (bool, default false).
- Rework transport exposure logic:
  - Keep `services.nextcloud.https = cfg.https`.
  - When `!cfg.https && !cfg.allowInsecureHttp`:
    - force vhost listen to loopback addresses on HTTP.
  - Firewall ports:
    - open `443` only when `cfg.https`.
    - open `80` when `cfg.https || cfg.allowInsecureHttp`.
- Update module comments/descriptions to clarify:
  - direct HTTPS mode
  - reverse-proxy backend HTTP mode (loopback only)
  - explicit insecure LAN mode

Compatibility note:
- Do not modify `adminPassFile` logic; keep backend abstraction intact.

### 7.2 `template/server-services.nix`

Planned changes:
- Add commented examples for Nextcloud transport modes:
  - default secure mode
  - reverse proxy local-backend mode (`https = false`, `allowInsecureHttp = false`)
  - explicit insecure LAN mode (`allowInsecureHttp = true`)
- Keep the current service toggle style and avoid introducing unrelated defaults.

### 7.3 `scripts/preflight.sh`

Planned changes:
- Add a new Nextcloud transport policy check section.
- At minimum, detect uncommented tracked declarations of explicit insecure exposure:
  - `vexos.server.nextcloud.allowInsecureHttp = true;`
- Output policy result:
  - recommended baseline: WARN with explicit file/line list
  - stricter baseline (optional): FAIL if project policy requires no tracked insecure exposure

Implementation caution:
- Follow existing preflight regex anchoring style to avoid false positives from commented template lines.

### 7.4 `full_code_analysis.md`

No direct Phase 2 edit required for functionality.
- If your workflow updates analysis artifacts, mark this item resolved/partially resolved after implementation and validation.

## 8. Risks and Mitigations

Risk 1: Reverse-proxy deployments unexpectedly stop working after scoping changes.
- Mitigation:
  - Keep behavior explicit and documented in template comments.
  - Validate with one local reverse-proxy smoke test (loopback backend).

Risk 2: Operators rely on plaintext LAN HTTP and are surprised by default lock-down.
- Mitigation:
  - Provide `allowInsecureHttp` explicit override with clear warning text.

Risk 3: Regression risk to unrelated server services.
- Mitigation:
  - Limit code changes to Nextcloud module, template comments, and preflight check section.
  - Do not touch global nginx/caddy/traefik defaults.

Risk 4: Backend secret behavior accidentally altered.
- Mitigation:
  - Do not change `adminPassFile` wiring and keep sops/plaintext modules untouched.

## 9. Validation Plan

### 9.1 Static/evaluation checks
- Run: `nix flake check --no-build --impure`
- Run targeted dry-builds for server roles (at minimum one per relevant role):
  - `sudo nixos-rebuild dry-build --flake .#vexos-server-amd`
  - `sudo nixos-rebuild dry-build --flake .#vexos-headless-server-amd`

### 9.2 Behavior checks (recommended)

Scenario A: Default secure mode
- Config: `vexos.server.nextcloud.enable = true` (no override)
- Expect:
  - HTTPS mode active
  - firewall includes 80/443 for Nextcloud flow

Scenario B: Reverse-proxy backend HTTP mode (safe default)
- Config: `https = false`, `allowInsecureHttp = false`
- Expect:
  - Nextcloud backend listens only on loopback HTTP
  - firewall does not expose HTTP port from Nextcloud module

Scenario C: Explicit insecure LAN mode
- Config: `https = false`, `allowInsecureHttp = true`
- Expect:
  - HTTP port 80 exposure allowed
  - clear warning present in docs/options

### 9.3 Preflight check validation
- Confirm new policy check flags tracked insecure exposure declarations per intended severity.

## 10. Dependency and Policy Impact

- No new flake input or external dependency required.
- No change to `nixpkgs.follows` policies.
- Aligns with existing phased secret backend architecture.

## 11. Phase 2 Decision

Recommendation: **Yes - Phase 2 should modify code now.**

Reason:
- The unresolved issue is only partially addressed at present.
- Current defaults improved, but accidental plaintext exposure remains possible.
- Proposed Phase 2 changes are low blast-radius, dependency-free, and align with existing architecture.