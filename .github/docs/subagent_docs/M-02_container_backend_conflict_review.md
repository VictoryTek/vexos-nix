# M-02 — Review & Quality Assurance

Status: Phase 3 (Review) — scope expanded once, by user decision, mid-validation
Spec: `.github/docs/subagent_docs/M-02_container_backend_conflict_spec.md`

## Modified Files

- `modules/server/dozzle.nix`, `portainer.nix`, `homepage.nix`, `authelia.nix`,
  `uptime-kuma.nix`, `stirling-pdf.nix`, `nginx-proxy-manager.nix` —
  `virtualisation.oci-containers.backend = "docker";` → `lib.mkDefault "docker"`.
- `modules/server/podman.nix` — added `virtualisation.docker.enable = lib.mkForce false;`
  (scope addition, see below).

## Scope Note

The spec's literal fix (`lib.mkDefault "docker"`) was implemented and verified to fully
resolve the named `oci-containers.backend` conflict on its own. While forcing the full
combination (podman + all seven services) to validate it, a second, adjacent,
pre-existing conflict surfaced: nixpkgs's own assertion against
`virtualisation.docker.enable` and `virtualisation.podman.dockerCompat` both being true
— triggered because the seven modules' `mkDefault true` for `virtualisation.docker.enable`
was never overridden to `false` when podman is active. This would have blocked the
practical goal of M-02 (podman + docker-backed services coexisting) even with the named
fix in place. Presented to the user as an explicit scope decision rather than silently
expanding or silently leaving it; user chose to include it.

## Review Findings

1. **Specification Compliance** — the named fix matches the spec exactly; the
   additional `podman.nix` line was an explicit, user-approved scope addition, not a
   silent deviation.
2. **Best Practices** — `lib.mkDefault`/`lib.mkForce` usage matches the standard NixOS
   idiom for "several modules agree on a default, one authoritative module overrides
   it" — the same pattern already used elsewhere in this codebase (e.g.
   `virtualisation.docker.package = lib.mkDefault pkgs.docker_29;` in `docker.nix`).
3. **Consistency** — no shared/base module touched; all changes are within
   already-role-scoped `modules/server/*.nix` service modules.
4. **Maintainability** — the new `podman.nix` line carries a comment explaining *why*
   (nixpkgs's own dockerCompat/docker assertion, and that podman's dockerCompat already
   provides the same socket those service modules need).
5. **Completeness** — both the named conflict and its necessary companion conflict are
   resolved; verified together, not just the named one in isolation.
6. **Performance** — no change.
7. **Security** — no change; same runtimes, same sockets, just resolved priority/force
   annotations.
8. **API Currency** — n/a, internal option-priority change only.
9. **Build Validation:**
   - Forced-branch test #1 (podman + all seven docker-backed services enabled
     together): **before** the `podman.nix` addition, hit the dockerCompat/docker
     assertion (a real, reproduced failure, not hypothetical); **after**, built the full
     `toplevel.drvPath` successfully with `backend = "podman"`, `podmanEnabled = true`,
     `dockerEnabled = false`.
   - Forced-branch test #2 (dozzle + homepage + authelia enabled, no podman): confirms
     no regression to the docker-only path — `backend = "docker"`,
     `dockerEnabled = true`, builds successfully.
   - `nix flake show --impure` — passed.
   - Required targets (`vexos-desktop-amd`, `-nvidia`, `-vm`, `vexos-server-amd`,
     `vexos-headless-server-amd`) evaluated via `nix eval --impure`; all `.drv` hashes
     byte-identical to the pre-change baseline (none of these services are enabled by
     default, so the default build path is untouched — expected).
   - `git ls-files hardware-configuration.nix` — empty. ✓
   - `system.stateVersion` — untouched. ✓
   - `bash scripts/preflight.sh` — exit 0, PASSED. Same pre-existing WARNs as every
     prior review this session; nothing new.

No CRITICAL or RECOMMENDED issues found.

| Category | Score | Grade |
|----------|-------|-------|
| Specification Compliance | 100% | A |
| Best Practices | 100% | A |
| Functionality | 100% | A |
| Code Quality | 100% | A |
| Security | 100% | A |
| Performance | 100% | A |
| Consistency | 100% | A |
| Build Success | 100% | A |

**Overall Grade: A (100%)**

## Returns

- Build result: PASS
- **PASS**
