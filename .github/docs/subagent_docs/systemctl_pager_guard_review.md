# Review: systemctl_pager_guard

Spec: `.github/docs/subagent_docs/systemctl_pager_guard_spec.md`
Date: 2026-09-05
Phase: 3 — Review & Quality Assurance

## Files modified

- `justfile` (2 changes: `export SYSTEMD_PAGER := ""`; `backup-now` error wording)
- `modules/packages-common.nix` (1 change: `ghostty.terminfo`)

## 1. Specification compliance

All three implementation steps completed exactly as specified. No scope creep: the
`LoadState` refactor across five call sites, considered and rejected in the spec, was
correctly not implemented.

## 2. Build validation

`nix flake check` NOT used (FORBIDDEN COMMANDS). `nixos-rebuild dry-build` unavailable —
sudo is not passwordless in this session — so the CLAUDE.md-sanctioned equivalent was used:
`nix eval` of `system.build.toplevel.drvPath`, which is what `.github/workflows/ci.yml`
runs.

`nix flake show --impure` → exit 0.

Because `packages-common.nix` is a universal base, every role was evaluated, not just the
three mandated desktop variants:

| Configuration | Result |
|---|---|
| vexos-desktop-amd | OK |
| vexos-desktop-nvidia | OK |
| vexos-desktop-vm | OK |
| vexos-server-amd | OK |
| vexos-headless-server-amd | OK |
| vexos-headless-server-intel | OK |
| vexos-htpc-amd | OK |
| vexos-stateless-amd | OK |

Server/stateless variants required the same eval fixtures CI applies
(`networking.hostId`, stateless `hashedPassword`) — see `ci.yml:158-190`. The initial
`hostId` assertion failure was confirmed **pre-existing** and unrelated: the placeholder
lives at `hosts/headless-server-intel.nix:15` in the committed tree and `git status` shows
`hosts/` untouched by this change.

### Fix reaches the affected host

Evaluated against `vexos-headless-server-intel`:

- `environment.systemPackages` contains `ghostty-1.3.1`
- `outputName=terminfo`, `outPath=/nix/store/...-ghostty-1.3.1-terminfo`
- Substitutable from `cache.nixos.org` — the server downloads a prebuilt terminfo output;
  it does **not** build ghostty from source.

### Behavioural verification

- `just --evaluate` → `SYSTEMD_PAGER := ""`; `just --list` → exit 0.
- Recipe environment probe → `SYSTEMD_PAGER=[]`.
- With an inherited `SYSTEMD_PAGER=less`, the recipe still sees `[]` — the export takes
  precedence, so a user's environment cannot reintroduce the failure.
- Only executed `journalctl` is `justfile:3874` (`-fu`, follow mode, never pages), so no
  recipe loses intended paging.

## 3. Repository invariants

- `git ls-files hardware-configuration.nix` → empty.
- `git diff -- configuration-*.nix | grep -i stateVersion` → no changes.
- No new flake inputs, so no `follows` obligations.

## 4. Best practices / consistency

`modules/packages-common.nix` is the Option B universal base; the package applies
unconditionally to all importing roles with no `lib.mkIf` guard and no role-conditional
logic. Comment style matches surrounding entries. The `justfile` export is placed above
the first recipe with a comment explaining the SIGPIPE failure mode.

## 5. Security

No secrets, credentials, or world-writable paths introduced. `ghostty.terminfo` is a data
output — no daemon, no setuid, no PATH executable. Disabling the pager removes a
subprocess rather than adding one.

## 6. Observations (non-blocking)

- **`configuration-vanilla.nix` does not import `packages-common.nix`**, so the vanilla
  role does not receive the terminfo. Deliberate — vanilla is intentionally minimal — and
  documented in the spec. A Ghostty SSH session into a vanilla host would still hit the
  pager problem, though justfile recipes there are already immune via the export.
- The five `list-unit-files` guards remain exit-code-based. With paging disabled this is
  correct, but the pattern is still sensitive to any future non-zero exit that is not a
  "missing unit" verdict. Not worth changing now; noted for future reference.
- Pre-existing, out of scope, not introduced here: evaluating server/stateless roles
  locally requires CI fixtures, so a developer cannot dry-build those variants on a
  desktop without replicating them.

## Score table

| Category | Score | Grade |
|----------|-------|-------|
| Specification Compliance | 100% | A |
| Best Practices | 98% | A |
| Functionality | 100% | A |
| Code Quality | 97% | A |
| Security | 100% | A |
| Performance | 100% | A |
| Consistency | 100% | A |
| Build Success | 100% | A |

**Overall Grade: A (99%)**

## Result

**PASS** — proceed to Phase 6 Preflight.
