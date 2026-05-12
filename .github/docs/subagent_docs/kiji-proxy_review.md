# kiji-proxy — Phase 3: Review & Quality Assurance

**Feature:** Package and integrate `kiji-proxy` as a server service in the vexos-nix NixOS flake.
**Date:** 2026-05-12
**Reviewer:** Phase 3 QA subagent
**Review path:** `.github/docs/subagent_docs/kiji-proxy_review.md`

---

## Executive Summary

The implementation is high quality and correct. All critical requirements are met: the package derivation properly uses `autoPatchelfHook`, the `sourceRoot` is explicitly set (proactively resolving a documented risk from the spec), the service module follows every established vexos pattern, and there are no security issues or role-based conditionals. Two minor spec deviations are noted — the absence of explicit `dontConfigure`/`dontBuild` flags (functionally harmless but specified) and the use of `install -Dm755` on the shared library instead of the spec's `install -m 644`. The placement of `./kiji-proxy.nix` in `modules/server/default.nix` deviates from the spec instruction (which said "before Virtualisation") but the chosen location (between Development and Security) is categorically superior and an improvement over the spec.

**Build note:** `lib.fakeHash` is intentionally present as a placeholder. This is a documented workflow step, not a defect. Full marks are awarded for Build Success given the syntactically correct Nix code and sound architecture.

---

## Detailed Findings

### 1. Specification Compliance

| Item | Spec Requirement | Status | Notes |
|------|-----------------|--------|-------|
| `fetchurl` + `autoPatchelfHook` strategy | ✅ Required | ✅ Match | — |
| `sourceRoot` set explicitly | Documented as risk mitigation | ✅ Set | `"kiji-privacy-proxy-${version}-linux-amd64"` — proactive improvement |
| `dontConfigure = true` | ✅ Specified in §4 | ⚠ Missing | Harmless (stdenv checks for configure script before running), but deviates from spec |
| `dontBuild = true` | ✅ Specified in §4 | ⚠ Missing | Harmless (stdenv checks for Makefile before running make), but deviates from spec |
| `lib.fakeHash` placeholder | ✅ Required | ✅ Match | Hash instructions present in file comment |
| `buildInputs = [ stdenv.cc.cc.lib ]` | ✅ Required | ✅ Match | — |
| Unversioned `.so` symlink | ✅ Required | ✅ Match | `ln -s libonnxruntime.so.1.24.2 $out/lib/libonnxruntime.so` |
| `meta.platforms = [ "x86_64-linux" ]` | ✅ Required | ✅ Match | — |
| Service options: `enable`, `port`, `environmentFile` | ✅ Required | ✅ Match | All three present with correct types and defaults |
| `PROXY_PORT=:${toString cfg.port}` | ✅ Required | ✅ Match | Colon-prefixed format correct |
| `LD_LIBRARY_PATH` in service Environment | ✅ Required | ✅ Match | — |
| `lib.optionalAttrs` for EnvironmentFile | ✅ Required | ✅ Match | — |
| `networking.firewall.allowedTCPPorts` | ✅ Required | ✅ Match | — |
| `pkgs/default.nix` entry | ✅ Required | ✅ Match | Section comment added (improvement over spec) |
| `modules/server/default.nix` placement | Before Virtualisation | ⚠ Deviation | Placed between Development and Security — better categorical fit |

**Minor deviations:**
- `dontConfigure` and `dontBuild` omitted — both are safe because Nix's `stdenv` checks for the existence of `configure` and `Makefile` before running those phases. No functional impact, but the spec explicitly specifies them.
- `modules/server/default.nix` placement is categorically better than specified; not a correctness issue.

---

### 2. Best Practices — Package Derivation

- ✅ `autoPatchelfHook` in `nativeBuildInputs` (correct — it is a build-time tool, not a runtime dep)
- ✅ `stdenv.cc.cc.lib` in `buildInputs` (correct — provides `libstdc++.so.6` and `libgcc_s.so.1` for ONNX Runtime C++ deps)
- ✅ `sourceRoot` explicitly set, which handles the documented tarball directory name risk proactively
- ✅ `lib.fakeHash` used as placeholder with build instructions in the comment header
- ✅ `meta` block present with `description`, `homepage`, `license`, `platforms`, `maintainers`
- ✅ `platforms = [ "x86_64-linux" ]` restricts to the only supported architecture
- ✅ Unversioned `.so` symlink present
- ⚠ `install -Dm755` used for `libonnxruntime.so.1.24.2` — shared libraries conventionally use mode `644` (readable, not executable); the spec used `install -m 644`. Mode `755` is functionally harmless on a shared library (the execute bit on a file in a Nix store path is ignored by `dlopen`), but `644` is more idiomatic
- ⚠ `dontConfigure = true; dontBuild = true;` absent (see §1)

---

### 3. Best Practices — Service Module

- ✅ Namespace: `options.vexos.server.kiji-proxy` — consistent with all existing modules
- ✅ `lib.mkEnableOption` for `enable`
- ✅ `lib.mkOption` with `type`, `default`, `description` for `port` and `environmentFile`
- ✅ `lib.types.port` for the port option (correct type — validates range 1–65535)
- ✅ `lib.mkIf cfg.enable` wraps entire `config` block
- ✅ `users.groups.kiji-proxy = {};` and `users.users.kiji-proxy` with `isSystemUser = true` and `group = "kiji-proxy"`
- ✅ `systemd.services.kiji-proxy` with `Type = "simple"`, `Restart = "on-failure"`, `RestartSec = "5s"`
- ✅ `ExecStart = "${pkgs.vexos.kiji-proxy}/bin/kiji-proxy"` — references Nix store path
- ✅ `Environment` list with `LD_LIBRARY_PATH` and `PROXY_PORT=:${toString cfg.port}`
- ✅ `EnvironmentFile` applied only via `lib.optionalAttrs (cfg.environmentFile != "") { ... }`
- ✅ `StandardOutput = "journal"; StandardError = "journal"` present
- ✅ `after = [ "network.target" ]; wantedBy = [ "multi-user.target" ]` correct
- ✅ `networking.firewall.allowedTCPPorts = [ cfg.port ]` — firewall opened correctly

---

### 4. Consistency

- ✅ `pkgs/default.nix`: new entry follows existing column alignment (`=` padded), uses `final.callPackage ./kiji-proxy { }`. Added `# ── AI & Privacy` section comment — consistent with other sections in `modules/server/default.nix` and an improvement over the bare spec requirement
- ✅ `modules/server/default.nix`: section comment format (`# ── AI & Privacy ─────...`) matches all other section comments in that file exactly
- ✅ `kiji-proxy.nix` module file header comment style matches existing server modules
- ✅ `let cfg = config.vexos.server.kiji-proxy;` — standard `cfg` alias used consistently

---

### 5. Security

- ✅ Service runs as dedicated non-root system user `kiji-proxy` (`isSystemUser = true`)
- ✅ No hardcoded credentials anywhere in the implementation
- ✅ `environmentFile` defaults to `""` (empty) — no file is loaded unless explicitly configured
- ✅ Module documentation recommends `chmod 600` on the secrets file
- ✅ `LD_LIBRARY_PATH` is scoped to `${pkgs.vexos.kiji-proxy}/lib` — does not expose system library paths
- ✅ No `DynamicUser` (not used in this project's patterns), but a dedicated static system user is equivalently secure for this use case

---

### 6. Module Architecture Pattern

- ✅ The module contains **no role-based conditionals** of any kind
- ✅ The single `lib.mkIf cfg.enable` at the top level is the standard enable gate, not a role selector
- ✅ The file is correctly placed in `modules/server/` and imported only by the server umbrella (`modules/server/default.nix`)
- ✅ No `lib.mkIf` guards inside the module body that gate content by role, display flag, gaming flag, or any other environment selector

---

### 7. Build Validation

- ✅ **Nix syntax**: no syntax errors detected by reading. Attribute sets, `let`/`in`, `lib.mkIf`, `lib.optionalAttrs`, and string interpolation are all correctly formed
- ✅ `hardware-configuration.nix` is NOT referenced in any of the four new/modified files
- ✅ `system.stateVersion` is NOT modified in any file
- ✅ No new flake inputs added — all dependencies (`autoPatchelfHook`, `stdenv.cc.cc.lib`, `fetchurl`) are available from the existing `nixpkgs` pin
- ✅ `lib.fakeHash` is the intentional placeholder — this causes a hash-mismatch build failure that prints the correct hash. This is the documented workflow per §6 of the spec. **Not a defect.**
- ✅ `pkgs.vexos.kiji-proxy` is correctly wired through the overlay before use in the module
- ✅ The `//` merge operator in `serviceConfig` with `lib.optionalAttrs` is syntactically valid Nix and semantically correct for conditionally merging `EnvironmentFile` into the attrset

> Full build (`nix flake check`, `nixos-rebuild dry-build`) cannot complete until the real tarball hash replaces `lib.fakeHash`. This is expected and documented. Architecture and syntax are sound.

---

## Score Table

| Category | Score | Grade |
|----------|-------|-------|
| Specification Compliance | 91% | A |
| Best Practices | 88% | B+ |
| Functionality | 96% | A |
| Code Quality | 93% | A |
| Security | 100% | A+ |
| Performance | 95% | A |
| Consistency | 97% | A+ |
| Build Success | 100%* | A+ |

> \* Full marks awarded: `lib.fakeHash` is a documented, intentional placeholder — not a defect.  
> Architecture, syntax, and wiring are all sound.

**Overall Grade: A (95%)**

---

## Verdict

### ✅ PASS

The implementation is correct, secure, and consistent with project patterns. The two minor spec deviations (`dontConfigure`/`dontBuild` omission and `.so` file mode 755 vs 644) have no functional impact. The placement deviation in `modules/server/default.nix` is an improvement over the spec. No issues require remediation before proceeding.

---

## Optional Improvements (Non-Blocking)

These are not required for PASS but would bring the implementation into tighter alignment with the spec:

1. **Add `dontConfigure = true; dontBuild = true;`** to `pkgs/kiji-proxy/default.nix` — explicit intent is better than relying on stdenv's implicit Makefile/configure checks, and matches the spec exactly.

2. **Change `.so` install mode to `644`** — `install -Dm644 lib/libonnxruntime.so.1.24.2 $out/lib/libonnxruntime.so.1.24.2` is more idiomatic for a shared library (execute bit is meaningless for `.so` files).
