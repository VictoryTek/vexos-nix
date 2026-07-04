# M-20 — Review & Quality Assurance

Status: Phase 3 (Review)
Spec: `.github/docs/subagent_docs/M-20_ssh_fail2ban_desktop_spec.md`

**User constraint honored:** SSH password authentication left completely untouched
throughout — the user explicitly reverted from key-only auth to password auth in a
prior session and prefers it; the MASTER_PLAN's `PasswordAuthentication = false`
alternative was never implemented.

## Modified Files

- `modules/security-desktop.nix` (new) — fail2ban block (sshd + recidive jails),
  matching `security-server.nix`'s settings exactly, no auditd.
- `configuration-desktop.nix`, `configuration-htpc.nix`, `configuration-stateless.nix`
  — import the new module.
- `modules/network.nix` — removed the redundant
  `networking.firewall.allowedTCPPorts = [ 22 ];` line.

## Review Findings

1. **Specification Compliance** — matches the spec exactly; the
   `PasswordAuthentication` option was correctly excluded per the user's explicit
   constraint (now also saved to persistent memory for future sessions).
2. **Best Practices** — new module follows the Option B pattern precisely, matching
   `security-server.nix`'s own header-comment convention and structure; no `lib.mkIf`
   gating added to any shared file.
3. **Consistency** — fail2ban settings (`maxretry = 5`, `bantime = "1h"`, recidive
   jail) are identical to the existing server-role config, avoiding a second,
   diverging security posture.
4. **Maintainability** — the new module's header explains exactly what gap it closes
   and why (mirrors `modules/network.nix`'s own SSH comment).
5. **Completeness** — all three roles missing fail2ban (desktop, htpc, stateless) now
   have it; server/headless-server were already covered and are unaffected; vanilla
   has no SSH server at all and correctly isn't touched.
6. **Performance** — negligible; fail2ban is lightweight.
7. **Security** — this is the core security fix: brute-force protection is now present
   everywhere SSH with password auth is enabled, not just on server roles.
8. **API Currency** — n/a, standard NixOS `services.fail2ban` usage, already
   established elsewhere in this repo.
9. **Build Validation:**
   - Direct verification on `vexos-desktop-amd`: confirmed `services.fail2ban.enable
     == true`, `networking.firewall.allowedTCPPorts` still contains `22` (supplied by
     `services.openssh.openFirewall`, not the removed explicit line), and
     `services.openssh.settings.PasswordAuthentication == true` (unchanged, matching
     the user's preference) — all three checked together in one evaluation rather than
     assumed independently.
   - Confirmed no conflict with `vexos-server-amd`'s existing (separate)
     `security-server.nix` fail2ban config — both build cleanly, no duplicate
     assertion or option conflict.
   - `modules/security-desktop.nix` was a new untracked file; `nix eval`/`nix flake
     show` couldn't see it until staged (git-index visibility, not a code issue) — user
     staged it before validation continued.
   - `nix flake show --impure` — passed.
   - All five affected targets (`vexos-desktop-amd`, `-nvidia`, `-vm`,
     `vexos-htpc-amd`, `vexos-stateless-amd`) evaluated cleanly after staging.
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
