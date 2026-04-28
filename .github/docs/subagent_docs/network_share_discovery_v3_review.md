# Network Share Discovery v3 — Review & Quality Assurance

## Date
2026-04-27

## Files Reviewed
- `modules/network-desktop.nix` (modified)

## Reference Files
- `.github/docs/subagent_docs/network_share_discovery_v3_spec.md`
- `modules/network.nix`
- `modules/gnome.nix`
- `configuration-desktop.nix`
- `configuration-headless-server.nix`

---

## 1. Specification Compliance

### 1.1 Required Changes — Status

| Spec Requirement | Status | Notes |
|------------------|--------|-------|
| `systemd.tmpfiles.settings` for `/etc/samba` symlink | ✅ Present | Evaluates correctly via `nix eval` |
| Symlink target = `/etc/static/samba` | ✅ Correct | Confirmed via `nix eval --impure` |
| `"client max protocol" = "SMB3"` | ✅ Present | Renders correctly in samba settings |
| `"client min protocol" = "SMB2"` | ✅ Present | Security: blocks SMBv1 |
| `"load printers"` disabled | ✅ Present | Uses `"no"` (string) vs spec's `false` (boolean) — see Finding #2 |
| All v2 components preserved | ✅ Verified | Samba client, Avahi publish, WSDD, NFS all present |
| `services.samba.enable = true` | ✅ Present | |
| All server daemons disabled (`lib.mkDefault false`) | ✅ Correct | nmbd, smbd, winbindd all `lib.mkDefault false` |

### 1.2 Spec Deviations

**Finding #1 (RECOMMENDED): tmpfiles type `L` vs `L+`**

The spec (Part 4.3, 4.5, 4.6) explicitly uses `"L+"` and explains:
> The `L+` type means: create symlink, removing any existing file/directory/symlink first

The implementation uses `L` (without `+`):
```nix
# Implementation (current):
"/etc/samba" = {
  L = {
    argument = "/etc/static/samba";
  };
};

# Spec (expected):
"/etc/samba" = {
  "L+" = {
    argument = "/etc/static/samba";
  };
};
```

**Impact:** `L` creates the symlink only if the path doesn't exist. `L+` removes any existing content first, then creates the symlink. For the observed bug (missing `/etc/samba`), both work identically. However, `L+` is more robust: if `/etc/samba` ever exists as a stale directory (e.g., from a partial etc activation), `L` would skip it while `L+` would fix it. The spec's choice of `L+` is deliberate and well-reasoned. **Recommend changing to `"L+"` per spec.**

**Finding #2 (MINOR): `"load printers"` value**

Spec: `"load printers" = false;` (Nix boolean → `"false"` in INI)
Implementation: `"load printers" = "no";` (string → `"no"` in INI)

Both are valid Samba booleans. Functionally equivalent. Cosmetic deviation only.

**Finding #3 (MINOR): Section ordering**

The spec groups the tmpfiles block immediately after the samba config block (related items together). The implementation places it after the WSDD section. Minor readability preference — no functional impact.

---

## 2. tmpfiles Rule Correctness

| Check | Result |
|-------|--------|
| `systemd.tmpfiles.settings` syntax valid | ✅ `nix eval` succeeds without error |
| `L` type creates a symlink | ✅ Correct (but should be `L+` per spec — see Finding #1) |
| Argument points to `/etc/static/samba` | ✅ Confirmed: `argument = "/etc/static/samba"` |
| Conflict with NixOS etc management? | ✅ No conflict — see analysis below |
| tmpfiles rule name `"10-samba-etc"` | ✅ Follows NixOS naming convention with priority prefix |

### Conflict Analysis with NixOS etc Management

On NixOS, the etc activation script:
1. Generates files to `/etc/static/`
2. Creates symlinks: `/etc/<name>` → `/etc/static/<name>`

The tmpfiles rule creates the same symlink (`/etc/samba` → `/etc/static/samba`). This is **not a conflict** because:
- During boot: `systemd-tmpfiles-setup.service` runs early (before user sessions). If the etc activation later recreates the symlink, it's idempotent.
- During `nixos-rebuild switch`: the etc activation runs during system activation. The tmpfiles rule is already applied. Both produce the same result.
- If the etc activation fixes itself in a future NixOS version, the tmpfiles rule becomes a harmless no-op.

**Evaluated output confirms correctness:**
```
{ "10-samba-etc" = { "/etc/samba" = { L = { age = "-"; argument = "/etc/static/samba"; 
  group = "-"; mode = "-"; type = "L"; user = "-"; }; }; }; }
```

---

## 3. Architecture Compliance

| Check | Result |
|-------|--------|
| No `lib.mkIf` guards in `network-desktop.nix` | ✅ PASS — zero matches via grep |
| `lib.mkDefault` on daemon enables | ✅ PASS — nmbd, smbd, winbindd all use `lib.mkDefault false` |
| Module naming follows `<subsystem>-<qualifier>.nix` convention | ✅ `network-desktop.nix` |
| Imported by display roles only | ✅ desktop, htpc, server, stateless — NOT headless-server |
| No samba conflicts with server modules | ✅ `services.samba` only defined in `network-desktop.nix` |
| Clean code style | ✅ Consistent section headers, comprehensive comments |
| Module header comment accurate | ✅ Describes purpose, intended import targets |
| Function signature `{ lib, ... }:` | ✅ Minimal — only imports what's used |

---

## 4. Security

| Check | Result |
|-------|--------|
| SMB2 minimum protocol enforced | ✅ `"client min protocol" = "SMB2"` blocks SMBv1 |
| SMB3 maximum protocol set | ✅ `"client max protocol" = "SMB3"` |
| No unnecessary inbound ports | ✅ Only WSDD ports (TCP 5357, UDP 3702) + existing mDNS (UDP 5353) |
| SMB port 445 not opened inbound | ✅ Client-only — outbound connections only |
| Server daemons disabled | ✅ smbd, nmbd, winbindd all `false` |
| tmpfiles rule permissions | ✅ `mode = "-"` and `user = "-"` — symlink inherits default ownership |
| No hardcoded secrets | ✅ |
| No world-writable files created | ✅ |

---

## 5. Build Validation

### 5.1 `nix flake check`

```
error: access to absolute path '/etc' is forbidden in pure evaluation mode
```

**Pre-existing issue.** All host configurations import `/etc/nixos/hardware-configuration.nix` which is forbidden in pure evaluation mode. This is by design — hardware-configuration.nix is host-generated and not tracked in the repository. **Unrelated to v3 changes.**

### 5.2 `nix flake check --impure`

```
Failed assertions:
- You must set the option 'boot.loader.grub.devices' or 'boot.loader.grub.mirroredBoots'
```

**Pre-existing issue.** `boot.loader.grub.devices` is set in the host's `/etc/nixos/hardware-configuration.nix`, which is only available on the actual target machine. **Unrelated to v3 changes.**

### 5.3 `nix eval --impure` (module-level validation)

| Evaluation | Result |
|------------|--------|
| `config.systemd.tmpfiles.settings` | ✅ Evaluates correctly — `10-samba-etc` entry present |
| `config.services.samba.settings.global` | ✅ All settings render correctly |

**Rendered samba global settings:**
```json
{
  "client max protocol": "SMB3",
  "client min protocol": "SMB2",
  "load printers": "no",
  "security": "user",
  "server role": "standalone",
  "server string": "NixOS",
  "workgroup": "WORKGROUP"
}
```

All expected settings are present and correct.

### 5.4 Additional Checks

| Check | Result |
|-------|--------|
| `hardware-configuration.nix` NOT in git | ✅ `git ls-files` confirms not tracked |
| `system.stateVersion` unchanged | ✅ `"25.11"` in `configuration-desktop.nix` |
| No new flake inputs added | ✅ No changes to `flake.nix` |
| No new imports required | ✅ `network-desktop.nix` already imported by all display roles |

---

## 6. Completeness & Functionality

| Check | Result |
|-------|--------|
| Root cause addressed (missing `/etc/samba` symlink) | ✅ tmpfiles rule creates it |
| Fix is a safety net, not a workaround | ✅ Works alongside normal etc activation |
| Fix survives reboots | ✅ tmpfiles rules run on every boot |
| Fix survives `nixos-rebuild switch` | ✅ Both activation and tmpfiles maintain the symlink |
| `smbclient` can load config | ✅ `/etc/samba/smb.conf` will resolve via symlink |
| `gvfsd-smb-browse` can find smb.conf | ✅ libsmbclient reads `/etc/samba/smb.conf` |
| Nautilus Network tab will work | ✅ Full chain: Nautilus → GVfs → gvfsd-smb-browse → libsmbclient → smb.conf |
| Printer enumeration suppressed | ✅ `"load printers" = "no"` |
| All v2 features preserved | ✅ Avahi publish, WSDD, NFS, samba client config |

---

## 7. Summary of Findings

### CRITICAL Issues
None.

### RECOMMENDED Changes

1. **Change tmpfiles type from `L` to `"L+"`** — Aligns with spec, more robust for edge cases where `/etc/samba` might exist as a stale directory. The spec explicitly chose `L+` and provided rationale in Parts 4.5 and 4.6.

### MINOR Notes

2. **`"load printers"` uses `"no"` instead of `false`** — Functionally equivalent. Both are valid Samba booleans. No action required.

3. **Section ordering differs from spec** — tmpfiles block is after WSDD instead of after samba config. No functional impact. Optional readability improvement.

---

## 8. Score Table

| Category | Score | Grade |
|----------|-------|-------|
| Specification Compliance | 90% | A- |
| Best Practices | 95% | A |
| Functionality | 100% | A+ |
| Code Quality | 95% | A |
| Security | 100% | A+ |
| Performance | 100% | A+ |
| Consistency | 95% | A |
| Build Success | 85% | B+ |

**Overall Grade: A (95%)**

Build Success scored 85% due to pre-existing `nix flake check` failures (unrelated to this change). Module-level evaluation succeeds fully.

Specification Compliance scored 90% due to the `L` vs `L+` deviation, which is the single substantive finding. The fix is functionally correct for the observed bug but deviates from the spec's more robust approach.

---

## 9. Verdict

**PASS**

The v3 implementation correctly addresses the root cause of the network share discovery failure. The tmpfiles rule ensures `/etc/samba` exists as a symlink to `/etc/static/samba`, allowing libsmbclient (and therefore GVfs gvfsd-smb-browse) to find smb.conf. All v2 components are preserved, no architecture violations exist, security is sound, and the code is clean and well-documented.

The single recommended change (`L` → `L+`) improves robustness but does not block functionality for the observed failure mode. The fix is ready for deployment.
