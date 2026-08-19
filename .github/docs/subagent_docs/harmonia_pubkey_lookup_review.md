# Harmonia public-key lookup fix — Review

Spec: `.github/docs/subagent_docs/harmonia_pubkey_lookup_spec.md`

## Files reviewed
- `justfile` (recipe `harmonia-info`)
- `modules/server/harmonia.nix`

## Findings

1. **Spec compliance** — both spec items implemented: config-resolved
   `signKeyPath` with `.pub`-then-derive lookup (justfile), `0711` state
   directory (module). Port hardcoding left alone as the spec declared.
2. **Deviation from spec (improvement, accepted)** — the `chmod` was moved
   *outside* the `if [ ! -e key ]` guard. As specified it would only have run
   during first key generation, so an already-provisioned host would keep its
   `0700` directory forever and the fix would not reach the machine that
   reported the bug. Now idempotent on every activation.
3. **Shell correctness issues found during implementation and fixed:**
   - `sudo nix key convert-secret-to-public < "$KEY"` was wrong — the redirect
     is opened by the unprivileged calling shell, so a 0400 root key would fail
     to open. Replaced with `sudo cat "$KEY" | nix key convert-secret-to-public`
     (root reads, user converts). `pipefail` is set, so failure still propagates.
   - `[ -n "$RESOLVED" ] && KEY="$RESOLVED"` as a bare statement exits the
     recipe under `set -e` when the test is false. Replaced with an `if` block.
   - The `[ ! -e "$KEY" ]` pre-check was removed: `/run/secrets/...` may not be
     stat-able by the invoking user, which would have produced a false "not
     found". The sudo read now reports the real failure, with `sudo ls -l` and
     `just rebuild` as follow-ups.
4. **Security** — no secret is printed. The derived value is the public half
   only. Private key remains `0600` root; `0711` grants directory traversal,
   not listing. No new credentials, no plaintext secrets.
5. **Consistency** — `nix eval --impure --raw path:/etc/nixos#…` matches the
   existing `_kernel-cache-guard` pattern (justfile L275-L287); `sudo` usage is
   routine in this justfile. Module Architecture Pattern untouched (no new
   `lib.mkIf` in a shared module; the existing backend guard is pre-existing).
6. **Dead code / orphans** — none; `KEY_PUB` was fully replaced by `KEY`.

## Validation performed

| Check | Result |
|---|---|
| `just --list` (justfile parses) | PASS |
| `bash -n` on extracted `harmonia-info` body | PASS |
| `nix flake show --impure` | PASS |
| `nix eval … vexos-desktop-amd …toplevel.drvPath` | PASS (drv produced) |
| `nix eval … vexos-server-amd + harmonia.enable + hostId …toplevel.drvPath` | PASS (drv produced) |
| `harmoniaKey` activation script text | PASS — emits `chmod 0711` unconditionally, key generation still guarded |
| Key derivation equivalence (`nix-store --generate-binary-cache-key` vs `nix key convert-secret-to-public`) | PASS — byte-identical public key |
| `git ls-files hardware-configuration.nix` | empty (not committed) |
| `system.stateVersion` unchanged | PASS (no `configuration-*.nix` touched) |
| New flake inputs | none added |

Notes on validation method: `sudo` is unavailable in this session (the
environment sets `no_new_privileges`), so `nixos-rebuild dry-build` could not
run. Per CLAUDE.md the sanctioned equivalent — `nix eval --impure
…system.build.toplevel.drvPath` — was used instead; it forces the same full
evaluation.

Bare `nixosConfigurations.vexos-server-amd` fails a **pre-existing** assertion
from `modules/zfs-server.nix:99` (placeholder `networking.hostId` committed in
`hosts/`), unrelated to this change and present before it — hence the
`extendModules` override with `hostId = "deadbeef"` to reach a real evaluation.

## Score table

| Category | Score | Grade |
|----------|-------|-------|
| Specification Compliance | 100% | A |
| Best Practices | 95% | A |
| Functionality | 95% | A |
| Code Quality | 95% | A |
| Security | 100% | A |
| Performance | 100% | A |
| Consistency | 100% | A |
| Build Success | 100% | A |

**Overall Grade: A (98%)**

**Result: PASS**

## Residual risk

The derive branch could not be exercised end-to-end against a live sops-backed
key from this machine (no Harmonia instance here). The conversion itself was
verified byte-identically against a freshly generated keypair, so the remaining
unknown is only whether `sudo cat` can read the host's key — which it can, as
root.
