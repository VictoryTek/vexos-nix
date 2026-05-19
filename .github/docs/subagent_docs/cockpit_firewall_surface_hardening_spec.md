# cockpit-firewall-surface-hardening Spec (Phase 1)

## Metadata
- Feature slug: cockpit-firewall-surface-hardening
- Phase: 1 (Research and Specification)
- Repository: vexos-nix
- Scope: Hardening network exposure for Cockpit + Samba + NFS while keeping LAN usability
- Implementation phase: Not included in this document (Phase 2 only)

## 1. Current State Analysis

### 1.1 Confirmed exposure points

1. Cockpit enables automatic firewall opening:
- `modules/server/cockpit.nix:87`
- `services.cockpit.openFirewall = true;`

2. Samba enables automatic firewall opening:
- `modules/server/cockpit.nix:128`
- `services.samba.openFirewall = true;`
- At the nixpkgs module level, this opens TCP 139/445 and UDP 137/138.

3. NFS and rpcbind ports are opened globally:
- `modules/server/cockpit.nix:149`
- `modules/server/cockpit.nix:150`
- `networking.firewall.allowedTCPPorts = [ 2049 111 ];`
- `networking.firewall.allowedUDPPorts = [ 2049 111 ];`

### 1.2 Activation path and blast radius

1. `modules/server/default.nix` imports `./cockpit.nix`.
2. `modules/server/nas.nix` sets defaults that auto-enable Cockpit and file-sharing when NAS is enabled.
3. Server roles import server module umbrella, so this affects server/headless-server compositions.

### 1.3 Existing hardening already present (important correction)

Fail2ban and a Cockpit jail are already enabled in server security profile:
- `modules/security-server.nix:61` (`services.fail2ban.enable = true`)
- `modules/security-server.nix:74` (`jails.cockpit`)

This means the primary gap is surface control (what is reachable and where), not absence of brute-force controls.

## 2. Problem Definition

Current defaults combine:
- Cockpit auto-open firewall,
- Samba auto-open firewall,
- NFS/rpcbind globally opened ports.

This creates a broad attack surface on any network where the host is reachable.

### 2.1 Security objective

Reduce exposed ports and scope exposure to intended LAN use, without breaking the Cockpit file-sharing workflow.

### 2.2 Functional objective

Keep GUI-based management usable for typical private/home LAN deployments.

### 2.3 Non-goals

- Replacing Cockpit file-sharing architecture.
- Introducing reverse proxies, SSO, or VPN requirements as mandatory defaults.
- Re-architecting unrelated modules.

## 3. Research Summary (Authoritative Sources)

## 3.1 NixOS module behavior

1. Cockpit module in nixpkgs:
- `services.cockpit.openFirewall` defaults to `false`.
- When enabled, it adds cockpit port to firewall allowed TCP ports.
- Source: `nixos/modules/services/monitoring/cockpit.nix` (NixOS/nixpkgs).

2. Samba module in nixpkgs:
- `services.samba.openFirewall` opens TCP 139/445 and UDP 137/138.
- Source: `nixos/modules/services/network-filesystems/samba.nix` (NixOS/nixpkgs).

3. NFS module in nixpkgs:
- Supports `services.nfs.server.hostName`, `mountdPort`, `lockdPort`, `statdPort`.
- `services.rpcbind.enable = true` is part of NFS stack wiring.
- Source: `nixos/modules/services/network-filesystems/nfsd.nix` and `nixos/modules/tasks/filesystems/nfs.nix` (NixOS/nixpkgs).

4. Firewall module in nixpkgs:
- `networking.firewall.interfaces` provides per-interface allowed ports.
- `trustedInterfaces` accepts all traffic from listed interfaces (too broad for this use-case).
- Firewalld backend does not support `networking.firewall.interfaces` in this path.
- Source: `nixos/modules/services/networking/firewall.nix`, `firewall-iptables.nix`, `firewall-firewalld.nix` (NixOS/nixpkgs).

## 3.2 Upstream service guidance

5. Samba config semantics:
- `interfaces`, `bind interfaces only`, and host ACL controls are key network-surface controls.
- Source: `smb.conf(5)` on mankier.

6. NFS daemon and mount daemon:
- NFS can be bound (`nfsd -H` / host option), mountd port can be pinned for firewalling.
- Source: `nfsd(8)` and `mountd(8)` on man7.

7. NFS export access controls:
- Exports support host/network-based allowlists and options controlling access/security.
- Source: `exports(5)` on man7.

8. Cockpit runtime guidance:
- Standard web endpoint is `https://<host>:9090`; docs explicitly call out firewall opening as an operational step.
- Source: cockpit-project running docs.

9. NixOS operational guidance for NFS firewalling:
- NFSv4 minimal opening differs from NFSv3 (which typically requires fixed auxiliary ports).
- Source: NixOS Wiki NFS page.

Total credible sources used: 9

## 4. Proposed Solution Architecture

Design principle: move from broad implicit exposure to explicit, minimal, configurable exposure.

### 4.1 High-level approach

1. Stop using service-level automatic firewall opening for Cockpit and Samba.
2. Replace with explicit firewall rule construction in this module.
3. Default NFS exposure to a v4-oriented minimal profile, with opt-in v3 compatibility profile.
4. Add Samba bind/ACL controls for LAN scoping.
5. Preserve existing Option B architecture by implementing in `modules/server/cockpit.nix` (server-specific module), without adding role-gated logic to shared base modules.

### 4.2 Proposed option model (to be added under `vexos.server.cockpit`)

1. Firewall scope options:
- `vexos.server.cockpit.firewall.interfaces` (list of interface names, default `[]`)
- `vexos.server.cockpit.firewall.allowedCidrs` (CIDR allowlist for service ACLs; default private RFC1918 + ULA + localhost)

2. Samba surface options:
- `vexos.server.cockpit.fileSharing.samba.enableNetbios` (bool, default `false`)
- `vexos.server.cockpit.fileSharing.samba.bindInterfacesOnly` (bool, default `true`)

3. NFS surface options:
- `vexos.server.cockpit.fileSharing.nfs.profile` enum:
  - `"v4-minimal"` (default)
  - `"v3-compatible"`
- Optional fixed ports used only for `v3-compatible` profile (mountd/lockd/statd).

### 4.3 Behavioral specification

1. Cockpit:
- Set `services.cockpit.openFirewall = false`.
- Open cockpit port explicitly in module-managed firewall rules.

2. Samba:
- Set `services.samba.openFirewall = false`.
- Keep registry mode.
- Add `settings.global` hardening controls:
  - `include = registry` (existing)
  - `bind interfaces only = yes` (when enabled)
  - `interfaces = ...` (when interface list is provided)
  - `hosts allow = ...` (from allowlist)
- Firewall ports:
  - Always open TCP 445 for file sharing.
  - Open 139/137/138 only when `enableNetbios = true`.

3. NFS:
- Keep `services.nfs.server.enable = true` and plugin-managed exports path behavior.
- For `v4-minimal` profile:
  - Open TCP 2049 only.
  - Do not open rpcbind or auxiliary v3 ports.
- For `v3-compatible` profile:
  - Pin mountd/lockd/statd ports.
  - Open required TCP/UDP ports (111, 2049, fixed auxiliary ports, and mountd default where applicable).

4. Interface scoping:
- If `firewall.interfaces` is non-empty, apply port openings via `networking.firewall.interfaces.<iface>`.
- If empty, apply global allowed ports and emit a warning prompting explicit interface scoping.

### 4.4 Compatibility strategy

1. Preserve usability for existing LAN users through sane defaults.
2. Provide explicit opt-in for legacy NetBIOS and NFSv3 behavior.
3. Avoid hard failure for hosts not yet migrated to interface scoping; use warning-first migration path.

## 5. File-by-File Phase 2 Plan

1. `modules/server/cockpit.nix` (primary)
- Add new options.
- Replace automatic `openFirewall` usage with explicit rule generation.
- Add Samba bind/ACL settings.
- Add NFS profile logic and fixed-port logic for v3 compatibility.
- Add assertions/warnings for unsupported combinations (e.g., interface scoping + firewalld backend).

2. `modules/security-server.nix` (minor doc consistency update)
- Update comments that currently imply Cockpit exposure is always from `openFirewall=true`.
- No behavior change required.

3. Optional docs update (if maintainers want user-facing discoverability)
- Update role/server docs to describe new cockpit file-sharing hardening options.

## 6. Risks and Mitigations

1. Risk: Interface-scoped rules could lock out management if wrong interface is configured.
- Mitigation: warning-first migration, clear defaults, and explicit documentation.

2. Risk: Disabling NetBIOS by default may impact legacy discovery workflows.
- Mitigation: `enableNetbios` opt-in toggle.

3. Risk: NFSv3 clients may fail under v4-minimal profile.
- Mitigation: `v3-compatible` profile with fixed ports.

4. Risk: Firewalld backend incompatibility with `networking.firewall.interfaces`.
- Mitigation: assertion/warning and fallback behavior.

5. Risk: Comment-level stale analysis could mislead future maintenance.
- Mitigation: refresh comments in touched modules as part of Phase 2.

## 7. Validation Plan (Phase 2/3)

1. Static/eval checks:
- `nix flake check`

2. Dry-build matrix (minimum):
- `sudo nixos-rebuild dry-build --flake .#vexos-server-amd`
- `sudo nixos-rebuild dry-build --flake .#vexos-server-nvidia`
- `sudo nixos-rebuild dry-build --flake .#vexos-server-vm`

3. Runtime verification on a target server:
- Confirm listening ports: `ss -tulpen | rg '9090|445|2049|111|4000|4001|4002|20048'`
- Confirm firewall rules for scoped/global profile.
- Validate Cockpit login and file-sharing plugin operations.
- Validate Samba/NFS access from an allowed LAN host.
- Validate blocked access from non-allowlisted segment (if available).

4. Policy checks:
- Ensure `hardware-configuration.nix` remains untracked.
- Ensure no change to `system.stateVersion`.

## 8. Dependencies and Configuration Impact

- New dependencies: none.
- New flake inputs: none.
- External API integrations: none.
- Main impact: Nix module option surface and generated firewall/service configuration.

## 9. Implementation Readiness

This specification is implementation-ready for Phase 2.

Phase 2 should modify code now: Yes (after user/orchestrator approval of this Phase 1 spec).
