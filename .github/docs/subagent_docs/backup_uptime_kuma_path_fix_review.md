# backup.nix Uptime Kuma Path Fix — Review & Quality Assurance

**Feature name:** `backup_uptime_kuma_path_fix`
**Date:** 2026-08-20
**Phase:** 3 — Review & Quality Assurance
**Spec:** `.github/docs/subagent_docs/backup_uptime_kuma_path_fix_spec.md`

---

## 1. Files Reviewed

| File | Change |
|---|---|
| `modules/server/backup.nix` | `uptime-kuma` entry (line 69) replaced with a backend-conditional named-volume path |

Diff:

```diff
-    uptime-kuma      = [ "/var/lib/uptime-kuma" ];
+    uptime-kuma      = [ (if config.virtualisation.oci-containers.backend == "podman"
+                          then "/var/lib/containers/storage/volumes/uptime-kuma-data/_data"
+                          else "/var/lib/docker/volumes/uptime-kuma-data/_data") ]; # named Docker/Podman volume, not a /var/lib bind mount
```

---

## 2. Specification Compliance

| Spec requirement | Status |
|---|---|
| §3 Backend-conditional path replacing static guess | ✅ |
| §3 Reuses existing `cfg.backend == "docker"` conditional idiom | ✅ matches arcane/dockhand/portainer style |
| §3 Uses `config.virtualisation.oci-containers.backend` (already in scope) | ✅ no new module argument added |
| §3.1 Scope limited to the `uptime-kuma` line only | ✅ `homepage`/`portainer` entries left untouched, flagged separately |
| §3.1 `modules/server/uptime-kuma.nix` untouched | ✅ |

**Verdict: full compliance.**

---

## 3. Functional Validation

### 3.1 Direct evaluation of the derived value (both backend branches)

Using `nixosConfigurations.vexos-server-amd.extendModules` to force
`vexos.server.backup.enable`, `vexos.server.uptime-kuma.enable`, and
`virtualisation.oci-containers.backend` for each branch, then reading
`config.services.restic.backups.main.paths`:

| Forced backend | Resulting path | Correct? |
|---|---|---|
| `docker` | `/var/lib/docker/volumes/uptime-kuma-data/_data` | ✅ matches Docker's named-volume root |
| `podman` | `/var/lib/containers/storage/volumes/uptime-kuma-data/_data` | ✅ matches Podman's named-volume root |

This directly exercises the exact code path added, independent of whether any committed
host currently enables both `backup` and `uptime-kuma` (none do today — confirmed via
grep of `hosts/`, `template/`, `configuration-*.nix`).

### 3.2 Full closure evaluation (CI-equivalent)

`nix eval --impure ".#nixosConfigurations.<c>.config.system.build.toplevel.drvPath"`
(forces all NixOS assertions, no build):

| Config | Result |
|---|---|
| `vexos-server-amd` | ✅ PASS |
| `vexos-headless-server-amd` | ✅ PASS |

Required because this change touches a server module. `nix flake check` was not used
(FORBIDDEN COMMAND).

### 3.3 Preflight

`bash scripts/preflight.sh` in WSL2 (Nix 2.34.1): **`Preflight PASSED — safe to push.`
EXIT_CODE=0**

### 3.4 Repo hygiene

| Check | Result |
|---|---|
| `git ls-files hardware-configuration.nix` | ✅ empty |
| `system.stateVersion` unchanged | ✅ no diff |
| New flake inputs | ✅ none |

---

## 4. Quality Assessment

**Correctness.** The old value backed up a path the Uptime Kuma container never writes
to (`/var/lib/uptime-kuma`); restic would have archived nothing for this service on any
host with both flags enabled, with no error surfaced. The new value resolves to the
container's actual named-volume mountpoint and was confirmed correct for both possible
backends.

**Consistency.** The `if backend == "docker" then ... else ...` shape mirrors the existing
convention in `arcane.nix:112-114`, `dockhand.nix:96-98`, and `portainer.nix:60-62` — no
new idiom introduced.

**Surgical scope.** Single table entry changed. No edits to `uptime-kuma.nix`, no changes
to unrelated `servicePaths` entries, no formatting churn elsewhere in the file. The
pre-existing analogous issue in `homepage`/`portainer` entries was investigated and
explicitly left alone per the user's scoped request, and is recorded as a follow-up
candidate rather than silently fixed or silently ignored.

**Module Architecture Pattern.** Not implicated — `backup.nix` is not a per-role file;
this is a data-table correction, not new conditional role logic.

**Security.** No secrets, no permission changes.

---

## 5. Findings

### CRITICAL
None.

### RECOMMENDED
None blocking.

### INFORMATIONAL (not fixed — outside this task's explicit scope)

1. **`servicePaths.homepage` (`/var/lib/homepage`) and `servicePaths.portainer`
   (`/var/lib/portainer`) have the identical class of bug** — both containers write to
   named Docker volumes (`homepage-config:/app/config`, `portainer-data:/data`), not
   `/var/lib/<name>` bind mounts. Same fix shape would apply. Left untouched because the
   user's request was scoped to the uptime-kuma line specifically.

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

**PASS** — no refinement required. Phases 4 and 5 skipped. Proceed to Phase 6.
