# M-04 — Review & Quality Assurance

Status: Phase 3 (Review)
Spec: `.github/docs/subagent_docs/M-04_headscale_serverurl_spec.md`

## Modified Files

- `modules/server/headscale.nix` — added `vexos.server.headscale.serverUrl` option
  (placeholder default + hard assertion, matching `vaultwarden.nix`'s established
  pattern for this exact kind of "must be a real value" option); wired to the current,
  non-deprecated `services.headscale.settings.server_url` instead of the deprecated
  top-level `services.headscale.serverUrl`; removed the broken `"http://0.0.0.0:..."`
  default entirely.

## Review Findings

1. **Specification Compliance** — matches the spec exactly.
2. **Best Practices** — reuses this codebase's own established idiom (invalid
   placeholder default + assertion) rather than inventing a new pattern, and moves to
   the current upstream option name rather than relying on the deprecated
   auto-forwarding alias.
3. **Consistency** — single self-contained service module change; no shared/base
   module touched.
4. **Maintainability** — the option description and assertion message both explain
   *why* this can't be a bind address (clients connect to it directly), not just that
   it must be set.
5. **Completeness** — the specific bug (0.0.0.0 as server_url) is fully removed, and
   the deprecated option path is replaced with the current one, addressing both halves
   of the MASTER_PLAN item.
6. **Performance** — no change.
7. **Security** — no change in security posture; if anything, the hard assertion
   prevents ever silently deploying a broken/unreachable control server again.
8. **API Currency** — verified directly against the pinned nixpkgs revision
   (`nixos/modules/services/networking/headscale.nix`) that `serverUrl` is deprecated
   via `mkRenamedOptionModule` in favor of `settings.server_url` — this was the
   specific question the MASTER_PLAN item raised, now confirmed and acted on rather
   than left open.
9. **Build Validation:**
   - Forced-branch test #1 (`headscale.enable = true`, no `serverUrl` override):
     confirms the assertion fires with the expected message — the fix is actually
     enforced, not just present in code.
   - Forced-branch test #2 (`headscale.enable = true`,
     `serverUrl = "https://headscale.example.org"`, MagicDNS/override-local-dns
     disabled to isolate this fix from headscale's own unrelated pre-existing
     assertions): confirms `services.headscale.settings.server_url` resolves to the
     supplied value and the full `toplevel` builds — direct proof the value reaches
     the current, correct option path.
   - `nix flake show --impure` — passed.
   - Required targets (`vexos-desktop-amd`, `-nvidia`, `-vm`, `vexos-server-amd`,
     `vexos-headless-server-amd`) evaluated cleanly via `nix eval --impure`; `.drv`
     hashes unchanged from the default (disabled) path, as expected since headscale
     is opt-in.
   - `git ls-files hardware-configuration.nix` — empty. ✓
   - `system.stateVersion` — untouched. ✓
   - `bash scripts/preflight.sh` — exit 0, PASSED. Same pre-existing WARNs as every
     prior review this session; the new placeholder string
     (`"https://headscale.example.com"`) did not trip the hardcoded-secret scan, as
     expected for an obviously-invalid placeholder domain, not a credential.

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
