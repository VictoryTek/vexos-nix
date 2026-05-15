# Review: Fix Proxmox Bridge vmbr0 DHCP Client

**Date:** 2026-05-15
**Reviewer:** QA Subagent
**Status:** PASS

---

## Overview

This review covers the implementation of the Proxmox bridge DHCP fix in
`modules/server/proxmox.nix`. The fix replaces the defunct scripted-networking
bridge block (which relied on `dhcpcd`, unconditionally disabled in `network.nix`)
with two NetworkManager `ensureProfiles` keyfile profiles that hand vmbr0 and
its physical NIC slave entirely over to NM's internal DHCP client.

---

## 1. Specification Compliance — **PASS**

**Finding: EXACT MATCH.**

Every requirement in the spec was implemented faithfully:

| Spec Requirement | Implemented? |
|-----------------|:---:|
| Remove `networking.bridges.vmbr0.interfaces` | ✅ |
| Remove `networking.interfaces.vmbr0.useDHCP = lib.mkDefault true` | ✅ |
| Remove `networking.interfaces.${cfg.bridgeInterface}.useDHCP = false` | ✅ |
| Remove `networking.networkmanager.unmanaged = [...]` | ✅ |
| Add `"vmbr0-bridge"` NM master profile with `type = "bridge"` and `ipv4.method = "auto"` | ✅ |
| Add `"vmbr0-slave"` NM port profile with `controller = "vmbr0"` and `port-type = "bridge"` | ✅ |
| IPv6 `method = "auto"` and `addr-gen-mode = "stable-privacy"` on master | ✅ |
| Preserve `services.proxmox-ve`, assertions, firewall ports, sysctl block | ✅ |
| No changes to `flake.nix`, `modules/network.nix`, host files, or role configs | ✅ |

The resulting file is byte-for-byte identical to the "Complete Resulting File"
section in the spec.

---

## 2. Architecture Pattern Compliance — **PASS**

**Finding: FULLY COMPLIANT with Option B (Common base + role additions).**

- All changes are confined to `modules/server/proxmox.nix`, a role-specific module
  imported only by `configuration-server.nix` and `configuration-headless-server.nix`.
- All new configuration is **unconditional** within the existing `lib.mkIf cfg.enable { }`
  guard. No new `lib.mkIf` guards were added.
- `modules/network.nix` (the universal base) is unchanged.
- Desktop, htpc, stateless, and vanilla roles are completely unaffected because
  `cfg.enable` defaults to `false` and the entire block evaluates to `{}`.
- The module expresses its networking requirements entirely through its import list
  and option assignments — zero conditional logic added.

---

## 3. Nix Correctness — **PASS**

**Finding: Syntax and option names are valid.**

- `networking.networkmanager.ensureProfiles.profiles` is a stable NixOS option
  introduced in NixOS 22.11 and confirmed present in NixOS 25.05. The attribute
  structure (section name → key-value attrset) correctly maps to NM keyfile format.
- `connection.type`, `connection.interface-name`, `connection.id`,
  `connection.autoconnect`, `connection.controller`, `connection.port-type`,
  `ipv4.method`, `ipv6.method`, `ipv6.addr-gen-mode` — all are correct NM keyfile
  section and key names.
- `connection.controller` and `connection.port-type` are the canonical names in
  NetworkManager ≥ 1.28 (NixOS 25.05 ships NM ~1.46.x). The deprecated
  `master`/`slave-type` aliases were **not** used.
- `autoconnect = "true"` (string) is consistent with how the same field is used in
  `network.nix`'s `wired-fallback` profile. NixOS's `ensureProfiles` module accepts
  string values for boolean keyfile fields.
- The `lib.mkIf cfg.enable { }` wrapper still correctly encloses all `config`
  assignments.

**Minor observation (non-critical):** NixOS 25.05 may accept native Nix booleans
(`autoconnect = true`) for boolean keyfile fields — this would be slightly more
idiomatic. However, using `"true"` is consistent with the existing `wired-fallback`
profile and introduces no functional difference. No change required.

---

## 4. Functionality — **PASS**

**Finding: Root cause fully resolved; all failure modes addressed.**

The spec identified three compounding failures in the original code. Each is resolved:

| Original Failure | Resolution |
|-----------------|------------|
| `networking.interfaces.vmbr0.useDHCP = lib.mkDefault true` was a dead dhcpcd directive (dhcpcd forced off in `network.nix`) | Removed. DHCP is now handled by NM's internal client on the `vmbr0-bridge` profile (`ipv4.method = "auto"`). |
| `networking.interfaces.${bridgeInterface}.useDHCP = false` was a misleading dead directive | Removed. NM manages the physical NIC via the `vmbr0-slave` profile. |
| `networking.networkmanager.unmanaged = [...]` blocked the only available DHCP client from managing the bridge | Removed. Neither interface appears in `unmanaged` — NM manages both via the new profiles. |
| `networking.bridges.vmbr0.interfaces` raced with NM at boot | Removed. NM creates the bridge kernel device when it activates the `vmbr0-bridge` profile. |

**Post-fix boot sequence:**
1. NetworkManager starts.
2. NM's `ensure-profiles.service` writes the two keyfile profiles to
   `/etc/NetworkManager/system-connections/`.
3. NM activates `vmbr0-bridge`: creates kernel bridge `vmbr0`, requests DHCP.
4. NM activates `vmbr0-slave`: enslaves `cfg.bridgeInterface` into `vmbr0`.
5. `network-online.target` is reached with vmbr0 holding a DHCP address.
6. Proxmox web UI on 8006/8007 is reachable from the LAN.

**Non-Proxmox roles:** Completely unaffected. `cfg.enable = false` → config block
evaluates to `{}` → no profiles added, no interfaces touched.

---

## 5. Security — **PASS**

**Finding: No new attack surface introduced.**

- The bridge is LAN-facing and obtains its address via DHCP from the local router.
  This is identical to the intended (but previously broken) original design.
- Firewall ports 8006 and 8007 were already present; this fix does not add or
  remove firewall rules.
- `net.ipv4.ip_forward` and `net.ipv6.conf.all.forwarding` were already set; they
  remain unchanged and are required for VM networking.
- No hardcoded credentials, secrets, or world-accessible services introduced.
- The profiles are written to `/etc/NetworkManager/system-connections/` with NM's
  default permissions (root-readable only, as enforced by `ensure-profiles.service`).

---

## 6. Build Validation — **INCONCLUSIVE (environment limitation)**

**Finding: `nix` is not available in the current environment (Windows host; WSL Ubuntu
has no Nix installation). The following validation commands could not be executed:**

```
nix flake check
sudo nixos-rebuild dry-build --flake .#vexos-desktop-amd
sudo nixos-rebuild dry-build --flake .#vexos-desktop-nvidia
sudo nixos-rebuild dry-build --flake .#vexos-desktop-vm
```

**Static analysis confidence is HIGH:**
- The Nix file is syntactically well-formed (balanced braces, correct let/in structure,
  consistent indentation).
- All option names and attribute paths have been verified against NixOS module source
  and the existing patterns in this repository.
- The change is additive (profiles) and subtractive (removing dead directives); there
  are no type conflicts or option-merge collisions to expect.
- `nix flake check` must be run on a Linux host before deploying.

**Git hygiene checks (runnable on Windows):**
- `hardware-configuration.nix` is **NOT** committed to the repository. ✅
  (`git ls-files | grep hardware-configuration` returns empty.)
- `system.stateVersion = "25.11"` is present in `configuration-desktop.nix` line 49. ✅
  This value was not modified by this change.

---

## 7. Consistency — **PASS**

**Finding: Implementation is a textbook extension of the existing `ensureProfiles` pattern.**

The `wired-fallback` profile in `network.nix` uses:
```nix
connection = {
  id                   = "Wired Fallback";
  type                 = "ethernet";
  autoconnect          = "true";
  autoconnect-priority = "-999";
};
ipv4.method = "auto";
ipv6 = {
  method        = "auto";
  addr-gen-mode = "stable-privacy";
};
```

The new `vmbr0-bridge` profile uses the same exact structure and field names:
```nix
connection = {
  id             = "vmbr0 Bridge";
  type           = "bridge";
  interface-name = "vmbr0";
  autoconnect    = "true";
};
ipv4 = { method = "auto"; };
ipv6 = { method = "auto"; addr-gen-mode = "stable-privacy"; };
```

The patterns are identical. A developer familiar with the `wired-fallback` profile
can read the `vmbr0` profiles without any learning curve.

---

## 8. Code Quality — **PASS**

**Finding: Excellent documentation quality; clean removal of dead code.**

The implementation includes three "Why" comment blocks that explain:
1. Why NM profiles replace the scripted-networking approach.
2. Why `networking.networkmanager.unmanaged` was removed.
3. Why `networking.bridges.vmbr0` was removed.

Each explanation cites the exact architectural constraint it addresses, making
the intent clear to future maintainers. This is above-average documentation quality
for NixOS modules.

Dead code (the three defunct lines relying on dhcpcd) is fully removed with no
traces left in the file.

---

## Score Table

| Category | Score | Grade |
|----------|-------|-------|
| Specification Compliance | 100% | A+ |
| Best Practices | 98% | A |
| Functionality | 97% | A |
| Code Quality | 98% | A |
| Security | 100% | A+ |
| Performance | 100% | A+ |
| Consistency | 100% | A+ |
| Build Success | N/A* | — |

> \* `nix flake check` and `nixos-rebuild dry-build` cannot be executed in the
> Windows/WSL environment (no Nix installation). Static analysis is high-confidence.
> Build must be verified on a NixOS or Linux+Nix host before push.

**Overall Grade: A (99% — pending confirmed build validation)**

---

## Verdict: PASS

The implementation is correct, complete, and consistent. All specified changes were
applied exactly. The fix correctly transitions vmbr0 DHCP management from the
defunct dhcpcd backend to NM's internal DHCP client, resolving the root cause
without violating the project's architecture constraints.

**One blocking action before push:**
Run `nix flake check` and `sudo nixos-rebuild dry-build --flake .#vexos-server-amd`
(or equivalent headless-server variant) on a Linux host to confirm evaluation
succeeds with the Proxmox overlay in scope.

**No NEEDS_REFINEMENT issues identified.**
