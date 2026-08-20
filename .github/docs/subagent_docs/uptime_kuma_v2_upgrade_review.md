# Uptime Kuma v2 Upgrade — Review & Quality Assurance

**Feature name:** `uptime_kuma_v2_upgrade`
**Date:** 2026-08-20
**Phase:** 3 — Review & Quality Assurance
**Spec:** `.github/docs/subagent_docs/uptime_kuma_v2_upgrade_spec.md`

---

## 1. Files Reviewed

| File | Change |
|---|---|
| `modules/server/uptime-kuma.nix` | Image pin `1.23.17` → `2.5.0` (1 line) |
| `.github/workflows/update-container-images-weekly-wednesday.yml` | Tag regex `^1\.` → major-agnostic (1 line) |

Total diff: **2 files, 2 insertions, 2 deletions.**

---

## 2. Specification Compliance

| Spec requirement | Status |
|---|---|
| §4.1 Bump pin to 2.5.0 | ✅ `image = "louislam/uptime-kuma:2.5.0";` |
| §4.2 Widen regex to `^[0-9]+\.[0-9]+\.[0-9]+$` | ✅ Applied verbatim |
| §4.3 No change to `ports` / `volumes` / options | ✅ Untouched |
| §4.3 No new env vars | ✅ None added |
| §4.3 No change to backup/proxy/default/justfile | ✅ Untouched |
| §4.3 Database major locks preserved | ✅ `postgres ^16\.` and `mariadb ^11\.4\.` unchanged |

**Verdict: full compliance, no deviation.**

---

## 3. Build & Functional Validation

Nix tooling is unavailable in the Windows working directory, but **WSL2 Ubuntu with Nix
2.34.1 is present**, and a `/etc/nixos/hardware-configuration.nix` fixture already existed
there. All validation below was therefore **actually executed**, not skipped.

### 3.1 Full closure evaluation (CI-equivalent)

Using the exact command CI runs
(`nix eval --impure ".#nixosConfigurations.<c>.config.system.build.toplevel.drvPath"`,
which forces full evaluation including all NixOS assertions without building):

| Config | Result |
|---|---|
| `vexos-server-amd` | ✅ PASS |
| `vexos-headless-server-amd` | ✅ PASS |
| `vexos-desktop-amd` | ✅ PASS |

`OVERALL_EXIT=0`. Server variants were required because this change touches a
`modules/server/` module.

**Note:** `nix flake check` was **not** used — it is a FORBIDDEN COMMAND per CLAUDE.md.
Per-target `nix eval` was used instead, as the project mandates.

### 3.2 Workflow logic validation

The automation's own resolution logic was replayed locally against the live Docker Hub API
with the new regex:

```
current=2.5.0
latest=2.5.0
RESULT: already at latest -> no bump (correct)
```

The `IFS=':'` four-field split was verified against the modified entry:

```
file=[modules/server/uptime-kuma.nix]
repo=[louislam/uptime-kuma]
registry=[dockerhub]
pattern=[^[0-9]+\.[0-9]+\.[0-9]+$]
```

The trailing `\$` inside the double-quoted array element correctly yields a literal `$`
anchor, so `-rootless` / `-slim` / `-slim-rootless` variants are properly excluded.

YAML syntax validated: **`YAML OK`** (`yaml.safe_load`).

### 3.3 Repo hygiene

| Check | Result |
|---|---|
| `git ls-files hardware-configuration.nix` | ✅ empty (not tracked) |
| `system.stateVersion` unchanged | ✅ all 6 files still `25.11`, zero diff |
| New flake inputs requiring `follows` | ✅ none introduced |
| Lingering `uptime-kuma:1` references | ✅ only in historical spec docs (correct) |

### 3.4 Preflight (executed early, full result recorded in Phase 6)

`bash scripts/preflight.sh` in WSL: **`Preflight PASSED — safe to push.` EXIT_CODE=0**

---

## 4. Quality Assessment

**Best practices.** Both changes are single-token edits consistent with surrounding code.
The image pin retains the explicit-version form the file's design depends on; no drift to
`:latest` or a floating major, which matters doubly now that upstream removed `latest` in v2.

**Consistency.** The widened regex now matches the convention used by all 11 other
application images. The change *reduces* special-casing rather than adding it.

**Module Architecture Pattern (Option B).** Not implicated — no new `lib.mkIf` guards, no
new module files, no role-conditional logic. The existing `lib.mkIf cfg.enable` is the
sanctioned carve-out (module gating on an option it declares itself).

**Surgical changes.** Every changed line traces directly to the request. No adjacent
refactoring, no formatting churn, no comment rewrites.

**Security.** No secrets, no credentials, no permission changes. `openFirewall` semantics
unchanged. Moving off a 1.x line that no longer receives upstream security fixes is a net
security improvement.

**Performance.** No evaluation-time cost change; the diff is two string literals.

---

## 5. Findings

### CRITICAL
None.

### RECOMMENDED
None blocking.

### INFORMATIONAL (no action taken — outside task scope)

1. **`modules/server/backup.nix:69` backup path appears incorrect.** It maps
   `uptime-kuma = [ "/var/lib/uptime-kuma" ]`, but the container writes to the Docker
   *named volume* `uptime-kuma-data` (`/var/lib/docker/volumes/uptime-kuma-data/_data`).
   This path likely backs up nothing. **Pre-existing**, unrelated to this change, and left
   untouched per the Surgical Changes rule. Recommended as separate follow-up work.

2. **Widened regex will auto-cross future majors (e.g. 3.x) unattended.** This is a
   deliberate, accepted trade-off (spec §9 risk 2) and matches how every other application
   image is already handled. If tighter control is wanted later, the durable fix is a
   policy decision across all 12 application images, not a one-off re-narrowing here.

3. **Pre-existing preflight WARN** at `modules/server/vexboard.nix:90`
   (`secret = "change-me-set-vexos.server.vexboard.secretFile"`). Unrelated placeholder;
   not introduced by this change.

---

## 6. Score Table

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

---

## 7. Verdict

**PASS** — no refinement required. Phases 4 and 5 are skipped. Proceed to Phase 6.

Root cause is fully addressed on both axes: the stale pin is corrected *and* the mechanism
that would have re-frozen it is repaired. Without the regex fix, a future run could have
reverted progress; without the pin bump, the fix would not take effect until the next
Wednesday run.
