# H-17 — Review & Quality Assurance

Status: Phase 3 (Review)
Spec: `.github/docs/subagent_docs/H-17_ntfy_notify_spec.md`

## Modified Files

- `modules/notify.nix` (new) — `vexos.notify.ntfyUrl`/`tokenFile` options,
  `vexos-notify` script (Nix-eval-time branch: no-op script when `ntfyUrl` is null,
  real curl POST otherwise), `notify-failure@.service` template unit.
- `configuration-{desktop,htpc,server,headless-server,stateless,vanilla}.nix` — added
  `./modules/notify.nix` to `imports`, next to the existing `./modules/nix.nix` line in
  each (matches how `modules/nix.nix` itself is distributed across all six roles).
- `modules/server/backup.nix` — replaced the inert H-17 placeholder comment with a live
  `systemd.services."restic-backups-main".onFailure = [ "notify-failure@backup.service" ];`.
- `modules/nix.nix` — one line at the end of `vexos-update`'s script body:
  `vexos-notify "Update applied on $(hostname)"`, reached only on success since
  `set -euo pipefail` is already active.

## Review Findings

1. **Specification Compliance** — matches the spec: cross-role module (not
   server-scoped), safe no-op default, documented manual token step, generic
   `notify-failure@.service` template, both named producers wired.
2. **Best Practices** — uses systemd unit specifiers (`%i`, `%H`) for the failure
   template instead of shelling out to `$(hostname)`, avoiding an unnecessary subshell
   in `ExecStart`. `vexos-notify`'s network call is best-effort (`|| true`, `exit 0`)
   so a flaky ntfy server can never turn a successful operation into a failed one.
3. **Consistency (Module Architecture Pattern)** — `modules/notify.nix` is a shared
   base module with no `lib.mkIf`-gated role branching inside it (matches
   `modules/nix.nix`'s own pattern of being imported directly by every role rather than
   gated by a flag). No new `lib.mkIf` guards added to any *existing* shared module.
4. **Maintainability** — the two option descriptions document the manual ntfy-token
   step and *why* it can't be automated (verified against the upstream module — no
   declarative token/ACL option exists).
5. **Completeness** — all spec items implemented; the `backup.nix` extension point this
   item was already carrying is now live instead of a comment.
6. **Performance** — no cost on hosts without `ntfyUrl` set (the script body is a
   1-line `exit 0`, decided at Nix-eval time, not a runtime branch).
7. **Security** — verified directly (built the derivation and inspected the rendered
   script) that passing `tokenFile` as the documented string form
   (`"/etc/nixos/secrets/ntfy-token"`) keeps it a pure runtime `cat` reference with no
   Nix store copy; only an actual unquoted Nix path literal would trigger a copy, which
   isn't the documented usage pattern (matches this repo's existing convention for
   every other path-typed secret option, e.g. `vexboard.secretFile`).
8. **API Currency** — `services.ntfy-sh`'s lack of a declarative token/ACL mechanism was
   confirmed by reading the upstream module source at the pinned nixpkgs revision, not
   assumed from memory.
9. **Build Validation:**
   - `nix flake show --impure` — passed.
   - `modules/notify.nix` was a brand-new untracked file; `nix eval`/`nix flake show`
     couldn't see it until staged (git-index visibility, not a code issue) — user staged
     it before validation continued.
   - Evaluated a broader-than-minimum target set since this change touches all six
     roles: `vexos-desktop-amd`, `vexos-desktop-nvidia`, `vexos-desktop-vm`,
     `vexos-server-amd`, `vexos-headless-server-amd`, `vexos-htpc-amd`,
     `vexos-stateless-amd`, `vexos-vanilla-amd` — all evaluated cleanly (the stateless
     locked-password warning is pre-existing and unrelated).
   - Forced-branch test: `vexos-server-amd.extendModules` with
     `vexos.notify.ntfyUrl`/`tokenFile` set and `vexos.server.backup.enable = true` —
     built cleanly, confirming the non-default script branch and the
     `notify-failure@backup` wiring both type-check together.
   - Built the `vexos-notify` derivation directly (`nix build --impure --expr ...`) and
     `cat`'d the rendered script to confirm the bash templating (line continuations,
     the conditional `Authorization` header) actually renders correctly, not just that
     Nix accepted it syntactically.
   - `git ls-files hardware-configuration.nix` — empty. ✓
   - `system.stateVersion` — untouched. ✓
   - `flake.nix` — untouched; no new inputs. ✓
   - `bash scripts/preflight.sh` — exit 0, PASSED. Same pre-existing WARNs as prior
     H-15/H-16 reviews (repo-wide nixpkgs-fmt drift; VexBoard's already-accepted
     placeholder string); nothing new.

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
