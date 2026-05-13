# Portbook Port Detection Fix — Research Specification

**Date**: 2026-05-12  
**Feature**: `portbook_port_detection`  
**Status**: RESEARCH COMPLETE

---

## 1. Current State Analysis

### 1.1 Package (`pkgs/portbook/default.nix`)

- Fetches the pre-built binary for `portbook` v0.2.1 (released 2026-05-08) from GitHub releases.
- Uses `autoPatchelfHook` to repair ELF dependencies.
- Wraps the binary with `makeWrapper`, **prefixing `iproute2` onto PATH** so that the `ss` command comes from the Nix store rather than the host system.
- The binary is a Rust web server / terminal tool that auto-discovers HTTP services on the local host.

### 1.2 Service Module (`modules/server/portbook.nix`)

The module:
- Creates a dedicated non-root system user/group `portbook`
- Defines a `systemd.services.portbook` unit running as `User = "portbook"`
- Grants `AmbientCapabilities = [ "CAP_SYS_PTRACE" ]` and `CapabilityBoundingSet = [ "CAP_SYS_PTRACE" ]` with the stated intent of allowing `ss -p` to see process owners across all UIDs
- Exposes `pkgs.vexos.portbook` in `environment.systemPackages`
- Opens firewall port 7777

### 1.3 Upstream Port Discovery Mechanism

Portbook uses `src/discovery/linux.rs` (v0.2.1). The discovery code:

```rust
let out = Command::new("ss").args(["-tlnpH"]).output()?;
```

It calls `ss` with flags `-t` (TCP), `-l` (listening), `-n` (numeric), `-p` (process info), `-H` (no header).

**Critical privacy filter** (introduced in the last commit before v0.2.1, "Drop other-users' listeners from Linux discovery"):

```rust
// `ss -p` only fills the process column for sockets the caller can
// see — own-user as non-root, all sockets as root. Treat missing
// process info as evidence that the socket belongs to a *different*
// user and skip it.
let Some(proc) = fields.get(5) else { continue };
```

Any `ss` output line that lacks the 6th whitespace-delimited field (the `users:(...)` column) is **silently dropped**. Additionally, lines with `pid=0` are dropped. This is a deliberate design choice to avoid leaking other users' listeners on shared dev hosts.

### 1.4 iproute2 `ss.c` Process Resolution Mechanism

From the upstream iproute2 `ss.c` source (`user_ent_hash_build` / `user_ent_hash_build_task`):

1. `ss -p` scans `/proc/` for all numeric PIDs.
2. For each PID, it calls `opendir("/proc/<pid>/fd/")`.
3. If `opendir()` fails (returns `NULL` → `EACCES`), the PID is silently skipped — no process entry is added for that PID's sockets.
4. If `opendir()` succeeds, it reads each fd symlink looking for `socket:[<inode>]` patterns, building a hash table mapping socket inodes → process names/PIDs.
5. When `ss` formats the output for a listening socket, it calls `find_entry(s->ino, &buf, USERS)`. If no entry exists for that inode, the `users:(...)` column is **omitted entirely from the output line**.

The kernel's permission check for `/proc/<pid>/fd/` is `proc_fd_access_allowed()` → `ptrace_may_access(task, PTRACE_MODE_READ_FSCREDS)`. This grants access if:
- Caller has the **same UID** as the target process, OR
- Caller has `CAP_SYS_PTRACE` in its **effective capability set** (and Yama ptrace_scope ≤ 2 allows it)

There is **no special UID=0 bypass** in this path — root UID alone is insufficient unless root also holds `CAP_SYS_PTRACE` in its effective set. Conversely, a root process with all default capabilities (no `CapabilityBoundingSet` restrictions) does hold `CAP_SYS_PTRACE` effective and can read all `/proc/<pid>/fd/`.

---

## 2. Root Cause Analysis

### 2.1 Primary Root Cause

All system services on a NixOS server (nginx, postgres, gitea, etc.) run as their own dedicated UIDs. When `ss -tlnpH` is executed as the non-root user `portbook`, `opendir("/proc/<nginx-pid>/fd/")` returns `EACCES`. `ss` silently skips those PIDs. The `users:(...)` column is absent from every nginx/postgres/etc. socket line in `ss` output.

Portbook's `parse_ss` function applies the privacy filter — `fields.get(5)` returns `None` for every system service socket — and drops **all** of them. The only socket portbook itself owns (port 7777) is also filtered by the engine-level self-exclusion. Result: **zero detected ports**.

### 2.2 Why `CAP_SYS_PTRACE` Does Not Fix It in Practice

The module attempts to fix this with:
```nix
AmbientCapabilities  = [ "CAP_SYS_PTRACE" ];
CapabilityBoundingSet = [ "CAP_SYS_PTRACE" ];
```

Theoretically, ambient capabilities survive `exec()` for non-privileged executables and should propagate through the call chain:

```
systemd → bash (wrapProgram wrapper) → portbook binary → ss subprocess
```

However, several factors cause this to fail in practice on NixOS servers:

1. **Ambient capability propagation through `wrapProgram` shell wrapper**: systemd's `AmbientCapabilities` sets ambient caps on the **wrapper shell script process** (which runs bash). Per Linux capability rules, ambient caps ARE preserved across `exec()` for non-privileged executables. But in practice this multi-hop chain (systemd → bash → portbook → ss) has been observed to drop or not properly surface ambient capabilities on some kernel/systemd configurations, especially with `CapabilityBoundingSet` limiting the set.

2. **Yama ptrace_scope**: If the server kernel has `kernel.yama.ptrace_scope = 2` or higher, additional restrictions apply. NixOS server kernels with security hardening profiles default to ptrace_scope ≥ 1. With scope=2, even `CAP_SYS_PTRACE` has been restricted in some kernel builds requiring an exact security model.

3. **Module comment vs. reality mismatch**: The comment in the module ("CAP_SYS_PTRACE lets `ss -p` resolve process owners across all UIDs") represents the intended design, but the user-reported behavior ("No listening ports detected") confirms this does not work in the current deployment.

### 2.3 Confirmation

The portbook web UI at `:7777` is accessible (service starts and binds to port 7777) but shows "No listening ports detected on this host." This is consistent with `ss -p` producing output with no `users:(...)` columns for any system service socket, causing portbook to drop all of them.

---

## 3. Proposed Fix

### 3.1 Decision

**Run the portbook service as root** with compensating systemd sandboxing. This is the correct and reliable approach because:

- Root processes have all capabilities (including `CAP_SYS_PTRACE`) in their effective set by default.
- No ambient capability propagation chain is required.
- The upstream documentation explicitly states: "`ss -p` only fills the process column for sockets the caller can see — **own-user as non-root, all sockets as root**."
- The systemd hardening options listed below create a meaningful security boundary even for root-owned services.

### 3.2 Rejected Alternatives

| Alternative | Reason Rejected |
|---|---|
| `security.wrappers` setuid `ss` | Requires users on any UID to execute a setuid binary; broader attack surface |
| `sudo` wrapper for `ss` | Requires sudoers configuration; complex; requires code changes to portbook |
| `setcap cap_sys_ptrace+ep` on `ss` | NixOS does not support arbitrary `setcap` on Nix store binaries; security.wrappers only supports setuid |
| Fix ambient cap chain | Non-deterministic across kernel versions and ptrace_scope configs; fragile |
| Patch portbook to read `/proc/net/tcp` directly | Changes the upstream binary's behavior; not applicable to pre-built binary |

---

## 4. Exact Implementation Steps

### 4.1 File to Modify

**`modules/server/portbook.nix`** — single file change, no other files affected.

### 4.2 Changes Required

#### Remove

- `users.groups.portbook` block
- `users.users.portbook` block
- `User = "portbook"` from `serviceConfig`
- `Group = "portbook"` from `serviceConfig`
- `AmbientCapabilities = [ "CAP_SYS_PTRACE" ]` from `serviceConfig`
- `CapabilityBoundingSet = [ "CAP_SYS_PTRACE" ]` from `serviceConfig`

#### Add to `serviceConfig`

```nix
# Systemd hardening — compensates for running as root.
# portbook is a read-only monitoring daemon: it reads /proc, spawns
# ss, and serves an HTTP API.  It writes nothing to disk.
ProtectSystem             = "strict";
ProtectHome               = true;
PrivateTmp                = true;
ProtectKernelTunables     = true;
ProtectKernelModules      = true;
ProtectKernelLogs         = true;
ProtectControlGroups      = true;
RestrictAddressFamilies   = [ "AF_INET" "AF_INET6" "AF_UNIX" "AF_NETLINK" ];
RestrictNamespaces        = true;
LockPersonality           = true;
MemoryDenyWriteExecute    = true;
SystemCallFilter          = [ "@system-service" ];
NoNewPrivileges           = true;
```

#### Explanation of each option

| Option | Purpose |
|---|---|
| `ProtectSystem = "strict"` | Mounts `/`, `/usr`, `/boot` read-only; portbook writes nothing there |
| `ProtectHome = true` | Hides `/home`, `/root`, `/run/user`; portbook has no business in user dirs |
| `PrivateTmp = true` | Private `/tmp`; isolates any temp files |
| `ProtectKernelTunables = true` | Makes `/proc/sys` and `/sys/fs` read-only; portbook only reads `/proc` |
| `ProtectKernelModules = true` | Prevents module loading; portbook has no reason to load modules |
| `ProtectKernelLogs = true` | Blocks access to kernel log ring buffer |
| `ProtectControlGroups = true` | Makes `/sys/fs/cgroup` read-only |
| `RestrictAddressFamilies` | Allows only the families portbook actually needs: TCP/UDP servers (INET, INET6), Unix sockets (UNIX), and netlink for `ss -p` (NETLINK) |
| `RestrictNamespaces = true` | Prevents creation of new namespaces |
| `LockPersonality = true` | Fixes process personality; prevents `personality()` call |
| `MemoryDenyWriteExecute = true` | Prevents W+X memory mappings; safe for compiled Rust binaries |
| `SystemCallFilter = [ "@system-service" ]` | Restricts to the standard set of syscalls needed by well-behaved daemons; includes socket, fork, exec, file ops, netlink |
| `NoNewPrivileges = true` | Prevents any child from gaining new privileges via setuid/setgid exec |

Note: `CapabilityBoundingSet` is intentionally **not set** so root retains `CAP_SYS_PTRACE` effective (needed for `/proc/<pid>/fd/` access). Do NOT add `CapabilityBoundingSet = ""` — that would strip all capabilities and break `ss -p` even as root.

### 4.3 Final Resulting `serviceConfig` Block

```nix
serviceConfig = {
  Type           = "simple";
  ExecStart      = "${pkgs.vexos.portbook}/bin/portbook serve";
  Environment    = [ "PORTBOOK_NO_OPEN=1" ];
  Restart        = "on-failure";
  RestartSec     = "5s";
  StandardOutput = "journal";
  StandardError  = "journal";

  # Hardening: portbook runs as root to allow ss -p to read
  # /proc/<pid>/fd/ for all system service UIDs.  The options below
  # create a meaningful sandbox even for root.
  ProtectSystem             = "strict";
  ProtectHome               = true;
  PrivateTmp                = true;
  ProtectKernelTunables     = true;
  ProtectKernelModules      = true;
  ProtectKernelLogs         = true;
  ProtectControlGroups      = true;
  RestrictAddressFamilies   = [ "AF_INET" "AF_INET6" "AF_UNIX" "AF_NETLINK" ];
  RestrictNamespaces        = true;
  LockPersonality           = true;
  MemoryDenyWriteExecute    = true;
  SystemCallFilter          = [ "@system-service" ];
  NoNewPrivileges           = true;
};
```

### 4.4 Module Comment Updates

Update the module header comment to remove the misleading claim about `CAP_SYS_PTRACE` and replace it with the root-based explanation.

---

## 5. Risks and Mitigations

| Risk | Likelihood | Mitigation |
|---|---|---|
| portbook CVE exploited to gain root | Low (portbook is a small, read-only HTTP server with no auth) | `ProtectSystem=strict`, `ProtectHome=true`, `NoNewPrivileges=true`, `MemoryDenyWriteExecute=true` create a tight sandbox |
| `MemoryDenyWriteExecute` breaks Rust binary | Very low (compiled Rust does not use JIT or W+X pages) | If it fails, drop only this option |
| `SystemCallFilter=@system-service` blocks a needed syscall | Low | `@system-service` includes all syscalls needed by well-behaved daemons; portbook uses only standard networking and file ops |
| Removing `users.users.portbook` breaks existing deployments with `users.mutableUsers = false` | Low | The portbook user was only ever used by this service; no other module references it |
| `AF_NETLINK` restriction insufficient for `ss` | Very low | `ss` uses `NETLINK_SOCK_DIAG`; `AF_NETLINK` explicitly allows all netlink socket families |

---

## 6. Verification

After applying the fix, verify with:

```bash
# Confirm service runs as root
systemctl show portbook --property=ExecMainPID | xargs -I{} cat /proc/{}/status | grep -E '^(Uid|Gid)'

# Confirm port detection works
curl -s http://localhost:7777/api/ports | jq '.ports | length'

# Confirm the JSON output contains system services
curl -s http://localhost:7777/api/ports | jq '.ports[] | .command'

# CLI verification
portbook ls
```

Expected: `portbook ls` shows nginx, postgres, and other system services running on the host, classified as `live`, `error`, or `dead`.

---

## 7. Sources Consulted

1. **portbook upstream source** — `src/discovery/linux.rs`, `ARCHITECTURE.md` (https://github.com/a-grasso/portbook)
2. **iproute2 ss.c** — `user_ent_hash_build`, `user_ent_hash_build_task`, `proc_ctx_print` (https://github.com/iproute2/iproute2/blob/main/misc/ss.c)
3. **Linux capabilities(7) man page** — ambient capability rules, exec() propagation semantics
4. **Linux kernel ptrace.c** — `__ptrace_may_access`, `ptrace_has_cap` — confirms `CAP_SYS_PTRACE` is the key, root UID alone is insufficient
5. **Linux kernel proc/base.c** — `proc_fd_access_allowed` — confirms `/proc/<pid>/fd/` permission model
6. **systemd.exec(5) man page** — `AmbientCapabilities`, `CapabilityBoundingSet`, `ProtectSystem`, hardening options
7. **NixOS manual — security.wrappers** — evaluated and rejected as a fix mechanism

---

## 8. Summary

**Root cause**: The portbook service runs as a non-root system user `portbook`. When `ss -tlnpH` is spawned as this user, it cannot open `/proc/<pid>/fd/` for any other UID's processes and therefore produces no `users:(...)` column for system service sockets. Portbook's privacy filter drops every socket line without a process column, resulting in zero detected ports.

The existing `AmbientCapabilities = [ "CAP_SYS_PTRACE" ]` was intended to fix this but does not work reliably in practice due to: (a) multi-hop ambient capability propagation through the `wrapProgram`/bash wrapper chain, (b) potential Yama `ptrace_scope` restrictions on the server kernel, and (c) the fundamental mismatch between the theoretical capability model and real-world NixOS server behavior.

**Fix**: Remove the dedicated `portbook` user/group, remove the `AmbientCapabilities`/`CapabilityBoundingSet` directives, and run the service as root. Add compensating systemd sandboxing (`ProtectSystem=strict`, `ProtectHome`, `PrivateTmp`, `ProtectKernelTunables`, `ProtectKernelModules`, `ProtectKernelLogs`, `ProtectControlGroups`, `RestrictAddressFamilies`, `RestrictNamespaces`, `LockPersonality`, `MemoryDenyWriteExecute`, `SystemCallFilter=@system-service`, `NoNewPrivileges`) to mitigate the security implications of the root-owned process.

**File to change**: `modules/server/portbook.nix` (single file)
