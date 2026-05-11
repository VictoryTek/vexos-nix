# NAS Phase C — cockpit-file-sharing — Review & QA

**Date:** 2026-05-11
**Reviewer:** Phase 3 QA subagent
**Spec:** `.github/docs/subagent_docs/nas_phase_c_cockpit_file_sharing_spec.md`
**Verdict:** ❌ NEEDS_REFINEMENT

---

## Executive Summary

The implementation is functionally correct and architecturally sound: the
derivation builds cleanly (`nix-instantiate --eval` returns the expected drv
path), Option B is respected throughout, Samba registry mode is wired up
correctly, NFS firewall ports are correct, and the `samba` package is
explicitly in `systemPackages`. Two CRITICAL issues block approval: `pkgs/default.nix`
and `modules/server/cockpit.nix` were delivered with **CRLF line endings**,
directly violating the repo-memory rule and risking parse failures in any
tooling that runs these files through a POSIX shell pipeline. One RECOMMENDED
fix also applies: the licence attribute uses `gpl3Only` where the upstream
licence is GPL-3.0-or-later, which requires `gpl3Plus`.

---

## Finding Summary

| Severity | Count |
|---|---|
| CRITICAL | 2 |
| RECOMMENDED | 1 |
| NICE-TO-HAVE | 0 |

---

## Per-File Findings

### 1. `pkgs/cockpit-file-sharing/default.nix` ✅ (no blockers)

| Check | Result | Notes |
|---|---|---|
| Uses `stdenvNoCC` | ✅ | Correct — no C compiler needed |
| `fetchurl` (not `fetchFromGitHub`) | ✅ | Downloads the upstream `.deb` directly |
| `dontUnpack = true` | ✅ | Unpack handled manually in `installPhase` |
| `dontConfigure = true` | ✅ | No configure step |
| `dontBuild = true` | ✅ | Pre-built assets — no compilation |
| `dpkg` in `nativeBuildInputs` | ✅ | Provides `dpkg-deb -x` |
| `runHook preInstall` / `runHook postInstall` | ✅ | Correct hook pattern |
| `cp -r extracted/usr/share/cockpit/file-sharing "$out/share/cockpit/"` | ✅ | XDG_DATA_DIRS scan will find `manifest.json` |
| `meta` block complete | ✅ | `description`, `homepage`, `platforms`, `maintainers` present |
| Hash is real (not PLACEHOLDER/fakeHash) | ✅ | `sha256-Jxcp4ucfUbX5BtsMBWvGfeHZBsxl5Yh52CKpuiUQolQ=` confirmed by Phase 2 `nix-build` |
| URL pinned to specific version tag (not branch/latest) | ✅ | `v4.5.6-1` |
| No hardcoded secrets | ✅ | |
| No dead code / TODO / PLACEHOLDER comments | ✅ | |
| Line endings | ✅ LF | `file` reports: `Unicode text, UTF-8 text` (no CRLF) |
| **License attribute** | ⚠️ RECOMMENDED | `licenses.gpl3Only` used, but upstream is GPL-3.0-**or-later** (GPL-3.0+) → should be `licenses.gpl3Plus` |

**Detail on licence finding:**
The upstream repository README and packaging scripts declare `GPL-3.0+`
(GPL-3.0 or any later version). In nixpkgs:
- `licenses.gpl3Only` = "GNU General Public License v3.0 only" (SPDX: `GPL-3.0-only`)
- `licenses.gpl3Plus` = "GNU General Public License v3.0 or later" (SPDX: `GPL-3.0-or-later`)

Using `gpl3Only` is legally incorrect — it understates the downstream permissions
granted by the upstream author. This does not affect the build but is incorrect
metadata.

---

### 2. `pkgs/default.nix` ❌ CRITICAL

| Check | Result | Notes |
|---|---|---|
| Accumulator pattern `(prev.vexos or { }) //` | ✅ | Correct — matches Phase A pattern |
| `cockpit-file-sharing = final.callPackage ./cockpit-file-sharing { };` | ✅ | Correct attribute and path |
| No structural changes to the overlay | ✅ | |
| **Line endings** | ❌ **CRLF** | `file` reports: `ASCII text, with CRLF line terminators` |

**CRITICAL — Line Endings:**
Repo memory (`/memories/repo/preflight-line-endings.md`) explicitly states:
> "Shell scripts in this repo should stay LF-only; CRLF caused bash parse
> failures in scripts/preflight.sh."

The same constraint applies to `.nix` files consumed by POSIX tooling. Phase 2
noted "CRLF→LF was applied" but the file still has CRLF. This must be converted
to LF before merging.

---

### 3. `modules/server/cockpit.nix` ❌ CRITICAL

| Check | Result | Notes |
|---|---|---|
| `fileSharing.enable` option declared | ✅ | `lib.mkOption { type = lib.types.bool; default = cfg.enable; ... }` |
| `default = cfg.enable` (not hardcoded) | ✅ | Matches spec §4.1 exactly |
| `lib.mkMerge` fragment gated by `lib.mkIf cfg.fileSharing.enable` | ✅ | Option gate only — no role/display/gaming guards |
| No new `lib.mkIf` guards by role | ✅ | Option B compliant |
| Assertion is non-tautological | ✅ | `cfg.fileSharing.enable -> cfg.enable` is meaningful: fires when fileSharing enabled without cockpit |
| Assertion inside `mkIf cfg.fileSharing.enable` block | ✅ | Correct — assertion only evaluated when feature is enabled |
| `pkgs.vexos.cockpit-file-sharing` in `systemPackages` | ✅ | Plugin package correctly placed |
| `pkgs.samba` in `systemPackages` | ✅ | Needed for `net` and `smbpasswd` on `$PATH` (not added by `services.samba.enable`) |
| Samba uses `services.samba.settings.global."include" = "registry"` | ✅ | Correct syntax at pinned rev; avoids removed `configText`/`extraConfig` |
| `services.samba.openFirewall = true` | ✅ | TCP 139/445, UDP 137/138 |
| `services.nfs.server.enable = true` | ✅ | |
| NFS firewall: TCP+UDP 2049 and 111 | ✅ | Correct — nfsd (2049) + portmapper (111) |
| `systemd.tmpfiles.rules` creates `/etc/exports.d 0755 root root` | ✅ | Correct mode and ownership |
| No `configText` / `extraConfig` usage | ✅ | Both removed at pinned rev; spec warned about this |
| No TODO / fakeHash comments | ✅ | |
| No hardcoded secrets | ✅ | |
| **Line endings** | ❌ **CRLF** | `file` reports: `Unicode text, UTF-8 text, with CRLF line terminators` |

**CRITICAL — Line Endings:**
Same issue as `pkgs/default.nix`. The file must be converted to LF-only.

**Architecture Compliance (Option B):**
All checks pass. The `fileSharing.enable` option is declared in the
existing module (not a new separate file) because it is an extension of the
same `vexos.server.cockpit` namespace, not a new subsystem. The `lib.mkMerge`
pattern is consistent with Phase A's implementation. No role/display/gaming
conditional gates were introduced. ✅

**Samba Config Correctness:**
`services.samba.settings.global = { "include" = "registry"; }` generates:
```ini
[global]
    include = registry
```
in the NixOS-managed `smb.conf`. This is the correct and only change needed —
the NixOS Samba module's `[global]` defaults (`security = user`, `passwd
program`, `invalid users`) are preserved unchanged. The TDB registry is
auto-initialized by smbd on first start. ✅

---

### 4. `template/server-services.nix` ✅ (no blockers)

| Check | Result | Notes |
|---|---|---|
| New `cockpit.fileSharing.enable` comment line added | ✅ | Under Cockpit section, after `navigator.enable` |
| Comment format matches existing style | ✅ | `# vexos.server.cockpit.fileSharing.enable = true;     # description` |
| Description mentions `requires cockpit.enable = true` | ✅ | Operator guidance present |
| Line endings | ✅ LF | `file` reports: `Unicode text, UTF-8 text` (no CRLF) |

---

## Build Validation

### Static Evaluation

```
$ nix-instantiate --eval --strict -E \
    '(import <nixpkgs> { overlays = [ (import /mnt/c/Projects/vexos-nix/pkgs) ]; }).vexos.cockpit-file-sharing.drvPath'
"/nix/store/6g3c53bgqirwk935s7y0rzigj5waxyms-cockpit-file-sharing-4.5.6.drv"
```

**Result: ✅ PASS** — drv path matches what Phase 2 reported exactly.

### Preflight Script

```
$ bash -l /mnt/c/Projects/vexos-nix/scripts/preflight.sh
EXIT: 0 (PASSED)
```

All mandatory checks passed:
- ✅ hardware-configuration.nix not tracked in git
- ✅ `system.stateVersion` present in all 5 configuration files
- ✅ `flake.lock` tracked in git
- ✅ No hardcoded secret patterns found

Expected WARNINGs (not failures):
- ⚠ `hardware-configuration.nix` not on WSL host → `nix flake check` and dry-build skipped
- ⚠ `jq` not installed → flake.lock pinning/freshness checks skipped
- ⚠ `nixpkgs-fmt` not installed → format check skipped

**Result: ✅ PASS**

---

## Score Table

| Category | Score | Grade |
|---|---|---|
| Specification Compliance | 95% | A |
| Best Practices | 90% | A- |
| Functionality | 98% | A+ |
| Code Quality | 88% | B+ |
| Security | 98% | A+ |
| Performance | 100% | A+ |
| Consistency | 85% | B |
| Build Success | 95% | A |

**Overall Grade: A- (94%)**

Scores are reduced from A+ due to the CRLF line-ending defect delivered in two
of the four changed files despite Phase 2 noting the conversion was applied.

---

## Required Changes Before Re-Review

### CRITICAL — Fix Line Endings (2 files)

Convert from CRLF to LF in:
1. `pkgs/default.nix`
2. `modules/server/cockpit.nix`

```bash
# On the NixOS/WSL host or any Unix:
sed -i 's/\r$//' pkgs/default.nix
sed -i 's/\r$//' modules/server/cockpit.nix
# Verify:
file pkgs/default.nix modules/server/cockpit.nix
# Expected: "ASCII text" / "UTF-8 text" — no "CRLF" in output
```

Or via git on Windows:
```bash
git config core.autocrlf false
# then re-save both files as LF in the editor
```

### RECOMMENDED — Fix Licence Attribute (1 file)

In `pkgs/cockpit-file-sharing/default.nix`, change:
```nix
license = licenses.gpl3Only;
```
to:
```nix
license = licenses.gpl3Plus;
```

This correctly reflects the upstream GPL-3.0-or-later licence.

---

## Verdict

**NEEDS_REFINEMENT**

Two CRITICAL issues (CRLF line endings in `pkgs/default.nix` and
`modules/server/cockpit.nix`) must be resolved. One RECOMMENDED improvement
(licence attribute) should also be applied. All other aspects of the
implementation are correct and spec-compliant.
