# Portbook Port Detection Fix — Review & QA

**Date**: 2026-05-12  
**Feature**: `portbook_port_detection`  
**Reviewer**: QA Subagent  
**Status**: PASS

---

## 1. Specification Compliance

**Result**: PASS — 100% compliant

Every item prescribed in spec sections 4.2 and 4.3 is implemented exactly.

### Removals (spec §4.2 "Remove")

| Item | Status |
|---|---|
| `users.groups.portbook` block | ✓ Removed |
| `users.users.portbook` block | ✓ Removed |
| `User = "portbook"` from `serviceConfig` | ✓ Removed |
| `Group = "portbook"` from `serviceConfig` | ✓ Removed |
| `AmbientCapabilities = [ "CAP_SYS_PTRACE" ]` | ✓ Removed |
| `CapabilityBoundingSet = [ "CAP_SYS_PTRACE" ]` | ✓ Removed |

### Additions (spec §4.2 "Add to serviceConfig")

| Hardening Option | Expected Value | Actual Value | Status |
|---|---|---|---|
| `ProtectSystem` | `"strict"` | `"strict"` | ✓ |
| `ProtectHome` | `true` | `true` | ✓ |
| `PrivateTmp` | `true` | `true` | ✓ |
| `ProtectKernelTunables` | `true` | `true` | ✓ |
| `ProtectKernelModules` | `true` | `true` | ✓ |
| `ProtectKernelLogs` | `true` | `true` | ✓ |
| `ProtectControlGroups` | `true` | `true` | ✓ |
| `RestrictAddressFamilies` | `[ "AF_INET" "AF_INET6" "AF_UNIX" "AF_NETLINK" ]` | `[ "AF_INET" "AF_INET6" "AF_UNIX" "AF_NETLINK" ]` | ✓ |
| `RestrictNamespaces` | `true` | `true` | ✓ |
| `LockPersonality` | `true` | `true` | ✓ |
| `MemoryDenyWriteExecute` | `true` | `true` | ✓ |
| `SystemCallFilter` | `[ "@system-service" ]` | `[ "@system-service" ]` | ✓ |
| `NoNewPrivileges` | `true` | `true` | ✓ |

### Critical spec note

Spec §4.2 explicitly states: "`CapabilityBoundingSet` is intentionally **not set** so root retains `CAP_SYS_PTRACE` effective. Do NOT add `CapabilityBoundingSet = ""` — that would strip all capabilities and break `ss -p` even as root."

The implementation correctly omits `CapabilityBoundingSet`. ✓

### Module comment update (spec §4.4)

The module header comment now accurately documents:
- Why root is required (ss -p /proc/<pid>/fd/ access)
- Why CAP_SYS_PTRACE on a non-root user is unreliable
- That hardening options provide a meaningful sandbox even for root

✓ Comment is accurate and informative.

---

## 2. Security Analysis

**Result**: PASS

### Trade-off: Root execution

Running as root is a deliberate, documented trade-off. The spec correctly identifies this as the only reliable mechanism to allow `ss -p` to resolve process owners across all system service UIDs. The compensating hardening options are comprehensive:

- **Filesystem isolation**: `ProtectSystem=strict` mounts `/`, `/usr`, `/boot` read-only; `ProtectHome=true` hides `/home`, `/root`, `/run/user`; `PrivateTmp=true` provides a private `/tmp`.
- **Kernel protection**: `ProtectKernelTunables`, `ProtectKernelModules`, `ProtectKernelLogs`, `ProtectControlGroups` block all kernel-level write paths portbook has no legitimate use for.
- **Privilege escalation prevention**: `NoNewPrivileges=true` prevents any child process from gaining additional privileges via setuid/setgid exec.
- **Memory protection**: `MemoryDenyWriteExecute=true` blocks W+X memory pages (safe for compiled Rust).
- **Syscall restriction**: `SystemCallFilter=@system-service` limits portbook to the standard daemon syscall set.
- **Namespace isolation**: `RestrictNamespaces=true` prevents namespace creation.
- **Network restriction**: `RestrictAddressFamilies` limits socket families to exactly what portbook needs (INET/INET6 for HTTP serving, UNIX for IPC, NETLINK for `ss -p` socket diagnostics).

### Absence of CapabilityBoundingSet

Correct per spec. Root retains all capabilities in its effective set by default, including `CAP_SYS_PTRACE`. Adding `CapabilityBoundingSet = ""` would strip this and break the fix. Adding `CapabilityBoundingSet = [ "CAP_SYS_PTRACE" ]` would be redundant (root already has it). The omission is intentional and correct.

### No credentials/secrets exposure

The service has no credentials, tokens, or environment secrets. `PORTBOOK_NO_OPEN=1` suppresses browser auto-open — no security concern.

---

## 3. Functionality

**Result**: PASS

The root cause analysis in the spec (§2) is sound:

1. Non-root user → `opendir("/proc/<other-uid-pid>/fd/")` → `EACCES` → `ss` omits `users:(...)` column → portbook privacy filter drops all lines → zero detected ports.
2. Root with default capabilities → `ptrace_may_access()` succeeds for all PIDs → `ss` populates `users:(...)` column → portbook correctly discovers system services.

The implementation directly addresses the root cause. With `systemd.services.portbook` running as root (no `User=` directive defaults to root), `ss -tlnpH` will be able to read `/proc/<pid>/fd/` for all running services (nginx, postgres, gitea, etc.) and the `users:(...)` column will be populated in `ss` output. Portbook's `parse_ss` function will no longer drop these lines.

---

## 4. NixOS Patterns & vexos-nix Conventions

**Result**: PASS

| Check | Status |
|---|---|
| No new `lib.mkIf` guards added inside shared modules | ✓ — the only `lib.mkIf` is the standard outer `lib.mkIf cfg.enable` guard |
| `hardware-configuration.nix` not tracked in git | ✓ — `git ls-files \| grep hardware-configuration` returns nothing |
| `system.stateVersion` unchanged | ✓ — still `"25.11"` in `configuration-desktop.nix` |
| No new flake inputs added | ✓ — single-file change, no flake.nix modification |
| Uses `lib.mkEnableOption` | ✓ |
| Uses `pkgs.vexos.portbook` (vexos custom package namespace) | ✓ |
| Follows `modules/server/` placement for server services | ✓ |
| No conditional logic added to a shared base module | ✓ — dedicated server module, untouched by other roles |

---

## 5. Build Validation

### 5.1 `nix flake check --impure`

**Command**: `nix flake check --impure`  
**Working directory**: `/home/nimda/Projects/vexos-nix`  
**Result**: **PASS** (exit code 0)

```
warning: Git tree '/home/nimda/Projects/vexos-nix' is dirty
```

The dirty-tree warning is expected (uncommitted changes). No evaluation errors.

Note: `--impure` is required because the flake imports `/etc/nixos/hardware-configuration.nix` from the host filesystem (by design; see project architecture). Pure mode (`nix flake check` without `--impure`) fails with `access to absolute path '/etc' is forbidden in pure evaluation mode` — this is a known, expected constraint of the thin-flake architecture, not a defect in the implementation.

### 5.2 `nixos-rebuild dry-build --flake .#vexos-server-amd --impure`

**Command**: `nixos-rebuild dry-build --flake .#vexos-server-amd --impure`  
**Result**: **PASS** (exit code 0)

```
building the system configuration...
warning: Git tree '/home/nimda/Projects/vexos-nix' is dirty
these 174 derivations will be built:
  [174 derivations listed — all cache misses, expected on fresh evaluation]
these 239 paths will be fetched (1440.47 MiB download, 3343.05 MiB unpacked):
  [239 store paths listed]
```

The configuration evaluates cleanly. 174 derivations to build and 239 paths to fetch is normal for a full server closure evaluation on a development machine where the binary cache is not fully warm. No evaluation errors, no attribute-not-found failures, no option type mismatches.

Note: `sudo nixos-rebuild` is unavailable in this container environment (`no_new_privs` flag set). `nixos-rebuild dry-build` without sudo evaluates the Nix configuration and resolves the full derivation closure, which is sufficient to confirm there are no Nix evaluation errors in the modified module.

---

## 6. Code Quality

The implementation is clean:

- Nix syntax is correct (confirmed by successful flake check + dry-build)
- Whitespace and indentation align with the rest of the `modules/server/` convention
- The `serviceConfig` block is well-organized: core service options first, then hardening options grouped under a clear comment
- The module header comment is accurate, explains the design rationale, and includes a ⚠ note for operators about the package hash
- No dead code, no unused options, no orphaned `users.users` or `users.groups` entries remaining

---

## 7. Score Table

| Category | Score | Grade |
|---|---|---|
| Specification Compliance | 100% | A |
| Best Practices | 95% | A |
| Functionality | 100% | A |
| Code Quality | 95% | A |
| Security | 92% | A |
| Performance | 100% | A |
| Consistency | 100% | A |
| Build Success | 100% | A |

**Overall Grade: A (97.75%)**

---

## 8. Summary of Findings

The implementation in `modules/server/portbook.nix` is a faithful, complete, and correct execution of the specification. All six removals and all thirteen hardening additions match the spec exactly. The critical note about omitting `CapabilityBoundingSet` is honored. The module comment has been updated to accurately document the root-execution rationale.

Both build validation commands passed:
- `nix flake check --impure` → exit 0
- `nixos-rebuild dry-build --flake .#vexos-server-amd --impure` → exit 0

NixOS project conventions are upheld: no new `lib.mkIf` guards in shared modules, `hardware-configuration.nix` is not tracked in git, `system.stateVersion` is unchanged.

The security trade-off (root execution) is justified, well-documented, and mitigated by a comprehensive set of thirteen systemd hardening options.

---

## 9. Build Result

**PASS** — `nix flake check --impure` exited 0; `nixos-rebuild dry-build --flake .#vexos-server-amd --impure` exited 0.

---

## Verdict: PASS
